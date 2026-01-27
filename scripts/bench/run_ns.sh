#!/bin/bash
# North-South Benchmark Runner
# Runs the existing benchmark harness against a public endpoint
#
# Usage:
#   ./scripts/bench/run_ns.sh --endpoint <base_url> --provider <name> [options]
#
# Example:
#   ./scripts/bench/run_ns.sh --endpoint http://172.236.105.4/api --provider akamai-lke
#   ./scripts/bench/run_ns.sh --endpoint https://a1b2c3.elb.amazonaws.com/api --provider aws-eks
#
# Output: Saves JSON results to benchmarks/ns/<provider>/<timestamp>.json

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Defaults
ENDPOINT=""
PROVIDER=""
CONCURRENCY=10
REQUESTS=100
TIMEOUT=120
SHOW_ERRORS=3
OUTPUT_DIR=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --endpoint|-e)
            ENDPOINT="$2"
            shift 2
            ;;
        --provider|-p)
            PROVIDER="$2"
            shift 2
            ;;
        --concurrency|-c)
            CONCURRENCY="$2"
            shift 2
            ;;
        --requests|-r)
            REQUESTS="$2"
            shift 2
            ;;
        --timeout|-t)
            TIMEOUT="$2"
            shift 2
            ;;
        --show-errors)
            SHOW_ERRORS="$2"
            shift 2
            ;;
        --output-dir|-o)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 --endpoint <url> --provider <name> [options]"
            echo ""
            echo "Runs north-south benchmark against a public endpoint."
            echo ""
            echo "Required:"
            echo "  --endpoint, -e   Base URL (e.g., http://172.236.105.4/api)"
            echo "  --provider, -p   Provider name (akamai-lke, aws-eks, gcp-gke)"
            echo ""
            echo "Options:"
            echo "  --concurrency, -c  Concurrent requests (default: 10)"
            echo "  --requests, -r     Total requests (default: 100)"
            echo "  --timeout, -t      Request timeout in seconds (default: 120)"
            echo "  --show-errors      Number of errors to show (default: 3)"
            echo "  --output-dir, -o   Output directory (default: benchmarks/ns/<provider>)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$ENDPOINT" ]]; then
    echo "Error: --endpoint is required" >&2
    exit 1
fi

if [[ -z "$PROVIDER" ]]; then
    echo "Error: --provider is required" >&2
    exit 1
fi

# Set output directory
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$REPO_ROOT/benchmarks/ns/$PROVIDER"
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate timestamp
TIMESTAMP=$(date -u +%Y-%m-%dT%H%M%SZ)
OUTPUT_FILE="$OUTPUT_DIR/$TIMESTAMP.json"

echo "North-South Benchmark Runner" >&2
echo "============================" >&2
echo "Provider:    $PROVIDER" >&2
echo "Endpoint:    $ENDPOINT" >&2
echo "Concurrency: $CONCURRENCY" >&2
echo "Requests:    $REQUESTS" >&2
echo "Timeout:     $TIMEOUT" >&2
echo "Output:      $OUTPUT_FILE" >&2
echo "" >&2

# Health check
echo "Checking endpoint health..." >&2
HEALTH_URL="${ENDPOINT}/healthz"
if ! curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
    echo "Warning: Health check failed at $HEALTH_URL" >&2
    echo "Proceeding anyway..." >&2
fi

# Method 1: Use in-cluster benchmark via API (if endpoint supports it)
echo "Triggering benchmark via API..." >&2
BENCHMARK_URL="${ENDPOINT}/benchmark/run"

RESPONSE=$(curl -sf -X POST "$BENCHMARK_URL" \
    -H "Content-Type: application/json" \
    -d "{
        \"concurrency\": $CONCURRENCY,
        \"requests\": $REQUESTS,
        \"timeout\": $TIMEOUT,
        \"show_errors\": $SHOW_ERRORS
    }" 2>/dev/null || echo "")

if [[ -z "$RESPONSE" ]]; then
    echo "Error: Failed to trigger benchmark at $BENCHMARK_URL" >&2
    echo "" >&2
    echo "Falling back to direct stream_bench.py..." >&2
    
    # Method 2: Run stream_bench.py directly if available
    BENCH_SCRIPT="$REPO_ROOT/scripts/benchmark/stream_bench.py"
    if [[ -f "$BENCH_SCRIPT" ]]; then
        STREAM_URL="${ENDPOINT}/query/stream"
        echo "Running stream_bench.py against $STREAM_URL..." >&2
        
        python3 "$BENCH_SCRIPT" \
            --url "$STREAM_URL" \
            --concurrency "$CONCURRENCY" \
            --requests "$REQUESTS" \
            --timeout "$TIMEOUT" \
            --show-errors "$SHOW_ERRORS" \
            > "$OUTPUT_FILE" 2>&1
        
        echo "" >&2
        echo "Results saved to: $OUTPUT_FILE" >&2
        cat "$OUTPUT_FILE"
        exit 0
    else
        echo "Error: stream_bench.py not found at $BENCH_SCRIPT" >&2
        exit 1
    fi
fi

# Parse job name from response
JOB_NAME=$(echo "$RESPONSE" | jq -r '.job_name' 2>/dev/null)
if [[ -z "$JOB_NAME" || "$JOB_NAME" == "null" ]]; then
    echo "Error: Could not parse job_name from response" >&2
    echo "Response: $RESPONSE" >&2
    exit 1
fi

echo "Job started: $JOB_NAME" >&2
echo "Polling for completion..." >&2

# Poll for completion
STATUS_URL="${ENDPOINT}/benchmark/status?job=$JOB_NAME"
MAX_WAIT=$((TIMEOUT + 60))
WAITED=0
POLL_INTERVAL=5

while [[ $WAITED -lt $MAX_WAIT ]]; do
    STATUS=$(curl -sf "$STATUS_URL" 2>/dev/null || echo '{"phase": "error"}')
    PHASE=$(echo "$STATUS" | jq -r '.phase' 2>/dev/null)
    
    case "$PHASE" in
        succeeded)
            echo "Benchmark completed successfully" >&2
            break
            ;;
        failed)
            echo "Error: Benchmark job failed" >&2
            echo "$STATUS" >&2
            exit 1
            ;;
        pending|running)
            echo "  Status: $PHASE (${WAITED}s elapsed)" >&2
            sleep $POLL_INTERVAL
            WAITED=$((WAITED + POLL_INTERVAL))
            ;;
        *)
            echo "Warning: Unknown status: $PHASE" >&2
            sleep $POLL_INTERVAL
            WAITED=$((WAITED + POLL_INTERVAL))
            ;;
    esac
done

if [[ "$PHASE" != "succeeded" ]]; then
    echo "Error: Timed out waiting for benchmark to complete" >&2
    exit 1
fi

# Fetch logs
echo "Fetching results..." >&2
LOGS_URL="${ENDPOINT}/benchmark/logs?job=$JOB_NAME"
LOGS=$(curl -sf "$LOGS_URL" 2>/dev/null || echo "")

if [[ -z "$LOGS" ]]; then
    echo "Error: Could not fetch benchmark logs" >&2
    exit 1
fi

# Extract JSON result from logs
# The benchmark output ends with pretty-printed JSON starting with lone { and ending with }
# Simple approach: find line numbers for last { and }, extract between them
LAST_OPEN=$(echo "$LOGS" | grep -n '^{$' | tail -1 | cut -d: -f1)
LAST_CLOSE=$(echo "$LOGS" | grep -n '^}$' | tail -1 | cut -d: -f1)

if [[ -n "$LAST_OPEN" ]] && [[ -n "$LAST_CLOSE" ]] && [[ "$LAST_CLOSE" -gt "$LAST_OPEN" ]]; then
    RESULT=$(echo "$LOGS" | sed -n "${LAST_OPEN},${LAST_CLOSE}p")
fi

# Validate JSON
if [[ -z "$RESULT" ]] || ! echo "$RESULT" | jq . &>/dev/null; then
    echo "Warning: Could not extract valid JSON from logs" >&2
    echo "$LOGS" > "${OUTPUT_FILE%.json}.raw.txt"
    echo "Raw logs saved to: ${OUTPUT_FILE%.json}.raw.txt" >&2
    RESULT="{}"
fi

# Add metadata
RESULT_WITH_META=$(echo "$RESULT" | jq \
    --arg provider "$PROVIDER" \
    --arg endpoint "$ENDPOINT" \
    --arg timestamp "$TIMESTAMP" \
    --arg job "$JOB_NAME" \
    '. + {
        _meta: {
            provider: $provider,
            endpoint: $endpoint,
            timestamp: $timestamp,
            job_name: $job,
            probe_type: "north_south"
        }
    }' 2>/dev/null || echo "$RESULT")

# Save results
echo "$RESULT_WITH_META" > "$OUTPUT_FILE"

echo "" >&2
echo "Results saved to: $OUTPUT_FILE" >&2
echo "" >&2
echo "=== SUMMARY ===" >&2
echo "$RESULT_WITH_META" | jq -r '
    "Requests:     \(.requests // "N/A")",
    "Success:      \(.success // "N/A")",
    "Errors:       \(.errors // "N/A")",
    "TTFT p50:     \(.ttft_p50_ms // "N/A") ms",
    "TTFT p95:     \(.ttft_p95_ms // "N/A") ms",
    "Latency p50:  \(.latency_p50_ms // "N/A") ms",
    "Latency p95:  \(.latency_p95_ms // "N/A") ms",
    "Tokens/sec:   \(.avg_tokens_per_sec // "N/A")"
' 2>/dev/null || cat "$OUTPUT_FILE"

echo "" >&2
echo "Done." >&2
