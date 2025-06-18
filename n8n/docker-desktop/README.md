# n8n Scalable Deployment on Docker Desktop

## Quick Start

### Prerequisites
- Docker Desktop with Kubernetes enabled
- Minikube (alternative to Docker Desktop Kubernetes)
- kubectl
- Helm 3.x

### Setup Configuration
1. **Copy the configuration template:**
   ```bash
   cp helm/values-local.yaml.template helm/values-local.yaml
   ```

2. **Generate secure values:**
   ```bash
   # Generate a 32-character encryption key
   openssl rand -base64 32 | head -c 32
   ```

3. **Edit `helm/values-local.yaml` and replace:**
   - `CHANGE_ME_ADMIN_PASSWORD` → Your chosen admin password
   - `CHANGE_ME_DB_PASSWORD` → Your chosen database password  
   - `CHANGE_ME_32_CHAR_ENCRYPTION_KEY` → The generated 32-character key

### Deploy
```bash
# Using PowerShell
./deploy-simple.ps1

# Using Bash
./deploy.sh
```

### Access n8n
- **URL**: http://localhost:30678
- **Username**: `admin`
- **Password**: The password you set in your configuration

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Docker Desktop                           │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    Minikube Cluster                         │ │
│  │                                                             │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │ │
│  │  │   n8n Main   │  │ n8n Worker 1 │  │ n8n Worker 2 │      │ │
│  │  │  (UI/API)    │  │  (Queue)     │  │  (Queue)     │      │ │
│  │  │              │  │              │  │              │      │ │
│  │  │ Port: 30678  │  │              │  │              │      │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘      │ │
│  │         │                  │                  │             │ │
│  │         └──────────────────┼──────────────────┘             │ │
│  │                           │                                 │ │
│  │  ┌──────────────┐  ┌──────────────┐                        │ │
│  │  │    Redis     │  │ PostgreSQL   │                        │ │
│  │  │  (Queue &    │  │ (Database)   │                        │ │
│  │  │   Streams)   │  │              │                        │ │
│  │  └──────────────┘  └──────────────┘                        │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### n8n Main Instance
- **Purpose**: Handles UI, API requests, and webhook endpoints
- **Replicas**: 1 (single instance for local development)
- **Access**: NodePort service on port 30678
- **Resources**: 250m CPU, 512Mi RAM (reduced for local)

### n8n Worker Instances  
- **Purpose**: Process workflow executions from the queue
- **Replicas**: 2 (reduced for local development)
- **Resources**: 500m CPU, 1Gi RAM (reduced for local)

### Redis
- **Purpose**: Queue management and streams for real-time communication
- **Mode**: Standalone (single instance for local)
- **Persistence**: 2Gi storage

### PostgreSQL
- **Purpose**: Persistent storage for workflows, credentials, and execution history
- **Mode**: Single instance
- **Persistence**: 2Gi storage

## Configuration

The deployment uses a template-based configuration system for security:

### Template File: `helm/values-local.yaml.template`
Contains placeholder values that must be replaced with your secure values.

### Local File: `helm/values-local.yaml` (gitignored)
Your actual configuration with real passwords and keys.

### Key Configuration Values:
- **N8N_BASIC_AUTH_PASSWORD**: Admin password for n8n UI
- **DB_POSTGRESDB_PASSWORD**: PostgreSQL database password
- **N8N_ENCRYPTION_KEY**: 32-character key for encrypting credentials

## Security Features

- ✅ No hardcoded secrets in repository
- ✅ Template-based configuration
- ✅ Local-only sensitive files (gitignored)
- ✅ Basic authentication enabled
- ✅ Encrypted credential storage

## Troubleshooting

### Common Issues

1. **values-local.yaml not found**
   - Copy from template: `cp helm/values-local.yaml.template helm/values-local.yaml`
   - Edit and replace placeholder values

2. **Pods in CrashLoopBackOff**
   - Check configuration values are correct
   - Verify database connectivity: `kubectl logs -n n8n deployment/n8n-scalable-main`

3. **Cannot access n8n UI**
   - Verify NodePort service: `kubectl get svc -n n8n`
   - Check Minikube status: `minikube status`
   - Get service URL: `minikube service n8n-scalable-main -n n8n --url`

4. **Authentication failed**
   - Verify your admin password in `helm/values-local.yaml`
   - Check configmap: `kubectl get configmap -n n8n n8n-scalable-config -o yaml`

### Useful Commands

```bash
# Check pod status
kubectl get pods -n n8n

# View logs
kubectl logs -n n8n deployment/n8n-scalable-main
kubectl logs -n n8n deployment/n8n-scalable-worker

# Access services
minikube service list -n n8n

# Port forward (alternative access)
kubectl port-forward -n n8n svc/n8n-scalable-main 8080:5678

# Restart deployment
kubectl rollout restart deployment -n n8n n8n-scalable-main
kubectl rollout restart deployment -n n8n n8n-scalable-worker
```

## Cleanup

```bash
# Uninstall n8n
helm uninstall n8n-scalable -n n8n

# Delete namespace
kubectl delete namespace n8n

# Stop Minikube (optional)
minikube stop
```

## 📁 File Structure

```
docker-desktop/
├── helm/                           # Helm chart files
│   ├── Chart.yaml                  # Chart metadata
│   ├── values.yaml                 # Default values
│   ├── values-local.yaml           # Local development values
│   └── templates/                  # Kubernetes manifests
│       ├── deployment-main.yaml
│       ├── deployment-worker.yaml
│       └── hpa.yaml
├── deploy.sh                       # Bash deployment script
├── deploy.ps1                      # PowerShell deployment script
└── README.md                       # This file
```

## ⚙️ Advanced Configuration

### Custom Environment Variables

Edit `values-local.yaml` to add custom environment variables:

```yaml
n8n:
  env:
    CUSTOM_VAR: "custom_value"
    N8N_LOG_LEVEL: "debug"
```

### Custom Resource Limits

```yaml
n8n:
  main:
    resources:
      limits:
        cpu: 1000m
        memory: 2Gi
  worker:
    resources:
      limits:
        cpu: 2000m
        memory: 4Gi
```

### External Database

To use an external PostgreSQL database:

```yaml
postgresql:
  enabled: false

n8n:
  env:
    DB_POSTGRESDB_HOST: "external-postgres-host"
    DB_POSTGRESDB_USER: "n8n_user"
    DB_POSTGRESDB_PASSWORD: "secure_password"
```

## 🔒 Security Notes

⚠️ **Important**: This configuration is optimized for local development and should not be used in production without proper security hardening:

- Change default passwords
- Enable HTTPS/TLS
- Configure proper authentication
- Set up network policies
- Use secrets management
- Enable audit logging

## 📞 Support

For issues and questions:

1. Check the [n8n documentation](https://docs.n8n.io/)
2. Visit the [n8n community forum](https://community.n8n.io/)
3. Check [Minikube troubleshooting](https://minikube.sigs.k8s.io/docs/handbook/troubleshooting/)

## 📝 License

This deployment configuration follows the same license as n8n. Please refer to the [n8n license](https://github.com/n8n-io/n8n/blob/master/LICENSE.md) for details. 