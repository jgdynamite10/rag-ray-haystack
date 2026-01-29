#!/usr/bin/env python3
"""
Lightweight streaming benchmark for /query/stream.

Measures TTFT, TPOT, tokens/sec (approx), and total latency.
Portable across Akamai LKE, AWS EKS, and GCP GKE.

Phase 2 additions:
- TPOT (time per output token)
- Warmup vs measured phases
- Workload manifest support
- Run metadata collection
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import os
import statistics
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import httpx


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = max(0, int(len(ordered) * pct) - 1)
    return ordered[index]


def collect_run_metadata() -> dict[str, Any]:
    """Collect run metadata from environment variables (best-effort)."""
    return {
        "provider": os.getenv("RAG_PROVIDER") or os.getenv("PROVIDER") or None,
        "region": os.getenv("RAG_REGION") or os.getenv("REGION") or None,
        "cluster_label": os.getenv("CLUSTER_LABEL") or os.getenv("CLUSTER_NAME") or None,
        "node_instance_type": os.getenv("NODE_INSTANCE_TYPE") or None,
        "gpu_model": os.getenv("GPU_MODEL") or None,
        "gpu_count": int(os.getenv("GPU_COUNT") or "0") or None,
        "ray_version": os.getenv("RAY_VERSION") or None,
        "vllm_version": os.getenv("VLLM_VERSION") or None,
        "model_id": os.getenv("VLLM_MODEL") or os.getenv("MODEL_ID") or None,
        "dtype": os.getenv("VLLM_DTYPE") or None,
        "quantization": os.getenv("VLLM_QUANTIZATION") or None,
        "max_model_len": int(os.getenv("VLLM_MAX_MODEL_LEN") or "0") or None,
        "backend_image_tag": os.getenv("BACKEND_IMAGE_TAG") or None,
        "frontend_image_tag": os.getenv("FRONTEND_IMAGE_TAG") or None,
        "vllm_image_tag": os.getenv("VLLM_IMAGE_TAG") or None,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


async def run_request(
    client: httpx.AsyncClient,
    url: str,
    prompt: str,
    request_id: int,
    max_output_tokens: int | None = None,
) -> dict[str, Any]:
    request_payload: dict[str, Any] = {"query": prompt}
    if max_output_tokens is not None:
        request_payload["max_tokens"] = max_output_tokens
    start = time.perf_counter()
    ttft: Optional[float] = None
    first_token_time: Optional[float] = None
    last_token_time: Optional[float] = None
    token_count = 0
    done_token_count: Optional[int] = None
    done_prompt_tokens: Optional[int] = None

    try:
        async with client.stream("POST", url, json=request_payload) as response:
            response.raise_for_status()
            event_name = None
            event_data = None

            async for line in response.aiter_lines():
                if line.startswith("event:"):
                    event_name = line.replace("event:", "", 1).strip()
                elif line.startswith("data:"):
                    event_data = line.replace("data:", "", 1).strip()
                elif line == "":
                    if not event_name or not event_data:
                        event_name = None
                        event_data = None
                        continue
                    payload = json.loads(event_data)
                    if event_name == "ttft" and ttft is None:
                        ttft = time.perf_counter() - start
                        first_token_time = time.perf_counter()
                    if event_name == "token":
                        current_time = time.perf_counter()
                        if ttft is None:
                            ttft = current_time - start
                            first_token_time = current_time
                        last_token_time = current_time
                        token_count += max(1, len(payload.get("text", "").split()))
                    if event_name == "done":
                        done_token_count = payload.get("token_count")
                        done_prompt_tokens = payload.get("prompt_tokens")
                        break
                    event_name = None
                    event_data = None

        total = time.perf_counter() - start
        final_token_count = done_token_count if done_token_count is not None else token_count

        # Compute TPOT (time per output token)
        # TPOT = (last_token_time - first_token_time) / output_token_count
        tpot: Optional[float] = None
        if first_token_time and last_token_time and final_token_count > 1:
            generation_duration = last_token_time - first_token_time
            tpot = generation_duration / (final_token_count - 1)  # -1 because first token doesn't have TPOT

        tokens_per_second = final_token_count / total if total > 0 else 0.0

        return {
            "id": request_id,
            "success": True,
            "ttft": ttft or total,
            "total": total,
            "tpot": tpot,
            "token_count": final_token_count,
            "prompt_tokens": done_prompt_tokens,
            "tokens_per_second": tokens_per_second,
        }
    except Exception as exc:  # noqa: BLE001
        return {
            "id": request_id,
            "success": False,
            "error": str(exc),
        }


async def worker(
    name: int,
    client: httpx.AsyncClient,
    url: str,
    prompt: str,
    counter: asyncio.Lock,
    remaining: list[int],
    results: list[dict[str, Any]],
    max_output_tokens: int | None = None,
) -> None:
    while True:
        async with counter:
            if remaining[0] <= 0:
                return
            remaining[0] -= 1
            request_id = remaining[0]
        result = await run_request(client, url, prompt, request_id, max_output_tokens)
        results.append(result)


async def run_phase(
    client: httpx.AsyncClient,
    url: str,
    prompt: str,
    concurrency: int,
    total_requests: int,
    max_output_tokens: int | None = None,
) -> list[dict[str, Any]]:
    """Run a single benchmark phase (warmup or measured)."""
    results: list[dict[str, Any]] = []
    remaining = [total_requests]
    lock = asyncio.Lock()

    tasks = [
        asyncio.create_task(
            worker(i, client, url, prompt, lock, remaining, results, max_output_tokens)
        )
        for i in range(concurrency)
    ]
    await asyncio.gather(*tasks)
    return results


def compute_phase_stats(results: list[dict[str, Any]]) -> dict[str, Any]:
    """Compute statistics for a benchmark phase."""
    success = [r for r in results if r.get("success")]
    failures = [r for r in results if not r.get("success")]

    ttft_values = [r["ttft"] for r in success]
    total_values = [r["total"] for r in success]
    tokens_per_second = [r["tokens_per_second"] for r in success]
    tpot_values = [r["tpot"] for r in success if r.get("tpot") is not None]
    token_counts = [r["token_count"] for r in success if r.get("token_count")]
    prompt_token_counts = [r["prompt_tokens"] for r in success if r.get("prompt_tokens") is not None]

    return {
        "requests": len(results),
        "success": len(success),
        "errors": len(failures),
        "ttft_p50_ms": round(percentile(ttft_values, 0.50) * 1000, 2) if ttft_values else None,
        "ttft_p95_ms": round(percentile(ttft_values, 0.95) * 1000, 2) if ttft_values else None,
        "latency_p50_ms": round(percentile(total_values, 0.50) * 1000, 2) if total_values else None,
        "latency_p95_ms": round(percentile(total_values, 0.95) * 1000, 2) if total_values else None,
        "tpot_p50_ms": round(percentile(tpot_values, 0.50) * 1000, 2) if tpot_values else None,
        "tpot_p95_ms": round(percentile(tpot_values, 0.95) * 1000, 2) if tpot_values else None,
        "avg_tokens_per_sec": round(
            statistics.mean(tokens_per_second) if tokens_per_second else 0.0, 2
        ),
        "total_tokens": sum(token_counts) if token_counts else 0,
        "avg_output_tokens": round(
            statistics.mean(token_counts) if token_counts else 0.0, 1
        ),
        "total_prompt_tokens": sum(prompt_token_counts) if prompt_token_counts else None,
        "avg_prompt_tokens": round(
            statistics.mean(prompt_token_counts) if prompt_token_counts else 0.0, 1
        ) if prompt_token_counts else None,
    }


async def run_benchmark(args: argparse.Namespace) -> dict[str, Any]:
    # Load workload manifest if provided
    workload_manifest: Optional[dict[str, Any]] = None
    manifest_hash: Optional[str] = None
    if args.workload:
        try:
            import yaml
            workload_manifest = yaml.safe_load(Path(args.workload).read_text())
            manifest_hash = hashlib.sha256(
                json.dumps(workload_manifest, sort_keys=True).encode()
            ).hexdigest()[:16]
            # Override args from manifest
            if "concurrency" in workload_manifest:
                args.concurrency = workload_manifest["concurrency"]
            if "requests" in workload_manifest:
                args.requests = workload_manifest["requests"]
            if "warmup_requests" in workload_manifest:
                args.warmup_requests = workload_manifest["warmup_requests"]
            if "timeout" in workload_manifest:
                args.timeout = workload_manifest["timeout"]
            if "max_output_tokens" in workload_manifest:
                args.max_output_tokens = workload_manifest["max_output_tokens"]
        except ImportError:
            print("Warning: PyYAML not installed, skipping workload manifest", file=__import__('sys').stderr)
        except Exception as e:
            print(f"Warning: Failed to load workload manifest: {e}", file=__import__('sys').stderr)

    prompt = "Explain what this system is and why vLLM matters."
    if args.prompt_file:
        prompt = Path(args.prompt_file).read_text().strip()
    elif workload_manifest and "prompts" in workload_manifest:
        prompts = workload_manifest["prompts"]
        prompt = prompts[0] if prompts else prompt

    timeout = httpx.Timeout(args.timeout)
    limits = httpx.Limits(max_keepalive_connections=args.concurrency)

    warmup_stats: Optional[dict[str, Any]] = None
    measured_results: list[dict[str, Any]] = []
    benchmark_start = time.perf_counter()

    async with httpx.AsyncClient(timeout=timeout, limits=limits) as client:
        # Warmup phase (if configured)
        if args.warmup_requests > 0:
            print(f"Running warmup phase: {args.warmup_requests} requests...", file=__import__('sys').stderr)
            warmup_results = await run_phase(
                client, args.url, prompt, args.concurrency, args.warmup_requests,
                args.max_output_tokens
            )
            warmup_stats = compute_phase_stats(warmup_results)
            warmup_stats["phase"] = "warmup"

        # Measured phase
        print(f"Running measured phase: {args.requests} requests...", file=__import__('sys').stderr)
        measured_results = await run_phase(
            client, args.url, prompt, args.concurrency, args.requests,
            args.max_output_tokens
        )

    measured_stats = compute_phase_stats(measured_results)
    measured_stats["phase"] = "measured"
    benchmark_duration = time.perf_counter() - benchmark_start

    # Collect run metadata
    run_metadata = collect_run_metadata()

    # Build comprehensive output
    summary = {
        # Primary metrics (from measured phase only)
        "requests": measured_stats["requests"],
        "concurrency": args.concurrency,
        "success": measured_stats["success"],
        "errors": measured_stats["errors"],
        "ttft_p50_ms": measured_stats["ttft_p50_ms"],
        "ttft_p95_ms": measured_stats["ttft_p95_ms"],
        "latency_p50_ms": measured_stats["latency_p50_ms"],
        "latency_p95_ms": measured_stats["latency_p95_ms"],
        "tpot_p50_ms": measured_stats.get("tpot_p50_ms"),
        "tpot_p95_ms": measured_stats.get("tpot_p95_ms"),
        "avg_tokens_per_sec": measured_stats["avg_tokens_per_sec"],
        "total_tokens": measured_stats["total_tokens"],
        "avg_output_tokens": measured_stats["avg_output_tokens"],
        "total_prompt_tokens": measured_stats.get("total_prompt_tokens"),
        "avg_prompt_tokens": measured_stats.get("avg_prompt_tokens"),
        # Phase details
        "phases": {
            "warmup": warmup_stats,
            "measured": measured_stats,
        },
        # Benchmark context
        "duration_seconds": round(benchmark_duration, 3),
        "warmup_requests": args.warmup_requests,
        "measured_requests": args.requests,
        "max_output_tokens": args.max_output_tokens,
        # Workload manifest reference
        "workload_manifest_path": args.workload,
        "workload_manifest_hash": manifest_hash,
        # Run metadata
        "run_metadata": run_metadata,
    }

    if args.json_out:
        Path(args.json_out).write_text(json.dumps(summary, indent=2))

    if args.show_errors:
        failures = [r for r in measured_results if not r.get("success")]
        if failures:
            print("Sample errors:", file=__import__('sys').stderr)
            for item in failures[: args.show_errors]:
                print(f"- {item.get('error')}", file=__import__('sys').stderr)

    return summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Stream benchmark for /query/stream with TPOT, warmup/measured phases"
    )
    parser.add_argument(
        "--url",
        default="http://localhost:8000/query/stream",
        help="Streaming endpoint URL",
    )
    parser.add_argument("--concurrency", type=int, default=10, help="Concurrent requests")
    parser.add_argument("--requests", type=int, default=100, help="Total measured requests")
    parser.add_argument(
        "--warmup-requests",
        type=int,
        default=0,
        help="Warmup requests (not counted in stats)",
    )
    parser.add_argument("--prompt-file", help="Optional prompt file")
    parser.add_argument("--workload", help="Workload manifest YAML file")
    parser.add_argument("--json-out", help="Write summary JSON to file")
    parser.add_argument("--timeout", type=int, default=120, help="Request timeout seconds")
    parser.add_argument(
        "--max-output-tokens",
        type=int,
        default=None,
        help="Maximum output tokens (controls response length for consistent benchmarks)",
    )
    parser.add_argument(
        "--show-errors",
        type=int,
        default=0,
        help="Print up to N error messages",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    summary = asyncio.run(run_benchmark(args))
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
