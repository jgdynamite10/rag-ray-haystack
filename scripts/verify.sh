#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="rag-app"
RELEASE="rag-app"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --release)
      RELEASE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Step 1: show context and basic workload info.
kubectl config current-context
kubectl -n "${NAMESPACE}" get pods
kubectl -n "${NAMESPACE}" get svc

# Step 2: discover services by Helm labels and name patterns.
services=$(kubectl -n "${NAMESPACE}" get svc -l "app.kubernetes.io/instance=${RELEASE}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
vllm_svc=$(echo "${services}" | grep -i "vllm" | head -n 1 || true)
backend_svc=$(echo "${services}" | grep -i "backend" | head -n 1 || true)

if [[ -z "${vllm_svc}" || -z "${backend_svc}" ]]; then
  echo "Failed to discover services for release ${RELEASE} in ${NAMESPACE}."
  echo "Tip: ensure the release name matches and services exist."
  exit 1
fi

# Step 3: vLLM direct streaming check.
echo "Checking vLLM streaming via ${vllm_svc}..."
kubectl -n "${NAMESPACE}" port-forward "svc/${vllm_svc}" 8001:8000 >/tmp/vllm-port-forward.log 2>&1 &
vllm_pf_pid=$!
sleep 3

set +e
curl -N http://localhost:8001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"${VLLM_MODEL_ID:-Qwen/Qwen2.5-7B-Instruct}"'",
    "messages": [{"role":"user","content":"Say hello in 20 words."}],
    "stream": true,
    "max_tokens": 64
  }' | head -n 5
vllm_status=$?
set -e
kill "${vllm_pf_pid}" >/dev/null 2>&1 || true

if [[ ${vllm_status} -ne 0 ]]; then
  echo "vLLM streaming check failed."
  echo "Tip: verify vLLM pod readiness and check ingress buffering."
  exit 1
fi

# Step 4: Ray Serve SSE relay check.
echo "Checking Ray Serve SSE relay via ${backend_svc}..."
kubectl -n "${NAMESPACE}" port-forward "svc/${backend_svc}" 8000:8000 >/tmp/backend-port-forward.log 2>&1 &
backend_pf_pid=$!
sleep 3

set +e
curl -N -X POST http://localhost:8000/query/stream \
  -H "Content-Type: application/json" \
  -d '{"query":"Explain what this system is and why vLLM matters."}' | head -n 10
backend_status=$?
set -e
kill "${backend_pf_pid}" >/dev/null 2>&1 || true

if [[ ${backend_status} -ne 0 ]]; then
  echo "Ray Serve streaming relay failed."
  echo "Tip: verify backend pods, vLLM connectivity, and SSE buffering."
  exit 1
fi

echo "Verify completed successfully."
