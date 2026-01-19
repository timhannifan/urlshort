#!/bin/bash

# stop.sh - Stop and cleanup all urlshortener resources

set -e

echo "Stopping and cleaning up URL Shortener deployment..."
echo ""

# Stop port-forwards
echo "Stopping port-forwards..."
pkill -f "kubectl port-forward.*urlshortener" || echo "  (No port-forwards found)"
sleep 1

# Check if namespace exists
if kubectl get namespace urlshortener &> /dev/null; then
    echo ""
    echo "Deleting all resources in urlshortener namespace..."
    echo "   This will delete:"
    echo "   - All pods, services, deployments"
    echo "   - Databases (PostgreSQL, Redis)"
    echo "   - Monitoring stack (Prometheus, Grafana)"
    echo "   - All configs and secrets"
    echo ""

    # Delete the namespace (this cascades to all resources)
    kubectl delete namespace urlshortener --wait=true --timeout=120s || true

    echo ""
    echo "✅ Cleanup complete!"
    echo ""
    echo "All resources have been removed from Kubernetes"
else
    echo ""
    echo "Namespace 'urlshortener' not found - nothing to clean up"
    echo "✅ Done"
fi
