###############################################################################
# AWS IPAM Lab - Variables
###############################################################################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

###############################################################################
# VPCs Configuration - Map for multiple VPCs
###############################################################################
variable "vpcs" {
  description = "Map of VPCs to create"
  type = map(object({
    vpc_name        = string
    vpc_cidr        = string
    subnet_name     = string
    subnet_cidr     = string
    private_ip      = string
    ec2_name        = string
    enable_internet = bool
    create_ec2      = bool
  }))
  default = {
    "production" = {
      vpc_name        = "Production-VPC"
      vpc_cidr        = "10.100.0.0/16"
      subnet_name     = "Production-Subnet"
      subnet_cidr     = "10.100.1.0/24"
      private_ip      = "10.100.1.10"
      ec2_name        = "prod-server"
      enable_internet = true
      create_ec2      = true
    }
    "development" = {
      vpc_name        = "Development-VPC"
      vpc_cidr        = "10.200.0.0/16"
      subnet_name     = "Development-Subnet"
      subnet_cidr     = "10.200.1.0/24"
      private_ip      = "10.200.1.10"
      ec2_name        = "dev-server"
      enable_internet = true
      create_ec2      = true
    }
  }
}

###############################################################################
# IPAM Configuration
###############################################################################
variable "infoblox_resource_identifier" {
  description = "Infoblox resource identifier for external authority (blox_id). If empty, reads from identity_file."
  type        = string
  default     = ""
}

variable "identity_file" {
  description = "Path to identity_output.json from get_infoblox_identity.py"
  type        = string
  default     = "../scripts/identity_output.json"
}
