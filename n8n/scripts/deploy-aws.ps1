# AWS EKS Deployment Script for n8n Scalable Platform (PowerShell)
# This script automates the deployment of n8n to AWS EKS on Windows

param(
    [switch]$SkipConfirmation
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write colored output
function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Check if running from correct directory
if (!(Test-Path "aws-eks\terraform\main.tf")) {
    Write-Error "Please run this script from the n8n directory"
    exit 1
}

Write-Status "Starting AWS EKS deployment for n8n..."

# Step 1: Check AWS credentials
Write-Status "Checking AWS credentials..."
try {
    $null = aws sts get-caller-identity 2>$null
    Write-Success "AWS credentials validated"
} catch {
    Write-Error "AWS credentials not configured or invalid"
    Write-Host "Please configure AWS credentials using one of these methods:"
    Write-Host "1. aws configure"
    Write-Host "2. Set environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)"
    Write-Host "3. Use IAM roles (for EC2 instances)"
    exit 1
}

# Step 2: Check required tools
Write-Status "Checking required tools..."

$tools = @("terraform", "kubectl", "helm", "aws")
foreach ($tool in $tools) {
    try {
        $null = Get-Command $tool -ErrorAction Stop
    } catch {
        Write-Error "$tool not found. Please install $tool"
        Write-Host "Installation guides:"
        Write-Host "- Terraform: https://learn.hashicorp.com/tutorials/terraform/install-cli"
        Write-Host "- kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/"
        Write-Host "- Helm: https://helm.sh/docs/intro/install/"
        Write-Host "- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-windows.html"
        exit 1
    }
}

Write-Success "All required tools found"

# Step 3: Check terraform.tfvars
Write-Status "Checking terraform configuration..."
if (!(Test-Path "aws-eks\terraform\terraform.tfvars")) {
    Write-Warning "terraform.tfvars not found. Copying from example..."
    Copy-Item "aws-eks\terraform\terraform.tfvars.example" "aws-eks\terraform\terraform.tfvars"
    Write-Warning "Please edit aws-eks\terraform\terraform.tfvars with your values and run this script again"
    exit 1
}

# Step 4: Initialize and deploy Terraform
Write-Status "Initializing Terraform..."
Push-Location "aws-eks\terraform"

try {
    terraform init

    Write-Status "Planning Terraform deployment..."
    terraform plan -out=tfplan

    if (!$SkipConfirmation) {
        $confirm = Read-Host "`nDo you want to proceed with the deployment? (yes/no)"
        if ($confirm -ne "yes") {
            Write-Warning "Deployment cancelled"
            exit 0
        }
    }

    Write-Status "Applying Terraform configuration..."
    terraform apply tfplan

    # Step 5: Configure kubectl
    Write-Status "Configuring kubectl..."
    $clusterName = terraform output -raw cluster_name
    $awsRegion = try { terraform output -raw aws_region } catch { "us-west-2" }

    aws eks update-kubeconfig --region $awsRegion --name $clusterName

    Write-Status "Testing cluster connectivity..."
    kubectl cluster-info

} finally {
    Pop-Location
}

# Step 6: Deploy Helm charts
Write-Status "Adding Helm repositories..."

helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo add aws-load-balancer-controller https://aws.github.io/eks-charts
helm repo add external-secrets https://charts.external-secrets.io
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server
helm repo update

Write-Status "Installing AWS Load Balancer Controller..."
Push-Location "aws-eks\terraform"
$lbRoleArn = terraform output -raw load_balancer_controller_role_arn
Pop-Location

helm upgrade --install aws-load-balancer-controller aws-load-balancer-controller/aws-load-balancer-controller `
  --namespace kube-system `
  --set clusterName=$clusterName `
  --set serviceAccount.create=true `
  --set serviceAccount.name=aws-load-balancer-controller `
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$lbRoleArn

Write-Status "Installing External Secrets Operator..."
Push-Location "aws-eks\terraform"
$externalSecretsRoleArn = terraform output -raw external_secrets_role_arn
Pop-Location

helm upgrade --install external-secrets external-secrets/external-secrets `
  --namespace external-secrets-system `
  --create-namespace `
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$externalSecretsRoleArn

Write-Status "Installing Metrics Server..."
helm upgrade --install metrics-server metrics-server/metrics-server `
  --namespace kube-system

# Step 7: Deploy n8n
Write-Status "Deploying n8n..."
Push-Location "shared\helm"

try {
    helm dependency update

    helm upgrade --install n8n . `
      --namespace n8n `
      --create-namespace `
      --values values-aws.yaml `
      --wait `
      --timeout 10m

} finally {
    Pop-Location
}

# Step 8: Display deployment information
Write-Success "Deployment completed successfully!"

Write-Host ""
Write-Host "=== DEPLOYMENT INFORMATION ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Cluster Name: $clusterName"
Write-Host "Region: $awsRegion"
Write-Host ""

Push-Location "aws-eks\terraform"
$dbEndpoint = terraform output db_instance_endpoint
$redisEndpoint = terraform output redis_endpoint
Pop-Location

Write-Host "Database Endpoint: $dbEndpoint"
Write-Host "Redis Endpoint: $redisEndpoint"
Write-Host ""
Write-Host "=== NEXT STEPS ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Get n8n URL:"
Write-Host "   kubectl get ingress -n n8n"
Write-Host ""
Write-Host "2. Get n8n admin password:"
Write-Host "   kubectl get secret -n n8n n8n-secret -o jsonpath='{.data.N8N_BASIC_AUTH_PASSWORD}' | base64 -d"
Write-Host ""
Write-Host "3. Monitor deployment:"
Write-Host "   kubectl get pods -n n8n"
Write-Host "   kubectl logs -n n8n -l app=n8n"
Write-Host ""
Write-Host "4. Scale workers:"
Write-Host "   kubectl scale deployment n8n-worker -n n8n --replicas=5"
Write-Host ""

Write-Success "AWS EKS deployment complete!" 