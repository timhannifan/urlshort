# URL Shortener Service

A production-ready URL shortening service built with FastAPI, featuring background job processing, Redis caching, PostgreSQL persistence, and Kubernetes-native deployment with autoscaling capabilities.

## Features

- **Microservices Architecture**: Separate API and worker services with clear separation of concerns
- **Event-Driven Processing**: Asynchronous job queue with Redis for background task processing
- **Auto-Scaling**: KEDA-based queue-driven autoscaling that scales workers based on queue depth
- **Production-Ready Infrastructure**: Full Kubernetes deployment with health checks, resource limits, and service discovery
- **Observability**: Prometheus metrics and Grafana dashboards for monitoring and alerting
- **High Availability**: Multi-replica deployments with database persistence and Redis caching
- **Cloud-Native**: Containerized services with Kubernetes-native configuration and deployment

## Architecture

The service consists of two main components:

1. **API Service** (`api/`): FastAPI application that handles:
   - URL shortening requests
   - URL redirection
   - Statistics retrieval
   - Health and metrics endpoints

2. **Worker Service** (`worker/`): Background job processor that handles:
   - QR code generation
   - Screenshot capture (simulated)
   - Metadata extraction from URLs

Both services communicate via:
- **PostgreSQL**: Persistent storage for URLs and job results
- **Redis**: Job queue and URL caching

## Tech Stack

- **API Framework**: FastAPI (Python 3.12+)
- **Database**: PostgreSQL
- **Cache/Queue**: Redis
- **Container Orchestration**: Kubernetes
- **Autoscaling**: KEDA (Kubernetes Event-Driven Autoscaling)
- **Monitoring**: Prometheus + Grafana
- **Package Management**: uv (via pyproject.toml)

## Prerequisites

- Docker Desktop with Kubernetes enabled OR Minikube
- kubectl installed
- Docker CLI

## Quick Start

### 0. Verify Kubernetes is Running

**For Docker Desktop:**
```bash
# Verify kubectl can connect to your cluster
kubectl cluster-info
kubectl get nodes

# If you see connection errors, ensure Kubernetes is enabled in Docker Desktop:
# Settings → Kubernetes → Enable Kubernetes
```

**For Minikube:**
```bash
# Check if minikube is running
minikube status

# If not running, start it
minikube start

# Verify connection
kubectl cluster-info
```

### 1. Create Secrets

```bash
# Copy the secrets template and fill in your values
cp k8s/base/secrets.yaml.template k8s/base/secrets.yaml

# Edit secrets.yaml and replace the placeholders with base64-encoded values
# To encode: echo -n 'yourvalue' | base64
```

### 2. Build Docker Images

```bash
# Make scripts executable (first time only)
chmod +x scripts/*.sh

# Build images
./scripts/build.sh
```

### 3. Deploy to Kubernetes

```bash
# Deploy all components
./scripts/deploy.sh
```

This script will:
- Create the Kubernetes namespace
- Deploy PostgreSQL and Redis
- Deploy the API and Worker services
- Set up Prometheus and Grafana
- Install KEDA (if not already installed)
- Set up port forwarding

### 4. Access the Services

After deployment, services are available at:
- **API**: http://localhost:8080
- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000 (admin/admin)

### 5. Test the API

```bash
# Create a short URL
curl -X POST http://localhost:8080/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://www.google.com"}'

# Get URL statistics
curl http://localhost:8080/stats/{short_code}

# Redirect (use short code from above)
curl -L http://localhost:8080/{short_code}
```

## Project Structure

```
urlshortener/
├── api/                    # API service
│   ├── main.py            # FastAPI application
│   ├── Dockerfile         # API container image
│   └── pyproject.toml      # Python dependencies
├── worker/                 # Worker service
│   ├── worker.py          # Background job processor
│   ├── Dockerfile         # Worker container image
│   └── pyproject.toml     # Python dependencies
├── k8s/base/              # Kubernetes manifests
│   ├── namespace.yaml     # Kubernetes namespace
│   ├── secrets.yaml       # Secrets configuration
│   ├── configmap.yaml     # Configuration
│   ├── postgres.yaml      # PostgreSQL StatefulSet
│   ├── redis.yaml         # Redis deployment
│   ├── api.yaml           # API deployment & service
│   ├── worker.yaml        # Worker deployment
│   └── monitoring.yaml    # Prometheus & Grafana
├── scripts/               # Deployment scripts
│   ├── build.sh          # Build Docker images
│   ├── deploy.sh         # Deploy to Kubernetes
│   ├── stop.sh           # Stop port-forwards
│   ├── verify.sh         # Verify deployment
│   ├── test-autoscaling.sh # Test autoscaling
│   └── watch-autoscaling.sh # Watch autoscaling
└── README.md             # This file
```

## Monitoring

### Prometheus Metrics

The service exposes the following metrics:

- `http_requests_total`: Total HTTP requests by method, endpoint, and status
- `http_request_duration_seconds`: HTTP request duration histogram
- `urls_created_total`: Total URLs created
- `urls_clicked_total`: Total URL clicks
- `jobs_processed_total`: Total jobs processed by type and status
- `job_processing_duration_seconds`: Job processing duration histogram

### Grafana Dashboards

Access Grafana at http://localhost:3000 (admin/admin) and add Prometheus as a data source at `http://prometheus-service:9090`.

Example queries:
- Request rate: `sum(rate(http_requests_total[5m])) by (endpoint)`
- URL creation rate: `rate(urls_created_total[5m])`
- Job processing rate: `sum(rate(jobs_processed_total[5m])) by (job_type, status)`
- Request latency (95th percentile): `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))`

## Autoscaling

The worker service uses KEDA for queue-based autoscaling. Workers automatically scale based on the Redis queue depth:

- **Min replicas**: 1
- **Max replicas**: 10
- **Scale target**: Redis queue length
- **Scale threshold**: 5 jobs per worker

To test autoscaling:

```bash
# Generate load
./scripts/test-autoscaling.sh

# Watch autoscaling in action
./scripts/watch-autoscaling.sh
```


## Stopping Services

```bash
# Stop port-forwards
./scripts/stop.sh

# Delete namespace (removes everything)
kubectl delete namespace urlshortener
```

## Next Steps

- [ ] Implement real screenshot service using Puppeteer/Playwright
- [ ] Add custom metrics to HPA for queue-based scaling
- [ ] Add analytics dashboard for click-through rates
- [ ] Implement additional caching layers
- [ ] Add Ingress controller for proper routing
- [ ] Set up GitOps with ArgoCD or Flux
- [ ] Add service mesh (Istio/Linkerd)
- [ ] Implement rate limiting
- [ ] Add authentication/authorization
- [ ] Set up CI/CD pipeline

## License

BSD 3-Clause License. See [LICENSE](LICENSE) for details.
