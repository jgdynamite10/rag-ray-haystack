# Architecture

## Overview

- Frontend: React (Vite) chat UI for querying and ingesting documents.
- Backend: Ray Serve deployment using Haystack for retrieval.
- Vector store: Qdrant for persistence (helm-deployed, OSS).
- Orchestration: KubeRay (RayService) running the backend workload.
- Packaging: Helm chart + Kustomize overlays for provider-specific diffs.

## Data flow

1. User uploads PDFs/text to `/ingest`.
2. Backend extracts text and writes documents to the document store.
3. User queries `/query`.
4. Backend retrieves top documents and returns structured results.

## Observability

- `/metrics` exposes Prometheus-compatible metrics.
- Structured JSON logs via `python-json-logger`.

## Deployment

- Helm chart `deploy/helm/rag-app` installs backend, frontend, Qdrant, and RayService.
- Kustomize overlays in `deploy/overlays` customize storage class per provider.
