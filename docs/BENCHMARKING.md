# Benchmarking Guide

This document explains the different ways to measure RAG system performance and when to use each method.

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
  --json-out benchmarks/ns/$(date +%Y-%m-%dT%H%M%S).json

# Trigger in-cluster benchmark via API
curl -X POST https://your-app.com/api/benchmark/run \
  -H "Content-Type: application/json" \
  -d '{"requests": 100, "concurrency": 10, "warmup_requests": 10}'

# Check benchmark status
curl "https://your-app.com/api/benchmark/status?job=rag-stream-bench-abc123"

# Get benchmark logs
curl "https://your-app.com/api/benchmark/logs?job=rag-stream-bench-abc123"
```
