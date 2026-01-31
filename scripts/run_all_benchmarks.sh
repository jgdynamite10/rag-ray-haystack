#!/usr/bin/env bash
#
# Run ALL benchmarks across ALL providers simultaneously
# Fixed: Uses isolated kubeconfigs to avoid context conflicts
#
# Usage: ./scripts/run_all_benchmarks.sh
#

set -euo pipefail

echo "========================================="
echo "=== Starting ALL benchmarks across ALL providers ==="
echo "========================================="
echo ""
echo "Running North-South (500 req, 50 concurrency) + East-West simultaneously..."
echo ""
echo "Kubeconfig mapping:"
echo "  LKE: ~/.kube/rag-ray-haystack-kubeconfig.yaml"
echo "  EKS: ~/.kube/eks-kubeconfig-fresh.yaml"
echo "  GKE: ~/.kube/gke-kubeconfig.yaml"
echo ""

# Track PIDs for wait
PIDS=()

# ============================================================
# NORTH-SOUTH BENCHMARKS (external API endpoint tests)
# ============================================================

# NS - Akamai LKE
(
  echo "[NS-LKE] Starting North-South benchmark..."
  ./scripts/benchmark/run_ns.sh akamai-lke \
    --url http://172.236.105.4/api/query/stream \
    --requests 500 --concurrency 50 --warmup 20 --max-output-tokens 256
  echo "[NS-LKE] ✅ Done!"
) &
PIDS+=($!)

# NS - AWS EKS
(
  echo "[NS-EKS] Starting North-South benchmark..."
  ./scripts/benchmark/run_ns.sh aws-eks \
    --url http://a1afeff1d897b401795f8fff97f26cbf-1811702222.us-east-1.elb.amazonaws.com/api/query/stream \
    --requests 500 --concurrency 50 --warmup 20 --max-output-tokens 256
  echo "[NS-EKS] ✅ Done!"
) &
PIDS+=($!)

# NS - GCP GKE
(
  echo "[NS-GKE] Starting North-South benchmark..."
  ./scripts/benchmark/run_ns.sh gcp-gke \
    --url http://136.112.241.175/api/query/stream \
    --requests 500 --concurrency 50 --warmup 20 --max-output-tokens 256
  echo "[NS-GKE] ✅ Done!"
) &
PIDS+=($!)

# ============================================================
# EAST-WEST BENCHMARKS (in-cluster network tests)
# Each uses isolated KUBECONFIG to avoid conflicts
# ============================================================

# EW - Akamai LKE (isolated kubeconfig)
(
  echo "[EW-LKE] Starting East-West benchmark..."
  export KUBECONFIG="$HOME/.kube/rag-ray-haystack-kubeconfig.yaml"
  ./scripts/netprobe/run_ew.sh \
    --provider akamai-lke \
    --kubeconfig "$HOME/.kube/rag-ray-haystack-kubeconfig.yaml"
  echo "[EW-LKE] ✅ Done!"
) &
PIDS+=($!)

# EW - AWS EKS (isolated kubeconfig - using fresh config)
(
  echo "[EW-EKS] Starting East-West benchmark..."
  export KUBECONFIG="$HOME/.kube/eks-kubeconfig-fresh.yaml"
  ./scripts/netprobe/run_ew.sh \
    --provider aws-eks \
    --kubeconfig "$HOME/.kube/eks-kubeconfig-fresh.yaml"
  echo "[EW-EKS] ✅ Done!"
) &
PIDS+=($!)

# EW - GCP GKE (isolated kubeconfig)
(
  echo "[EW-GKE] Starting East-West benchmark..."
  export KUBECONFIG="$HOME/.kube/gke-kubeconfig.yaml"
  export USE_GKE_GCLOUD_AUTH_PLUGIN=True
  ./scripts/netprobe/run_ew.sh \
    --provider gcp-gke \
    --kubeconfig "$HOME/.kube/gke-kubeconfig.yaml"
  echo "[EW-GKE] ✅ Done!"
) &
PIDS+=($!)

# ============================================================
# WAIT FOR ALL BENCHMARKS
# ============================================================

echo ""
echo "All 6 benchmarks started. Waiting for completion..."
echo "PIDs: ${PIDS[*]}"
echo ""

# Wait for all background jobs
FAILED=0
for PID in "${PIDS[@]}"; do
  if ! wait "$PID"; then
    echo "❌ Process $PID failed"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "========================================="
if [[ $FAILED -eq 0 ]]; then
  echo "=== ALL BENCHMARKS COMPLETE ✅ ==="
else
  echo "=== BENCHMARKS COMPLETE ($FAILED failed) ❌ ==="
fi
echo "========================================="
echo ""

# Show latest results
echo "Latest benchmark results:"
echo ""
echo "North-South (NS):"
ls -lt benchmarks/ns/*/2026*.json 2>/dev/null | head -6 || echo "  No NS results found"
echo ""
echo "East-West (EW):"
ls -lt benchmarks/ew/*/2026*.json 2>/dev/null | head -6 || echo "  No EW results found"

exit $FAILED
