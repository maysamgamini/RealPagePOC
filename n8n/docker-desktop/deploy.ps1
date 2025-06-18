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

# Colors for output
$Colors = @{
    Red = 'Red'
    Green = 'Green'
    Yellow = 'Yellow'
    Blue = 'Cyan'
}

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = 'White'
    )
    Write-Host $Message -ForegroundColor $Colors[$Color]
}

Write-ColorOutput "🚀 Starting n8n Scalable Deployment on Docker Desktop" "Blue"

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
Write-ColorOutput "📋 Checking prerequisites..." "Yellow"

if (-not (Test-Command "minikube")) {
    Write-ColorOutput "❌ Minikube is not installed. Please install it first." "Red"
    Write-Host "Visit: https://minikube.sigs.k8s.io/docs/start/"
    exit 1
}

if (-not (Test-Command "kubectl")) {
    Write-ColorOutput "❌ kubectl is not installed. Please install it first." "Red"
    Write-Host "Visit: https://kubernetes.io/docs/tasks/tools/"
    exit 1
}

if (-not (Test-Command "helm")) {
    Write-ColorOutput "❌ Helm is not installed. Please install it first." "Red"
    Write-Host "Visit: https://helm.sh/docs/intro/install/"
    exit 1
}

Write-ColorOutput "✅ All prerequisites are installed" "Green"

# Check if Minikube is running
Write-ColorOutput "🔍 Checking Minikube status..." "Yellow"
$minikubeStatus = minikube status 2>$null
if ($minikubeStatus -notmatch "Running") {
    Write-ColorOutput "🔄 Starting Minikube..." "Yellow"
    minikube start --memory=8192 --cpus=4 --disk-size=20g
    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "✅ Minikube started successfully" "Green"
    } else {
        Write-ColorOutput "❌ Failed to start Minikube" "Red"
        exit 1
    }
} else {
    Write-ColorOutput "✅ Minikube is already running" "Green"
}

# Enable required addons
Write-ColorOutput "🔧 Enabling Minikube addons..." "Yellow"
minikube addons enable metrics-server
minikube addons enable storage-provisioner
Write-ColorOutput "✅ Addons enabled" "Green"

# Create namespace
Write-ColorOutput "📂 Creating namespace..." "Yellow"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
if ($LASTEXITCODE -eq 0) {
    Write-ColorOutput "✅ Namespace '$NAMESPACE' created/updated" "Green"
} else {
    Write-ColorOutput "❌ Failed to create namespace" "Red"
    exit 1
}

# Add Helm repositories
Write-ColorOutput "📦 Adding Helm repositories..." "Yellow"
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
Write-ColorOutput "✅ Helm repositories added and updated" "Green"

# Install/Upgrade the Helm chart
Write-ColorOutput "🚀 Deploying n8n with Helm..." "Yellow"
helm upgrade --install $RELEASE_NAME $CHART_PATH `
    --namespace $NAMESPACE `
    --values $VALUES_FILE `
    --wait `
    --timeout 10m

if ($LASTEXITCODE -eq 0) {
    Write-ColorOutput "✅ n8n deployment completed successfully!" "Green"
} else {
    Write-ColorOutput "❌ Helm deployment failed" "Red"
    exit 1
}

# Wait for all pods to be ready
Write-ColorOutput "⏳ Waiting for pods to be ready..." "Yellow"
kubectl wait --namespace $NAMESPACE `
    --for=condition=ready pod `
    --selector=app.kubernetes.io/name=n8n-scalable `
    --timeout=300s

if ($LASTEXITCODE -eq 0) {
    Write-ColorOutput "✅ All pods are ready!" "Green"
} else {
    Write-ColorOutput "⚠️ Some pods may still be starting. Check with: kubectl get pods -n $NAMESPACE" "Yellow"
}

# Get service information
Write-ColorOutput "🔍 Getting service information..." "Yellow"
$MINIKUBE_IP = minikube ip
$NODE_PORT = kubectl get svc -n $NAMESPACE "$RELEASE_NAME-main" -o jsonpath='{.spec.ports[0].nodePort}'

Write-Host ""
Write-ColorOutput "🎉 Deployment completed successfully!" "Green"
Write-Host ""
Write-ColorOutput "📝 Access Information:" "Blue"
Write-Host "   🌐 n8n URL: http://$MINIKUBE_IP`:$NODE_PORT"
Write-Host "   👤 Username: admin"
Write-Host "   🔑 Password: Check your values-local.yaml file"
Write-Host ""
Write-ColorOutput "📊 Useful Commands:" "Blue"
Write-Host "   📋 Check pods: kubectl get pods -n $NAMESPACE"
Write-Host "   📋 Check services: kubectl get svc -n $NAMESPACE"
Write-Host "   📋 View logs: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=n8n-scalable"
Write-Host "   🗑️  Delete deployment: helm uninstall $RELEASE_NAME -n $NAMESPACE"
Write-Host ""

# Open browser (optional)
if (-not $SkipBrowser) {
    $response = Read-Host "🌐 Open n8n in your default browser? (y/n)"
    if ($response -eq "y" -or $response -eq "Y") {
        try {
            Start-Process "http://$MINIKUBE_IP`:$NODE_PORT"
        }
        catch {
            Write-ColorOutput "⚠️ Could not open browser automatically. Please open http://$MINIKUBE_IP`:$NODE_PORT manually." "Yellow"
        }
    }
}

Write-ColorOutput "🎊 Setup complete! Happy automating with n8n!" "Green"

Write-Host "Deployment completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Access Information:" -ForegroundColor Cyan
Write-Host "   URL: http://localhost:$NodePort/"
Write-Host "   Username: admin"
Write-Host "   Password: Check your values-local.yaml file"
Write-Host ""
Write-Host "Alternative access methods:" -ForegroundColor Yellow
Write-Host "   minikube service n8n-scalable-main -n n8n --url"
Write-Host "   kubectl port-forward -n n8n svc/n8n-scalable-main 8080:5678" 