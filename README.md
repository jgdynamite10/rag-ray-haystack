# rag-ray-haystack

Cloud-portable RAG chatbot using Haystack + Ray Serve (KubeRay), with vLLM
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
