#!/usr/bin/env bash
#
# North-South Benchmark Runner
# Runs stream_bench.py against a public endpoint with proper metadata and result storage.
#
# Usage:
#   ./run_ns.sh <provider> [options]
#
# Examples:
#   ./run_ns.sh akamai-lke --url http://172.236.105.4/api/query/stream
#   ./run_ns.sh aws-eks --url http://eks-lb.example.com/api/query/stream --requests 100
#   ./run_ns.sh gcp-gke --url http://gke-lb.example.com/api/query/stream --with-cost
#
# Environment variables (optional, auto-detected where possible):
#   RAG_PROVIDER, RAG_REGION, CLUSTER_LABEL, GPU_MODEL, MODEL_ID, etc.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
Usage: $(basename "$0") <provider> [options]

Arguments:
  provider          Provider name: akamai-lke, aws-eks, gcp-gke (required)

Options:
  --url URL         Streaming endpoint URL (required)
  --requests N      Number of measured requests (default: 100)
  --concurrency N   Concurrent requests (default: 10)
  --warmup N        Warmup requests (default: 10)
  --timeout N       Request timeout in seconds (default: 180)
  --with-cost       Run cost computation after benchmark
  --dry-run         Show what would be run without executing

Environment:
  Set these for richer run_metadata in output:
    RAG_REGION, CLUSTER_LABEL, GPU_MODEL, GPU_COUNT, MODEL_ID,
    VLLM_VERSION, BACKEND_IMAGE_TAG

Examples:
  $(basename "$0") akamai-lke --url http://172.236.105.4/api/query/stream
  $(basename "$0") aws-eks --url http://eks.example.com/api/query/stream --requests 50 --with-cost
EOF
    exit 1
}

log() { echo -e "${GREEN}[run_ns]${NC} $*"; }
warn() { echo -e "${YELLOW}[run_ns]${NC} $*" >&2; }
error() { echo -e "${RED}[run_ns]${NC} $*" >&2; exit 1; }

# Defaults
PROVIDER=""
URL=""
REQUESTS=100
CONCURRENCY=10
WARMUP=10
TIMEOUT=180
WITH_COST=false
DRY_RUN=false

# Parse arguments
[[ $# -lt 1 ]] && usage

PROVIDER="$1"
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --url) URL="$2"; shift 2 ;;
        --requests) REQUESTS="$2"; shift 2 ;;
        --concurrency) CONCURRENCY="$2"; shift 2 ;;
        --warmup) WARMUP="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --with-cost) WITH_COST=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage ;;
        *) error "Unknown option: $1" ;;
    esac
done

# Validate
[[ -z "$PROVIDER" ]] && error "Provider is required"
[[ -z "$URL" ]] && error "--url is required"

# Set provider-specific defaults
case "$PROVIDER" in
    akamai-lke|akamai)
        export RAG_PROVIDER="${RAG_PROVIDER:-akamai-lke}"
        export RAG_REGION="${RAG_REGION:-us-ord}"
        ;;
    aws-eks|aws)
        export RAG_PROVIDER="${RAG_PROVIDER:-aws-eks}"
        export RAG_REGION="${RAG_REGION:-us-east-1}"
        ;;
    gcp-gke|gcp)
        export RAG_PROVIDER="${RAG_PROVIDER:-gcp-gke}"
        export RAG_REGION="${RAG_REGION:-us-central1}"
        ;;
    *)
        export RAG_PROVIDER="$PROVIDER"
        warn "Unknown provider '$PROVIDER', using as-is"
        ;;
esac

# Export additional metadata from environment (if set)
export PROVIDER="${RAG_PROVIDER}"
export REGION="${RAG_REGION:-}"
export CLUSTER_LABEL="${CLUSTER_LABEL:-}"
export GPU_MODEL="${GPU_MODEL:-}"
export GPU_COUNT="${GPU_COUNT:-}"
export MODEL_ID="${MODEL_ID:-}"
export VLLM_VERSION="${VLLM_VERSION:-}"
export BACKEND_IMAGE_TAG="${BACKEND_IMAGE_TAG:-}"

# Create output directory
OUTPUT_DIR="$PROJECT_ROOT/benchmarks/ns/$RAG_PROVIDER"
mkdir -p "$OUTPUT_DIR"

# Generate output filename
TIMESTAMP=$(date -u +%Y-%m-%dT%H%M%SZ)
OUTPUT_FILE="$OUTPUT_DIR/${TIMESTAMP}.json"

log "Provider: $RAG_PROVIDER"
log "Region: ${RAG_REGION:-not set}"
log "URL: $URL"
log "Requests: $REQUESTS (warmup: $WARMUP, concurrency: $CONCURRENCY)"
log "Output: $OUTPUT_FILE"

# Build command
CMD=(
    python "$SCRIPT_DIR/stream_bench.py"
    --url "$URL"
    --requests "$REQUESTS"
    --concurrency "$CONCURRENCY"
    --warmup-requests "$WARMUP"
    --timeout "$TIMEOUT"
    --json-out "$OUTPUT_FILE"
)

if $DRY_RUN; then
    log "Dry run - would execute:"
    echo "${CMD[*]}"
    exit 0
fi

# Run benchmark
log "Starting North-South benchmark..."
echo ""

"${CMD[@]}"

echo ""
log "Results saved to: $OUTPUT_FILE"

# Optionally run cost computation
if $WITH_COST; then
    COST_SCRIPT="$PROJECT_ROOT/scripts/cost/compute_cost.py"
    COST_CONFIG="$PROJECT_ROOT/cost/cost-config.yaml"
    
    if [[ -f "$COST_SCRIPT" && -f "$COST_CONFIG" ]]; then
        log "Running cost computation..."
        COST_OUTPUT="${OUTPUT_FILE%.json}-cost.json"
        python "$COST_SCRIPT" "$OUTPUT_FILE" "$COST_CONFIG" --provider "$RAG_PROVIDER" --output "$COST_OUTPUT"
        log "Cost results saved to: $COST_OUTPUT"
    else
        warn "Cost script or config not found, skipping cost computation"
    fi
fi

log "Done!"
