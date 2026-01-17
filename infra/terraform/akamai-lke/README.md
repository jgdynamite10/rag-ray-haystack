# Akamai LKE Terraform

Creates a Linode Kubernetes Engine (LKE) cluster with:

- 1 CPU node pool
- 1 GPU node pool (for immediate vLLM testing)

## Usage

```bash
export TF_VAR_linode_token="..."
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

## Notes

- Discover GPU node types in your region:

```bash
curl -H "Authorization: Bearer ${TF_VAR_linode_token}" \
  "https://api.linode.com/v4/linode/types" | grep -i gpu
```

If you have `jq` installed, you can filter for GPU types:

```bash
curl -H "Authorization: Bearer ${TF_VAR_linode_token}" \
  "https://api.linode.com/v4/linode/types" | jq -r '.data[] | select(.class=="gpu") | .id'
```

- Set `gpu_node_type` to a type available in your region.
- GPU scheduling conventions are `accelerator=nvidia` and `nvidia.com/gpu=true:NoSchedule`.
  Apply these via your node pool config or cluster tooling if your provider
  does not support labels/taints in Terraform.

Apply labels/taints after cluster creation if needed:

```bash
./scripts/label_gpu_nodes.sh
```

Validate labels/taints after cluster creation:

```bash
kubectl describe node | grep -A5 -i "Taints"
kubectl describe node | grep -A5 -i "Labels"
```
