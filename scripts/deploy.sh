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
FRONTEND_TAG="${FRONTEND_TAG:-${IMAGE_TAG}}"  # Default to IMAGE_TAG; set separately for version mismatch (e.g. 0.3.5)
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${HOME}/.kube/${PROVIDER}-${ENVIRONMENT}-config.yaml}"

IMAGE_OVERRIDES=()
if [[ -n "${IMAGE_REGISTRY}" ]]; then
  IMAGE_OVERRIDES+=("--set" "backend.image.repository=${IMAGE_REGISTRY}/rag-ray-backend")
  IMAGE_OVERRIDES+=("--set" "frontend.image.repository=${IMAGE_REGISTRY}/rag-ray-frontend")
fi
if [[ -n "${IMAGE_TAG}" ]]; then
  IMAGE_OVERRIDES+=("--set" "backend.image.tag=${IMAGE_TAG}")
  IMAGE_OVERRIDES+=("--set" "frontend.image.tag=${FRONTEND_TAG}")
fi

ensure_node_labels() {
  local kc="$1"
  echo "Ensuring node role labels (node.kubernetes.io/role)..."
  for node in $(KUBECONFIG="$kc" kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    has_gpu=$(KUBECONFIG="$kc" kubectl get node "$node" -o jsonpath='{.metadata.labels.nvidia\.com/gpu\.present}' 2>/dev/null || true)
    if [[ "$has_gpu" == "true" ]]; then
      KUBECONFIG="$kc" kubectl label node "$node" node.kubernetes.io/role=gpu --overwrite >/dev/null
    else
      KUBECONFIG="$kc" kubectl label node "$node" node.kubernetes.io/role=cpu --overwrite >/dev/null
    fi
  done
  echo "Node labels applied."
}

ensure_monitoring() {
  local kc="$1"
  echo "Ensuring monitoring stack is installed..."

  if ! KUBECONFIG="$kc" helm -n monitoring status kube-prometheus-stack >/dev/null 2>&1; then
    echo "Installing kube-prometheus-stack..."
    KUBECONFIG="$kc" helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    KUBECONFIG="$kc" helm repo update >/dev/null 2>&1
    KUBECONFIG="$kc" helm -n monitoring upgrade --install kube-prometheus-stack \
      prometheus-community/kube-prometheus-stack \
      --create-namespace \
      --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
      --set prometheus.service.type=LoadBalancer \
      --set grafana.enabled=false \
      --wait --timeout 5m
    echo "kube-prometheus-stack installed."
  else
    echo "kube-prometheus-stack already installed."
  fi

  if ! KUBECONFIG="$kc" helm -n monitoring status prometheus-pushgateway >/dev/null 2>&1; then
    echo "Installing prometheus-pushgateway..."
    KUBECONFIG="$kc" helm -n monitoring upgrade --install prometheus-pushgateway \
      prometheus-community/prometheus-pushgateway \
      --set serviceMonitor.enabled=true \
      --set serviceMonitor.additionalLabels.release=kube-prometheus-stack
    echo "prometheus-pushgateway installed."
  else
    echo "prometheus-pushgateway already installed."
  fi
}

case "${ACTION}" in
  apply)
    echo "Deploying ${RELEASE} to ${NAMESPACE} using ${PROVIDER}/${ENVIRONMENT}"
    ensure_node_labels "${KUBECONFIG_PATH}"
    ensure_monitoring "${KUBECONFIG_PATH}"
    KUBECONFIG="${KUBECONFIG_PATH}" helm -n "${NAMESPACE}" upgrade --install "${RELEASE}" deploy/helm/rag-app \
      --create-namespace \
      -f "${BASE_VALUES}" \
      -f "${OVERLAY_VALUES}" \
      ${IMAGE_OVERRIDES[@]+"${IMAGE_OVERRIDES[@]}"}
    ;;
  destroy)
    echo "Uninstalling ${RELEASE} from ${NAMESPACE}"
    KUBECONFIG="${KUBECONFIG_PATH}" helm -n "${NAMESPACE}" uninstall "${RELEASE}"
    ;;
  verify)
    echo "Verifying workloads in ${NAMESPACE}"
    KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NAMESPACE}" get pods
    KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NAMESPACE}" get svc
    ;;
  bench)
    python scripts/benchmark/stream_bench.py --url http://localhost:8000/query/stream
    ;;
  *)
    echo "Unsupported action: ${ACTION}"
    exit 1
    ;;
esac
