# Quickstart

## One-command flow

```bash
cp infra/terraform/akamai-lke/terraform.tfvars.example infra/terraform/akamai-lke/terraform.tfvars
make deploy PROVIDER=akamai-lke ENV=dev
```

This runs:

1. `terraform apply` in `infra/terraform/<provider>`
2. `make kubeconfig` (writes `~/.kube/<provider>-<env>-config.yaml`)
3. `helm upgrade --install` with base + overlay values

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
