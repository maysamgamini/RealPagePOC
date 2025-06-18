# n8n Scalable Platform Configuration Guide

## Overview
This document provides comprehensive configuration guidance for the n8n Scalable Deployment Platform, covering queue mode setup, Redis Streams integration, horizontal pod autoscaling, and event-driven workflow patterns.

## Architecture Configuration

### Queue Mode Setup
The platform uses n8n in queue mode with BullMQ for distributed workflow execution:

```yaml
# Core queue configuration
n8n:
  env:
    EXECUTIONS_PROCESS: "queue"
    QUEUE_BULL_REDIS_HOST: "redis-master"
    QUEUE_BULL_REDIS_PORT: "6379"
    QUEUE_BULL_REDIS_DB: "0"
    QUEUE_BULL_REDIS_TIMEOUT_THRESHOLD: "5000"
    QUEUE_BULL_MAX_STALLED_COUNT: "1"
```

### Redis Streams Configuration
Event-driven architecture with Redis Streams for external system integration:

```yaml
# Redis Streams setup
n8n:
  env:
    REDIS_STREAMS_ENABLED: "true"
    REDIS_STREAMS_CONSUMER_GROUP: "n8n-consumers"
    REDIS_STREAMS_BLOCK_TIME: "5000"
    REDIS_STREAMS_MAX_LEN: "10000"
```

## Scaling Configuration

### Horizontal Pod Autoscaler (HPA)
Automatic scaling based on CPU, memory, and custom metrics:

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 20
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
  
  # Advanced scaling behavior
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
```

### Custom Metrics Scaling
Scale based on queue depth and processing metrics:

```yaml
# Custom metrics for HPA
customMetrics:
  - type: Pods
    pods:
      metric:
        name: n8n_queue_depth
      target:
        type: AverageValue
        averageValue: "10"
```

## Component Configuration

### Main Pod Configuration
UI/API server and job dispatcher:

```yaml
n8n:
  main:
    enabled: true
    replicaCount: 2
    
    resources:
      limits:
        cpu: 1000m
        memory: 2Gi
      requests:
        cpu: 500m
        memory: 1Gi
    
    # Health checks
    livenessProbe:
      httpGet:
        path: /healthz
        port: 5678
      initialDelaySeconds: 30
      periodSeconds: 10
    
    readinessProbe:
      httpGet:
        path: /healthz
        port: 5678
      initialDelaySeconds: 10
      periodSeconds: 5
```

### Worker Pod Configuration
Dedicated workflow execution workers:

```yaml
n8n:
  worker:
    enabled: true
    replicaCount: 3
    
    resources:
      limits:
        cpu: 2000m
        memory: 4Gi
      requests:
        cpu: 1000m
        memory: 2Gi
    
    # Worker-specific environment
    env:
      EXECUTIONS_PROCESS: "queue"
      N8N_DISABLE_UI: "true"
      QUEUE_WORKER_TIMEOUT: "300000"
```

## Event Bridge Configuration

### Redis Streams Event Bridge
Microservice for handling external events:

```javascript
// Event Bridge Service Configuration
const eventBridge = {
  streams: {
    'api-events': {
      consumerGroup: 'n8n-api-consumers',
      webhookUrl: 'http://n8n-main:5678/webhook/api-events',
      maxRetries: 3,
      batchSize: 10
    },
    'webhook-events': {
      consumerGroup: 'n8n-webhook-consumers', 
      webhookUrl: 'http://n8n-main:5678/webhook/webhook-events',
      maxRetries: 3,
      batchSize: 5
    },
    'scheduled-events': {
      consumerGroup: 'n8n-scheduled-consumers',
      webhookUrl: 'http://n8n-main:5678/webhook/scheduled-events',
      maxRetries: 5,
      batchSize: 1
    }
  }
};
```

### Event Bridge Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: n8n-event-bridge
spec:
  replicas: 2
  selector:
    matchLabels:
      app: n8n-event-bridge
  template:
    spec:
      containers:
      - name: event-bridge
        image: n8n-event-bridge:latest
        env:
        - name: REDIS_HOST
          value: "redis-master"
        - name: REDIS_PORT
          value: "6379"
        - name: N8N_WEBHOOK_BASE_URL
          value: "http://n8n-main:5678"
        resources:
          limits:
            cpu: 500m
            memory: 1Gi
          requests:
            cpu: 250m
            memory: 512Mi
```

## Database Configuration

### PostgreSQL Setup
High-availability database configuration:

```yaml
postgresql:
  enabled: true
  auth:
    database: n8n
    username: n8n
    password: # Set via secret
  
  primary:
    persistence:
      enabled: true
      size: 100Gi
      storageClass: "gp3"
    
    resources:
      limits:
        cpu: 2000m
        memory: 4Gi
      requests:
        cpu: 1000m
        memory: 2Gi
    
    # Connection pooling
    pgpool:
      enabled: true
      maxConnections: 100
```

### Redis Configuration
High-performance queue and streams backend:

```yaml
redis:
  enabled: true
  architecture: replication
  
  master:
    persistence:
      enabled: true
      size: 50Gi
      storageClass: "gp3"
    
    resources:
      limits:
        cpu: 1000m
        memory: 2Gi
      requests:
        cpu: 500m
        memory: 1Gi
  
  replica:
    replicaCount: 2
    persistence:
      enabled: true
      size: 50Gi
    
    resources:
      limits:
        cpu: 500m
        memory: 1Gi
      requests:
        cpu: 250m
        memory: 512Mi
```

## Security Configuration

### RBAC Setup
Role-based access control for n8n components:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: n8n-operator
  namespace: n8n
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

### Network Policies
Micro-segmentation for enhanced security:

```yaml
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
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: ingress-nginx
    ports:
    - protocol: TCP
      port: 5678
  egress:
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: redis
    ports:
    - protocol: TCP
      port: 6379
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: postgresql
    ports:
    - protocol: TCP
      port: 5432
```

## Monitoring Configuration

### Prometheus Metrics
Custom metrics for n8n monitoring:

```yaml
# ServiceMonitor for Prometheus
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: n8n-metrics
  namespace: n8n
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: n8n-scalable
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

### Grafana Dashboards
Pre-configured dashboards for operational insights:

```json
{
  "dashboard": {
    "title": "n8n Scalable Platform",
    "panels": [
      {
        "title": "Workflow Executions",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(n8n_workflow_executions_total[5m])",
            "legendFormat": "Executions/sec"
          }
        ]
      },
      {
        "title": "Queue Depth",
        "type": "graph", 
        "targets": [
          {
            "expr": "n8n_queue_depth",
            "legendFormat": "Queue Depth"
          }
        ]
      },
      {
        "title": "Worker Pod Count",
        "type": "graph",
        "targets": [
          {
            "expr": "kube_deployment_status_replicas{deployment=\"n8n-scalable-worker\"}",
            "legendFormat": "Worker Pods"
          }
        ]
      }
    ]
  }
}
```

## Workflow Patterns

### Event-Driven Workflows
Leverage Redis Streams for event processing:

```javascript
// Example: API Event Processing Workflow
{
  "nodes": [
    {
      "name": "API Event Trigger",
      "type": "n8n-nodes-base.webhook",
      "parameters": {
        "httpMethod": "POST",
        "path": "api-events"
      }
    },
    {
      "name": "Process Event",
      "type": "n8n-nodes-base.function",
      "parameters": {
        "functionCode": `
          const event = items[0].json;
          
          // Process the event
          const processedData = {
            eventId: event.id,
            eventType: event.type,
            timestamp: new Date().toISOString(),
            processed: true,
            data: event.data
          };
          
          return [{ json: processedData }];
        `
      }
    },
    {
      "name": "Send to Stream",
      "type": "n8n-nodes-base.redis",
      "parameters": {
        "operation": "xadd",
        "key": "processed-events",
        "values": "={{JSON.stringify($json)}}"
      }
    }
  ]
}
```

### High-Throughput Workflows
Optimize for performance and scalability:

```javascript
// Example: Batch Processing Workflow
{
  "nodes": [
    {
      "name": "Batch Trigger",
      "type": "n8n-nodes-base.cron",
      "parameters": {
        "rule": {
          "interval": [
            {
              "field": "minute",
              "expression": "*/5"
            }
          ]
        }
      }
    },
    {
      "name": "Fetch Batch Data",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "method": "GET",
        "url": "https://api.example.com/batch-data",
        "options": {
          "batch": {
            "batchSize": 100
          }
        }
      }
    },
    {
      "name": "Process in Parallel",
      "type": "n8n-nodes-base.splitInBatches",
      "parameters": {
        "batchSize": 10
      }
    },
    {
      "name": "Parallel Processing",
      "type": "n8n-nodes-base.function",
      "parameters": {
        "functionCode": `
          // Process batch items in parallel
          const promises = items.map(async (item) => {
            // Simulate processing
            await new Promise(resolve => setTimeout(resolve, 100));
            return { ...item.json, processed: true };
          });
          
          const results = await Promise.all(promises);
          return results.map(result => ({ json: result }));
        `
      }
    }
  ]
}
```

## Performance Optimization

### Queue Configuration
Optimize queue performance for high throughput:

```yaml
n8n:
  env:
    # Queue performance settings
    QUEUE_BULL_REDIS_TIMEOUT_THRESHOLD: "5000"
    QUEUE_BULL_MAX_STALLED_COUNT: "1"
    QUEUE_HEALTH_CHECK_ACTIVE: "true"
    QUEUE_HEALTH_CHECK_PORT: "5679"
    
    # Worker concurrency
    EXECUTIONS_PROCESS_QUEUE_CONCURRENCY: "10"
    
    # Memory optimization
    NODE_OPTIONS: "--max-old-space-size=4096"
```

### Resource Optimization
Right-size resources based on workload:

```yaml
# Production resource configuration
resources:
  main:
    limits:
      cpu: 2000m
      memory: 4Gi
    requests:
      cpu: 1000m
      memory: 2Gi
  
  worker:
    limits:
      cpu: 4000m
      memory: 8Gi
    requests:
      cpu: 2000m
      memory: 4Gi
```

## Troubleshooting

### Common Issues and Solutions

#### Queue Processing Issues
```bash
# Check queue health
kubectl exec -n n8n deployment/n8n-scalable-main -- curl localhost:5679/health

# Monitor queue depth
kubectl exec -n n8n deployment/redis-master -- redis-cli llen bull:n8n:active

# Check worker logs
kubectl logs -n n8n -l app.kubernetes.io/component=worker --tail=100
```

#### Scaling Issues
```bash
# Check HPA status
kubectl get hpa -n n8n

# Check metrics server
kubectl top pods -n n8n

# Debug scaling events
kubectl describe hpa n8n-scalable-worker-hpa -n n8n
```

#### Performance Issues
```bash
# Check resource utilization
kubectl top pods -n n8n

# Monitor database connections
kubectl exec -n n8n deployment/postgresql -- psql -U n8n -c "SELECT count(*) FROM pg_stat_activity;"

# Check Redis performance
kubectl exec -n n8n deployment/redis-master -- redis-cli info stats
```

## Best Practices

### Workflow Design
1. **Use appropriate triggers**: Choose the right trigger type for your use case
2. **Implement error handling**: Add try-catch blocks and error workflows
3. **Optimize data flow**: Minimize data transformation between nodes
4. **Use batching**: Process multiple items together when possible

### Performance
1. **Monitor queue depth**: Keep queue depth under control
2. **Scale workers appropriately**: Match worker count to workload
3. **Optimize database queries**: Use efficient queries and indexing
4. **Cache frequently accessed data**: Reduce database load

### Security
1. **Use secrets management**: Store sensitive data in Kubernetes secrets
2. **Implement network policies**: Restrict network access between components
3. **Regular updates**: Keep n8n and dependencies updated
4. **Audit workflows**: Review workflows for security issues

### Monitoring
1. **Set up alerts**: Monitor critical metrics and set up alerting
2. **Use dashboards**: Create comprehensive monitoring dashboards
3. **Log analysis**: Implement centralized logging and analysis
4. **Performance monitoring**: Track performance metrics over time

## Advanced Configuration

### Multi-Tenant Setup
Configure namespace-based multi-tenancy:

```yaml
# Tenant-specific namespace
apiVersion: v1
kind: Namespace
metadata:
  name: n8n-tenant-a
  labels:
    tenant: tenant-a
    
---
# Tenant-specific deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: n8n-scalable-tenant-a
  namespace: n8n-tenant-a
spec:
  template:
    spec:
      containers:
      - name: n8n
        env:
        - name: N8N_DATABASE_SCHEMA
          value: "tenant_a"
        - name: QUEUE_BULL_REDIS_DB
          value: "1"
```

### GitOps Integration
Use ArgoCD for continuous deployment:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: n8n-scalable
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/n8n-scalable
    targetRevision: HEAD
    path: helm/charts/n8n-scalable
    helm:
      valueFiles:
      - values-production.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: n8n
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

This configuration guide provides a comprehensive foundation for deploying and managing the n8n Scalable Deployment Platform across multiple environments with enterprise-grade features and best practices. 