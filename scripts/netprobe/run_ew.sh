#!/usr/bin/env bash
#
# East-West Network Probe Runner
# Measures in-cluster network latency and throughput between nodes
#
# Usage:
#   ./run_ew.sh [OPTIONS]
#
# Options:
#   --provider PROVIDER       Provider name (akamai-lke, aws-eks, gcp-gke)
#   --kubeconfig PATH         Path to kubeconfig file
#   --output DIR              Output directory (default: benchmarks/ew)
#   --pushgateway-url URL     Push metrics to Prometheus Pushgateway
#   --keep                    Don't cleanup resources after test
#   --help                    Show this help
#
# Output:
#   JSON file with TCP throughput, UDP jitter, and latency measurements
#   Optional: Push metrics to Prometheus Pushgateway for dashboard display

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[netprobe]${NC} $*"; }
warn() { echo -e "${YELLOW}[netprobe]${NC} $*"; }
error() { echo -e "${RED}[netprobe]${NC} $*" >&2; }

# Defaults
PROVIDER="${PROVIDER:-unknown}"
KUBECONFIG="${KUBECONFIG:-}"
OUTPUT_DIR="benchmarks/ew"
KEEP_RESOURCES=false
PUSHGATEWAY_URL=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$PROJECT_ROOT/deploy/netprobe/ew-netprobe.yaml"
NAMESPACE="netprobe"

usage() {
    head -25 "$0" | tail -20 | sed 's/^# //' | sed 's/^#//'
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --provider)
            PROVIDER="$2"
            shift 2
            ;;
        --kubeconfig)
            KUBECONFIG="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --pushgateway-url)
            PUSHGATEWAY_URL="$2"
            shift 2
            ;;
        --keep)
            KEEP_RESOURCES=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            error "Unknown option: $1"
            usage
            ;;
    esac
done

# Set KUBECONFIG if provided
if [[ -n "$KUBECONFIG" ]]; then
    export KUBECONFIG
fi

# Verify kubectl access
if ! kubectl cluster-info &>/dev/null; then
    error "Cannot connect to Kubernetes cluster. Check KUBECONFIG."
    exit 1
fi

# Get cluster info
CLUSTER_NAME=$(kubectl config current-context 2>/dev/null || echo "unknown")
log "Provider: $PROVIDER"
log "Cluster: $CLUSTER_NAME"

# Check if manifest exists
if [[ ! -f "$MANIFEST" ]]; then
    error "Manifest not found: $MANIFEST"
    exit 1
fi

# Cleanup function
cleanup() {
    if [[ "$KEEP_RESOURCES" == "false" ]]; then
        log "Cleaning up resources..."
        kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --wait=false &>/dev/null || true
    else
        warn "Keeping resources in namespace: $NAMESPACE"
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Clean up any existing namespace first
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    log "Cleaning up existing namespace..."
    kubectl delete namespace "$NAMESPACE" --wait=true --timeout=60s || true
    sleep 5
fi

# Deploy netprobe resources
log "Deploying netprobe resources..."
kubectl apply -f "$MANIFEST"

# Wait for server to be ready
log "Waiting for iperf3 server to be ready..."
kubectl wait --for=condition=available deployment/iperf3-server -n "$NAMESPACE" --timeout=120s

# Get server node
SERVER_NODE=$(kubectl get pod -n "$NAMESPACE" -l app=iperf3-server -o jsonpath='{.items[0].spec.nodeName}')
log "Server running on node: $SERVER_NODE"

# Delete any existing client job
kubectl delete job iperf3-client -n "$NAMESPACE" --ignore-not-found=true &>/dev/null || true
sleep 2

# Recreate client job (to ensure fresh run)
log "Starting client job..."
kubectl apply -f "$MANIFEST"

# Wait for client job to complete
log "Waiting for tests to complete (up to 60s)..."
if ! kubectl wait --for=condition=complete job/iperf3-client -n "$NAMESPACE" --timeout=60s 2>/dev/null; then
    # Check if job failed
    JOB_STATUS=$(kubectl get job iperf3-client -n "$NAMESPACE" -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
    if [[ "$JOB_STATUS" -gt 0 ]]; then
        error "Client job failed. Logs:"
        kubectl logs -n "$NAMESPACE" -l app=iperf3-client --tail=50
        exit 1
    fi
    warn "Job not complete yet, waiting longer..."
    kubectl wait --for=condition=complete job/iperf3-client -n "$NAMESPACE" --timeout=60s
fi

# Get client node
CLIENT_NODE=$(kubectl get pod -n "$NAMESPACE" -l app=iperf3-client -o jsonpath='{.items[0].spec.nodeName}')
log "Client ran on node: $CLIENT_NODE"

# Check if nodes are different
if [[ "$SERVER_NODE" == "$CLIENT_NODE" ]]; then
    warn "WARNING: Server and client on same node ($SERVER_NODE). Results may not reflect cross-node performance."
    SAME_NODE=true
else
    log "Cross-node test confirmed: $CLIENT_NODE -> $SERVER_NODE"
    SAME_NODE=false
fi

# Get results from job logs (only from the completed job pod)
log "Collecting results..."
CLIENT_POD=$(kubectl get pods -n "$NAMESPACE" -l app=iperf3-client --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null)
RAW_RESULTS=$(kubectl logs -n "$NAMESPACE" "$CLIENT_POD" 2>/dev/null)

# Extract JSON - find lines starting with { and capture until final }
# The JSON output is the last thing printed by the container
JSON_RESULTS=$(echo "$RAW_RESULTS" | awk '/^{\"test_type\":/,/^}$/' | head -50)

# If that didn't work, try extracting from the last { to the end
if [[ -z "$JSON_RESULTS" ]]; then
    JSON_RESULTS=$(echo "$RAW_RESULTS" | grep -A100 '^{"test_type"' | head -50)
fi

if [[ -z "$JSON_RESULTS" ]] || ! echo "$JSON_RESULTS" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    warn "Could not extract clean JSON, attempting to build from raw values..."
    # Try to extract key values directly
    TCP_GBPS=$(echo "$RAW_RESULTS" | grep -o '"gbps": [0-9.]*' | head -1 | grep -o '[0-9.]*')
    TCP_MBPS=$(echo "$RAW_RESULTS" | grep -o '"mbps": [0-9.]*' | head -1 | grep -o '[0-9.]*')
    if [[ -n "$TCP_GBPS" ]]; then
        # Build minimal JSON from extracted values
        JSON_RESULTS="{\"test_type\": \"east-west\", \"tcp_throughput\": {\"gbps\": $TCP_GBPS, \"mbps\": $TCP_MBPS}, \"udp_jitter\": {\"jitter_ms\": 0}, \"latency\": {\"avg_ms\": 0}}"
        log "Built minimal JSON from extracted values"
    else
        error "Failed to parse results JSON"
        echo "Raw output:"
        echo "$RAW_RESULTS"
        exit 1
    fi
fi

# Add metadata to results
TIMESTAMP=$(date -u +%Y-%m-%dT%H%M%SZ)
OUTPUT_FILE="$PROJECT_ROOT/$OUTPUT_DIR/$PROVIDER/${TIMESTAMP}.json"
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Write raw JSON to temp file to avoid heredoc quoting issues
TEMP_JSON=$(mktemp)
echo "$JSON_RESULTS" > "$TEMP_JSON"

# Merge results with metadata using Python
SAME_NODE_BOOL=$( [[ "$SAME_NODE" == "true" ]] && echo "true" || echo "false" )
python3 - "$TEMP_JSON" "$PROVIDER" "$CLUSTER_NAME" "$SERVER_NODE" "$CLIENT_NODE" "$SAME_NODE_BOOL" > "$OUTPUT_FILE" << 'PYEOF'
import json
import sys

temp_file = sys.argv[1]
provider = sys.argv[2]
cluster = sys.argv[3]
server_node = sys.argv[4]
client_node = sys.argv[5]
same_node = sys.argv[6] == "true"

with open(temp_file) as f:
    data = json.load(f)

# Add metadata
data["provider"] = provider
data["cluster"] = cluster
data["server_node"] = server_node
data["client_node"] = client_node
data["same_node"] = same_node

# Pretty print
print(json.dumps(data, indent=2))
PYEOF
rm -f "$TEMP_JSON"

# Display summary
log "Results saved to: $OUTPUT_FILE"
echo ""
echo "=== East-West Network Probe Results ==="
python3 << EOF
import json
with open("$OUTPUT_FILE") as f:
    d = json.load(f)
    
print(f"Provider:    {d.get('provider', 'N/A')}")
print(f"Cluster:     {d.get('cluster', 'N/A')}")
print(f"Server Node: {d.get('server_node', 'N/A')}")
print(f"Client Node: {d.get('client_node', 'N/A')}")
print(f"Same Node:   {d.get('same_node', 'N/A')}")
print()

tcp = d.get('tcp_throughput', {})
print(f"TCP Throughput:")
print(f"  Gbps:        {tcp.get('gbps', 0):.2f}")
print(f"  Mbps:        {tcp.get('mbps', 0):.0f}")
print(f"  Retransmits: {tcp.get('retransmits', 0)}")

udp = d.get('udp_jitter', {})
print(f"\nUDP Jitter:")
print(f"  Jitter:      {udp.get('jitter_ms', 0):.3f} ms")
print(f"  Loss:        {udp.get('loss_percent', 0):.2f}%")

lat = d.get('latency', {})
print(f"\nLatency:")
print(f"  Min:         {lat.get('min_ms', 0):.3f} ms")
print(f"  Avg:         {lat.get('avg_ms', 0):.3f} ms")
print(f"  Max:         {lat.get('max_ms', 0):.3f} ms")
EOF
echo ""

# Push metrics to Prometheus Pushgateway if URL provided
if [[ -n "$PUSHGATEWAY_URL" ]]; then
    log "Pushing metrics to Pushgateway: $PUSHGATEWAY_URL"
    
    # Extract metrics from the saved JSON and push to Pushgateway
    python3 - "$OUTPUT_FILE" "$PUSHGATEWAY_URL" "$PROVIDER" << 'PUSHEOF'
import json
import sys
import urllib.request
import urllib.error

output_file = sys.argv[1]
pushgateway_url = sys.argv[2]
provider = sys.argv[3]

with open(output_file) as f:
    data = json.load(f)

tcp = data.get('tcp_throughput', {})
udp = data.get('udp_jitter', {})
lat = data.get('latency', {})

# Build Prometheus text format metrics
metrics = f"""# HELP ew_tcp_throughput_bps East-West TCP throughput in bits per second
# TYPE ew_tcp_throughput_bps gauge
ew_tcp_throughput_bps{{provider="{provider}"}} {tcp.get('mbps', 0) * 1000000}

# HELP ew_tcp_throughput_gbps East-West TCP throughput in Gbps
# TYPE ew_tcp_throughput_gbps gauge
ew_tcp_throughput_gbps{{provider="{provider}"}} {tcp.get('gbps', 0)}

# HELP ew_tcp_retransmits East-West TCP retransmit count
# TYPE ew_tcp_retransmits gauge
ew_tcp_retransmits{{provider="{provider}"}} {tcp.get('retransmits', 0)}

# HELP ew_udp_jitter_ms East-West UDP jitter in milliseconds
# TYPE ew_udp_jitter_ms gauge
ew_udp_jitter_ms{{provider="{provider}"}} {udp.get('jitter_ms', 0)}

# HELP ew_udp_loss_percent East-West UDP packet loss percentage
# TYPE ew_udp_loss_percent gauge
ew_udp_loss_percent{{provider="{provider}"}} {udp.get('loss_percent', 0)}

# HELP ew_latency_min_ms East-West minimum latency in milliseconds
# TYPE ew_latency_min_ms gauge
ew_latency_min_ms{{provider="{provider}"}} {lat.get('min_ms', 0)}

# HELP ew_latency_avg_ms East-West average latency in milliseconds
# TYPE ew_latency_avg_ms gauge
ew_latency_avg_ms{{provider="{provider}"}} {lat.get('avg_ms', 0)}

# HELP ew_latency_max_ms East-West maximum latency in milliseconds
# TYPE ew_latency_max_ms gauge
ew_latency_max_ms{{provider="{provider}"}} {lat.get('max_ms', 0)}
"""

# Push to Pushgateway
url = f"{pushgateway_url}/metrics/job/east_west_probe/provider/{provider}"
req = urllib.request.Request(url, data=metrics.encode('utf-8'), method='POST')
req.add_header('Content-Type', 'text/plain')

try:
    with urllib.request.urlopen(req) as response:
        print(f"Metrics pushed successfully (status: {response.status})")
except urllib.error.HTTPError as e:
    print(f"Failed to push metrics: {e.code} {e.reason}")
    sys.exit(1)
except urllib.error.URLError as e:
    print(f"Failed to connect to Pushgateway: {e.reason}")
    sys.exit(1)
PUSHEOF

    if [[ $? -eq 0 ]]; then
        log "Metrics pushed to Pushgateway"
    else
        warn "Failed to push metrics to Pushgateway"
    fi
fi

log "Done!"
