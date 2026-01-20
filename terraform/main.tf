###############################################################################
# AWS IPAM + Infoblox Integration - Main Configuration
###############################################################################
# This Terraform configuration creates:
# 1. AWS IPAM with Advanced tier (required for external authority)
# 2. Custom private scope with Infoblox as external authority
# 3. Top-level pool for CIDR provisioning from Infoblox
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

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

###############################################################################
# AWS IPAM - Advanced Tier
###############################################################################
resource "aws_vpc_ipam" "main" {
  description = var.ipam_description
  tier        = "advanced" # Required for external authority integration

  operating_regions {
    region_name = var.aws_region
  }

  # Add additional operating regions if specified
  dynamic "operating_regions" {
    for_each = [for r in var.operating_regions : r if r != var.aws_region]
    content {
      region_name = operating_regions.value
    }
  }

  tags = merge(var.tags, {
    Name = var.ipam_name
  })
}

###############################################################################
# Custom Private Scope - Infoblox External Authority
###############################################################################
resource "aws_vpc_ipam_scope" "infoblox" {
  ipam_id     = aws_vpc_ipam.main.id
  description = var.scope_description

  tags = merge(var.tags, {
    Name = var.scope_name
  })
}

###############################################################################
# Configure Infoblox as External Authority
# Note: This uses a null_resource with local-exec because Terraform AWS
# provider doesn't yet support external_authority_configuration natively
###############################################################################
resource "null_resource" "configure_infoblox_authority" {
  depends_on = [aws_vpc_ipam_scope.infoblox]

  triggers = {
    scope_id                     = aws_vpc_ipam_scope.infoblox.id
    infoblox_resource_identifier = var.infoblox_resource_identifier
    aws_profile                  = var.aws_profile
    aws_region                   = var.aws_region
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws ec2 modify-ipam-scope \
        --profile ${var.aws_profile} \
        --region ${var.aws_region} \
        --ipam-scope-id ${aws_vpc_ipam_scope.infoblox.id} \
        --external-authority-configuration Type=infoblox,ExternalResourceIdentifier=${var.infoblox_resource_identifier}
    EOT
  }

  # Remove external authority on destroy
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      aws ec2 modify-ipam-scope \
        --profile ${self.triggers.aws_profile} \
        --region ${self.triggers.aws_region} \
        --ipam-scope-id ${self.triggers.scope_id} \
        --remove-external-authority-configuration 2>/dev/null || true
    EOT
  }
}

###############################################################################
# Top-Level Pool in Infoblox-Managed Scope
# Note: Pool starts empty - CIDRs are provisioned from Infoblox
###############################################################################
resource "aws_vpc_ipam_pool" "infoblox_managed" {
  depends_on = [null_resource.configure_infoblox_authority]

  ipam_scope_id  = aws_vpc_ipam_scope.infoblox.id
  address_family = "ipv4"
  description    = "Pool managed by Infoblox - CIDR sourced from Infoblox UDDI"
  locale         = var.aws_region

  tags = merge(var.tags, {
    Name   = "infoblox-managed-pool"
    Source = "infoblox-uddi"
  })
}

###############################################################################
# Data source for account ID (useful for IAM role setup)
###############################################################################
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
