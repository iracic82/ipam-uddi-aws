###############################################################################
# Challenge 4: Deploy AWS VPC from AWS IPAM Pool (Infoblox Delegated)
###############################################################################
# This terraform:
# 1. Looks up the AWS IPAM APPS pool (delegated from Infoblox)
# 2. Creates VPC using IPAM pool allocation (next-available)
# 3. Infoblox sees the allocation via delegation sync
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

###############################################################################
# Variables
###############################################################################
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

variable "ipam_pool_name" {
  description = "Name of the AWS IPAM pool to allocate from"
  type        = string
  default     = "APPS"
}

variable "vpc_netmask" {
  description = "Netmask length for VPC CIDR allocation"
  type        = number
  default     = 26
}

###############################################################################
# Data Sources - Look up AWS IPAM Pool
###############################################################################
data "aws_vpc_ipam_pools" "all" {}

locals {
  # Find the APPS pool by name tag
  apps_pool = [
    for pool in data.aws_vpc_ipam_pools.all.ipam_pools :
    pool if lookup(pool.tags, "Name", "") == var.ipam_pool_name
  ][0]
}

###############################################################################
# Create AWS VPC - Allocate from IPAM Pool
###############################################################################
resource "aws_vpc" "apps" {
  ipv4_ipam_pool_id   = local.apps_pool.id
  ipv4_netmask_length = var.vpc_netmask

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = var.vpc_name
    Source      = "aws-ipam-infoblox-delegated"
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
output "ipam_pool_id" {
  description = "AWS IPAM Pool ID used"
  value       = local.apps_pool.id
}

output "vpc_id" {
  description = "AWS VPC ID"
  value       = aws_vpc.apps.id
}

output "vpc_cidr" {
  description = "AWS VPC CIDR (allocated from IPAM)"
  value       = aws_vpc.apps.cidr_block
}

output "subnet_id" {
  description = "AWS Subnet ID"
  value       = aws_subnet.apps.id
}

output "summary" {
  description = "Deployment summary"
  value = {
    ipam_pool_id   = local.apps_pool.id
    ipam_pool_name = var.ipam_pool_name
    vpc_id         = aws_vpc.apps.id
    vpc_cidr       = aws_vpc.apps.cidr_block
    subnet_id      = aws_subnet.apps.id
    aws_region     = var.aws_region
    message        = "VPC created from AWS IPAM pool (Infoblox delegated)!"
  }
}
