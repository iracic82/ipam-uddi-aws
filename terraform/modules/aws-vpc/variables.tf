#######################################
# AWS VPC Module - Variables
#######################################

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
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
  description = "Whether to create IGW and default route"
  type        = bool
  default     = true
}

variable "create_ec2" {
  description = "Whether to create EC2 instance"
  type        = bool
  default     = true
}

variable "ec2_name" {
  description = "Name of the EC2 instance"
  type        = string
  default     = "demo-instance"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "private_ip" {
  description = "Private IP for the EC2 instance"
  type        = string
}

variable "user_data" {
  description = "User data script for EC2"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
