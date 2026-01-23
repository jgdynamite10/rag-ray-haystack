#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG_PATH:-${HOME}/.kube/akamai-lke-dev-config.yaml}"
GPU_NODE_NAME="${GPU_NODE_NAME:-}"

export KUBECONFIG="${KUBECONFIG_PATH}"

echo "Using KUBECONFIG=${KUBECONFIG_PATH}"

# Step 0: If GPUs are already advertised, skip.
gpu_capacity=$(kubectl get nodes -o jsonpath="{range .items[*]}{.metadata.name}{' -> '}{.status.capacity['nvidia.com/gpu']}{'\n'}{end}" | grep -E -- '-> [1-9]' || true)
if [[ -n "${gpu_capacity}" ]]; then
  echo "GPU capacity already advertised. Skipping GPU fix."
  exit 0
fi

# Step 1: Ensure NFD tolerates GPU taints so it can label GPU nodes.
kubectl -n node-feature-discovery patch ds node-feature-discovery-worker \
  --type='json' \
  -p='[
    {"op":"add","path":"/spec/template/spec/tolerations","value":[
      {"key":"nvidia.com/gpu","operator":"Exists","effect":"NoSchedule"}
    ]}
  ]' || true

kubectl -n node-feature-discovery rollout restart ds/node-feature-discovery-worker || true

# Step 2: Pick a GPU node if not provided.
if [[ -z "${GPU_NODE_NAME}" ]]; then
  GPU_NODE_NAME=$(kubectl get nodes --show-labels | awk '
    $0 ~ /instance-type=g.*gpu/ {print $1; exit}
  ')
fi

if [[ -z "${GPU_NODE_NAME}" ]]; then
  echo "No GPU node detected. Set GPU_NODE_NAME explicitly."
  exit 1
fi

echo "Using GPU node: ${GPU_NODE_NAME}"

# If the node already has GPU operator labels, skip.
if kubectl get node "${GPU_NODE_NAME}" --show-labels | grep -q "nvidia.com/gpu.deploy.device-plugin=true"; then
  echo "GPU operator labels already applied. Skipping label step."
else
  # Step 3: Apply GPU Operator selector labels.
  kubectl label node "${GPU_NODE_NAME}" \
    nvidia.com/gpu.deploy.driver=true \
    nvidia.com/gpu.deploy.device-plugin=true \
    nvidia.com/gpu.deploy.container-toolkit=true \
    nvidia.com/gpu.deploy.dcgm-exporter=true \
    nvidia.com/gpu.deploy.gpu-feature-discovery=true \
    nvidia.com/gpu.deploy.operator-validator=true \
    --overwrite
fi

# Step 4: Restart device plugin to register resources.
kubectl -n gpu-operator rollout restart ds/nvidia-device-plugin-daemonset || true

echo "GPU fix applied. Check capacity with:"
echo "kubectl get nodes -o jsonpath=\"{range .items[*]}{.metadata.name}{' -> '}{.status.capacity['nvidia.com/gpu']}{'\\n'}{end}\""
