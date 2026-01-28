# Observability Guide

This document covers the complete Prometheus and Grafana setup for monitoring the RAG system, including central monitoring for cross-cluster comparison.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            OBSERVABILITY STACK                              │
└─────────────────────────────────────────────────────────────────────────────┘

                    Option A: In-Cluster Grafana
                    (Deployed with kube-prometheus-stack)
                    
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster (LKE)                            │
│                                                                             │
│  ┌─────────────────┐    scrape    ┌─────────────────┐                      │
│  │   Prometheus    │◄─────────────│   RAG Backend   │                      │
│  │   (monitoring)  │              │   /metrics      │                      │
│  └────────┬────────┘              └─────────────────┘                      │
│           │                                                                 │
│           │ query                                                           │
│           ▼                                                                 │
│  ┌─────────────────┐                                                       │
│  │    Grafana      │◄──── Access via port-forward or LoadBalancer          │
│  │   (monitoring)  │                                                       │
│  └─────────────────┘                                                       │
└─────────────────────────────────────────────────────────────────────────────┘


                    Option B: Central Grafana (Recommended)
                    (For cross-cluster comparison)

┌─────────────────────────────────────────────────────────────────────────────┐
│                        Central Grafana VM                                   │
│                        (Akamai Cloud / Linode)                              │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         Grafana                                      │   │
│  │   Datasources:                                                       │   │
│  │   - Prometheus-LKE  (http://<lke-prometheus-ip>:9090)               │   │
│  │   - Prometheus-EKS  (http://<eks-prometheus-ip>:9090)               │   │
│  │   - Prometheus-GKE  (http://<gke-prometheus-ip>:9090)               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
         │                         │                         │
         ▼                         ▼                         ▼
    ┌─────────┐              ┌─────────┐              ┌─────────┐
    │   LKE   │              │   EKS   │              │   GKE   │
    │Prometheus│              │Prometheus│              │Prometheus│
    └─────────┘              └─────────┘              └─────────┘
```

---

## Part 1: Prometheus Deployment (Per Cluster)

### What Gets Deployed

The `kube-prometheus-stack` Helm chart deploys:

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| Prometheus | monitoring | Scrapes and stores metrics |
| Alertmanager | monitoring | Handles alerts (optional) |
| Node Exporter | monitoring | Host-level metrics |
| Kube State Metrics | monitoring | Kubernetes object metrics |

> **Note:** Grafana is disabled in our config since we use a central Grafana VM.

### Deploy Prometheus

```bash
# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Deploy to LKE
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f deploy/monitoring/prometheus-values.yaml \
  --set prometheus.prometheusSpec.externalLabels.provider="akamai-lke" \
  --set prometheus.prometheusSpec.externalLabels.region="us-ord"

# For EKS (when ready)
# KUBECONFIG=~/.kube/aws-eks-config.yaml \
# helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
#   --namespace monitoring --create-namespace \
#   -f deploy/monitoring/prometheus-values.yaml \
#   --set prometheus.prometheusSpec.externalLabels.provider="aws-eks" \
#   --set prometheus.prometheusSpec.externalLabels.region="us-east-1"
```

### Configure ServiceMonitor for RAG Backend

```bash
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
kubectl apply -f - <<'EOF'
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
EOF
```

### Get Prometheus External IP

```bash
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
kubectl -n monitoring get svc prometheus-kube-prometheus-prometheus

# Example output:
# NAME                                    TYPE           EXTERNAL-IP      PORT(S)
# prometheus-kube-prometheus-prometheus   LoadBalancer   172.238.165.45   9090:32112/TCP
```

### Verify Scraping

1. Port-forward to Prometheus:
   ```bash
   kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090
   ```
2. Open http://localhost:9090
3. Go to Status → Targets
4. Look for `rag-backend` target showing `UP`

---

## Part 2: Central Grafana Deployment

For cross-cluster comparison, deploy a central Grafana on a separate VM.

### Option A: Terraform (Recommended)

```bash
cd deploy/monitoring/terraform

# 1. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values:
#   - linode_token
#   - root_password
#   - grafana_admin_password
#   - prometheus_lke_url (e.g., http://172.238.165.45:9090)

# 2. Deploy
terraform init
terraform plan
terraform apply

# 3. Access Grafana
# URL shown in terraform output
```

### Option B: Manual Setup

#### Step 1: Create Linode VM

**Via Linode CLI:**
```bash
pip install linode-cli

linode-cli linodes create \
  --type g6-nanode-1 \
  --region us-ord \
  --image linode/ubuntu22.04 \
  --root_pass "YourSecurePassword" \
  --label rag-central-grafana \
  --tags "monitoring,rag"
```

**Via Cloud Manager:**
1. Go to https://cloud.linode.com/linodes/create
2. Choose Ubuntu 22.04 LTS, Nanode 1GB ($5/month), us-ord region
3. Create and note the IP address

#### Step 2: Setup the VM

```bash
ssh root@<vm-ip>

# Install Docker
curl -fsSL https://get.docker.com | sh

# Clone repo
git clone https://github.com/jgdynamite10/rag-ray-haystack.git
cd rag-ray-haystack/deploy/monitoring

# Configure
cp env.example .env
nano .env
```

Edit `.env`:
```ini
GRAFANA_PORT=3000
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=YourSecurePassword

# Prometheus endpoints
PROMETHEUS_LKE_URL=http://172.238.165.45:9090
PROMETHEUS_EKS_URL=
PROMETHEUS_GKE_URL=
```

#### Step 3: Start Grafana

```bash
docker-compose up -d

# Check status
docker-compose ps
docker-compose logs -f
```

#### Step 4: Access Grafana

1. Open `http://<vm-ip>:3000`
2. Login with admin / (your password)
3. Dashboards are auto-provisioned in the "RAG Benchmarking" folder

---

## Part 3: Metrics Reference

### RAG Backend Metrics

The backend exposes these Prometheus metrics at `/metrics`:

#### Request Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `rag_requests_total` | Counter | Total requests by endpoint |
| `rag_errors_total` | Counter | Total errors by endpoint |

#### Latency Metrics (Histograms)

| Metric | Labels | Description |
|--------|--------|-------------|
| `rag_latency_seconds` | `stage` | Latency by stage (embedding, retrieval, generation, total) |
| `rag_ttft_seconds` | - | Time to first token |
| `rag_tpot_seconds` | - | Time per output token |
| `rag_tokens_per_second` | - | Token generation rate |

#### Token Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `rag_tokens_total` | Counter | Total tokens generated |

### Example Prometheus Queries

```promql
# Request rate
rate(rag_requests_total[5m])

# Error rate
rate(rag_errors_total[5m]) / rate(rag_requests_total[5m])

# TTFT p95
histogram_quantile(0.95, rate(rag_ttft_seconds_bucket[5m]))

# TPOT p95
histogram_quantile(0.95, rate(rag_tpot_seconds_bucket[5m]))

# Total latency p95
histogram_quantile(0.95, rate(rag_latency_seconds_bucket{stage="total"}[5m]))

# Latency breakdown by stage
histogram_quantile(0.95, rate(rag_latency_seconds_bucket{stage="retrieval"}[5m]))
histogram_quantile(0.95, rate(rag_latency_seconds_bucket{stage="generation"}[5m]))

# Tokens per second
rate(rag_tokens_total[5m])

# Filter by provider (cross-cluster)
histogram_quantile(0.95, rate(rag_ttft_seconds_bucket{provider="akamai-lke"}[5m]))
```

### External Labels

Prometheus adds these labels to all metrics for cross-cluster identification:

```yaml
externalLabels:
  provider: "akamai-lke"  # or aws-eks, gcp-gke
  region: "us-ord"
  cluster: "rag-ray-dev"
```

---

## Part 4: Grafana Dashboards

### Pre-configured Dashboards

Located in `grafana/dashboards/`:

| Dashboard | File | Description |
|-----------|------|-------------|
| RAG Overview | `rag-overview.json` | TTFT, TPOT, latency, throughput, errors |
| Provider Comparison | `provider-comparison.json` | Side-by-side provider metrics table |
| vLLM Metrics | `vllm-metrics.json` | vLLM inference server metrics |
| GPU Utilization | `gpu-utilization.json` | DCGM GPU metrics |

### Dashboard Features

- **Provider dropdown**: Filter by akamai-lke, aws-eks, gcp-gke
- **Time series comparison**: See metrics across providers over time
- **Comparison table**: Side-by-side snapshot of all providers

### Import Dashboards Manually

1. Access Grafana
2. Go to Dashboards → Import
3. Upload JSON file from `grafana/dashboards/`
4. Select Prometheus datasource

---

## Part 5: Troubleshooting

### Prometheus Not Scraping RAG Backend

1. Check ServiceMonitor exists:
   ```bash
   kubectl -n monitoring get servicemonitor rag-backend
   ```

2. Check service labels match:
   ```bash
   kubectl -n rag-app get svc -l app=rag-app-backend --show-labels
   ```

3. Check Prometheus targets (Status → Targets in Prometheus UI)

### No Data in Grafana

1. Verify Prometheus has data:
   ```promql
   rag_requests_total
   ```

2. Check time range (metrics need time to accumulate)

3. Run a benchmark to generate metrics:
   ```bash
   ./scripts/benchmark/run_ns.sh akamai-lke --url http://<app-url>/api/query/stream
   ```

### Datasource Shows "Bad Gateway"

1. Check Prometheus is reachable from Grafana VM:
   ```bash
   curl http://<prometheus-ip>:9090/api/v1/status/config
   ```

2. Ensure firewall allows port 9090

### Provider Label Missing

Check externalLabels in Prometheus:
```bash
kubectl -n monitoring get prometheus prometheus-kube-prometheus-prometheus -o yaml | grep -A5 externalLabels
```

---

## Part 6: Security

### Prometheus

- Default: ClusterIP (internal only)
- LoadBalancer exposes to internet - add firewall rules
- For production: Use Ingress with authentication or VPN

### Grafana

- Change default password immediately
- For production: Use HTTPS via nginx reverse proxy
- Consider OAuth/LDAP integration

### Firewall Rules (Linode)

```bash
# Allow only necessary ports
ufw allow 22/tcp    # SSH
ufw allow 3000/tcp  # Grafana
ufw enable
```

---

## Part 7: Maintenance

### Update Prometheus Stack

```bash
helm repo update
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f deploy/monitoring/prometheus-values.yaml
```

### Update Central Grafana

```bash
ssh root@<grafana-vm-ip>
cd /opt/rag-monitoring  # or ~/rag-ray-haystack/deploy/monitoring
docker-compose pull
docker-compose up -d
```

### View Logs

```bash
# Prometheus
kubectl -n monitoring logs -l app.kubernetes.io/name=prometheus -f

# Grafana (on VM)
docker-compose logs -f grafana
```

### Backup Grafana

```bash
# On Grafana VM
cd /opt/rag-monitoring
docker run --rm -v rag-monitoring_grafana-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/grafana-backup.tar.gz /data
```

---

## Quick Reference

### Deploy Prometheus (per cluster)
```bash
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f deploy/monitoring/prometheus-values.yaml \
  --set prometheus.prometheusSpec.externalLabels.provider="<provider>"
```

### Deploy Central Grafana (Terraform)
```bash
cd deploy/monitoring/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
terraform init && terraform apply
```

### Access Prometheus
```bash
kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open http://localhost:9090
```

### Get Prometheus External IP
```bash
kubectl -n monitoring get svc prometheus-kube-prometheus-prometheus
```
