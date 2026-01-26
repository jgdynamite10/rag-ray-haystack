locals {
  kubeconfig = {
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = google_container_cluster.primary.name
      cluster = {
        server                      = "https://${google_container_cluster.primary.endpoint}"
        "certificate-authority-data" = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
      }
    }]
    contexts = [{
      name = google_container_cluster.primary.name
      context = {
        cluster = google_container_cluster.primary.name
        user    = "gke"
      }
    }]
    "current-context" = google_container_cluster.primary.name
    users = [{
      name = "gke"
      user = {
        exec = {
          apiVersion         = "client.authentication.k8s.io/v1beta1"
          command            = "gke-gcloud-auth-plugin"
          provideClusterInfo = true
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
  description = "GKE cluster name."
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint."
  value       = google_container_cluster.primary.endpoint
}

output "gpu_node_label" {
  description = "GPU node label used for scheduling."
  value       = "nvidia.com/gpu.present=true"
}

output "gpu_node_taint" {
  description = "GPU node taint used for scheduling."
  value       = "nvidia.com/gpu=true:NoSchedule"
}
