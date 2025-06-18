# Infrastructure Setup Guide - n8n Scalable Deployment Platform

## Overview
This document outlines the comprehensive infrastructure setup for the n8n Scalable Deployment Platform, covering multi-cloud deployments with Terraform automation, Kubernetes orchestration, and modern DevOps practices.

## Prerequisites
- **Cloud Accounts**: AWS and/or Azure account with appropriate permissions
- **Local Tools**: kubectl, helm, terraform, docker
- **Domain** (optional): For custom SSL certificates and DNS
- **Git**: For version control and GitOps workflows

## Architecture Overview

### Multi-Cloud Support
```
┌─────────────────────────────────────────────────────────────┐
│                    Load Balancer                            │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                  n8n Main Pods (2)                         │
│  - UI/API Server                                            │
│  - Webhook Handler                                          │
│  - Job Dispatcher (BullMQ)                                  │
│  - Scheduler                                                │
└─────────────────────┬───────────────────────────────────────┘
                      │
                ┌─────▼─────┐
                │   Redis   │
                │ Cluster   │
                │(Queue +   │
                │ Streams)  │
                └─────┬─────┘
                      │
    ┌─────────────────┼─────────────────┐
    │                 │                 │
┌───▼───┐         ┌───▼───┐         ┌───▼───┐
│ n8n   │         │ n8n   │         │ n8n   │
│Worker │   ...   │Worker │   ...   │Worker │
│ Pod   │         │ Pod   │         │ Pod   │
│(HPA)  │         │(2-20) │         │(Auto) │
└───────┘         └───────┘         └───────┘
```

## Phase 1: AWS EKS Deployment

### 1.1 Prerequisites Setup

#### Install Required Tools
```bash
# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

#### Configure AWS Credentials
```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, Region, and Output format
```

### 1.2 EKS Infrastructure Deployment

#### Navigate to AWS EKS Directory
```bash
cd n8n/aws-eks/terraform
```

#### Configure Terraform Variables
```hcl
# terraform.tfvars
aws_region = "us-west-2"
aws_profile = "default"
environment = "production"
cluster_name = "n8n-scalable-prod"

# VPC Configuration
vpc_cidr = "10.0.0.0/16"
private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
public_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

# EKS Configuration
kubernetes_version = "1.28"
cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

# Database Configuration
postgres_instance_class = "db.t3.medium"

# Redis Configuration
redis_node_type = "cache.t3.medium"

# Tags
tags = {
  Project = "n8n-scalable"
  Environment = "production"
  Owner = "devops-team"
}
```

#### Deploy Infrastructure
```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan -var-file="terraform.tfvars"

# Apply configuration
terraform apply -var-file="terraform.tfvars"

# Note: This creates:
# - VPC with public/private subnets
# - EKS cluster with managed node groups
# - ElastiCache Redis cluster
# - RDS PostgreSQL database
# - IAM roles and policies
# - Security groups
# - Secrets Manager entries
```

#### Update Kubeconfig
```bash
aws eks update-kubeconfig --region us-west-2 --name n8n-scalable-prod
```

### 1.3 Deploy n8n Application

#### Install Helm Chart
```bash
cd ../helm

# Add required Helm repositories
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Install n8n with AWS-optimized values
helm upgrade --install n8n-scalable ./charts/n8n-scalable \
  --namespace n8n \
  --create-namespace \
  --values values-aws.yaml \
  --wait \
  --timeout 10m
```

#### Verify Deployment
```bash
# Check pod status
kubectl get pods -n n8n

# Check services
kubectl get svc -n n8n

# Check ingress
kubectl get ingress -n n8n

# View logs
kubectl logs -n n8n -l app.kubernetes.io/name=n8n-scalable
```

## Phase 2: Azure AKS Deployment

### 2.1 Prerequisites Setup

#### Install Azure CLI
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

#### Login to Azure
```bash
az login
az account set --subscription "your-subscription-id"
```

### 2.2 AKS Infrastructure Deployment

#### Navigate to Azure AKS Directory
```bash
cd n8n/azure-aks/terraform
```

#### Configure Terraform Variables
```hcl
# terraform.tfvars
azure_subscription_id = "your-subscription-id"
azure_tenant_id = "your-tenant-id"
location = "East US"
environment = "production"
cluster_name = "n8n-scalable-prod"

# Resource Group
resource_group_name = "rg-n8n-scalable-prod"

# AKS Configuration
kubernetes_version = "1.28"
node_count = 3
node_vm_size = "Standard_D2s_v3"

# Database Configuration
postgres_sku_name = "GP_Gen5_2"
postgres_storage_mb = 51200

# Redis Configuration
redis_sku_name = "Standard"
redis_family = "C"
redis_capacity = 1

# Tags
tags = {
  Project = "n8n-scalable"
  Environment = "production"
  Owner = "devops-team"
}
```

#### Deploy Infrastructure
```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan -var-file="terraform.tfvars"

# Apply configuration
terraform apply -var-file="terraform.tfvars"
```

#### Update Kubeconfig
```bash
az aks get-credentials --resource-group rg-n8n-scalable-prod --name n8n-scalable-prod
```

### 2.3 Deploy n8n Application

#### Install Helm Chart
```bash
cd ../helm

# Install n8n with Azure-optimized values
helm upgrade --install n8n-scalable ./charts/n8n-scalable \
  --namespace n8n \
  --create-namespace \
  --values values-azure.yaml \
  --wait \
  --timeout 10m
```

## Phase 3: Local Development Setup

### 3.1 Docker Desktop / Minikube

#### Start Local Kubernetes
```bash
# For Docker Desktop: Enable Kubernetes in settings

# For Minikube:
minikube start --memory=8192 --cpus=4 --disk-size=20g
```

#### Deploy n8n Locally
```bash
cd n8n/docker-desktop

# Copy configuration template
cp helm/values-local.yaml.template helm/values-local.yaml

# Edit values-local.yaml with your secure values
# Replace CHANGE_ME_* placeholders

# Deploy using script
./deploy.sh
```

## Phase 4: Monitoring and Observability

### 4.1 Prometheus and Grafana Setup

#### Install Monitoring Stack
```bash
# Add Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values monitoring/prometheus-values.yaml

# Install custom dashboards
kubectl apply -f monitoring/grafana-dashboards/
```

### 4.2 Configure Alerts
```yaml
# monitoring/alert-rules.yaml
groups:
  - name: n8n-alerts
    rules:
      - alert: N8NHighQueueDepth
        expr: n8n_queue_depth > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "n8n queue depth is high"
          
      - alert: N8NWorkerDown
        expr: up{job="n8n-worker"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "n8n worker is down"
```

## Phase 5: Security Configuration

### 5.1 RBAC Setup
```yaml
# security/rbac.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: n8n-operator
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

### 5.2 Network Policies
```yaml
# security/network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: n8n-network-policy
  namespace: n8n
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: n8n-scalable
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 5678
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: n8n
    ports:
    - protocol: TCP
      port: 6379  # Redis
    - protocol: TCP
      port: 5432  # PostgreSQL
```

## Phase 6: Testing and Validation

### 6.1 Health Checks
```bash
# Run health tests
cd n8n/shared/tests
./health-check.sh

# Expected output:
# ✅ n8n main pods are healthy
# ✅ n8n worker pods are healthy  
# ✅ Redis connection successful
# ✅ PostgreSQL connection successful
# ✅ Queue processing functional
```

### 6.2 Load Testing
```bash
# Run load tests
./load-test.sh --duration 300s --rps 100

# Monitor scaling behavior
kubectl get hpa -n n8n -w
```

### 6.3 Failover Testing
```bash
# Test Redis failover
kubectl delete pod -n n8n redis-master-0

# Test database failover (AWS RDS/Azure Database)
# Simulate AZ failure in cloud console

# Verify recovery
kubectl get pods -n n8n
```

## Phase 7: Backup and Recovery

### 7.1 Database Backups
```bash
# AWS RDS automated backups are configured via Terraform
# Point-in-time recovery available for 7 days

# Manual backup
aws rds create-db-snapshot \
  --db-instance-identifier n8n-scalable-prod-postgres \
  --db-snapshot-identifier n8n-manual-backup-$(date +%Y%m%d)
```

### 7.2 Redis Persistence
```yaml
# Redis persistence is configured in Helm values
redis:
  master:
    persistence:
      enabled: true
      size: 10Gi
      storageClass: "gp3"
    # AOF and RDB persistence enabled
    configmap: |
      save 900 1
      save 300 10
      appendonly yes
```

## Phase 8: Operational Procedures

### 8.1 Scaling Operations
```bash
# Manual scaling
kubectl scale deployment n8n-scalable-worker --replicas=10 -n n8n

# Update HPA limits
kubectl patch hpa n8n-scalable-worker-hpa -n n8n -p '{"spec":{"maxReplicas":30}}'
```

### 8.2 Updates and Maintenance
```bash
# Rolling update
helm upgrade n8n-scalable ./charts/n8n-scalable \
  --namespace n8n \
  --values values-production.yaml \
  --set image.tag=1.20.0

# Monitor rollout
kubectl rollout status deployment/n8n-scalable-main -n n8n
```

### 8.3 Troubleshooting
```bash
# Debug pod issues
kubectl describe pod <pod-name> -n n8n
kubectl logs <pod-name> -n n8n --previous

# Debug service issues
kubectl get endpoints -n n8n
nslookup n8n-scalable-main.n8n.svc.cluster.local

# Debug ingress issues
kubectl describe ingress n8n-scalable -n n8n
```

## Cost Optimization

### Resource Right-Sizing
- Monitor resource utilization with Prometheus
- Adjust node instance types based on actual usage
- Use spot instances for worker nodes where appropriate

### Auto-Scaling Configuration
```yaml
# Aggressive scaling for cost optimization
autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 50
  targetCPUUtilizationPercentage: 60
  targetMemoryUtilizationPercentage: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
```

## Security Best Practices

### 1. Secrets Management
- Use cloud-native secret management (AWS Secrets Manager, Azure Key Vault)
- Rotate secrets regularly
- Never commit secrets to version control

### 2. Network Security
- Implement network policies
- Use private subnets for worker nodes
- Enable VPC flow logs for audit trails

### 3. Image Security
- Use official n8n images
- Scan images for vulnerabilities
- Implement admission controllers

### 4. Access Control
- Implement RBAC with least privilege
- Use service accounts for pod-to-pod communication
- Enable audit logging

## Disaster Recovery

### Multi-Region Setup
```bash
# Deploy to secondary region
cd n8n/aws-eks/terraform
terraform workspace new dr-region
terraform apply -var-file="terraform-dr.tfvars"
```

### Backup Strategy
- **Database**: Automated backups with point-in-time recovery
- **Redis**: AOF and RDB persistence with cross-region replication
- **Configuration**: GitOps with infrastructure as code
- **Workflows**: Regular exports and version control

## Next Steps

1. **Performance Tuning**: Optimize based on actual workload patterns
2. **Advanced Monitoring**: Implement custom metrics and dashboards
3. **Multi-Tenancy**: Implement namespace-based isolation
4. **GitOps**: Implement ArgoCD for continuous deployment
5. **Service Mesh**: Consider Istio for advanced traffic management 