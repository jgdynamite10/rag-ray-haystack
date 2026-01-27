# GCP GKE Terraform

Creates a GKE cluster with:

- 1 CPU node pool
- 1 GPU node pool (for vLLM workloads)

## Prereqs

- Google Cloud credentials configured (`gcloud auth login` + `gcloud auth application-default login`)
- Terraform >= 1.5
- Billing account linked to project

## GCP Project Setup

If you need a new project:

```bash
# Create project (skip if reusing existing)
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

## Quickstart

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set your project_id
terraform init
terraform apply
```

Write kubeconfig:

```bash
make kubeconfig PROVIDER=gcp-gke ENV=dev
export KUBECONFIG=~/.kube/gcp-gke-dev-config.yaml
```

## GPU scheduling conventions

- Label: `nvidia.com/gpu.present=true`
- Taint: `nvidia.com/gpu=true:NoSchedule`

These match the vLLM `nodeSelector` and tolerations in the Helm chart.

## Notes

- Set `project_id`, `region`, and GPU types in `terraform.tfvars`.
- If using a zonal cluster, set `zone` and leave `region` as the default provider region.
- Default GPU type is `nvidia-l4` on `g2-standard-8` machines (comparable to AWS g6/Akamai RTX 4000 Ada).
- For other GPU types, check availability: `gcloud compute accelerator-types list --filter="zone:us-central1-a"`
