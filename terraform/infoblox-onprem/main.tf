###############################################################################
# Infoblox On-Prem IP Spaces - Non-overlapping datacenter networks
###############################################################################
# Creates on-prem IP spaces in Infoblox within the 192.168.0.0/16 range
# matching the On-Prem federated block from config.yaml
###############################################################################

terraform {
  required_providers {
    bloxone = {
      source  = "infobloxopen/bloxone"
      version = ">= 1.5.0"
    }
  }
}

provider "bloxone" {
  csp_url = "https://csp.infoblox.com"
  api_key = var.ddi_api_key
}

###############################################################################
# Variables
###############################################################################
variable "ddi_api_key" {
  description = "Infoblox CSP API key (from deploy_api_key.py)"
  type        = string
  sensitive   = true
}

variable "realm_id" {
  description = "Federated realm ID from federation_output.json"
  type        = string
}

###############################################################################
# On-Prem IP Space
###############################################################################
resource "bloxone_ipam_ip_space" "onprem" {
  name    = "On-Premises-DataCenter"
  comment = "On-premises datacenter IP space"

  default_realms = [var.realm_id]

  tags = {
    environment = "on-prem"
    location    = "datacenter"
    managed_by  = "terraform"
  }
}

###############################################################################
# On-Prem Address Blocks - Within 192.168.0.0/16 range
###############################################################################

# Server Network
resource "bloxone_ipam_address_block" "onprem_servers" {
  address = "192.168.1.0"
  cidr    = 24
  name    = "Server-Network"
  space   = bloxone_ipam_ip_space.onprem.id
  comment = "On-prem server network"

  federated_realms = [var.realm_id]

  tags = {
    environment = "on-prem"
    network     = "servers"
  }
}

# Workstation Network
resource "bloxone_ipam_address_block" "onprem_workstations" {
  address = "192.168.10.0"
  cidr    = 24
  name    = "Workstation-Network"
  space   = bloxone_ipam_ip_space.onprem.id
  comment = "On-prem workstation network"

  federated_realms = [var.realm_id]

  tags = {
    environment = "on-prem"
    network     = "workstations"
  }
}

# Management Network
resource "bloxone_ipam_address_block" "onprem_mgmt" {
  address = "192.168.100.0"
  cidr    = 24
  name    = "Management-Network"
  space   = bloxone_ipam_ip_space.onprem.id
  comment = "On-prem management network"

  federated_realms = [var.realm_id]

  tags = {
    environment = "on-prem"
    network     = "management"
  }
}

###############################################################################
# On-Prem Subnets - Must be created AFTER address blocks
###############################################################################
resource "bloxone_ipam_subnet" "onprem_servers_subnet" {
  depends_on = [bloxone_ipam_address_block.onprem_servers]

  address = "192.168.1.0"
  cidr    = 26
  space   = bloxone_ipam_ip_space.onprem.id
  name    = "Servers-Subnet-1"

  tags = {
    subnet_type = "server"
    vlan        = "101"
  }
}

resource "bloxone_ipam_subnet" "onprem_workstations_subnet" {
  depends_on = [bloxone_ipam_address_block.onprem_workstations]

  address = "192.168.10.0"
  cidr    = 26
  space   = bloxone_ipam_ip_space.onprem.id
  name    = "Workstations-Subnet-1"

  tags = {
    subnet_type = "workstation"
    vlan        = "110"
  }
}

###############################################################################
# Outputs
###############################################################################
output "ip_space_id" {
  description = "On-prem IP space ID"
  value       = bloxone_ipam_ip_space.onprem.id
}

output "address_blocks" {
  description = "On-prem address blocks"
  value = {
    servers = {
      id   = bloxone_ipam_address_block.onprem_servers.id
      cidr = "192.168.1.0/24"
    }
    workstations = {
      id   = bloxone_ipam_address_block.onprem_workstations.id
      cidr = "192.168.10.0/24"
    }
    management = {
      id   = bloxone_ipam_address_block.onprem_mgmt.id
      cidr = "192.168.100.0/24"
    }
  }
}
