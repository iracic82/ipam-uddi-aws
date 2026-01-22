###############################################################################
# AWS + Azure IPAM Lab - Outputs
###############################################################################

###############################################################################
# AWS IPAM Outputs
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

output "production_pool_id" {
  description = "The ID of the Production pool"
  value       = aws_vpc_ipam_pool.production.id
}

output "development_pool_id" {
  description = "The ID of the Development pool"
  value       = aws_vpc_ipam_pool.development.id
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
# AWS VPC Outputs
###############################################################################
output "aws_vpcs" {
  description = "Map of AWS VPC outputs"
  value = {
    for k, v in module.vpc : k => {
      vpc_id     = v.vpc_id
      vpc_cidr   = v.vpc_cidr
      subnet_id  = v.subnet_id
      private_ip = v.private_ip
      public_ip  = v.public_ip
    }
  }
}

###############################################################################
# Azure VNet Outputs
###############################################################################
output "azure_vnets" {
  description = "Map of Azure VNet outputs"
  value = {
    for k, v in module.vnet : k => {
      resource_group = v.resource_group_name
      vnet_id        = v.vnet_id
      vnet_cidr      = v.vnet_cidr
      subnet_id      = v.subnet_id
      private_ip     = v.private_ip
      public_ip      = v.public_ip
    }
  }
}

###############################################################################
# SSH Access - AWS
###############################################################################
output "aws_ssh_access" {
  description = "SSH commands to access AWS EC2 instances"
  value = {
    for k, v in module.vpc : k => v.public_ip != null ? {
      instance    = "${k}-server"
      private_ip  = v.private_ip
      public_ip   = v.public_ip
      ssh_command = "ssh -i '${k}-server-aws.pem' ec2-user@${v.public_ip}"
    } : null
  }
}

###############################################################################
# SSH Access - Azure
###############################################################################
output "azure_ssh_access" {
  description = "SSH commands to access Azure VMs"
  value = {
    for k, v in module.vnet : k => v.public_ip != null ? {
      vm_name     = v.vnet_name
      private_ip  = v.private_ip
      public_ip   = v.public_ip
      ssh_command = v.ssh_command
    } : null
  }
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
    }
    aws_vpcs   = keys(module.vpc)
    azure_vnets = keys(module.vnet)
    overlap_demo = {
      note         = "Azure 'legacy-onprem' VNet (10.100.50.0/24) overlaps with AWS Production pool (10.100.0.0/16)"
      aws_cidr     = "10.100.0.0/16"
      azure_cidr   = "10.100.50.0/24"
      overlap_type = "Azure CIDR is a subset of AWS Production"
    }
  }
}

###############################################################################
# Quick SSH Reference
###############################################################################
output "ssh_quick_reference" {
  description = "Quick SSH reference for all instances"
  value = <<-EOT

  ==========================================
  SSH Access - Quick Reference
  ==========================================

  AWS Instances:
  ${join("\n  ", [for k, v in module.vpc : v.public_ip != null ? "  ${k}: ssh -i '${k}-server-aws.pem' ec2-user@${v.public_ip}" : "  ${k}: No public IP"])}

  Azure VMs:
  ${join("\n  ", [for k, v in module.vnet : v.public_ip != null ? "  ${k}: ssh -i '${v.vnet_name}-azure.pem' azureuser@${v.public_ip}" : "  ${k}: No public IP"])}

  ==========================================
  IP Overlap Demo
  ==========================================
  AWS Production Pool:     10.100.0.0/16
  Azure Legacy-OnPrem:     10.100.50.0/24  <-- OVERLAPS!

  This demonstrates how Infoblox Federated IPAM
  detects IP conflicts across hybrid environments.
  ==========================================

  EOT
}
