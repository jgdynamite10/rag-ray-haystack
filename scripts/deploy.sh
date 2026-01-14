#!/usr/bin/env bash
set -euo pipefail

PROVIDER="${PLATFORM:-aws}"
ENVIRONMENT="dev"

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
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

case "${PROVIDER}" in
  akamai)
    PROVIDER="akamai-lke"
    ;;
  aws)
    PROVIDER="aws-eks"
    ;;
  gcp)
    PROVIDER="gcp-gke"
    ;;
esac

OVERLAY="deploy/overlays/${PROVIDER}/${ENVIRONMENT}"

echo "Deploying overlay: ${OVERLAY}"
kustomize build "${OVERLAY}" --enable-helm | kubectl apply -f -
