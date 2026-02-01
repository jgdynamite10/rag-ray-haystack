# Cloud-Portable RAG: Performance & Cost Scorecard

Cloud-portable RAG service using **Haystack + Ray Serve (KubeRay)** with **vLLM streaming inference**, deployable to:
- **Akamai LKE**
- **AWS EKS**
- **GCP GKE**

This repository is designed to answer a practical IT decision question:

> **For the same RAG workload, what performance do we get and what does it cost — across Kubernetes providers?**

---

## What you get

### 1) A portable RAG service (same app, multiple clouds)
- One service architecture and deployment surface across Akamai LKE / AWS EKS / GCP GKE.
- Pluggable model + vector store with minimal infra changes.

### 2) A measurement contract for streaming inference (SSE)
Server-Sent Events (SSE) event types: `meta`, `token`, `done`, `error`.

The `done` event is designed to support consistent measurement and correlation:
- `session_id`, `request_id`, `replica_id`, `model_id`, `k`, `documents`
- `timings` (`ttft_ms`, `total_ms`) for diagnostics/correlation
- `token_count`, `tokens_per_sec`

Metric definitions:
- **TTFT in the UI is client-measured** (send → first token) and is the source of truth.
- **Total latency in the UI is client-measured** (send → done/error) and is the source of truth.
- `done.timings.*` are server-side measurements used for diagnostics/correlation.
- Tokens/sec uses `done.tokens_per_sec` if present; else `token_count / stream_duration`.
- Token count uses `done.token_count` if present; else best-effort (# token events).
- `replica_id` uses the backend pod hostname for debugging.

### 3) A scorecard view (Grafana)
A Grafana dashboard intended to summarize:
- Latency (TTFT, total)
- Throughput (tokens/sec, requests/sec)
- Resource usage (GPU/CPU/memory)
- Error rate
- Cost model inputs and derived cost efficiency

→ See [docs/COST_MODEL.md](docs/COST_MODEL.md) for detailed cost analysis across providers.

---

## Benchmark Results (January 30, 2026)

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 500/500 ✅ | 500/500 ✅ | 500/500 ✅ |
| **TTFT p50** | **2,912 ms** 🏆 | 3,490 ms | 2,933 ms |
| **TTFT p95** | **6,162 ms** 🏆 | 6,694 ms | 9,809 ms |
| **Latency p50** | **14,097 ms** 🏆 | 18,041 ms | 19,193 ms |
| **Latency p95** | **22,620 ms** 🏆 | 29,488 ms | 28,922 ms |
| **TPOT p50** | **44.6 ms** 🏆 | 57.5 ms | 63.2 ms |
| **Tokens/sec** | **17.63** 🏆 | 13.85 | 13.16 |
| **Duration** | **167s** 🏆 | 213s | 219s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 1.18 Gbps | 4.97 Gbps | **6.72 Gbps** 🏆 |
| **Retransmits** | 11,499 | **203** 🏆 | 46,610 |

### Key Insights

- **Akamai LKE** won all LLM performance metrics (faster TTFT, latency, TPOT)
- **GCP GKE** has highest network throughput (6.72 Gbps)
- **AWS EKS** has most stable network (only 203 retransmits)
- All providers: **0 errors** on 500 requests

---

## Dashboard Screenshots

<!-- TODO: Add Grafana dashboard screenshots here -->

*Screenshots coming soon*

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              AKAMAI CLOUD                                       │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                         Grafana (Self-hosted VM)                          │  │
│  │                        Unified Observability Dashboard                    │  │
│  └─────────┬─────────────────────┬─────────────────────┬─────────────────────┘  │
│            │                     │                     │                        │
│            ▼                     ▼                     ▼                        │
│  ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐               │
│  │  LKE Prom LB    │   │  EKS Prom LB    │   │  GKE Prom LB    │               │
│  └────────┬────────┘   └────────┬────────┘   └────────┬────────┘               │
│           │                     │                     │                        │
└───────────┼─────────────────────┼─────────────────────┼────────────────────────┘
            │                     │                     │
            ▼                     ▼                     ▼
┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐
│   AKAMAI LKE      │   │     AWS EKS       │   │     GCP GKE       │
│                   │   │                   │   │                   │
│ ┌───────────────┐ │   │ ┌───────────────┐ │   │ ┌───────────────┐ │
│ │ App LB        │ │   │ │ App LB (ELB)  │ │   │ │ App LB (GCLB) │ │
│ │ (NodeBalancer)│ │   │ └───────┬───────┘ │   │ └───────┬───────┘ │
│ └───────┬───────┘ │   │         │         │   │         │         │
│         │         │   │         │         │   │         │         │
│         ▼         │   │         ▼         │   │         ▼         │
│ ┌───────────────┐ │   │ ┌───────────────┐ │   │ ┌───────────────┐ │
│ │   Frontend    │ │   │ │   Frontend    │ │   │ │   Frontend    │ │
│ │ (React+Nginx) │ │   │ │ (React+Nginx) │ │   │ │ (React+Nginx) │ │
│ └───────┬───────┘ │   │ └───────┬───────┘ │   │ └───────┬───────┘ │
│         │         │   │         │         │   │         │         │
│         ▼         │   │         ▼         │   │         ▼         │
│ ┌───────────────┐ │   │ ┌───────────────┐ │   │ ┌───────────────┐ │
│ │ Ray Serve     │ │   │ │ Ray Serve     │ │   │ │ Ray Serve     │ │
│ │ Backend       │◄┼───┼─┤ Backend       │◄┼───┼─┤ Backend       │ │
│ │ (KubeRay)     │ │   │ │ (KubeRay)     │ │   │ │ (KubeRay)     │ │
│ └──┬─────────┬──┘ │   │ └──┬─────────┬──┘ │   │ └──┬─────────┬──┘ │
│    │         │    │   │    │         │    │   │    │         │    │
│    ▼         ▼    │   │    ▼         ▼    │   │    ▼         ▼    │
│ ┌──────┐ ┌──────┐ │   │ ┌──────┐ ┌──────┐ │   │ ┌──────┐ ┌──────┐ │
│ │Qdrant│ │ vLLM │ │   │ │Qdrant│ │ vLLM │ │   │ │Qdrant│ │ vLLM │ │
│ │      │ │ (GPU)│ │   │ │      │ │ (GPU)│ │   │ │      │ │ (GPU)│ │
│ └──────┘ └──────┘ │   │ └──────┘ └──────┘ │   │ └──────┘ └──────┘ │
│                   │   │                   │   │                   │
│ ┌───────────────┐ │   │ ┌───────────────┐ │   │ ┌───────────────┐ │
│ │  Prometheus   │ │   │ │  Prometheus   │ │   │ │  Prometheus   │ │
│ │  Pushgateway  │ │   │ │  Pushgateway  │ │   │ │  Pushgateway  │ │
│ │  DCGM Exporter│ │   │ │  DCGM Exporter│ │   │ │  DCGM Exporter│ │
│ └───────────────┘ │   │ └───────────────┘ │   │ └───────────────┘ │
└───────────────────┘   └───────────────────┘   └───────────────────┘
```

### High-level components
- **Frontend (UI)** — Collects user prompts, streams tokens, and records client-side TTFT/total latency.
- **Backend (RAG API)** — Orchestrates retrieval + generation and emits SSE events (`meta`, `token`, `done`, `error`) and exposes `/metrics`.
- **Ray Serve on Kubernetes (KubeRay)** — Runs the serving layer and scales inference workers across GPU nodes.
- **vLLM (GPU inference)** — Performs token streaming generation and returns tokens back through the backend streaming pipeline.
- **Vector store / Retriever (via Haystack)** — Handles document ingestion and retrieval during RAG.
- **Observability (Prometheus + Grafana)** — Scrapes backend (and optionally Ray/vLLM/K8s) metrics and renders the scorecard dashboard.

### Data flow (request lifecycle)
1. User uploads docs (UI → backend ingestion)
2. User sends prompt (UI → backend request)
3. Backend executes:
   - Retrieve top-k passages (Haystack)
   - Construct prompt with context
   - Stream generation from vLLM via Ray Serve
4. Backend streams SSE:
   - `meta` (request/session context)
   - `token` (streaming tokens)
   - `done` (final metrics + correlation ids)
5. UI computes:
   - TTFT (send → first token)
   - Total latency (send → done/error)
6. Prometheus scrapes metrics; Grafana renders scorecard panels.

→ See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed Mermaid diagrams.

---

## Repository layout (where to find things)

High-signal directories/files you will use when replicating deployments and benchmarks:

| Path | Description |
|------|-------------|
| `apps/backend/` | Backend service (RAG pipeline + streaming inference + metrics/logging) |
| `apps/frontend/` | UI for interactive RAG + streaming + client-side timing (TTFT/total) |
| `scripts/deploy.sh` | Primary deployment entrypoint for Kubernetes providers |
| `scripts/benchmark/` | Benchmark runners (North-South streaming tests) |
| `scripts/netprobe/` | East-West network benchmarks (iperf3-based) |
| `benchmarks/` | Benchmark results (JSON) by provider and type |
| `deploy/helm/rag-app/` | Helm chart for the application |
| `deploy/overlays/` | Kustomize overlays for provider-specific configuration |
| `docs/ARCHITECTURE.md` | Detailed architecture diagrams |
| `docs/COST_MODEL.md` | Cost analysis across providers |
| `docs/PROJECT_STATE.public.md` | Project state / scope / progress notes |
| `docs/OPERATIONS.public.md` | Ops notes: environments, debugging, reliability guidance |

> **New to the repo?** Read `docs/PROJECT_STATE.public.md` first, then `docs/OPERATIONS.public.md`.

---

## Deployment templates and configuration

### A) Local quick start (developer workstation)

```bash
git clone https://github.com/jgdynamite10/rag-ray-haystack
cd rag-ray-haystack
```

```bash
# Backend
cd apps/backend
uv sync --python 3.11
uv run --python 3.11 serve run app.main:deployment
```

```bash
# Frontend (new terminal)
cd apps/frontend
npm install
npm run dev
```

### B) Kubernetes deployment

```bash
# Deploy to a provider (akamai-lke, aws-eks, gcp-gke)
./scripts/deploy.sh --provider akamai-lke --env dev
```

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for detailed instructions.

---

## GPU instances by provider

All providers use comparable Ada Lovelace architecture GPUs:

| Provider | Instance | GPU | vRAM | Hourly Cost |
|----------|----------|-----|------|-------------|
| Akamai LKE | g2-gpu-rtx4000a1-s | RTX 4000 Ada | 20 GB | $1.10/hr |
| AWS EKS | g6.xlarge | NVIDIA L4 | 24 GB | $0.8049/hr |
| GCP GKE | g2-standard-8 | NVIDIA L4 | 24 GB | $0.8369/hr |

→ See [docs/COST_MODEL.md](docs/COST_MODEL.md) for full cost breakdown including CPU, storage, and networking.

---

## Model configuration

Set `VLLM_MODEL` (backend env) or `vllm.model` in Helm values:

| Model | Use case |
|-------|----------|
| `Qwen/Qwen2.5-3B-Instruct` | Smaller/faster |
| `Qwen/Qwen2.5-7B-Instruct` | Default balanced |
| `Qwen/Qwen2.5-14B-Instruct` | Higher quality (more VRAM) |

Quantization can be enabled via Helm `vllm.quantization`.

---

## Why this stack

- **Cloud-portable**: One Helm chart + overlays for Akamai LKE, AWS EKS, and GCP GKE.
- **Production-grade serving**: KubeRay + Ray Serve + vLLM for scalable, streaming GPU inference.
- **Observable by default**: `/metrics`, structured logs, and portable benchmarking scripts.
- **Swap-friendly**: Pluggable models and vector store with minimal infra changes.
- **Ops-ready**: Build/push/deploy/verify/benchmark scripts baked in.

---

## License

MIT
