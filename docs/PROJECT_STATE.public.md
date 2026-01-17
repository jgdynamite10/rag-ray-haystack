# Project State (Public)

This file is safe to publish. Keep it sanitized and avoid sensitive details.

## Current status

- Infrastructure: Terraform scaffolding exists for Akamai LKE.
- Deployment: Helm chart for backend, frontend, Qdrant, RayService, and vLLM.
- GPU: vLLM runs on GPU nodes when `nvidia.com/gpu` capacity is available.
- Verification: Run `make verify` for end-to-end streaming checks.

## Open items

- Publish container images to a registry (GHCR/Docker Hub).
- Run benchmark and capture TTFT/tokens/sec metrics.

## Environment (sanitized)

- Provider: <provider>
- Namespace: <namespace>
- Release: <release>
