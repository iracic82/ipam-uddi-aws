###############################################################################
# AWS IPAM + Infoblox Integration - Outputs
###############################################################################

output "ipam_id" {
  description = "The ID of the AWS IPAM"
  value       = local.ipam_id
}

output "ipam_arn" {
  description = "The ARN of the AWS IPAM"
  value       = local.create_ipam ? aws_vpc_ipam.main[0].arn : "existing-ipam"
}

output "ipam_region" {
  description = "The home region of the AWS IPAM"
  value       = var.aws_region
}

output "infoblox_scope_id" {
  description = "The ID of the Infoblox-managed scope"
  value       = aws_vpc_ipam_scope.infoblox.id
}

output "infoblox_scope_arn" {
  description = "The ARN of the Infoblox-managed scope"
  value       = aws_vpc_ipam_scope.infoblox.arn
}

output "production_pool_id" {
  description = "The ID of the Production pool"
  value       = aws_vpc_ipam_pool.production.id
}

output "production_pool_arn" {
  description = "The ARN of the Production pool"
  value       = aws_vpc_ipam_pool.production.arn
}

output "development_pool_id" {
  description = "The ID of the Development pool"
  value       = aws_vpc_ipam_pool.development.id
}

output "development_pool_arn" {
  description = "The ARN of the Development pool"
  value       = aws_vpc_ipam_pool.development.arn
}

output "aws_account_id" {
  description = "The AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "infoblox_resource_identifier" {
  description = "The Infoblox resource identifier used for external authority"
  value       = local.infoblox_resource_identifier
}

###############################################################################
# VPC Outputs
###############################################################################
output "vpcs" {
  description = "Map of VPC outputs"
  value = {
    for k, v in module.vpc : k => {
      vpc_id    = v.vpc_id
      vpc_cidr  = v.vpc_cidr
      subnet_id = v.subnet_id
      public_ip = v.public_ip
    }
  }
}

###############################################################################
# Summary Output for Quick Reference
###############################################################################
output "summary" {
  description = "Summary of created resources"
  value = {
    ipam = {
      id     = local.ipam_id
      region = var.aws_region
      tier   = "advanced"
    }
    scope = {
      id                 = aws_vpc_ipam_scope.infoblox.id
      external_authority = local.infoblox_resource_identifier != "" ? "infoblox" : "none"
      resource_id        = local.infoblox_resource_identifier
    }
    pools = {
      production = {
        id     = aws_vpc_ipam_pool.production.id
        cidr   = "10.100.0.0/16"
        locale = var.aws_region
      }
      development = {
        id     = aws_vpc_ipam_pool.development.id
        cidr   = "10.200.0.0/16"
        locale = var.aws_region
      }
      note = "CIDRs provisioned from Infoblox"
    }
    vpcs = keys(module.vpc)
  }
}
