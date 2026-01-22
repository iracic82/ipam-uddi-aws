#######################################
# Azure VNet Module - Variables
#######################################

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "North Europe"
}

variable "vnet_name" {
  description = "Name of the VNet"
  type        = string
}

variable "vnet_cidr" {
  description = "CIDR block for the VNet"
  type        = string
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
}

variable "enable_internet" {
  description = "Whether to create public IP"
  type        = bool
  default     = true
}

variable "create_vm" {
  description = "Whether to create VM"
  type        = bool
  default     = true
}

variable "vm_name" {
  description = "Name of the VM"
  type        = string
  default     = "demo-vm"
}

variable "vm_size" {
  description = "Azure VM size"
  type        = string
  default     = "Standard_DS1_v2"
}

variable "admin_username" {
  description = "Admin username for VM"
  type        = string
  default     = "azureuser"
}

variable "private_ip" {
  description = "Private IP for the VM"
  type        = string
}

variable "user_data" {
  description = "Custom data script for VM"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
