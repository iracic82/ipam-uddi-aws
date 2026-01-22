###############################################################################
# AWS + Azure IPAM Lab - Main Configuration
###############################################################################
# This creates:
# 1. AWS VPC infrastructure using module (VPC, Subnet, EC2, SG)
# 2. Azure VNet infrastructure using module (VNet, Subnet, VM, NSG)
# 3. AWS IPAM with Advanced tier (for Infoblox integration)
# 4. Overlapping IP ranges between AWS and Azure for demo
###############################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

# AWS Provider - uses environment variables
provider "aws" {
  region = var.aws_region
}

# Azure Provider - North Europe with explicit credentials
provider "azurerm" {
  alias = "eun"
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.subscription
  client_id       = var.client
  client_secret   = var.clientsecret
  tenant_id       = var.tenantazure
}

###############################################################################
# Local values
###############################################################################
locals {
  common_tags = {
    Environment   = "Lab"
    Project       = "IPAM-UDDI"
    ManagedBy     = "Terraform"
    ResourceOwner = "lab-user"
  }

  aws_user_data   = file("${path.module}/../scripts/aws-user-data.sh")
  azure_user_data = file("${path.module}/../scripts/azure-user-data.sh")

  # Read blox_id from identity_output.json if not provided via variable
  identity_data = var.infoblox_resource_identifier != "" ? null : (
    fileexists(var.identity_file) ? jsondecode(file(var.identity_file)) : null
  )
  infoblox_resource_identifier = var.infoblox_resource_identifier != "" ? var.infoblox_resource_identifier : (
    local.identity_data != null ? local.identity_data.blox_id : ""
  )
}

###############################################################################
# AWS VPC Infrastructure - Using Module
###############################################################################
module "vpc" {
  source   = "./modules/aws-vpc"
  for_each = var.vpcs

  vpc_name        = each.value.vpc_name
  vpc_cidr        = each.value.vpc_cidr
  subnet_name     = each.value.subnet_name
  subnet_cidr     = each.value.subnet_cidr
  private_ip      = each.value.private_ip
  ec2_name        = each.value.ec2_name
  enable_internet = each.value.enable_internet
  create_ec2      = each.value.create_ec2
  instance_type   = var.instance_type
  user_data       = local.aws_user_data

  tags = merge(local.common_tags, {
    VPC   = each.key
    Cloud = "AWS"
  })
}

###############################################################################
# Azure VNet Infrastructure - Using Module (Overlapping IP for Demo)
###############################################################################
module "vnet" {
  source   = "./modules/azure-vnet"
  for_each = var.vnets

  providers = {
    azurerm = azurerm.eun
  }

  resource_group_name = each.value.resource_group_name
  location            = each.value.location
  vnet_name           = each.value.vnet_name
  vnet_cidr           = each.value.vnet_cidr
  subnet_name         = each.value.subnet_name
  subnet_cidr         = each.value.subnet_cidr
  private_ip          = each.value.private_ip
  vm_name             = each.value.vm_name
  enable_internet     = each.value.enable_internet
  create_vm           = each.value.create_vm
  vm_size             = var.azure_vm_size
  user_data           = local.azure_user_data

  tags = merge(local.common_tags, {
    VNet  = each.key
    Cloud = "Azure"
  })
}

###############################################################################
# AWS IPAM - Advanced Tier (Required for Infoblox Integration)
###############################################################################
resource "aws_vpc_ipam" "main" {
  description = "IPAM for Infoblox Integration"
  tier        = "advanced"

  operating_regions {
    region_name = var.aws_region
  }

  tags = merge(local.common_tags, {
    Name = "infoblox-ipam"
  })
}

# Custom Private Scope for Infoblox
resource "aws_vpc_ipam_scope" "infoblox" {
  ipam_id     = aws_vpc_ipam.main.id
  description = "Scope managed by Infoblox UDDI"

  tags = merge(local.common_tags, {
    Name = "infoblox-scope"
  })
}

# Configure Infoblox as External Authority (only if identifier provided)
resource "null_resource" "configure_infoblox_authority" {
  count = local.infoblox_resource_identifier != "" ? 1 : 0

  depends_on = [aws_vpc_ipam_scope.infoblox]

  triggers = {
    scope_id                     = aws_vpc_ipam_scope.infoblox.id
    infoblox_resource_identifier = local.infoblox_resource_identifier
    aws_region                   = var.aws_region
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws ec2 modify-ipam-scope \
        --region ${var.aws_region} \
        --ipam-scope-id ${aws_vpc_ipam_scope.infoblox.id} \
        --external-authority-configuration Type=infoblox,ExternalResourceIdentifier=${local.infoblox_resource_identifier}
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      aws ec2 modify-ipam-scope \
        --region ${self.triggers.aws_region} \
        --ipam-scope-id ${self.triggers.scope_id} \
        --remove-external-authority-configuration 2>/dev/null || true
    EOT
  }
}

# IPAM Pools in Infoblox-Managed Scope
# Production Pool - 10.100.0.0/16
resource "aws_vpc_ipam_pool" "production" {
  depends_on = [aws_vpc_ipam_scope.infoblox]

  ipam_scope_id  = aws_vpc_ipam_scope.infoblox.id
  address_family = "ipv4"
  description    = "Production Environment Pool - Infoblox UDDI"
  locale         = var.aws_region

  tags = merge(local.common_tags, {
    Name        = "production-pool"
    Environment = "production"
    Source      = "infoblox-uddi"
  })
}

# Development Pool - 10.200.0.0/16
resource "aws_vpc_ipam_pool" "development" {
  depends_on = [aws_vpc_ipam_scope.infoblox]

  ipam_scope_id  = aws_vpc_ipam_scope.infoblox.id
  address_family = "ipv4"
  description    = "Development Environment Pool - Infoblox UDDI"
  locale         = var.aws_region

  tags = merge(local.common_tags, {
    Name        = "development-pool"
    Environment = "development"
    Source      = "infoblox-uddi"
  })
}

###############################################################################
# Data sources
###############################################################################
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
