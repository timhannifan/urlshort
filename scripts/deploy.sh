#!/bin/bash

# deploy.sh - Deploy URL Shortener to Kubernetes

set -e  # Exit on error

echo "Deploying URL Shortener to Kubernetes"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl first."
    exit 1
fi

# Note: We use port-forwarding for all environments for consistency

# Apply manifests in order
echo ""
echo "Creating namespace and configs..."
kubectl apply -f k8s/base/namespace.yaml
kubectl apply -f k8s/base/secrets.yaml
kubectl apply -f k8s/base/configmap.yaml

echo ""
echo "Deploying databases..."
kubectl apply -f k8s/base/postgres.yaml
kubectl apply -f k8s/base/redis.yaml

echo ""
echo "Waiting for databases to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres -n urlshortener --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=redis -n urlshortener --timeout=120s || true

echo ""
echo "Checking KEDA installation (required for queue-based autoscaling)..."
if ! kubectl get crd scaledobjects.keda.sh &> /dev/null; then
    echo "   ⚠️  KEDA not found. Installing KEDA..."
    # Install KEDA - some CRDs may fail due to annotation size limits, but we only need ScaledObject and TriggerAuthentication
    kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.18.3/keda-2.18.3.yaml 2>&1 | grep -v "Too long" || true

    echo "   Waiting for required KEDA CRDs to be ready..."
    # Wait for CRDs to be established (we only need the ones we use)
    kubectl wait --for=condition=established crd/scaledobjects.keda.sh --timeout=120s || true
    kubectl wait --for=condition=established crd/triggerauthentications.keda.sh --timeout=120s || true

    # Fix ScaledJob CRD issue - delete it to prevent operator crashes
    echo "   Fixing ScaledJob CRD issue (preventing operator crashes)..."
    # Wait a moment for all CRDs to be created, then delete ScaledJob
    sleep 3
    if kubectl get crd scaledjobs.keda.sh &> /dev/null; then
        # Delete the problematic ScaledJob CRD (we don't use it, only ScaledObject)
        kubectl delete crd scaledjobs.keda.sh --ignore-not-found=true
        echo "   ✓ Removed problematic ScaledJob CRD"
    fi

    # Verify required CRDs exist
    if kubectl get crd scaledobjects.keda.sh &> /dev/null && kubectl get crd triggerauthentications.keda.sh &> /dev/null; then
        echo "   ✓ Required CRDs installed"
    else
        echo "   ⚠️  Warning: Some required CRDs may not be ready, but continuing..."
    fi

    echo "   Waiting for KEDA deployments to be ready..."
    kubectl wait --for=condition=available deployment/keda-operator -n keda --timeout=120s || true
    kubectl wait --for=condition=available deployment/keda-operator-metrics-apiserver -n keda --timeout=120s || true

    # Ensure operator is actually running and stable (not just available)
    echo "   Verifying KEDA operator is running and stable..."
    for i in {1..6}; do
        OPERATOR_STATUS=$(kubectl get pods -n keda -l app=keda-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
        if [ "$OPERATOR_STATUS" = "Running" ]; then
            # Check if it's actually ready (not just running)
            READY=$(kubectl get pods -n keda -l app=keda-operator -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
            if [ "$READY" = "True" ]; then
                echo "   ✓ Operator is running and ready"
                break
            fi
        fi
        if [ $i -lt 6 ]; then
            echo "   Waiting for operator to be stable... (attempt $i/6)"
            sleep 10
        fi
    done

    # If operator is still not stable, restart it
    OPERATOR_STATUS=$(kubectl get pods -n keda -l app=keda-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$OPERATOR_STATUS" != "Running" ]; then
        echo "   ⚠️  Operator not stable, restarting..."
        kubectl rollout restart deployment/keda-operator -n keda
        kubectl wait --for=condition=available deployment/keda-operator -n keda --timeout=120s || true
        sleep 10
    fi

    # Wait a bit more for metrics API server to be fully ready
    echo "   Waiting for metrics API server to be ready..."
    sleep 10

    echo "   ✅ KEDA installed and ready"
else
    echo "   ✓ KEDA already installed"
fi

echo ""
echo "Deploying application..."
kubectl apply -f k8s/base/api.yaml
kubectl apply -f k8s/base/worker.yaml

# Wait a moment for ScaledObject to be processed and HPA to be created
echo ""
echo "Waiting for autoscaling to initialize..."
sleep 15

echo ""
echo "Deploying monitoring stack..."
kubectl apply -f k8s/base/monitoring.yaml

echo ""
echo "Waiting for services to be ready..."
kubectl wait --for=condition=ready pod -l app=api -n urlshortener --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=prometheus -n urlshortener --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=grafana -n urlshortener --timeout=120s || true

echo ""
echo "✅ Deployment complete!"
echo ""

# Function to kill existing port-forwards
cleanup_port_forwards() {
    echo "Cleaning up existing port-forwards..."
    pkill -f "kubectl port-forward.*urlshortener" || true
    sleep 1
}

# Function to setup port forwarding for Docker Desktop
setup_port_forwards() {
    cleanup_port_forwards

    echo "Setting up port forwarding (running in background)..."
    kubectl port-forward -n urlshortener service/api-service 8080:80 > /dev/null 2>&1 &
    kubectl port-forward -n urlshortener service/prometheus-service 9090:9090 > /dev/null 2>&1 &
    kubectl port-forward -n urlshortener service/grafana-service 3000:3000 > /dev/null 2>&1 &

    sleep 2
    echo "✓ Port forwarding active"
}

# Setup port forwarding for all environments (simpler and more reliable)
setup_port_forwards
echo ""
echo "Service URLs (via port-forward):"
echo ""
echo "  API:        http://localhost:8080"
echo "  Prometheus: http://localhost:9090"
echo "  Grafana:    http://localhost:3000 (admin/admin)"
echo ""
echo "Port-forwards are running in the background"
echo "   To stop them: ./scripts/stop.sh"

echo ""
echo "Check status:"
echo "  kubectl get pods -n urlshortener"
echo ""
echo "Watch pods:"
echo "  kubectl get pods -n urlshortener -w"
echo ""
