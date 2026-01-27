# Cost Model

This document describes the cost model used for cross-provider benchmarking comparisons.

## Philosophy

The cost model is **inputs-driven** for repeatability:

1. **Explicit inputs** - All cost values are manually configured, not scraped or computed
2. **Timestamped** - `as_of` field records when prices were captured
3. **Provider-specific** - Each cloud provider has its own section
4. **Override-friendly** - Users can adjust values for their specific pricing (spot, reserved, etc.)

This approach ensures:
- Reproducible comparisons
- Transparent assumptions
- Easy updates when prices change

## Quick Start

```bash
# 1. Copy the example config
cp cost/cost-config.example.yaml cost/cost-config.yaml

# 2. Edit values for your environment (optional)
# The example includes reasonable defaults

# 3. Run a benchmark and save results
curl -s -X POST "http://<endpoint>/api/benchmark/run" \
  -H "Content-Type: application/json" \
  -d '{"concurrency": 10, "requests": 100}' > /tmp/job.json

# Wait for completion, then save results
JOB=$(cat /tmp/job.json | jq -r '.job_name')
curl -s "http://<endpoint>/api/benchmark/logs?job=$JOB" | tail -1 > benchmarks/lke/results.json

# 4. Compute cost metrics
python scripts/cost/compute_cost.py benchmarks/lke/results.json cost/cost-config.yaml --provider akamai-lke
```

## Configuration File

Location: `cost/cost-config.yaml` (copy from `cost/cost-config.example.yaml`)

### Structure

```yaml
providers:
  akamai-lke:
    as_of: "2026-01-27"
    notes: "Source and assumptions"
    
    # Required: Node costs
    gpu_node_usd_per_hr: 1.50
    cpu_node_usd_per_hr: 0.036
    
    # Optional: Network costs
    egress_usd_per_gb: 0.005
    ingress_usd_per_gb: 0.0
    
    # Optional: Storage and management
    storage_usd_per_gb_month: 0.10
    cluster_mgmt_usd_per_hr: 0.0

benchmark_context:
  gpu_node_count: 1
  cpu_node_count: 2
```

### Provider Sections

Each provider section includes:

| Field | Description | Required |
|-------|-------------|----------|
| `as_of` | Date prices were captured | Yes |
| `notes` | Source/assumptions documentation | Yes |
| `gpu_node_usd_per_hr` | GPU node hourly cost | Yes |
| `cpu_node_usd_per_hr` | CPU node hourly cost | Yes |
| `egress_usd_per_gb` | Outbound network cost | No |
| `ingress_usd_per_gb` | Inbound network cost | No |
| `storage_usd_per_gb_month` | Persistent storage cost | No |
| `cluster_mgmt_usd_per_hr` | Control plane/management fee | No |

## Derived Metrics

The `compute_cost.py` script outputs:

| Metric | Description |
|--------|-------------|
| `usd_per_1m_tokens` | Cost per million tokens generated |
| `usd_per_request` | Cost per benchmark request |
| `usd_per_successful_request` | Cost per successful request |
| `hourly_cluster_cost` | Total cluster cost per hour |
| `benchmark_run_cost` | Total cost of the benchmark run |

### Calculation Details

```
hourly_cluster_cost = (gpu_node_usd_per_hr × gpu_count) 
                    + (cpu_node_usd_per_hr × cpu_count)
                    + cluster_mgmt_usd_per_hr

benchmark_run_cost = hourly_cluster_cost × (duration_seconds / 3600)

usd_per_1m_tokens = benchmark_run_cost / total_tokens × 1,000,000

usd_per_request = benchmark_run_cost / total_requests
```

## Example Output

```json
{
  "provider": "akamai-lke",
  "benchmark_file": "benchmarks/lke/2026-01-27.json",
  "cost_config_as_of": "2026-01-27",
  "benchmark_summary": {
    "requests": 100,
    "success": 100,
    "errors": 0,
    "total_tokens": 45000,
    "duration_seconds": 120.5,
    "avg_tokens_per_sec": 43.78
  },
  "cost_inputs": {
    "gpu_node_usd_per_hr": 1.5,
    "cpu_node_usd_per_hr": 0.036,
    "cluster_mgmt_usd_per_hr": 0,
    "gpu_node_count": 1,
    "cpu_node_count": 2
  },
  "derived_metrics": {
    "usd_per_1m_tokens": 1.168,
    "usd_per_request": 0.000526,
    "usd_per_successful_request": 0.000526,
    "hourly_cluster_cost": 1.572,
    "benchmark_run_cost": 0.0526
  }
}
```

## Price Sources

### Akamai/Linode
- https://www.linode.com/pricing/
- GPU: Dedicated GPU instances
- Network: Transfer pool model (overage rates apply)

### AWS
- https://aws.amazon.com/ec2/pricing/on-demand/
- https://aws.amazon.com/eks/pricing/
- GPU: g6 instances (NVIDIA L4)
- Network: Standard data transfer rates

### GCP
- https://cloud.google.com/compute/pricing
- https://cloud.google.com/kubernetes-engine/pricing
- GPU: g2 instances (NVIDIA L4)
- Network: Premium tier pricing

## Auto-Update (TODO)

A future `make update-prices` target will:
1. Generate `cost/cost-config.autogen.yaml` with latest list prices
2. Record `as_of` timestamp
3. Never overwrite user's `cost-config.yaml`

For now, manually update prices when needed.

## Best Practices

1. **Document your sources** - Use the `notes` field
2. **Update `as_of`** when changing prices
3. **Use consistent pricing models** - Don't mix spot and on-demand across providers
4. **Include all relevant costs** - Management fees, storage, network
5. **Version control your config** - Track price changes over time
