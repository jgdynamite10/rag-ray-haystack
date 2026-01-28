#!/bin/bash
# Setup script for Central Monitoring VM on Akamai Cloud (Linode)
# Run this on a fresh Ubuntu 22.04 Linode VM
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/jgdynamite10/rag-ray-haystack/main/deploy/monitoring/setup-vm.sh | bash
#   # Or download and run:
#   chmod +x setup-vm.sh && ./setup-vm.sh

set -euo pipefail

echo "=== Central Monitoring Setup for RAG Benchmarking ==="
echo ""

# Update system
echo "[1/5] Updating system packages..."
sudo apt-get update -qq
sudo apt-get upgrade -y -qq

# Install Docker
echo "[2/5] Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker $USER
    echo "Docker installed. You may need to log out and back in for group changes."
else
    echo "Docker already installed."
fi

# Install Docker Compose
echo "[3/5] Installing Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    sudo apt-get install -y -qq docker-compose-plugin
    # Also install standalone docker-compose for compatibility
    sudo curl -fsSL "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
else
    echo "Docker Compose already installed."
fi

# Clone repo (or create directory structure)
echo "[4/5] Setting up monitoring stack..."
MONITORING_DIR="$HOME/rag-monitoring"

if [ -d "$MONITORING_DIR" ]; then
    echo "Directory $MONITORING_DIR already exists. Updating..."
    cd "$MONITORING_DIR"
    git pull origin main 2>/dev/null || echo "Not a git repo, skipping pull."
else
    echo "Cloning repository..."
    git clone https://github.com/jgdynamite10/rag-ray-haystack.git "$MONITORING_DIR"
    cd "$MONITORING_DIR"
fi

cd deploy/monitoring

# Create .env file if not exists
if [ ! -f .env ]; then
    echo "[5/5] Creating configuration file..."
    cp env.example .env
    echo ""
    echo "=== IMPORTANT ==="
    echo "Edit the .env file with your Prometheus endpoints:"
    echo "  nano $MONITORING_DIR/deploy/monitoring/.env"
    echo ""
    echo "Example:"
    echo "  PROMETHEUS_LKE_URL=http://192.0.2.10:9090"
    echo "  PROMETHEUS_EKS_URL=http://192.0.2.20:9090"
    echo "  PROMETHEUS_GKE_URL=http://192.0.2.30:9090"
    echo ""
else
    echo "[5/5] Configuration file already exists."
fi

# Configure firewall
echo "Configuring firewall..."
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 3000/tcp # Grafana
sudo ufw --force enable

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit configuration: nano $MONITORING_DIR/deploy/monitoring/.env"
echo "  2. Start Grafana: cd $MONITORING_DIR/deploy/monitoring && docker-compose up -d"
echo "  3. Access Grafana: http://$(curl -s ifconfig.me):3000"
echo "  4. Login: admin / (password from .env)"
echo ""
echo "To view logs: docker-compose logs -f"
echo "To stop: docker-compose down"
