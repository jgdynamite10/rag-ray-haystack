provider "linode" {
  token = var.linode_token
}

resource "linode_lke_cluster" "rag" {
  label       = var.cluster_label
  region      = var.region
  k8s_version = var.k8s_version
  tags        = ["rag-ray-haystack"]
}

resource "linode_lke_node_pool" "cpu" {
  cluster_id  = linode_lke_cluster.rag.id
  type        = var.cpu_node_type
  node_count  = var.cpu_node_count
  tags        = ["rag-ray-haystack", "cpu"]

  dynamic "autoscaler" {
    for_each = var.cpu_autoscaler_enabled ? [1] : []
    content {
      min = var.cpu_autoscaler_min
      max = var.cpu_autoscaler_max
    }
  }
}

resource "linode_lke_node_pool" "gpu" {
  cluster_id  = linode_lke_cluster.rag.id
  type        = var.gpu_node_type
  node_count  = var.gpu_node_count
  tags        = ["rag-ray-haystack", "gpu"]

  labels = {
    (var.gpu_label_key) = var.gpu_label_value
  }

  taints = [
    {
      key    = var.gpu_taint_key
      value  = "true"
      effect = var.gpu_taint_effect
    }
  ]

  dynamic "autoscaler" {
    for_each = var.gpu_autoscaler_enabled ? [1] : []
    content {
      min = var.gpu_autoscaler_min
      max = var.gpu_autoscaler_max
    }
  }
}
