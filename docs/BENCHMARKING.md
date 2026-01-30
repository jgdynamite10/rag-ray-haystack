# Benchmarking Guide

This document explains the different ways to measure RAG system performance and when to use each method.

---

## Quick Start: Populate ITDM Dashboard

### Complete Workflow (4 Steps)

```bash
# Step 1: Setup Python environment (one-time)
cd ~/Documents/new-projects/rag-ray-haystack
python3 -m venv .venv
source .venv/bin/activate
pip install -r scripts/benchmark/requirements.txt

# Step 2: Ingest a document (required for retrieval metrics)
# Option A: Via UI - Open http://<PUBLIC_IP> and upload a PDF/text file
# Option B: Via API
curl -X POST "http://<PUBLIC_IP>/api/ingest" \
  -F "file=@/path/to/your/document.pdf"

# Step 3: Run East-West probe (in-cluster network metrics)
# Metrics are pushed to Pushgateway automatically from inside the cluster
./scripts/netprobe/run_ew.sh --provider akamai-lke

# Step 4: Run North-South benchmark (all LLM metrics)
./scripts/benchmark/run_ns.sh akamai-lke \
  --url http://<PUBLIC_IP>/api/query/stream \
  --requests 100 \
  --max-output-tokens 256
```

### What Each Step Populates

| Step | Metrics Populated |
|------|-------------------|
| **Step 2: Document Ingestion** | `rag_k_retrieved` (retrieval count) |
| **Step 3: East-West Probe** | `ew_tcp_throughput_gbps`, `ew_tcp_retransmits`, `ew_udp_jitter_ms`, `ew_latency_avg_ms` |
| **Step 4: North-South Benchmark** | `rag_ttft_seconds`, `rag_tpot_seconds`, `rag_latency_seconds`, `rag_tokens_total`, `rag_requests_total` |

### Why Document Ingestion Matters

The benchmark queries the RAG system, which:
1. **Embeds** your query → embedding latency
2. **Retrieves** relevant documents from Qdrant → `rag_k_retrieved` metric
3. **Generates** response via vLLM → TTFT, TPOT, tokens/sec

**Without documents ingested**, the retrieval step returns 0 documents and `rag_k_retrieved` will be empty.

---

## Test Profiles

### Light Test (Quick Sanity Check)
**Use case:** Verify system is working, ~30 seconds

```bash
./scripts/benchmark/run_ns.sh akamai-lke \
  --url http://172.236.105.4/api/query/stream \
  --requests 20 \
  --concurrency 5 \
  --warmup 5 \
  --max-output-tokens 128
```

| Parameter | Value | Purpose |
|-----------|-------|---------|
| requests | 20 | Quick validation |
| concurrency | 5 | Light parallel load |
| warmup | 5 | Minimal warmup |
| max-output-tokens | 128 | Short responses |

### Standard Test (Default Benchmark)
**Use case:** Regular benchmarking, ~2-3 minutes

```bash
./scripts/benchmark/run_ns.sh akamai-lke \
  --url http://172.236.105.4/api/query/stream \
  --requests 100 \
  --concurrency 10 \
  --warmup 10 \
  --max-output-tokens 256
```

| Parameter | Value | Purpose |
|-----------|-------|---------|
| requests | 100 | Statistically meaningful |
| concurrency | 10 | Typical multi-user load |
| warmup | 10 | Proper cache warming |
| max-output-tokens | 256 | Standard response length |

### Load Test (High Concurrency)
**Use case:** Test system under heavy load, ~5-10 minutes

```bash
./scripts/benchmark/run_ns.sh akamai-lke \
  --url http://172.236.105.4/api/query/stream \
  --requests 500 \
  --concurrency 50 \
  --warmup 20 \
  --max-output-tokens 256
```

| Parameter | Value | Purpose |
|-----------|-------|---------|
| requests | 500 | Large sample size |
| concurrency | 50 | Heavy parallel load |
| warmup | 20 | Thorough warmup |
| max-output-tokens | 256 | Consistent responses |

### Stress Test (Maximum Load)
**Use case:** Find breaking point, ~15-30 minutes

```bash
./scripts/benchmark/run_ns.sh akamai-lke \
  --url http://172.236.105.4/api/query/stream \
  --requests 1000 \
  --concurrency 100 \
  --warmup 50 \
  --max-output-tokens 256 \
  --timeout 300
```

| Parameter | Value | Purpose |
|-----------|-------|---------|
| requests | 1000 | Stress volume |
| concurrency | 100 | Maximum parallel requests |
| warmup | 50 | Extended warmup |
| timeout | 300 | Allow for queueing delays |

**Warning:** Stress tests may cause GPU memory pressure and request failures. Monitor GPU utilization in Grafana.

---

## How Warmup Works

```
┌─────────────────────────────────────────────────────────────┐
│  Phase 1: WARMUP (--warmup 10)                             │
│  - Runs 10 requests                                         │
│  - Results DISCARDED (not counted in metrics)              │
│  - Purpose: Prime caches, warm up GPU, stabilize vLLM      │
├─────────────────────────────────────────────────────────────┤
│  Phase 2: MEASURED (--requests 100)                        │
│  - Runs 100 requests at --concurrency 10                   │
│  - Results RECORDED for TTFT, TPOT, latency, etc.          │
│  - This is what appears in dashboard and JSON output       │
└─────────────────────────────────────────────────────────────┘
```

**Why warmup matters:**
- First requests after deployment are slower (cold GPU, empty KV cache)
- Warmup ensures measured results reflect steady-state performance
- Industry standard practice for LLM benchmarking

---

## Concurrency Guide

| Concurrency | Simulates | Expected Behavior |
|-------------|-----------|-------------------|
| 1 | Single user | Baseline latency, no queueing |
| 5 | Small team | Light load, minimal queueing |
| 10 | Standard app | Typical production load |
| 25 | Busy app | Moderate queueing on GPU |
| 50 | High traffic | Significant queueing, higher latency |
| 100 | Stress test | May hit GPU memory limits |

**Tip:** Compare p50 vs p95 latency. Large gaps indicate queueing under load.

---

### What Gets Populated

| ITDM Panel | Metric | Populated By |
|------------|--------|--------------|
| TTFT p50/p95 | `rag_ttft_seconds` | North-South benchmark |
| TPOT p50/p95 | `rag_tpot_seconds` | North-South benchmark |
| Latency p50/p95 | `rag_latency_seconds` | North-South benchmark |
| Tokens/sec | `rag_tokens_per_second` | North-South benchmark |
| Requests/sec | `rag_requests_total` | North-South benchmark |
| Error Rate | `rag_errors_total` | North-South benchmark |
| Avg k Retrieved | `rag_k_retrieved` | North-South benchmark |
| GPU Utilization | `DCGM_FI_DEV_GPU_UTIL` | DCGM exporter (automatic) |
| GPU Memory | `DCGM_FI_DEV_FB_USED` | DCGM exporter (automatic) |
| GPU Temperature | `DCGM_FI_DEV_GPU_TEMP` | DCGM exporter (automatic) |
| GPU Power | `DCGM_FI_DEV_POWER_USAGE` | DCGM exporter (automatic) |
| Cost Metrics | Calculated from above | Dashboard variables (manual input) |

### Requirements

1. **RAG app deployed** with documents ingested
2. **Prometheus scraping** the backend `/metrics` endpoint
3. **DCGM ServiceMonitor** applied (for GPU metrics)
4. **Grafana** with ITDM dashboard imported

### Provider-Specific Commands

```bash
# Akamai LKE
./scripts/benchmark/run_ns.sh akamai-lke --url http://172.236.105.4/api/query/stream

# AWS EKS (when deployed)
./scripts/benchmark/run_ns.sh aws-eks --url http://<eks-lb-ip>/api/query/stream

# GCP GKE (when deployed)
./scripts/benchmark/run_ns.sh gcp-gke --url http://<gke-lb-ip>/api/query/stream
```

### Verify Metrics in Prometheus

```bash
# Port-forward to Prometheus
kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090

# Check metrics exist
curl -s "http://localhost:9090/api/v1/query?query=rag_ttft_seconds_count" | jq '.data.result | length'
# Should return > 0
```

## Overview of Measurement Methods

| Method | Location | Concurrency | Use Case |
|--------|----------|-------------|----------|
| **UI Floating Widget** | Browser | 1 (your request) | Real-time feedback during chat |
| **UI Rolling Metrics** | Browser | 1 (sequential) | Session-level trends |
| **UI Performance Snapshot** | Server `/stats` | Aggregated | Server-side health check |
| **In-cluster Benchmark** | K8s Job | Configurable | Isolate cluster performance |
| **North-South Benchmark** | External client | Configurable | Real-world user experience |

---

## UI Metrics (Single-User, Real-Time)

### Floating Widget (Footer Bar)

The footer bar shows metrics for your **current or last request**:

```
Provider: akamai-lke | Latency: 10234ms (retrieval 45ms, generation 10189ms) | TTFT: 82ms | Tokens/sec: 45.2
```

| Metric | What it measures |
|--------|------------------|
| **Latency** | Total time from clicking Send to response complete |
| **TTFT** | Time from clicking Send to first token appearing |
| **Tokens/sec** | Generation speed during streaming |

**Use case:** Quick feedback while chatting. See how the system responds to your specific query.

### Rolling Metrics Panel

Aggregates the **last 20 requests** from your chat session:

```
TTFT p50: 82ms | TTFT p95: 479ms | Total p50: 10234ms | Total p95: 11761ms
Avg tokens/sec: 43.78 | Success: 20 | Errors: 0
```

**Use case:** Track consistency during a session. Spot degradation over time.

### Performance Snapshot

Server-side aggregated metrics from the `/stats` endpoint:

```
ingest: embed + store documents
retrieval: fetch relevant docs  
generation: model response time
ttft: time to first token
```

**Use case:** Server health check. See aggregate performance across all users.

---

## Benchmark Methods (Multi-User, Load Testing)

### In-Cluster Benchmark (`/benchmark/run`)

Runs a Kubernetes Job **inside the cluster** that sends concurrent requests to the backend.

**Trigger:** UI "Run benchmark" button or API call

```bash
curl -X POST http://backend:8000/benchmark/run \
  -H "Content-Type: application/json" \
  -d '{"requests": 100, "concurrency": 10, "warmup_requests": 5}'
```

**What it measures:**
- Pod-to-pod latency (no external network)
- Backend + vLLM performance in isolation
- Kubernetes networking overhead

**Output (Phase 2 format):**
```json
{
  "requests": 100,
  "success": 100,
  "ttft_p50_ms": 62.6,
  "ttft_p95_ms": 255.0,
  "tpot_p50_ms": 21.6,
  "tpot_p95_ms": 21.7,
  "latency_p50_ms": 10250.4,
  "latency_p95_ms": 11140.0,
  "avg_tokens_per_sec": 45.86,
  "phases": {
    "warmup": { ... },
    "measured": { ... }
  },
  "run_metadata": { ... }
}
```

**Use case:** Isolate cluster performance. Compare providers without network variable.

---

### North-South Benchmark (`stream_bench.py`)

Runs from an **external client** (your laptop, CI runner) and hits the public endpoint.

```
    ┌──────────────────┐
    │   Your Laptop    │  ← Client (North)
    │  stream_bench.py │
    └────────┬─────────┘
             │
             │  Internet / Load Balancer
             │
             ▼
    ┌──────────────────┐
    │   Kubernetes     │  ← Cluster (South)
    │   (RAG System)   │
    └──────────────────┘
```

**Run:**
```bash
cd scripts/benchmark

# Basic run
python stream_bench.py \
  --url "https://your-cluster.com/api/query/stream" \
  --requests 100 \
  --concurrency 10

# With warmup and output file
python stream_bench.py \
  --url "https://your-cluster.com/api/query/stream" \
  --requests 100 \
  --concurrency 10 \
  --warmup-requests 10 \
  --json-out results.json
```

**What it measures:**
- End-to-end latency including internet/load balancer
- Real-world user experience
- Full network path performance

**Use case:** Measure what users actually experience. Compare across regions/providers.

---

## Comparison: UI vs Benchmarks

| Aspect | UI Metrics | In-Cluster Benchmark | North-South Benchmark |
|--------|------------|---------------------|----------------------|
| **Concurrency** | 1 (your browser) | Configurable (e.g., 10) | Configurable (e.g., 10) |
| **Network path** | Browser → LB → Cluster | Pod → Pod | Client → Internet → LB → Cluster |
| **Measures** | Your requests | Cluster capacity | User experience |
| **TPOT metric** | ❌ | ✅ | ✅ |
| **Warmup phase** | ❌ | ✅ | ✅ |
| **JSON output** | ❌ | ✅ | ✅ |
| **Automation** | Manual | API-triggered | Script/CI |

---

## When to Use Each Method

### During Development
- **UI Floating Widget** - Quick sanity check while building features
- **In-cluster Benchmark** - Test changes without network noise

### Before Release
- **In-cluster Benchmark** - Establish baseline performance
- **North-South Benchmark** - Validate user experience

### Cross-Provider Comparison
- **North-South Benchmark** - Compare LKE vs EKS vs GKE from same client location
- **In-cluster Benchmark** - Compare cluster-internal performance

### Production Monitoring
- **UI Performance Snapshot** - Real-time health dashboard
- **Grafana Dashboards** - Historical trends from Prometheus metrics

---

## Output Length Control

For consistent, reproducible benchmarks, control the maximum output tokens:

```bash
# Standalone script
python stream_bench.py --url http://... --max-output-tokens 256

# Wrapper script
./scripts/benchmark/run_ns.sh akamai-lke --url http://... --max-output-tokens 256

# In-cluster API
curl -X POST http://.../benchmark/run \
  -d '{"requests": 100, "max_output_tokens": 256}'
```

**Why this matters:**
- Without limits, models generate variable-length responses
- Variable output = inconsistent TPOT, latency, and tokens/sec measurements
- Set the same `max_output_tokens` across all benchmark runs for fair comparison

**Recommended values:**
| Use Case | max_output_tokens |
|----------|-------------------|
| Quick test | 128 |
| Standard benchmark | 256 |
| Long-form generation | 512 |
| Stress test | 1024 |

---

## Grafana Dashboards

### ITDM Unified Dashboard

The **ITDM - Unified Dashboard** (`grafana/dashboards/itdm-unified.json`) provides a single view for:

1. **Key Performance Metrics** - TTFT, TPOT, Latency, Tokens/sec, Requests/sec, Error Rate
2. **Cost Analysis** - Provider-specific pricing with editable inputs (LKE, EKS, GKE)
3. **Provider Comparison** - Side-by-side charts comparing all 3 providers
4. **Latency Breakdown** - Attribution by stage (embedding, retrieval, generation)

**Import the dashboard:**
1. Open Grafana (http://172.239.55.129:3000 for central instance)
2. **Dashboards** → **New** → **Import**
3. Upload `grafana/dashboards/itdm-unified.json`
4. Select your Prometheus datasource(s)

**Cost Variables (editable dropdowns at top):**
| Provider | GPU $/hr | CPU $/hr | Mgmt $/hr |
|----------|----------|----------|-----------|
| Akamai LKE | $1.50 (RTX 4090) | $0.036 | $0 |
| AWS EKS | $0.80 (g5.xlarge) | $0.096 | $0.10 |
| GCP GKE | $0.94 (T4) | $0.067 | $0.10 |

---

## Metrics Reference

### Interactive LLM Metrics (ITDMs)

| Metric | Definition | Good Value |
|--------|------------|------------|
| **TTFT** | Time To First Token - latency until first token appears | < 500ms |
| **TPOT** | Time Per Output Token - avg time to generate each subsequent token | < 50ms |
| **Total Latency** | Full request-response time | Varies by output length |
| **Tokens/sec** | Generation throughput | > 30 tokens/sec |

### Percentiles

| Percentile | Meaning |
|------------|---------|
| **p50** | Median - 50% of requests are faster |
| **p95** | 95th percentile - 95% of requests are faster (captures tail latency) |

---

## Output Schema (Phase 2)

```json
{
  "requests": 100,
  "concurrency": 10,
  "success": 98,
  "errors": 2,
  
  "ttft_p50_ms": 82.0,
  "ttft_p95_ms": 479.5,
  "latency_p50_ms": 10234.0,
  "latency_p95_ms": 11761.8,
  "tpot_p50_ms": 21.6,
  "tpot_p95_ms": 23.4,
  
  "avg_tokens_per_sec": 43.78,
  "total_tokens": 8756,
  "avg_output_tokens": 87.6,
  
  "phases": {
    "warmup": {
      "requests": 10,
      "success": 10,
      "ttft_p50_ms": 95.0,
      "phase": "warmup"
    },
    "measured": {
      "requests": 100,
      "success": 98,
      "ttft_p50_ms": 82.0,
      "phase": "measured"
    }
  },
  
  "duration_seconds": 125.3,
  "warmup_requests": 10,
  "measured_requests": 100,
  "max_output_tokens": 256,
  
  "workload_manifest_path": null,
  "workload_manifest_hash": null,
  
  "run_metadata": {
    "provider": "akamai-lke",
    "region": "us-ord",
    "cluster_label": "rag-ray-dev",
    "model_id": "Qwen/Qwen3-1.7B",
    "timestamp": "2026-01-28T01:27:25.427935+00:00"
  }
}
```

---

## Quick Reference

```bash
# North-South benchmark from laptop
python scripts/benchmark/stream_bench.py \
  --url "https://your-app.com/api/query/stream" \
  --requests 100 \
  --concurrency 10 \
  --warmup-requests 10 \
  --max-output-tokens 256 \
  --json-out benchmarks/ns/$(date +%Y-%m-%dT%H%M%S).json

# Using the wrapper script (recommended)
./scripts/benchmark/run_ns.sh akamai-lke \
  --url "https://your-app.com/api/query/stream" \
  --requests 100 \
  --max-output-tokens 256 \
  --with-cost

# Trigger in-cluster benchmark via API
curl -X POST https://your-app.com/api/benchmark/run \
  -H "Content-Type: application/json" \
  -d '{"requests": 100, "concurrency": 10, "warmup_requests": 10, "max_output_tokens": 256}'

# Check benchmark status
curl "https://your-app.com/api/benchmark/status?job=rag-stream-bench-abc123"

# Get benchmark logs
curl "https://your-app.com/api/benchmark/logs?job=rag-stream-bench-abc123"
```
