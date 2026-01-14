#!/usr/bin/env bash
set -euo pipefail

PLATFORM="${PLATFORM:-aws-eks}"

echo "Deploying overlay: ${PLATFORM}"
kustomize build "deploy/overlays/${PLATFORM}" --enable-helm | kubectl apply -f -
