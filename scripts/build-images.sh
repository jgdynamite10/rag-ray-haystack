#!/usr/bin/env bash
set -euo pipefail

REGISTRY="${IMAGE_REGISTRY:-local}"
TAG="${IMAGE_TAG:-0.1.0}"

echo "Building backend image..."
docker build -t "${REGISTRY}/rag-ray-backend:${TAG}" apps/backend

echo "Building frontend image..."
docker build -t "${REGISTRY}/rag-ray-frontend:${TAG}" apps/frontend
