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
export PLATFORM=aws-eks  # or akamai-lke, gcp-gke
./scripts/deploy.sh
```

## Verify

```bash
kubectl -n rag-app get pods
kubectl -n rag-app get svc
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
