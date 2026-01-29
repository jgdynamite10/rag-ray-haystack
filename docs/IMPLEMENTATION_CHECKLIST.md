# Implementation Checklist

This checklist tracks gaps between the documented requirements and current implementation.
Use this to systematically close gaps across Phase 1 and Phase 2 features.

## Status Legend
- [ ] Not started
- [~] In progress
- [x] Complete

---

## Phase 1: Core Infrastructure

### 1.1 Cost Model
| Task | File(s) | Status |
|------|---------|--------|
| Cost computation script | `scripts/cost/compute_cost.py` | [x] |
| Cost config example | `cost/cost-config.example.yaml` | [x] |
| Cost documentation | `docs/COST_MODEL.md` | [x] Complete |
| Integration with benchmark output | `run_ns.sh --with-cost` | [x] Complete |

**Status:** Complete. Cost model fully documented with cross-provider comparison guide.

### 1.2 Network Probes

#### East-West (In-Cluster) Probe
| Task | File(s) | Status |
|------|---------|--------|
| Netprobe Job manifest | `deploy/netprobe/ew-netprobe-job.yaml` | [ ] |
| Netprobe DaemonSet (optional) | `deploy/netprobe/ew-netprobe-ds.yaml` | [ ] |
| Netprobe script (iperf3/qperf based) | `scripts/netprobe/run_ew.sh` | [ ] |
| Sample output JSON schema | `schemas/netprobe-ew.schema.json` | [ ] |

**Gap:** No East-West network probe implemented. Needs:
- Pod-to-pod latency measurement
- Pod-to-service latency
- Bandwidth test between nodes

#### North-South (Client-to-Service) Probe
| Task | File(s) | Status |
|------|---------|--------|
| Runner wrapper script | `scripts/benchmark/run_ns.sh` | [x] Complete |
| Runner documentation | `docs/NORTH_SOUTH_BENCHMARK.md` | [x] Complete |

**Status:** Complete. `run_ns.sh` features:
- Auto-creates Python venv and installs dependencies
- Sets environment variables for run_metadata
- Calls `stream_bench.py` with standard args
- Optionally calls `compute_cost.py` on output (`--with-cost`)
- Saves results to `benchmarks/ns/<provider>/<timestamp>.json`

### 1.3 Observability

| Task | File(s) | Status |
|------|---------|--------|
| Grafana dashboards (JSON) | `grafana/dashboards/*.json` | [x] Complete |
| Provider comparison dashboard | `grafana/dashboards/provider-comparison.json` | [x] Complete |
| Central Grafana docker-compose | `deploy/monitoring/docker-compose.yml` | [x] Complete |
| Central Grafana Terraform | `deploy/monitoring/terraform/` | [x] Complete |
| Prometheus values (per-cluster) | `deploy/monitoring/prometheus-values.yaml` | [x] Complete |
| Central monitoring docs | Merged into OBSERVABILITY.md | [x] Complete |
| Benchmarking guide | `docs/BENCHMARKING.md` | [x] Complete |
| Observability overview doc | `docs/OBSERVABILITY.md` | [x] Complete |
| ServiceMonitor/PodMonitor setup | Documented in OBSERVABILITY.md | [x] Complete |
| Prometheus scraping RAG backend | Deployed to LKE | [x] Complete |

**Status:** Complete. Central Grafana deployed at http://172.239.55.129:3000

---

## Phase 2: Measurement Rigor Addendum

### 2.1 Interactive LLM Metrics (ITDMs)

| Metric | Backend Prometheus | Benchmark Script | Dashboard | Status |
|--------|-------------------|------------------|-----------|--------|
| TTFT (Time To First Token) | `rag_ttft_seconds` | [x] `ttft` | [x] | [x] Complete |
| TPOT (Time Per Output Token) | `rag_tpot_seconds` | [x] `tpot_p50_ms` | [x] | [x] Complete (0.3.4) |
| Total Latency | `rag_latency_seconds` | [x] `latency_p50_ms` | [x] | [x] Complete |
| Tokens/sec | `rag_tokens_per_second` | [x] `avg_tokens_per_sec` | [x] | [x] Complete |

**Status:** All core ITDMs implemented including Prometheus metrics.

### 2.2 Output Length Control

| Task | File(s) | Status |
|------|---------|--------|
| `max_output_tokens` param in benchmark | `stream_bench.py` | [x] Complete |
| Pass `max_tokens` to backend `/query/stream` | Backend API | [x] Complete |
| Backend forwards to vLLM | `main.py`, `vllm_client.py` | [x] Complete |

**Status:** Complete. Usage:
```bash
# Standalone benchmark with max output tokens
python stream_bench.py --url http://... --max-output-tokens 256

# Wrapper script
./scripts/benchmark/run_ns.sh akamai-lke --url http://... --max-output-tokens 256

# In-cluster benchmark via API
curl -X POST http://.../benchmark/run -d '{"max_output_tokens": 256}'
```

### 2.3 Token Counting

| Task | File(s) | Status |
|------|---------|--------|
| Prompt token count in output | `stream_bench.py` | [~] Deferred |
| Output token count in output | `stream_bench.py` | [x] `token_count` |
| Backend exposes token counts in SSE | `main.py` | [~] Deferred |

**Status:** Deferred. Output token counting is complete (`token_count`).

**Why prompt tokens are deferred:** For cross-provider GPU throughput/latency comparisons
(LKE vs EKS vs GKE), prompt token counting is not critical because:
1. We use the **same prompts** across all providers (controlled variable)
2. Our primary metrics (TTFT, TPOT, latency, tokens/sec) already capture performance
3. Cost comparisons use cluster-level pricing, not per-token API costs
4. Adding prompt tokens requires vLLM `stream_options` which adds complexity

Prompt token counting can be added later if per-token cost analysis becomes necessary.

### 2.4 Warmup vs Measured Phases

| Task | File(s) | Status |
|------|---------|--------|
| `--warmup-requests` argument | `stream_bench.py` | [x] Complete |
| Separate phase stats in output | JSON output | [x] Complete |
| Embedded script updated | `main.py` BENCH_SCRIPT | [x] Complete (0.3.2) |
| API passthrough to Job | `main.py` _benchmark_run | [x] Complete (0.3.3) |

**Status:** Complete. Warmup phases work in both standalone and in-cluster benchmarks.

### 2.5 Workload Manifest Schema

| Task | File(s) | Status |
|------|---------|--------|
| Workload manifest support | `stream_bench.py` | [x] Basic |
| Schema definition | `schemas/workload.schema.json` | [ ] |
| Example manifests | `workloads/` directory | [ ] |

**Gap:** Schema not formalized. Need:
```yaml
# workloads/example.yaml
name: "standard-rag-benchmark"
version: "1.0"
benchmark:
  concurrency: 10
  requests: 100
  warmup_requests: 10
  timeout: 120
  max_output_tokens: 512
retrieval:
  k: 5                    # Number of docs to retrieve
  docset: "default"       # Document set identifier
model:
  model_id: "Qwen/Qwen3-1.7B"
  dtype: "float16"
prompts:
  - "Explain what this system is and why vLLM matters."
  - "What are the key features of RAG systems?"
```

### 2.6 Run Metadata Schema

| Task | File(s) | Status |
|------|---------|--------|
| Collect from environment | `stream_bench.py` | [x] |
| Schema definition | `schemas/run-metadata.schema.json` | [ ] |
| Consistent field names | JSON output | [~] |

**Current run_metadata fields:**
- provider, region, cluster_label
- node_instance_type, gpu_model, gpu_count
- ray_version, vllm_version, model_id
- dtype, quantization, max_model_len
- backend/frontend/vllm image tags
- timestamp

**Missing fields per addendum:**
- `k` (retrieval count)
- `dataset` / `docset` identifier
- `cost_config_path` reference
- `netprobe_ew_path` reference

### 2.7 Attribution Signals (Prometheus Metrics)

| Metric | Label | Backend Code | Status |
|--------|-------|--------------|--------|
| `rag_latency_seconds` | `stage=embedding` | [x] | [x] |
| `rag_latency_seconds` | `stage=retrieval` | [x] | [x] |
| `rag_latency_seconds` | `stage=inference` | [x] | [x] |
| `rag_k_retrieved` | - | [x] | [x] |

**Status:** Attribution metrics exist in backend.

**Gap:** Dashboard queries may need verification to match actual label names.

### 2.8 Benchmark JSON Output Format

| Field | Status | Notes |
|-------|--------|-------|
| requests, success, errors | [x] | |
| ttft_p50_ms, ttft_p95_ms | [x] | |
| latency_p50_ms, latency_p95_ms | [x] | |
| tpot_p50_ms, tpot_p95_ms | [x] | |
| avg_tokens_per_sec | [x] | |
| total_tokens | [x] | |
| avg_output_tokens | [x] | |
| duration_seconds | [x] | |
| phases.warmup, phases.measured | [x] | |
| workload_manifest_hash | [x] | |
| run_metadata | [x] | |
| prompt_tokens | [x] | Complete (total_prompt_tokens, avg_prompt_tokens) |
| max_output_tokens | [x] | Complete |
| cost_reference | [ ] | Missing |
| netprobe_reference | [ ] | Missing |

---

## Dashboard/Metrics Alignment

### Required Verification

| Dashboard | Query | Backend Metric | Verified |
|-----------|-------|----------------|----------|
| RAG Overview | `rate(rag_requests_total[5m])` | `rag_requests_total` | [ ] |
| RAG Overview | `histogram_quantile(0.95, rag_ttft_seconds_bucket)` | `rag_ttft_seconds` | [ ] |
| RAG Overview | `histogram_quantile(0.95, rag_tpot_seconds_bucket)` | `rag_tpot_seconds` | [ ] |
| vLLM Metrics | `vllm:num_requests_running` | vLLM native | [ ] |
| vLLM Metrics | `vllm:gpu_cache_usage_perc` | vLLM native | [ ] |
| GPU Utilization | `DCGM_FI_DEV_GPU_UTIL` | DCGM exporter | [ ] |

**Action:** After deploying to cluster with Prometheus, verify each query returns data.

---

## Files to Create

### Priority 1 (Blocking)
1. ~~`scripts/benchmark/run_ns.sh`~~ - [x] Complete
2. ~~`docs/OBSERVABILITY.md`~~ - [x] Complete
3. ~~`docs/COST_MODEL.md`~~ - [x] Complete

### Priority 2 (Important)
4. `deploy/netprobe/ew-netprobe-job.yaml` - East-West probe manifest
5. `scripts/netprobe/run_ew.sh` - East-West runner
6. `schemas/workload.schema.json` - Workload manifest schema
7. `workloads/standard.yaml` - Default workload manifest

### Priority 3 (Nice to Have)
8. `schemas/run-metadata.schema.json` - Run metadata schema
9. `schemas/benchmark-output.schema.json` - Output JSON schema
10. `schemas/netprobe-ew.schema.json` - Netprobe output schema

---

## Remaining Gaps Summary

### High Priority (Critical for Cross-Provider Comparison)
| Gap | Impact | Effort | Status |
|-----|--------|--------|--------|
| ~~Cost documentation~~ | ~~Users can't understand cost model~~ | ~~Low~~ | [x] Complete |
| ~~`max_output_tokens` control~~ | ~~Benchmark results vary with response length~~ | ~~Medium~~ | [x] Complete |
| ~~ITDM Unified Dashboard~~ | ~~No single pane for comparison~~ | ~~Medium~~ | [x] Complete |

### Medium Priority
| Gap | Impact | Effort | Status |
|-----|--------|--------|--------|
| East-West network probe | Can't attribute latency to network vs GPU | Medium | [ ] |
| PROJECT_STATE.md update | Outdated docs for users | Low | [ ] |

### Deferred (Not Critical for Provider Comparison)
| Gap | Reason Deferred | 
|-----|-----------------|
| Prompt token counting | Same prompts across providers; output tokens sufficient |
| Workload manifest schema | Current CLI args work; formal schema is nice-to-have |
| Run metadata schema | Current fields work; formalization is nice-to-have |
| JSON schemas | Validation not blocking; manual review sufficient |

---

## Code Changes Required

### `scripts/benchmark/stream_bench.py`
```python
# Add these arguments:
parser.add_argument("--max-output-tokens", type=int, default=None)
parser.add_argument("--k", type=int, default=5, help="Retrieval k value")
parser.add_argument("--docset", default="default", help="Document set identifier")

# Update request payload:
request_payload = {
    "query": prompt,
    "k": args.k,
    "max_tokens": args.max_output_tokens,
}

# Add to run_metadata:
"k": args.k,
"docset": args.docset,
"max_output_tokens": args.max_output_tokens,
```

### `apps/backend/app/main.py`
```python
# Update /query/stream to accept max_tokens and k:
@app.post("/query/stream")
async def query_stream(request: QueryRequest):
    max_tokens = request.max_tokens  # Forward to vLLM
    k = request.k or 5  # Retrieval count
```

### Embedded `BENCH_SCRIPT` in `main.py`
- Must stay in sync with `scripts/benchmark/stream_bench.py`
- Update whenever standalone script changes

---

## Testing Checklist

After implementing changes:

- [ ] Local standalone benchmark runs: `python stream_bench.py --warmup-requests 5`
- [ ] In-cluster benchmark via API: `POST /benchmark/run`
- [ ] Cost script processes output: `python compute_cost.py`
- [ ] Prometheus scrapes metrics: check `/metrics` endpoint
- [ ] Grafana dashboards load without errors
- [ ] Dashboard queries return data
- [ ] JSON output matches expected schema

---

## PROJECT_STATE.public.md Updates Needed

Update the following sections:
1. Current status - reflect actual Phase 1/2 completion
2. Benchmark results - use Phase 2 format with TPOT
3. Open items - remove completed, add remaining gaps
4. Image tag - update to 0.3.4 after deployment

---

## Recent Progress (Session Log)

| Version | Changes |
|---------|---------|
| 0.3.2 | Embedded BENCH_SCRIPT with Phase 2 features (TPOT, warmup, run_metadata) |
| 0.3.3 | Fixed warmup_requests passthrough in /benchmark/run API |
| 0.3.4 | Added rag_tpot_seconds Prometheus histogram for Grafana |
| 0.3.5 | Added max_output_tokens control for consistent benchmarks |
| 0.3.6 | Dashboard fix: aggregate metrics for clean provider lines |

**Documentation created:**
- `docs/BENCHMARKING.md` - Explains all measurement methods (UI, N-S, in-cluster)
- `docs/CENTRAL_MONITORING.md` - Central Grafana setup guide
- `docs/IMPLEMENTATION_CHECKLIST.md` - This file

**Dashboards created:**
- `grafana/dashboards/rag-overview.json` - ITDMs overview
- `grafana/dashboards/vllm-metrics.json` - vLLM inference metrics
- `grafana/dashboards/gpu-utilization.json` - DCGM GPU metrics
- `grafana/dashboards/provider-comparison.json` - Side-by-side provider comparison
