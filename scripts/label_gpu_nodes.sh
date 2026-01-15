#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="rag-app"
LABEL_KEY="accelerator"
LABEL_VALUE="nvidia"
TAINT_KEY="nvidia.com/gpu"
TAINT_VALUE="true"
TAINT_EFFECT="NoSchedule"
MATCH_LABEL="node.kubernetes.io/instance-type"
MATCH_VALUE="gpu"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label-key)
      LABEL_KEY="$2"
      shift 2
      ;;
    --label-value)
      LABEL_VALUE="$2"
      shift 2
      ;;
    --taint-key)
      TAINT_KEY="$2"
      shift 2
      ;;
    --taint-value)
      TAINT_VALUE="$2"
      shift 2
      ;;
    --taint-effect)
      TAINT_EFFECT="$2"
      shift 2
      ;;
    --match-label)
      MATCH_LABEL="$2"
      shift 2
      ;;
    --match-value)
      MATCH_VALUE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Apply labels/taints to nodes that advertise GPUs.
nodes=$(kubectl get nodes -o jsonpath="{range .items[?(@.status.capacity['nvidia\.com/gpu'])]}{.metadata.name}{'\n'}{end}")
if [[ -z "${nodes}" ]]; then
  # Fall back to matching instance type labels that include "gpu".
  nodes=$(kubectl get nodes --show-labels | awk -v match_key="${MATCH_LABEL}" -v match_val="${MATCH_VALUE}" '
    NR>1 && $0 ~ match_key && $0 ~ match_val {print $1}
  ')
fi

if [[ -z "${nodes}" ]]; then
  echo "No GPU nodes found via nvidia.com/gpu capacity or label match."
  echo "Tip: install the NVIDIA device plugin or set --match-label/--match-value."
  exit 1
fi

for node in ${nodes}; do
  kubectl label node "${node}" "${LABEL_KEY}=${LABEL_VALUE}" --overwrite
  kubectl taint node "${node}" "${TAINT_KEY}=${TAINT_VALUE}:${TAINT_EFFECT}" --overwrite
done

echo "Applied ${LABEL_KEY}=${LABEL_VALUE} and ${TAINT_KEY}=${TAINT_VALUE}:${TAINT_EFFECT} to GPU nodes."
