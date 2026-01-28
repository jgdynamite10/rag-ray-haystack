# Central Grafana VM - Terraform Deployment

This Terraform configuration deploys a Grafana VM on Akamai Cloud (Linode) for cross-cluster monitoring.

## Prerequisites

1. [Terraform](https://www.terraform.io/downloads) >= 1.0.0
2. [Linode API Token](https://cloud.linode.com/profile/tokens)
3. Prometheus deployed in your Kubernetes clusters

## Quick Start

```bash
cd deploy/monitoring/terraform

# 1. Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 2. Initialize Terraform
terraform init

# 3. Review the plan
terraform plan

# 4. Deploy
terraform apply

# 5. Access Grafana
# URL will be shown in outputs
```

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `linode_token` | Linode API token | (required) |
| `root_password` | VM root password | (required) |
| `ssh_keys` | SSH public keys | `[]` |
| `region` | Linode region | `us-ord` |
| `instance_type` | VM size | `g6-nanode-1` |
| `grafana_admin_password` | Grafana login password | `changeme123` |
| `prometheus_lke_url` | LKE Prometheus URL | `""` |
| `prometheus_eks_url` | EKS Prometheus URL | `""` |
| `prometheus_gke_url` | GKE Prometheus URL | `""` |

## Outputs

| Output | Description |
|--------|-------------|
| `grafana_ip` | Public IP of the Grafana VM |
| `grafana_url` | URL to access Grafana |
| `ssh_command` | SSH command to connect |

## What Gets Deployed

1. **Linode Instance** - Ubuntu 22.04 VM with Docker
2. **Linode Firewall** - Only ports 22 (SSH) and 3000 (Grafana) open
3. **Grafana Container** - Auto-started with Docker Compose
4. **Datasources** - Pre-configured for LKE, EKS, GKE Prometheus

## Architecture

```
┌─────────────────────────────────────────┐
│        Central Grafana VM               │
│        (Linode, us-ord)                 │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │         Grafana:3000              │  │
│  │   ┌─────────────────────────────┐ │  │
│  │   │ Datasources:                │ │  │
│  │   │ - Prometheus-LKE            │ │  │
│  │   │ - Prometheus-EKS            │ │  │
│  │   │ - Prometheus-GKE            │ │  │
│  │   └─────────────────────────────┘ │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
         │           │           │
         ▼           ▼           ▼
    ┌─────────┐ ┌─────────┐ ┌─────────┐
    │   LKE   │ │   EKS   │ │   GKE   │
    │Prometheus│ │Prometheus│ │Prometheus│
    │  :9090  │ │  :9090  │ │  :9090  │
    └─────────┘ └─────────┘ └─────────┘
```

## Post-Deployment

### Import Dashboards

1. SSH into the VM:
   ```bash
   ssh root@<grafana-ip>
   ```

2. Download dashboards from the repo:
   ```bash
   cd /opt/rag-monitoring
   mkdir -p dashboards
   curl -o dashboards/rag-overview.json https://raw.githubusercontent.com/jgdynamite10/rag-ray-haystack/main/grafana/dashboards/rag-overview.json
   curl -o dashboards/provider-comparison.json https://raw.githubusercontent.com/jgdynamite10/rag-ray-haystack/main/grafana/dashboards/provider-comparison.json
   ```

3. Import via Grafana UI (Dashboards → Import)

### Update Prometheus URLs

If you need to add EKS/GKE later:

```bash
ssh root@<grafana-ip>
cd /opt/rag-monitoring
nano .env  # Update PROMETHEUS_EKS_URL, PROMETHEUS_GKE_URL
docker-compose down && docker-compose up -d
```

Or re-run Terraform with updated variables.

## Destroy

```bash
terraform destroy
```

## Troubleshooting

### VM Not Accessible

1. Check firewall is attached:
   ```bash
   linode-cli firewalls list
   ```

2. Check VM is running:
   ```bash
   linode-cli linodes list
   ```

### Grafana Not Starting

1. SSH into VM and check logs:
   ```bash
   ssh root@<ip>
   cat /var/log/grafana-setup.log
   docker-compose logs
   ```

2. Check Docker is running:
   ```bash
   systemctl status docker
   ```

### Datasource Connection Failed

1. Verify Prometheus is accessible from the VM:
   ```bash
   ssh root@<grafana-ip>
   curl http://<prometheus-ip>:9090/api/v1/status/config
   ```

2. Check firewall allows Prometheus port (9090)
