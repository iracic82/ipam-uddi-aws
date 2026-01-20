#######################################
# AWS VPC Module
# Creates: VPC, Subnet, RT, IGW, SG, EC2
#######################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_availability_zones" "available" {}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = var.vpc_name
  })
}

# Subnet
resource "aws_subnet" "main" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(var.tags, {
    Name = var.subnet_name
  })
}

# Internet Gateway (optional)
resource "aws_internet_gateway" "main" {
  count  = var.enable_internet ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-igw"
  })
}

# Route Table
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-rt"
  })
}

# Route Table Association
resource "aws_route_table_association" "main" {
  route_table_id = aws_route_table.main.id
  subnet_id      = aws_subnet.main.id
}

# Default Route to IGW (if enabled)
resource "aws_route" "internet" {
  count                  = var.enable_internet ? 1 : 0
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main[0].id
  route_table_id         = aws_route_table.main.id
}

# Security Group
resource "aws_security_group" "main" {
  name        = "${var.vpc_name}-sg"
  description = "Security group for ${var.vpc_name}"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-sg"
  })
}

# Get latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Network Interface
resource "aws_network_interface" "main" {
  count           = var.create_ec2 ? 1 : 0
  subnet_id       = aws_subnet.main.id
  private_ips     = [var.private_ip]
  security_groups = [aws_security_group.main.id]

  tags = merge(var.tags, {
    Name = "${var.ec2_name}-eni"
  })
}

# EC2 Instance
resource "aws_instance" "main" {
  count         = var.create_ec2 ? 1 : 0
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type

  network_interface {
    network_interface_id = aws_network_interface.main[0].id
    device_index         = 0
  }

  user_data = var.user_data

  tags = merge(var.tags, {
    Name = var.ec2_name
  })
}

# Elastic IP (if internet enabled and EC2 created)
resource "aws_eip" "main" {
  count                     = var.enable_internet && var.create_ec2 ? 1 : 0
  domain                    = "vpc"
  instance                  = aws_instance.main[0].id
  associate_with_private_ip = var.private_ip

  depends_on = [aws_internet_gateway.main]

  tags = merge(var.tags, {
    Name = "${var.ec2_name}-eip"
  })
}
