###############################################################################
# AWS IPAM Lab - Main Configuration
###############################################################################
# This creates:
# 1. Base VPC infrastructure using module (VPC, Subnet, EC2, SG)
# 2. AWS IPAM with Advanced tier (optional - for Infoblox integration)
###############################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Provider uses environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
provider "aws" {
  region = var.aws_region
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

  user_data = file("${path.module}/../scripts/aws-user-data.sh")
}

###############################################################################
# Base VPC Infrastructure - Using Module
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
  user_data       = local.user_data

  tags = merge(local.common_tags, {
    VPC = each.key
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
  count = var.infoblox_resource_identifier != "" ? 1 : 0

  depends_on = [aws_vpc_ipam_scope.infoblox]

  triggers = {
    scope_id                     = aws_vpc_ipam_scope.infoblox.id
    infoblox_resource_identifier = var.infoblox_resource_identifier
    aws_region                   = var.aws_region
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws ec2 modify-ipam-scope \
        --region ${var.aws_region} \
        --ipam-scope-id ${aws_vpc_ipam_scope.infoblox.id} \
        --external-authority-configuration Type=infoblox,ExternalResourceIdentifier=${var.infoblox_resource_identifier}
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
