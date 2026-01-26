# GCP GKE Terraform

Creates a GKE cluster with:

- 1 CPU node pool
- 1 GPU node pool (for vLLM workloads)

## Prereqs

- Google Cloud credentials configured (ADC or gcloud auth)
- Terraform >= 1.5

## Quickstart

```bash
cp terraform.tfvars.example terraform.tfvars
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
