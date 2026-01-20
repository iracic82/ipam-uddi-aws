#!/bin/bash
# AWS EC2 User Data Script for IPAM Lab
# Installs: Docker, networking tools, sample app

set -e

# Update system
yum update -y

# Install packages
yum install -y docker iperf3 jq curl wget

# Install Python packages
pip3 install requests boto3

# Start Docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Pull sample containers
docker pull nginx:alpine
docker pull iracic82/prosimo-flask-app-labs:latest || true

# Run simple web server for connectivity testing
docker run -d --name web-server -p 80:80 nginx:alpine

# Create a simple health check script
cat > /home/ec2-user/health-check.sh << 'EOF'
#!/bin/bash
echo "=== EC2 Health Check ==="
echo "Hostname: $(hostname)"
echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo 'N/A')"
echo "Docker Status: $(systemctl is-active docker)"
echo "Running Containers: $(docker ps -q | wc -l)"
EOF

chmod +x /home/ec2-user/health-check.sh
chown ec2-user:ec2-user /home/ec2-user/health-check.sh

echo "User data script completed successfully"
