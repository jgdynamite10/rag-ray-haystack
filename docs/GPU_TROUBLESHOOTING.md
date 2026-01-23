# GPU Troubleshooting

This guide documents the common GPU bring-up issues we hit on LKE and the
exact recovery steps. Use it when vLLM pods stay Pending or GPUs do not show
up in `nvidia.com/gpu` capacity.

## Symptoms

- `vllm` pod stuck in `Pending` with `Insufficient nvidia.com/gpu`
- `kubectl get nodes ... nvidia.com/gpu` shows empty values
- NVIDIA device plugin pods not scheduled

## Baseline checks

```bash
KUBECONFIG=~/.kube/akamai-lke-dev-config.yaml kubectl -n rag-app get pods -o wide
KUBECONFIG=~/.kube/akamai-lke-dev-config.yaml kubectl get nodes --show-labels | grep -i gpu
```

## Install GPU Operator (preferred)

```bash
helm repo add nvidia-gpu https://nvidia.github.io/gpu-operator
helm repo update

helm upgrade --install gpu-operator nvidia-gpu/gpu-operator \
  --namespace gpu-operator --create-namespace
```

## Ensure Node Feature Discovery tolerates GPU taint

If the GPU node is tainted (`nvidia.com/gpu=NoSchedule`), NFD may not run there.

```bash
KUBECONFIG=~/.kube/akamai-lke-dev-config.yaml \
kubectl -n node-feature-discovery patch ds node-feature-discovery-worker \
  --type='json' \
  -p='[
    {"op":"add","path":"/spec/template/spec/tolerations","value":[
      {"key":"nvidia.com/gpu","operator":"Exists","effect":"NoSchedule"}
    ]}
  ]'

KUBECONFIG=~/.kube/akamai-lke-dev-config.yaml \
kubectl -n node-feature-discovery rollout restart ds/node-feature-discovery-worker
```

## Force GPU Operator selectors (if labels are missing)

If driver/device-plugin daemonsets show 0 desired, apply GPU operator labels:

```bash
KUBECONFIG=~/.kube/akamai-lke-dev-config.yaml \
kubectl label node <gpu-node-name> \
  nvidia.com/gpu.deploy.driver=true \
  nvidia.com/gpu.deploy.device-plugin=true \
  nvidia.com/gpu.deploy.container-toolkit=true \
  nvidia.com/gpu.deploy.dcgm-exporter=true \
  nvidia.com/gpu.deploy.gpu-feature-discovery=true \
  nvidia.com/gpu.deploy.operator-validator=true \
  --overwrite
```

Then restart device plugin:

```bash
KUBECONFIG=~/.kube/akamai-lke-dev-config.yaml \
kubectl -n gpu-operator rollout restart ds/nvidia-device-plugin-daemonset
```

## Verify GPU capacity

```bash
KUBECONFIG=~/.kube/akamai-lke-dev-config.yaml \
kubectl get nodes -o jsonpath="{range .items[*]}{.metadata.name}{' -> '}{.status.capacity['nvidia.com/gpu']}{'\n'}{end}"
```

Once you see a non-empty GPU value, the vLLM pod should schedule.

## GPU allocatable is still empty after fix-gpu

If the NVIDIA device plugin is running and logs show it registered with kubelet,
but `nvidia.com/gpu` is still missing from `Capacity`/`Allocatable`, the node
likely needs a reboot to complete driver registration. `fix-gpu` labels nodes and
restarts daemonsets, but it cannot restart kubelet or reinitialize the kernel
driver stack.

### Symptoms

- `kubectl get nodes ... allocatable['nvidia.com/gpu']` is empty
- `kubectl describe node <gpu-node> | grep -A10 -i "Capacity"` does not list `nvidia.com/gpu`
- `kubectl -n gpu-operator logs -l app=nvidia-device-plugin-daemonset` shows device plugin started

### Recovery

1. Reboot the GPU node (LKE UI or provider console).
2. Wait for the node to rejoin.
3. Re-run the capacity check:

```bash
KUBECONFIG=~/.kube/akamai-lke-dev-config.yaml \
kubectl get nodes -o jsonpath="{range .items[*]}{.metadata.name}{' -> '}{.status.allocatable['nvidia.com/gpu']}{'\n'}{end}"
```

### Example (Akamai LKE)

- Working: RTX4000 Ada x1 **small** (us-sea) with `fix-gpu` only.
- Ashley's deployment: RTX4000 Ada x1 **medium** in a different region required a node reboot
  before `nvidia.com/gpu` appeared in `allocatable`.

## vLLM scheduling check

```bash
KUBECONFIG=~/.kube/akamai-lke-dev-config.yaml kubectl -n rag-app get pods -o wide
```

If vLLM is still `Pending`, check:

```bash
KUBECONFIG=~/.kube/akamai-lke-dev-config.yaml \
kubectl -n rag-app describe pod <vllm-pod-name>
```
