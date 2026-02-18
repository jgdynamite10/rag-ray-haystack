.PHONY: terraform-apply terraform-destroy tf-apply tf-destroy kubeconfig helm-apply helm-destroy deploy destroy verify bench label-gpu install-kuberay fix-gpu install-monitoring install-dcgm

PROVIDER ?= akamai-lke
ENV ?= dev
RELEASE ?= rag-app
NAMESPACE ?= rag-app
IMAGE_REGISTRY ?=
IMAGE_TAG ?=
FRONTEND_TAG ?= $(IMAGE_TAG)

TERRAFORM_DIR := infra/terraform/$(PROVIDER)
BASE_VALUES := deploy/helm/rag-app/values.yaml
OVERLAY_VALUES := deploy/overlays/$(PROVIDER)/$(ENV)/values.yaml
KUBECONFIG_PATH ?= $(HOME)/.kube/$(PROVIDER)-$(ENV)-config.yaml

define IMAGE_OVERRIDES
$(if $(IMAGE_REGISTRY),--set backend.image.repository=$(IMAGE_REGISTRY)/rag-ray-backend,) \
$(if $(IMAGE_REGISTRY),--set frontend.image.repository=$(IMAGE_REGISTRY)/rag-ray-frontend,) \
$(if $(IMAGE_TAG),--set backend.image.tag=$(IMAGE_TAG),) \
$(if $(FRONTEND_TAG),--set frontend.image.tag=$(FRONTEND_TAG),)
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

install-monitoring:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
	helm repo update
	KUBECONFIG=$(KUBECONFIG_PATH) helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
		--namespace monitoring --create-namespace \
		--set prometheus.prometheusSpec.externalLabels.provider=$(PROVIDER) \
		--set prometheus.service.type=LoadBalancer
	KUBECONFIG=$(KUBECONFIG_PATH) kubectl apply -f deploy/monitoring/pushgateway.yaml

install-dcgm:
	@echo "Installing DCGM exporter for $(PROVIDER)"
	@if [ "$(PROVIDER)" = "gcp-gke" ]; then \
		echo "GKE: Using managed DCGM exporter — applying bridge Service + ServiceMonitor"; \
		KUBECONFIG=$(KUBECONFIG_PATH) kubectl apply -f deploy/monitoring/gke-dcgm-bridge.yaml; \
	else \
		echo "Installing DCGM exporter via Helm"; \
		helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts || true; \
		helm repo update; \
		KUBECONFIG=$(KUBECONFIG_PATH) helm upgrade --install dcgm-exporter gpu-helm-charts/dcgm-exporter \
			--namespace monitoring \
			-f deploy/helm/dcgm-values.yaml; \
	fi
	@echo "Verifying DCGM exporter..."
	@sleep 10
	KUBECONFIG=$(KUBECONFIG_PATH) kubectl get pods -n monitoring -l app.kubernetes.io/name=dcgm-exporter 2>/dev/null || \
		KUBECONFIG=$(KUBECONFIG_PATH) kubectl get pods -n gke-managed-system 2>/dev/null | grep dcgm
