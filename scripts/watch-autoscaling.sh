#!/bin/bash

# watch-autoscaling.sh - Watch KEDA ScaledObject and pods during autoscaling

echo "Watching Autoscaling (Press Ctrl+C to stop)"
echo ""

# Function to cleanup on exit
cleanup() {
    kill $SCALEDOBJECT_PID $HPA_PID $PODS_PID $METRICS_PID 2>/dev/null
    exit
}
trap cleanup INT TERM

# Watch ScaledObject in background
kubectl get scaledobject worker-scaler -n urlshortener -w &
SCALEDOBJECT_PID=$!

# Watch HPA (created by KEDA) in background
kubectl get hpa -n urlshortener -l scaledobject.keda.sh/name=worker-scaler -w &
HPA_PID=$!

# Watch pods in background
kubectl get pods -n urlshortener -l app=worker -w &
PODS_PID=$!

# Watch metrics every 5 seconds
while true; do
    clear
    echo "Autoscaling Monitor (Refreshing every 5s)"
    echo "=========================================="
    echo ""
    echo "KEDA ScaledObject Status:"
    kubectl get scaledobject worker-scaler -n urlshortener
    echo ""
    echo "HPA Status (created by KEDA):"
    kubectl get hpa -n urlshortener -l scaledobject.keda.sh/name=worker-scaler
    echo ""
    echo "Worker Pods:"
    kubectl get pods -n urlshortener -l app=worker
    echo ""
    echo "CPU Usage:"
    kubectl top pods -n urlshortener -l app=worker 2>/dev/null || echo "Metrics collecting..."
    echo ""
    echo "Press Ctrl+C to stop"
    sleep 5
done
