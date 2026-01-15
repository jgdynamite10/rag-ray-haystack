output "cluster_name" {
  description = "LKE cluster name."
  value       = linode_lke_cluster.rag.label
}

output "kubeconfig" {
  description = "Raw kubeconfig for the cluster."
  value       = linode_lke_cluster.rag.kubeconfig
  sensitive   = true
}

output "gpu_label" {
  description = "GPU node label applied by Terraform."
  value       = "${var.gpu_label_key}=${var.gpu_label_value}"
}

output "gpu_taint" {
  description = "GPU node taint applied by Terraform."
  value       = "${var.gpu_taint_key}=true:${var.gpu_taint_effect}"
}
