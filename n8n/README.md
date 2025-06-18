# n8n Scalable Deployment Platform

## Overview

This project provides enterprise-grade, scalable n8n deployments across multiple cloud platforms using modern Kubernetes patterns. It implements n8n queue mode with Redis Streams for maximum flexibility, scalability, and event-driven workflow automation.

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Load Balancer                            │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                  n8n Main Pod                               │
│  - UI/API Server                                            │
│  - Webhook Handler                                          │
│  - Job Dispatcher (BullMQ)                                  │
│  - Scheduler                                                │
└─────────────────────┬───────────────────────────────────────┘
                      │
                ┌─────▼─────┐
                │   Redis   │
                │ (BullMQ + │
                │  Streams) │
                └─────┬─────┘
                      │
    ┌─────────────────┼─────────────────┐
    │                 │                 │
┌───▼───┐         ┌───▼───┐         ┌───▼───┐
│ n8n   │         │ n8n   │         │ n8n   │
│Worker │   ...   │Worker │   ...   │Worker │
│ Pod 1 │         │ Pod N │         │ Pod X │
└───────┘         └───────┘         └───────┘
```

### Event Flow with Redis Streams

```
[External Services] ──► [Redis Streams] ──► [n8n Workflows]
                                        │
[Retell AI Events] ─────┐               │
[Twilio Webhooks] ──────┼──► [Event     │
[Property Systems] ─────┘    Bridge]────┘
                             Service
```

## Platform Support

- **AWS EKS**: Production-ready with auto-scaling, monitoring, and security
- **Azure AKS**: Enterprise integration with Azure services
- **Docker Desktop/Minikube**: Local development and testing

## Quick Start

### Prerequisites

```bash
# Required tools
- kubectl
- helm
- docker
- terraform (for cloud deployments)
```

### Local Development (Docker Desktop/Minikube)

```bash
# 1. Start local environment
cd docker-desktop
make install

# 2. Access n8n
kubectl port-forward svc/n8n-main 5678:5678
# Open http://localhost:5678
```

### AWS EKS Deployment

```bash
# 1. Deploy infrastructure
cd aws-eks
terraform init
terraform apply

# 2. Install n8n
make install-n8n

# 3. Configure monitoring
make install-monitoring
```

### Azure AKS Deployment

```bash
# 1. Deploy infrastructure
cd azure-aks
terraform init
terraform apply

# 2. Install n8n
make install-n8n
```

## Features

### ✅ Scalability
- Horizontal Pod Autoscaler (HPA)
- Redis-based job queue (BullMQ)
- Worker pod auto-scaling
- Resource-based scaling metrics

### ✅ High Availability
- Multi-replica deployments
- Redis Sentinel for HA
- Health checks and liveness probes
- Graceful shutdown handling

### ✅ Security
- RBAC configuration
- Network policies
- Secret management
- TLS encryption

### ✅ Monitoring
- Prometheus metrics
- Grafana dashboards
- Redis monitoring
- Custom n8n metrics

### ✅ Event-Driven Architecture
- Redis Streams integration
- Event bridge service
- Webhook handling
- Stream-based triggers

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `EXECUTIONS_PROCESS` | Execution mode | `queue` |
| `QUEUE_BULL_REDIS_HOST` | Redis host | `redis-master` |
| `QUEUE_BULL_REDIS_PORT` | Redis port | `6379` |
| `REDIS_STREAMS_ENABLED` | Enable Redis Streams | `true` |

### Scaling Configuration

```yaml
# HPA Configuration
minReplicas: 2
maxReplicas: 20
targetCPUUtilizationPercentage: 70
targetMemoryUtilizationPercentage: 80
```

## Testing

### Run All Tests

```bash
# Unit tests
make test-unit

# Integration tests
make test-integration

# Load tests
make test-load

# End-to-end tests
make test-e2e
```

### Test Scenarios

1. **Scalability Tests**: Verify HPA scaling under load
2. **Failover Tests**: Redis and pod failure scenarios
3. **Performance Tests**: Queue processing and throughput
4. **Security Tests**: RBAC and network policies

## Monitoring and Observability

### Metrics

- **n8n Metrics**: Workflow executions, queue depth, processing time
- **Redis Metrics**: Memory usage, operations/sec, connection count
- **Kubernetes Metrics**: Pod CPU/memory, network I/O
- **Custom Metrics**: Business KPIs, error rates

### Dashboards

- n8n Operations Dashboard
- Redis Performance Dashboard
- Kubernetes Cluster Overview
- Application Performance Monitoring

## Best Practices

### Queue Management
- Configure appropriate queue concurrency
- Monitor queue depth and processing time
- Implement dead letter queues
- Use job priorities for critical workflows

### Redis Streams
- Partition streams by event type
- Implement consumer groups for load distribution
- Configure stream retention policies
- Monitor stream lag and processing rates

### Security
- Use least privilege RBAC
- Encrypt data in transit and at rest
- Regular security updates
- Network segmentation

## Troubleshooting

### Common Issues

1. **Queue Backlog**: Check worker scaling and Redis performance
2. **Memory Issues**: Adjust resource limits and garbage collection
3. **Network Connectivity**: Verify service mesh and network policies
4. **Redis Connection**: Check Redis health and connection limits

### Debug Commands

```bash
# Check pod status
kubectl get pods -l app=n8n

# View logs
kubectl logs -f deployment/n8n-worker

# Redis CLI
kubectl exec -it redis-master-0 -- redis-cli

# Queue status
kubectl exec -it n8n-main-0 -- n8n queue:health
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## License

MIT License - see LICENSE file for details

## Support

- Documentation: [docs/](./docs/)
- Issues: GitHub Issues
- Community: n8n Community Forum 