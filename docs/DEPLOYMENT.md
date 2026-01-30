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

### Step 6: Install KubeRay Operator

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

### Step 7: Deploy RAG Application

```bash
helm upgrade --install rag-app ./deploy/helm/rag-app \
  --namespace default \
  --set backend.image.tag=0.3.7 \
  --set frontend.image.tag=0.3.7
```

### Step 8: Get External IPs

```bash
# Prometheus (for Central Grafana datasource)
kubectl get svc -n monitoring prometheus-kube-prometheus-prometheus

# RAG App (for benchmarking)
kubectl get svc rag-app-frontend
```

### Step 9: Add to Central Grafana

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
helm upgrade --install rag-app ./deploy/helm/rag-app \
  --namespace default \
  --set backend.image.tag=0.3.7 \
  --set frontend.image.tag=0.3.7
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
helm upgrade --install rag-app ./deploy/helm/rag-app \
  --namespace default \
  --set backend.image.tag=0.3.7 \
  --set frontend.image.tag=0.3.7
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
