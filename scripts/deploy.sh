#!/usr/bin/env bash
set -euo pipefail

PROVIDER="akamai-lke"
ENVIRONMENT="dev"
ACTION="apply"
RELEASE="${RELEASE:-rag-app}"
NAMESPACE="${NAMESPACE:-rag-app}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      PROVIDER="$2"
      shift 2
      ;;
    --env)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --action)
      ACTION="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

BASE_VALUES="deploy/helm/rag-app/values.yaml"
OVERLAY_VALUES="deploy/overlays/${PROVIDER}/${ENVIRONMENT}/values.yaml"
IMAGE_REGISTRY="${IMAGE_REGISTRY:-}"
IMAGE_TAG="${IMAGE_TAG:-}"

IMAGE_OVERRIDES=()
if [[ -n "${IMAGE_REGISTRY}" ]]; then
  IMAGE_OVERRIDES+=("--set" "backend.image.repository=${IMAGE_REGISTRY}/rag-ray-backend")
  IMAGE_OVERRIDES+=("--set" "frontend.image.repository=${IMAGE_REGISTRY}/rag-ray-frontend")
fi
if [[ -n "${IMAGE_TAG}" ]]; then
  IMAGE_OVERRIDES+=("--set" "backend.image.tag=${IMAGE_TAG}")
  IMAGE_OVERRIDES+=("--set" "frontend.image.tag=${IMAGE_TAG}")
fi

case "${ACTION}" in
  apply)
    echo "Deploying ${RELEASE} to ${NAMESPACE} using ${PROVIDER}/${ENVIRONMENT}"
    helm -n "${NAMESPACE}" upgrade --install "${RELEASE}" deploy/helm/rag-app \
      --create-namespace \
      -f "${BASE_VALUES}" \
      -f "${OVERLAY_VALUES}" \
      "${IMAGE_OVERRIDES[@]}"
    ;;
  destroy)
    echo "Uninstalling ${RELEASE} from ${NAMESPACE}"
    helm -n "${NAMESPACE}" uninstall "${RELEASE}"
    ;;
  verify)
    echo "Verifying workloads in ${NAMESPACE}"
    kubectl -n "${NAMESPACE}" get pods
    kubectl -n "${NAMESPACE}" get svc
    ;;
  bench)
    python scripts/benchmark/stream_bench.py --url http://localhost:8000/query/stream
    ;;
  *)
    echo "Unsupported action: ${ACTION}"
    exit 1
    ;;
esac
