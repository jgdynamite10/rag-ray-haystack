#!/usr/bin/env bash
set -euo pipefail

REGISTRY="${IMAGE_REGISTRY:-local}"
TAG="${IMAGE_TAG:-0.1.0}"

echo "Pushing backend image..."
docker push "${REGISTRY}/rag-ray-backend:${TAG}"

echo "Pushing frontend image..."
docker push "${REGISTRY}/rag-ray-frontend:${TAG}"
