###############################################################################
# AWS IAM Role for Infoblox Discovery
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "external_id" {
  description = "External ID from Infoblox (account UUID from get_infoblox_identity.py)"
  type        = string
  default     = ""
}

variable "identity_file" {
  description = "Path to identity_output.json from get_infoblox_identity.py"
  type        = string
  default     = "../../scripts/identity_output.json"
}

variable "role_name" {
  description = "Name of the IAM role"
  type        = string
  default     = "InfobloxDiscoveryRole"
}

locals {
  infoblox_aws_account_id = "418668170506"
  # Read from file if external_id not provided
  identity_data = var.external_id != "" ? null : jsondecode(file(var.identity_file))
  external_id   = var.external_id != "" ? var.external_id : local.identity_data.external_id
}

###############################################################################
# IAM Role
###############################################################################
resource "aws_iam_role" "infoblox_discovery" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.infoblox_aws_account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = local.external_id
          }
        }
      }
    ]
  })

  tags = {
    Name      = var.role_name
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.infoblox_discovery.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

###############################################################################
# Outputs
###############################################################################
output "role_arn" {
  value = aws_iam_role.infoblox_discovery.arn
}

resource "local_file" "role_arn" {
  content  = aws_iam_role.infoblox_discovery.arn
  filename = "${path.module}/../infoblox_role_arn.txt"
}
