#######################################
# Azure VNet Module
# Creates: VNet, Subnet, RT, NSG, VM
#######################################

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(var.tags, {
    Name = var.vnet_name
  })
}

# Subnet
resource "azurerm_subnet" "main" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_cidr]
}

# Route Table
resource "azurerm_route_table" "main" {
  name                = "${var.vnet_name}-rt"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(var.tags, {
    Name = "${var.vnet_name}-rt"
  })
}

# Route Table Association
resource "azurerm_subnet_route_table_association" "main" {
  subnet_id      = azurerm_subnet.main.id
  route_table_id = azurerm_route_table.main.id
}

# Network Security Group
resource "azurerm_network_security_group" "main" {
  name                = "${var.vnet_name}-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Flask"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "iPerf"
    priority                   = 1005
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "5201"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "ICMP"
    priority                   = 1006
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
    destination_address_prefix = "*"
  }

  tags = merge(var.tags, {
    Name = "${var.vnet_name}-nsg"
  })
}

# Public IP (if internet enabled)
resource "azurerm_public_ip" "main" {
  count               = var.enable_internet && var.create_vm ? 1 : 0
  name                = "${var.vm_name}-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = merge(var.tags, {
    Name = "${var.vm_name}-pip"
  })
}

# Network Interface
resource "azurerm_network_interface" "main" {
  count               = var.create_vm ? 1 : 0
  name                = "${var.vm_name}-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.private_ip
    public_ip_address_id          = var.enable_internet ? azurerm_public_ip.main[0].id : null
  }

  tags = merge(var.tags, {
    Name = "${var.vm_name}-nic"
  })
}

# NSG Association to NIC
resource "azurerm_network_interface_security_group_association" "main" {
  count                     = var.create_vm ? 1 : 0
  network_interface_id      = azurerm_network_interface.main[0].id
  network_security_group_id = azurerm_network_security_group.main.id
}

# SSH Key Pair
resource "tls_private_key" "ssh_key" {
  count     = var.create_vm ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save private key locally
resource "local_sensitive_file" "private_key" {
  count           = var.create_vm ? 1 : 0
  content         = tls_private_key.ssh_key[0].private_key_pem
  filename        = "${path.root}/${var.vm_name}-azure.pem"
  file_permission = "0400"
}

# Virtual Machine
resource "azurerm_linux_virtual_machine" "main" {
  count               = var.create_vm ? 1 : 0
  name                = var.vm_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.main[0].id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh_key[0].public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  custom_data = var.user_data != "" ? base64encode(var.user_data) : null

  tags = merge(var.tags, {
    Name = var.vm_name
  })
}
