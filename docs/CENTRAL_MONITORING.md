# Central Monitoring Setup

This guide explains how to deploy a central Grafana instance on an Akamai Cloud VM that can query Prometheus instances across all your Kubernetes clusters (LKE, EKS, GKE).

## Architecture

```
                    ┌─────────────────────────────┐
                    │  Akamai Cloud VM            │
                    │  (Central Monitoring)       │
                    │                             │
                    │  ┌───────────────────────┐  │
                    │  │       Grafana         │  │
                    │  │   (Docker Container)  │  │
                    │  └───────────┬───────────┘  │
                    └──────────────┼──────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
              ▼                    ▼                    ▼
    ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
    │   Akamai LKE    │  │    AWS EKS      │  │    GCP GKE      │
    │  ┌───────────┐  │  │  ┌───────────┐  │  │  ┌───────────┐  │
    │  │Prometheus │  │  │  │Prometheus │  │  │  │Prometheus │  │
    │  └───────────┘  │  │  └───────────┘  │  │  └───────────┘  │
    │  ┌───────────┐  │  │  ┌───────────┐  │  │  ┌───────────┐  │
    │  │  RAG App  │  │  │  │  RAG App  │  │  │  │  RAG App  │  │
    │  └───────────┘  │  │  └───────────┘  │  │  └───────────┘  │
    └─────────────────┘  └─────────────────┘  └─────────────────┘
```

## Prerequisites

- Akamai Cloud (Linode) account
- SSH access to your clusters
- Prometheus deployed in each Kubernetes cluster

## Step 1: Create the Monitoring VM

### Option A: Linode CLI

```bash
# Install Linode CLI
pip install linode-cli

# Create VM (Nanode 1GB is sufficient for Grafana)
linode-cli linodes create \
  --type g6-nanode-1 \
  --region us-ord \
  --image linode/ubuntu22.04 \
  --root_pass "YourSecurePassword" \
  --label rag-central-monitoring \
  --tags "monitoring,rag"

# Note the IP address from output
```

### Option B: Linode Cloud Manager

1. Go to https://cloud.linode.com/linodes/create
2. Choose:
   - **Image:** Ubuntu 22.04 LTS
   - **Region:** Same region as your LKE cluster (e.g., us-ord)
   - **Plan:** Nanode 1GB ($5/month) or Shared CPU 2GB ($12/month)
   - **Label:** `rag-central-monitoring`
3. Create Linode and note the IP address

## Step 2: Setup the VM

SSH into your new VM and run the setup script:

```bash
ssh root@<vm-ip>

# Run setup script
curl -fsSL https://raw.githubusercontent.com/jgdynamite10/rag-ray-haystack/main/deploy/monitoring/setup-vm.sh | bash
```

Or manually:

```bash
# Update and install Docker
apt-get update && apt-get upgrade -y
curl -fsSL https://get.docker.com | sh

# Clone repo
git clone https://github.com/jgdynamite10/rag-ray-haystack.git
cd rag-ray-haystack/deploy/monitoring

# Configure
cp env.example .env
nano .env  # Edit with your Prometheus URLs
```

## Step 3: Deploy Prometheus in Each Cluster

Before Grafana can query metrics, you need Prometheus running in each cluster.

### Install kube-prometheus-stack

```bash
# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install in each cluster (adjust KUBECONFIG for each)
export KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml  # LKE
# export KUBECONFIG=~/.kube/aws-eks-config.yaml            # EKS
# export KUBECONFIG=~/.kube/gcp-gke-config.yaml            # GKE

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set prometheus.prometheusSpec.externalLabels.provider="akamai-lke" \
  --set prometheus.prometheusSpec.externalLabels.cluster="rag-ray-dev" \
  --set prometheus.service.type=LoadBalancer
```

### Get Prometheus External IP

```bash
kubectl -n monitoring get svc prometheus-kube-prometheus-prometheus
# Note the EXTERNAL-IP
```

### Configure Scraping for RAG App

Create a ServiceMonitor to scrape the RAG backend:

```yaml
# prometheus-servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: rag-backend
  namespace: monitoring
  labels:
    release: prometheus
spec:
  namespaceSelector:
    matchNames:
      - rag-app
  selector:
    matchLabels:
      app: rag-app-backend
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

```bash
kubectl apply -f prometheus-servicemonitor.yaml
```

## Step 4: Configure Central Grafana

Edit the `.env` file on your monitoring VM with the Prometheus URLs:

```bash
cd ~/rag-ray-haystack/deploy/monitoring
nano .env
```

```ini
# .env
GRAFANA_PORT=3000
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=YourSecurePassword

# Prometheus endpoints (use LoadBalancer IPs or NodePorts)
PROMETHEUS_LKE_URL=http://192.0.2.10:9090
PROMETHEUS_EKS_URL=http://192.0.2.20:9090
PROMETHEUS_GKE_URL=http://192.0.2.30:9090
```

## Step 5: Start Grafana

```bash
cd ~/rag-ray-haystack/deploy/monitoring
docker-compose up -d

# Check status
docker-compose ps
docker-compose logs -f
```

## Step 6: Access Grafana

1. Open `http://<vm-ip>:3000` in your browser
2. Login with admin / (your password from .env)
3. Go to **Dashboards** → **RAG Benchmarking** folder
4. Open any dashboard and use the **Provider** dropdown to filter by cluster

## Pre-configured Dashboards

| Dashboard | Description |
|-----------|-------------|
| RAG System Overview | TTFT, TPOT, latency, throughput, error rate |
| vLLM Inference Metrics | Request queue, KV cache, generation throughput |
| GPU Utilization | DCGM metrics: utilization, memory, power, temp |

## Troubleshooting

### Datasource shows "Bad Gateway"

- Check if Prometheus is reachable from the VM:
  ```bash
  curl http://<prometheus-ip>:9090/api/v1/status/config
  ```
- Ensure firewall allows traffic on port 9090
- Check if Prometheus LoadBalancer has external IP

### No metrics appearing

1. Verify Prometheus is scraping the RAG app:
   ```bash
   kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090
   # Open http://localhost:9090/targets
   ```

2. Check RAG backend exposes metrics:
   ```bash
   kubectl -n rag-app port-forward svc/rag-app-rag-app-backend 8000:8000
   curl http://localhost:8000/metrics
   ```

### Provider label not showing

Ensure `externalLabels` is set in Prometheus config:
```yaml
prometheus:
  prometheusSpec:
    externalLabels:
      provider: "akamai-lke"  # or aws-eks, gcp-gke
```

## Security Considerations

### Restrict Grafana Access

1. Use a strong admin password
2. Consider adding nginx reverse proxy with SSL:
   ```bash
   sudo apt install nginx certbot python3-certbot-nginx
   # Configure nginx to proxy to localhost:3000
   # Add Let's Encrypt SSL
   ```

3. Use Linode Firewall to restrict access:
   - Allow port 22 (SSH) from your IP only
   - Allow port 443 (HTTPS) from anywhere (if using SSL)
   - Block port 3000 from public (access via nginx)

### Secure Prometheus Endpoints

For production, don't expose Prometheus directly. Options:

1. **VPN/Private Network:** Use Linode VLAN or VPC peering
2. **SSH Tunnel:** Forward Prometheus ports through SSH
3. **Prometheus Federation:** Central Prometheus scrapes from cluster Prometheus instances

## Maintenance

### Update Grafana

```bash
cd ~/rag-ray-haystack/deploy/monitoring
git pull origin main
docker-compose pull
docker-compose up -d
```

### Backup Grafana Data

```bash
docker-compose exec grafana grafana-cli admin export
# Or backup the volume:
docker run --rm -v rag-monitoring_grafana-data:/data -v $(pwd):/backup alpine tar czf /backup/grafana-backup.tar.gz /data
```

### View Logs

```bash
docker-compose logs -f grafana
```
