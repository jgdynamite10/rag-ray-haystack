locals {
  location = var.zone != "" ? var.zone : var.region
  cpu_min  = var.cpu_autoscaler_enabled ? var.cpu_autoscaler_min : var.cpu_node_count
  cpu_max  = var.cpu_autoscaler_enabled ? var.cpu_autoscaler_max : var.cpu_node_count
  gpu_min  = var.gpu_autoscaler_enabled ? var.gpu_autoscaler_min : var.gpu_node_count
  gpu_max  = var.gpu_autoscaler_enabled ? var.gpu_autoscaler_max : var.gpu_node_count
}

resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = local.location

  min_master_version       = var.k8s_version
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network
  subnetwork = var.subnetwork

  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {}

  deletion_protection = false
}

resource "google_container_node_pool" "cpu" {
  name       = "${var.cluster_name}-cpu"
  location   = local.location
  cluster    = google_container_cluster.primary.name
  node_count = var.cpu_node_count

  dynamic "autoscaling" {
    for_each = var.cpu_autoscaler_enabled ? [1] : []
    content {
      min_node_count = local.cpu_min
      max_node_count = local.cpu_max
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.cpu_machine_type
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    metadata = {
      disable-legacy-endpoints = "true"
    }
    labels = {
      "node.kubernetes.io/role" = "cpu"
    }
  }
}

resource "google_container_node_pool" "gpu" {
  name       = "${var.cluster_name}-gpu"
  location   = local.location
  cluster    = google_container_cluster.primary.name
  node_count = var.gpu_node_count

  dynamic "autoscaling" {
    for_each = var.gpu_autoscaler_enabled ? [1] : []
    content {
      min_node_count = local.gpu_min
      max_node_count = local.gpu_max
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.gpu_machine_type
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    metadata = {
      disable-legacy-endpoints = "true"
    }
    guest_accelerator {
      type  = var.gpu_type
      count = var.gpu_count
    }
    labels = {
      "node.kubernetes.io/role" = "gpu"
      "nvidia.com/gpu.present"  = "true"
    }
    taint {
      key    = "nvidia.com/gpu"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }
}
