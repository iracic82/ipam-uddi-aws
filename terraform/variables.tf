###############################################################################
# AWS IPAM + Infoblox Integration - Variables
###############################################################################

variable "aws_region" {
  description = "AWS region for IPAM deployment"
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "okta-sso"
}

variable "ipam_name" {
  description = "Name tag for the IPAM"
  type        = string
  default     = "federated-ipam-lab"
}

variable "ipam_description" {
  description = "Description for the IPAM"
  type        = string
  default     = "Federated IPAM Lab - Infoblox Integration"
}

variable "infoblox_resource_identifier" {
  description = "Infoblox resource identifier for external authority (format: <version>.identity.account.<entity_realm>.<entity_id>)"
  type        = string
  # Example: blox0.identity.account.us-com-1.ivmfiurrgyyteiba
}

variable "scope_name" {
  description = "Name for the Infoblox-managed scope"
  type        = string
  default     = "infoblox-federated-scope"
}

variable "scope_description" {
  description = "Description for the Infoblox-managed scope"
  type        = string
  default     = "Infoblox Federated IPAM Scope"
}

variable "operating_regions" {
  description = "List of AWS regions where IPAM will operate"
  type        = list(string)
  default     = ["eu-west-1"]
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Purpose     = "infoblox-integration"
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}
