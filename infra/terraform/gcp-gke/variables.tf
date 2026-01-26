variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region (or default region for zonal clusters)."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Optional GCP zone for a zonal cluster. Leave empty for regional."
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "GKE cluster name."
  type        = string
  default     = "rag-ray-haystack"
}

variable "k8s_version" {
  description = "Kubernetes version for GKE."
  type        = string
  default     = "1.29"
}

variable "network" {
  description = "VPC network name."
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Subnetwork name."
  type        = string
  default     = "default"
}

variable "cpu_machine_type" {
  description = "Machine type for CPU node pool."
  type        = string
  default     = "e2-standard-4"
}

variable "cpu_node_count" {
  description = "Desired CPU node count."
  type        = number
  default     = 2
}

variable "cpu_autoscaler_enabled" {
  description = "Enable autoscaling for CPU nodes."
  type        = bool
  default     = false
}

variable "cpu_autoscaler_min" {
  description = "Minimum CPU node count."
  type        = number
  default     = 2
}

variable "cpu_autoscaler_max" {
  description = "Maximum CPU node count."
  type        = number
  default     = 4
}

variable "gpu_machine_type" {
  description = "Machine type for GPU node pool."
  type        = string
  default     = "n1-standard-8"
}

variable "gpu_type" {
  description = "GPU accelerator type."
  type        = string
  default     = "nvidia-tesla-t4"
}

variable "gpu_count" {
  description = "GPU count per node."
  type        = number
  default     = 1
}

variable "gpu_node_count" {
  description = "Desired GPU node count."
  type        = number
  default     = 1
}

variable "gpu_autoscaler_enabled" {
  description = "Enable autoscaling for GPU nodes."
  type        = bool
  default     = false
}

variable "gpu_autoscaler_min" {
  description = "Minimum GPU node count."
  type        = number
  default     = 1
}

variable "gpu_autoscaler_max" {
  description = "Maximum GPU node count."
  type        = number
  default     = 2
}
