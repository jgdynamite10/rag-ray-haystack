#!/usr/bin/env bash
#
# East-West Network Probe Runner
# Measures in-cluster network latency and throughput between nodes
#
# Usage:
#   ./run_ew.sh [OPTIONS]
#
# Options:
#   --provider PROVIDER   Provider name (akamai-lke, aws-eks, gcp-gke)
#   --kubeconfig PATH     Path to kubeconfig file
#   --output DIR          Output directory (default: benchmarks/ew)
#   --keep                Don't cleanup resources after test
#   --help                Show this help
#
# Output:
#   JSON file with TCP throughput, UDP jitter, and latency measurements

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

# Extract JSON (find the complete JSON object)
JSON_RESULTS=$(echo "$RAW_RESULTS" | sed -n '/^{/,/^}$/p' | head -30)

if [[ -z "$JSON_RESULTS" ]] || ! echo "$JSON_RESULTS" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    error "Failed to parse results JSON"
    echo "Raw output:"
    echo "$RAW_RESULTS"
    exit 1
fi

# Add metadata to results
TIMESTAMP=$(date -u +%Y-%m-%dT%H%M%SZ)
OUTPUT_FILE="$PROJECT_ROOT/$OUTPUT_DIR/$PROVIDER/${TIMESTAMP}.json"
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Merge results with metadata using Python
python3 << EOF
import json
import sys

raw = '''$JSON_RESULTS'''
data = json.loads(raw)

# Add metadata
data["provider"] = "$PROVIDER"
data["cluster"] = "$CLUSTER_NAME"
data["server_node"] = "$SERVER_NODE"
data["client_node"] = "$CLIENT_NODE"
data["same_node"] = $( [[ "$SAME_NODE" == "true" ]] && echo "true" || echo "false" )

# Pretty print
print(json.dumps(data, indent=2))
EOF > "$OUTPUT_FILE"

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
log "Done!"
