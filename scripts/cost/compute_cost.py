#!/usr/bin/env python3
"""
Compute derived cost metrics from benchmark results and cost configuration.

Usage:
    python scripts/cost/compute_cost.py <benchmark_json> <cost_config_yaml> [--provider <name>]

Example:
    python scripts/cost/compute_cost.py benchmarks/lke/2026-01-27.json cost/cost-config.yaml --provider akamai-lke

Output (JSON):
    {
        "provider": "akamai-lke",
        "benchmark_file": "benchmarks/lke/2026-01-27.json",
        "cost_config_as_of": "2026-01-27",
        "benchmark_summary": {
            "requests": 100,
            "success": 100,
            "errors": 0,
            "total_tokens": 12500,
            "duration_seconds": 120.5,
            "avg_tokens_per_sec": 103.7
        },
        "cost_inputs": {
            "gpu_node_usd_per_hr": 1.50,
            "cpu_node_usd_per_hr": 0.036,
            "gpu_node_count": 1,
            "cpu_node_count": 2
        },
        "derived_metrics": {
            "usd_per_1m_tokens": 0.0402,
            "usd_per_request": 0.000502,
            "usd_per_successful_request": 0.000502,
            "hourly_cluster_cost": 1.572,
            "benchmark_run_cost": 0.0527
        }
    }
"""

import argparse
import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Error: PyYAML is required. Install with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


def load_benchmark_results(path: str) -> dict:
    """Load benchmark results JSON file."""
    with open(path, "r") as f:
        return json.load(f)


def load_cost_config(path: str) -> dict:
    """Load cost configuration YAML file."""
    with open(path, "r") as f:
        return yaml.safe_load(f)


def extract_benchmark_summary(results: dict) -> dict:
    """Extract summary metrics from benchmark results."""
    # Handle different benchmark output formats
    
    # Format 1: Direct summary (from stream_bench.py)
    if "requests" in results and "success" in results:
        summary = {
            "requests": results.get("requests", 0),
            "success": results.get("success", 0),
            "errors": results.get("errors", 0),
            "avg_tokens_per_sec": results.get("avg_tokens_per_sec", 0),
        }
        # Estimate total tokens if not provided
        if "total_tokens" in results:
            summary["total_tokens"] = results["total_tokens"]
        else:
            # Rough estimate: avg_tokens_per_sec * latency_p50 * requests / 1000
            latency_p50_sec = results.get("latency_p50_ms", 10000) / 1000
            summary["total_tokens"] = int(
                summary["avg_tokens_per_sec"] * latency_p50_sec * summary["success"]
            )
        
        # Duration: estimate from latency and concurrency
        if "duration_seconds" in results:
            summary["duration_seconds"] = results["duration_seconds"]
        else:
            concurrency = results.get("concurrency", 10)
            latency_p50_sec = results.get("latency_p50_ms", 10000) / 1000
            summary["duration_seconds"] = (summary["requests"] / concurrency) * latency_p50_sec
        
        return summary
    
    # Format 2: Wrapped format with "summary" key
    if "summary" in results:
        return extract_benchmark_summary(results["summary"])
    
    raise ValueError("Unrecognized benchmark results format")


def compute_derived_metrics(
    benchmark_summary: dict,
    provider_config: dict,
    context: dict | None = None,
) -> dict:
    """Compute cost-derived metrics."""
    
    # Get node counts from context or defaults
    gpu_node_count = (context or {}).get("gpu_node_count", 1)
    cpu_node_count = (context or {}).get("cpu_node_count", 2)
    
    # Calculate hourly cluster cost
    gpu_cost_hr = provider_config.get("gpu_node_usd_per_hr", 0) * gpu_node_count
    cpu_cost_hr = provider_config.get("cpu_node_usd_per_hr", 0) * cpu_node_count
    mgmt_cost_hr = provider_config.get("cluster_mgmt_usd_per_hr", 0)
    hourly_cluster_cost = gpu_cost_hr + cpu_cost_hr + mgmt_cost_hr
    
    # Calculate benchmark run cost
    duration_seconds = benchmark_summary.get("duration_seconds", 60)
    duration_hours = duration_seconds / 3600
    benchmark_run_cost = hourly_cluster_cost * duration_hours
    
    # Calculate per-token and per-request costs
    total_tokens = benchmark_summary.get("total_tokens", 0)
    total_requests = benchmark_summary.get("requests", 0)
    successful_requests = benchmark_summary.get("success", 0)
    
    usd_per_1m_tokens = (benchmark_run_cost / total_tokens * 1_000_000) if total_tokens > 0 else 0
    usd_per_request = (benchmark_run_cost / total_requests) if total_requests > 0 else 0
    usd_per_successful_request = (benchmark_run_cost / successful_requests) if successful_requests > 0 else 0
    
    return {
        "usd_per_1m_tokens": round(usd_per_1m_tokens, 6),
        "usd_per_request": round(usd_per_request, 6),
        "usd_per_successful_request": round(usd_per_successful_request, 6),
        "hourly_cluster_cost": round(hourly_cluster_cost, 4),
        "benchmark_run_cost": round(benchmark_run_cost, 6),
    }


def main():
    parser = argparse.ArgumentParser(
        description="Compute derived cost metrics from benchmark results"
    )
    parser.add_argument(
        "benchmark_json",
        help="Path to benchmark results JSON file",
    )
    parser.add_argument(
        "cost_config_yaml",
        help="Path to cost configuration YAML file",
    )
    parser.add_argument(
        "--provider",
        default=None,
        help="Provider name (akamai-lke, aws-eks, gcp-gke). Auto-detected from path if not specified.",
    )
    parser.add_argument(
        "--output",
        "-o",
        default=None,
        help="Output file path (default: stdout)",
    )
    
    args = parser.parse_args()
    
    # Load inputs
    try:
        benchmark_results = load_benchmark_results(args.benchmark_json)
    except Exception as e:
        print(f"Error loading benchmark results: {e}", file=sys.stderr)
        sys.exit(1)
    
    try:
        cost_config = load_cost_config(args.cost_config_yaml)
    except Exception as e:
        print(f"Error loading cost config: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Determine provider
    provider = args.provider
    if not provider:
        # Try to auto-detect from path
        path_lower = args.benchmark_json.lower()
        if "lke" in path_lower or "akamai" in path_lower:
            provider = "akamai-lke"
        elif "eks" in path_lower or "aws" in path_lower:
            provider = "aws-eks"
        elif "gke" in path_lower or "gcp" in path_lower:
            provider = "gcp-gke"
        else:
            print("Error: Could not auto-detect provider. Use --provider flag.", file=sys.stderr)
            sys.exit(1)
    
    # Get provider config
    providers = cost_config.get("providers", {})
    if provider not in providers:
        print(f"Error: Provider '{provider}' not found in cost config.", file=sys.stderr)
        print(f"Available providers: {list(providers.keys())}", file=sys.stderr)
        sys.exit(1)
    
    provider_config = providers[provider]
    context = cost_config.get("benchmark_context", {})
    
    # Extract benchmark summary
    try:
        benchmark_summary = extract_benchmark_summary(benchmark_results)
    except ValueError as e:
        print(f"Error parsing benchmark results: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Compute derived metrics
    derived_metrics = compute_derived_metrics(benchmark_summary, provider_config, context)
    
    # Build output
    output = {
        "provider": provider,
        "benchmark_file": args.benchmark_json,
        "cost_config_as_of": provider_config.get("as_of", "unknown"),
        "benchmark_summary": benchmark_summary,
        "cost_inputs": {
            "gpu_node_usd_per_hr": provider_config.get("gpu_node_usd_per_hr", 0),
            "cpu_node_usd_per_hr": provider_config.get("cpu_node_usd_per_hr", 0),
            "cluster_mgmt_usd_per_hr": provider_config.get("cluster_mgmt_usd_per_hr", 0),
            "gpu_node_count": context.get("gpu_node_count", 1),
            "cpu_node_count": context.get("cpu_node_count", 2),
        },
        "derived_metrics": derived_metrics,
    }
    
    # Output
    output_json = json.dumps(output, indent=2)
    if args.output:
        with open(args.output, "w") as f:
            f.write(output_json)
        print(f"Output written to {args.output}", file=sys.stderr)
    else:
        print(output_json)


if __name__ == "__main__":
    main()
