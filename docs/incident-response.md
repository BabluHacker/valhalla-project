# Production Incident Response Runbook

## Incident Scenario

**Time:** 02:37 AM  
**Symptoms:**
- ⚠️ Latency ↑ (increased response times)
- ⚠️ Error rate ↑ (more failures)
- ✅ Service still reachable (not complete outage)

**Severity:** **P1 - Critical** (degraded service impacting users)

---

## PHASE 1: First Response (0-5 minutes)

### Immediate Actions

**1. Acknowledge the Incident (30 seconds)**

```bash
# Check current time and start incident log
echo "INCIDENT START: $(date)" >> incident-log.txt
echo "症状: High latency, increased errors, service reachable" >> incident-log.txt
```

**2. Verify the Issue (2 minutes)**

```bash
# Check Valhalla service status
kubectl get pods -n valhalla
kubectl get svc -n valhalla

# Test public endpoint
export VALHALLA_URL="http://k8s-valhalla-valhalla-f7f06e7694-96790d154369cade.elb.us-east-1.amazonaws.com"
time curl -s $VALHALLA_URL/status | jq .

# Check multiple times to confirm pattern
for i in {1..5}; do
  echo "Test $i:"
  time curl -s -w "\nHTTP Status: %{http_code}\nTime: %{time_total}s\n" \
    $VALHALLA_URL/status -o /dev/null
  sleep 2
done
```

**Expected Results:**
- Normal: 100-200ms response time, 200 status
- **Problem**: 2-5s response time, occasional 503/504 errors

**3. Check HPA and Resource Metrics (1 minute)**

```bash
# Check auto-scaling status
kubectl get hpa -n valhalla

# Check pod resource usage
kubectl top pods -n valhalla

# Check node resource usage
kubectl top nodes
```

**4. Initial Communication (1 minute)**

**Slack #incidents channel:**
```
🚨 INCIDENT DECLARED - P1
Time: 02:37 AM
Service: Valhalla Routing API
Status: DEGRADED (not down)
Symptoms: 
  - Response time: 2-5s (normal: 100-200ms)
  - Error rate: ~15% (normal: <1%)
  - Service: Still reachable
On-call: @your-name
Investigating...
```

**Status Page Update:**
```
Investigating: We are currently investigating degraded performance 
on the Valhalla routing API. Some requests may experience slower 
response times or intermittent errors. We are actively working 
to resolve this issue.
```

---

## PHASE 2: Debugging & Diagnosis (5-15 minutes)

### Systematic Investigation

**Timeline:**
```
02:37 - Incident detected
02:38 - First responder online
02:40 - Initial diagnosis started
02:50 - Root cause identified (target)
```

### Step 1: Check Application Logs (2 minutes)

```bash
# Get recent logs from all pods
kubectl logs -n valhalla -l app=valhalla-api --tail=200 --timestamps

# Look for errors
kubectl logs -n valhalla -l app=valhalla-api --tail=500 | grep -i error

# Check for specific error patterns
kubectl logs -n valhalla -l app=valhalla-api --tail=500 | grep -E "(timeout|OOM|memory|killed)"
```

**Common Issues to Look For:**
- `OOMKilled` - Memory issues
- `Timeout` - Slow database/tile access
- `Connection refused` - Service connectivity
- `Tile not found` - Map data issues

### Step 2: Check Pod Status & Events (2 minutes)

```bash
# Detailed pod status
kubectl describe pods -n valhalla -l app=valhalla-api

# Recent events
kubectl get events -n valhalla --sort-by='.lastTimestamp' | tail -20

# Check for pod restarts
kubectl get pods -n valhalla -o json | \
  jq '.items[] | {name: .metadata.name, restarts: .status.containerStatuses[].restartCount}'
```

**Red Flags:**
- Frequent restarts → Memory leaks or crashes
- OOMKilled → Insufficient memory
- ImagePullBackOff → Image issues
- CrashLoopBackOff → Application crashes

### Step 3: Check Resource Utilization (2 minutes)

```bash
# CPU and Memory usage
kubectl top pods -n valhalla

# Check if approaching limits
kubectl get pods -n valhalla -o json | \
  jq '.items[] | {
    name: .metadata.name,
    cpu_request: .spec.containers[].resources.requests.cpu,
    cpu_limit: .spec.containers[].resources.limits.cpu,
    mem_request: .spec.containers[].resources.requests.memory,
    mem_limit: .spec.containers[].resources.limits.memory
  }'

# Check HPA scaling
kubectl describe hpa valhalla-api -n valhalla
```

**Thresholds:**
- CPU > 80% → Scaling needed
- Memory > 85% → Risk of OOMKill
- Disk I/O high → Tile access slow

### Step 4: Check Network & Load Balancer (2 minutes)

```bash
# Check LoadBalancer status
kubectl get svc valhalla-api-lb -n valhalla

# Check endpoints
kubectl get endpoints -n valhalla

# Test from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -s http://valhalla-api.valhalla.svc.cluster.local/status
```

### Step 5: Check PVC & Storage (2 minutes)

```bash
# Check PVC status
kubectl get pvc -n valhalla

# Check if disk is full
kubectl exec -n valhalla $(kubectl get pod -n valhalla -l app=valhalla-api -o jsonpath='{.items[0].metadata.name}') \
  -- df -h /custom_files

# Check tile access
kubectl exec -n valhalla $(kubectl get pod -n valhalla -l app=valhalla-api -o jsonpath='{.items[0].metadata.name}') \
  -- ls -lh /custom_files/valhalla_tiles/
```

### Step 6: Check Recent Changes (1 minute)

```bash
# Check recent deployments
kubectl rollout history deployment/valhalla-api -n valhalla

# Check recent config changes
kubectl get configmap -n valhalla valhalla-api-config -o yaml

# Git history
git log --oneline --since="24 hours ago"
```

---

## PHASE 3: Root Cause Analysis

### Common Scenarios & Solutions

### Scenario A: Memory Pressure (OOMKilled)

**Symptoms:**
- Pods restarting frequently
- OOMKilled in events
- Memory usage > 85%

**Root Cause:**
- Memory limits too low
- Memory leak in application
- Large tile files loading into memory

**Immediate Fix:**
```bash
# Increase memory limits
kubectl patch deployment valhalla-api -n valhalla --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/limits/memory",
    "value": "4Gi"
  }
]'

# Wait for rollout
kubectl rollout status deployment/valhalla-api -n valhalla
```

**Verification:**
```bash
# Monitor memory after fix
watch kubectl top pods -n valhalla
```

### Scenario B: CPU Saturation

**Symptoms:**
- CPU usage > 90%
- Slow response times
- HPA not scaling fast enough

**Root Cause:**
- Traffic spike
- Expensive routing calculations
- Insufficient replicas

**Immediate Fix:**
```bash
# Manual scale up
kubectl scale deployment valhalla-api -n valhalla --replicas=10

# Verify scaling
kubectl get pods -n valhalla

# Or adjust HPA
kubectl patch hpa valhalla-api -n valhalla --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/maxReplicas",
    "value": 30
  },
  {
    "op": "replace",
    "path": "/spec/metrics/0/resource/target/averageUtilization",
    "value": 60
  }
]'
```

### Scenario C: Tile Access Slowdown

**Symptoms:**
- Slow responses only for routing requests
- `/status` fast, `/route` slow
- High disk I/O

**Root Cause:**
- PVC performance degraded
- Tile cache misses
- Corrupted tiles

**Immediate Fix:**
```bash
# Check tile integrity
kubectl exec -n valhalla $(kubectl get pod -n valhalla -l app=valhalla-api -o jsonpath='{.items[0].metadata.name}') \
  -- ls -lh /custom_files/valhalla_tiles/ | head -20

# Restart pods to reload tiles
kubectl rollout restart deployment/valhalla-api -n valhalla
```

### Scenario D: Network Issues

**Symptoms:**
- Timeout errors
- Connection refused
- LoadBalancer issues

**Root Cause:**
- LB health check failures
- Security group changes
- DNS issues

**Immediate Fix:**
```bash
# Check LB health
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names k8s-valhalla-valhalla* \
    --query 'TargetGroups[0].TargetGroupArn' --output text)

# Check service endpoints
kubectl describe svc valhalla-api-lb -n valhalla
```

---

## PHASE 4: Communication Strategy

### Internal Communication

**02:40 - Initial Update (3 min after detection)**

**Slack #incidents:**
```
📊 INCIDENT UPDATE
Time: 02:40 AM (+3min)
Status: INVESTIGATING

Current findings:
✅ All 3 pods running
✅ LoadBalancer healthy
⚠️ CPU usage: 85% (high)
⚠️ Memory usage: 78% (elevated)
⚠️ Response time: 3.2s avg

Theory: CPU saturation due to traffic spike
Action: Scaling from 3 to 10 replicas
ETA: 2 minutes
```

**02:45 - Progress Update**

```
📈 INCIDENT UPDATE
Time: 02:45 AM (+8min)
Status: MITIGATING

Actions taken:
✅ Scaled to 10 replicas (was 3)
✅ New pods healthy: 10/10 Running
✅ CPU usage dropping: 45% (was 85%)

Metrics improving:
• Response time: 1.2s (was 3.2s)
• Error rate: 5% (was 15%)

Observation period: 5 minutes
```

**02:52 - Resolution**

```
✅ INCIDENT RESOLVED
Time: 02:52 AM (+15min)
Duration: 15 minutes

Final status:
✅ Response time: 180ms (normal)
✅ Error rate: 0.5% (normal)
✅ All 10 replicas healthy

Root cause: CPU saturation from traffic spike
Fix: Scaled from 3 to 10 replicas
Impact: ~15min of degraded service (2-5s latency)

Post-mortem: Scheduled for tomorrow 3PM
```

### External Communication

**Status Page Updates:**

**02:40 - Investigating:**
```
We are experiencing elevated response times on the routing API. 
Our team is actively investigating and implementing fixes.
Current status: Degraded Performance
```

**02:45 - Identified:**
```
We have identified the cause as increased load and are scaling 
our infrastructure to handle the traffic. 
Performance is improving.
Current status: Degraded Performance (improving)
```

**02:52 - Resolved:**
```
The issue has been resolved. All systems are operating normally. 
We apologize for any inconvenience and are implementing 
improvements to prevent recurrence.
Current status: Operational
```

### Stakeholder Communication

**Email to Management (next morning):**

```
Subject: Incident Summary - Valhalla API Degradation (Jan 16, 02:37-02:52)

Summary:
On January 16 at 02:37 AM, we experienced a 15-minute degradation 
of the Valhalla routing API due to CPU saturation from a traffic spike.

Impact:
- Duration: 15 minutes
- Severity: Service degraded (not down)
- User Impact: Slower responses (2-5s vs normal 200ms)
- Affected Requests: ~1,500 requests

Response:
- Detection: 02:37 (automated monitoring)
- Response: 02:38 (on-call engaged)
- Mitigation: 02:45 (scaled infrastructure)
- Resolution: 02:52 (service restored)

Root Cause:
Traffic spike exceeded capacity of 3 replicas, causing CPU saturation.

Immediate Fix:
Scaled from 3 to 10 replicas.

Long-term Improvements:
See "Long-term Fixes" section below.
```

---

## PHASE 5: Long-Term Fixes

### Immediate Improvements (This Week)

**1. Adjust HPA Configuration**

**Problem:** HPA too conservative, scaling too slowly

**Fix:**
```yaml
# k8s/base/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: valhalla-api
spec:
  minReplicas: 5          # Was: 3 → Increase baseline
  maxReplicas: 30         # Was: 20 → Allow more headroom
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60  # Was: 70 → Scale earlier
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 70  # Was: 80 → More aggressive
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 30  # Faster scale-up
      policies:
      - type: Percent
        value: 100    # Double pods immediately
        periodSeconds: 30
      - type: Pods
        value: 5      # Or add 5 pods
        periodSeconds: 30
      selectPolicy: Max
    scaleDown:
      stabilizationWindowSeconds: 300  # Slower scale-down
      policies:
      - type: Percent
        value: 10     # Remove 10% at a time
        periodSeconds: 60
```

**2. Implement Pod Disruption Budget**

Already exists but verify:
```bash
kubectl get pdb -n valhalla
kubectl describe pdb valhalla-api -n valhalla
```

**3. Add Resource Requests/Limits**

Review and adjust:
```yaml
resources:
  requests:
    cpu: 500m      # Guarantee
    memory: 1Gi
  limits:
    cpu: 2000m     # Allow bursting
    memory: 4Gi    # Prevent OOM
```

### Medium-Term Improvements (This Month)

**1. Implement Proactive Monitoring & Alerting**

**CloudWatch Alarms:**
```bash
# High latency alarm
aws cloudwatch put-metric-alarm \
  --alarm-name valhalla-high-latency \
  --alarm-description "Alert when p95 latency > 1s" \
  --metric-name ResponseTime \
  --namespace Valhalla \
  --statistic Average \
  --period 60 \
  --threshold 1000 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions arn:aws:sns:us-east-1:ACCOUNT:valhalla-alerts

# High error rate alarm
aws cloudwatch put-metric-alarm \
  --alarm-name valhalla-high-errors \
  --alarm-description "Alert when error rate > 5%" \
  --metric-name ErrorRate \
  --namespace Valhalla \
  --statistic Average \
  --period 60 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions arn:aws:sns:us-east-1:ACCOUNT:valhalla-alerts
```

**Prometheus Alert Rules:**
```yaml
# prometheus-rules.yaml
groups:
- name: valhalla_alerts
  interval: 30s
  rules:
  - alert: HighLatency
    expr: histogram_quantile(0.95, valhalla_request_duration_seconds) > 1
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High latency detected"
      description: "P95 latency is {{ $value }}s"
      
  - alert: HighErrorRate
    expr: rate(valhalla_errors_total[5m]) / rate(valhalla_requests_total[5m]) > 0.05
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "High error rate detected"
      description: "Error rate is {{ $value | humanizePercentage }}"
      
  - alert: PodCPUHigh
    expr: rate(container_cpu_usage_seconds_total{namespace="valhalla"}[5m]) > 0.8
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Pod CPU usage high"
```

**2. Implement Caching Layer**

Add Redis for route caching:
```yaml
# k8s/base/redis-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        resources:
          limits:
            memory: 256Mi
            cpu: 250m
```

**3. Add Load Testing**

Implement regular load tests:
```bash
# Install k6
brew install k6

# Create load test script
cat > valhalla-load-test.js << 'EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 100 },  // Ramp up
    { duration: '5m', target: 100 },  // Sustain
    { duration: '2m', target: 200 },  // Spike
    { duration: '5m', target: 200 },  // Sustain spike
    { duration: '2m', target: 0 },     // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<1000'],  // 95% under 1s
    http_req_failed: ['rate<0.01'],     // <1% errors
  },
};

export default function () {
  const res = http.post(
    'http://VALHALLA_URL/route',
    JSON.stringify({
      locations: [
        {lat: 43.7384, lon: 7.4246},
        {lat: 43.7311, lon: 7.4197}
      ],
      costing: 'auto'
    }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 1s': (r) => r.timings.duration < 1000,
  });
  
  sleep(1);
}
EOF

# Run test
k6 run valhalla-load-test.js
```

### Long-Term Improvements (This Quarter)

**1. Multi-Region Deployment**

- Deploy to multiple AWS regions
- Use Route53 geo-routing
- Distribute load geographically

**2. Advanced Auto-Scaling**

Implement KEDA (Kubernetes Event Driven Autoscaling):
```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: valhalla-scaler
spec:
  scaleTargetRef:
    name: valhalla-api
  minReplicaCount: 5
  maxReplicaCount: 50
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus:9090
      metricName: valhalla_requests_per_second
      threshold: '100'
      query: rate(valhalla_requests_total[1m])
```

**3. Implement Circuit Breaker**

Use Istio or similar:
```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: valhalla-circuit-breaker
spec:
  host: valhalla-api
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
```

**4. Chaos Engineering**

Regular chaos tests:
```bash
# Install chaos mesh
helm install chaos-mesh chaos-mesh/chaos-mesh

# Pod chaos test
kubectl apply -f - <<EOF
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: valhalla-pod-failure
spec:
  action: pod-kill
  mode: one
  selector:
    namespaces:
      - valhalla
    labelSelectors:
      app: valhalla-api
  scheduler:
    cron: '@weekly'
EOF
```

---

## Post-Incident Review

### Incident Timeline

| Time | Action | Duration |
|------|--------|----------|
| 02:37 | Incident detected (monitoring alert) | 0m |
| 02:38 | On-call acknowledged | +1m |
| 02:40 | Root cause identified (CPU saturation) | +3m |
| 02:43 | Mitigation started (scaling) | +6m |
| 02:45 | Metrics improving | +8m |
| 02:52 | Incident resolved | +15m |

### What Went Well ✅

- Automated monitoring detected issue quickly
- On-call responded within 1 minute
- Root cause identified in 3 minutes
- Clear communication to stakeholders
- Service never completely down

### What Could Be Improved ⚠️

- HPA too conservative, should have scaled earlier
- Minimum replicas too low (3 → should be 5)
- No proactive alerting before degradation
- No load testing identified this scenario
- Manual scaling required (should be automatic)

### Action Items

| Priority | Action | Owner | Due Date | Status |
|----------|--------|-------|----------|--------|
| P0 | Increase min replicas to 5 | DevOps | This week | ✅ Done |
| P0 | Lower HPA CPU threshold to 60% | DevOps | This week | ✅ Done |
| P1 | Implement CloudWatch alarms | DevOps | Next week | 🔄 In Progress |
| P1 | Add Prometheus alerting | DevOps | Next week | 📝 Planned |
| P2 | Regular load testing | QA | This month | 📝 Planned |
| P2 | Implement caching layer | Engineering | This month | 📝 Planned |
| P3 | Multi-region deployment | Architecture | This quarter | 📝 Planned |

---

## Quick Reference Card

**Print this and keep near your desk!**

### Incident Response Checklist

**☐ 1. ACKNOWLEDGE (30 sec)**
- [ ] Note time and symptoms
- [ ] Start incident log

**☐ 2. VERIFY (2 min)**
- [ ] Test endpoint: `curl $VALHALLA_URL/status`
- [ ] Check pods: `kubectl get pods -n valhalla`
- [ ] Check metrics: `kubectl top pods -n valhalla`

**☐ 3. COMMUNICATE (1 min)**
- [ ] Post to #incidents Slack
- [ ] Update status page
- [ ] Page backup if needed

**☐ 4. DIAGNOSE (10 min)**
- [ ] Check logs: `kubectl logs -n valhalla -l app=valhalla-api --tail=200`
- [ ] Check events: `kubectl get events -n valhalla --sort-by='.lastTimestamp'`
- [ ] Check resources: `kubectl describe pods -n valhalla`

**☐ 5. MITIGATE (5 min)**
- [ ] Scale if needed: `kubectl scale deployment valhalla-api -n valhalla --replicas=10`
- [ ] Restart if needed: `kubectl rollout restart deployment/valhalla-api -n valhalla`
- [ ] Update communication

**☐ 6. VERIFY FIX (5 min)**
- [ ] Test endpoint again
- [ ] Monitor for 5 minutes
- [ ] Confirm metrics normal

**☐ 7. RESOLVE**
- [ ] Update #incidents
- [ ] Update status page
- [ ] Schedule post-mortem

### Key Commands

```bash
# Quick health check
kubectl get all -n valhalla && kubectl top pods -n valhalla

# Emergency scale
kubectl scale deployment valhalla-api -n valhalla --replicas=10

# Emergency restart
kubectl rollout restart deployment/valhalla-api -n valhalla

# Watch recovery
watch kubectl get pods -n valhalla
```

### Escalation Contacts

- L1: On-call engineer (PagerDuty)
- L2: DevOps Lead (+1-XXX-XXX-XXXX)
- L3: Engineering Manager (+1-XXX-XXX-XXXX)
- L4: CTO (critical only, +1-XXX-XXX-XXXX)

---

**Document Version:** 1.0  
**Last Updated:** January 16, 2026  
**Next Review:** February 2026  
**Owner:** DevOps Team
