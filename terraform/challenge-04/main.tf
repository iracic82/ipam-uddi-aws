###############################################################################
# Challenge 4: Deploy AWS VPC with Infoblox IP Allocation
###############################################################################
# This terraform:
# 1. Looks up ACME Corporation realm
# 2. Creates an IP Space and Address Block in Infoblox
# 3. Allocates next-available subnet from the block
# 4. Creates AWS VPC and networking using that allocation
###############################################################################

terraform {
  required_providers {
    bloxone = {
      source  = "infobloxopen/bloxone"
      version = ">= 1.5.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "bloxone" {
  csp_url = "https://csp.infoblox.com"
  api_key = var.ddi_api_key

  default_tags = {
    managed_by = "terraform"
    lab        = "challenge-04"
  }
}

###############################################################################
# Variables
###############################################################################
variable "ddi_api_key" {
  description = "Infoblox CSP API key"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "availability_zone" {
  description = "AWS availability zone"
  type        = string
  default     = "eu-west-1a"
}

variable "vpc_name" {
  description = "Name for the new VPC"
  type        = string
  default     = "Apps-VPC"
}

variable "apps_block_cidr" {
  description = "CIDR for the APPS address block"
  type        = string
  default     = "10.40.0.0/24"
}

###############################################################################
# Lookup Infoblox Federated Realm
###############################################################################
data "bloxone_federation_federated_realms" "acme" {
  filters = {
    name = "ACME Corporation"
  }
}

###############################################################################
# Create Infoblox IP Space for Apps
###############################################################################
resource "bloxone_ipam_ip_space" "apps" {
  name    = "Apps-IP-Space"
  comment = "IP Space for Apps VPCs - Challenge 4"

  default_realms = [data.bloxone_federation_federated_realms.acme.results[0].id]

  tags = {
    environment = "apps"
    purpose     = "vpc-allocation"
  }
}

###############################################################################
# Create Address Block in the IP Space
###############################################################################
resource "bloxone_ipam_address_block" "apps" {
  address = split("/", var.apps_block_cidr)[0]
  cidr    = tonumber(split("/", var.apps_block_cidr)[1])
  name    = "Apps-Block"
  space   = bloxone_ipam_ip_space.apps.id
  comment = "Address block for Apps VPCs"

  federated_realms = [data.bloxone_federation_federated_realms.acme.results[0].id]

  tags = {
    environment = "apps"
    origin      = "terraform"
  }
}

###############################################################################
# Allocate Next Available Subnet from Apps Block
###############################################################################
resource "bloxone_ipam_subnet" "apps_vpc_subnet" {
  next_available_id = bloxone_ipam_address_block.apps.id
  cidr              = 26
  space             = bloxone_ipam_ip_space.apps.id
  name              = "${var.vpc_name}-Subnet"
  comment           = "Allocated for ${var.vpc_name} via Challenge 4 automation"

  tags = {
    environment = "apps"
    provisioned = "terraform"
    challenge   = "04"
  }
}

###############################################################################
# Create AWS VPC from Infoblox Allocation
###############################################################################
resource "aws_vpc" "apps" {
  cidr_block           = "${bloxone_ipam_subnet.apps_vpc_subnet.address}/${bloxone_ipam_subnet.apps_vpc_subnet.cidr}"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = var.vpc_name
    Source      = "infoblox-allocation"
    Environment = "apps"
    ManagedBy   = "terraform"
  }
}

resource "aws_subnet" "apps" {
  vpc_id                  = aws_vpc.apps.id
  cidr_block              = aws_vpc.apps.cidr_block
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.vpc_name}-Subnet"
    Environment = "apps"
    ManagedBy   = "terraform"
  }
}

resource "aws_internet_gateway" "apps" {
  vpc_id = aws_vpc.apps.id

  tags = {
    Name        = "${var.vpc_name}-IGW"
    Environment = "apps"
    ManagedBy   = "terraform"
  }
}

resource "aws_route_table" "apps" {
  vpc_id = aws_vpc.apps.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.apps.id
  }

  tags = {
    Name        = "${var.vpc_name}-RT"
    Environment = "apps"
    ManagedBy   = "terraform"
  }
}

resource "aws_route_table_association" "apps" {
  subnet_id      = aws_subnet.apps.id
  route_table_id = aws_route_table.apps.id
}

resource "aws_security_group" "apps" {
  name        = "${var.vpc_name}-SG"
  description = "Security group for ${var.vpc_name}"
  vpc_id      = aws_vpc.apps.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.vpc_name}-SG"
    Environment = "apps"
    ManagedBy   = "terraform"
  }
}

###############################################################################
# Outputs
###############################################################################
output "infoblox_ip_space" {
  description = "Infoblox IP Space created"
  value       = bloxone_ipam_ip_space.apps.name
}

output "infoblox_address_block" {
  description = "Infoblox Address Block created"
  value       = "${bloxone_ipam_address_block.apps.address}/${bloxone_ipam_address_block.apps.cidr}"
}

output "infoblox_allocated_cidr" {
  description = "CIDR allocated from Infoblox"
  value       = "${bloxone_ipam_subnet.apps_vpc_subnet.address}/${bloxone_ipam_subnet.apps_vpc_subnet.cidr}"
}

output "vpc_id" {
  description = "AWS VPC ID"
  value       = aws_vpc.apps.id
}

output "vpc_cidr" {
  description = "AWS VPC CIDR"
  value       = aws_vpc.apps.cidr_block
}

output "subnet_id" {
  description = "AWS Subnet ID"
  value       = aws_subnet.apps.id
}

output "summary" {
  description = "Deployment summary"
  value = {
    infoblox_ip_space       = bloxone_ipam_ip_space.apps.name
    infoblox_address_block  = "${bloxone_ipam_address_block.apps.address}/${bloxone_ipam_address_block.apps.cidr}"
    infoblox_allocation     = "${bloxone_ipam_subnet.apps_vpc_subnet.address}/${bloxone_ipam_subnet.apps_vpc_subnet.cidr}"
    aws_vpc_id              = aws_vpc.apps.id
    aws_vpc_cidr            = aws_vpc.apps.cidr_block
    aws_subnet_id           = aws_subnet.apps.id
    aws_region              = var.aws_region
    message                 = "VPC created with IP-safe allocation from Infoblox!"
  }
}
