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

### Configure Prometheus to Scrape RAG Backend

**Important:** The Helm-deployed RAG app uses specific labels. You must match the correct labels.

#### Step 1: Check Service and Pod Labels

```bash
# Check service labels (used by ServiceMonitor)
kubectl -n rag-app get svc rag-app-rag-app-backend --show-labels

# Check pod labels (used by PodMonitor)
kubectl -n rag-app get pods -l app=rag-app-rag-app-backend --show-labels
```

#### Step 2: Add Named Port to Service (Required for ServiceMonitor)

ServiceMonitors require a **named port**. Patch the service:

```bash
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
kubectl -n rag-app patch svc rag-app-rag-app-backend \
  --type='json' -p='[{"op": "replace", "path": "/spec/ports/0/name", "value": "http"}]'
```

#### Step 3: Create ServiceMonitor (Recommended)

```bash
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: rag-backend
  namespace: monitoring
  labels:
    release: prometheus  # Required: must match Prometheus serviceMonitorSelector
spec:
  namespaceSelector:
    matchNames:
      - rag-app
  selector:
    matchLabels:
      # IMPORTANT: Use the actual SERVICE labels, not pod labels
      app.kubernetes.io/name: rag-app
      app.kubernetes.io/component: backend
  endpoints:
    - port: http           # Must match the named port on the service
      path: /metrics
      interval: 15s
EOF
```

#### Alternative: Create PodMonitor (If Service Labels Don't Work)

PodMonitors select pods directly and can use `targetPort` (no named port required):

```bash
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
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
      # Use the actual POD labels (check with kubectl get pods --show-labels)
      app: rag-app-rag-app-backend
  podMetricsEndpoints:
    - targetPort: 8000     # Can use port number directly
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

## Part 2b: GPU Metrics (DCGM Exporter)

DCGM (Data Center GPU Manager) exporter provides GPU metrics for Prometheus.

### Provider-Specific Setup

#### Akamai LKE (GPU Operator Pre-Installed)

LKE GPU nodes come with the **NVIDIA GPU Operator** pre-installed, which includes DCGM exporter.

**Verify DCGM is running:**
```bash
kubectl get pods -n gpu-operator | grep dcgm
# Expected: nvidia-dcgm-exporter-xxxxx   1/1   Running
```

**Check GPU metrics are exposed:**
```bash
kubectl port-forward -n gpu-operator svc/nvidia-dcgm-exporter 9400:9400 &
curl -s localhost:9400/metrics | grep DCGM_FI_DEV_GPU_TEMP
kill %1
```

**Add ServiceMonitor for Prometheus scraping:**
```bash
kubectl apply -f deploy/monitoring/dcgm-servicemonitor.yaml
```

Or manually:
```bash
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nvidia-dcgm-exporter
  namespace: gpu-operator
  labels:
    app: nvidia-dcgm-exporter
    release: prometheus
spec:
  selector:
    matchLabels:
      app: nvidia-dcgm-exporter
  endpoints:
    - port: gpu-metrics
      interval: 15s
  namespaceSelector:
    matchNames:
      - gpu-operator
EOF
```

#### AWS EKS

EKS does **not** include GPU Operator by default. You have two options:

**Option A: Install NVIDIA GPU Operator (Recommended)**
```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator --create-namespace \
  --set operator.defaultRuntime=containerd
```

**Option B: Install DCGM Exporter Only**
```bash
helm install dcgm-exporter nvidia/dcgm-exporter \
  --namespace gpu-operator --create-namespace \
  --set serviceMonitor.enabled=true
```

After installation, apply the ServiceMonitor:
```bash
kubectl apply -f deploy/monitoring/dcgm-servicemonitor.yaml
```

#### GCP GKE

GKE with GPU node pools includes the NVIDIA device plugin but **not** DCGM exporter.

**Install DCGM Exporter:**
```bash
# Add NVIDIA Helm repo
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# Install DCGM exporter
helm install dcgm-exporter nvidia/dcgm-exporter \
  --namespace gpu-operator --create-namespace \
  --set serviceMonitor.enabled=true \
  --set arguments[0]="--kubernetes"
```

Then apply the ServiceMonitor:
```bash
kubectl apply -f deploy/monitoring/dcgm-servicemonitor.yaml
```

### DCGM Metrics Reference

| Metric | Description | Unit |
|--------|-------------|------|
| `DCGM_FI_DEV_GPU_UTIL` | GPU utilization | % |
| `DCGM_FI_DEV_FB_USED` | GPU framebuffer memory used | bytes |
| `DCGM_FI_DEV_FB_FREE` | GPU framebuffer memory free | bytes |
| `DCGM_FI_DEV_GPU_TEMP` | GPU temperature | °C |
| `DCGM_FI_DEV_POWER_USAGE` | GPU power draw | Watts |
| `DCGM_FI_DEV_SM_CLOCK` | Streaming multiprocessor clock | MHz |
| `DCGM_FI_DEV_MEM_CLOCK` | Memory clock | MHz |

### Example Prometheus Queries for GPU

```promql
# GPU Utilization
avg(DCGM_FI_DEV_GPU_UTIL)

# GPU Memory Usage (%)
avg(DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) * 100)

# GPU Temperature
avg(DCGM_FI_DEV_GPU_TEMP)

# GPU Power
avg(DCGM_FI_DEV_POWER_USAGE)

# Compare GPU utilization across providers
avg(DCGM_FI_DEV_GPU_UTIL) by (provider)
```

### Troubleshooting DCGM

**No DCGM pods running:**
- Check if GPU Operator is installed: `kubectl get pods -n gpu-operator`
- Check node labels: `kubectl describe node <gpu-node> | grep nvidia`

**DCGM exporter CrashLoopBackOff:**
- Usually means driver access issue
- Check if another DCGM instance is running
- Verify NVIDIA drivers: `kubectl exec -it <gpu-pod> -- nvidia-smi`

**ServiceMonitor not being scraped:**
- Verify labels match: `kubectl get svc -n gpu-operator nvidia-dcgm-exporter --show-labels`
- Check port name: `kubectl get svc -n gpu-operator nvidia-dcgm-exporter -o yaml | grep -A3 ports`

---

## Part 2c: Pushgateway for East-West Metrics

The East-West network probe pushes metrics to Prometheus via Pushgateway. This is required for East-West metrics to appear on the ITDM dashboard.

### Deploy Pushgateway

Deploy the Pushgateway manifest (ClusterIP - internal access only):

```bash
kubectl apply -f deploy/monitoring/pushgateway.yaml
```

This creates:
- Deployment: `prometheus-pushgateway`
- Service: `prometheus-pushgateway` (ClusterIP on port 9091)
- ServiceMonitor: Auto-discovered by Prometheus

**Note:** No external LoadBalancer needed - the E-W probe pod pushes metrics directly to the internal service.

### Run East-West Probe

The probe automatically pushes metrics from inside the cluster:

```bash
./scripts/netprobe/run_ew.sh --provider akamai-lke
```

The iperf3-client pod pushes metrics to `prometheus-pushgateway.monitoring.svc.cluster.local:9091`.

### East-West Metrics

The following metrics are pushed to Prometheus:

| Metric | Description | Unit |
|--------|-------------|------|
| `ew_tcp_throughput_gbps` | TCP throughput between nodes | Gbps |
| `ew_tcp_throughput_bps` | TCP throughput between nodes | bps |
| `ew_tcp_retransmits` | TCP retransmit count | count |
| `ew_udp_jitter_ms` | UDP jitter | ms |
| `ew_udp_loss_percent` | UDP packet loss | % |
| `ew_latency_min_ms` | Minimum latency | ms |
| `ew_latency_avg_ms` | Average latency | ms |
| `ew_latency_max_ms` | Maximum latency | ms |

All metrics have a `provider` label for filtering.

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

#### Retrieval Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `rag_k_retrieved` | Histogram | Number of documents retrieved per query (buckets: 0-20) |

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

1. Access Grafana at `http://<grafana-ip>:3000`
2. Login with `admin` / (your password)
3. Go to **Dashboards** → **New** → **Import**
4. Click **Upload dashboard JSON file**
5. Upload each file from `grafana/dashboards/`:
   - `rag-overview.json` - RAG System Overview with TTFT, TPOT, latency
   - `provider-comparison.json` - Cross-provider comparison table
   - `vllm-metrics.json` - vLLM inference metrics
   - `gpu-utilization.json` - DCGM GPU metrics
6. Select **Prometheus-LKE** as the datasource
7. Click **Import**

### Verify Setup

After import, you should see these dashboards:

| Dashboard | Purpose |
|-----------|---------|
| GPU Utilization (DCGM) | GPU metrics from NVIDIA DCGM exporter |
| Provider Comparison | Side-by-side metrics across providers |
| RAG System Overview | TTFT, TPOT, latency, throughput |
| vLLM Inference Metrics | vLLM request queue, KV cache |

---

## Part 5: Troubleshooting

### Cloud-Init Stuck on Interactive Prompt (Terraform)

If `cloud-init status` shows `running` but Grafana isn't starting, the apt upgrade may be stuck on an interactive prompt.

**Fix:**

```bash
# SSH into the VM
ssh root@<vm-ip>

# Kill stuck processes
sudo pkill -9 cloud-init
sudo pkill -9 apt
sudo pkill -9 dpkg

# Remove lock files
sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock

# Fix broken packages
sudo dpkg --configure -a

# Install Docker manually
curl -fsSL https://get.docker.com | sh

# Create Grafana setup
mkdir -p /opt/rag-monitoring
cd /opt/rag-monitoring

cat > docker-compose.yml << 'EOF'
services:
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana-data:/var/lib/grafana
      - ./provisioning:/etc/grafana/provisioning

volumes:
  grafana-data:
EOF

mkdir -p provisioning/datasources
cat > provisioning/datasources/datasources.yml << 'EOF'
apiVersion: 1
datasources:
  - name: Prometheus-LKE
    type: prometheus
    access: proxy
    url: http://<PROMETHEUS_IP>:9090
    isDefault: true
    editable: true
EOF

# Start Grafana
docker compose up -d
```

### Prometheus Not Scraping RAG Backend

This is a common issue. Follow these steps systematically:

#### 1. Verify the ServiceMonitor/PodMonitor Exists

```bash
kubectl -n monitoring get servicemonitor rag-backend
kubectl -n monitoring get podmonitor rag-backend
```

#### 2. Check Label Mismatch (Most Common Issue)

**The #1 cause of scraping failures is label mismatch.**

```bash
# Get the ACTUAL service labels
kubectl -n rag-app get svc rag-app-rag-app-backend -o jsonpath='{.metadata.labels}' | jq

# Get the ACTUAL pod labels  
kubectl -n rag-app get pods -l app=rag-app-rag-app-backend -o jsonpath='{.items[0].metadata.labels}' | jq
```

Compare these with what your ServiceMonitor/PodMonitor is selecting:

```bash
kubectl -n monitoring get servicemonitor rag-backend -o yaml | grep -A5 "selector:"
```

**Common mistakes:**
- Service labels: `app.kubernetes.io/name: rag-app` (not `app: rag-app-backend`)
- Pod labels: `app: rag-app-rag-app-backend` (not `app: rag-app-backend`)

#### 3. Check Named Port (ServiceMonitor Only)

ServiceMonitors require a **named port**. Check if the service has one:

```bash
kubectl -n rag-app get svc rag-app-rag-app-backend -o yaml | grep -A5 "ports:"
```

If the port doesn't have a `name:` field, add one:

```bash
kubectl -n rag-app patch svc rag-app-rag-app-backend \
  --type='json' -p='[{"op": "replace", "path": "/spec/ports/0/name", "value": "http"}]'
```

#### 4. Check Prometheus ServiceMonitor Selector

Prometheus only watches ServiceMonitors with specific labels:

```bash
kubectl -n monitoring get prometheus prometheus-kube-prometheus-prometheus \
  -o yaml | grep -A3 "serviceMonitorSelector"
```

Your ServiceMonitor must have the matching label (usually `release: prometheus`).

#### 5. Verify Target Discovery

```bash
# Query Prometheus directly
curl -s "http://<prometheus-ip>:9090/api/v1/targets" | \
  jq '.data.activeTargets[] | select(.labels.namespace=="rag-app")'
```

#### 6. Check Prometheus Config

```bash
curl -s "http://<prometheus-ip>:9090/api/v1/status/config" | \
  jq -r '.data.yaml' | grep -A20 "rag"
```

#### 7. Wait and Retry

After creating/updating a ServiceMonitor, Prometheus takes 30-60 seconds to reload. Run a quick test:

```bash
# Wait and check
sleep 45
curl -s "http://<prometheus-ip>:9090/api/v1/query?query=rag_requests_total" | jq '.data.result | length'
```

If it returns `0`, the scraping isn't working yet.

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
