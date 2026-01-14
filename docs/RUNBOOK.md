# Runbook

## Build and push images

```bash
export IMAGE_REGISTRY=registry.example.com/your-team
export IMAGE_TAG=0.1.0
./scripts/build-images.sh
./scripts/push-images.sh
```

## Deploy

```bash
./scripts/deploy.sh --provider aws --env dev
```

## Verify

```bash
kubectl -n rag-app get pods
kubectl -n rag-app get svc
```

## Backend configuration

Environment variables:

- `RAG_USE_EMBEDDINGS` (default `true`)
- `EMBEDDING_MODEL_ID` (default `sentence-transformers/all-MiniLM-L6-v2`)
- `RAG_TOP_K` (default `4`)
- `RAG_MAX_HISTORY` (default `6`)
- `QDRANT_URL` (optional, e.g. `http://rag-app-rag-app-qdrant:6333`)
- `QDRANT_COLLECTION` (default `rag-documents`)
- `VLLM_BASE_URL` (default `http://vllm:8000`)
- `VLLM_MODEL` (default `Qwen/Qwen2.5-7B-Instruct`)
- `VLLM_MAX_TOKENS` (default `512`)
- `VLLM_TEMPERATURE` (default `0.2`)
- `VLLM_TOP_P` (default `0.95`)
- `VLLM_TIMEOUT_SECONDS` (default `30`)

## Streaming responses

Use `/query/stream` for SSE streaming. The frontend supports streaming by default.

SSE event types:

- `meta` (retrieval timings + documents)
- `ttft` (time-to-first-token)
- `token` (token delta)
- `done` (final timings + citations)

## Swap vLLM models

- Helm: set `vllm.model` and (optionally) `vllm.quantization`.
- Backend env: set `VLLM_MODEL`.

Common options:

- Smaller / lower cost: `Qwen/Qwen2.5-3B-Instruct`
- Balanced default: `Qwen/Qwen2.5-7B-Instruct`
- Higher quality / more VRAM: `Qwen/Qwen2.5-14B-Instruct`

Quantization (ex: `awq`, `gptq`) reduces VRAM usage but may impact accuracy.

## Connector upgrades

`/ingest` accepts:

- multipart files: `.pdf`, `.docx`, `.html`, `.txt`
- JSON body with `texts`, `documents`, `urls`, or `sitemap_url`

Example:

```json
{
  "urls": ["https://example.com/docs"],
  "sitemap_url": "https://example.com/sitemap.xml"
}
```

## Benchmark

```bash
export BENCH_TARGET=http://localhost:8000
./scripts/benchmark.sh
```

## Rollback

```bash
kubectl -n rag-app rollout undo deployment/rag-app-rag-app-frontend
kubectl -n rag-app rollout undo deployment/rag-app-rag-app-backend
```
