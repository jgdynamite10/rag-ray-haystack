# Central Grafana VM on Akamai Cloud (Linode)
# Deploys a small VM running Grafana in Docker for cross-cluster monitoring

terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.0"
    }
  }
}

provider "linode" {
  # Set LINODE_TOKEN environment variable or use token variable
  token = var.linode_token
}

# Variables
variable "linode_token" {
  description = "Linode API token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Linode region"
  type        = string
  default     = "us-ord"  # Chicago - same as LKE
}

variable "instance_type" {
  description = "Linode instance type"
  type        = string
  default     = "g6-nanode-1"  # 1GB RAM, $5/month
}

variable "label" {
  description = "Instance label"
  type        = string
  default     = "rag-central-grafana"
}

variable "root_password" {
  description = "Root password for the VM"
  type        = string
  sensitive   = true
}

variable "ssh_keys" {
  description = "List of SSH public keys to add"
  type        = list(string)
  default     = []
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
  default     = "changeme123"
}

variable "prometheus_lke_url" {
  description = "Prometheus URL for Akamai LKE cluster"
  type        = string
  default     = ""
}

variable "prometheus_eks_url" {
  description = "Prometheus URL for AWS EKS cluster"
  type        = string
  default     = ""
}

variable "prometheus_gke_url" {
  description = "Prometheus URL for GCP GKE cluster"
  type        = string
  default     = ""
}

# Cloud-init script to bootstrap the VM
locals {
  cloud_init = <<-EOF
    #!/bin/bash
    set -euo pipefail
    
    # Prevent interactive prompts during apt operations
    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    
    # Log everything
    exec > >(tee /var/log/grafana-setup.log) 2>&1
    echo "Starting Grafana VM setup at $(date)"
    
    # Update system (non-interactive)
    apt-get update -qq
    apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade -y -qq
    
    # Install Docker
    curl -fsSL https://get.docker.com | sh
    
    # Install Docker Compose
    apt-get install -y -qq docker-compose-plugin
    curl -fsSL "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Create monitoring directory
    mkdir -p /opt/rag-monitoring
    cd /opt/rag-monitoring
    
    # Create docker-compose.yml
    cat > docker-compose.yml << 'COMPOSE'
    version: '3.8'

    services:
      grafana:
        image: grafana/grafana:10.4.1
        container_name: rag-central-grafana
        ports:
          - "3000:3000"
        environment:
          - GF_SECURITY_ADMIN_USER=admin
          - GF_SECURITY_ADMIN_PASSWORD=$${GRAFANA_ADMIN_PASSWORD}
          - GF_USERS_ALLOW_SIGN_UP=false
          - GF_AUTH_ANONYMOUS_ENABLED=false
        volumes:
          - grafana-data:/var/lib/grafana
          - ./provisioning:/etc/grafana/provisioning:ro
        restart: unless-stopped
        healthcheck:
          test: ["CMD-SHELL", "wget -q --spider http://localhost:3000/api/health || exit 1"]
          interval: 30s
          timeout: 10s
          retries: 3

    volumes:
      grafana-data:
    COMPOSE
    
    # Create provisioning directories
    mkdir -p provisioning/datasources provisioning/dashboards
    
    # Create datasources provisioning
    cat > provisioning/datasources/datasources.yml << 'DATASOURCES'
    apiVersion: 1

    datasources:
      - name: Prometheus-LKE
        type: prometheus
        access: proxy
        url: $${PROMETHEUS_LKE_URL}
        isDefault: true
        editable: true
        jsonData:
          httpMethod: POST
          timeInterval: "15s"

      - name: Prometheus-EKS
        type: prometheus
        access: proxy
        url: $${PROMETHEUS_EKS_URL}
        isDefault: false
        editable: true
        jsonData:
          httpMethod: POST
          timeInterval: "15s"

      - name: Prometheus-GKE
        type: prometheus
        access: proxy
        url: $${PROMETHEUS_GKE_URL}
        isDefault: false
        editable: true
        jsonData:
          httpMethod: POST
          timeInterval: "15s"
    DATASOURCES
    
    # Create dashboards provisioning
    cat > provisioning/dashboards/dashboards.yml << 'DASHBOARDS'
    apiVersion: 1

    providers:
      - name: 'RAG Benchmarking'
        orgId: 1
        folder: 'RAG Benchmarking'
        folderUid: 'rag-benchmarking'
        type: file
        disableDeletion: false
        updateIntervalSeconds: 30
        allowUiUpdates: true
        options:
          path: /var/lib/grafana/dashboards
    DASHBOARDS
    
    # Create .env file
    cat > .env << 'ENVFILE'
    GRAFANA_ADMIN_PASSWORD=${var.grafana_admin_password}
    PROMETHEUS_LKE_URL=${var.prometheus_lke_url}
    PROMETHEUS_EKS_URL=${var.prometheus_eks_url}
    PROMETHEUS_GKE_URL=${var.prometheus_gke_url}
    ENVFILE
    
    # Configure firewall
    ufw allow 22/tcp
    ufw allow 3000/tcp
    ufw --force enable
    
    # Start Grafana
    docker-compose up -d
    
    echo "Grafana VM setup complete at $(date)"
    echo "Access Grafana at http://$(curl -s ifconfig.me):3000"
  EOF
}

# Create the Linode instance
resource "linode_instance" "grafana" {
  label           = var.label
  region          = var.region
  type            = var.instance_type
  image           = "linode/ubuntu22.04"
  root_pass       = var.root_password
  authorized_keys = var.ssh_keys
  
  # Use StackScript-like approach with metadata
  metadata {
    user_data = base64encode(local.cloud_init)
  }
  
  tags = ["monitoring", "grafana", "rag"]
}

# Firewall for the Grafana VM
resource "linode_firewall" "grafana" {
  label = "${var.label}-firewall"
  
  inbound {
    label    = "allow-ssh"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22"
    ipv4     = ["0.0.0.0/0"]
  }
  
  inbound {
    label    = "allow-grafana"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "3000"
    ipv4     = ["0.0.0.0/0"]
  }
  
  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"
  
  linodes = [linode_instance.grafana.id]
}

# Outputs
output "grafana_ip" {
  description = "Public IP address of the Grafana VM"
  value       = linode_instance.grafana.ip_address
}

output "grafana_url" {
  description = "URL to access Grafana"
  value       = "http://${linode_instance.grafana.ip_address}:3000"
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = "ssh root@${linode_instance.grafana.ip_address}"
}
