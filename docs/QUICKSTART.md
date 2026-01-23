# Quickstart

## End-to-end Akamai LKE (cluster → app)

This assumes you have Akamai/Linode credentials and will create a new LKE cluster.

1) Clone the repo

```bash
git clone https://github.com/jgdynamite10/rag-ray-haystack
cd rag-ray-haystack
```

2) Create the cluster (Terraform)

```bash
cp infra/terraform/akamai-lke/terraform.tfvars.example infra/terraform/akamai-lke/terraform.tfvars
terraform -chdir=infra/terraform/akamai-lke init
terraform -chdir=infra/terraform/akamai-lke apply
```

3) Fetch kubeconfig and deploy the app

```bash
# write kubeconfig to ~/.kube/<provider>-<env>-config.yaml
make kubeconfig PROVIDER=akamai-lke ENV=dev
export KUBECONFIG=~/.kube/akamai-lke-dev-config.yaml
```

If your kubeconfig file name differs (ex: cluster label-specific), use:

```bash
export KUBECONFIG="/Users/$USER/.kube/<cluster>-kubeconfig.yaml"
```

# install KubeRay operator
KUBECONFIG_PATH="$KUBECONFIG" make install-kuberay PROVIDER=akamai-lke ENV=dev

# install GPU Operator + Node Feature Discovery
helm repo add nvidia-gpu https://nvidia.github.io/gpu-operator
helm repo add nfd https://kubernetes-sigs.github.io/node-feature-discovery/charts
helm repo update
helm upgrade --install gpu-operator nvidia-gpu/gpu-operator \
  --namespace gpu-operator --create-namespace
helm upgrade --install node-feature-discovery nfd/node-feature-discovery \
  --namespace node-feature-discovery --create-namespace

# apply GPU labels/taints (required for vLLM scheduling)
KUBECONFIG_PATH="$KUBECONFIG" make fix-gpu PROVIDER=akamai-lke ENV=dev

# deploy app images (replace with your registry/tag)
export IMAGE_REGISTRY=ghcr.io/jgdynamite10
export IMAGE_TAG=0.2.11
make deploy PROVIDER=akamai-lke ENV=dev IMAGE_REGISTRY=$IMAGE_REGISTRY IMAGE_TAG=$IMAGE_TAG
```

4) Verify workloads

```bash
make verify PROVIDER=akamai-lke ENV=dev NAMESPACE=rag-app RELEASE=rag-app
kubectl -n rag-app get svc
```

5) Optional: in-cluster streaming check (no public UI)

```bash
kubectl -n rag-app port-forward svc/rag-app-rag-app-backend 8000:8000
```

Second terminal:

```bash
curl -N -X POST http://localhost:8000/query/stream \
  -H "Content-Type: application/json" \
  -d '{"query":"Explain what this system is and why vLLM matters."}'
```

Expected behavior: `meta` → repeated `token` → `done` events.

## One-command flow

```bash
cp infra/terraform/akamai-lke/terraform.tfvars.example infra/terraform/akamai-lke/terraform.tfvars
GPU_FIX=1 make deploy PROVIDER=akamai-lke ENV=dev
```

This runs:

1. `terraform apply` in `infra/terraform/<provider>`
2. `make kubeconfig` (writes `~/.kube/<provider>-<env>-config.yaml`)
3. `helm upgrade --install` with base + overlay values

## Install KubeRay operator

```bash
make install-kuberay PROVIDER=akamai-lke ENV=dev
```

## Optional overrides

```bash
IMAGE_REGISTRY=registry.example.com/your-team \
IMAGE_TAG=0.1.0 \
make deploy PROVIDER=aws-eks ENV=prod RELEASE=rag-app NAMESPACE=rag-app
```

## Destroy

```bash
make destroy PROVIDER=akamai-lke ENV=dev
```

## Verify

```bash
make verify PROVIDER=akamai-lke ENV=dev NAMESPACE=rag-app RELEASE=rag-app
```
