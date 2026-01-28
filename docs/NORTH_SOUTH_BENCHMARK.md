# North-South Benchmark Guide

The North-South (N-S) benchmark measures end-to-end latency from an external client to the RAG system, simulating real user experience.

## What is North-South?

```
    NORTH (Client)
    ┌──────────────────┐
    │  Your Laptop     │
    │  ./run_ns.sh     │
    └────────┬─────────┘
             │
             │  Internet / Public Network
             │
             ▼
    SOUTH (Cluster)
    ┌──────────────────┐
    │  Kubernetes      │
    │  (RAG System)    │
    └──────────────────┘
```

**North** = External client (your laptop, CI runner, any machine outside the cluster)
**South** = The Kubernetes cluster running the RAG application

## What the Benchmark Measures

### Request Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         NORTH-SOUTH BENCHMARK FLOW                          │
└─────────────────────────────────────────────────────────────────────────────┘

[Client: run_ns.sh / stream_bench.py]
         │
         │ (1) HTTP POST /api/query/stream
         │     Body: {"query": "..."}
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ LOAD BALANCER (NodeBalancer / ALB / GCP LB)                                 │
│ - SSL termination (if HTTPS)                                                │
│ - Request routing                                                           │
└─────────────────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ FRONTEND (nginx proxy)                                                      │
│ - Serves static UI                                                          │
│ - Proxies /api/* to backend                                                 │
└─────────────────────────────────────────────────────────────────────────────┘
         │
         │ (2) Proxy to backend:8000
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ BACKEND (Python/FastAPI)                                                    │
│                                                                             │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ (3) EMBEDDING                                                           │ │
│ │     - Encode user query to vector                                       │ │
│ │     - Model: sentence-transformers/all-MiniLM-L6-v2 (default)           │ │
│ │     - Runs on CPU                                                       │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│                              │                                              │
│                              ▼                                              │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ (4) RETRIEVAL                                                           │ │
│ │     - Query Qdrant vector database                                      │ │
│ │     - Retrieve top-k relevant documents                                 │ │
│ │     - Default k=5                                                       │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│                              │                                              │
│                              ▼                                              │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ (5) PROMPT CONSTRUCTION                                                 │ │
│ │     - Build context from retrieved docs                                 │ │
│ │     - Format system + user prompt                                       │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│                              │                                              │
│                              ▼                                              │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ (6) vLLM INFERENCE                                                      │ │
│ │     - Send prompt to vLLM server                                        │ │
│ │     - Stream tokens back                                                │ │
│ │     - Model: Qwen/Qwen3-1.7B (default)                                  │ │
│ │     - Runs on GPU                                                       │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│                              │                                              │
└──────────────────────────────┼──────────────────────────────────────────────┘
                               │
                               │ (7) SSE Stream: tokens
                               ▼
                        [Client receives tokens]
```

## Dependencies That Affect Results

**CRITICAL:** Benchmark results depend on the ENTIRE stack. Changing any component will affect the metrics.

### Component Dependencies

| Component | Affects | If Changed... |
|-----------|---------|---------------|
| **Network** | TTFT, Total Latency | Different ISP, region, or network conditions change latency |
| **Load Balancer** | TTFT, Total Latency | Different LB type/config affects routing overhead |
| **Frontend** | TTFT | Nginx config, proxy overhead |
| **Embedding Model** | TTFT | Larger model = slower embedding = higher TTFT |
| **Qdrant** | TTFT | Index size, hardware, query complexity |
| **vLLM Model** | TTFT, TPOT, Tokens/sec | **MAJOR IMPACT** - different model = completely different results |
| **vLLM Config** | TPOT, Tokens/sec | dtype, quantization, max_model_len, tensor parallelism |
| **GPU Hardware** | TPOT, Tokens/sec | **MAJOR IMPACT** - GPU model determines generation speed |
| **CPU Hardware** | TTFT | Affects embedding speed |
| **Memory** | All | Insufficient memory causes swapping/OOM |
| **Concurrent Load** | All | More users = resource contention = higher latency |

### Metric Breakdown

| Metric | Primary Dependencies | Secondary Dependencies |
|--------|---------------------|----------------------|
| **TTFT** | Network, Embedding, Retrieval, vLLM prefill | Load balancer, CPU, Qdrant index |
| **TPOT** | GPU, vLLM model, dtype | Memory bandwidth, batch size |
| **Total Latency** | All above + output length | Token count varies per response |
| **Tokens/sec** | GPU, vLLM config | Concurrent requests, KV cache |

### What Must Be Documented for Reproducibility

When sharing benchmark results, always include:

```yaml
# Minimum reproducibility info
hardware:
  gpu_model: "NVIDIA RTX 4090"          # or L4, A100, etc.
  gpu_count: 1
  cpu: "AMD EPYC 7543"
  memory_gb: 64

software:
  vllm_model: "Qwen/Qwen3-1.7B"
  vllm_dtype: "float16"                 # or bfloat16, int8, etc.
  vllm_quantization: null               # or "awq", "gptq"
  embedding_model: "sentence-transformers/all-MiniLM-L6-v2"
  
infrastructure:
  provider: "akamai-lke"                # or aws-eks, gcp-gke
  region: "us-ord"
  node_type: "g6-dedicated-8"           # GPU node instance type

benchmark:
  client_location: "local"              # or "same-region", "cross-region"
  requests: 100
  concurrency: 10
  warmup_requests: 10
```

## Using run_ns.sh

### Basic Usage

```bash
# Navigate to project
cd /path/to/rag-ray-haystack

# Run benchmark against LKE
./scripts/benchmark/run_ns.sh akamai-lke \
  --url http://172.236.105.4/api/query/stream

# Run against AWS EKS
./scripts/benchmark/run_ns.sh aws-eks \
  --url http://eks-lb.example.com/api/query/stream

# Run against GCP GKE
./scripts/benchmark/run_ns.sh gcp-gke \
  --url http://gke-lb.example.com/api/query/stream
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--url` | (required) | Streaming endpoint URL |
| `--requests` | 100 | Number of measured requests |
| `--concurrency` | 10 | Concurrent requests |
| `--warmup` | 10 | Warmup requests (not counted) |
| `--timeout` | 180 | Request timeout in seconds |
| `--with-cost` | false | Run cost computation after |
| `--dry-run` | false | Show command without executing |

### Full Example

```bash
./scripts/benchmark/run_ns.sh akamai-lke \
  --url http://172.236.105.4/api/query/stream \
  --requests 100 \
  --concurrency 10 \
  --warmup 10 \
  --with-cost
```

### Environment Variables

Set these for richer `run_metadata` in output:

```bash
export GPU_MODEL="NVIDIA RTX 4090"
export GPU_COUNT="1"
export MODEL_ID="Qwen/Qwen3-1.7B"
export VLLM_VERSION="0.4.0"
export BACKEND_IMAGE_TAG="0.3.4"
export CLUSTER_LABEL="rag-ray-dev"

./scripts/benchmark/run_ns.sh akamai-lke --url http://...
```

## Output

Results are saved to: `benchmarks/ns/<provider>/<timestamp>.json`

### Sample Output

```json
{
  "requests": 100,
  "concurrency": 10,
  "success": 100,
  "errors": 0,
  "ttft_p50_ms": 186.07,
  "ttft_p95_ms": 237.34,
  "tpot_p50_ms": 21.6,
  "tpot_p95_ms": 21.8,
  "latency_p50_ms": 11183.52,
  "latency_p95_ms": 11379.34,
  "avg_tokens_per_sec": 45.15,
  "total_tokens": 48570,
  "avg_output_tokens": 485.7,
  "phases": {
    "warmup": { ... },
    "measured": { ... }
  },
  "run_metadata": {
    "provider": "akamai-lke",
    "region": "us-ord",
    "gpu_model": "NVIDIA RTX 4090",
    "model_id": "Qwen/Qwen3-1.7B",
    "timestamp": "2026-01-28T02:38:41.344506+00:00"
  }
}
```

## Comparing Results

### Valid Comparisons

| Comparison | Valid? | Notes |
|------------|--------|-------|
| Same stack, different providers | ✅ | Measures infrastructure difference |
| Same stack, different regions | ✅ | Measures network latency difference |
| Same stack, different times | ✅ | Measures consistency/variance |
| Different vLLM models | ❌ | Not comparable - different models |
| Different GPU hardware | ⚠️ | Shows hardware impact, not provider |
| Different embedding models | ⚠️ | Affects TTFT, confounds comparison |

### Best Practices

1. **Control variables**: Only change one thing at a time
2. **Document everything**: Record all component versions
3. **Run multiple times**: Account for variance
4. **Use warmup**: First requests are often slower (cold cache)
5. **Same client location**: Run from same machine for all providers

## Troubleshooting

### High TTFT

- Check embedding model size (larger = slower)
- Check Qdrant performance (index size, hardware)
- Check network latency to cluster
- Check vLLM prefill time (long prompts = slower)

### High TPOT

- Check GPU utilization (should be high during generation)
- Check vLLM config (dtype, quantization)
- Check for memory pressure (KV cache eviction)
- Check concurrent load (batch interference)

### Errors

- Check vLLM health: `kubectl logs deploy/rag-app-rag-app-vllm`
- Check backend health: `kubectl logs deploy/rag-app-rag-app-backend`
- Increase `--timeout` for slow networks
