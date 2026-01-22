#######################################
# Azure VNet Module - Outputs
#######################################

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "vnet_id" {
  description = "ID of the VNet"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the VNet"
  value       = azurerm_virtual_network.main.name
}

output "vnet_cidr" {
  description = "CIDR block of the VNet"
  value       = tolist(azurerm_virtual_network.main.address_space)[0]
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = azurerm_subnet.main.id
}

output "route_table_id" {
  description = "ID of the route table"
  value       = azurerm_route_table.main.id
}

output "nsg_id" {
  description = "ID of the network security group"
  value       = azurerm_network_security_group.main.id
}

output "vm_id" {
  description = "ID of the VM"
  value       = var.create_vm ? azurerm_linux_virtual_machine.main[0].id : null
}

output "private_ip" {
  description = "Private IP of the VM"
  value       = var.create_vm ? azurerm_network_interface.main[0].private_ip_address : null
}

output "public_ip" {
  description = "Public IP of the VM"
  value       = var.enable_internet && var.create_vm ? azurerm_public_ip.main[0].ip_address : null
}

output "admin_username" {
  description = "Admin username for SSH"
  value       = var.admin_username
}

output "ssh_private_key_path" {
  description = "Path to the SSH private key"
  value       = var.create_vm ? "${path.root}/${var.vm_name}-azure.pem" : null
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = var.enable_internet && var.create_vm ? "ssh -i '${var.vm_name}-azure.pem' ${var.admin_username}@${azurerm_public_ip.main[0].ip_address}" : null
}
