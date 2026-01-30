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
    as_of: "2026-01-30"                    # When prices were captured
    notes: "Linode list prices - actual deployed instances"
    
    # Core compute costs (USD per hour)
    gpu_node_usd_per_hr: 0.52              # g2-gpu-rtx4000a1-s (RTX 4000 Ada Small)
    cpu_node_usd_per_hr: 0.03              # g6-standard-2 (Shared CPU 4GB)
    
    # Network costs (USD per GB)
    egress_usd_per_gb: 0.005               # Outbound data transfer (overage)
    ingress_usd_per_gb: 0.0                # Inbound (free)
    
    # Storage costs
    storage_usd_per_gb_month: 0.10         # linode-block-storage (NVMe)
    
    # Cluster overhead
    cluster_mgmt_usd_per_hr: 0.0           # No control plane fee

  aws-eks:
    as_of: "2026-01-27"
    gpu_node_usd_per_hr: 0.8048            # g6.xlarge (NVIDIA L4)
    cpu_node_usd_per_hr: 0.096             # m5.large
    cluster_mgmt_usd_per_hr: 0.10          # EKS control plane

  gcp-gke:
    as_of: "2026-01-30"
    gpu_node_usd_per_hr: 0.8536            # g2-standard-8 (NVIDIA L4 24GB)
    cpu_node_usd_per_hr: 0.134             # e2-standard-4 (actual deployed)
    cluster_mgmt_usd_per_hr: 0.10          # GKE management fee
    storage_usd_per_gb_month: 0.17         # pd-ssd (standard-rwo)

# Benchmark context (node counts for cost attribution)
benchmark_context:
  gpu_node_count: 1                        # Number of GPU nodes
  cpu_node_count: 2                        # Number of CPU nodes
```

### Provider Pricing Sources (Actual Deployed Instances)

| Provider | GPU Instance | CPU Instance | Price Source |
|----------|--------------|--------------|--------------|
| Akamai LKE | g2-gpu-rtx4000a1-s (RTX 4000 Ada 20GB) $0.52/hr | g6-standard-2 (2 vCPU, 4GB) ~$0.03/hr | [Linode Pricing](https://www.linode.com/pricing/) |
| AWS EKS | g6.xlarge (NVIDIA L4 24GB) $0.8048/hr | m5.large (2 vCPU, 8GB) $0.096/hr | [EC2 Pricing](https://aws.amazon.com/ec2/pricing/on-demand/) |
| GCP GKE | g2-standard-8 (NVIDIA L4 24GB) $0.8536/hr | e2-standard-4 (4 vCPU, 16GB) $0.134/hr | [GCE Pricing](https://cloud.google.com/compute/vm-instance-pricing) |

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

### Example Comparison Table (Actual Deployed - January 2026)

| Provider | GPU | Instance | $/hr (cluster) | Monthly |
|----------|-----|----------|----------------|---------|
| Akamai LKE | RTX 4000 Ada | g2-gpu-rtx4000a1-s | **$0.58** | $424 |
| GCP GKE | NVIDIA L4 | g2-standard-8 | **$1.22** | $893 |
| AWS EKS | NVIDIA L4 | g6.xlarge | ~$1.10 | ~$800 (destroyed) |

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

## Actual Infrastructure (Queried January 30, 2026)

This section documents the **actual deployed infrastructure** queried directly from the live clusters.

### GCP GKE

**Cluster Info:**
- Region: `us-central1` / Zone: `us-central1-a`
- Kubernetes Control Plane: `https://35.194.42.146`
- Kubeconfig: `~/.kube/gke-kubeconfig.yaml`

**Compute Nodes (Queried January 30, 2026):**

| Node Name | Instance Type | vCPU | Memory | GPU | On-Demand $/hr |
|-----------|---------------|------|--------|-----|----------------|
| gke-rag-ray-haystack-rag-ray-haystack-2279193b-b4gd | `g2-standard-8` | 8 | 32 GB | 1x NVIDIA L4 (24GB) | **$0.8536** |
| gke-rag-ray-haystack-rag-ray-haystack-c0133a71-21wq | `e2-standard-4` | 4 | 16 GB | — | **$0.134** |
| gke-rag-ray-haystack-rag-ray-haystack-c0133a71-h5jk | `e2-standard-4` | 4 | 16 GB | — | **$0.134** |

**Storage (Queried January 30, 2026):**

| PVC | Namespace | Storage Class | Provisioned | Actual Used | $/GB/month |
|-----|-----------|---------------|-------------|-------------|------------|
| qdrant-storage-rag-app-rag-app-qdrant-0 | rag-app | `standard-rwo` | 10 Gi | **40 KB (0.0004%)** | $0.17 |

**Pod Placement:**
- vLLM → GPU node (2279193b-b4gd)
- Backend, Ray worker → CPU node (c0133a71-21wq)
- Frontend, Qdrant, Ray head → CPU node (c0133a71-h5jk)

**Monthly Cost Breakdown (On-Demand):**

| Cost Category | Calculation | Monthly Cost |
|---------------|-------------|--------------|
| GPU Node (1x g2-standard-8) | $0.8536 × 730 hrs | $623.13 |
| CPU Nodes (2x e2-standard-4) | $0.134 × 730 hrs × 2 | $195.64 |
| GKE Management Fee | $0.10 × 730 hrs | $73.00 |
| Storage (10 GB pd-ssd) | 10 GB × $0.17 | $1.70 |
| **Total** | | **$893.47** |

**Hourly Run Rate:** $1.22/hr

**Storage Optimization Note:** Only 40 KB of 10 GB is used (0.0004%). Could reduce to 1 GB minimum and save $1.53/month.

**Commitment Discounts Available:**
- 1-year CUD: ~37% savings on compute
- 3-year CUD: ~55% savings on compute
- Spot VMs: ~60% savings (but can be preempted)

**Pricing Sources (January 2026):**
- [GCP Compute Engine Pricing](https://cloud.google.com/compute/vm-instance-pricing)
- [GKE Pricing](https://cloud.google.com/kubernetes-engine/pricing)
- [Persistent Disk Pricing](https://cloud.google.com/compute/disks-image-pricing)

---

### Akamai LKE

**Cluster Info:**
- Region: `us-ord` (Chicago)
- Control Plane: `https://06d998c7-a2de-4b55-a7c6-8b20c0d47a81.us-ord-2-gw.linodelke.net:443`
- Kubeconfig: `~/.kube/rag-ray-haystack-kubeconfig.yaml`

**Compute Nodes (Queried January 30, 2026):**

| Node Name | Instance Type | vCPU | Memory | GPU | On-Demand $/hr |
|-----------|---------------|------|--------|-----|----------------|
| lke561078-818958-4d4783670000 | `g2-gpu-rtx4000a1-s` | 4 | 16 GB | 1x RTX 4000 Ada (20GB) | **$0.52** |
| lke561078-818957-4ab4a6130000 | `g6-standard-2` | 2 | 4 GB | — | **~$0.03** |
| lke561078-818957-50ad39bd0000 | `g6-standard-2` | 2 | 4 GB | — | **~$0.03** |

**Storage (Queried January 30, 2026):**

| PVC | Namespace | Storage Class | Provisioned | Actual Used | $/GB/month |
|-----|-----------|---------------|-------------|-------------|------------|
| qdrant-storage-rag-app-rag-app-qdrant-0 | rag-app | `linode-block-storage` | 10 Gi | **2.1 MB (0.02%)** | $0.10 |

**Pod Placement:**
- Backend, Qdrant, vLLM → GPU node (lke561078-818958)
- Frontend → CPU node (lke561078-818957)

**Monthly Cost Breakdown (On-Demand):**

| Cost Category | Calculation | Monthly Cost |
|---------------|-------------|--------------|
| GPU Node (1x g2-gpu-rtx4000a1-s) | $0.52 × 730 hrs | $379.60 |
| CPU Nodes (2x g6-standard-2) | $0.03 × 730 hrs × 2 | $43.80 |
| LKE Management Fee | $0.00 | $0.00 |
| Storage (10 GB block) | 10 GB × $0.10 | $1.00 |
| **Total** | | **$424.40** |

**Hourly Run Rate:** $0.58/hr

**Storage Optimization Note:** Only 2.1 MB of 10 GB is used (0.02%). Could reduce to 1 GB minimum and save $0.90/month.

**Pricing Sources (January 2026):**
- [Linode Pricing](https://www.linode.com/pricing/)
- [Linode GPU Plans](https://www.linode.com/docs/products/compute/compute-instances/plans/gpu/)

---

### AWS EKS

**Cluster Info:**
- Region: `us-east-1`
- Zones: `us-east-1c`, `us-east-1d`, `us-east-1f` (multi-AZ)
- Kubernetes Control Plane: `https://B698E4381E416AB41D3F0F6ABB030D84.gr7.us-east-1.eks.amazonaws.com`
- Kubeconfig: `~/.kube/eks-kubeconfig-fresh.yaml`

**Compute Nodes (Queried January 30, 2026):**

| Node Name | Instance Type | vCPU | Memory | GPU | Zone | On-Demand $/hr |
|-----------|---------------|------|--------|-----|------|----------------|
| ip-172-31-43-85.ec2.internal | `g6.xlarge` | 4 | 16 GB | 1x NVIDIA L4 (24GB) | us-east-1d | **$0.80** |
| ip-172-31-56-49.ec2.internal | `m5.large` | 2 | 8 GB | — | us-east-1c | **$0.096** |
| ip-172-31-92-17.ec2.internal | `m5.large` | 2 | 8 GB | — | us-east-1f | **$0.096** |

**Storage (Queried January 30, 2026):**

| PVC | Namespace | Storage Class | Provisioned | Actual Used | $/GB/month |
|-----|-----------|---------------|-------------|-------------|------------|
| qdrant-storage-rag-app-rag-app-qdrant-0 | rag-app | `gp2` (EBS) | 10 Gi | **40 KB (0.0004%)** | $0.10 |

**Pod Placement:**
- vLLM → GPU node (us-east-1d)
- Backend, Ray worker → CPU node (us-east-1c)
- Frontend, Qdrant, Ray head → CPU node (us-east-1f)

**Monthly Cost Breakdown (On-Demand):**

| Cost Category | Calculation | Monthly Cost |
|---------------|-------------|--------------|
| **Compute** | | |
| GPU Node (1x g6.xlarge) | $0.80 × 730 hrs | $584.00 |
| CPU Nodes (2x m5.large) | $0.096 × 730 hrs × 2 | $140.16 |
| **Management** | | |
| EKS Control Plane (Standard) | $0.10 × 730 hrs | $73.00 |
| **Storage** | | |
| EBS gp2 (10 GB) | 10 GB × $0.10 | $1.00 |
| **Networking (Estimated)** | | |
| NAT Gateway (if used) | $0.045 × 730 hrs | $32.85 |
| NAT Data Processing (~100GB) | 100 GB × $0.045 | $4.50 |
| Data Transfer Out (~100GB) | 100 GB × $0.09 | $9.00 |
| Cross-AZ Traffic (multi-AZ) | ~50 GB × $0.01 × 2 | $1.00 |
| **Total (with networking)** | | **$845.51** |
| **Total (compute only)** | | **$798.16** |

**Hourly Run Rate:** $1.16/hr (with networking) | $1.09/hr (compute only)

**Networking Notes:**
- Nodes span 3 AZs (us-east-1c, us-east-1d, us-east-1f) - cross-AZ traffic is charged
- NAT Gateway costs apply if pods need internet egress (model downloads, API calls)
- Data transfer to internet: First 100 GB/month is $0.09/GB, then tiered down
- Cross-AZ traffic: $0.01/GB in each direction

**Storage Optimization Note:** Only 40 KB of 10 GB is used (0.0004%). Could reduce to 1 GB minimum and save $0.90/month.

**Cost Optimization Options:**
- **Spot Instances**: Save ~60-70% on GPU nodes (but can be interrupted)
- **Reserved Instances (1-year)**: Save ~30-40% on compute
- **Savings Plans (3-year)**: Save ~50-60% on compute
- **Single-AZ Deployment**: Eliminate cross-AZ charges (reduced availability)
- **VPC Endpoints**: Avoid NAT Gateway for AWS service traffic

**Pricing Sources (January 2026):**
- [EC2 On-Demand Pricing](https://aws.amazon.com/ec2/pricing/on-demand/)
- [EKS Pricing](https://aws.amazon.com/eks/pricing/)
- [EBS Pricing](https://aws.amazon.com/ebs/pricing/)
- [Data Transfer Pricing](https://aws.amazon.com/ec2/pricing/on-demand/#Data_Transfer)
- [NAT Gateway Pricing](https://aws.amazon.com/vpc/pricing/)

---

### Cost Comparison Summary (January 30, 2026)

**Compute + Management + Storage (excluding network):**

| Provider | Status | GPU $/hr | CPU $/hr | Mgmt $/hr | Storage $/GB/mo | Monthly Total | Hourly Total |
|----------|--------|----------|----------|-----------|-----------------|---------------|--------------|
| **Akamai LKE** | ✅ Running | $0.52 | ~$0.03 | $0.00 | $0.10 | **$424.40** | $0.58 |
| **AWS EKS** | ✅ Running | $0.80 | $0.096 | $0.10 | $0.10 | **$798.16** | $1.09 |
| **GCP GKE** | ✅ Running | $0.8536 | $0.134 | $0.10 | $0.17 | **$893.47** | $1.22 |

**Including Estimated Networking (~100GB egress/month):**

| Provider | Compute + Mgmt + Storage | Networking | Total w/ Network | Hourly Total |
|----------|--------------------------|------------|------------------|--------------|
| **Akamai LKE** | $424.40 | ~$0.50 (egress only) | **$424.90** | $0.58 |
| **AWS EKS** | $798.16 | ~$47.35 (NAT + egress + cross-AZ) | **$845.51** | $1.16 |
| **GCP GKE** | $893.47 | ~$12.00 (egress only) | **$905.47** | $1.24 |

**Key Findings:**
1. **Akamai LKE is 50% cheaper than AWS EKS** and **53% cheaper than GCP GKE**
2. **No management fee** on LKE saves $73/month vs AWS/GCP
3. **AWS networking adds significant cost**: NAT Gateway ($32.85/mo) + data processing + cross-AZ traffic
4. **Storage is massively over-provisioned**: 10GB allocated, <1MB used on all providers
5. **GCP has most powerful CPU nodes** (4 vCPU vs 2 vCPU) but highest total cost
6. **AWS multi-AZ deployment** increases reliability but adds cross-AZ charges

---

## Related Documentation

- [Benchmarking Guide](BENCHMARKING.md) - How to run benchmarks
- [Observability Guide](OBSERVABILITY.md) - Metrics and monitoring
- [Architecture Guide](ARCHITECTURE.md) - System components and dependencies
