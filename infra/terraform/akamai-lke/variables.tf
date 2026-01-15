variable "cluster_label" {
  description = "LKE cluster label."
  type        = string
  default     = "rag-ray-haystack"
}

variable "region" {
  description = "Akamai LKE region."
  type        = string
  default     = "us-ord"
}

variable "k8s_version" {
  description = "Kubernetes version for LKE."
  type        = string
  default     = "1.29"
}

variable "cpu_node_type" {
  description = "Linode CPU node type (e.g., g6-standard-2)."
  type        = string
  default     = "g6-standard-2"
}

variable "cpu_node_count" {
  description = "CPU node count."
  type        = number
  default     = 2
}

variable "cpu_autoscaler_enabled" {
  description = "Enable autoscaler for CPU node pool."
  type        = bool
  default     = false
}

variable "cpu_autoscaler_min" {
  description = "Minimum CPU nodes when autoscaling."
  type        = number
  default     = 2
}

variable "cpu_autoscaler_max" {
  description = "Maximum CPU nodes when autoscaling."
  type        = number
  default     = 4
}

variable "gpu_node_type" {
  description = "Linode GPU node type (example; verify availability)."
  type        = string
  default     = "g6-gpu-rtx6000-1"
}

variable "gpu_node_count" {
  description = "GPU node count."
  type        = number
  default     = 1
}

variable "gpu_autoscaler_enabled" {
  description = "Enable autoscaler for GPU node pool."
  type        = bool
  default     = false
}

variable "gpu_autoscaler_min" {
  description = "Minimum GPU nodes when autoscaling."
  type        = number
  default     = 1
}

variable "gpu_autoscaler_max" {
  description = "Maximum GPU nodes when autoscaling."
  type        = number
  default     = 2
}

variable "gpu_label_key" {
  description = "Label key applied to GPU nodes."
  type        = string
  default     = "accelerator"
}

variable "gpu_label_value" {
  description = "Label value applied to GPU nodes."
  type        = string
  default     = "nvidia"
}

variable "gpu_taint_key" {
  description = "Taint key applied to GPU nodes."
  type        = string
  default     = "nvidia.com/gpu"
}

variable "gpu_taint_effect" {
  description = "Taint effect applied to GPU nodes."
  type        = string
  default     = "NoSchedule"
}

variable "linode_token" {
  description = "Linode API token. Prefer TF_VAR_linode_token."
  type        = string
  sensitive   = true
}
