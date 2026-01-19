#!/bin/bash

# build.sh - Build Docker images for URL Shortener

set -e  # Exit on error

echo "Building URL Shortener Docker Images"

# Check if minikube is running
if minikube status &> /dev/null; then
    echo "✓ Minikube detected - using minikube's Docker daemon"
    eval $(minikube docker-env)
else
    echo "⚠️  Minikube not running - using local Docker daemon"
    echo "   If you're using minikube, start it first with: minikube start"
fi

# Build API image
echo ""
echo "Building API image..."
docker build -t urlshortener-api:latest ./api
echo "✓ API image built"

# Build Worker image
echo ""
echo "Building Worker image..."
docker build -t urlshortener-worker:latest ./worker
echo "✓ Worker image built"

# Verify images
echo ""
echo "Built images:"
docker images | grep urlshortener || echo "No images found!"

echo ""
echo "✅ Build complete!"
echo ""
echo "Next steps:"
echo "  1. Deploy to Kubernetes: ./scripts/deploy.sh"
echo "  2. Or manually: kubectl apply -f k8s/base/"
