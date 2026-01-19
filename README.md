# URL Shortener Service

A production-ready URL shortening service built with FastAPI, featuring background job processing, Redis caching, PostgreSQL persistence, and Kubernetes-native deployment with autoscaling capabilities.

## Features

- **URL Shortening**: Create short URLs with optional custom codes
- **Background Job Processing**: Asynchronous processing of QR code generation, screenshots, and metadata extraction
- **Redis Caching**: Fast URL lookups with Redis caching layer
- **PostgreSQL Persistence**: Reliable data storage with click tracking
- **Kubernetes Deployment**: Full Kubernetes manifests with autoscaling via KEDA
- **Monitoring**: Prometheus metrics and Grafana dashboards
- **Health Checks**: Liveness and readiness probes for reliable deployments
- **Analytics**: Track URL creation and click events

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

### 1. Build Docker Images

```bash
# Make scripts executable (first time only)
chmod +x scripts/*.sh

# Build images
./scripts/build.sh
```

### 2. Deploy to Kubernetes

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

### 3. Access the Services

After deployment, services are available at:
- **API**: http://localhost:8080
- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000 (admin/admin)

### 4. Test the API

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
├── deploy-guide.md        # Detailed deployment guide
└── README.md             # This file
```

## API Endpoints

### `POST /shorten`
Create a shortened URL.

**Request:**
```json
{
  "url": "https://example.com",
  "custom_code": "optional-custom-code"
}
```

**Response:**
```json
{
  "short_url": "http://localhost:8080/abc123",
  "original_url": "https://example.com",
  "short_code": "abc123"
}
```

### `GET /{short_code}`
Redirect to the original URL.

**Response:**
```json
{
  "redirect_url": "https://example.com"
}
```

### `GET /stats/{short_code}`
Get statistics for a shortened URL.

**Response:**
```json
{
  "short_code": "abc123",
  "original_url": "https://example.com",
  "clicks": 42,
  "created_at": "2024-01-01T00:00:00",
  "jobs": [
    {
      "type": "qr_code",
      "status": "completed",
      "result": {...}
    }
  ]
}
```

### `GET /health`
Health check endpoint.

### `GET /ready`
Readiness check endpoint (verifies database and Redis connectivity).

### `GET /metrics`
Prometheus metrics endpoint.

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

## Development

### Local Development

1. **Set up environment variables:**
   ```bash
   export REDIS_HOST=localhost
   export REDIS_PORT=6379
   export POSTGRES_HOST=localhost
   export POSTGRES_PORT=5432
   export POSTGRES_DB=urlshortener
   export POSTGRES_USER=urlshort
   export POSTGRES_PASSWORD=password123
   export BASE_URL=http://localhost:8080
   ```

2. **Start dependencies:**
   ```bash
   # Start PostgreSQL and Redis (using Docker)
   docker run -d --name postgres -e POSTGRES_DB=urlshortener -e POSTGRES_USER=urlshort -e POSTGRES_PASSWORD=password123 -p 5432:5432 postgres:15
   docker run -d --name redis -p 6379:6379 redis:7-alpine
   ```

3. **Run the API:**
   ```bash
   cd api
   uv run python main.py
   ```

4. **Run the worker:**
   ```bash
   cd worker
   uv run python worker.py
   ```

### Building Images

```bash
# Build API image
cd api
docker build -t urlshortener-api:latest .

# Build Worker image
cd ../worker
docker build -t urlshortener-worker:latest .
```

## Deployment

See [deploy-guide.md](./deploy-guide.md) for detailed deployment instructions.

### Quick Deploy

```bash
# Build and deploy
./scripts/build.sh
./scripts/deploy.sh
```

### Manual Deploy

```bash
# Apply manifests in order
kubectl apply -f k8s/base/namespace.yaml
kubectl apply -f k8s/base/secrets.yaml
kubectl apply -f k8s/base/configmap.yaml
kubectl apply -f k8s/base/postgres.yaml
kubectl apply -f k8s/base/redis.yaml

# Wait for databases
kubectl wait --for=condition=ready pod -l app=postgres -n urlshortener --timeout=120s
kubectl wait --for=condition=ready pod -l app=redis -n urlshortener --timeout=120s

# Deploy application
kubectl apply -f k8s/base/api.yaml
kubectl apply -f k8s/base/worker.yaml
kubectl apply -f k8s/base/monitoring.yaml
```

## Stopping Services

```bash
# Stop port-forwards
./scripts/stop.sh

# Delete namespace (removes everything)
kubectl delete namespace urlshortener
```

## Troubleshooting

### kubectl can't connect to Kubernetes API server?

If you see an error like `failed to download openapi: Get "http://localhost:8080/openapi/v2?timeout=32s": dial tcp [::1]:8080: connect: connection refused`, this means kubectl can't reach your Kubernetes cluster.

**For Docker Desktop:**
1. Ensure Kubernetes is enabled and running:
   - Open Docker Desktop
   - Go to Settings → Kubernetes
   - Make sure "Enable Kubernetes" is checked
   - Wait for Kubernetes to start (the status should show "Running")

2. Verify kubectl can connect:
   ```bash
   kubectl cluster-info
   kubectl get nodes
   ```

3. Check your kubectl context:
   ```bash
   kubectl config current-context
   # Should show something like "docker-desktop" or "docker-for-desktop"
   ```

4. If context is wrong, switch to Docker Desktop context:
   ```bash
   kubectl config use-context docker-desktop
   # or
   kubectl config use-context docker-for-desktop
   ```

**For Minikube:**
```bash
# Check if minikube is running
minikube status

# If not running, start it
minikube start

# Make sure kubectl is using minikube context
kubectl config use-context minikube
```

### Pods not starting?
```bash
kubectl describe pod -n urlshortener <pod-name>
kubectl logs -n urlshortener <pod-name>
```

### Can't connect to services?
```bash
kubectl get svc -n urlshortener
kubectl get endpoints -n urlshortener
```

### Images not found?
If using Minikube, ensure you're using minikube's Docker daemon:
```bash
eval $(minikube docker-env)
./scripts/build.sh
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

[Add your license here]

## Contributing

[Add contributing guidelines here]
