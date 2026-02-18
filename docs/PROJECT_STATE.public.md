# Project State (Public)

This file is safe to publish. Keep it sanitized and avoid sensitive details.

## Current Status

**Phase 1: Core Infrastructure** - ✅ Complete
**Phase 2: Measurement Rigor** - ✅ Complete (core features)

### What's Working

| Component | Status | Notes |
|-----------|--------|-------|
| Helm/Kustomize deployment | ✅ | Backend, frontend, Qdrant, RayService, vLLM |
| GPU inference (vLLM) | ✅ | Runs on GPU nodes with `nvidia.com/gpu` |
| North-South benchmark | ✅ | `run_ns.sh` with warmup phases, TPOT |
| East-West probe | ✅ | `run_ew.sh` for in-cluster network (needs tuning per cluster) |
| Cost model | ✅ | Per-provider configs, cost computation |
| Central Grafana | ✅ | Multi-cluster observability |
| ITDM Dashboard | ✅ | Unified 3-provider comparison |

### Images

| Image | Tag | Notes |
|-------|-----|-------|
| Backend | 0.3.9 | Fixes benchmark_logs KeyError from 0.3.8, K8s token rotation fix, TPOT metrics, max_output_tokens, k_retrieved histogram. Includes `qdrant-client==1.16.2` |
| Frontend | 0.3.5 | SSE streaming with metrics (0.3.7 has regression) |
| Qdrant | v1.12.6 | **Must be >= v1.10.0** for backend 0.3.9 (`/points/query` API). v1.8.4 causes query 404 |

### Provider Deployment Status

| Provider | Status | Endpoint | Notes |
|----------|--------|----------|-------|
| Akamai LKE | ✅ Deployed | http://<LKE-FRONTEND-IP> | Load tested |
| AWS EKS | ✅ Deployed | ELB endpoint | Ready for benchmarks |
| GCP GKE | ✅ Deployed | http://<GKE-FRONTEND-IP> | `e2-standard-2` CPU + `g2-standard-8` GPU. See DEPLOYMENT.md for shared-core caveat |

---

## Benchmark Tools

### North-South Benchmark (Client → Service)

```bash
# Basic usage
./scripts/benchmark/run_ns.sh <provider> --url <endpoint>

# With all options
./scripts/benchmark/run_ns.sh akamai-lke \
  --url http://<public-ip>/api/query/stream \
  --requests 100 \
  --warmup-requests 10 \
  --concurrency 10 \
  --max-output-tokens 256 \
  --with-cost
```

**Output:** `benchmarks/ns/<provider>/<timestamp>.json`

### East-West Probe (In-Cluster Network)

```bash
./scripts/netprobe/run_ew.sh --provider akamai-lke --kubeconfig ~/.kube/lke.yaml
```

**Measures:** TCP throughput (Gbps), UDP jitter, TCP latency
**Output:** `benchmarks/ew/<provider>/<timestamp>.json`

**LKE Results (2026-01-29):**
| Metric | Value |
|--------|-------|
| TCP Throughput | ~1.0 Gbps |
| TCP Retransmits | ~1500-2000 |
| Cross-node confirmed | Yes |
| Server Node | lke*-*-gpu-node |
| Client Node | lke*-*-cpu-node |

### Cost Computation

```bash
python scripts/cost/compute_cost.py \
  --benchmark benchmarks/ns/akamai-lke/2026-01-28.json \
  --cost-config cost/akamai-lke.yaml
```

---

## Benchmark Results

### AWS EKS (2026-01-30) - Load Test

| Metric | Value |
|--------|-------|
| Requests | 500 (measured) |
| Warmup | 20 |
| Concurrency | 50 |
| Success Rate | 100% (500/500) |
| TTFT p50 | 536 ms |
| TTFT p95 | 3,314 ms |
| TPOT p50 | 57.6 ms |
| TPOT p95 | 60.3 ms |
| Latency p50 | 15,276 ms |
| Latency p95 | 17,228 ms |
| Avg tokens/sec | 16.5 |
| Duration | 152 seconds |

**East-West Network (AWS EKS):**
| Metric | Value |
|--------|-------|
| TCP Throughput | 4.96 Gbps |
| TCP Retransmits | 173 |
| Cross-node | Yes |

### LKE (2026-01-29) - Load Test

### Load Test (High Concurrency)

| Metric | Value |
|--------|-------|
| Requests | 500 (measured) |
| Warmup | 20 |
| Concurrency | 50 |
| Success Rate | 97.4% (487/500) |
| TTFT p50 | 1,112 ms |
| TTFT p95 | 4,012 ms |
| TPOT p50 | 47.5 ms |
| TPOT p95 | 56.4 ms |
| Latency p50 | 12,932 ms |
| Latency p95 | 16,530 ms |
| Avg tokens/sec | 19.5 |
| Avg output tokens | 255.8 |
| Duration | 180 seconds |

### Standard Test (For Reference)

| Metric | Value |
|--------|-------|
| Requests | 100 (measured) |
| Warmup | 10 |
| Concurrency | 10 |
| Success Rate | 100% |
| TTFT p50 | 221 ms |
| TTFT p95 | 700 ms |
| TPOT p50 | 26 ms |
| TPOT p95 | 27 ms |
| Latency p50 | 10,734 ms |
| Latency p95 | 13,948 ms |
| Avg tokens/sec | 37.3 |

### Metric Definitions

| Metric | Description |
|--------|-------------|
| TTFT | Time to first token (lower is better) |
| TPOT | Time per output token after first (lower is better) |
| Latency | Total response time including all tokens |
| Tokens/sec | Streaming throughput |

---

## Observability

### Central Grafana

Runs on LKE (included in `kube-prometheus-stack`). Queries all 3 Prometheus datasources.

**Datasources:** `Prometheus-LKE`, `Prometheus-EKS`, `Prometheus-GKE`
**Setup:** See `docs/DEPLOYMENT.md` → "Monitoring & Observability" section

### GPU Metrics (DCGM)

| Provider | DCGM Source | Status |
|----------|-------------|--------|
| LKE | GPU Operator (automatic) | ✅ |
| EKS | Helm chart (`deploy/helm/dcgm-values.yaml`) | ✅ |
| GKE | Managed + bridge (`deploy/monitoring/gke-dcgm-bridge.yaml`) | ✅ |

### Dashboards

| Dashboard | Purpose |
|-----------|---------|
| ITDM - Unified | 3-provider comparison (LKE/EKS/GKE) with costs + GPU metrics |
| RAG Overview | Per-cluster ITDMs |
| vLLM Metrics | Inference server stats |
| GPU Utilization | DCGM metrics (util, memory, temp, power) |

### Prometheus Metrics (Backend)

| Metric | Type | Labels |
|--------|------|--------|
| `rag_ttft_seconds` | Histogram | - |
| `rag_tpot_seconds` | Histogram | - |
| `rag_latency_seconds` | Histogram | `stage` (embedding/retrieval/inference) |
| `rag_tokens_total` | Counter | - |
| `rag_k_retrieved` | Histogram | - |

---

## Cross-Provider Comparison Workflow

1. **Deploy** the stack to each cluster (LKE, EKS, GKE)
2. **Configure** Prometheus per cluster with `prometheus-values.yaml`
3. **Run** North-South benchmark against each cluster's public endpoint
4. **Optionally run** East-West probe for network attribution
5. **View** results in ITDM Unified Dashboard
6. **Compute** costs with provider-specific configs

---

## Directory Structure

```
rag-ray-haystack/
├── apps/
│   ├── backend/           # FastAPI + Ray Serve
│   └── frontend/          # React UI
├── deploy/
│   ├── helm/rag-app/      # Main Helm chart
│   ├── overlays/          # Kustomize per provider
│   ├── netprobe/          # East-West probe manifests
│   └── monitoring/        # Grafana, Prometheus configs
├── scripts/
│   ├── benchmark/         # run_ns.sh, stream_bench.py
│   ├── netprobe/          # run_ew.sh
│   └── cost/              # compute_cost.py
├── grafana/dashboards/    # Dashboard JSON exports
├── cost/                  # Cost config examples
├── benchmarks/            # Results storage
└── docs/                  # Documentation
```

---

## Documentation

| Doc | Purpose |
|-----|---------|
| `docs/BENCHMARKING.md` | How to run benchmarks |
| `docs/OBSERVABILITY.md` | Prometheus + Grafana setup |
| `docs/COST_MODEL.md` | Cost computation guide |
| `docs/IMPLEMENTATION_CHECKLIST.md` | Feature tracking |
| `docs/ARCHITECTURE.md` | System architecture |

---

## Known Limitations

1. **East-West probe**: May need network policy adjustments per cluster (iperf3 connections can be reset)
2. **Prompt tokens**: Deferred - not critical for cross-provider comparison
3. **Workload manifests**: CLI args work; formal schema is nice-to-have
4. **Ray pod probes**: Default KubeRay probes use `wget` which isn't in our backend image. Custom tcpSocket/exec probes configured in rayservice template.
5. **Qdrant embedding dimension**: `qdrant-haystack` auto-creates collection with dim=768, but `all-MiniLM-L6-v2` produces dim=384. After first deploy, recreate the collection with correct dimension (see DEPLOYMENT.md).
6. **Qdrant server version**: Must be >= v1.10.0 (currently v1.12.6). Backend 0.3.9 uses `qdrant-client==1.16.2` which requires the `/points/query` API.
7. **GCP shared-core instances**: Do **not** use `e2-medium` for CPU nodes on GKE. Shared-core instances provide only ~940m allocatable CPU (vs ~1,930m on dedicated). Ray pods (1,000m request) cannot schedule. Use `e2-standard-2` instead. See DEPLOYMENT.md for full analysis.
8. **GKE DCGM exporter**: The DCGM Helm chart sets `priorityClassName: system-node-critical` which GKE blocks. Use GKE's managed DCGM exporter via `deploy/monitoring/gke-dcgm-bridge.yaml` instead. See DEPLOYMENT.md "Monitoring & Observability" section.

---

## Open Items

- [x] Deploy to AWS EKS
- [x] Run benchmarks on AWS EKS (Load test: 500 requests, 50 concurrency)
- [x] Verify dashboards with live EKS data
- [x] Test East-West probe on EKS (4.96 Gbps)
- [x] Deploy to GCP GKE (e2-standard-2 CPU, g2-standard-8 GPU)
- [ ] Run benchmarks on GCP GKE
- [ ] Compare benchmark results across all 3 providers

---

## Environment (Sanitized)

- Provider: `<provider>`
- Namespace: `rag-app`
- Image registry: `ghcr.io/<owner>`
- Backend tag: `0.3.9`
- Frontend tag: `0.3.5`
- Qdrant tag: `v1.12.6`
