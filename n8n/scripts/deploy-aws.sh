#!/bin/bash

# AWS EKS Deployment Script for n8n Scalable Platform
# This script automates the deployment of n8n to AWS EKS

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running from correct directory
if [[ ! -f "aws-eks/terraform/main.tf" ]]; then
    print_error "Please run this script from the n8n directory"
    exit 1
fi

print_status "Starting AWS EKS deployment for n8n..."

# Step 1: Check AWS credentials
print_status "Checking AWS credentials..."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    print_error "AWS credentials not configured or invalid"
    echo "Please configure AWS credentials using one of these methods:"
    echo "1. aws configure"
    echo "2. Set environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)"
    echo "3. Use IAM roles (for EC2 instances)"
    exit 1
fi

print_success "AWS credentials validated"

# Step 2: Check required tools
print_status "Checking required tools..."

if ! command -v terraform &> /dev/null; then
    print_error "Terraform not found. Please install Terraform: https://learn.hashicorp.com/tutorials/terraform/install-cli"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found. Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    print_error "Helm not found. Please install Helm: https://helm.sh/docs/intro/install/"
    exit 1
fi

print_success "All required tools found"

# Step 3: Check terraform.tfvars
print_status "Checking terraform configuration..."
if [[ ! -f "aws-eks/terraform/terraform.tfvars" ]]; then
    print_warning "terraform.tfvars not found. Copying from example..."
    cp aws-eks/terraform/terraform.tfvars.example aws-eks/terraform/terraform.tfvars
    print_warning "Please edit aws-eks/terraform/terraform.tfvars with your values and run this script again"
    exit 1
fi

# Step 4: Initialize and deploy Terraform
print_status "Initializing Terraform..."
cd aws-eks/terraform

terraform init

print_status "Planning Terraform deployment..."
terraform plan -out=tfplan

echo ""
read -p "Do you want to proceed with the deployment? (yes/no): " confirm
if [[ $confirm != "yes" ]]; then
    print_warning "Deployment cancelled"
    exit 0
fi

print_status "Applying Terraform configuration..."
terraform apply tfplan

# Step 5: Configure kubectl
print_status "Configuring kubectl..."
CLUSTER_NAME=$(terraform output -raw cluster_name)
AWS_REGION=$(terraform output -raw aws_region || echo "us-west-2")

aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

print_status "Testing cluster connectivity..."
kubectl cluster-info

# Step 6: Deploy Helm charts
print_status "Adding Helm repositories..."
cd ../../  # Back to n8n directory

helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo add aws-load-balancer-controller https://aws.github.io/eks-charts
helm repo add external-secrets https://charts.external-secrets.io
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server
helm repo update

print_status "Installing AWS Load Balancer Controller..."
LB_ROLE_ARN=$(cd aws-eks/terraform && terraform output -raw load_balancer_controller_role_arn)

helm upgrade --install aws-load-balancer-controller aws-load-balancer-controller/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$LB_ROLE_ARN

print_status "Installing External Secrets Operator..."
EXTERNAL_SECRETS_ROLE_ARN=$(cd aws-eks/terraform && terraform output -raw external_secrets_role_arn)

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$EXTERNAL_SECRETS_ROLE_ARN

print_status "Installing Metrics Server..."
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system

# Step 7: Deploy n8n
print_status "Deploying n8n..."
cd shared/helm

helm dependency update

helm upgrade --install n8n . \
  --namespace n8n \
  --create-namespace \
  --values values-aws.yaml \
  --wait \
  --timeout 10m

# Step 8: Display deployment information
print_success "Deployment completed successfully!"

echo ""
echo "=== DEPLOYMENT INFORMATION ==="
echo ""
echo "Cluster Name: $CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo ""
echo "Database Endpoint: $(cd ../../aws-eks/terraform && terraform output db_instance_endpoint)"
echo "Redis Endpoint: $(cd ../../aws-eks/terraform && terraform output redis_endpoint)"
echo ""
echo "=== NEXT STEPS ==="
echo ""
echo "1. Get n8n URL:"
echo "   kubectl get ingress -n n8n"
echo ""
echo "2. Get n8n admin password:"
echo "   kubectl get secret -n n8n n8n-secret -o jsonpath='{.data.N8N_BASIC_AUTH_PASSWORD}' | base64 -d"
echo ""
echo "3. Monitor deployment:"
echo "   kubectl get pods -n n8n"
echo "   kubectl logs -n n8n -l app=n8n"
echo ""
echo "4. Scale workers:"
echo "   kubectl scale deployment n8n-worker -n n8n --replicas=5"
echo ""

print_success "AWS EKS deployment complete!" 