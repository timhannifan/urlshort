#!/bin/bash

# test-autoscaling.sh - Generate load to test HPA autoscaling

set -e

echo "Testing Autoscaling"
echo ""
echo "This will generate load to trigger worker autoscaling"
echo ""

# Check KEDA ScaledObject and HPA status
echo "Current Autoscaling Status:"
echo "KEDA ScaledObject:"
kubectl get scaledobject worker-scaler -n urlshortener
echo ""
echo "HPA (created by KEDA):"
kubectl get hpa -n urlshortener -l scaledobject.keda.sh/name=worker-scaler
echo ""

# Get current replica count
CURRENT_REPLICAS=$(kubectl get deployment worker -n urlshortener -o jsonpath='{.spec.replicas}')
echo "Current worker replicas: $CURRENT_REPLICAS"

# Check current queue length
echo ""
echo "Current Redis Queue Status:"
QUEUE_LENGTH=$(kubectl exec -n urlshortener deployment/redis -- redis-cli -a redispass LLEN job_queue 2>/dev/null || echo "0")
echo "   Current queue length: $QUEUE_LENGTH jobs"
echo "   Scaling threshold: 5 jobs per replica (need $((CURRENT_REPLICAS * 5)) jobs to scale)"
echo "   Each URL creates 3 jobs (QR code, screenshot, metadata)"
echo ""

# Ask for confirmation
read -p "Generate load? This will create 200 URLs (600 jobs) (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

echo ""
echo "Generating load (creating 200 URLs = 600 jobs)..."
echo "   This should create enough jobs in the queue to trigger scaling"
echo ""

# Generate load - create URLs quickly to build up the queue
for i in {1..200}; do
    curl -s -X POST http://localhost:8080/shorten \
      -H "Content-Type: application/json" \
      -d "{\"url\": \"https://example.com/load-test-$i-$(date +%s)\"}" > /dev/null 2>&1 &

    # Show progress every 25 requests
    if [ $((i % 25)) -eq 0 ]; then
        echo "   Created $i URLs ($((i * 3)) jobs queued)..."
        # Check queue length
        CURRENT_QUEUE=$(kubectl exec -n urlshortener deployment/redis -- redis-cli -a redispass LLEN job_queue 2>/dev/null || echo "0")
        echo "   Current queue length: $CURRENT_QUEUE jobs"
    fi
done

echo ""
echo "Waiting for requests to complete..."
wait

# Check final queue length
FINAL_QUEUE=$(kubectl exec -n urlshortener deployment/redis -- redis-cli -a redispass LLEN job_queue 2>/dev/null || echo "0")
echo ""
echo "✅ Load generation complete!"
echo "   Final queue length: $FINAL_QUEUE jobs"
echo "   Expected: ~600 jobs (200 URLs × 3 jobs each)"
echo ""
echo "Monitoring autoscaling (watch for 60 seconds)..."
echo "   Press Ctrl+C to stop watching"
echo ""

# Function to check queue length
check_queue() {
    kubectl exec -n urlshortener deployment/redis -- redis-cli -a redispass LLEN job_queue 2>/dev/null || echo "0"
}

# Watch ScaledObject, HPA and pods
kubectl get scaledobject worker-scaler -n urlshortener -w &
SCALEDOBJECT_PID=$!
kubectl get hpa -n urlshortener -l scaledobject.keda.sh/name=worker-scaler -w &
HPA_PID=$!

kubectl get pods -n urlshortener -l app=worker -w &
PODS_PID=$!

# Monitor queue length every 5 seconds
(
    for i in {1..12}; do
        sleep 5
        QUEUE_LEN=$(check_queue)
        REPLICAS=$(kubectl get deployment worker -n urlshortener -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")
        echo "   [$(date +%H:%M:%S)] Queue: $QUEUE_LEN jobs | Replicas: $REPLICAS"
    done
) &
QUEUE_MONITOR_PID=$!

# Wait for 60 seconds then kill background processes
sleep 60
kill $SCALEDOBJECT_PID $HPA_PID $PODS_PID $QUEUE_MONITOR_PID 2>/dev/null || true

echo ""
echo "Final Status:"
echo "KEDA ScaledObject:"
kubectl get scaledobject worker-scaler -n urlshortener
echo ""
echo "HPA:"
kubectl get hpa -n urlshortener -l scaledobject.keda.sh/name=worker-scaler
echo ""
echo "Worker Pods:"
kubectl get pods -n urlshortener -l app=worker
echo ""
FINAL_QUEUE=$(check_queue)
FINAL_REPLICAS=$(kubectl get deployment worker -n urlshortener -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")
echo "Queue Status:"
echo "   Queue length: $FINAL_QUEUE jobs"
echo "   Worker replicas: $FINAL_REPLICAS"
echo "   Threshold: 5 jobs per replica"
echo ""
echo "To continue watching:"
echo "   kubectl get scaledobject worker-scaler -n urlshortener -w"
echo "   kubectl get hpa -n urlshortener -l scaledobject.keda.sh/name=worker-scaler -w"
echo "   kubectl get pods -n urlshortener -l app=worker -w"
echo "   kubectl exec -n urlshortener deployment/redis -- redis-cli -a redispass LLEN job_queue"
