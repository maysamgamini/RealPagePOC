# n8n Scalable Deployment Script for Docker Desktop / Minikube (PowerShell)
# This script sets up a complete n8n environment with queue mode, Redis, and PostgreSQL

param(
    [switch]$SkipBrowser
)

# Configuration
$NAMESPACE = "n8n"
$RELEASE_NAME = "n8n-scalable"
$CHART_PATH = "./helm"
$VALUES_FILE = "./helm/values-local.yaml"

Write-Host "========================================="
Write-Host "n8n Scalable Deployment for Docker Desktop"
Write-Host "========================================="
Write-Host ""

# Check if values-local.yaml exists
if (-not (Test-Path "helm/values-local.yaml")) {
    Write-Host "ERROR: values-local.yaml not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please create your local configuration file:" -ForegroundColor Yellow
    Write-Host "1. Copy the template: cp helm/values-local.yaml.template helm/values-local.yaml" -ForegroundColor Yellow
    Write-Host "2. Edit helm/values-local.yaml and replace placeholder values:" -ForegroundColor Yellow
    Write-Host "   - CHANGE_ME_ADMIN_PASSWORD (n8n admin password)" -ForegroundColor Yellow
    Write-Host "   - CHANGE_ME_DB_PASSWORD (PostgreSQL password)" -ForegroundColor Yellow
    Write-Host "   - CHANGE_ME_32_CHAR_ENCRYPTION_KEY (32-character encryption key)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Example encryption key generation:" -ForegroundColor Cyan
    Write-Host "   openssl rand -base64 32 | head -c 32" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

Write-Host "Starting n8n Scalable Deployment on Docker Desktop" -ForegroundColor Cyan

# Function to check if command exists
function Test-Command {
    param([string]$Command)
    try {
        Get-Command $Command -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

if (-not (Test-Command "minikube")) {
    Write-Host "Minikube is not installed. Please install it first." -ForegroundColor Red
    Write-Host "Visit: https://minikube.sigs.k8s.io/docs/start/"
    exit 1
}

if (-not (Test-Command "kubectl")) {
    Write-Host "kubectl is not installed. Please install it first." -ForegroundColor Red
    Write-Host "Visit: https://kubernetes.io/docs/tasks/tools/"
    exit 1
}

if (-not (Test-Command "helm")) {
    Write-Host "Helm is not installed. Please install it first." -ForegroundColor Red
    Write-Host "Visit: https://helm.sh/docs/intro/install/"
    exit 1
}

Write-Host "All prerequisites are installed" -ForegroundColor Green

# Check if Minikube is running
Write-Host "Checking Minikube status..." -ForegroundColor Yellow
$minikubeStatus = minikube status 2>$null
if ($minikubeStatus -notmatch "Running") {
    Write-Host "Starting Minikube..." -ForegroundColor Yellow
    minikube start --memory=8192 --cpus=4 --disk-size=20g
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Minikube started successfully" -ForegroundColor Green
    } else {
        Write-Host "Failed to start Minikube" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Minikube is already running" -ForegroundColor Green
}

# Enable required addons
Write-Host "Enabling Minikube addons..." -ForegroundColor Yellow
minikube addons enable metrics-server
minikube addons enable storage-provisioner
Write-Host "Addons enabled" -ForegroundColor Green

# Create namespace
Write-Host "Creating namespace..." -ForegroundColor Yellow
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
if ($LASTEXITCODE -eq 0) {
    Write-Host "Namespace '$NAMESPACE' created/updated" -ForegroundColor Green
} else {
    Write-Host "Failed to create namespace" -ForegroundColor Red
    exit 1
}

# Add Helm repositories
Write-Host "Adding Helm repositories..." -ForegroundColor Yellow
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
Write-Host "Helm repositories added and updated" -ForegroundColor Green

# Install/Upgrade the Helm chart
Write-Host "Deploying n8n with Helm..." -ForegroundColor Yellow
helm upgrade --install $RELEASE_NAME $CHART_PATH `
    --namespace $NAMESPACE `
    --values $VALUES_FILE `
    --wait `
    --timeout 10m

if ($LASTEXITCODE -eq 0) {
    Write-Host "n8n deployment completed successfully!" -ForegroundColor Green
} else {
    Write-Host "Helm deployment failed" -ForegroundColor Red
    exit 1
}

# Wait for all pods to be ready
Write-Host "Waiting for pods to be ready..." -ForegroundColor Yellow
kubectl wait --namespace $NAMESPACE `
    --for=condition=ready pod `
    --selector=app.kubernetes.io/name=n8n-scalable `
    --timeout=300s

if ($LASTEXITCODE -eq 0) {
    Write-Host "All pods are ready!" -ForegroundColor Green
} else {
    Write-Host "Some pods may still be starting. Check with: kubectl get pods -n $NAMESPACE" -ForegroundColor Yellow
}

# Get service information
Write-Host "Getting service information..." -ForegroundColor Yellow
$MINIKUBE_IP = minikube ip
$NODE_PORT = kubectl get svc -n $NAMESPACE "$RELEASE_NAME-main" -o jsonpath='{.spec.ports[0].nodePort}'

Write-Host ""
Write-Host "Deployment completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Access Information:" -ForegroundColor Cyan
Write-Host "   URL: http://localhost:30678/"
Write-Host "   Username: admin"
Write-Host "   Password: Check your values-local.yaml file"
Write-Host ""
Write-Host "Alternative access methods:" -ForegroundColor Yellow
Write-Host "   minikube service n8n-scalable-main -n n8n --url"
Write-Host "   kubectl port-forward -n n8n svc/n8n-scalable-main 8080:5678"
Write-Host "Useful Commands:" -ForegroundColor Cyan
Write-Host "   Check pods: kubectl get pods -n $NAMESPACE"
Write-Host "   Check services: kubectl get svc -n $NAMESPACE"
Write-Host "   View logs: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=n8n-scalable"
Write-Host "   Delete deployment: helm uninstall $RELEASE_NAME -n $NAMESPACE"
Write-Host ""

# Open browser (optional)
if (-not $SkipBrowser) {
    $response = Read-Host "Open n8n in your default browser? (y/n)"
    if ($response -eq "y" -or $response -eq "Y") {
        try {
            Start-Process "http://$MINIKUBE_IP`:$NODE_PORT"
        }
        catch {
            Write-Host "Could not open browser automatically. Please open http://$MINIKUBE_IP`:$NODE_PORT manually." -ForegroundColor Yellow
        }
    }
}

Write-Host "Setup complete! Happy automating with n8n!" -ForegroundColor Green 