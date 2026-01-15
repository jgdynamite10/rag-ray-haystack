Infrastructure modules live under `infra/terraform/<provider>`.

Each provider directory should:

- include a `terraform.tfvars.example` with dev defaults
- document how to copy it to `terraform.tfvars`
- expose standard outputs:
  - `kubeconfig` (raw kubeconfig content)
  - `cluster_label`/`cluster_name`
  - GPU scheduling conventions (label + taint)
- work with Makefile targets:
  - `make tf-apply PROVIDER=<provider>`
  - `make tf-destroy PROVIDER=<provider>`
  - `make kubeconfig PROVIDER=<provider> ENV=<env>`
- write kubeconfig to `~/.kube/<provider>-<env>-config.yaml`

See each provider README under `infra/terraform/<provider>/README.md` for details.
