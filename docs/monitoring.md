# Monitoring & Observability Guide

## Overview

This guide covers the monitoring, logging, and observability setup for the Valhalla routing platform on AWS EKS.

---

## Monitoring Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Monitoring Stack                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────┐      ┌──────────────┐    ┌─────────────┐ │
│  │  Valhalla   │─────▶│  Prometheus  │───▶│   Grafana   │ │
│  │   Pods      │      │   Metrics    │    │  Dashboards │ │
│  └─────────────┘      └──────────────┘    └─────────────┘ │
│         │                                                   │
│         │                                                   │
│         ▼                                                   │
│  ┌─────────────┐      ┌──────────────┐    ┌─────────────┐ │
│  │ K8s Health  │─────▶│  CloudWatch  │───▶│   Alarms    │ │
│  │   Probes    │      │     Logs     │    │             │ │
│  └─────────────┘      └──────────────┘    └─────────────┘ │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Current Monitoring Capabilities

### 1. Health Checks ✅ **IMPLEMENTED**

**Kubernetes Health Probes:**

```yaml
livenessProbe:
  httpGet:
    path: /status
    port: 8002
  initialDelaySeconds: 60
  timeoutSeconds: 5
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /status
    port: 8002
  initialDelaySeconds: 30
  timeoutSeconds: 5
  periodSeconds: 5
  failureThreshold: 3
```

**What it monitors:**
- Pod health and availability
- Valhalla service responsiveness
- Routing engine status

**Actions:**
- Liveness failure → Pod restart
- Readiness failure → Remove from service endpoints

### 2. Prometheus Metrics ✅ **AVAILABLE**

**Metrics Endpoint:**
```
GET http://<valhalla-url>:8002/metrics
```

**Built-in Valhalla Metrics:**
- Request count
- Request duration
- Response status codes
- Active connections
- Routing calculations

**Pod Annotations:**
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8002"
  prometheus.io/path: "/metrics"
```

### 3. Kubernetes Metrics ✅ **IMPLEMENTED**

**Metrics Server:**
- Installed and operational
- Provides CPU and memory metrics
- Powers HorizontalPodAutoscaler

**Check metrics:**
```bash
kubectl top pods -n valhalla
kubectl top nodes
```

**HPA Metrics:**
```yaml
metrics:
- type: Resource
  resource:
    name: cpu
    target:
      type: Utilization
      averageUtilization: 70
- type: Resource
  resource:
    name: memory
    target:
      type: Utilization
      averageUtilization: 80
```

### 4. CloudWatch Integration ✅ **CONFIGURED**

**EKS Control Plane Logs:**
- API server logs
- Audit logs
- Authenticator logs
- Controller manager logs
- Scheduler logs

**Container Logs:**
- Automatically sent to CloudWatch Logs
- Log group: `/aws/eks/<cluster-name>/cluster`
- Retention: Configurable (default 7 days)

**View logs:**
```bash
# Via kubectl
kubectl logs -n valhalla <pod-name> -c valhalla --tail=100 -f

# Via AWS CLI
aws logs tail /aws/eks/valhalla-dev-cluster/cluster --follow
```

---

## Monitoring Metrics Reference

### Application Metrics

| Metric | Description | Type | Alert Threshold |
|--------|-------------|------|----------------|
| `valhalla_requests_total` | Total routing requests | Counter | - |
| `valhalla_request_duration_seconds` | Request latency | Histogram | p95 > 2s |
| `valhalla_errors_total` | Total errors | Counter | > 100/min |
| `valhalla_route_calculations` | Routes calculated | Counter | - |
| `valhalla_cache_hits` | Tile cache hits | Counter | Hit rate < 80% |

### Infrastructure Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|----------------|
| `container_cpu_usage_seconds` | CPU usage | > 80% |
| `container_memory_usage_bytes` | Memory usage | > 85% |
| `kube_pod_status_ready` | Pod readiness | < 2 pods |
| `kube_pod_container_status_restarts_total` | Container restarts | > 5/hour |

### Custom KPIs

| KPI | Target | Measurement |
|-----|--------|-------------|
| **Availability** | 99.9% | Uptime monitoring |
| **Latency (p95)** | < 200ms | Request duration |
| **Latency (p99)** | < 500ms | Request duration |
| **Error Rate** | < 1% | Failed requests / Total |
| **Success Rate** | > 99% | 2xx responses / Total |

---

## Monitoring Setup Options

### Option 1: CloudWatch Only (Current) ✅

**What's included:**
- EKS control plane logs
- Container logs
- Basic metrics via Container Insights

**Pros:**
- No additional setup required
- Native AWS integration
- Built-in alerting

**Cons:**
- Limited query capabilities
- Higher cost for large volumes
- Less flexible dashboards

**Enable Container Insights:**
```bash
aws eks update-cluster-config \
  --region us-east-1 \
  --name valhalla-dev-cluster \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'
```

### Option 2: Prometheus + Grafana (Recommended for Production)

**Architecture:**
```
Valhalla Pods → Prometheus → Grafana
      ↓              ↓
  Metrics     Alert Manager → PagerDuty/Slack
```

**Install Prometheus Stack:**
```bash
# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```

**Benefits:**
- Rich query language (PromQL)
- Beautiful Grafana dashboards
- Flexible alerting rules
- Long-term metrics retention
- Community dashboards available

### Option 3: Hybrid Approach

**Combination:**
- Prometheus for metrics and alerting
- CloudWatch for log aggregation
- Grafana for visualization
- X-Ray for distributed tracing (optional)

---

## Alerting Strategy

### Critical Alerts (Page On-Call)

```yaml
# Prometheus Alert Rules
groups:
- name: valhalla_critical
  interval: 30s
  rules:
  
  # Pod availability
  - alert: ValhallaPodDown
    expr: sum(kube_pod_status_ready{namespace="valhalla"}) < 2
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Less than 2 Valhalla pods available"
      
  # High error rate
  - alert: HighErrorRate
    expr: rate(valhalla_errors_total[5m]) > 10
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "High error rate detected"
      
  # High latency
  - alert: HighLatency
    expr: histogram_quantile(0.95, valhalla_request_duration_seconds) > 2
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "P95 latency exceeds 2 seconds"
```

### Warning Alerts (Email/Slack)

```yaml
  # High memory usage
  - alert: HighMemoryUsage
    expr: container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.85
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "Pod memory usage above 85%"
      
  # Approaching pod limit
  - alert: ApproachingPodLimit
    expr: sum(kube_pod_status_ready{namespace="valhalla"}) < 3
    for: 15m
    labels:
      severity: warning
```

### CloudWatch Alarms

```bash
# Create alarm for pod count
aws cloudwatch put-metric-alarm \
  --alarm-name valhalla-pod-count-low \
  --alarm-description "Alert when running pod count is low" \
  --metric-name pod_count \
  --namespace AWS/EKS \
  --statistic Average \
  --period 300 \
  --threshold 2 \
  --comparison-operator LessThanThreshold \
  --evaluation-periods 2
```

---

## Dashboards

### Grafana Dashboard JSON

**Valhalla Overview Dashboard:**

```json
{
  "dashboard": {
    "title": "Valhalla Routing Engine",
    "panels": [
      {
        "title": "Request Rate",
        "targets": [{
          "expr": "rate(valhalla_requests_total[5m])"
        }]
      },
      {
        "title": "Latency (P95, P99)",
        "targets": [
          {"expr": "histogram_quantile(0.95, valhalla_request_duration_seconds)"},
          {"expr": "histogram_quantile(0.99, valhalla_request_duration_seconds)"}
        ]
      },
      {
        "title": "Error Rate",
        "targets": [{
          "expr": "rate(valhalla_errors_total[5m])"
        }]
      },
      {
        "title": "Pod CPU Usage",
        "targets": [{
          "expr": "rate(container_cpu_usage_seconds_total{namespace='valhalla'}[5m])"
        }]
      },
      {
        "title": "Pod Memory Usage",
        "targets": [{
          "expr": "container_memory_usage_bytes{namespace='valhalla'}"
        }]
      }
    ]
  }
}
```

**Import Community Dashboards:**
- Kubernetes Cluster Monitoring: Dashboard ID **7249**
- Kubernetes Pod Monitoring: Dashboard ID **6417**
- Node Exporter Full: Dashboard ID **1860**

### CloudWatch Dashboard

Create via AWS Console or CLI:

```bash
aws cloudwatch put-dashboard \
  --dashboard-name valhalla-monitoring \
  --dashboard-body file://cloudwatch-dashboard.json
```

---

## Log Aggregation

### Current Setup

**Log Sources:**
1. EKS Control Plane → CloudWatch Logs
2. Container stdout/stderr → CloudWatch Logs
3. Application logs → CloudWatch Logs

**Log Groups:**
- `/aws/eks/valhalla-dev-cluster/cluster`
- `/aws/containerinsights/valhalla-dev-cluster/application`

### Query Logs

**CloudWatch Insights:**
```sql
# Find errors in last hour
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100

# Request latency analysis
fields @timestamp, request_duration
| filter @message like /routing request/
| stats avg(request_duration), max(request_duration), min(request_duration) by bin(5m)
```

**kubectl logs:**
```bash
# Real-time logs
kubectl logs -n valhalla -l app=valhalla-api -f

# Last 100 lines
kubectl logs -n valhalla <pod-name> --tail=100

# Previous container (after crash)
kubectl logs -n valhalla <pod-name> --previous
```

### Enhanced Logging (Optional)

**FluentBit for Log Forwarding:**

```yaml
# Install FluentBit
helm install fluent-bit fluent/fluent-bit \
  --namespace logging \
  --set outputs.cloudWatch.enabled=true \
  --set outputs.cloudWatch.region=us-east-1
```

---

## Distributed Tracing (Optional)

### AWS X-Ray Integration

**Enable X-Ray:**

1. Install X-Ray daemon as DaemonSet
2. Add X-Ray SDK to application
3. Configure IAM permissions

**Benefits:**
- Request flow visualization
- Performance bottleneck identification
- Service dependency mapping

```bash
# Install X-Ray DaemonSet
kubectl apply -f https://eksworkshop.com/intermediate/245_x-ray/daemonset.files/xray-k8s-daemonset.yaml
```

---

## Monitoring Checklist

### Daily Checks
- [ ] Check pod health: `kubectl get pods -n valhalla`
- [ ] Review error rate in last 24h
- [ ] Check HPA scaling events
- [ ] Review CloudWatch alarms

### Weekly Checks
- [ ] Review latency trends
- [ ] Check resource utilization
- [ ] Review cost metrics
- [ ] Update dashboards if needed

### Monthly Reviews
- [ ] SLO/SLA compliance review
- [ ] Capacity planning
- [ ] Alert rule effectiveness
- [ ] Dashboard optimization

---

## Troubleshooting Guide

### High Latency

**Check:**
1. Pod CPU/memory usage
2. Number of running pods
3. Tile cache effectiveness
4. Network latency

**Fix:**
```bash
# Scale up
kubectl scale deployment valhalla-api -n valhalla --replicas=6

# Check HPA
kubectl get hpa -n valhalla

# Review metrics
kubectl top pods -n valhalla
```

### High Error Rate

**Investigate:**
```bash
# Get recent logs
kubectl logs -n valhalla -l app=valhalla-api --tail=200 | grep ERROR

# Check pod events
kubectl describe pod -n valhalla <pod-name>

# Test endpoint
curl http://<lb-url>/status
```

### Pod Crashes

**Debug:**
```bash
# Get crash logs
kubectl logs -n valhalla <pod-name> --previous

# Check events
kubectl get events -n valhalla --sort-by='.lastTimestamp'

# Describe pod
kubectl describe pod -n valhalla <pod-name>
```

---

## Quick Commands Reference

```bash
# View all monitoring resources
kubectl get all -n valhalla
kubectl top pods -n valhalla
kubectl top nodes

# Check HPA status
kubectl get hpa -n valhalla
kubectl describe hpa valhalla-api -n valhalla

# View logs
kubectl logs -n valhalla -l app=valhalla-api -f
kubectl logs -n valhalla <pod-name> --tail=100

# Check metrics endpoint
kubectl port-forward -n valhalla svc/valhalla-api 8002:80
curl http://localhost:8002/metrics

# CloudWatch logs
aws logs tail /aws/eks/valhalla-dev-cluster/cluster --follow

# Prometheus queries (if installed)
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Visit http://localhost:9090
```

---

## Next Steps

### Immediate (Production Readiness)
1. ✅ Health checks configured
2. ✅ Metrics endpoints available
3. ✅ CloudWatch logging enabled
4. → Set up CloudWatch alarms
5. → Create basic dashboards

### Short-term (1-2 weeks)
1. Install Prometheus + Grafana stack
2. Configure alert rules
3. Create custom dashboards
4. Set up PagerDuty/Slack integration
5. Document runbooks

### Long-term (1-3 months)
1. Implement distributed tracing
2. Set up log aggregation pipeline
3. Create SLO/SLI tracking
4. Automated anomaly detection
5. Cost optimization based on metrics

---

## Monitoring Costs

**CloudWatch (Current):**
- Logs: ~$0.50/GB ingested
- Metrics: ~$0.30/metric/month
- Alarms: $0.10/alarm/month
- **Estimated:** $50-100/month

**Prometheus + Grafana (Self-hosted):**
- EC2/EKS resources: ~$100-200/month
- Storage: ~$20/month
- **Estimated:** $120-220/month

**Managed Prometheus (AMP):**
- Metric samples: $0.30/million samples
- Query: $0.01/million samples
- **Estimated:** $80-150/month

---

## Support & Documentation

**AWS Documentation:**
- [EKS Observability](https://docs.aws.amazon.com/eks/latest/userguide/eks-observe.html)
- [Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html)

**Prometheus:**
- [Prometheus Docs](https://prometheus.io/docs/)
- [Kubernetes Monitoring](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#kubernetes_sd_config)

**Grafana:**
- [Grafana Docs](https://grafana.com/docs/)
- [Dashboard Gallery](https://grafana.com/grafana/dashboards/)

---

**Status:** Monitoring infrastructure ready for production deployment
**Last Updated:** January 16, 2026
