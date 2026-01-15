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
cp infra/terraform/akamai-lke/terraform.tfvars.example infra/terraform/akamai-lke/terraform.tfvars
./scripts/deploy.sh --provider akamai-lke --env dev --action apply
```

## Install KubeRay operator

```bash
make install-kuberay PROVIDER=akamai-lke ENV=dev
```

## GPU bring-up (automated)

```bash
make fix-gpu PROVIDER=akamai-lke ENV=dev
```

## Verify

```bash
# context + namespace discovery
kubectl config current-context
kubectl get ns
kubectl -n <namespace> get svc

# workload status
kubectl -n <namespace> get pods

# automated streaming verification
make verify NAMESPACE=<namespace> RELEASE=<release>
```

If GPU scheduling or `nvidia.com/gpu` capacity is missing, see
`docs/GPU_TROUBLESHOOTING.md`.

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

## In-cluster sanity check (Kubernetes)

Note: Helm release names change service names, so discovery is required before port-forwarding.

### A. vLLM streaming (direct)

```bash
# context + namespace discovery
kubectl config current-context
kubectl get ns
kubectl -n <namespace> get svc

# discover vLLM service name
kubectl -n <namespace> get svc | grep vllm

# port-forward vLLM service
kubectl -n <namespace> port-forward svc/<release>-vllm 8001:8000

export VLLM_MODEL_ID="Qwen/Qwen2.5-7B-Instruct"
curl -N http://localhost:8001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"$VLLM_MODEL_ID"'",
    "messages": [{"role":"user","content":"Say hello in 20 words."}],
    "stream": true,
    "max_tokens": 64
  }'
```

Expected behavior: many incremental `data:` events, not a single buffered response.

### B. Ray Serve → vLLM streaming relay (SSE end-to-end)

```bash
# context + namespace discovery
kubectl config current-context
kubectl get ns
kubectl -n <namespace> get svc

# discover backend service name
kubectl -n <namespace> get svc | grep backend

# port-forward Ray Serve backend
kubectl -n <namespace> port-forward svc/<release>-backend 8000:8000

curl -N -X POST http://localhost:8000/query/stream \
  -H "Content-Type: application/json" \
  -d '{"query":"Explain what this system is and why vLLM matters."}'
```

Expected behavior: `meta` → `ttft` → repeated `token` → `done` events.

### C. Confirm no buffering at ingress

If you deploy behind an ingress, disable response buffering for SSE paths. Example
NGINX ingress snippet (generic):

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_set_header X-Accel-Buffering "no";
```

### Troubleshooting

If streaming appears chunked/delayed:

1. Verify vLLM direct stream (A).
2. Verify backend relay (B).
3. Check ingress buffering (C).

## Benchmarking (portable)

Install benchmark deps:

```bash
python -m pip install -r scripts/benchmark/requirements.txt
```

Port-forward the backend:

```bash
# context + namespace discovery
kubectl config current-context
kubectl get ns
kubectl -n <namespace> get svc

# discover backend service name
kubectl -n <namespace> get svc | grep backend

# port-forward Ray Serve backend
kubectl -n <namespace> port-forward svc/<release>-backend 8000:8000
```

Run benchmarks:

```bash
python scripts/benchmark/stream_bench.py \
  --url http://localhost:8000/query/stream \
  --concurrency 1 \
  --requests 50
```

```bash
python scripts/benchmark/stream_bench.py \
  --url http://localhost:8000/query/stream \
  --concurrency 10 \
  --requests 100
```

```bash
python scripts/benchmark/stream_bench.py \
  --url http://localhost:8000/query/stream \
  --concurrency 50 \
  --requests 200
```

Keep prompts and max tokens identical for cross-cloud comparisons.

## Benchmark

```bash
export BENCH_TARGET=http://localhost:8000
./scripts/benchmark.sh
```

## Rollback

```bash
# safety checks before rollback
kubectl config current-context
kubectl -n <namespace> get pods
helm -n <namespace> list
helm -n <namespace> history <release>

# rollback workload deployments
kubectl -n <namespace> rollout undo deployment/<release>-frontend
kubectl -n <namespace> rollout undo deployment/<release>-backend
```

## Uninstall / cleanup

```bash
# safety checks before uninstall
kubectl config current-context
kubectl -n <namespace> get pods
helm -n <namespace> list
helm -n <namespace> history <release>

# uninstall helm release
helm -n <namespace> uninstall <release>

# delete namespace if desired (optional)
kubectl delete ns <namespace>
```
