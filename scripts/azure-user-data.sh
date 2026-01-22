#!/bin/bash
# Azure VM User Data Script for IPAM Lab
# Installs: Docker, networking tools, sample apps
# For Ubuntu 22.04 LTS

set -e

# Update system
sudo apt update
sudo apt upgrade -y

# Install packages
sudo apt install -y docker.io iperf3 jq curl wget python3-pip net-tools

# Install Python packages
pip3 install requests

# Start Docker
sudo systemctl start docker
sudo systemctl enable docker

# Add user to docker group
sudo groupadd docker 2>/dev/null || true
sudo usermod -aG docker azureuser

# Download network testing script
sudo curl -s https://igor-prosimo.s3.eu-west-1.amazonaws.com/network_testing.py -o /home/azureuser/network_testing.py 2>/dev/null || true

# Pull sample containers
sudo docker pull nginx:alpine
sudo docker pull iracic82/prosimo-flask-app-labs:latest || true
sudo docker pull iracic82/prosimo-iperf3:latest || true
sudo docker pull iracic82/prosimo-postgresql:latest || true
sudo docker pull iracic82/prosimo-flask-sqlclient:latest || true
sudo docker pull iracic82/prosimo-security-api:latest || true

# Run Flask SQL client container
sudo docker run -d -p 5000:5000 iracic82/prosimo-flask-sqlclient:latest || true

# Run iPerf3 server container
sudo docker run -d --name iperf-server \
  -p 5201:5201/tcp \
  -p 5201:5201/udp \
  -p 5201:5201/sctp \
  iracic82/prosimo-iperf3:latest -s || true

# Run simple web server for connectivity testing
sudo docker run -d --name web-server -p 80:80 nginx:alpine

# Create network testing loop script
cat <<"EOT" > /home/azureuser/run_script.sh
#!/bin/bash

while true; do
    # Call Python network testing script
    python3 /home/azureuser/network_testing.py 2>/dev/null || true

    # Sleep for 3 minutes (180 seconds)
    sleep 180
done
EOT

sudo chmod +x /home/azureuser/run_script.sh
sudo chown azureuser:azureuser /home/azureuser/run_script.sh

# Start the network testing script in background
nohup sudo -u azureuser /home/azureuser/run_script.sh > /dev/null 2>&1 &

# Create a health check script
cat > /home/azureuser/health-check.sh << 'EOF'
#!/bin/bash
echo "=== Azure VM Health Check ==="
echo "Hostname: $(hostname)"
echo "Private IP: $(hostname -I | awk '{print $1}')"
echo "Public IP: $(curl -s ifconfig.me 2>/dev/null || echo 'N/A')"
echo "Docker Status: $(systemctl is-active docker)"
echo "Running Containers: $(docker ps -q | wc -l)"
echo ""
echo "=== Running Containers ==="
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"
EOF

chmod +x /home/azureuser/health-check.sh
chown azureuser:azureuser /home/azureuser/health-check.sh

echo "User data script completed successfully"
