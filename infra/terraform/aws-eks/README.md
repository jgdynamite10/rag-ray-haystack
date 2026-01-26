# AWS EKS (Terraform)

This module provisions an EKS cluster with one CPU node group and one GPU node
group. It defaults to the account's default VPC and all subnets in that VPC.

## Prereqs

- AWS CLI installed (`brew install awscli`)
- AWS credentials configured (`aws configure`)
- Terraform >= 1.5
- IAM user with permissions: `AmazonEKSClusterPolicy`, `AmazonVPCFullAccess`,
  `IAMFullAccess`, `AmazonEC2FullAccess`, `CloudWatchLogsFullAccess`
- GPU quota: Request "Running On-Demand G and VT instances" >= 4 vCPUs in your
  region via AWS Service Quotas console

## Quickstart

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars if needed (region, instance types, etc.)
terraform init
terraform apply
```

## Configure kubectl access

After `terraform apply` completes:

```bash
aws eks update-kubeconfig --region us-east-1 --name rag-ray-haystack \
  --kubeconfig ~/.kube/aws-eks-dev-config.yaml
export KUBECONFIG=~/.kube/aws-eks-dev-config.yaml
```

### Grant IAM user access to the cluster

EKS uses access entries for authorization. If you get `401 Unauthorized` when
running `kubectl get nodes`, add your IAM user as a cluster admin:

```bash
# Get your IAM user ARN
aws sts get-caller-identity

# Create access entry for your IAM user
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

See [EKS Access Entries documentation](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
for more details.

### Verify cluster access

```bash
kubectl get nodes
```

You should see CPU and GPU nodes in `Ready` status.

## GPU scheduling conventions

- Label: `nvidia.com/gpu.present=true`
- Taint: `nvidia.com/gpu=true:NoSchedule`

These match the vLLM `nodeSelector` and tolerations in the Helm chart.

## Deploy the app

After cluster access is verified:

```bash
# Install KubeRay operator
KUBECONFIG_PATH="$KUBECONFIG" make install-kuberay PROVIDER=aws-eks ENV=dev

# Install GPU Operator + Node Feature Discovery
helm repo add nvidia-gpu https://nvidia.github.io/gpu-operator
helm repo add nfd https://kubernetes-sigs.github.io/node-feature-discovery/charts
helm repo update
helm upgrade --install gpu-operator nvidia-gpu/gpu-operator \
  --namespace gpu-operator --create-namespace
helm upgrade --install node-feature-discovery nfd/node-feature-discovery \
  --namespace node-feature-discovery --create-namespace

# Deploy app
export IMAGE_REGISTRY=ghcr.io/<your-registry>
export IMAGE_TAG=<your-tag>
make deploy PROVIDER=aws-eks ENV=dev IMAGE_REGISTRY=$IMAGE_REGISTRY IMAGE_TAG=$IMAGE_TAG

# Verify
make verify PROVIDER=aws-eks ENV=dev NAMESPACE=rag-app RELEASE=rag-app
```

## Notes

- If your account has no default VPC, set `vpc_id` and `subnet_ids` in
  `terraform.tfvars`.
- EKS does not support all availability zones (e.g., `us-east-1e`). The module
  automatically filters out unsupported AZs.
- GPU nodes use `AL2023_x86_64_NVIDIA` AMI which supports Kubernetes 1.33+.
- Update `k8s_version` and instance types to match your region availability.

## Troubleshooting

### 401 Unauthorized / credentials error

Run the access entry commands above to grant your IAM user cluster access.

### GPU quota exceeded

Request a quota increase for "Running On-Demand G and VT instances" in the
AWS Service Quotas console. GPU instances (g4dn, g5, g6) require at least 4
vCPUs per instance.

### Unsupported availability zone

The module filters out `us-east-1e` automatically. If you hit other AZ issues,
specify `subnet_ids` explicitly in `terraform.tfvars`.
