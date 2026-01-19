#!/bin/bash

# verify.sh - Verify URL Shortener deployment is working

set -e

echo "Verifying URL Shortener Deployment"
echo ""

# Check all pods are running
echo "1. Checking Pod Status..."
PODS_NOT_READY=$(kubectl get pods -n urlshortener --no-headers | grep -v "Running" | grep -v "Completed" | wc -l | tr -d ' ')

if [ "$PODS_NOT_READY" -eq 0 ]; then
    echo "   ✅ All pods are running"
    kubectl get pods -n urlshortener
else
    echo "   ❌ Some pods are not ready:"
    kubectl get pods -n urlshortener | grep -v "Running" | grep -v "Completed"
    exit 1
fi

echo ""
echo "2. Checking Services..."
SERVICES=$(kubectl get svc -n urlshortener --no-headers | wc -l | tr -d ' ')
echo "   ✓ Found $SERVICES services"

echo ""
echo "3. Testing API Health..."
if curl -s http://localhost:8080/health > /dev/null; then
    echo "   ✓ API health check passed"
    curl -s http://localhost:8080/health | jq . || echo "   (Response: $(curl -s http://localhost:8080/health))"
else
    echo "   ❌ API health check failed - is port-forward running?"
    echo "   Run: kubectl port-forward -n urlshortener service/api-service 8080:80"
fi

echo ""
echo "4. Testing API Readiness..."
if curl -s http://localhost:8080/ready > /dev/null; then
    echo "   ✓ API readiness check passed"
else
    echo "   ⚠️  API readiness check failed (may need a moment to connect to DB)"
fi

echo ""
echo "5. Testing URL Shortening..."
RESPONSE=$(curl -s -X POST http://localhost:8080/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://www.example.com/test"}')

if echo "$RESPONSE" | grep -q "short_url"; then
    echo "   ✅ URL shortening works!"
    SHORT_CODE=$(echo "$RESPONSE" | jq -r '.short_code' 2>/dev/null || echo "$RESPONSE" | grep -o '"short_code":"[^"]*"' | cut -d'"' -f4)
    echo "   Created short code: $SHORT_CODE"

    # Test stats endpoint
    echo ""
    echo "6. Testing Stats Endpoint..."
    if curl -s "http://localhost:8080/stats/$SHORT_CODE" > /dev/null; then
        echo "   ✓ Stats endpoint works"
    else
        echo "   ⚠️  Stats endpoint failed (may need jobs to process first)"
    fi
else
    echo "   ❌ URL shortening failed"
    echo "   Response: $RESPONSE"
fi

echo ""
echo "7. Checking Worker Job Processing..."
WORKER_LOGS=$(kubectl logs -n urlshortener -l app=worker --tail=5 2>/dev/null | grep -i "processing\|completed\|error" | tail -3)
if [ -n "$WORKER_LOGS" ]; then
    echo "   ✓ Workers are processing jobs:"
    echo "$WORKER_LOGS" | sed 's/^/      /'
else
    echo "   ⚠️  No recent worker activity (may be normal if queue is empty)"
fi

echo ""
echo "8. Checking Prometheus Targets..."
PROM_TARGETS=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq -r '.data.activeTargets[] | select(.health=="up") | .labels.job' 2>/dev/null | wc -l | tr -d ' ')
if [ -n "$PROM_TARGETS" ] && [ "$PROM_TARGETS" -gt 0 ]; then
    echo "   ✓ Prometheus has $PROM_TARGETS active targets"
else
    echo "   ⚠️  Check Prometheus targets at http://localhost:9090/targets"
fi

echo ""
echo "9. Checking Metrics Endpoints..."
if curl -s http://localhost:8080/metrics > /dev/null 2>&1; then
    METRIC_COUNT=$(curl -s http://localhost:8080/metrics | grep -c "^http_requests_total" || echo "0")
    echo "   ✓ API metrics endpoint working ($METRIC_COUNT http_requests_total metrics found)"
else
    echo "   ❌ API metrics endpoint not accessible"
fi

echo ""
echo "10. Checking Autoscaling (KEDA)..."
if kubectl get scaledobject worker-scaler -n urlshortener &> /dev/null; then
    SCALEDOBJECT_STATUS=$(kubectl get scaledobject worker-scaler -n urlshortener -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [ "$SCALEDOBJECT_STATUS" = "True" ]; then
        echo "   ✓ KEDA ScaledObject is ready"
        QUEUE_LENGTH=$(kubectl exec -n urlshortener deployment/redis -- redis-cli -a redispass LLEN job_queue 2>/dev/null | grep -v Warning | tr -d ' ' || echo "?")
        echo "   Current queue length: $QUEUE_LENGTH items"
    else
        echo "   ⚠️  KEDA ScaledObject status: $SCALEDOBJECT_STATUS"
    fi
else
    echo "   ⚠️  KEDA ScaledObject not found"
fi

echo ""
echo "Quick Summary:"
echo "   API:        http://localhost:8080"
echo "   Prometheus: http://localhost:9090"
echo "   Grafana:    http://localhost:3000 (admin/admin)"
echo ""
echo "✅ Verification complete!"
echo ""
echo "Next steps:"
echo "   - Generate load: for i in {1..20}; do curl -X POST http://localhost:8080/shorten -H 'Content-Type: application/json' -d '{\"url\": \"https://example.com/page'$i'\"}' & done; wait"
echo "   - Check Prometheus queries: rate(http_requests_total[5m])"
echo "   - View worker logs: kubectl logs -f -l app=worker -n urlshortener"
