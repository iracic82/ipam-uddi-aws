###############################################################################
# AWS + Azure IPAM Lab - Variables
###############################################################################

###############################################################################
# AWS Configuration
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
# Azure Configuration
###############################################################################
variable "subscription" {
  description = "Azure Subscription ID"
  type        = string
  default     = ""
}

variable "client" {
  description = "Azure Service Principal Client ID"
  type        = string
  default     = ""
}

variable "clientsecret" {
  description = "Azure Service Principal Client Secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tenantazure" {
  description = "Azure Tenant ID"
  type        = string
  default     = ""
}

variable "azure_location" {
  description = "Azure region"
  type        = string
  default     = "North Europe"
}

variable "azure_vm_size" {
  description = "Azure VM size"
  type        = string
  default     = "Standard_DS2_v2"
}

###############################################################################
# AWS VPCs Configuration - Map for multiple VPCs
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
# Azure VNets Configuration - With OVERLAPPING IP ranges for demo
###############################################################################
variable "vnets" {
  description = "Map of Azure VNets to create (includes intentional overlap with AWS)"
  type = map(object({
    resource_group_name = string
    location            = string
    vnet_name           = string
    vnet_cidr           = string
    subnet_name         = string
    subnet_cidr         = string
    private_ip          = string
    vm_name             = string
    enable_internet     = bool
    create_vm           = bool
  }))
  default = {
    # This VNet uses the SAME CIDR as AWS Production - intentional overlap!
    "legacy-onprem" = {
      resource_group_name = "ipam-lab-legacy-rg"
      location            = "North Europe"
      vnet_name           = "Legacy-OnPrem-VNet"
      vnet_cidr           = "10.100.50.0/24"
      subnet_name         = "Legacy-Subnet"
      subnet_cidr         = "10.100.50.0/26"
      private_ip          = "10.100.50.10"
      vm_name             = "legacy-server"
      enable_internet     = true
      create_vm           = true
    }
    # DataCenter EU simulation
    "datacenter-eu" = {
      resource_group_name = "ipam-lab-dc-eu-rg"
      location            = "North Europe"
      vnet_name           = "DataCenter-EU-VNet"
      vnet_cidr           = "10.20.0.0/16"
      subnet_name         = "DC-EU-Subnet"
      subnet_cidr         = "10.20.1.0/24"
      private_ip          = "10.20.1.10"
      vm_name             = "dc-eu-server"
      enable_internet     = true
      create_vm           = true
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

###############################################################################
# Instruqt Variables
###############################################################################
variable "instruqt_id" {
  description = "Instruqt participant ID"
  type        = string
  default     = ""
}
