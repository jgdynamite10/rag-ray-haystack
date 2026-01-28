# Observability Guide

This document covers the Prometheus and Grafana setup for monitoring the RAG system.

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


                    Option B: Central Grafana
                    (For cross-cluster comparison)

┌─────────────────────────────────────────────────────────────────────────────┐
│                        Central Grafana VM                                   │
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

## What's Deployed

The `kube-prometheus-stack` Helm chart deploys:

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| Prometheus | monitoring | Scrapes and stores metrics |
| Grafana | monitoring | Visualizes metrics (in-cluster) |
| Alertmanager | monitoring | Handles alerts (optional) |
| Node Exporter | monitoring | Host-level metrics |
| Kube State Metrics | monitoring | Kubernetes object metrics |

## Accessing Components

### Check Pod Status

```bash
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
kubectl -n monitoring get pods
```

Expected output:
```
NAME                                                     READY   STATUS    RESTARTS   AGE
prometheus-kube-prometheus-operator-xxx                  1/1     Running   0          5m
prometheus-prometheus-kube-prometheus-prometheus-0       2/2     Running   0          5m
prometheus-grafana-xxx                                   3/3     Running   0          5m
prometheus-kube-state-metrics-xxx                        1/1     Running   0          5m
prometheus-prometheus-node-exporter-xxx                  1/1     Running   0          5m
```

### Access In-Cluster Grafana

**Option 1: Port Forward (Quick Access)**
```bash
# Get Grafana pod
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80

# Open http://localhost:3000
# Username: admin
# Password: (see below)
```

**Get Grafana Password:**
```bash
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
kubectl -n monitoring get secret prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d; echo
```

**Option 2: LoadBalancer (Persistent Access)**
```bash
# Patch Grafana service to LoadBalancer
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
kubectl -n monitoring patch svc prometheus-grafana -p '{"spec": {"type": "LoadBalancer"}}'

# Get external IP
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
kubectl -n monitoring get svc prometheus-grafana
```

### Access Prometheus

**Port Forward:**
```bash
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090

# Open http://localhost:9090
```

**Get External IP (for Central Grafana):**
```bash
# Check current service type
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
kubectl -n monitoring get svc prometheus-kube-prometheus-prometheus

# If ClusterIP, patch to LoadBalancer
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
kubectl -n monitoring patch svc prometheus-kube-prometheus-prometheus \
  -p '{"spec": {"type": "LoadBalancer"}}'
```

## Metrics Exposed by RAG Backend

The RAG backend exposes metrics at `/metrics`:

### Request Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `rag_requests_total` | Counter | Total requests by endpoint |
| `rag_errors_total` | Counter | Total errors by endpoint |

### Latency Metrics (Histograms)

| Metric | Labels | Description |
|--------|--------|-------------|
| `rag_latency_seconds` | `stage` | Latency by stage (embedding, retrieval, generation, total) |
| `rag_ttft_seconds` | - | Time to first token |
| `rag_tpot_seconds` | - | Time per output token |
| `rag_tokens_per_second` | - | Token generation rate |

### Token Metrics

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
```

## Configuring Prometheus to Scrape RAG Backend

The kube-prometheus-stack uses ServiceMonitors. Create one for the RAG backend:

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

### Verify Scraping

1. Open Prometheus UI: `http://localhost:9090` (via port-forward)
2. Go to Status → Targets
3. Look for `rag-backend` target
4. Should show `UP` status

## Grafana Dashboards

### Pre-configured Dashboards

Located in `grafana/dashboards/`:

| Dashboard | File | Description |
|-----------|------|-------------|
| RAG Overview | `rag-overview.json` | TTFT, TPOT, latency, throughput, errors |
| Provider Comparison | `provider-comparison.json` | Side-by-side provider metrics |
| vLLM Metrics | `vllm-metrics.json` | vLLM inference server metrics |
| GPU Utilization | `gpu-utilization.json` | DCGM GPU metrics |

### Import Dashboards to In-Cluster Grafana

1. Access Grafana (port-forward or LoadBalancer)
2. Go to Dashboards → Import
3. Upload JSON file or paste contents
4. Select Prometheus datasource

### Dashboard Variables

All dashboards support:
- **Datasource**: Select Prometheus instance
- **Provider**: Filter by provider label (akamai-lke, aws-eks, gcp-gke)

## External Labels

Prometheus is configured with external labels for cross-cluster identification:

```yaml
prometheus:
  prometheusSpec:
    externalLabels:
      provider: "akamai-lke"  # Identifies this cluster
      region: "us-ord"
      cluster: "rag-ray-dev"
```

These labels are added to all metrics, enabling provider-based filtering in Grafana.

## Central Grafana Setup

For cross-cluster comparison, deploy a central Grafana that queries multiple Prometheus instances.

See: `docs/CENTRAL_MONITORING.md`

### Quick Setup

1. **Expose Prometheus externally** (each cluster):
   ```bash
   kubectl -n monitoring patch svc prometheus-kube-prometheus-prometheus \
     -p '{"spec": {"type": "LoadBalancer"}}'
   ```

2. **Deploy Central Grafana** (on a VM):
   ```bash
   cd deploy/monitoring
   cp env.example .env
   # Edit .env with Prometheus URLs
   docker-compose up -d
   ```

3. **Access Central Grafana**: `http://<vm-ip>:3000`

## Troubleshooting

### Prometheus Not Scraping RAG Backend

1. Check ServiceMonitor exists:
   ```bash
   kubectl -n monitoring get servicemonitor rag-backend
   ```

2. Check labels match:
   ```bash
   kubectl -n rag-app get svc -l app=rag-app-backend --show-labels
   ```

3. Check Prometheus targets:
   - Port-forward to Prometheus
   - Go to Status → Targets
   - Look for errors

### No Data in Grafana

1. Verify Prometheus has data:
   ```promql
   rag_requests_total
   ```

2. Check time range (metrics need time to accumulate)

3. Verify datasource is configured correctly

### Metrics Missing Provider Label

Ensure `externalLabels` is set in Prometheus config:
```bash
kubectl -n monitoring get prometheus prometheus-kube-prometheus-prometheus -o yaml | grep -A5 externalLabels
```

## Security Considerations

### Prometheus Access

- Default: ClusterIP (internal only)
- LoadBalancer: Exposes to internet - add firewall rules
- Consider using Ingress with authentication

### Grafana Access

- Change default password immediately
- Use Ingress with TLS for production
- Consider OAuth/LDAP integration

## Maintenance

### Upgrade Prometheus Stack

```bash
helm repo update
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f deploy/monitoring/prometheus-values.yaml
```

### View Prometheus Logs

```bash
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
kubectl -n monitoring logs -l app.kubernetes.io/name=prometheus -f
```

### Check Storage Usage

```bash
KUBECONFIG=~/.kube/rag-ray-haystack-kubeconfig.yaml \
kubectl -n monitoring exec -it prometheus-prometheus-kube-prometheus-prometheus-0 \
  -- df -h /prometheus
```
