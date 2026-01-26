# AWS EKS (Terraform)

This module provisions an EKS cluster with one CPU node group and one GPU node
group. It defaults to the account's default VPC and all subnets in that VPC.

## Prereqs

- AWS credentials configured (env vars or `aws configure`)
- Terraform >= 1.5

## Quickstart

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

Write kubeconfig:

```bash
make kubeconfig PROVIDER=aws-eks ENV=dev
export KUBECONFIG=~/.kube/aws-eks-dev-config.yaml
```

## GPU scheduling conventions

- Label: `nvidia.com/gpu.present=true`
- Taint: `nvidia.com/gpu=true:NoSchedule`

These match the vLLM `nodeSelector` and tolerations in the Helm chart.

## Notes

- If your account has no default VPC, set `vpc_id` and `subnet_ids` in
  `terraform.tfvars`.
- Update `k8s_version` and instance types to match your region availability.
