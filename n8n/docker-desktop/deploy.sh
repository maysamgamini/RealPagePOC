#!/bin/bash

# n8n Scalable Deployment Script for Docker Desktop / Minikube
# This script sets up a complete n8n environment with queue mode, Redis, and PostgreSQL

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}🚀 n8n Scalable Deployment for Docker Desktop${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

# Check if values-local.yaml exists
if [ ! -f "helm/values-local.yaml" ]; then
    echo -e "${RED}❌ ERROR: values-local.yaml not found!${NC}"
    echo ""
    echo -e "${YELLOW}Please create your local configuration file:${NC}"
    echo -e "${YELLOW}1. Copy the template: cp helm/values-local.yaml.template helm/values-local.yaml${NC}"
    echo -e "${YELLOW}2. Edit helm/values-local.yaml and replace placeholder values:${NC}"
    echo -e "${YELLOW}   - CHANGE_ME_ADMIN_PASSWORD (n8n admin password)${NC}"
    echo -e "${YELLOW}   - CHANGE_ME_DB_PASSWORD (PostgreSQL password)${NC}"
    echo -e "${YELLOW}   - CHANGE_ME_32_CHAR_ENCRYPTION_KEY (32-character encryption key)${NC}"
    echo ""
    echo -e "${CYAN}Example encryption key generation:${NC}"
    echo -e "${CYAN}   openssl rand -base64 32 | head -c 32${NC}"
    echo ""
    exit 1
fi

# Configuration
NAMESPACE="n8n"
RELEASE_NAME="n8n-scalable"
CHART_PATH="./helm"
VALUES_FILE="./helm/values-local.yaml"

echo -e "${BLUE}🚀 Starting n8n Scalable Deployment on Docker Desktop${NC}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${YELLOW}📋 Checking prerequisites...${NC}"

if ! command_exists minikube; then
    echo -e "${RED}❌ Minikube is not installed. Please install it first.${NC}"
    echo "Visit: https://minikube.sigs.k8s.io/docs/start/"
    exit 1
fi

if ! command_exists kubectl; then
    echo -e "${RED}❌ kubectl is not installed. Please install it first.${NC}"
    echo "Visit: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

if ! command_exists helm; then
    echo -e "${RED}❌ Helm is not installed. Please install it first.${NC}"
    echo "Visit: https://helm.sh/docs/intro/install/"
    exit 1
fi

echo -e "${GREEN}✅ All prerequisites are installed${NC}"

# Check if Minikube is running
echo -e "${YELLOW}🔍 Checking Minikube status...${NC}"
if ! minikube status | grep -q "Running"; then
    echo -e "${YELLOW}🔄 Starting Minikube...${NC}"
    minikube start --memory=8192 --cpus=4 --disk-size=20g
    echo -e "${GREEN}✅ Minikube started successfully${NC}"
else
    echo -e "${GREEN}✅ Minikube is already running${NC}"
fi

# Enable required addons
echo -e "${YELLOW}🔧 Enabling Minikube addons...${NC}"
minikube addons enable metrics-server
minikube addons enable storage-provisioner
echo -e "${GREEN}✅ Addons enabled${NC}"

# Create namespace
echo -e "${YELLOW}📂 Creating namespace...${NC}"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✅ Namespace '$NAMESPACE' created/updated${NC}"

# Add Helm repositories
echo -e "${YELLOW}📦 Adding Helm repositories...${NC}"
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
echo -e "${GREEN}✅ Helm repositories added and updated${NC}"

# Install/Upgrade the Helm chart
echo -e "${YELLOW}🚀 Deploying n8n with Helm...${NC}"
helm upgrade --install $RELEASE_NAME $CHART_PATH \
    --namespace $NAMESPACE \
    --values $VALUES_FILE \
    --wait \
    --timeout 10m

echo -e "${GREEN}✅ n8n deployment completed successfully!${NC}"

# Wait for all pods to be ready
echo -e "${YELLOW}⏳ Waiting for pods to be ready...${NC}"
kubectl wait --namespace $NAMESPACE \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=n8n-scalable \
    --timeout=300s

echo -e "${GREEN}✅ All pods are ready!${NC}"

# Get service information
echo -e "${YELLOW}🔍 Getting service information...${NC}"
MINIKUBE_IP=$(minikube ip)
NODE_PORT=$(kubectl get svc -n $NAMESPACE ${RELEASE_NAME}-main -o jsonpath='{.spec.ports[0].nodePort}')

echo ""
echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
echo ""
echo -e "${CYAN}🌐 Access Information:${NC}"
echo -e "   📍 URL: http://localhost:${NODE_PORT}/"
echo -e "   👤 Username: admin"
echo -e "   🔑 Password: Check your values-local.yaml file"
echo ""
echo -e "${YELLOW}📝 Alternative access methods:${NC}"
echo -e "   minikube service n8n-scalable-main -n n8n --url"
echo -e "   kubectl port-forward -n n8n svc/n8n-scalable-main 8080:5678"

# Open browser (optional)
read -p "🌐 Open n8n in your default browser? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command_exists xdg-open; then
        xdg-open "http://${MINIKUBE_IP}:${NODE_PORT}"
    elif command_exists open; then
        open "http://${MINIKUBE_IP}:${NODE_PORT}"
    elif command_exists start; then
        start "http://${MINIKUBE_IP}:${NODE_PORT}"
    else
        echo -e "${YELLOW}⚠️  Could not detect browser command. Please open http://${MINIKUBE_IP}:${NODE_PORT} manually.${NC}"
    fi
fi

echo -e "${GREEN}🎊 Setup complete! Happy automating with n8n!${NC}" 