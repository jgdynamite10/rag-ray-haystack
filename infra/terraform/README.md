Infrastructure modules live under `infra/terraform/<provider>`.

Each provider directory should expose a `kubeconfig` output used by the
Makefile target `make kubeconfig`.
