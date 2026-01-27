# Observability Guide

This document describes how to set up observability for cross-provider benchmarking and comparison.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Each Cluster                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Backend   │  │    vLLM     │  │   DCGM Exporter     │  │
│  │  /metrics   │  │  /metrics   │  │   (GPU metrics)     │  │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘  │
│         │                │                     │             │
│         └────────────────┼─────────────────────┘             │
│                          │                                   │
│                   ┌──────▼──────┐                            │
│                   │ Prometheus  │                            │
│                   │ (per-cluster)│                           │
│                   └──────┬──────┘                            │
│                          │                                   │
│                   ┌──────▼──────┐                            │
│                   │  Grafana    │                            │
│                   │(per-cluster)│                            │
│                   └─────────────┘                            │
└─────────────────────────────────────────────────────────────┘
```

For cross-cluster comparison, either:
1. Run a central Grafana that queries multiple Prometheus instances
2. Use Grafana Cloud or similar aggregation service
3. Export benchmark results JSON and compare offline

## Quick Start: Deploy Prometheus + Grafana

### Option 1: kube-prometheus-stack (Recommended)

```bash
# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install with custom values
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f deploy/monitoring/prometheus-values.yaml
```

Create `deploy/monitoring/prometheus-values.yaml`:

```yaml
prometheus:
  prometheusSpec:
    # Scrape our app metrics
    additionalScrapeConfigs:
      - job_name: 'rag-backend'
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names: ['rag-app']
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_app]
            regex: rag-app-backend
            action: keep
          - source_labels: [__meta_kubernetes_pod_container_port_number]
            regex: "8000"
            action: keep
      - job_name: 'vllm'
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names: ['rag-app']
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_app]
            regex: rag-app-vllm
            action: keep
          
    # Add external labels for cross-cluster identification
    externalLabels:
      provider: "akamai-lke"  # or aws-eks, gcp-gke
      cluster: "rag-ray-dev"
      region: "us-ord"

grafana:
  adminPassword: "admin"  # Change in production
  
  # Import our dashboards
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'rag-dashboards'
          folder: 'RAG Benchmarking'
          type: file
          disableDeletion: false
          options:
            path: /var/lib/grafana/dashboards/rag
            
  dashboardsConfigMaps:
    rag: "rag-grafana-dashboards"
```

### Option 2: Minimal Prometheus + Grafana

```bash
# Prometheus
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml

# Grafana
helm repo add grafana https://grafana.github.io/helm-charts
helm upgrade --install grafana grafana/grafana \
  --namespace monitoring --create-namespace \
  --set adminPassword=admin
```

## Metrics Sources

### 1. Backend Application Metrics (/metrics)

The RAG backend exposes Prometheus metrics at `/metrics`:

| Metric | Type | Description |
|--------|------|-------------|
| `rag_requests_total` | Counter | Total requests by endpoint |
| `rag_request_duration_seconds` | Histogram | Request latency |
| `rag_tokens_generated_total` | Counter | Total tokens generated |
| `rag_ttft_seconds` | Histogram | Time to first token |
| `rag_retrieval_duration_seconds` | Histogram | Qdrant retrieval time |
| `rag_generation_duration_seconds` | Histogram | LLM generation time |

### 2. vLLM Metrics

vLLM exposes metrics at port 8000 (if enabled):

| Metric | Description |
|--------|-------------|
| `vllm:num_requests_running` | Currently processing requests |
| `vllm:num_requests_waiting` | Queued requests |
| `vllm:gpu_cache_usage_perc` | KV cache utilization |
| `vllm:avg_prompt_throughput_toks_per_s` | Input token throughput |
| `vllm:avg_generation_throughput_toks_per_s` | Output token throughput |

### 3. DCGM GPU Metrics

Deploy DCGM exporter for GPU metrics:

```bash
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts
helm upgrade --install dcgm-exporter gpu-helm-charts/dcgm-exporter \
  --namespace monitoring --create-namespace
```

Key metrics:

| Metric | Description |
|--------|-------------|
| `DCGM_FI_DEV_GPU_UTIL` | GPU utilization % |
| `DCGM_FI_DEV_MEM_COPY_UTIL` | Memory copy utilization % |
| `DCGM_FI_DEV_FB_USED` | Framebuffer memory used |
| `DCGM_FI_DEV_FB_FREE` | Framebuffer memory free |
| `DCGM_FI_DEV_POWER_USAGE` | Power consumption (watts) |
| `DCGM_FI_DEV_GPU_TEMP` | GPU temperature |

### 4. k6 Load Test Metrics

For external load testing with k6:

```bash
# Run k6 with Prometheus output
k6 run --out experimental-prometheus-rw \
  -e K6_PROMETHEUS_RW_SERVER_URL=http://prometheus:9090/api/v1/write \
  scripts/benchmark-k6.js
```

Or use the pushgateway pattern:

```bash
k6 run --out json=results.json scripts/benchmark-k6.js

# Then push to Prometheus pushgateway
curl -X POST http://pushgateway:9091/metrics/job/k6 \
  --data-binary @results.json
```

## Dashboard Templates

Dashboard JSON files are in `grafana/dashboards/`:

| Dashboard | Description |
|-----------|-------------|
| `rag-overview.json` | High-level RAG system metrics |
| `vllm-metrics.json` | vLLM inference performance |
| `gpu-utilization.json` | DCGM GPU metrics |
| `benchmark-results.json` | Load test results comparison |

### Import Dashboards

1. Open Grafana UI
2. Go to Dashboards → Import
3. Upload JSON file or paste contents
4. Select Prometheus data source
5. Click Import

### Deploy via ConfigMap

```bash
kubectl create configmap rag-grafana-dashboards \
  --from-file=grafana/dashboards/ \
  --namespace monitoring
```

## Cross-Cluster Comparison

### Option A: Multi-Datasource Grafana

Configure Grafana with multiple Prometheus datasources:

1. Add datasource for each cluster:
   - Name: `prometheus-lke`
   - URL: `http://prometheus-lke.monitoring:9090`
   
2. Use dashboard variables to switch between datasources

### Option B: Prometheus Federation

Central Prometheus scrapes from cluster Prometheus instances:

```yaml
# Central prometheus.yml
scrape_configs:
  - job_name: 'federate-lke'
    honor_labels: true
    metrics_path: '/federate'
    params:
      'match[]':
        - '{job=~"rag-backend|vllm"}'
    static_configs:
      - targets: ['prometheus-lke.external:9090']
        labels:
          provider: 'akamai-lke'
```

### Option C: Offline Comparison

Export benchmark results and compare locally:

```bash
# Run benchmarks on each cluster
./scripts/bench/run_ns.sh --endpoint http://lke-endpoint/api --provider akamai-lke
./scripts/bench/run_ns.sh --endpoint http://eks-endpoint/api --provider aws-eks
./scripts/bench/run_ns.sh --endpoint http://gke-endpoint/api --provider gcp-gke

# Compare results
ls benchmarks/ns/*/
```

## Labeling Convention

For consistent cross-cluster comparison, use these labels:

| Label | Example Values | Description |
|-------|---------------|-------------|
| `provider` | akamai-lke, aws-eks, gcp-gke | Cloud provider |
| `cluster` | rag-ray-dev, rag-ray-prod | Cluster name |
| `region` | us-ord, us-east-1, us-central1 | Deployment region |
| `environment` | dev, staging, prod | Environment tier |

Configure in Prometheus `externalLabels` or via relabeling.

## Alerting (Optional)

Example alert rules:

```yaml
groups:
  - name: rag-alerts
    rules:
      - alert: HighTTFT
        expr: histogram_quantile(0.95, rate(rag_ttft_seconds_bucket[5m])) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High TTFT p95 ({{ $value }}s)"
          
      - alert: HighErrorRate
        expr: rate(rag_requests_total{status="error"}[5m]) / rate(rag_requests_total[5m]) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Error rate above 5%"
          
      - alert: GPUMemoryHigh
        expr: DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "GPU memory utilization above 90%"
```

## Troubleshooting

### Metrics not appearing

1. Check service discovery:
   ```bash
   kubectl port-forward svc/prometheus 9090:9090 -n monitoring
   # Open http://localhost:9090/targets
   ```

2. Verify pod labels match scrape config:
   ```bash
   kubectl get pods -n rag-app --show-labels
   ```

### DCGM exporter not finding GPUs

1. Verify GPU nodes:
   ```bash
   kubectl get nodes -l nvidia.com/gpu.present=true
   ```

2. Check DCGM pods:
   ```bash
   kubectl logs -n monitoring -l app=dcgm-exporter
   ```

### Cross-cluster datasource errors

1. Verify network connectivity between clusters
2. Check Prometheus API accessibility
3. Ensure external labels are configured
