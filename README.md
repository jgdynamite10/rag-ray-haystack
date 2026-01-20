# rag-ray-fabric

Cloud-portable RAG service using Haystack + Ray Serve (KubeRay), with vLLM
streaming inference and deployable to Akamai LKE, AWS EKS, and GCP GKE.

## Quick start (local)

```bash
cd apps/backend
uv sync --python 3.11
uv run --python 3.11 serve run app.main:deployment
```

```bash
cd ../frontend
npm install
npm run dev
```

## Kubernetes

```bash
./scripts/deploy.sh --provider aws --env dev
```

## Public access (Akamai dev)

- UI: `http://<public-url>/`
- Backend API via UI proxy: `http://<public-url>/api/*`

## Streaming metrics (SSE)

Event types: `meta`, `token`, `done`, `error`.

`token` payload:
- `{ "text": "<string>" }`

`done` payload fields:
- `session_id`, `request_id`, `replica_id`, `model_id`, `k`, `documents`
- `timings` (`ttft_ms`, `total_ms`) (server-side diagnostics)
- `token_count`, `tokens_per_sec`

Metric definitions:
- TTFT shown in UI is client-measured (send → first token event) and is the source of truth.
- Total latency shown is client-measured (send → done/error) and is the source of truth.
- `done.timings.*` are server-side measurements used for diagnostics/correlation.
- Tokens/sec uses `done.tokens_per_sec` if present; else `token_count / stream_duration`.
- Token count uses `done.token_count` if present; else best-effort (# token events).
- `replica_id` uses the backend pod hostname for debugging.

Quick verification:
1) Open the UI and ingest a small PDF/text file.
2) Send 3 prompts with streaming enabled.
3) Confirm per-message metrics panels populate and the rolling widget updates; Top sources should
   show retrieved snippets for at least one request (`k > 0`).

## Sanity checks and benchmarking

- In-cluster sanity check (Kubernetes): see `docs/RUNBOOK.md#in-cluster-sanity-check-kubernetes`
- Benchmarking (portable): see `docs/RUNBOOK.md#benchmarking-portable`

## Why this stack

- Cloud-portable: one Helm chart + overlays for Akamai LKE, AWS EKS, and GCP GKE.
- Production-grade serving: KubeRay + Ray Serve + vLLM for scalable, streaming GPU inference.
- Observable by default: `/metrics`, structured logs, and portable benchmarking scripts.
- Swap-friendly: pluggable models and vector store with minimal infra changes.
- Ops-ready: build/push/deploy/verify/benchmark scripts baked in.

## Project context (public)

- `docs/PROJECT_STATE.public.md`
- `docs/OPERATIONS.public.md`

## vLLM Helm values

- `vllm.image.repository`, `vllm.image.tag`
- `vllm.model`, `vllm.servedModelName`
- `vllm.maxModelLen`, `vllm.gpuMemoryUtilization`, `vllm.dtype`, `vllm.quantization`
- `vllm.resources`, `vllm.nodeSelector`, `vllm.tolerations`

## Model swap

Set `VLLM_MODEL` (backend env) or `vllm.model` in Helm values. For example:

- Smaller/faster: `Qwen/Qwen2.5-3B-Instruct`
- Default balanced: `Qwen/Qwen2.5-7B-Instruct`
- Higher quality (more VRAM): `Qwen/Qwen2.5-14B-Instruct`

Quantization can be enabled via Helm `vllm.quantization`.
