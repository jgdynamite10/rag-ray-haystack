locals {
  kubeconfig = {
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = module.eks.cluster_name
      cluster = {
        server                      = module.eks.cluster_endpoint
        "certificate-authority-data" = module.eks.cluster_certificate_authority_data
      }
    }]
    contexts = [{
      name = module.eks.cluster_name
      context = {
        cluster = module.eks.cluster_name
        user    = "aws"
      }
    }]
    "current-context" = module.eks.cluster_name
    users = [{
      name = "aws"
      user = {
        exec = {
          apiVersion = "client.authentication.k8s.io/v1beta1"
          command    = "aws"
          args = [
            "eks",
            "get-token",
            "--cluster-name",
            module.eks.cluster_name,
            "--region",
            var.region
          ]
        }
      }
    }]
  }
}

output "kubeconfig" {
  description = "Raw kubeconfig content for the cluster."
  value       = yamlencode(local.kubeconfig)
  sensitive   = true
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint."
  value       = module.eks.cluster_endpoint
}

output "gpu_node_label" {
  description = "GPU node label used for scheduling."
  value       = "nvidia.com/gpu.present=true"
}

output "gpu_node_taint" {
  description = "GPU node taint used for scheduling."
  value       = "nvidia.com/gpu=true:NoSchedule"
}
