# Quickstart

## GPU instances by provider

All providers use comparable Ada Lovelace architecture GPUs:

| Provider | Instance | GPU | vRAM |
|----------|----------|-----|------|
| Akamai | g2-gpu-rtx4000a1-s | RTX 4000 Ada | 20 GB |
| AWS | g6.xlarge | NVIDIA L4 | 24 GB |
| GCP | g2-standard-8 | NVIDIA L4 | 24 GB |

---

## End-to-end Akamai LKE (cluster → app)

This assumes you have Akamai/Linode credentials and will create a new LKE cluster.

1. Clone the repo

```bash
git clone https://github.com/jgdynamite10/rag-ray-haystack
cd rag-ray-haystack
```

2. Create the cluster (Terraform)

```bash
cp infra/terraform/akamai-lke/terraform.tfvars.example infra/terraform/akamai-lke/terraform.tfvars
terraform -chdir=infra/terraform/akamai-lke init
terraform -chdir=infra/terraform/akamai-lke apply
```

3. Fetch kubeconfig and install dependencies

```bash
# write kubeconfig to ~/.kube/<provider>-<env>-config.yaml
make kubeconfig PROVIDER=akamai-lke ENV=dev
export KUBECONFIG=~/.kube/akamai-lke-dev-config.yaml
```

If your kubeconfig file name differs (ex: cluster label-specific), use a real
path (avoid angle brackets):

```bash
export KUBECONFIG="$HOME/.kube/<your-kubeconfig-file>kubeconfig.yaml"
```

Install KubeRay operator:

```bash
KUBECONFIG_PATH="$KUBECONFIG" make install-kuberay PROVIDER=akamai-lke ENV=dev
```

Install GPU Operator + Node Feature Discovery:

```bash
helm repo add nvidia-gpu https://nvidia.github.io/gpu-operator
helm repo add nfd https://kubernetes-sigs.github.io/node-feature-discovery/charts
helm repo update
helm upgrade --install gpu-operator nvidia-gpu/gpu-operator \
  --namespace gpu-operator --create-namespace
helm upgrade --install node-feature-discovery nfd/node-feature-discovery \
  --namespace node-feature-discovery --create-namespace
```

Apply GPU labels/taints (required for vLLM scheduling):

```bash
KUBECONFIG_PATH="$KUBECONFIG" make fix-gpu PROVIDER=akamai-lke ENV=dev
```

4. Deploy app images (replace with your registry/tag):

```bash
export IMAGE_REGISTRY=ghcr.io/jgdynamite10
export IMAGE_TAG=0.2.11
make deploy PROVIDER=akamai-lke ENV=dev IMAGE_REGISTRY=$IMAGE_REGISTRY IMAGE_TAG=$IMAGE_TAG
```

5. Verify workloads

```bash
KUBECONFIG_PATH="$KUBECONFIG" make verify PROVIDER=akamai-lke ENV=dev NAMESPACE=rag-app RELEASE=rag-app
kubectl -n rag-app get svc
```

Expected output (abridged):

```text
NAME                                        READY   STATUS    RESTARTS   AGE
rag-app-rag-app-backend-7bcc875cbc-xxxxx    1/1     Running   0          5m
rag-app-rag-app-frontend-5867fc4f99-xxxxx   1/1     Running   0          5m
rag-app-rag-app-qdrant-0                    1/1     Running   0          5m
rag-app-rag-app-vllm-54cdbb8b59-xxxxx       1/1     Running   0          2m

NAME                       TYPE           EXTERNAL-IP
rag-app-rag-app-frontend   LoadBalancer   <public-ip>

Checking vLLM streaming via rag-app-rag-app-vllm...
data: {"object":"chat.completion.chunk", ... "model":"rag-default", ...}

Checking Ray Serve SSE relay via rag-app-rag-app-backend...
event: meta
event: token
```

Note: `curl: (23) Failure writing output to destination` can appear during streaming checks and
is expected; success is indicated by streamed `data:` or `event:` lines.

6. Optional: in-cluster streaming check (no public UI)

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

---

## End-to-end GCP GKE (cluster → app)

This assumes you have GCP credentials configured (`gcloud auth login`).

### 1. Create GCP project and enable APIs

```bash
# Create a new project (skip if reusing existing)
gcloud projects create rag-ray-haystack --name="RAG Ray Haystack"

# If project ID is taken, use a unique suffix:
# gcloud projects create rag-ray-haystack-$(date +%Y%m%d) --name="RAG Ray Haystack"

# Link billing (required for GKE)
gcloud billing accounts list
gcloud billing projects link rag-ray-haystack --billing-account=YOUR_BILLING_ACCOUNT_ID

# Set as active project
gcloud config set project rag-ray-haystack

# Enable required APIs
gcloud services enable container.googleapis.com compute.googleapis.com
```

### 2. Configure Terraform

```bash
cp infra/terraform/gcp-gke/terraform.tfvars.example infra/terraform/gcp-gke/terraform.tfvars
# Edit terraform.tfvars and set your project_id
```

### 3. Create the cluster

```bash
terraform -chdir=infra/terraform/gcp-gke init
terraform -chdir=infra/terraform/gcp-gke apply
```

### 4. Fetch kubeconfig and install dependencies

```bash
make kubeconfig PROVIDER=gcp-gke ENV=dev
export KUBECONFIG=~/.kube/gcp-gke-dev-config.yaml
```

Install KubeRay operator:

```bash
KUBECONFIG_PATH="$KUBECONFIG" make install-kuberay PROVIDER=gcp-gke ENV=dev
```

Install GPU Operator + Node Feature Discovery:

```bash
helm repo add nvidia-gpu https://nvidia.github.io/gpu-operator
helm repo add nfd https://kubernetes-sigs.github.io/node-feature-discovery/charts
helm repo update
helm upgrade --install gpu-operator nvidia-gpu/gpu-operator \
  --namespace gpu-operator --create-namespace
helm upgrade --install node-feature-discovery nfd/node-feature-discovery \
  --namespace node-feature-discovery --create-namespace
```

### 5. Deploy app images

```bash
export IMAGE_REGISTRY=ghcr.io/jgdynamite10
export IMAGE_TAG=0.2.11
make deploy PROVIDER=gcp-gke ENV=dev IMAGE_REGISTRY=$IMAGE_REGISTRY IMAGE_TAG=$IMAGE_TAG
```

### 6. Verify workloads

```bash
KUBECONFIG_PATH="$KUBECONFIG" make verify PROVIDER=gcp-gke ENV=dev NAMESPACE=rag-app RELEASE=rag-app
kubectl -n rag-app get svc
```

### 7. Destroy (when done)

```bash
make destroy PROVIDER=gcp-gke ENV=dev
```

---

## End-to-end AWS EKS (cluster → app)

This assumes you have AWS credentials configured (`aws configure`).

### Prerequisites

1. **AWS CLI** installed:
   ```bash
   brew install awscli
   aws --version
   ```

2. **AWS credentials** configured:
   ```bash
   aws configure
   # Enter: Access Key ID, Secret Access Key, Region (us-east-1), Output format
   ```

3. **IAM permissions** — attach these policies to your IAM user:
   - `AmazonEKSClusterPolicy`
   - `AmazonVPCFullAccess`
   - `IAMFullAccess`
   - `AmazonEC2FullAccess`
   - `CloudWatchLogsFullAccess`

4. **GPU quota** — request increase for "Running On-Demand G and VT instances":
   ```bash
   aws service-quotas request-service-quota-increase \
     --service-code ec2 \
     --quota-code L-DB2E81BA \
     --desired-value 4 \
     --region us-east-1
   ```
   Or via AWS Console: **Service Quotas → Amazon EC2 → Running On-Demand G and VT instances**

### 1. Clone the repo

```bash
git clone https://github.com/jgdynamite10/rag-ray-haystack
cd rag-ray-haystack
```

### 2. Create the cluster (Terraform)

```bash
cp infra/terraform/aws-eks/terraform.tfvars.example infra/terraform/aws-eks/terraform.tfvars
# Edit terraform.tfvars if needed (region, instance types)

terraform -chdir=infra/terraform/aws-eks init
terraform -chdir=infra/terraform/aws-eks apply
```

This creates:
- EKS cluster (K8s 1.34)
- 2 CPU nodes (m5.large)
- 1 GPU node (g6.xlarge with NVIDIA L4)

### 3. Configure kubectl access

```bash
aws eks update-kubeconfig --region us-east-1 --name rag-ray-haystack \
  --kubeconfig ~/.kube/aws-eks-dev-config.yaml
export KUBECONFIG=~/.kube/aws-eks-dev-config.yaml
```

**Important:** Use `aws eks update-kubeconfig`, not the Terraform-generated kubeconfig.

### 4. Grant IAM user cluster access

EKS requires explicit access entries. If `kubectl get nodes` returns `401 Unauthorized`:

```bash
# Get your IAM ARN
aws sts get-caller-identity

# Create access entry (replace ACCOUNT_ID and USERNAME)
aws eks create-access-entry \
  --cluster-name rag-ray-haystack \
  --principal-arn arn:aws:iam::<ACCOUNT_ID>:user/<USERNAME> \
  --region us-east-1

# Associate cluster admin policy
aws eks associate-access-policy \
  --cluster-name rag-ray-haystack \
  --principal-arn arn:aws:iam::<ACCOUNT_ID>:user/<USERNAME> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster \
  --region us-east-1
```

See [EKS Access Entries documentation](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html).

### 5. Verify cluster access

```bash
kubectl get nodes
```

Expected: 3 nodes (2 CPU + 1 GPU) in `Ready` status.

### 6. Install dependencies

```bash
# KubeRay operator
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update
helm upgrade --install kuberay-operator kuberay/kuberay-operator \
  --namespace kuberay-system --create-namespace

# GPU Operator + Node Feature Discovery
helm repo add nvidia-gpu https://nvidia.github.io/gpu-operator
helm repo add nfd https://kubernetes-sigs.github.io/node-feature-discovery/charts
helm repo update
helm upgrade --install gpu-operator nvidia-gpu/gpu-operator \
  --namespace gpu-operator --create-namespace
helm upgrade --install node-feature-discovery nfd/node-feature-discovery \
  --namespace node-feature-discovery --create-namespace
```

### 7. Deploy app

```bash
export IMAGE_REGISTRY=ghcr.io/jgdynamite10
export IMAGE_TAG=0.2.11

helm -n rag-app upgrade --install rag-app deploy/helm/rag-app \
  --create-namespace \
  -f deploy/helm/rag-app/values.yaml \
  -f deploy/overlays/aws-eks/dev/values.yaml \
  --set backend.image.repository=$IMAGE_REGISTRY/rag-ray-backend \
  --set frontend.image.repository=$IMAGE_REGISTRY/rag-ray-frontend \
  --set backend.image.tag=$IMAGE_TAG \
  --set frontend.image.tag=$IMAGE_TAG
```

### 8. Verify workloads

```bash
# Watch pods start (vLLM takes 2-3 min to download model)
kubectl -n rag-app get pods -w

# Check services
kubectl -n rag-app get svc

# Run streaming verification
make verify PROVIDER=aws-eks ENV=dev NAMESPACE=rag-app RELEASE=rag-app
```

Expected output:
```text
NAME                                        READY   STATUS    RESTARTS   AGE
rag-app-rag-app-backend-xxxxx               1/1     Running   0          5m
rag-app-rag-app-frontend-xxxxx              1/1     Running   0          5m
rag-app-rag-app-qdrant-0                    1/1     Running   0          5m
rag-app-rag-app-vllm-xxxxx                  1/1     Running   0          3m

NAME                       TYPE           EXTERNAL-IP
rag-app-rag-app-frontend   LoadBalancer   <public-ip>
```

### 9. Access the UI

Get the LoadBalancer external IP:
```bash
kubectl -n rag-app get svc rag-app-rag-app-frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Open `http://<hostname>/` in your browser.

### 10. Destroy (when done)

```bash
# Delete app
helm -n rag-app uninstall rag-app

# Delete cluster
terraform -chdir=infra/terraform/aws-eks destroy
```

---

## One-command flow

```bash
cp infra/terraform/akamai-lke/terraform.tfvars.example infra/terraform/akamai-lke/terraform.tfvars
KUBECONFIG_PATH="$KUBECONFIG" GPU_FIX=1 make deploy PROVIDER=akamai-lke ENV=dev
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
