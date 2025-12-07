# MCP Server Deployment Guide

## Overview

**Model Context Protocol (MCP) servers** are specialized backend services that expose tools and capabilities to AI models like Claude through a standardized protocol. They enable AI assistants to:

- Access external data sources (GitHub repositories, databases, S3 buckets)
- Perform system operations (execute CLI commands, manage Docker containers)
- Integrate with third-party APIs (Slack, Jira, email services)

This guide provides the requirements and patterns for deploying MCP servers as **in-cluster EKS pods** alongside your LiteLLM proxy.

**Why in-cluster deployment?**
- Lower latency (no external network hops)
- Simplified networking (ClusterIP services)
- Consistent observability (same Prometheus/Jaeger stack)
- Unified secret management (External Secrets Operator)
- Better security (network policies, no public exposure)

---

## Deployment Requirements

### 1. Standard Kubernetes Resources

Every MCP server deployment should include:

- **Deployment**: 2+ replicas for high availability
- **Service**: ClusterIP type for internal access
- **ServiceAccount**: Required if using IRSA for AWS access
- **PodDisruptionBudget**: Optional but recommended (minAvailable: 1)
- **Container Image**: Must be from approved internal registry (AWS ECR recommended)

### 2. Security Requirements

All MCP servers must comply with existing OPA Gatekeeper policies:

- **Approved container registries only**: Use internal AWS ECR or approved registries (no external public registries)
- **Specific image tags**: No `:latest` tag or untagged images
- **Non-root containers**: Run as UID 1000
- **Drop all capabilities**: `securityContext.capabilities.drop: ["ALL"]`
- **Resource limits**: Define CPU and memory requests/limits
- **Standard labels**: Use `app.kubernetes.io/*` labels
- **Read-only root filesystem**: Recommended where possible
- **No NodePort services**: Use ClusterIP only

### 3. Observability Integration

Integrate with the existing monitoring stack:

- **Metrics**: Expose `/metrics` endpoint (Prometheus format)
- **Tracing**: Send OTLP traces to Jaeger at `http://jaeger-all-in-one.monitoring.svc.cluster.local:4318`
- **Health probes**:
  - Liveness probe: `GET /health` (pod is alive)
  - Readiness probe: `GET /ready` (can serve traffic)
- **Logging**: Structured JSON logs to stdout

### 4. Authentication & Authorization

- **API tokens/credentials**: Store in AWS Secrets Manager, sync via External Secrets Operator
- **AWS service access**: Use IRSA (IAM Roles for Service Accounts) - no static credentials
- **User context**: LiteLLM should pass user identity in request headers (future enhancement)

### 5. Configuration Management

- **Service endpoints**: Environment variables (e.g., `MCP_GITHUB_ENDPOINT`)
- **Tool-specific config**: ConfigMaps (e.g., allowed S3 buckets, command whitelist)
- **Sensitive data**: ExternalSecrets synced from AWS Secrets Manager
- **Service discovery**: Kubernetes DNS (`<service>.<namespace>.svc.cluster.local`)

---

## Building and Publishing MCP Server Images

**IMPORTANT**: MCP server images must be built and pushed to your AWS ECR (or other approved internal registry). External public registries are not allowed.

### Step 1: Create ECR Repository

```bash
# Set variables
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export MCP_SERVER_NAME=mcp-github

# Create ECR repository
aws ecr create-repository \
  --repository-name ${MCP_SERVER_NAME} \
  --region ${AWS_REGION}
```

### Step 2: Build MCP Server Image

```bash
# Build your MCP server Docker image
cd /path/to/mcp-server-code
docker build -t ${MCP_SERVER_NAME}:1.0.0 .
```

### Step 3: Push to ECR

```bash
# Login to ECR
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Tag image for ECR
docker tag ${MCP_SERVER_NAME}:1.0.0 \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${MCP_SERVER_NAME}:1.0.0

# Push to ECR
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${MCP_SERVER_NAME}:1.0.0
```

### Step 4: Update OPA Allowed Repos Policy

Add your ECR registry to the allowed repos:

```bash
# Update the OPA constraint to allow your ECR
sed -i "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" \
  manifests/opa-policies/constraints/allowed-repos.yaml

# Apply the updated policy
kubectl apply -f manifests/opa-policies/constraints/allowed-repos.yaml
```

### Step 5: Update Deployment Manifest

Replace `ACCOUNT_ID` in the deployment YAML:

```bash
export IMAGE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${MCP_SERVER_NAME}:1.0.0"
# Use this image in your deployment manifest
```

---

## Example Deployment

Below is a complete, annotated example for deploying a GitHub MCP server.

See [`docs/mcp/examples/mcp-server-template.yaml`](mcp/examples/mcp-server-template.yaml) for the full YAML manifest.

**Key components**:

1. **Deployment** with 2 replicas for HA
2. **Service** (ClusterIP) for internal access
3. **ServiceAccount** with IRSA annotation for AWS access
4. **ExternalSecret** to sync GitHub token from AWS Secrets Manager
5. **Security context** meeting OPA requirements
6. **Health probes** for Kubernetes health checks
7. **OTEL configuration** for tracing to Jaeger

---

## Connecting LiteLLM to MCP Servers

### Step 1: Configure Service Endpoint

Add the MCP server endpoint to `helm-values/litellm-values.yaml`:

```yaml
extraEnvVars:
  # ... existing env vars ...

  # MCP server endpoints
  - name: MCP_GITHUB_ENDPOINT
    value: "http://mcp-github.litellm.svc.cluster.local:8080"

  - name: MCP_S3_ENDPOINT
    value: "http://mcp-s3.litellm.svc.cluster.local:8080"

  # Enable MCP support
  - name: MCP_ENABLED
    value: "true"
```

### Step 2: Configure LiteLLM MCP Registry (Future Feature)

Once LiteLLM adds MCP server registry support, you'll be able to configure servers like this:

```yaml
# In litellm-values.yaml (future feature)
litellm_settings:
  # ... existing settings ...

  mcp_servers:
    - server_name: github
      endpoint: "http://mcp-github.litellm.svc.cluster.local:8080"
      transport: sse
      description: "GitHub repository and issue access"
      allowed_user_groups:
        - litellm-developers
        - litellm-admins

    - server_name: s3
      endpoint: "http://mcp-s3.litellm.svc.cluster.local:8080"
      transport: http
      description: "S3 file access"
      allowed_user_groups:
        - litellm-admins
        - data-team
```

### Step 3: Test the Connection

```bash
# Port-forward to LiteLLM
kubectl port-forward -n litellm svc/litellm-proxy 4000:4000

# Test MCP server connectivity (once LiteLLM adds MCP support)
curl http://localhost:4000/mcp/servers
```

---

## Security Best Practices

### IRSA (IAM Roles for Service Accounts)

For MCP servers that need AWS access (S3, DynamoDB, Secrets Manager):

**1. Create IAM role with trust policy:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/OIDC_PROVIDER"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "OIDC_PROVIDER:aud": "sts.amazonaws.com",
          "OIDC_PROVIDER:sub": "system:serviceaccount:litellm:mcp-s3-sa"
        }
      }
    }
  ]
}
```

**2. Attach scoped permission policy:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3ReadOnly",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::company-docs/*",
        "arn:aws:s3:::company-docs"
      ]
    }
  ]
}
```

**3. Annotate ServiceAccount:**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: mcp-s3-sa
  namespace: litellm
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT_ID:role/mcp-s3-role"
```

### External Secrets

Store credentials in AWS Secrets Manager, sync to Kubernetes:

**1. Create secret in AWS:**

```bash
aws secretsmanager create-secret \
  --name mcp/github/token \
  --description "GitHub API token for MCP server" \
  --secret-string "ghp_xxxxxxxxxxxxxxxxxxxx" \
  --region us-east-1
```

**2. Create ExternalSecret resource:**

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: mcp-github-secrets
  namespace: litellm
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: mcp-github-secrets
    creationPolicy: Owner
  data:
  - secretKey: github-token
    remoteRef:
      key: mcp/github/token
```

**3. Mount as environment variable:**

```yaml
env:
- name: GITHUB_TOKEN
  valueFrom:
    secretKeyRef:
      name: mcp-github-secrets
      key: github-token
```

### Network Policies (Optional)

For strict network isolation:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-litellm-to-mcp
  namespace: litellm
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: mcp-server
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow from LiteLLM proxy
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: litellm-proxy
    ports:
    - protocol: TCP
      port: 8080
  egress:
  # Allow DNS resolution
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
  # Allow to external APIs (for SaaS MCPs like GitHub)
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443
  # Allow to Jaeger for tracing
  - to:
    - namespaceSelector:
        matchLabels:
          app.kubernetes.io/name: monitoring
    ports:
    - protocol: TCP
      port: 4318
```

---

## Monitoring & Observability

### Prometheus Metrics

All MCP servers should expose standard metrics:

**Required metrics:**
```
# Request metrics
mcp_requests_total{server="github",tool="search_repos",status="success"}
mcp_request_duration_seconds{server="github",tool="search_repos"}
mcp_errors_total{server="github",tool="search_repos",error_type="api_error"}

# Resource metrics (optional)
mcp_api_calls_total{server="github",endpoint="repos/search"}
mcp_api_rate_limit_remaining{server="github"}
mcp_concurrent_requests{server="github"}
```

### ServiceMonitor

Create a ServiceMonitor for Prometheus auto-discovery:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mcp-servers
  namespace: monitoring
  labels:
    release: kube-prometheus
spec:
  namespaceSelector:
    matchNames:
    - litellm
  selector:
    matchLabels:
      app.kubernetes.io/component: mcp-server
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
```

### Distributed Tracing

Configure OTEL to send traces to Jaeger:

```yaml
env:
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: "http://jaeger-all-in-one.monitoring.svc.cluster.local:4318"
- name: OTEL_EXPORTER_OTLP_PROTOCOL
  value: "http/protobuf"
- name: OTEL_SERVICE_NAME
  value: "mcp-github"
- name: OTEL_TRACES_SAMPLER
  value: "always_on"
```

**Trace context should include:**
- User ID/email
- Tool name
- Request parameters
- Duration
- Error details (if failed)

### Grafana Dashboard

Create a dashboard to monitor MCP server health:

**Panels to include:**
- Request rate by server and tool
- Error rate (%)
- P95/P99 latency
- API rate limits (for external services)
- Active connections/concurrent requests

---

## Deployment Checklist

Before deploying an MCP server:

- [ ] Deployment manifest created with 2+ replicas
- [ ] Service (ClusterIP) defined
- [ ] Security context configured (non-root, drop capabilities)
- [ ] Resource requests and limits defined
- [ ] Health probes configured (`/health`, `/ready`)
- [ ] Prometheus metrics exposed at `/metrics`
- [ ] OTEL tracing configured to Jaeger
- [ ] Credentials stored in AWS Secrets Manager
- [ ] ExternalSecret created for secret sync
- [ ] IRSA role created (if AWS access needed)
- [ ] ServiceAccount annotated with IAM role
- [ ] Standard labels applied
- [ ] PodDisruptionBudget created (minAvailable: 1)
- [ ] LiteLLM configured with MCP endpoint
- [ ] ServiceMonitor created for Prometheus
- [ ] Tested connectivity from LiteLLM
- [ ] Verified metrics in Prometheus
- [ ] Verified traces in Jaeger

---

## Troubleshooting

### MCP Server Not Reachable from LiteLLM

**Symptoms**: Connection timeouts, DNS resolution failures

**Checks**:
```bash
# 1. Verify service exists
kubectl get svc -n litellm | grep mcp

# 2. Verify pods are running
kubectl get pods -n litellm -l app.kubernetes.io/name=mcp-github

# 3. Test DNS resolution from LiteLLM pod
kubectl exec -n litellm deployment/litellm-proxy -- nslookup mcp-github.litellm.svc.cluster.local

# 4. Test connectivity
kubectl exec -n litellm deployment/litellm-proxy -- curl http://mcp-github.litellm.svc.cluster.local:8080/health
```

### Authentication Failures

**Symptoms**: 401/403 errors, "access denied"

**Checks**:
```bash
# 1. Verify ExternalSecret sync status
kubectl get externalsecret -n litellm mcp-github-secrets
kubectl describe externalsecret -n litellm mcp-github-secrets

# 2. Check if Kubernetes secret was created
kubectl get secret -n litellm mcp-github-secrets

# 3. Verify secret contents (without exposing values)
kubectl get secret -n litellm mcp-github-secrets -o jsonpath='{.data}' | jq 'keys'

# 4. Check IRSA role assumption (if using AWS)
kubectl logs -n litellm deployment/mcp-s3 | grep -i "unable to retrieve credentials"
```

### High Latency

**Symptoms**: Slow response times, timeout errors

**Checks**:
```bash
# 1. Check CPU throttling
kubectl top pods -n litellm -l app.kubernetes.io/name=mcp-github

# 2. Review resource limits
kubectl get deployment -n litellm mcp-github -o jsonpath='{.spec.template.spec.containers[0].resources}'

# 3. Check external API rate limits (if applicable)
kubectl exec -n litellm deployment/mcp-github -- curl -s http://localhost:8080/metrics | grep rate_limit

# 4. Review Jaeger traces for bottlenecks
# Access Grafana and check Jaeger datasource
```

### Permission Denied

**Symptoms**: AWS API errors, S3 access denied

**Checks**:
```bash
# 1. Verify IRSA annotation on ServiceAccount
kubectl get sa -n litellm mcp-s3-sa -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# 2. Check IAM role trust policy
aws iam get-role --role-name mcp-s3-role --query 'Role.AssumeRolePolicyDocument'

# 3. Review IAM role permissions
aws iam list-attached-role-policies --role-name mcp-s3-role

# 4. Test IAM access from pod
kubectl exec -n litellm deployment/mcp-s3 -- aws sts get-caller-identity
```

---

## Next Steps

1. Review the complete example in [`docs/mcp/examples/mcp-server-template.yaml`](mcp/examples/mcp-server-template.yaml)
2. Customize the template for your specific MCP server
3. Deploy to a test namespace first
4. Verify observability (metrics, traces, logs)
5. Update LiteLLM configuration to connect to your MCP server
6. Test tool invocation from Claude
7. Promote to production with proper monitoring

---

## References

- **LiteLLM MCP Documentation**: https://docs.litellm.ai/docs/mcp
- **Model Context Protocol Spec**: https://modelcontextprotocol.io
- **Existing Architecture**: [`security/ARCHITECTURE.md`](../security/ARCHITECTURE.md)
- **External Secrets Pattern**: [`manifests/litellm-external-secret.yaml`](../manifests/litellm-external-secret.yaml)
- **IRSA Example**: [`helm-values/litellm-values.yaml`](../helm-values/litellm-values.yaml)
- **OPA Policies**: [`manifests/opa-policies/`](../manifests/opa-policies/)
