#!/bin/bash

# n8n Scalable Deployment Script
# Automates deployment across AWS EKS, Azure AKS, and local environments

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${PROJECT_DIR}/deployment.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
PLATFORM="${PLATFORM:-local}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
NAMESPACE="${NAMESPACE:-n8n}"
HELM_RELEASE_NAME="${HELM_RELEASE_NAME:-n8n-scalable}"
SKIP_INFRA="${SKIP_INFRA:-false}"
SKIP_PREREQS="${SKIP_PREREQS:-false}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# Logging functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

# Usage function
usage() {
    cat << EOF
n8n Scalable Deployment Script

Usage: $0 [OPTIONS]

Options:
    -p, --platform PLATFORM     Target platform (aws-eks|azure-aks|local) [default: local]
    -e, --environment ENV        Environment (dev|staging|prod) [default: dev]
    -n, --namespace NAMESPACE    Kubernetes namespace [default: n8n]
    -r, --release-name NAME      Helm release name [default: n8n-scalable]
    --skip-infra                 Skip infrastructure deployment
    --skip-prereqs               Skip prerequisite installation
    --dry-run                    Show what would be deployed without executing
    -v, --verbose                Enable verbose output
    -h, --help                   Show this help message

Examples:
    # Deploy to local minikube
    $0 --platform local

    # Deploy to AWS EKS production
    $0 --platform aws-eks --environment prod

    # Deploy to Azure AKS with custom namespace
    $0 --platform azure-aks --namespace n8n-prod --environment prod

    # Dry run for AWS EKS
    $0 --platform aws-eks --dry-run

Environment Variables:
    PLATFORM                     Same as --platform
    ENVIRONMENT                  Same as --environment
    NAMESPACE                    Same as --namespace
    HELM_RELEASE_NAME           Same as --release-name
    SKIP_INFRA                  Same as --skip-infra
    SKIP_PREREQS                Same as --skip-prereqs
    DRY_RUN                     Same as --dry-run
    VERBOSE                     Same as --verbose

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--platform)
                PLATFORM="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -r|--release-name)
                HELM_RELEASE_NAME="$2"
                shift 2
                ;;
            --skip-infra)
                SKIP_INFRA="true"
                shift
                ;;
            --skip-prereqs)
                SKIP_PREREQS="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

# Validation functions
validate_platform() {
    case $PLATFORM in
        aws-eks|azure-aks|local)
            log "Platform validated: $PLATFORM"
            ;;
        *)
            error "Invalid platform: $PLATFORM. Must be one of: aws-eks, azure-aks, local"
            ;;
    esac
}

validate_environment() {
    case $ENVIRONMENT in
        dev|staging|prod)
            log "Environment validated: $ENVIRONMENT"
            ;;
        *)
            error "Invalid environment: $ENVIRONMENT. Must be one of: dev, staging, prod"
            ;;
    esac
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check required tools
    local tools=("kubectl" "helm")
    
    case $PLATFORM in
        aws-eks)
            tools+=("aws" "terraform")
            ;;
        azure-aks)
            tools+=("az" "terraform")
            ;;
        local)
            if command -v minikube &> /dev/null; then
                tools+=("minikube")
            elif command -v docker &> /dev/null; then
                tools+=("docker")
            else
                error "Neither minikube nor docker found for local deployment"
            fi
            ;;
    esac
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is required but not installed"
        else
            info "$tool: $(command -v "$tool")"
        fi
    done
    
    # Check kubectl context
    if ! kubectl cluster-info &> /dev/null; then
        error "kubectl is not connected to a cluster"
    fi
    
    local current_context
    current_context=$(kubectl config current-context)
    info "Current kubectl context: $current_context"
    
    # Validate context for platform
    case $PLATFORM in
        aws-eks)
            if [[ ! $current_context =~ arn:aws:eks ]]; then
                warn "Current context doesn't appear to be an EKS cluster"
            fi
            ;;
        azure-aks)
            if [[ ! $current_context =~ aks ]]; then
                warn "Current context doesn't appear to be an AKS cluster"
            fi
            ;;
        local)
            if [[ ! $current_context =~ (minikube|docker-desktop) ]]; then
                warn "Current context doesn't appear to be a local cluster"
            fi
            ;;
    esac
}

# Infrastructure deployment
deploy_infrastructure() {
    if [[ $SKIP_INFRA == "true" ]]; then
        log "Skipping infrastructure deployment"
        return 0
    fi
    
    log "Deploying infrastructure for $PLATFORM..."
    
    local terraform_dir="$PROJECT_DIR/$PLATFORM/terraform"
    local tfvars_file="$terraform_dir/environments/$ENVIRONMENT.tfvars"
    
    if [[ ! -d $terraform_dir ]]; then
        error "Terraform directory not found: $terraform_dir"
    fi
    
    if [[ ! -f $tfvars_file ]]; then
        error "Terraform variables file not found: $tfvars_file"
    fi
    
    cd "$terraform_dir"
    
    if [[ $DRY_RUN == "true" ]]; then
        info "DRY RUN: Would execute terraform commands in $terraform_dir"
        return 0
    fi
    
    # Initialize Terraform
    log "Initializing Terraform..."
    terraform init
    
    # Plan
    log "Planning Terraform deployment..."
    terraform plan -var-file="$tfvars_file" -out=tfplan
    
    # Apply
    log "Applying Terraform deployment..."
    terraform apply tfplan
    
    # Update kubectl config
    case $PLATFORM in
        aws-eks)
            local cluster_name
            cluster_name=$(terraform output -raw cluster_name)
            local region
            region=$(terraform output -raw region)
            aws eks update-kubeconfig --region "$region" --name "$cluster_name"
            ;;
        azure-aks)
            local resource_group
            resource_group=$(terraform output -raw resource_group_name)
            local cluster_name
            cluster_name=$(terraform output -raw cluster_name)
            az aks get-credentials --resource-group "$resource_group" --name "$cluster_name"
            ;;
    esac
    
    cd "$PROJECT_DIR"
}

# Install prerequisites
install_prerequisites() {
    if [[ $SKIP_PREREQS == "true" ]]; then
        log "Skipping prerequisites installation"
        return 0
    fi
    
    log "Installing prerequisites..."
    
    # Add Helm repositories
    log "Adding Helm repositories..."
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo add jetstack https://charts.jetstack.io
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    if [[ $DRY_RUN == "true" ]]; then
        info "DRY RUN: Would install prerequisites"
        return 0
    fi
    
    # Install ingress controller
    case $PLATFORM in
        aws-eks)
            log "Installing AWS Load Balancer Controller..."
            kubectl apply -k "$PROJECT_DIR/aws-eks/kubernetes/aws-load-balancer-controller/"
            ;;
        azure-aks)
            log "Installing Application Gateway Ingress Controller..."
            kubectl apply -k "$PROJECT_DIR/azure-aks/kubernetes/application-gateway-ingress/"
            ;;
        local)
            log "Installing NGINX Ingress Controller..."
            helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
                --namespace ingress-nginx \
                --create-namespace \
                --set controller.service.type=LoadBalancer \
                --wait
            ;;
    esac
    
    # Install cert-manager
    log "Installing cert-manager..."
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --set installCRDs=true \
        --wait
    
    # Install metrics-server if not present
    if ! kubectl get deployment metrics-server -n kube-system &> /dev/null; then
        log "Installing metrics-server..."
        kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    fi
    
    # Wait for prerequisites to be ready
    log "Waiting for prerequisites to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cert-manager -n cert-manager --timeout=300s
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=metrics-server -n kube-system --timeout=300s
}

# Deploy n8n
deploy_n8n() {
    log "Deploying n8n to $PLATFORM..."
    
    local values_file="$PROJECT_DIR/$PLATFORM/helm/values-${PLATFORM#*-}.yaml"
    
    # Use shared values for local deployment
    if [[ $PLATFORM == "local" ]]; then
        values_file="$PROJECT_DIR/docker-desktop/helm/values-local.yaml"
    fi
    
    if [[ ! -f $values_file ]]; then
        error "Values file not found: $values_file"
    fi
    
    # Create namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    if [[ $DRY_RUN == "true" ]]; then
        info "DRY RUN: Would deploy n8n with values from $values_file"
        helm template "$HELM_RELEASE_NAME" "$PROJECT_DIR/shared/helm/" \
            --namespace "$NAMESPACE" \
            --values "$values_file"
        return 0
    fi
    
    # Deploy n8n
    log "Installing n8n Helm chart..."
    helm upgrade --install "$HELM_RELEASE_NAME" "$PROJECT_DIR/shared/helm/" \
        --namespace "$NAMESPACE" \
        --values "$values_file" \
        --timeout=15m \
        --wait
    
    # Wait for deployment to be ready
    log "Waiting for n8n deployment to be ready..."
    kubectl wait --for=condition=available deployment -l app.kubernetes.io/instance="$HELM_RELEASE_NAME" \
        -n "$NAMESPACE" --timeout=600s
}

# Post-deployment verification
verify_deployment() {
    log "Verifying deployment..."
    
    # Check pod status
    log "Checking pod status..."
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$HELM_RELEASE_NAME"
    
    # Check services
    log "Checking services..."
    kubectl get services -n "$NAMESPACE" -l app.kubernetes.io/instance="$HELM_RELEASE_NAME"
    
    # Check HPA
    if kubectl get hpa -n "$NAMESPACE" &> /dev/null; then
        log "Checking HPA status..."
        kubectl get hpa -n "$NAMESPACE"
    fi
    
    # Check ingress
    if kubectl get ingress -n "$NAMESPACE" &> /dev/null; then
        log "Checking ingress..."
        kubectl get ingress -n "$NAMESPACE"
    fi
    
    # Test basic connectivity
    log "Testing basic connectivity..."
    local main_pod
    main_pod=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/component=main -o jsonpath='{.items[0].metadata.name}')
    
    if [[ -n $main_pod ]]; then
        if kubectl exec -n "$NAMESPACE" "$main_pod" -- curl -f http://localhost:5678/healthz &> /dev/null; then
            log "✅ n8n main pod health check passed"
        else
            warn "❌ n8n main pod health check failed"
        fi
    fi
    
    # Show access instructions
    show_access_instructions
}

# Show access instructions
show_access_instructions() {
    log "Deployment completed successfully!"
    echo
    echo "====================================="
    echo "🎉 n8n Deployment Complete!"
    echo "====================================="
    echo
    echo "Platform: $PLATFORM"
    echo "Environment: $ENVIRONMENT"
    echo "Namespace: $NAMESPACE"
    echo "Release: $HELM_RELEASE_NAME"
    echo
    echo "Access Instructions:"
    echo "-------------------"
    
    case $PLATFORM in
        aws-eks|azure-aks)
            local ingress_host
            ingress_host=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")
            if [[ -n $ingress_host ]]; then
                echo "🌐 Web UI: https://$ingress_host"
            else
                echo "🔄 Port Forward: kubectl port-forward -n $NAMESPACE svc/$HELM_RELEASE_NAME-main 8080:5678"
                echo "   Then access: http://localhost:8080"
            fi
            ;;
        local)
            echo "🔄 Port Forward: kubectl port-forward -n $NAMESPACE svc/$HELM_RELEASE_NAME-main 8080:5678"
            echo "   Then access: http://localhost:8080"
            ;;
    esac
    
    echo
    echo "Useful Commands:"
    echo "---------------"
    echo "📊 Check status: kubectl get all -n $NAMESPACE"
    echo "📈 Check HPA: kubectl get hpa -n $NAMESPACE"
    echo "📋 Check logs: kubectl logs -n $NAMESPACE deployment/$HELM_RELEASE_NAME-main -f"
    echo "🧪 Run tests: kubectl apply -f shared/tests/"
    echo
    echo "For more information, see: docs/DEPLOYMENT_GUIDE.md"
}

# Cleanup function
cleanup() {
    log "Cleaning up..."
    cd "$PROJECT_DIR"
}

# Main execution
main() {
    echo "🚀 n8n Scalable Deployment Script"
    echo "=================================="
    
    # Setup
    parse_args "$@"
    trap cleanup EXIT
    
    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "Starting deployment at $(date)" > "$LOG_FILE"
    
    # Validation
    validate_platform
    validate_environment
    check_prerequisites
    
    # Execute deployment steps
    deploy_infrastructure
    install_prerequisites
    deploy_n8n
    verify_deployment
    
    log "🎉 Deployment completed successfully!"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 