# Project State (Public)

This file is safe to publish. Keep it sanitized and avoid sensitive details.

## Current status

- Infrastructure: Terraform scaffolding exists for Akamai LKE.
- Deployment: Helm chart for backend, frontend, Qdrant, RayService, and vLLM.
- GPU: vLLM runs on GPU nodes when `nvidia.com/gpu` capacity is available.
- Verification: vLLM streaming check passes on dev; backend pods Ready with service endpoints.
- Images: GHCR images published for backend/frontend (tag `0.2.1`).

## Benchmark results (dev, in-cluster)

- Requests: 100
- Concurrency: 10
- Success: 100 (errors: 0)
- TTFT p50: 82.03 ms
- TTFT p95: 479.48 ms
- Latency p50: 11157.53 ms
- Latency p95: 11761.82 ms
- Avg tokens/sec: 43.78

## Benchmark metric definitions

- TTFT p50/p95: time to first token for the 50th/95th percentile; lower is better.
- Latency p50/p95: total time to finish streaming the response.
- Avg tokens/sec: approximate throughput computed from streamed tokens.
- Success/errors: request-level success rate for the benchmark run.

## Open items

- Publish public URL (Ingress/LoadBalancer) after benchmarks.
- Update Akamai Value section with metrics.

## Environment (sanitized)

- Provider: <provider>
- Namespace: <namespace>
- Release: <release>
- Image registry: ghcr.io/<owner>
- Image tag: 0.2.1