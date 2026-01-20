###############################################################################
# Infoblox On-Prem IP Spaces - Creates overlapping blocks for demo
###############################################################################
# This creates "on-prem" IP spaces in Infoblox that intentionally overlap
# with AWS ranges to demonstrate overlap detection in Federated IPAM
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
  comment = "Simulated on-premises data center IP space"

  default_realms = [var.realm_id]

  tags = {
    environment = "on-prem"
    location    = "datacenter-1"
    managed_by  = "terraform"
  }
}

###############################################################################
# On-Prem Address Blocks - Intentionally overlapping with AWS
###############################################################################

# This block overlaps with Production (10.100.0.0/16)
resource "bloxone_ipam_address_block" "onprem_legacy" {
  address = "10.100.50.0"
  cidr    = 24
  name    = "Legacy-Server-Network"
  space   = bloxone_ipam_ip_space.onprem.id
  comment = "Legacy servers - overlaps with AWS Production"

  federated_realms = [var.realm_id]

  tags = {
    environment = "on-prem"
    overlap     = "intentional-demo"
    network     = "legacy"
  }
}

# This block overlaps with Development (10.200.0.0/16)
resource "bloxone_ipam_address_block" "onprem_dev_test" {
  address = "10.200.100.0"
  cidr    = 24
  name    = "Dev-Test-Network"
  space   = bloxone_ipam_ip_space.onprem.id
  comment = "Dev/Test servers - overlaps with AWS Development"

  federated_realms = [var.realm_id]

  tags = {
    environment = "on-prem"
    overlap     = "intentional-demo"
    network     = "dev-test"
  }
}

###############################################################################
# On-Prem Subnets within the overlapping blocks
###############################################################################
resource "bloxone_ipam_subnet" "onprem_legacy_subnet" {
  address = "10.100.50.0"
  cidr    = 26
  space   = bloxone_ipam_ip_space.onprem.id
  name    = "Legacy-Subnet-1"

  tags = {
    subnet_type = "server"
    vlan        = "100"
  }
}

resource "bloxone_ipam_subnet" "onprem_devtest_subnet" {
  address = "10.200.100.0"
  cidr    = 26
  space   = bloxone_ipam_ip_space.onprem.id
  name    = "DevTest-Subnet-1"

  tags = {
    subnet_type = "workstation"
    vlan        = "200"
  }
}

###############################################################################
# Outputs
###############################################################################
output "ip_space_id" {
  description = "On-prem IP space ID"
  value       = bloxone_ipam_ip_space.onprem.id
}

output "overlapping_blocks" {
  description = "Overlapping address blocks created"
  value = {
    legacy_network = {
      id      = bloxone_ipam_address_block.onprem_legacy.id
      cidr    = "10.100.50.0/24"
      overlap = "AWS Production (10.100.0.0/16)"
    }
    devtest_network = {
      id      = bloxone_ipam_address_block.onprem_dev_test.id
      cidr    = "10.200.100.0/24"
      overlap = "AWS Development (10.200.0.0/16)"
    }
  }
}
