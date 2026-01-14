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

- `GENERATOR_ENABLED` (default `true`)
- `GENERATOR_MODEL_ID` (default `sshleifer/tiny-gpt2`)
- `GENERATOR_MAX_NEW_TOKENS` (default `256`)
- `GENERATOR_TEMPERATURE` (default `0.2`)
- `RAG_USE_EMBEDDINGS` (default `true`)
- `EMBEDDING_MODEL_ID` (default `sentence-transformers/all-MiniLM-L6-v2`)
- `RAG_TOP_K` (default `4`)
- `RAG_MAX_HISTORY` (default `6`)
- `QDRANT_URL` (optional, e.g. `http://rag-app-rag-app-qdrant:6333`)
- `QDRANT_COLLECTION` (default `rag-documents`)

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
