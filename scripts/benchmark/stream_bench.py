#!/usr/bin/env python3
"""
Lightweight streaming benchmark for /query/stream.

Measures TTFT, tokens/sec (approx), and total latency.
Portable across Akamai LKE, AWS EKS, and GCP GKE.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import statistics
import time
from pathlib import Path
from typing import Any, Optional

import httpx


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = max(0, int(len(ordered) * pct) - 1)
    return ordered[index]


async def run_request(
    client: httpx.AsyncClient,
    url: str,
    prompt: str,
    request_id: int,
) -> dict[str, Any]:
    payload = {"query": prompt}
    start = time.perf_counter()
    ttft: Optional[float] = None
    token_count = 0

    try:
        async with client.stream("POST", url, json=payload) as response:
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
                    if event_name == "token":
                        if ttft is None:
                            ttft = time.perf_counter() - start
                        token_count += max(1, len(payload.get("text", "").split()))
                    if event_name == "done":
                        break
                    event_name = None
                    event_data = None

        total = time.perf_counter() - start
        tokens_per_second = token_count / total if total > 0 else 0.0
        return {
            "id": request_id,
            "success": True,
            "ttft": ttft or total,
            "total": total,
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
) -> None:
    while True:
        async with counter:
            if remaining[0] <= 0:
                return
            remaining[0] -= 1
            request_id = remaining[0]
        result = await run_request(client, url, prompt, request_id)
        results.append(result)


async def run_benchmark(args: argparse.Namespace) -> dict[str, Any]:
    prompt = "Explain what this system is and why vLLM matters."
    if args.prompt_file:
        prompt = Path(args.prompt_file).read_text().strip()

    timeout = httpx.Timeout(args.timeout)
    limits = httpx.Limits(max_keepalive_connections=args.concurrency)
    results: list[dict[str, Any]] = []
    remaining = [args.requests]
    lock = asyncio.Lock()

    async with httpx.AsyncClient(timeout=timeout, limits=limits) as client:
        tasks = [
            asyncio.create_task(worker(i, client, args.url, prompt, lock, remaining, results))
            for i in range(args.concurrency)
        ]
        await asyncio.gather(*tasks)

    success = [r for r in results if r.get("success")]
    failures = [r for r in results if not r.get("success")]
    ttft_values = [r["ttft"] for r in success]
    total_values = [r["total"] for r in success]
    tokens_per_second = [r["tokens_per_second"] for r in success]

    summary = {
        "requests": args.requests,
        "concurrency": args.concurrency,
        "success": len(success),
        "errors": len(failures),
        "ttft_p50_ms": round(percentile(ttft_values, 0.50) * 1000, 2),
        "ttft_p95_ms": round(percentile(ttft_values, 0.95) * 1000, 2),
        "latency_p50_ms": round(percentile(total_values, 0.50) * 1000, 2),
        "latency_p95_ms": round(percentile(total_values, 0.95) * 1000, 2),
        "avg_tokens_per_sec": round(
            statistics.mean(tokens_per_second) if tokens_per_second else 0.0, 2
        ),
    }

    if args.json_out:
        Path(args.json_out).write_text(json.dumps(summary, indent=2))

    if args.show_errors and failures:
        print("Sample errors:")
        for item in failures[: args.show_errors]:
            print(f"- {item.get('error')}")

    return summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Stream benchmark for /query/stream")
    parser.add_argument(
        "--url",
        default="http://localhost:8000/query/stream",
        help="Streaming endpoint URL",
    )
    parser.add_argument("--concurrency", type=int, default=10, help="Concurrent requests")
    parser.add_argument("--requests", type=int, default=100, help="Total requests")
    parser.add_argument("--prompt-file", help="Optional prompt file")
    parser.add_argument("--json-out", help="Write summary JSON to file")
    parser.add_argument("--timeout", type=int, default=120, help="Request timeout seconds")
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
