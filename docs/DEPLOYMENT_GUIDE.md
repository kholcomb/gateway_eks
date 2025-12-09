# LiteLLM + OpenWebUI Deployment Guide

## Overview

This guide walks you through deploying a production-ready LiteLLM proxy with OpenWebUI frontend on Amazon EKS, featuring:

- **JWT Authentication**: Client-agnostic authentication via Okta OIDC
- **AWS Bedrock Integration**: Access to Claude, Llama, and other models
- **High Availability**: Redis HA, multi-replica deployments
- **Observability**: Prometheus, Grafana, Jaeger distributed tracing
- **Security**: OPA Gatekeeper policies, IRSA, encrypted secrets
- **MCP Server Support**: Deploy Model Context Protocol servers for extended AI capabilities

> **Note**: This guide focuses on application deployment. For infrastructure setup (EKS cluster, VPC, RDS), see the [main README](../README.md) for Terraform deployment instructions.

## Architecture

```mermaid
graph TB
    User[User] -->|Authenticates| Okta[Okta OIDC]
    Okta -->|JWT Token| OpenWebUI[OpenWebUI Frontend]
    OpenWebUI -->|API Requests + JWT| LiteLLM[LiteLLM Proxy]
    LiteLLM -->|Validates JWT| Okta
    LiteLLM -->|Model Requests| Bedrock[AWS Bedrock<br/>Claude, Llama, Mistral]
    LiteLLM -->|Caching| Redis[Redis HA Cluster]
    LiteLLM -->|Metrics| Prometheus[Prometheus]
    LiteLLM -->|Traces| Jaeger[Jaeger]
    OpenWebUI -->|Session Data| PostgreSQL[PostgreSQL RDS]
    Prometheus -->|Visualization| Grafana[Grafana Dashboards]

    subgraph "EKS Cluster"
        OpenWebUI
        LiteLLM
        Redis
        Prometheus
        Grafana
        Jaeger
    end

    subgraph "AWS Services"
        Bedrock
        PostgreSQL
        Okta
    end

    style LiteLLM fill:#326CE5
    style OpenWebUI fill:#61DAFB
    style Bedrock fill:#FF9900
    style Okta fill:#007DC1
```

## Prerequisites

### 1. AWS Infrastructure

The following must be deployed before running this deployment:

- **EKS cluster** (via Terraform - see [README.md](../README.md))
- **PostgreSQL database** (RDS from Terraform, or external)
- **VPC with private subnets** (created by infrastructure deployment)
- **AWS Secrets Manager** enabled in your region
- (Optional) **Bastion host** for kubectl access and testing

### 2. Local Tools

Install required CLI tools:

```bash
# macOS
brew install awscli kubectl helm

# Linux
# Follow official installation guides for each tool
```

Verify installations:
```bash
aws --version      # AWS CLI 2.x
kubectl version    # v1.28+
helm version       # v3.0+
```

### 3. AWS Credentials

Configure AWS CLI and verify access:

```bash
aws configure
aws sts get-caller-identity  # Should show your account ID
aws eks list-clusters --region us-east-1  # Verify EKS access
```

### 4. kubectl Configuration

Connect to your EKS cluster:

```bash
aws eks update-kubeconfig --name <your-cluster-name> --region <region>
kubectl cluster-info  # Verify connection
kubectl get nodes    # Should show your EKS nodes
```

### 5. Okta Setup (for JWT Authentication)

You need an Okta organization and OIDC application configured. See [JWT_AUTHENTICATION_SETUP.md](./JWT_AUTHENTICATION_SETUP.md) for detailed Okta configuration steps.

**Required Okta information:**
- Okta domain (e.g., `dev-123456.okta.com`)
- JWKS endpoint URL
- Client ID and Client Secret
- Callback URL configuration

---

## Quick Start

### Step 1: Configure Environment

Set environment variables (the deployment script will auto-detect if not set):

```bash
export AWS_REGION="us-east-1"
export EKS_CLUSTER_NAME="my-eks-cluster"
# AWS_ACCOUNT_ID will be auto-detected if not set
```

> **Tip**: The deployment script runs in **interactive mode** by default. It will prompt you before deploying resources that already exist, allowing you to skip, proceed, or view details. To disable prompts, set `INTERACTIVE_MODE=false`.

### Step 2: Create AWS Secrets Manually

Before running the deployment, create the required secrets in AWS Secrets Manager:

#### LiteLLM Secrets

```bash
# JWT Public Key URL (Okta JWKS endpoint)
aws secretsmanager create-secret \
  --name litellm/jwt-public-key-url \
  --description "Okta JWKS endpoint for JWT validation" \
  --secret-string "https://<your-okta-domain>/oauth2/default/v1/keys" \
  --region us-east-1

# Database URL (should already exist from Terraform setup)
# If not, create it:
aws secretsmanager create-secret \
  --name litellm/database-url \
  --secret-string "postgresql://username:password@rds-endpoint:5432/litellm" \
  --region us-east-1
```

#### OpenWebUI Secrets

```bash
# Generate session encryption key
WEBUI_SECRET=$(openssl rand -hex 32)

aws secretsmanager create-secret \
  --name openwebui/webui-secret-key \
  --description "OpenWebUI session encryption key" \
  --secret-string "$WEBUI_SECRET" \
  --region us-east-1

# Okta OpenID configuration URL
aws secretsmanager create-secret \
  --name openwebui/okta-openid-url \
  --description "Okta OpenID Connect discovery URL" \
  --secret-string "https://<your-okta-domain>/oauth2/default/.well-known/openid-configuration" \
  --region us-east-1

# Okta Client ID (from Okta application)
aws secretsmanager create-secret \
  --name openwebui/okta-client-id \
  --description "Okta OIDC Application Client ID" \
  --secret-string "<your-client-id>" \
  --region us-east-1

# Okta Client Secret (from Okta application)
aws secretsmanager create-secret \
  --name openwebui/okta-client-secret \
  --description "Okta OIDC Application Client Secret" \
  --secret-string "<your-client-secret>" \
  --region us-east-1

# Admin user emails (comma-separated)
aws secretsmanager create-secret \
  --name openwebui/admin-email \
  --description "Admin user email addresses" \
  --secret-string "admin@yourcompany.com" \
  --region us-east-1
```

**Replace placeholders:**
- `<your-okta-domain>` - Your Okta domain (e.g., `dev-123456.okta.com`)
- `<your-client-id>` - Okta application Client ID
- `<your-client-secret>` - Okta application Client Secret
- Admin email with your actual admin user email

### Step 3: Run Deployment

```bash
cd scripts
./deploy.sh all
```

The deployment script will:
1. ✅ Validate YAML configurations
2. ✅ Create IRSA roles for Bedrock and External Secrets
3. ✅ Create LiteLLM secrets (master-key, salt-key, redis-password)
4. ✅ Add Helm repositories
5. ✅ Create Kubernetes namespaces
6. ✅ Deploy External Secrets Operator
7. ✅ Create ClusterSecretStore and sync secrets
8. ✅ Deploy OPA Gatekeeper and policies
9. ✅ Deploy Prometheus/Grafana monitoring
10. ✅ Deploy Jaeger distributed tracing
11. ✅ Deploy Redis HA cluster
12. ✅ Deploy LiteLLM proxy with JWT authentication
13. ✅ Deploy OpenWebUI with Okta OIDC
14. ✅ Verify all components

### Step 4: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -A | grep -E 'litellm|open-webui|monitoring|redis'

# Check External Secrets synced
kubectl get externalsecret -n litellm
kubectl get externalsecret -n open-webui

# View secrets (base64 encoded)
kubectl get secret litellm-secrets -n litellm -o yaml
kubectl get secret openwebui-secrets -n open-webui -o yaml
```

### Step 5: Access Applications

From your bastion host or local machine (with kubectl port-forward):

```bash
# OpenWebUI (user interface)
kubectl port-forward -n open-webui svc/open-webui 8080:80 --address 0.0.0.0
# Open: http://localhost:8080

# Grafana (monitoring dashboards)
kubectl port-forward -n monitoring svc/kube-prometheus-grafana 3000:80 --address 0.0.0.0
# Open: http://localhost:3000
# Default credentials: admin / prom-operator

# Prometheus (metrics)
kubectl port-forward -n monitoring svc/kube-prometheus-kube-prome-prometheus 9090:9090 --address 0.0.0.0
# Open: http://localhost:9090

# Jaeger (distributed tracing)
kubectl port-forward -n monitoring svc/jaeger-query 16686:16686 --address 0.0.0.0
# Open: http://localhost:16686
```

---

## Incremental Deployment

You can deploy individual components:

```bash
# Deploy only specific components
./deploy.sh irsa                 # Create IAM roles
./deploy.sh secrets              # Create AWS secrets (litellm only)
./deploy.sh external-secrets     # Deploy External Secrets Operator
./deploy.sh redis                # Deploy Redis HA
./deploy.sh litellm              # Deploy LiteLLM
./deploy.sh openwebui            # Deploy OpenWebUI
./deploy.sh monitoring           # Deploy Prometheus/Grafana
./deploy.sh jaeger               # Deploy Jaeger tracing
./deploy.sh gatekeeper           # Deploy OPA Gatekeeper
./deploy.sh opa-policies         # Apply OPA policies
./deploy.sh verify               # Verify deployment status
```

---

## Configuration Files

### Helm Values

Located in `/helm-values/`:

- **litellm-values.yaml**: LiteLLM proxy configuration
  - JWT authentication settings
  - Model definitions (Claude, Llama, etc.)
  - Redis connection
  - OpenTelemetry/Prometheus
- **openwebui-values.yaml**: OpenWebUI frontend configuration
  - Okta OIDC settings
  - OAuth scopes and permissions
  - LiteLLM backend connection
- **redis-values.yaml**: Redis HA configuration
- **kube-prometheus-stack-values.yaml**: Monitoring stack
- **jaeger-values.yaml**: Distributed tracing

### Kubernetes Manifests

Located in `/manifests/`:

- **namespaces.yaml**: Namespace definitions
- **cluster-secret-store.yaml**: AWS Secrets Manager integration
- **litellm-external-secret.yaml**: LiteLLM secrets sync
- **openwebui-external-secret.yaml**: OpenWebUI secrets sync
- **opa-policies/**: OPA Gatekeeper policies

### IAM Policies

Located in `/iam/`:

- **litellm-bedrock-policy.json**: Bedrock access permissions
- **external-secrets-policy.json**: Secrets Manager read permissions

---

## JWT Authentication Flow

### How It Works

1. **User authenticates with Okta**
   - User visits OpenWebUI
   - Redirected to Okta login page
   - Enters credentials
   - Okta issues JWT token with claims (email, groups, etc.)

2. **OpenWebUI stores session**
   - Receives JWT from Okta callback
   - Validates token
   - Creates encrypted session (using WEBUI_SECRET_KEY)
   - User is now logged in

3. **User sends chat request**
   - OpenWebUI extracts user's JWT token
   - Sends request to LiteLLM with `Authorization: Bearer <jwt-token>`
   - Request includes user context

4. **LiteLLM validates JWT**
   - Fetches Okta public keys from `jwt_public_key_url`
   - Validates token signature
   - Extracts user claims (email, groups, sub)
   - Checks permissions (optional)
   - Logs request with user context

5. **LiteLLM routes to Bedrock**
   - Uses IRSA credentials (no static keys)
   - Calls Claude/Llama models
   - Streams response back to user

### Key Configuration

In `litellm-values.yaml`:
```yaml
general_settings:
  enable_jwt_auth: true
  jwt_public_key_url: "os.environ/JWT_PUBLIC_KEY_URL"
```

In `openwebui-values.yaml`:
```yaml
extraEnvVars:
  - name: OAUTH_PROVIDER
    value: "oidc"
  - name: OPENID_PROVIDER_URL
    valueFrom:
      secretKeyRef:
        name: openwebui-secrets
        key: okta-openid-url
```

---

## Required AWS Secrets Summary

### LiteLLM Namespace

| Secret Name | Description | How Created |
|------------|-------------|-------------|
| `litellm/master-key` | LiteLLM API master key | Auto-generated by deploy script |
| `litellm/salt-key` | Database encryption salt (CANNOT change) | Auto-generated by deploy script |
| `litellm/redis-password` | Redis authentication password | Auto-generated by deploy script |
| `litellm/database-url` | PostgreSQL connection string | **Manual** (from Terraform outputs) |
| `litellm/jwt-public-key-url` | Okta JWKS endpoint | **Manual** (Okta domain) |

### OpenWebUI Namespace

| Secret Name | Description | How Created |
|------------|-------------|-------------|
| `openwebui/webui-secret-key` | Session encryption key | **Manual** |
| `openwebui/okta-openid-url` | Okta OpenID discovery URL | **Manual** |
| `openwebui/okta-client-id` | Okta application client ID | **Manual** |
| `openwebui/okta-client-secret` | Okta application client secret | **Manual** |
| `openwebui/admin-email` | Admin user emails (comma-separated) | **Manual** |

---

## Troubleshooting

### Issue: ExternalSecrets Not Syncing

**Symptoms:**
```bash
kubectl get externalsecret -n litellm
NAME              STORE                  STATUS   AGE
litellm-secrets   aws-secrets-manager    Failed   2m
```

**Diagnosis:**
```bash
kubectl describe externalsecret litellm-secrets -n litellm
```

**Common Causes:**
1. IAM role for External Secrets Operator not configured
2. Secret doesn't exist in AWS Secrets Manager
3. Incorrect region in ClusterSecretStore

**Solution:**
```bash
# Verify IAM role exists
aws iam get-role --role-name external-secrets-role

# Verify secrets exist
aws secretsmanager list-secrets --query 'SecretList[?starts_with(Name, `litellm/`) || starts_with(Name, `openwebui/`)].Name'

# Check External Secrets Operator logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

### Issue: LiteLLM JWT Validation Fails

**Symptoms:**
```bash
curl -H "Authorization: Bearer <jwt-token>" http://litellm:4000/v1/chat/completions
# Returns: 401 Unauthorized
```

**Diagnosis:**
```bash
kubectl logs -n litellm -l app.kubernetes.io/name=litellm | grep -i jwt
```

**Common Causes:**
1. `JWT_PUBLIC_KEY_URL` incorrect or unreachable
2. Token expired
3. Token signature invalid
4. Wrong Okta domain

**Solution:**
```bash
# Verify JWT_PUBLIC_KEY_URL
kubectl get secret litellm-secrets -n litellm -o jsonpath='{.data.jwt-public-key-url}' | base64 -d
# Should output: https://<your-okta-domain>/oauth2/default/v1/keys

# Test URL manually
curl https://<your-okta-domain>/oauth2/default/v1/keys

# Decode JWT token to inspect claims
# Visit https://jwt.io and paste your token
```

### Issue: OpenWebUI OAuth Login Fails

**Symptoms:**
- Clicking "Sign in with Okta" returns error
- Redirects to error page

**Diagnosis:**
```bash
kubectl logs -n open-webui -l app.kubernetes.io/name=open-webui | tail -50
```

**Common Causes:**
1. Incorrect Okta client ID/secret
2. Callback URL mismatch
3. Missing scopes

**Solution:**
1. Verify secrets in AWS Secrets Manager
2. Check Okta app redirect URIs match OpenWebUI URL
3. Ensure scopes include: `openid email profile groups`

### Issue: Pods Stuck in Pending

**Symptoms:**
```bash
kubectl get pods -n litellm
NAME                      READY   STATUS    RESTARTS   AGE
litellm-xxx               0/1     Pending   0          5m
```

**Diagnosis:**
```bash
kubectl describe pod litellm-xxx -n litellm
```

**Common Causes:**
1. Insufficient cluster resources
2. PVC not bound (for Redis/OpenWebUI)
3. Node selector not matching

**Solution:**
```bash
# Check cluster capacity
kubectl top nodes

# Check PVC status
kubectl get pvc -A

# Check node labels
kubectl get nodes --show-labels
```

---

## Security Considerations

### 1. Secret Rotation

Rotate secrets regularly:

```bash
# Rotate Redis password
NEW_PASSWORD=$(openssl rand -hex 16)
aws secretsmanager update-secret \
  --secret-id litellm/redis-password \
  --secret-string "$NEW_PASSWORD"

# Restart Redis and LiteLLM pods
kubectl rollout restart statefulset/redis-redis-ha-server -n litellm
kubectl rollout restart deployment/litellm -n litellm
```

### 2. JWT Token Lifetime

Configure short-lived tokens in Okta (15-60 minutes recommended).

### 3. HTTPS Only

In production, configure ingress with TLS:
- Use AWS Application Load Balancer with ACM certificate
- Or use nginx-ingress with cert-manager

### 4. Network Policies

Consider adding Kubernetes NetworkPolicies to restrict pod-to-pod communication.

### 5. OPA Policies

Review and enforce OPA Gatekeeper policies:

```bash
# View current policies
kubectl get constrainttemplates
kubectl get constraints

# Change from dryrun to enforce
# Edit constraint and set: enforcementAction: deny
```

---

## Monitoring and Observability

### Metrics (Prometheus)

Access Prometheus: `kubectl port-forward -n monitoring svc/kube-prometheus-kube-prome-prometheus 9090:9090`

Key metrics:
- `litellm_requests_total` - Total API requests
- `litellm_request_latency_seconds` - Request latency
- `litellm_tokens_total` - Token usage
- `redis_commands_processed_total` - Redis operations

### Dashboards (Grafana)

Access Grafana: `kubectl port-forward -n monitoring svc/kube-prometheus-grafana 3000:80`

Pre-configured dashboards:
- **LiteLLM Prometheus Dashboard**: API metrics, token usage, costs
- **Kubernetes Cluster Dashboard**: Node/pod metrics
- **Redis Dashboard**: Cache hit rates, memory usage

### Tracing (Jaeger)

Access Jaeger: `kubectl port-forward -n monitoring svc/jaeger-query 16686:16686`

View distributed traces for:
- End-to-end request flow (OpenWebUI → LiteLLM → Bedrock)
- Performance bottlenecks
- Error tracking

---

## MCP Server Deployment (Optional)

**Model Context Protocol (MCP)** servers extend LiteLLM's capabilities by providing tools and integrations to AI models. MCP servers enable:

- **External data access**: GitHub repositories, S3 buckets, databases
- **System operations**: CLI commands, Docker containers, file systems
- **Third-party integrations**: Slack, Jira, email services

### Quick Start

See the complete guide at [docs/MCP_DEPLOYMENT.md](./MCP_DEPLOYMENT.md) for detailed instructions.

**Example: Deploy a GitHub MCP Server**

```bash
# 1. Create IAM role for GitHub access (if needed)
# 2. Deploy MCP server to EKS
kubectl apply -f docs/mcp/examples/github-mcp-server.yaml

# 3. Verify deployment
kubectl get pods -n mcp-servers
kubectl logs -n mcp-servers -l app=github-mcp-server
```

### Key Requirements

- **Security**: Comply with OPA Gatekeeper policies (no :latest tags, resource limits, non-root)
- **Networking**: Use ClusterIP services (internal cluster access only)
- **Observability**: Integrate with Prometheus/Jaeger monitoring
- **Secrets**: Use External Secrets Operator for sensitive data

See [MCP_DEPLOYMENT.md](./MCP_DEPLOYMENT.md) for:
- Complete annotated deployment example
- Security best practices
- IRSA configuration
- Monitoring integration

---

## Cost Optimization

### 1. Right-Size Resources

Review resource requests/limits in helm values:

```yaml
# litellm-values.yaml
resources:
  requests:
    cpu: "500m"      # Adjust based on load
    memory: "512Mi"
  limits:
    cpu: "2000m"
    memory: "2Gi"
```

### 2. Enable Caching

LiteLLM uses Redis for response caching (configured by default).

### 3. Auto-Scaling

Add HorizontalPodAutoscalers:

```yaml
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
```

### 4. Bedrock Model Selection

Use appropriate models for each use case:
- **claude-3-haiku**: Fast, cheap (simple queries)
- **claude-3-sonnet**: Balanced (general use)
- **claude-3.5-sonnet**: Best quality (complex tasks)

---

## Deployment Modes

### Interactive Mode (Default)

The deployment script runs in interactive mode by default, prompting before deploying resources that already exist:

```bash
./deploy.sh all
# You'll see prompts like:
# [S] Skip - Skip this step (recommended if resource is healthy)
# [P] Proceed - Run deployment anyway (may update existing resource)
# [V] View - Show resource details
# [A] Auto - Auto-skip all remaining healthy resources
# [Q] Quit - Exit deployment
```

### Non-Interactive Mode

For CI/CD pipelines or automated deployments:

```bash
# Skip all existing resources automatically
INTERACTIVE_MODE=false SKIP_ALL=true ./deploy.sh all

# Proceed with all deployments (update existing)
INTERACTIVE_MODE=false ./deploy.sh all
```

---

## Additional Resources

### Documentation
- [Main README](../README.md) - Infrastructure deployment with Terraform
- [JWT Authentication Setup Guide](./JWT_AUTHENTICATION_SETUP.md) - Detailed Okta configuration
- [MCP Deployment Guide](./MCP_DEPLOYMENT.md) - Deploy Model Context Protocol servers
- [OPA Policies README](../manifests/opa-policies/README.md) - Security policy details
- [Scripts README](../scripts/README.md) - Deployment script documentation

### External Resources
- [LiteLLM Documentation](https://docs.litellm.ai/) - LiteLLM proxy features and configuration
- [OpenWebUI Documentation](https://docs.openwebui.com/) - OpenWebUI setup and customization
- [AWS Bedrock Models](https://aws.amazon.com/bedrock/claude/) - Available models and pricing
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/) - Policy enforcement
- [External Secrets Operator](https://external-secrets.io/) - Secret management

---

## Support

For issues:
1. Check logs: `kubectl logs -n <namespace> <pod-name>`
2. Review this troubleshooting guide
3. Check External Secrets sync status
4. Verify Okta configuration
5. Open an issue in the repository
