# Project State (Public)

This file is safe to publish. Keep it sanitized and avoid sensitive details.

## Current status

- Infrastructure: Terraform modules for Akamai LKE, AWS EKS, and GCP GKE.
- Deployment: Helm chart for backend, frontend, Qdrant, RayService, and vLLM.
- GPU: vLLM runs on GPU nodes when `nvidia.com/gpu` capacity is available.
- Verification: vLLM streaming check passes on dev; backend pods Ready with service endpoints.
- Images: GHCR images published for backend/frontend (tag `0.3.0`).
- Cross-CSP Benchmarking: Cost model, network probes, and observability pack available.

## Cross-Provider Benchmarking Capabilities

### Cost Model

Compute derived cost metrics from benchmark results:

```bash
# Copy and configure cost inputs
cp cost/cost-config.example.yaml cost/cost-config.yaml

# Run benchmark and compute cost metrics
python scripts/cost/compute_cost.py benchmarks/results.json cost/cost-config.yaml --provider akamai-lke
```

Outputs: `usd_per_1m_tokens`, `usd_per_request`, `hourly_cluster_cost`

See: [docs/COST_MODEL.md](COST_MODEL.md)

### East-West Network Probe

Measure cross-node network performance within a cluster:

```bash
./scripts/netprobe/run_ew.sh --namespace rag-app --output benchmarks/ew/lke.json
```

Outputs: TCP bandwidth (Mbps), UDP jitter/loss, ping latency

### North-South Benchmark Runner

Run benchmarks against external endpoints:

```bash
./scripts/bench/run_ns.sh --endpoint http://172.236.105.4/api --provider akamai-lke
```

Results saved to: `benchmarks/ns/<provider>/<timestamp>.json`

### Grafana Observability

Import dashboards for cross-provider comparison:

- `grafana/dashboards/rag-overview.json` - Request rates, latencies
- `grafana/dashboards/gpu-utilization.json` - DCGM GPU metrics
- `grafana/dashboards/vllm-metrics.json` - vLLM inference metrics

See: [docs/OBSERVABILITY.md](OBSERVABILITY.md)

## Benchmark results (dev, in-cluster)

- Requests: 100
- Concurrency: 10
- Success: 100 (errors: 0)
- TTFT p50: 104.27 ms
- TTFT p95: 420.52 ms
- Latency p50: 12224.43 ms
- Latency p95: 12949.65 ms
- Avg tokens/sec: 40.0

## Benchmark metric definitions

- TTFT p50/p95: time to first token for the 50th/95th percentile; lower is better.
- Latency p50/p95: total time to finish streaming the response.
- Avg tokens/sec: approximate throughput computed from streamed tokens.
- Success/errors: request-level success rate for the benchmark run.

## Akamai Value

- Public URL (frontend): <public-url>
- Backend API is available via `http://<public-url>/api/*` (frontend proxy).
- In-cluster benchmark (dev): TTFT p50 104.27 ms, p95 420.52 ms; avg tokens/sec 40.0.

## Open items

- Test cross-CSP benchmarking on AWS EKS and GCP GKE.
- Deploy Prometheus + Grafana for live metrics comparison.
- (Optional) Build compare-ui for side-by-side results.

## Environment (sanitized)

- Provider: <provider>
- Namespace: <namespace>
- Release: <release>
- Image registry: ghcr.io/<owner>
- Image tag: 0.3.0
