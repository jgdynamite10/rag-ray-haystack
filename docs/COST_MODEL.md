# Cost Model Guide

This document explains how to compute and compare costs across cloud providers (Akamai LKE, AWS EKS, GCP GKE) for running the RAG system.

## Overview

The cost model is **inputs-driven** for reproducibility:
- All costs are explicit inputs (no hidden calculations)
- Prices are timestamped (`as_of`) to track when they were captured
- Derived metrics are computed from benchmark results + cost inputs

```
┌─────────────────────┐     ┌─────────────────────┐
│  Benchmark Results  │     │   Cost Config       │
│  (JSON)             │     │   (YAML)            │
│                     │     │                     │
│  - requests: 100    │     │  akamai-lke:        │
│  - total_tokens     │     │    gpu: $1.50/hr    │
│  - duration_seconds │     │    cpu: $0.036/hr   │
└─────────┬───────────┘     └─────────┬───────────┘
          │                           │
          └───────────┬───────────────┘
                      │
                      ▼
          ┌───────────────────────┐
          │   compute_cost.py     │
          └───────────┬───────────┘
                      │
                      ▼
          ┌───────────────────────┐
          │   Derived Metrics     │
          │                       │
          │  - $/1M tokens        │
          │  - $/request          │
          │  - hourly cluster $   │
          │  - benchmark run $    │
          └───────────────────────┘
```

---

## Quick Start

### 1. Set Up Cost Configuration

```bash
# Copy the example config
cp cost/cost-config.example.yaml cost/cost-config.yaml

# Edit with your actual prices (optional - defaults are reasonable)
nano cost/cost-config.yaml
```

### 2. Run a Benchmark

```bash
./scripts/benchmark/run_ns.sh akamai-lke --url http://<app-url>/api/query/stream
```

### 3. Compute Costs

```bash
# Install pyyaml if not already installed
pip3 install pyyaml

# Run cost computation
python3 scripts/cost/compute_cost.py \
  benchmarks/ns/akamai-lke/2026-01-28T155552Z.json \
  cost/cost-config.yaml \
  --provider akamai-lke
```

### 4. Or Use the Integrated Flag

```bash
# Run benchmark and compute cost in one command
./scripts/benchmark/run_ns.sh akamai-lke \
  --url http://<app-url>/api/query/stream \
  --with-cost
```

---

## Cost Configuration File

Location: `cost/cost-config.yaml`

```yaml
providers:
  akamai-lke:
    as_of: "2026-01-27"                    # When prices were captured
    notes: "Linode list prices"             # Source documentation
    
    # Core compute costs (USD per hour)
    gpu_node_usd_per_hr: 1.50              # GPU node (e.g., RTX 4000 Ada)
    cpu_node_usd_per_hr: 0.036             # CPU node (e.g., g6-standard-2)
    
    # Network costs (USD per GB)
    egress_usd_per_gb: 0.005               # Outbound data transfer
    ingress_usd_per_gb: 0.0                # Inbound (usually free)
    
    # Storage costs (optional)
    storage_usd_per_gb_month: 0.10         # Block storage
    
    # Cluster overhead
    cluster_mgmt_usd_per_hr: 0.0           # Control plane fee

  aws-eks:
    as_of: "2026-01-27"
    gpu_node_usd_per_hr: 0.8048            # g6.xlarge (NVIDIA L4)
    cpu_node_usd_per_hr: 0.096             # m5.large
    cluster_mgmt_usd_per_hr: 0.10          # EKS control plane

  gcp-gke:
    as_of: "2026-01-27"
    gpu_node_usd_per_hr: 0.942             # g2-standard-8 (NVIDIA L4)
    cpu_node_usd_per_hr: 0.067             # e2-standard-2
    cluster_mgmt_usd_per_hr: 0.10          # GKE management fee

# Benchmark context (node counts for cost attribution)
benchmark_context:
  gpu_node_count: 1                        # Number of GPU nodes
  cpu_node_count: 2                        # Number of CPU nodes
```

### Provider Pricing Sources

| Provider | GPU Instance | Price Source |
|----------|--------------|--------------|
| Akamai LKE | g2-gpu-rtx4000a1-s (RTX 4000 Ada 20GB) | [Linode Pricing](https://www.linode.com/pricing/) |
| AWS EKS | g6.xlarge (NVIDIA L4 24GB) | [EC2 Pricing](https://aws.amazon.com/ec2/pricing/on-demand/) |
| GCP GKE | g2-standard-8 (NVIDIA L4 24GB) | [GCE Pricing](https://cloud.google.com/compute/vm-instance-pricing) |

---

## Output Format

The cost computation outputs JSON with these sections:

```json
{
  "provider": "akamai-lke",
  "benchmark_file": "benchmarks/ns/akamai-lke/2026-01-28.json",
  "cost_config_as_of": "2026-01-27",
  
  "benchmark_summary": {
    "requests": 100,
    "success": 100,
    "errors": 0,
    "total_tokens": 38292,
    "duration_seconds": 120.007,
    "avg_tokens_per_sec": 37.29,
    "ttft_p50_ms": 221.37,
    "tpot_p50_ms": 26.13
  },
  
  "cost_inputs": {
    "gpu_node_usd_per_hr": 1.50,
    "cpu_node_usd_per_hr": 0.036,
    "cluster_mgmt_usd_per_hr": 0.0,
    "gpu_node_count": 1,
    "cpu_node_count": 2
  },
  
  "derived_metrics": {
    "usd_per_1m_tokens": 1.37,
    "usd_per_request": 0.000524,
    "usd_per_successful_request": 0.000524,
    "hourly_cluster_cost": 1.572,
    "benchmark_run_cost": 0.0524
  }
}
```

### Derived Metrics Explained

| Metric | Formula | Use Case |
|--------|---------|----------|
| `usd_per_1m_tokens` | `(benchmark_run_cost / total_tokens) × 1,000,000` | Compare with API pricing (e.g., OpenAI) |
| `usd_per_request` | `benchmark_run_cost / requests` | Per-query cost attribution |
| `hourly_cluster_cost` | `(gpu × gpu_count) + (cpu × cpu_count) + mgmt` | Capacity planning |
| `benchmark_run_cost` | `hourly_cluster_cost × (duration_seconds / 3600)` | Actual benchmark cost |

---

## Cross-Provider Comparison

### Run Benchmarks on Each Provider

```bash
# Akamai LKE
./scripts/benchmark/run_ns.sh akamai-lke \
  --url http://172.236.105.4/api/query/stream \
  --with-cost

# AWS EKS (when deployed)
./scripts/benchmark/run_ns.sh aws-eks \
  --url http://<eks-lb>/api/query/stream \
  --with-cost

# GCP GKE (when deployed)
./scripts/benchmark/run_ns.sh gcp-gke \
  --url http://<gke-lb>/api/query/stream \
  --with-cost
```

### Compare Results

```bash
# View all cost results
find benchmarks -name "*-cost.json" -exec cat {} \; | jq -s '
  .[] | {
    provider: .provider,
    usd_per_1m_tokens: .derived_metrics.usd_per_1m_tokens,
    hourly_cost: .derived_metrics.hourly_cluster_cost,
    tokens_per_sec: .benchmark_summary.avg_tokens_per_sec
  }
'
```

### Example Comparison Table

| Provider | GPU | $/hr (cluster) | $/1M tokens | Tokens/sec | TTFT p50 |
|----------|-----|----------------|-------------|------------|----------|
| Akamai LKE | RTX 4000 Ada | $1.57 | $1.37 | 37.3 | 221ms |
| AWS EKS | NVIDIA L4 | $0.99 | TBD | TBD | TBD |
| GCP GKE | NVIDIA L4 | $1.18 | TBD | TBD | TBD |

---

## Understanding Cost Efficiency

### Cost per Token vs Performance

The key insight is the **cost-performance tradeoff**:

```
Cost Efficiency = Tokens per Dollar = 1,000,000 / usd_per_1m_tokens
```

Higher is better. A provider with:
- Lower $/1M tokens
- Higher tokens/sec
- Acceptable latency (TTFT, TPOT)

...is more cost-efficient.

### Factors Affecting Cost

1. **GPU Price**: Biggest factor. RTX 4000 Ada vs NVIDIA L4 have different price/performance
2. **Cluster Overhead**: EKS/GKE charge for control plane; LKE doesn't
3. **Network Egress**: Significant for high-traffic deployments
4. **Utilization**: Running benchmarks at full load shows peak efficiency

### Hidden Costs to Consider

Not captured in this model (add manually if significant):

- **Data transfer between regions** (multi-region setups)
- **Storage for model weights** (if not using shared registry)
- **Logging/monitoring costs** (CloudWatch, Stackdriver)
- **Reserved instance discounts** (1-year/3-year commitments)

---

## Updating Prices

Prices change. Update the cost config periodically:

```bash
# Update the as_of date and prices
nano cost/cost-config.yaml

# Verify by re-running cost computation on existing benchmarks
python3 scripts/cost/compute_cost.py \
  benchmarks/ns/akamai-lke/latest.json \
  cost/cost-config.yaml
```

### Price Check Frequency

| Scenario | Frequency |
|----------|-----------|
| Active benchmarking | Before each run |
| Production monitoring | Monthly |
| Cost reports | Quarterly |

---

## Scripting Examples

### Batch Process All Benchmarks

```bash
#!/bin/bash
for file in benchmarks/ns/*/*.json; do
  # Skip cost files
  [[ "$file" == *-cost.json ]] && continue
  
  # Auto-detect provider from path
  python3 scripts/cost/compute_cost.py \
    "$file" \
    cost/cost-config.yaml \
    --output "${file%.json}-cost.json"
done
```

### Extract Key Metrics for Reporting

```bash
# Get cost comparison as CSV
echo "provider,hourly_cost,usd_per_1m_tokens,tokens_per_sec"
for f in benchmarks/ns/*/*-cost.json; do
  jq -r '[
    .provider,
    .derived_metrics.hourly_cluster_cost,
    .derived_metrics.usd_per_1m_tokens,
    .benchmark_summary.avg_tokens_per_sec
  ] | @csv' "$f"
done
```

---

## Troubleshooting

### "Provider not found in cost config"

```bash
# Check available providers
grep -A1 "^  [a-z]" cost/cost-config.yaml

# Ensure provider name matches exactly
python3 scripts/cost/compute_cost.py ... --provider akamai-lke  # ✓
python3 scripts/cost/compute_cost.py ... --provider lke         # ✗
```

### "PyYAML not installed"

```bash
pip3 install pyyaml
```

### Cost Seems Too Low/High

1. Check `gpu_node_count` and `cpu_node_count` in config
2. Verify `duration_seconds` in benchmark results
3. Confirm GPU price matches your actual instance type

---

## Related Documentation

- [Benchmarking Guide](BENCHMARKING.md) - How to run benchmarks
- [Observability Guide](OBSERVABILITY.md) - Metrics and monitoring
- [Architecture Guide](ARCHITECTURE.md) - System components and dependencies
