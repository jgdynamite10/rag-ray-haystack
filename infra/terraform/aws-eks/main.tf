data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

locals {
  vpc_id = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
}

data "aws_subnets" "selected" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

# Filter out subnets in AZs not supported by EKS (e.g. us-east-1e)
data "aws_subnet" "all" {
  for_each = length(var.subnet_ids) == 0 ? toset(data.aws_subnets.selected[0].ids) : toset([])
  id       = each.value
}

locals {
  # EKS-supported AZs (excludes us-east-1e)
  eks_supported_azs = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]
  filtered_subnets = length(var.subnet_ids) == 0 ? [
    for s in data.aws_subnet.all : s.id if contains(local.eks_supported_azs, s.availability_zone)
  ] : var.subnet_ids
  subnet_ids = local.filtered_subnets
  cpu_min    = var.cpu_autoscaler_enabled ? var.cpu_autoscaler_min : var.cpu_node_count
  cpu_max    = var.cpu_autoscaler_enabled ? var.cpu_autoscaler_max : var.cpu_node_count
  gpu_min    = var.gpu_autoscaler_enabled ? var.gpu_autoscaler_min : var.gpu_node_count
  gpu_max    = var.gpu_autoscaler_enabled ? var.gpu_autoscaler_max : var.gpu_node_count
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.35.0"

  cluster_name    = var.cluster_name
  cluster_version = var.k8s_version

  vpc_id     = local.vpc_id
  subnet_ids = local.subnet_ids

  cluster_endpoint_public_access = true
  enable_irsa                    = true

  tags = var.tags

  eks_managed_node_groups = {
    cpu = {
      instance_types = [var.cpu_instance_type]
      min_size       = local.cpu_min
      max_size       = local.cpu_max
      desired_size   = var.cpu_node_count
      labels = {
        "node.kubernetes.io/role" = "cpu"
      }
    }

    gpu = {
      instance_types = [var.gpu_instance_type]
      min_size       = local.gpu_min
      max_size       = local.gpu_max
      desired_size   = var.gpu_node_count
      ami_type       = "AL2023_x86_64_NVIDIA"
      disk_size      = 100  # vLLM image is ~20GB+, needs larger disk
      labels = {
        "node.kubernetes.io/role"  = "gpu"
        "nvidia.com/gpu.present"   = "true"
      }
      taints = [{
        key    = "nvidia.com/gpu"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }
  }
}
