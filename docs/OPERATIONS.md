# Operations Guide

Complete guide for monitoring, troubleshooting, and maintaining the LiteLLM + OpenWebUI deployment on Amazon EKS.

---

## Table of Contents

- [Monitoring & Observability](#monitoring--observability)
- [Troubleshooting](#troubleshooting)
- [Maintenance Procedures](#maintenance-procedures)
- [Performance Tuning](#performance-tuning)
- [Cost Optimization](#cost-optimization)
- [Backup & Recovery](#backup--recovery)
- [Security Operations](#security-operations)

---

## Monitoring & Observability

### Prometheus Metrics

**Access Prometheus:**
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-kube-prome-prometheus 9090:9090
# Open: http://localhost:9090
```

#### LiteLLM Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `litellm_proxy_total_requests_metric` | Counter | Total requests by model, user, status |
| `litellm_proxy_failed_requests_metric` | Counter | Failed requests with exception details |
| `litellm_spend_metric` | Counter | Token spend by model/user |
| `litellm_total_tokens_metric` | Counter | Total tokens (input + output) |
| `litellm_request_total_latency_metric` | Histogram | Request latency percentiles |
| `litellm_llm_api_time_to_first_token_metric` | Histogram | Time to first token (streaming) |
| `litellm_deployment_state` | Gauge | Model health (0=healthy, 1=partial, 2=outage) |
| `litellm_redis_latency` | Histogram | Redis operation latency |

#### Useful PromQL Queries

```promql
# Request rate by model (last 5 minutes)
rate(litellm_proxy_total_requests_metric[5m])

# Error rate percentage
(rate(litellm_proxy_failed_requests_metric[5m]) / rate(litellm_proxy_total_requests_metric[5m])) * 100

# P95 latency by model
histogram_quantile(0.95, rate(litellm_request_total_latency_metric_bucket[5m]))

# Token usage per minute
rate(litellm_total_tokens_metric[1m]) * 60

# Cost per hour (assuming $0.01 per 1K tokens)
rate(litellm_total_tokens_metric[1h]) * 3600 * 0.00001
```

#### Redis Metrics

```promql
# Cache hit rate
rate(redis_keyspace_hits_total[5m]) / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))

# Memory usage
redis_memory_used_bytes / redis_memory_max_bytes

# Connected clients
redis_connected_clients
```

#### Kubernetes Metrics

```promql
# Pod CPU usage
sum(rate(container_cpu_usage_seconds_total{namespace="litellm"}[5m])) by (pod)

# Pod memory usage
sum(container_memory_working_set_bytes{namespace="litellm"}) by (pod)

# Pod restart count
kube_pod_container_status_restarts_total{namespace="litellm"}
```

---

### Grafana Dashboards

**Access Grafana:**
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-grafana 3000:80
# Open: http://localhost:3000
```

#### Pre-installed Dashboards

| Dashboard | Description | Location |
|-----------|-------------|----------|
| **LiteLLM Proxy** | Request rates, latency, token usage, costs | Home → LiteLLM |
| **Kubernetes / Compute Resources** | Pod/node CPU, memory, network | Home → Kubernetes |
| **Node Exporter** | Host-level metrics | Home → Node Exporter |
| **Redis** | Cache performance, memory | Home → Redis |

#### Creating Custom Dashboards

```bash
# Import LiteLLM community dashboards
# Download from: https://github.com/BerriAI/litellm/tree/main/cookbook/misc/grafana_dashboard

# Import via Grafana UI:
# 1. Click + → Import
# 2. Upload JSON file or paste dashboard ID
# 3. Select Prometheus datasource
```

#### Alert Rules

Configure alerts in Grafana for critical metrics:

**High Error Rate:**
```yaml
alert: HighLiteLLMErrorRate
expr: |
  (rate(litellm_proxy_failed_requests_metric[5m]) / rate(litellm_proxy_total_requests_metric[5m])) > 0.05
for: 5m
labels:
  severity: warning
annotations:
  summary: "LiteLLM error rate above 5%"
```

**High Latency:**
```yaml
alert: HighLiteLLMLatency
expr: |
  histogram_quantile(0.95, rate(litellm_request_total_latency_metric_bucket[5m])) > 5
for: 10m
labels:
  severity: warning
annotations:
  summary: "P95 latency above 5 seconds"
```

**Pod Down:**
```yaml
alert: LiteLLMPodDown
expr: |
  kube_deployment_status_replicas_available{deployment="litellm"} < 1
for: 2m
labels:
  severity: critical
annotations:
  summary: "LiteLLM has no available replicas"
```

---

### Distributed Tracing (Jaeger)

**Access Jaeger:**
```bash
kubectl port-forward -n monitoring svc/jaeger-query 16686:16686
# Open: http://localhost:16686
```

#### Understanding Traces

LiteLLM exports traces via OpenTelemetry to Jaeger. Each trace represents an end-to-end request flow:

```
User → OpenWebUI → LiteLLM → AWS Bedrock → Response
```

**Trace components:**
- **Service**: Component name (e.g., `litellm-proxy`, `openwebui`)
- **Operation**: Action performed (e.g., `chat_completion`, `jwt_validation`)
- **Span**: Individual unit of work with start/end time
- **Tags**: Metadata (model, user, status_code)

#### Using Jaeger

**Find slow requests:**
1. Service: `litellm-proxy`
2. Operation: `chat_completion`
3. Min Duration: `5s`
4. Click "Find Traces"

**Trace failed requests:**
1. Tags: `error=true`
2. Lookback: Last 1 hour

**Analyze latency breakdown:**
- Click on a trace to see span timeline
- Identify bottlenecks (Redis cache, Bedrock API call, JWT validation)
- Check span tags for model, user, token count

---

### Logging

#### View Logs

```bash
# LiteLLM logs
kubectl logs -n litellm -l app.kubernetes.io/name=litellm --tail=100 -f

# OpenWebUI logs
kubectl logs -n open-webui -l app.kubernetes.io/name=open-webui --tail=100 -f

# External Secrets Operator
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=100 -f

# All logs from a namespace
kubectl logs -n litellm --all-containers --tail=100 -f
```

#### Structured Log Queries

```bash
# Filter by log level
kubectl logs -n litellm -l app.kubernetes.io/name=litellm | grep "ERROR"

# Filter JWT validation errors
kubectl logs -n litellm -l app.kubernetes.io/name=litellm | grep -i "jwt"

# Filter by user email
kubectl logs -n litellm -l app.kubernetes.io/name=litellm | grep "user@example.com"
```

#### Centralized Logging (Optional)

For production deployments, consider adding:

- **Loki** - Log aggregation (Grafana Labs)
- **Elasticsearch + Kibana** - Search and visualization
- **AWS CloudWatch Logs** - Native AWS integration

---

## Troubleshooting

### Common Issues

#### 1. ExternalSecrets Not Syncing

**Symptoms:**
```bash
kubectl get externalsecret -n litellm
NAME              STORE                  STATUS   AGE
litellm-secrets   aws-secrets-manager    Failed   2m
```

**Diagnosis:**
```bash
# Describe ExternalSecret
kubectl describe externalsecret litellm-secrets -n litellm

# Check ESO logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50

# Verify ClusterSecretStore
kubectl get clustersecretstore aws-secrets-manager -o yaml
```

**Common Causes:**
1. IAM role for External Secrets Operator not configured correctly
2. Secret doesn't exist in AWS Secrets Manager
3. Incorrect region in ClusterSecretStore
4. IRSA annotation missing on ServiceAccount

**Solutions:**
```bash
# Verify IAM role
aws iam get-role --role-name external-secrets-role

# List secrets in AWS
aws secretsmanager list-secrets \
  --query 'SecretList[?starts_with(Name, `litellm/`) || starts_with(Name, `openwebui/`)].Name'

# Check ServiceAccount annotation
kubectl get sa external-secrets -n external-secrets -o yaml | grep eks.amazonaws.com/role-arn

# Restart ESO pods
kubectl rollout restart deployment/external-secrets -n external-secrets
```

---

#### 2. LiteLLM JWT Validation Fails

**Symptoms:**
```bash
# 401 Unauthorized on API calls
curl -H "Authorization: Bearer <token>" http://litellm:4000/v1/chat/completions
```

**Diagnosis:**
```bash
# Check LiteLLM logs for JWT errors
kubectl logs -n litellm -l app.kubernetes.io/name=litellm | grep -i jwt

# Verify JWT_PUBLIC_KEY_URL
kubectl get secret litellm-secrets -n litellm -o jsonpath='{.data.jwt-public-key-url}' | base64 -d
```

**Common Causes:**
1. `JWT_PUBLIC_KEY_URL` incorrect or unreachable
2. Token expired
3. Token signature invalid
4. Okta JWKS endpoint unreachable from cluster

**Solutions:**
```bash
# Test Okta JWKS endpoint from pod
kubectl exec -n litellm deployment/litellm -- curl https://<okta-domain>/oauth2/default/v1/keys

# Decode JWT to inspect claims
# Visit https://jwt.io and paste your token

# Update JWT_PUBLIC_KEY_URL in AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id litellm/jwt-public-key-url \
  --secret-string "https://<correct-okta-domain>/oauth2/default/v1/keys"

# Restart LiteLLM pods to pick up new secret
kubectl rollout restart deployment/litellm -n litellm
```

---

#### 3. OpenWebUI OAuth Login Fails

**Symptoms:**
- "Sign in with Okta" button returns error
- Redirects to error page
- Infinite redirect loop

**Diagnosis:**
```bash
# Check OpenWebUI logs
kubectl logs -n open-webui -l app.kubernetes.io/name=open-webui --tail=100

# Verify secrets
kubectl get secret openwebui-secrets -n open-webui -o jsonpath='{.data}' | jq 'keys'
```

**Common Causes:**
1. Incorrect Okta client ID/secret
2. Callback URL mismatch in Okta app settings
3. Missing OAuth scopes (`openid`, `email`, `profile`, `groups`)

**Solutions:**
```bash
# Verify Okta configuration in AWS Secrets Manager
aws secretsmanager get-secret-value --secret-id openwebui/okta-client-id
aws secretsmanager get-secret-value --secret-id openwebui/okta-openid-url

# Check Okta app settings:
# 1. Login to Okta Admin Console
# 2. Applications → Your App
# 3. Verify Sign-in redirect URIs include: http(s)://<openwebui-url>/oauth/callback
# 4. Verify Grant types include: Authorization Code, Refresh Token
# 5. Verify Assignments allow your users

# Restart OpenWebUI
kubectl rollout restart deployment/open-webui -n open-webui
```

---

#### 4. Pods Stuck in Pending

**Symptoms:**
```bash
kubectl get pods -n litellm
NAME                      READY   STATUS    RESTARTS   AGE
litellm-xxx               0/1     Pending   0          5m
```

**Diagnosis:**
```bash
# Describe pod to see events
kubectl describe pod litellm-xxx -n litellm

# Check node resources
kubectl top nodes

# Check PVC status
kubectl get pvc -A
```

**Common Causes:**
1. Insufficient cluster resources (CPU/memory)
2. PVC not bound (waiting for storage provisioner)
3. Node selector/affinity not matching any nodes
4. Resource quotas exceeded

**Solutions:**
```bash
# Scale cluster nodes (if using Cluster Autoscaler)
# Or manually add nodes

# For eksctl cluster:
eksctl scale nodegroup --cluster=litellm-eks --name=ng-1 --nodes=5

# For Terraform cluster:
# Update terraform.tfvars with new desired_size
# Run: terraform apply

# Check PVC provisioning
kubectl describe pvc <pvc-name> -n <namespace>

# Delete and recreate pod if PVC stuck
kubectl delete pod <pod-name> -n <namespace>
```

---

#### 5. High Latency / Slow Responses

**Symptoms:**
- Requests taking >5 seconds
- Timeout errors
- User complaints about slow chat responses

**Diagnosis:**
```bash
# Check Prometheus P95 latency
# Visit Prometheus UI and run:
# histogram_quantile(0.95, rate(litellm_request_total_latency_metric_bucket[5m]))

# Check Jaeger traces for slow requests
# Filter by Min Duration: 5s

# Check pod resource usage
kubectl top pods -n litellm

# Check Redis cache hit rate
kubectl logs -n litellm -l app.kubernetes.io/name=litellm | grep "cache"
```

**Common Causes:**
1. AWS Bedrock throttling
2. Redis cache misses
3. Pods under-resourced (CPU/memory throttling)
4. Network issues

**Solutions:**
```bash
# Scale LiteLLM horizontally
kubectl scale deployment/litellm -n litellm --replicas=5

# Increase resource limits in helm-values/litellm-values.yaml
resources:
  limits:
    cpu: "4000m"
    memory: "4Gi"

# Verify cache is working
kubectl exec -n litellm deployment/litellm -- redis-cli -h redis-redis-ha-haproxy ping

# Check Bedrock throttling in CloudWatch
# AWS Console → CloudWatch → Metrics → Bedrock
```

---

#### 6. Redis Connection Errors

**Symptoms:**
```bash
# Logs show Redis connection failures
ERROR: Redis connection failed
ERROR: Cache unavailable
```

**Diagnosis:**
```bash
# Check Redis pods
kubectl get pods -n litellm | grep redis

# Test Redis connectivity
kubectl exec -n litellm deployment/litellm -- redis-cli -h redis-redis-ha-haproxy ping

# Check Redis logs
kubectl logs -n litellm statefulset/redis-redis-ha-server --tail=50
```

**Common Causes:**
1. Redis password mismatch
2. Redis pods not ready
3. Network policy blocking access

**Solutions:**
```bash
# Verify Redis password secret
kubectl get secret litellm-secrets -n litellm -o jsonpath='{.data.redis-password}' | base64 -d

# Restart Redis
kubectl rollout restart statefulset/redis-redis-ha-server -n litellm

# Restart LiteLLM
kubectl rollout restart deployment/litellm -n litellm
```

---

#### 7. OPA Gatekeeper Blocking Deployments

**Symptoms:**
```bash
# Deployment fails with admission webhook error
Error from server: admission webhook "validation.gatekeeper.sh" denied the request
```

**Diagnosis:**
```bash
# Check which constraint is blocking
kubectl describe <resource-type> <resource-name> -n <namespace>

# List all constraints
kubectl get constraints

# View constraint details
kubectl describe k8srequiredlabels require-labels
```

**Common Causes:**
1. Missing required labels
2. Using `:latest` image tag
3. No resource limits defined
4. Using disallowed container registry

**Solutions:**
```bash
# View constraint requirements
kubectl get constraint <constraint-name> -o yaml

# Fix manifest to comply with policy
# Example: Add required labels
metadata:
  labels:
    app.kubernetes.io/name: myapp
    app.kubernetes.io/version: "1.0.0"

# Temporarily set constraint to dryrun mode (NOT for production)
kubectl patch constraint <constraint-name> --type=merge -p '{"spec":{"enforcementAction":"dryrun"}}'
```

---

## Maintenance Procedures

### Upgrading Components

#### 1. Upgrade LiteLLM

```bash
# Check current version
kubectl get deployment litellm -n litellm -o jsonpath='{.spec.template.spec.containers[0].image}'

# Update helm-values/litellm-values.yaml
image:
  tag: "v1.81.0-stable"  # New version

# Apply upgrade
helm upgrade litellm oci://ghcr.io/berriai/litellm-helm \
  -n litellm -f helm-values/litellm-values.yaml

# Monitor rollout
kubectl rollout status deployment/litellm -n litellm

# Verify new version
kubectl get pods -n litellm -o jsonpath='{.items[0].spec.containers[0].image}'
```

#### 2. Upgrade OpenWebUI

```bash
# Update Helm chart
helm repo update open-webui

# Check available versions
helm search repo open-webui/open-webui --versions

# Upgrade
helm upgrade open-webui open-webui/open-webui \
  -n open-webui -f helm-values/openwebui-values.yaml \
  --version <new-version>

# Monitor
kubectl rollout status deployment/open-webui -n open-webui
```

#### 3. Upgrade Prometheus/Grafana

```bash
# Update Helm repo
helm repo update prometheus-community

# Upgrade stack
helm upgrade kube-prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring -f helm-values/kube-prometheus-stack-values.yaml

# Verify
kubectl get pods -n monitoring
```

#### 4. Upgrade Kubernetes (EKS)

**For eksctl cluster:**
```bash
# Upgrade control plane
eksctl upgrade cluster --name litellm-eks --approve

# Upgrade node groups
eksctl upgrade nodegroup --name=ng-1 --cluster=litellm-eks
```

**For Terraform cluster:**
```bash
# Update terraform.tfvars
cluster_version = "1.29"

# Plan and apply
terraform plan
terraform apply

# Upgrade add-ons
aws eks update-addon --cluster-name litellm-eks \
  --addon-name vpc-cni --addon-version <version>
```

---

### Secret Rotation

Rotate secrets regularly for security:

#### 1. Rotate Redis Password

```bash
# Generate new password
NEW_PASSWORD=$(openssl rand -hex 16)

# Update in AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id litellm/redis-password \
  --secret-string "$NEW_PASSWORD"

# Wait for External Secrets to sync (1 hour default)
# Or force sync by deleting the ExternalSecret
kubectl delete externalsecret litellm-secrets -n litellm
kubectl apply -f manifests/litellm-external-secret.yaml

# Restart Redis and LiteLLM
kubectl rollout restart statefulset/redis-redis-ha-server -n litellm
kubectl rollout restart deployment/litellm -n litellm
```

#### 2. Rotate LiteLLM Master Key

```bash
# Generate new key
NEW_KEY="sk-$(openssl rand -hex 32)"

# Update in AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id litellm/master-key \
  --secret-string "$NEW_KEY"

# Wait for sync, then restart LiteLLM
kubectl rollout restart deployment/litellm -n litellm

# Update any clients using the old master key
```

#### 3. Rotate Okta Client Secret

```bash
# Generate new secret in Okta Admin Console:
# Applications → Your App → Client Credentials → Rotate Secret

# Update in AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id openwebui/okta-client-secret \
  --secret-string "<new-secret>"

# Restart OpenWebUI
kubectl rollout restart deployment/open-webui -n open-webui
```

---

### Database Maintenance

#### Backup PostgreSQL

```bash
# Port-forward to RDS (if using Terraform-created RDS)
# Or connect directly from bastion

# Create backup
pg_dump -h <rds-endpoint> -U litellm -d litellm > backup-$(date +%Y%m%d).sql

# Upload to S3
aws s3 cp backup-$(date +%Y%m%d).sql s3://my-backups-bucket/litellm/
```

#### Restore PostgreSQL

```bash
# Download backup
aws s3 cp s3://my-backups-bucket/litellm/backup-20240101.sql .

# Restore
psql -h <rds-endpoint> -U litellm -d litellm < backup-20240101.sql
```

#### Vacuum Database

```bash
# Connect to database
psql -h <rds-endpoint> -U litellm -d litellm

# Run vacuum
VACUUM ANALYZE;

# Check table sizes
SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

---

## Performance Tuning

### Horizontal Pod Autoscaling

Enable HPA for LiteLLM based on CPU/memory:

```yaml
# litellm-hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: litellm-hpa
  namespace: litellm
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: litellm
  minReplicas: 2
  maxReplicas: 10
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

```bash
kubectl apply -f litellm-hpa.yaml
kubectl get hpa -n litellm
```

### Cluster Autoscaling

Enable Cluster Autoscaler to automatically scale nodes:

**For eksctl cluster:**
```bash
eksctl create iamserviceaccount \
  --cluster=litellm-eks \
  --namespace=kube-system \
  --name=cluster-autoscaler \
  --attach-policy-arn=arn:aws:iam::aws:policy/AutoScalingFullAccess \
  --approve

helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=litellm-eks
```

### Redis Optimization

#### Enable Redis Persistence

```yaml
# helm-values/redis-values.yaml
redis:
  persistentVolume:
    enabled: true
    size: 10Gi
```

#### Tune Redis Memory

```yaml
# helm-values/redis-values.yaml
redis:
  resources:
    limits:
      memory: 4Gi
```

### LiteLLM Caching

Ensure caching is enabled in `litellm-values.yaml`:

```yaml
litellm_settings:
  cache: true
  cache_params:
    type: redis
    host: redis-redis-ha-haproxy
    port: 6379
    ttl: 3600  # 1 hour cache
```

---

## Cost Optimization

### Right-Size Resources

Review resource requests/limits:

```bash
# Check actual resource usage
kubectl top pods -n litellm
kubectl top pods -n open-webui
kubectl top pods -n monitoring

# Adjust in helm values if over/under-allocated
```

### Enable Response Caching

Cache identical requests:

```yaml
# litellm-values.yaml
litellm_settings:
  cache: true
  cache_params:
    ttl: 3600  # Cache for 1 hour
```

### Set Rate Limits

Prevent cost overruns:

```yaml
# litellm-values.yaml
litellm_settings:
  max_parallel_requests: 100
  user_api_key_rate_limit_config:
    rpm: 100  # requests per minute
    tpm: 50000  # tokens per minute
```

### Monitor Costs

```bash
# View token usage by model
# Prometheus query:
sum(increase(litellm_total_tokens_metric[1d])) by (model)
```

---

## Backup & Recovery

### Backup Strategy

**What to backup:**
1. PostgreSQL database (user data, request logs, API keys)
2. AWS Secrets Manager secrets
3. Helm values files (version controlled)
4. OPA policies (version controlled)

**Backup Schedule:**
- Database: Daily automated snapshots
- Secrets: Weekly manual export
- Configuration: Continuous (Git commits)

### Database Snapshots (RDS)

```bash
# Create manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier litellm-db \
  --db-snapshot-identifier litellm-db-snapshot-$(date +%Y%m%d)

# List snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier litellm-db

# Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier litellm-db-restored \
  --db-snapshot-identifier litellm-db-snapshot-20240101
```

### Secrets Backup

```bash
# Export all secrets to JSON
aws secretsmanager list-secrets \
  --query 'SecretList[?starts_with(Name, `litellm/`) || starts_with(Name, `openwebui/`)].Name' \
  --output text | xargs -I {} aws secretsmanager get-secret-value --secret-id {} > secrets-backup.json

# Encrypt and store securely
gpg --encrypt --recipient admin@company.com secrets-backup.json
aws s3 cp secrets-backup.json.gpg s3://secure-backups-bucket/
```

---

#### Review OPA Audit Violations

```bash
# Check for constraint violations in dryrun mode
kubectl get constraints -o json | jq '.items[] | select(.spec.enforcementAction=="dryrun") | {name:.metadata.name, violations:.status.totalViolations}'

# View detailed violations
kubectl describe constraint <constraint-name>
```

---

## Additional Resources

- [Deployment Guide](DEPLOYMENT_GUIDE.md) - Initial setup and deployment
- [JWT Authentication Setup](JWT_AUTHENTICATION_SETUP.md) - Okta configuration
- [MCP Deployment](MCP_DEPLOYMENT.md) - Model Context Protocol servers
- [LiteLLM Documentation](https://docs.litellm.ai/) - Official LiteLLM docs
- [Prometheus Best Practices](https://prometheus.io/docs/practices/) - Monitoring guidelines
- [Grafana Tutorials](https://grafana.com/tutorials/) - Dashboard creation
