# Deployment Guide

This guide covers deploying the RAG system to Akamai LKE, AWS EKS, and GCP GKE.

---

## Prerequisites

- Terraform >= 1.0
- kubectl
- Helm 3
- AWS CLI (for EKS)
- gcloud CLI (for GKE)
- linode-cli (for LKE)

---

## Quickstart (Fast Path)

### GPU instances by provider

| Provider | Instance | GPU | vRAM |
|----------|----------|-----|------|
| Akamai | g2-gpu-rtx4000a1-s | RTX 4000 Ada | 20 GB |
| AWS | g6.xlarge | NVIDIA L4 | 24 GB |
| GCP | g2-standard-8 | NVIDIA L4 | 24 GB |

### End-to-end Akamai LKE (cluster → app)

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
make kubeconfig PROVIDER=akamai-lke ENV=dev
export KUBECONFIG=~/.kube/akamai-lke-dev-config.yaml
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
export IMAGE_REGISTRY=ghcr.io/<owner>
export IMAGE_TAG=0.3.8
make deploy PROVIDER=akamai-lke ENV=dev IMAGE_REGISTRY=$IMAGE_REGISTRY IMAGE_TAG=$IMAGE_TAG
```

5. Verify workloads

```bash
KUBECONFIG_PATH="$KUBECONFIG" make verify PROVIDER=akamai-lke ENV=dev NAMESPACE=rag-app RELEASE=rag-app
kubectl -n rag-app get svc
```

Optional in-cluster streaming check:

```bash
kubectl -n rag-app port-forward svc/rag-app-rag-app-backend 8000:8000
curl -N -X POST http://localhost:8000/query/stream \
  -H "Content-Type: application/json" \
  -d '{"query":"Explain what this system is and why vLLM matters."}'
```

---

## AWS EKS Deployment

### Step 1: Deploy EKS Cluster

```bash
cd infra/terraform/aws-eks

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy (takes ~15-20 minutes)
terraform apply
```

**Default Configuration:**
| Setting | Value |
|---------|-------|
| Region | us-east-1 |
| Cluster | rag-ray-haystack |
| CPU Nodes | 2x m5.large |
| GPU Nodes | 1x g4dn.xlarge (T4 GPU) |
| K8s Version | 1.29 |

### Step 2: Configure kubectl

```bash
# Update kubeconfig using AWS CLI
aws eks update-kubeconfig \
  --name rag-ray-haystack \
  --region us-east-1 \
  --kubeconfig ~/.kube/eks-kubeconfig.yaml

# Set kubeconfig
export KUBECONFIG=~/.kube/eks-kubeconfig.yaml

# Verify access
kubectl get nodes
```

**If you get credential errors**, add your IAM user to the cluster:
```bash
aws eks create-access-entry \
  --cluster-name rag-ray-haystack \
  --principal-arn arn:aws:iam::<ACCOUNT_ID>:user/<USERNAME> \
  --region us-east-1

aws eks associate-access-policy \
  --cluster-name rag-ray-haystack \
  --principal-arn arn:aws:iam::<ACCOUNT_ID>:user/<USERNAME> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster \
  --region us-east-1
```

### Step 3: Deploy Prometheus Stack

```bash
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set prometheus.prometheusSpec.externalLabels.provider=aws-eks \
  --set prometheus.service.type=LoadBalancer
```

### Step 4: Deploy Pushgateway

```bash
kubectl apply -f deploy/monitoring/pushgateway.yaml
```

### Step 5: Install NVIDIA Device Plugin (if needed)

```bash
# Check if already installed
kubectl get pods -n kube-system | grep nvidia

# If not present, install
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.1/nvidia-device-plugin.yml
```

### Step 6: Install EBS CSI Driver (required for persistent storage)

EKS requires the EBS CSI driver addon for PersistentVolumeClaims (Qdrant storage):

```bash
# Get OIDC provider ID
OIDC_ID=$(aws eks describe-cluster --name rag-ray-haystack --region us-east-1 \
  --query 'cluster.identity.oidc.issuer' --output text | cut -d'/' -f5)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create OIDC provider (if not exists)
aws iam create-open-id-connect-provider \
  --url https://oidc.eks.us-east-1.amazonaws.com/id/$OIDC_ID \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da2b0ab7280 2>/dev/null || true

# Create trust policy for EBS CSI
cat > /tmp/ebs-trust.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::\${ACCOUNT_ID}:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/\${OIDC_ID}"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.us-east-1.amazonaws.com/id/\${OIDC_ID}:aud": "sts.amazonaws.com",
        "oidc.eks.us-east-1.amazonaws.com/id/\${OIDC_ID}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
      }
    }
  }]
}
EOF

# Create IAM role
aws iam create-role \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --assume-role-policy-document file:///tmp/ebs-trust.json 2>/dev/null || true

aws iam attach-role-policy \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy 2>/dev/null || true

# Install EBS CSI addon
aws eks create-addon \
  --cluster-name rag-ray-haystack \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::${ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole \
  --region us-east-1

# Verify addon is ACTIVE
aws eks describe-addon --cluster-name rag-ray-haystack \
  --addon-name aws-ebs-csi-driver --region us-east-1 --query 'addon.status'

# Verify pods are running
kubectl get pods -n kube-system | grep ebs
```

### Step 7: Install KubeRay Operator

The RAG app uses Ray Serve, which requires the KubeRay operator for RayService CRDs.

```bash
# Add KubeRay Helm repo
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update

# Install KubeRay operator
helm install kuberay-operator kuberay/kuberay-operator \
  --namespace ray-system --create-namespace

# Wait for operator to be ready
kubectl get pods -n ray-system
```

### Step 8: Deploy RAG Application

```bash
export IMAGE_REGISTRY=ghcr.io/jgdynamite10
export IMAGE_TAG=0.3.8

helm -n rag-app upgrade --install rag-app deploy/helm/rag-app \
  --create-namespace \
  -f deploy/helm/rag-app/values.yaml \
  -f deploy/overlays/aws-eks/dev/values.yaml \
  --set backend.image.repository=${IMAGE_REGISTRY}/rag-ray-backend \
  --set frontend.image.repository=${IMAGE_REGISTRY}/rag-ray-frontend \
  --set backend.image.tag=${IMAGE_TAG} \
  --set frontend.image.tag=${IMAGE_TAG}
```

**Note:** The Helm chart automatically deploys a ServiceMonitor for Prometheus scraping. Verify it's working:
```bash
kubectl get servicemonitor -n rag-app
# Should show: rag-app-rag-app-backend
```

**Note:** If you get StatefulSet errors on upgrade, delete and reinstall:
```bash
helm uninstall rag-app -n rag-app
kubectl delete pvc -n rag-app --all
# Then run the install command above
```

### Step 9: Get External IPs

```bash
# Prometheus (for Central Grafana datasource)
kubectl get svc -n monitoring prometheus-kube-prometheus-prometheus

# RAG App (for benchmarking)
kubectl get svc -n rag-app rag-app-rag-app-frontend

# Watch pods until ready (Ctrl+C to exit)
kubectl get pods -n rag-app -w
```

### Step 10: Add to Central Grafana

Add a new Prometheus datasource:
- **Name**: `Prometheus-EKS`
- **URL**: `http://<EKS-PROMETHEUS-ELB>:9090`
- **Variable**: `ds_eks`

---

## Akamai LKE Deployment

### Step 1: Deploy LKE Cluster

```bash
cd infra/terraform/akamai-lke

terraform init
terraform plan
terraform apply
```

### Step 2: Configure kubectl

```bash
# Download kubeconfig from Linode Cloud Manager
# Or use Terraform output
terraform output -raw kubeconfig > ~/.kube/lke-kubeconfig.yaml

export KUBECONFIG=~/.kube/lke-kubeconfig.yaml
kubectl get nodes
```

### Step 3: Deploy Prometheus Stack

```bash
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set prometheus.prometheusSpec.externalLabels.provider=akamai-lke \
  --set prometheus.service.type=LoadBalancer
```

### Step 4: Deploy Pushgateway

```bash
kubectl apply -f deploy/monitoring/pushgateway.yaml
```

### Step 5: Install NVIDIA Device Plugin (if needed)

```bash
kubectl get pods -n kube-system | grep nvidia
# If not present:
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.1/nvidia-device-plugin.yml
```

### Step 6: Install KubeRay Operator

```bash
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update
helm install kuberay-operator kuberay/kuberay-operator \
  --namespace ray-system --create-namespace
kubectl get pods -n ray-system
```

### Step 7: Deploy RAG Application

```bash
export IMAGE_REGISTRY=ghcr.io/jgdynamite10
export IMAGE_TAG=0.3.8

helm -n rag-app upgrade --install rag-app deploy/helm/rag-app \
  --create-namespace \
  -f deploy/helm/rag-app/values.yaml \
  -f deploy/overlays/akamai-lke/dev/values.yaml \
  --set backend.image.repository=${IMAGE_REGISTRY}/rag-ray-backend \
  --set frontend.image.repository=${IMAGE_REGISTRY}/rag-ray-frontend \
  --set backend.image.tag=${IMAGE_TAG} \
  --set frontend.image.tag=${IMAGE_TAG}
```

---

## GCP GKE Deployment

### Step 1: Deploy GKE Cluster

```bash
cd infra/terraform/gcp-gke

terraform init
terraform plan
terraform apply
```

### Step 2: Configure kubectl

```bash
gcloud container clusters get-credentials rag-ray-haystack \
  --region us-central1 \
  --project <PROJECT_ID>

# Or use Terraform output
terraform output -raw kubeconfig > ~/.kube/gke-kubeconfig.yaml
export KUBECONFIG=~/.kube/gke-kubeconfig.yaml
```

### Step 3: Deploy Prometheus Stack

```bash
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set prometheus.prometheusSpec.externalLabels.provider=gcp-gke \
  --set prometheus.service.type=LoadBalancer
```

### Step 4: Deploy Pushgateway

```bash
kubectl apply -f deploy/monitoring/pushgateway.yaml
```

### Step 5: Install NVIDIA Device Plugin (if needed)

```bash
kubectl get pods -n kube-system | grep nvidia
# GKE with GPU node pools usually has this pre-installed
# If not present:
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.1/nvidia-device-plugin.yml
```

### Step 6: Install DCGM Exporter (for GPU metrics)

GKE has the device plugin pre-installed but NOT DCGM exporter. Install it for GPU metrics:

```bash
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts
helm repo update

# Create values file (avoids shell escaping issues)
cat > /tmp/dcgm-gke-values.yaml << 'EOF'
serviceMonitor:
  enabled: true
  additionalLabels:
    release: prometheus

nodeSelector:
  nvidia.com/gpu.present: "true"

tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
EOF

helm install dcgm-exporter gpu-helm-charts/dcgm-exporter \
  --namespace monitoring \
  -f /tmp/dcgm-gke-values.yaml

# Verify running on GPU node
kubectl get pods -n monitoring | grep dcgm
```

### Step 7: Install KubeRay Operator

```bash
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update
helm install kuberay-operator kuberay/kuberay-operator \
  --namespace ray-system --create-namespace
kubectl get pods -n ray-system
```

### Step 8: Deploy RAG Application

```bash
export IMAGE_REGISTRY=ghcr.io/jgdynamite10
export IMAGE_TAG=0.3.8

helm -n rag-app upgrade --install rag-app deploy/helm/rag-app \
  --create-namespace \
  -f deploy/helm/rag-app/values.yaml \
  -f deploy/overlays/gcp-gke/dev/values.yaml \
  --set backend.image.repository=${IMAGE_REGISTRY}/rag-ray-backend \
  --set frontend.image.repository=${IMAGE_REGISTRY}/rag-ray-frontend \
  --set backend.image.tag=${IMAGE_TAG} \
  --set frontend.image.tag=${IMAGE_TAG}
```

---

## Provider Configuration Differences

### Storage Classes

Each provider uses a different storage class for PersistentVolumeClaims (Qdrant data):

| Provider | Storage Class | Description |
|----------|---------------|-------------|
| Akamai LKE | `linode-block-storage` | Linode Block Storage (NVMe SSD) |
| AWS EKS | `gp2` | EBS General Purpose SSD (requires EBS CSI driver) |
| GCP GKE | `standard-rwo` | Persistent Disk (SSD, ReadWriteOnce) |

These are configured in each provider's overlay values file:
- `deploy/overlays/akamai-lke/dev/values.yaml`
- `deploy/overlays/aws-eks/dev/values.yaml`
- `deploy/overlays/gcp-gke/dev/values.yaml`

### LLM Model

All providers use the same model for fair benchmarking comparison:
- **Model**: `Qwen/Qwen2.5-3B-Instruct`
- **Served Name**: `rag-default`
- **Max Model Length**: 2048 tokens

---

## Operations Runbook (Day-2)

### Build and push images

```bash
export IMAGE_REGISTRY=registry.example.com/your-team
export IMAGE_TAG=0.3.8
./scripts/build-images.sh
./scripts/push-images.sh
```

### Deploy (scripted)

```bash
cp infra/terraform/akamai-lke/terraform.tfvars.example infra/terraform/akamai-lke/terraform.tfvars
./scripts/deploy.sh --provider akamai-lke --env dev --action apply
```

### Install KubeRay operator

```bash
export KUBECONFIG=~/.kube/akamai-lke-dev-config.yaml
KUBECONFIG_PATH="$KUBECONFIG" make install-kuberay PROVIDER=akamai-lke ENV=dev
```

### GPU bring-up (automated)

```bash
helm repo add nvidia-gpu https://nvidia.github.io/gpu-operator
helm repo add nfd https://kubernetes-sigs.github.io/node-feature-discovery/charts
helm repo update
helm upgrade --install gpu-operator nvidia-gpu/gpu-operator \
  --namespace gpu-operator --create-namespace
helm upgrade --install node-feature-discovery nfd/node-feature-discovery \
  --namespace node-feature-discovery --create-namespace

KUBECONFIG_PATH="$KUBECONFIG" make fix-gpu PROVIDER=akamai-lke ENV=dev
kubectl get nodes -o jsonpath="{range .items[*]}{.metadata.name}{' -> '}{.status.capacity['nvidia.com/gpu']}{'\n'}{end}"
```

### Verify

```bash
kubectl config current-context
kubectl get ns
kubectl -n <namespace> get svc
kubectl -n <namespace> get pods
make verify NAMESPACE=<namespace> RELEASE=<release>
```

### Backend configuration (env vars)

- `RAG_USE_EMBEDDINGS` (default `true`)
- `EMBEDDING_MODEL_ID` (default `sentence-transformers/all-MiniLM-L6-v2`)
- `RAG_TOP_K` (default `4`)
- `RAG_MAX_HISTORY` (default `6`)
- `QDRANT_URL` (optional, e.g. `http://rag-app-rag-app-qdrant:6333`)
- `QDRANT_COLLECTION` (default `rag-documents`)
- `VLLM_BASE_URL` (default `http://vllm:8000`)
- `VLLM_MODEL` (default `Qwen/Qwen2.5-7B-Instruct`)
- `VLLM_MAX_TOKENS` (default `512`)
- `VLLM_TEMPERATURE` (default `0.2`)
- `VLLM_TOP_P` (default `0.95`)
- `VLLM_TIMEOUT_SECONDS` (default `30`)

### Streaming responses

SSE event types:
- `meta` (retrieval timings + documents)
- `ttft` (time-to-first-token)
- `token` (token delta)
- `done` (final timings + citations)

### Swap vLLM models

- Helm: set `vllm.model` and (optionally) `vllm.quantization`.
- Backend env: set `VLLM_MODEL`.

Common options:
- Smaller / lower cost: `Qwen/Qwen2.5-3B-Instruct`
- Balanced default: `Qwen/Qwen2.5-7B-Instruct`
- Higher quality / more VRAM: `Qwen/Qwen2.5-14B-Instruct`

### Connector inputs

`/ingest` accepts:
- multipart files: `.pdf`, `.docx`, `.html`, `.txt`
- JSON body with `texts`, `documents`, `urls`, or `sitemap_url`

Example:
```json
{
  "urls": ["https://example.com/docs"],
  "sitemap_url": "https://example.com/sitemap.xml"
}
```

### In-cluster sanity checks

#### A. vLLM streaming (direct)

```bash
kubectl -n <namespace> get svc | grep vllm
kubectl -n <namespace> port-forward svc/<release>-vllm 8001:8000

export VLLM_MODEL_ID="Qwen/Qwen2.5-7B-Instruct"
curl -N http://localhost:8001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"$VLLM_MODEL_ID"'",
    "messages": [{"role":"user","content":"Say hello in 20 words."}],
    "stream": true,
    "max_tokens": 64
  }'
```

Expected behavior: many incremental `data:` events, not a single buffered response.

#### B. Ray Serve → vLLM streaming relay (SSE end-to-end)

```bash
kubectl -n <namespace> get svc | grep backend
kubectl -n <namespace> port-forward svc/<release>-backend 8000:8000

curl -N -X POST http://localhost:8000/query/stream \
  -H "Content-Type: application/json" \
  -d '{"query":"Explain what this system is and why vLLM matters."}'
```

Expected behavior: `meta` → `ttft` → repeated `token` → `done` events.

#### C. Disable buffering for SSE paths

If deploying behind an ingress, disable response buffering for SSE paths. Example
NGINX ingress snippet:

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_set_header X-Accel-Buffering "no";
```

---

## Post-Deployment: Run Benchmarks

After deploying to any provider, run the benchmark workflow:

### 1. Ingest Documents

```bash
# Via API
curl -X POST "http://<FRONTEND_IP>/api/ingest" \
  -F "file=@/path/to/document.pdf"

# Or use the UI
open http://<FRONTEND_IP>
```

### 2. Run East-West Probe

```bash
./scripts/netprobe/run_ew.sh --provider <provider-name>
# provider-name: akamai-lke, aws-eks, gcp-gke
```

### 3. Run North-South Benchmark

```bash
# Standard test
./scripts/benchmark/run_ns.sh <provider-name> \
  --url http://<FRONTEND_IP>/api/query/stream \
  --requests 100 \
  --concurrency 10 \
  --max-output-tokens 256

# Load test
./scripts/benchmark/run_ns.sh <provider-name> \
  --url http://<FRONTEND_IP>/api/query/stream \
  --requests 500 \
  --concurrency 50 \
  --warmup 20 \
  --max-output-tokens 256
```

---

## Central Grafana Setup

The Central Grafana VM aggregates metrics from all clusters.

### Add Datasources

For each provider, add a Prometheus datasource:

| Provider | Datasource Name | Variable |
|----------|-----------------|----------|
| LKE | Prometheus-LKE | `ds_lke` |
| EKS | Prometheus-EKS | `ds_eks` |
| GKE | Prometheus-GKE | `ds_gke` |

**URL Format**: `http://<PROMETHEUS_LOADBALANCER_IP>:9090`

### Import Dashboard

Import `grafana/dashboards/itdm-unified.json` for the unified comparison dashboard.

---

## Cleanup

### AWS EKS
```bash
cd infra/terraform/aws-eks
terraform destroy
```

### Akamai LKE
```bash
cd infra/terraform/akamai-lke
terraform destroy
```

### GCP GKE
```bash
cd infra/terraform/gcp-gke
terraform destroy
```

---

## Troubleshooting

### EKS: Credential Errors

If you get "the server has asked for the client to provide credentials":

```bash
# Check your AWS identity
aws sts get-caller-identity

# Add your user to the cluster
aws eks create-access-entry \
  --cluster-name rag-ray-haystack \
  --principal-arn <your-arn> \
  --region us-east-1
```

### EKS: EBS CSI CrashLoopBackOff

If `ebs-csi-controller` pods are in CrashLoopBackOff with "sts:AssumeRoleWithWebIdentity AccessDenied":

The IAM role trust policy has the wrong OIDC ID (common when recreating clusters). Fix:

```bash
# Get current cluster's OIDC ID
OIDC_ID=$(aws eks describe-cluster --name rag-ray-haystack --region us-east-1 \
  --query 'cluster.identity.oidc.issuer' --output text | cut -d'/' -f5)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Delete and recreate IAM role with correct OIDC ID
aws iam detach-role-policy --role-name AmazonEKS_EBS_CSI_DriverRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy 2>/dev/null || true
aws iam delete-role --role-name AmazonEKS_EBS_CSI_DriverRole 2>/dev/null || true

cat << EOF > /tmp/trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/${OIDC_ID}"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.us-east-1.amazonaws.com/id/${OIDC_ID}:aud": "sts.amazonaws.com",
        "oidc.eks.us-east-1.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
      }
    }
  }]
}
EOF

aws iam create-role --role-name AmazonEKS_EBS_CSI_DriverRole \
  --assume-role-policy-document file:///tmp/trust-policy.json
aws iam attach-role-policy --role-name AmazonEKS_EBS_CSI_DriverRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

# Restart pods
kubectl -n kube-system delete pods -l app=ebs-csi-controller
```

### GPU Pods Pending

If GPU pods are stuck in Pending:

```bash
# Check if NVIDIA device plugin is running
kubectl get pods -n kube-system | grep nvidia

# Check node GPU capacity
kubectl describe node <gpu-node> | grep -A5 "Allocatable"

# Check for taints
kubectl describe node <gpu-node> | grep -A5 "Taints"
```

### Prometheus Not Scraping

```bash
# Check ServiceMonitor
kubectl get servicemonitor -n monitoring

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Then visit http://localhost:9090/targets
```

### Ray Pods Show 0/1 Ready with Restarts

This is a known cosmetic issue. The default KubeRay probes use `wget` which isn't installed in the backend container. The pods restart periodically but recover quickly.

**Verify the app still works:**
```bash
curl -s http://<FRONTEND_IP>/api/healthz
# Should return: {"status":"ok"}
```

The app is functional despite the probe restarts. To fix permanently, the backend Docker image needs `wget` installed or the rayservice template needs custom probes using `curl`.

---

## Version Compatibility

### Recommended Versions (January 2026)

| Component | Version | Notes |
|-----------|---------|-------|
| **Frontend** | `0.3.5` | **Use this version.** Version 0.3.7 has a regression where Rolling metrics don't populate and status stays "Streaming..." |
| **Backend** | `0.3.8` | Latest stable (fixes K8s token rotation for in-cluster jobs) |
| **vLLM** | `v0.6.2` | Works with RTX 4000 Ada and NVIDIA L4 GPUs |

### Frontend Version 0.3.7 Regression

Version `0.3.7` of the frontend has a bug where:
- The "Rolling metrics" widget never populates
- The status stays "Streaming..." even after the response completes
- Latency breakdown shows "—" instead of actual values

**Fix:** Use frontend version `0.3.5`:

```bash
# Update frontend image on a deployment
kubectl -n rag-app set image deployment/rag-app-rag-app-frontend \
  frontend=ghcr.io/jgdynamite10/rag-ray-frontend:0.3.5

# Or via Helm
helm upgrade rag-app deploy/helm/rag-app \
  --namespace rag-app \
  --set frontend.image.tag=0.3.5 \
  --reuse-values
```

### Backend QDRANT_URL Requirement

The backend requires the `QDRANT_URL` environment variable to use Qdrant for document storage. Without it, the backend falls back to **in-memory storage** which:
- Loses documents on pod restart
- Doesn't record `rag_k_retrieved` metrics

**Verify QDRANT_URL is set:**

```bash
kubectl -n rag-app get deployment rag-app-rag-app-backend \
  -o jsonpath='{.spec.template.spec.containers[0].env}' | jq '.[] | select(.name=="QDRANT_URL")'
```

**If missing, redeploy with:**

```bash
helm upgrade rag-app deploy/helm/rag-app \
  --namespace rag-app \
  --reuse-values
```

The base Helm chart now includes `QDRANT_URL=http://rag-app-rag-app-qdrant:6333` by default.
