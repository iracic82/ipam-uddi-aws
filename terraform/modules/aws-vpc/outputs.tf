#######################################
# AWS VPC Module - Outputs
#######################################

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = aws_subnet.main.id
}

output "route_table_id" {
  description = "ID of the route table"
  value       = aws_route_table.main.id
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.main.id
}

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = var.create_ec2 ? aws_instance.main[0].id : null
}

output "private_ip" {
  description = "Private IP of the EC2 instance"
  value       = var.create_ec2 ? aws_instance.main[0].private_ip : null
}

output "public_ip" {
  description = "Public IP of the EC2 instance"
  value       = var.enable_internet && var.create_ec2 ? aws_eip.main[0].public_ip : null
}

output "ssh_private_key_path" {
  description = "Path to the SSH private key"
  value       = var.create_ec2 ? "${path.root}/${var.ec2_name}-aws.pem" : null
}

output "ssh_command" {
  description = "SSH command to connect to the EC2 instance"
  value       = var.enable_internet && var.create_ec2 ? "ssh -i '${var.ec2_name}-aws.pem' ec2-user@${aws_eip.main[0].public_ip}" : null
}
