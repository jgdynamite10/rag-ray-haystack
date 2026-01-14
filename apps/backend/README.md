# Backend

Ray Serve + Haystack backend exposing `/query`, `/ingest`, `/healthz`, `/metrics`, and
`/query/stream` for SSE streaming. Inference uses a vLLM OpenAI-compatible server.

## Local dev

```bash
uv sync --python 3.11
uv run --python 3.11 serve run app.main:deployment
```

## Environment variables

- `VLLM_BASE_URL` (default `http://vllm:8000`)
- `VLLM_MODEL` (default `Qwen/Qwen2.5-7B-Instruct`)
- `VLLM_MAX_TOKENS` (default `512`)
- `VLLM_TEMPERATURE` (default `0.2`)
- `VLLM_TOP_P` (default `0.95`)
- `VLLM_TIMEOUT_SECONDS` (default `30`)
- `RAG_USE_EMBEDDINGS` (default `true`)
- `EMBEDDING_MODEL_ID` (default `sentence-transformers/all-MiniLM-L6-v2`)
- `RAG_TOP_K` (default `4`)
- `RAG_MAX_HISTORY` (default `6`)
- `QDRANT_URL` (optional, e.g. `http://rag-app-rag-app-qdrant:6333`)
- `QDRANT_COLLECTION` (default `rag-documents`)
