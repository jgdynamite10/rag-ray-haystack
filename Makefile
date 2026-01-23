.PHONY: terraform-apply terraform-destroy tf-apply tf-destroy kubeconfig helm-apply helm-destroy deploy destroy verify bench label-gpu install-kuberay fix-gpu

PROVIDER ?= akamai-lke
ENV ?= dev
RELEASE ?= rag-app
NAMESPACE ?= rag-app
IMAGE_REGISTRY ?=
IMAGE_TAG ?=

TERRAFORM_DIR := infra/terraform/$(PROVIDER)
BASE_VALUES := deploy/helm/rag-app/values.yaml
OVERLAY_VALUES := deploy/overlays/$(PROVIDER)/$(ENV)/values.yaml
KUBECONFIG_PATH ?= $(HOME)/.kube/$(PROVIDER)-$(ENV)-config.yaml

define IMAGE_OVERRIDES
$(if $(IMAGE_REGISTRY),--set backend.image.repository=$(IMAGE_REGISTRY)/rag-ray-backend,) \
$(if $(IMAGE_REGISTRY),--set frontend.image.repository=$(IMAGE_REGISTRY)/rag-ray-frontend,) \
$(if $(IMAGE_TAG),--set backend.image.tag=$(IMAGE_TAG),) \
$(if $(IMAGE_TAG),--set frontend.image.tag=$(IMAGE_TAG),)
endef

terraform-apply:
	@echo "Applying Terraform in $(TERRAFORM_DIR)"
	cd $(TERRAFORM_DIR) && terraform init && \
	if [ -f terraform.tfvars ]; then \
		terraform apply -auto-approve -var-file=terraform.tfvars; \
	else \
		terraform apply -auto-approve; \
	fi

tf-apply: terraform-apply

terraform-destroy:
	@echo "Destroying Terraform in $(TERRAFORM_DIR)"
	cd $(TERRAFORM_DIR) && terraform init && \
	if [ -f terraform.tfvars ]; then \
		terraform destroy -auto-approve -var-file=terraform.tfvars; \
	else \
		terraform destroy -auto-approve; \
	fi

tf-destroy: terraform-destroy

kubeconfig:
	@echo "Writing kubeconfig to $(KUBECONFIG_PATH)"
	@mkdir -p $(dir $(KUBECONFIG_PATH))
	cd $(TERRAFORM_DIR) && terraform output -raw kubeconfig | \
		( base64 --decode 2>/dev/null || base64 -D ) > $(KUBECONFIG_PATH)
	@echo "Run: export KUBECONFIG=$(KUBECONFIG_PATH)"

helm-apply:
	@echo "Deploying Helm chart $(RELEASE) to namespace $(NAMESPACE)"
	KUBECONFIG=$(KUBECONFIG_PATH) helm -n $(NAMESPACE) upgrade --install $(RELEASE) deploy/helm/rag-app \
		--create-namespace \
		-f $(BASE_VALUES) \
		-f $(OVERLAY_VALUES) \
		$(IMAGE_OVERRIDES)

helm-destroy:
	@echo "Uninstalling Helm release $(RELEASE) from $(NAMESPACE)"
	KUBECONFIG=$(KUBECONFIG_PATH) helm -n $(NAMESPACE) uninstall $(RELEASE)

deploy: terraform-apply kubeconfig helm-apply
	@if [ "$(PROVIDER)" = "akamai-lke" ]; then \
		KUBECONFIG_PATH=$(KUBECONFIG_PATH) ./scripts/fix_gpu.sh; \
	fi

destroy: helm-destroy terraform-destroy

verify:
	KUBECONFIG=$(KUBECONFIG_PATH) ./scripts/verify.sh --namespace $(NAMESPACE) --release $(RELEASE)

bench:
	python scripts/benchmark/stream_bench.py --url http://localhost:8000/query/stream

label-gpu:
	KUBECONFIG=$(KUBECONFIG_PATH) ./scripts/label_gpu_nodes.sh

install-kuberay:
	helm repo add kuberay https://ray-project.github.io/kuberay-helm/
	helm repo update
	KUBECONFIG=$(KUBECONFIG_PATH) helm upgrade --install kuberay-operator kuberay/kuberay-operator \
		--namespace kuberay-system --create-namespace \
		--values deploy/kuberay/operator-values.yaml

fix-gpu:
	KUBECONFIG_PATH=$(KUBECONFIG_PATH) ./scripts/fix_gpu.sh
