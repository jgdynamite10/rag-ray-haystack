provider "linode" {
  token = var.linode_token
}

resource "linode_lke_cluster" "rag" {
  label       = var.cluster_label
  region      = var.region
  k8s_version = var.k8s_version
  tags        = ["rag-ray-haystack"]

  pool {
    type  = var.cpu_node_type
    count = var.cpu_node_count

    dynamic "autoscaler" {
      for_each = var.cpu_autoscaler_enabled ? [1] : []
      content {
        min = var.cpu_autoscaler_min
        max = var.cpu_autoscaler_max
      }
    }
  }

  pool {
    type  = var.gpu_node_type
    count = var.gpu_node_count

    dynamic "autoscaler" {
      for_each = var.gpu_autoscaler_enabled ? [1] : []
      content {
        min = var.gpu_autoscaler_min
        max = var.gpu_autoscaler_max
      }
    }
  }
}
