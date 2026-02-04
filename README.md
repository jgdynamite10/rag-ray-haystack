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

## Benchmark Results (February 4, 2026)

### North-South (500 requests, 50 concurrency)

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **Success** | 499/500 ✅ | 500/500 ✅ | 480/500 ⚠️ |
| **TTFT p50** | **1,442 ms** 🏆 | 3,884 ms | 2,540 ms |
| **TTFT p95** | **6,010 ms** 🏆 | 6,753 ms | 7,124 ms |
| **Latency p50** | **9,009 ms** 🏆 | 18,784 ms | 15,737 ms |
| **Latency p95** | **11,841 ms** 🏆 | 19,715 ms | 21,486 ms |
| **TPOT p50** | **29.0 ms** 🏆 | 58.3 ms | 52.8 ms |
| **Tokens/sec** | **27.07** 🏆 | 13.87 | 15.55 |
| **Duration** | **107s** 🏆 | 199s | 282s |

### East-West Network

| Metric | Akamai LKE | AWS EKS | GCP GKE |
|--------|------------|---------|---------|
| **TCP Throughput** | 1.06 Gbps | 4.92 Gbps | **6.65 Gbps** 🏆 |
| **Retransmits** | 2,416 | **194** 🏆 | 110,884 |

---

## Dashboard Screenshots

<!-- TODO: Add Grafana dashboard screenshots here -->

*Screenshots coming soon*

---

## Architecture

```mermaid
flowchart TB
  subgraph External
    User[User Browser]
    Grafana[Grafana<br/>Akamai VM]
  end

  subgraph K8s Cluster
    subgraph Ingress Layer
      AppLB[App LoadBalancer<br/>NodeBalancer / ELB / GCLB]
      PromLB[Prometheus LoadBalancer]
    end

    subgraph Application
      Frontend[Frontend<br/>React + Nginx]
      Backend[Ray Serve Backend<br/>Haystack + vLLM Client]
      Qdrant[(Qdrant<br/>Vector DB)]
      VLLM[vLLM Server<br/>GPU]
    end

    subgraph Orchestration
      KubeRay[KubeRay Operator]
    end

    subgraph Monitoring
      Prom[(Prometheus)]
      Push[Pushgateway]
      DCGM[DCGM Exporter<br/>GPU Metrics]
    end
  end

  User -->|HTTPS| AppLB
  AppLB --> Frontend
  AppLB --> Backend
  Frontend -->|/api proxy| Backend
  Backend -->|retrieve| Qdrant
  Backend -->|stream chat| VLLM
  KubeRay -.->|manages| Backend
  
  Backend -->|push job metrics| Push
  Prom -->|scrape /metrics| Backend
  Prom -->|scrape| Push
  Prom -->|scrape| DCGM
  Grafana -->|query| PromLB
  PromLB --> Prom
```

### Multi-Cluster Monitoring

```
┌─────────────────────────────────────────────────────────┐
│              Akamai VM (External)                       │
│                   Grafana                               │
│           (Unified dashboards)                          │
└─────────┬─────────────┬─────────────┬───────────────────┘
          │             │             │
          ▼             ▼             ▼
   ┌────────────┐ ┌────────────┐ ┌────────────┐
   │ LKE Prom LB│ │ EKS Prom LB│ │ GKE Prom LB│
   └──────┬─────┘ └──────┬─────┘ └──────┬─────┘
          ▼              ▼              ▼
   ┌────────────┐ ┌────────────┐ ┌────────────┐
   │  LKE       │ │  EKS       │ │  GKE       │
   │ Prometheus │ │ Prometheus │ │ Prometheus │
   │ Pushgateway│ │ Pushgateway│ │ Pushgateway│
   │ DCGM       │ │ DCGM       │ │ DCGM       │
   └────────────┘ └────────────┘ └────────────┘
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
