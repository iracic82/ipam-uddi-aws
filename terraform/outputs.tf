###############################################################################
# AWS IPAM + Infoblox Integration - Outputs
###############################################################################

output "ipam_id" {
  description = "The ID of the AWS IPAM"
  value       = aws_vpc_ipam.main.id
}

output "ipam_arn" {
  description = "The ARN of the AWS IPAM"
  value       = aws_vpc_ipam.main.arn
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

output "infoblox_pool_id" {
  description = "The ID of the Infoblox-managed pool"
  value       = aws_vpc_ipam_pool.infoblox_managed.id
}

output "infoblox_pool_arn" {
  description = "The ARN of the Infoblox-managed pool"
  value       = aws_vpc_ipam_pool.infoblox_managed.arn
}

output "aws_account_id" {
  description = "The AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "infoblox_resource_identifier" {
  description = "The Infoblox resource identifier used for external authority"
  value       = var.infoblox_resource_identifier
}

###############################################################################
# Summary Output for Quick Reference
###############################################################################
output "summary" {
  description = "Summary of created resources"
  value = {
    ipam = {
      id     = aws_vpc_ipam.main.id
      region = var.aws_region
      tier   = "advanced"
    }
    scope = {
      id                = aws_vpc_ipam_scope.infoblox.id
      external_authority = "infoblox"
      resource_id       = var.infoblox_resource_identifier
    }
    pool = {
      id     = aws_vpc_ipam_pool.infoblox_managed.id
      locale = var.aws_region
      note   = "CIDRs provisioned from Infoblox"
    }
  }
}
