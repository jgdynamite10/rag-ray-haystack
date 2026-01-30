# Runbook

## Build and push images

```bash
export IMAGE_REGISTRY=registry.example.com/your-team
export IMAGE_TAG=0.3.0
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
export KUBECONFIG=~/.kube/akamai-lke-dev-config.yaml
KUBECONFIG_PATH="$KUBECONFIG" make install-kuberay PROVIDER=akamai-lke ENV=dev
```

## GPU bring-up (automated)

```bash
# install GPU Operator + Node Feature Discovery
helm repo add nvidia-gpu https://nvidia.github.io/gpu-operator
helm repo add nfd https://kubernetes-sigs.github.io/node-feature-discovery/charts
helm repo update
helm upgrade --install gpu-operator nvidia-gpu/gpu-operator \
  --namespace gpu-operator --create-namespace
helm upgrade --install node-feature-discovery nfd/node-feature-discovery \
  --namespace node-feature-discovery --create-namespace

# apply GPU labels/taints (required for vLLM scheduling)
KUBECONFIG_PATH="$KUBECONFIG" make fix-gpu PROVIDER=akamai-lke ENV=dev

# verify GPU capacity (should be non-empty on GPU node)
kubectl get nodes -o jsonpath="{range .items[*]}{.metadata.name}{' -> '}{.status.capacity['nvidia.com/gpu']}{'\n'}{end}"
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

## East-West Network Benchmark

Measures in-cluster TCP throughput, UDP jitter, and latency between nodes.

```bash
# Run for each provider
./scripts/netprobe/run_ew.sh --provider akamai-lke --kubeconfig ~/.kube/rag-ray-haystack-kubeconfig.yaml
./scripts/netprobe/run_ew.sh --provider aws-eks --kubeconfig ~/.kube/eks-kubeconfig.yaml
./scripts/netprobe/run_ew.sh --provider gcp-gke --kubeconfig ~/.kube/gke-kubeconfig.yaml

# With Pushgateway metrics
./scripts/netprobe/run_ew.sh --provider gcp-gke \
  --pushgateway-url http://prometheus-pushgateway.monitoring:9091
```

**Reference Results (January 2026):**

| Provider | TCP Throughput | Retransmits |
|----------|----------------|-------------|
| Akamai LKE | 1.11 Gbps | 2,291 |
| AWS EKS | 4.78 Gbps | 308 |
| GCP GKE | 6.97 Gbps | 64,112 |

### Troubleshooting East-West

**GKE: iperf3 "Bad file descriptor" error**

If you see "unable to receive cookie" or "Bad file descriptor" errors on GKE:

```bash
# Check server logs
./scripts/netprobe/run_ew.sh --provider gcp-gke --keep
kubectl -n netprobe logs -l app=iperf3-server

# Manual cleanup if needed
kubectl delete namespace netprobe
```

The fix (already applied): Server runs in `--one-off` loop mode with `--forceflush` to handle connections cleanly.

**Same-node test warning**

If you see "Server and client on same node", the cluster may have only one schedulable node or anti-affinity couldn't be satisfied. Cross-node tests require at least 2 nodes.

See `docs/BENCHMARKING.md` for complete East-West documentation.

## Version Compatibility

### Recommended Versions (January 2026)

| Component | Version | Notes |
|-----------|---------|-------|
| **Frontend** | `0.3.5` | **Required** - 0.3.7 has Rolling metrics bug |
| **Backend** | `0.3.7` | Latest stable |
| **vLLM** | `v0.6.2` | Compatible with RTX 4000 Ada / NVIDIA L4 |

### Quick Fixes

**Fix frontend Rolling metrics (downgrade from 0.3.7):**
```bash
kubectl -n rag-app set image deployment/rag-app-rag-app-frontend \
  frontend=ghcr.io/jgdynamite10/rag-ray-frontend:0.3.5
```

**Fix backend QDRANT_URL (if Avg k Retrieved = 0):**
```bash
# Verify QDRANT_URL is set
kubectl -n rag-app exec deployment/rag-app-rag-app-backend -- env | grep QDRANT_URL

# If missing, redeploy with Helm (base chart now includes QDRANT_URL)
helm upgrade rag-app deploy/helm/rag-app -n rag-app --reuse-values
```

**Verify all images across providers:**
```bash
for ctx in lke561078-ctx arn:aws:eks:us-east-1:494507830157:cluster/rag-ray-haystack gke_rag-ray-haystack_us-central1-a_rag-ray-haystack; do
  echo "=== $ctx ==="
  kubectl --context="$ctx" -n rag-app get deployments -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.template.spec.containers[0].image}{"\n"}{end}'
done
```
