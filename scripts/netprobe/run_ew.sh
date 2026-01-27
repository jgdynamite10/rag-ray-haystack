#!/bin/bash
# East-West Network Probe Script
# Runs iperf3 bandwidth/latency tests between nodes in the cluster
#
# Usage:
#   ./scripts/netprobe/run_ew.sh [--namespace <ns>] [--output <file>] [--no-cleanup]
#
# Output: JSON blob with TCP bandwidth, UDP jitter/loss, and ping latency

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFESTS_DIR="$REPO_ROOT/deploy/k8s/netprobe"

# Defaults
NAMESPACE="default"
OUTPUT_FILE=""
CLEANUP=true
TIMEOUT=120

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace|-n)
            NAMESPACE="$2"
            shift 2
            ;;
        --output|-o)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --no-cleanup)
            CLEANUP=false
            shift
            ;;
        --timeout|-t)
            TIMEOUT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--namespace <ns>] [--output <file>] [--no-cleanup] [--timeout <sec>]"
            echo ""
            echo "Runs east-west network probes (iperf3) between nodes in the cluster."
            echo ""
            echo "Options:"
            echo "  --namespace, -n  Kubernetes namespace (default: default)"
            echo "  --output, -o     Output file path (default: stdout)"
            echo "  --no-cleanup     Don't delete resources after run"
            echo "  --timeout, -t    Timeout in seconds (default: 120)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

echo "East-West Network Probe" >&2
echo "=======================" >&2
echo "Namespace: $NAMESPACE" >&2
echo "" >&2

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found" >&2
    exit 1
fi

# Verify cluster access
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster" >&2
    exit 1
fi

# Check we have at least 2 nodes
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
if [[ $NODE_COUNT -lt 2 ]]; then
    echo "Warning: Only $NODE_COUNT node(s) found. East-west test requires 2+ nodes." >&2
    echo "Test will run but may not measure cross-node latency." >&2
fi

# Update namespace in manifests (in-place sed is not portable, use temp files)
echo "Deploying iperf3 server..." >&2
sed "s/namespace: default/namespace: $NAMESPACE/g" "$MANIFESTS_DIR/iperf3-server.yaml" | kubectl apply -f -

# Wait for server to be ready
echo "Waiting for server pod to be ready..." >&2
kubectl wait --for=condition=available deployment/netprobe-iperf3-server \
    --namespace="$NAMESPACE" --timeout=60s

# Get server pod node for verification
SERVER_NODE=$(kubectl get pods -n "$NAMESPACE" -l app=netprobe-iperf3-server \
    -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || echo "unknown")
echo "Server running on node: $SERVER_NODE" >&2

# Delete any existing client job
kubectl delete job netprobe-iperf3-client --namespace="$NAMESPACE" --ignore-not-found=true &>/dev/null

# Deploy client job
echo "Deploying iperf3 client job..." >&2
sed "s/namespace: default/namespace: $NAMESPACE/g" "$MANIFESTS_DIR/iperf3-client-job.yaml" | kubectl apply -f -

# Wait for client job to complete
echo "Waiting for client job to complete (timeout: ${TIMEOUT}s)..." >&2
if ! kubectl wait --for=condition=complete job/netprobe-iperf3-client \
    --namespace="$NAMESPACE" --timeout="${TIMEOUT}s" 2>/dev/null; then
    
    # Check if job failed
    JOB_STATUS=$(kubectl get job netprobe-iperf3-client -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
    if [[ "$JOB_STATUS" == "Failed" ]]; then
        echo "Error: Client job failed" >&2
        kubectl logs job/netprobe-iperf3-client -n "$NAMESPACE" >&2
        
        if [[ "$CLEANUP" == "true" ]]; then
            echo "Cleaning up..." >&2
            kubectl delete -f "$MANIFESTS_DIR/iperf3-server.yaml" --namespace="$NAMESPACE" --ignore-not-found=true &>/dev/null
            kubectl delete job netprobe-iperf3-client --namespace="$NAMESPACE" --ignore-not-found=true &>/dev/null
        fi
        exit 1
    fi
    
    echo "Error: Timeout waiting for client job" >&2
    exit 1
fi

# Get client pod node
CLIENT_NODE=$(kubectl get pods -n "$NAMESPACE" -l app=netprobe-iperf3-client \
    -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || echo "unknown")
echo "Client ran on node: $CLIENT_NODE" >&2

# Verify different nodes
if [[ "$SERVER_NODE" == "$CLIENT_NODE" ]]; then
    echo "WARNING: Server and client ran on the SAME node ($SERVER_NODE)!" >&2
    echo "Results may not reflect true cross-node network performance." >&2
else
    echo "SUCCESS: Pods ran on different nodes (server: $SERVER_NODE, client: $CLIENT_NODE)" >&2
fi

# Get results
echo "" >&2
echo "Fetching results..." >&2
RESULT=$(kubectl logs job/netprobe-iperf3-client --namespace="$NAMESPACE" 2>/dev/null | grep -A 1000 '^{' | head -n -0)

# Add metadata
RESULT_WITH_META=$(echo "$RESULT" | jq --arg sn "$SERVER_NODE" --arg cn "$CLIENT_NODE" \
    '. + {server_node: $sn, client_node: $cn, same_node: ($sn == $cn)}' 2>/dev/null || echo "$RESULT")

# Cleanup
if [[ "$CLEANUP" == "true" ]]; then
    echo "Cleaning up resources..." >&2
    kubectl delete -f "$MANIFESTS_DIR/iperf3-server.yaml" --namespace="$NAMESPACE" --ignore-not-found=true &>/dev/null
    kubectl delete job netprobe-iperf3-client --namespace="$NAMESPACE" --ignore-not-found=true &>/dev/null
fi

# Output
if [[ -n "$OUTPUT_FILE" ]]; then
    echo "$RESULT_WITH_META" > "$OUTPUT_FILE"
    echo "Results written to: $OUTPUT_FILE" >&2
else
    echo "" >&2
    echo "=== RESULTS ===" >&2
    echo "$RESULT_WITH_META"
fi

echo "" >&2
echo "Done." >&2
