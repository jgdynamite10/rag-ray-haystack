variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-2"
}

variable "aws_profile" {
  description = "Optional AWS CLI profile name."
  type        = string
  default     = null
  nullable    = true
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "rag-ray-haystack"
}

variable "k8s_version" {
  description = "Kubernetes version for EKS."
  type        = string
  default     = "1.29"
}

variable "vpc_id" {
  description = "Optional VPC ID. If empty, uses default VPC."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Optional subnet IDs. If empty, uses all subnets in the selected VPC."
  type        = list(string)
  default     = []
}

variable "cpu_instance_type" {
  description = "Instance type for CPU node group."
  type        = string
  default     = "t3.medium"
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

variable "gpu_instance_type" {
  description = "Instance type for GPU node group."
  type        = string
  default     = "g6.xlarge"
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

variable "node_availability_zone" {
  description = "Pin all node groups to a single AZ for consistent intra-zone latency. Set to empty string to allow multi-AZ spread."
  type        = string
  default     = "us-east-2a"
}

variable "tags" {
  description = "Optional tags applied to AWS resources."
  type        = map(string)
  default     = {}
}
