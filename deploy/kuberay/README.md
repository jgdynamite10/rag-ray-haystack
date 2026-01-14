# KubeRay Operator

Install the operator with Helm:

```bash
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update
helm upgrade --install kuberay-operator kuberay/kuberay-operator \
  --namespace kuberay-system --create-namespace \
  --values deploy/kuberay/operator-values.yaml
```

Apply the RayService:

```bash
kubectl apply -f deploy/kuberay/rayservice.yaml
```
