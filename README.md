# LiteLLM + OpenWebUI EKS Deployment

**Production-ready AI/LLM infrastructure on Amazon EKS** with comprehensive observability, security, and authentication.

This repository provides everything you need to deploy a complete, enterprise-grade LLM proxy infrastructure featuring:

- 🔐 **JWT Authentication** via Okta OIDC
- 🤖 **Multi-Model Support** - Claude, Llama, Mistral via AWS Bedrock
- 📊 **Full Observability** - Prometheus, Grafana, Jaeger tracing
- 🔒 **Security First** - OPA Gatekeeper policies, IRSA, encrypted secrets
- ⚡ **High Availability** - Redis HA, multi-replica deployments
- 🛠️ **Extensible** - Support for Model Context Protocol (MCP) servers

**Quick Links:**
- 📖 [Deployment Guide](docs/DEPLOYMENT_GUIDE.md) - Step-by-step walkthrough
- 🚀 [Quick Start](#quick-start) - Get started in minutes
- 🏗️ [Architecture](#architecture) - System design overview
- 📦 [ECR Setup](docs/ECR_SETUP.md) - Container registry configuration

## Architecture

```mermaid
graph TB
    subgraph "External Services"
        User[Users/Clients]
        Bedrock[AWS Bedrock<br/>Claude, Llama, Mistral]
        RDS[Amazon RDS<br/>PostgreSQL]
        SecretsManager[AWS Secrets Manager<br/>API Keys & Credentials]
        Bastion[EC2 Bastion<br/>Testing & Access]
    end

    subgraph "EKS Cluster"
        subgraph "Application Layer"
            OpenWebUI[OpenWebUI<br/>Chat Frontend]
            LiteLLM[LiteLLM Proxy<br/>JWT Auth + Routing]
            Redis[Redis HA<br/>Caching]
        end

        subgraph "Observability Stack"
            Prometheus[Prometheus<br/>Metrics Collection]
            Grafana[Grafana<br/>Dashboards]
            Jaeger[Jaeger<br/>Distributed Tracing]
            Alertmanager[Alertmanager<br/>Alerts]
        end

        subgraph "Security & Secrets"
            ESO[External Secrets<br/>Operator]
            OPA[OPA Gatekeeper<br/>Policy Enforcement]
        end
    end

    User -->|HTTPS| OpenWebUI
    OpenWebUI -->|API + JWT| LiteLLM
    LiteLLM -->|Model Requests| Bedrock
    LiteLLM -->|Cache| Redis
    OpenWebUI -->|Session Data| RDS

    LiteLLM -->|Metrics| Prometheus
    LiteLLM -->|Traces| Jaeger
    Prometheus -->|Visualize| Grafana
    Prometheus -->|Alerts| Alertmanager

    ESO -->|Sync Secrets| SecretsManager
    ESO -.->|Provides| LiteLLM
    ESO -.->|Provides| OpenWebUI

    OPA -.->|Enforce Policies| LiteLLM
    OPA -.->|Enforce Policies| OpenWebUI

    Bastion -.->|kubectl/port-forward| OpenWebUI
    Bastion -.->|kubectl/port-forward| Grafana

    style LiteLLM fill:#326CE5,color:#fff
    style OpenWebUI fill:#61DAFB
    style Bedrock fill:#FF9900,color:#fff
    style Prometheus fill:#E6522C,color:#fff
    style Grafana fill:#F46800,color:#fff
```

## Components

| Component | Helm Chart | Image Version | Purpose |
|-----------|------------|---------------|---------|
| LiteLLM | `oci://ghcr.io/berriai/litellm-helm` | v1.80.5-stable | API gateway to Bedrock |
| OpenWebUI | `open-webui/open-webui` | latest | Chat frontend |
| Redis HA | `dandydev/redis-ha` | redis:7.4-alpine | Caching & rate limiting |
| kube-prometheus-stack | `prometheus-community/kube-prometheus-stack` | - | Metrics & alerting |
| Jaeger | `jaegertracing/jaeger` | 1.53 | Distributed tracing |
| External Secrets Operator | `external-secrets/external-secrets` | - | Secrets sync |
| **ECR** | Terraform module | - | **Private container registry** |

## Directory Structure

```
eks-deploy/
├── terraform/                       # Terraform infrastructure (full IaC)
│   ├── main.tf                      # Main Terraform config
│   ├── modules/                     # Reusable Terraform modules
│   ├── environments/                # Environment-specific configs
│   ├── terraform.tfvars.example     # Example configuration
│   └── README.md                    # Terraform deployment guide
├── docs/                            # Documentation
│   ├── DEPLOYMENT_GUIDE.md          # Complete deployment walkthrough
│   ├── JWT_AUTHENTICATION_SETUP.md  # Okta/JWT configuration
│   ├── MCP_DEPLOYMENT.md            # Model Context Protocol servers
│   └── mcp/examples/                # MCP server templates
├── helm-values/                     # Helm chart configurations
│   ├── litellm-values.yaml          # LiteLLM proxy (JWT, models, telemetry)
│   ├── openwebui-values.yaml        # OpenWebUI frontend (Okta OIDC)
│   ├── redis-values.yaml            # Redis HA cluster
│   ├── kube-prometheus-stack-values.yaml  # Prometheus/Grafana/Alertmanager
│   ├── jaeger-values.yaml           # Jaeger distributed tracing
│   ├── external-secrets-values.yaml # External Secrets Operator
│   └── gatekeeper-values.yaml       # OPA Gatekeeper policy engine
├── manifests/                       # Kubernetes manifests
│   ├── namespaces.yaml              # Namespace definitions
│   ├── cluster-secret-store.yaml    # AWS Secrets Manager integration
│   ├── litellm-external-secret.yaml # LiteLLM secrets sync
│   ├── openwebui-external-secret.yaml # OpenWebUI secrets sync
│   └── opa-policies/                # OPA Gatekeeper policies
│       ├── templates/               # Policy templates
│       ├── constraints/             # Policy constraints
│       └── README.md                # Policy documentation
├── grafana_dashboards/
│   └── litellm-prometheus.json      # LiteLLM metrics dashboard
├── iam/                             # IAM policies for IRSA
│   ├── litellm-bedrock-policy.json  # Bedrock model access
│   ├── external-secrets-policy.json # Secrets Manager read access
│   └── trust-policy-template.json   # IRSA trust policy template
├── scripts/                         # Deployment automation
│   ├── deploy.sh                    # Main deployment script (interactive)
│   ├── setup-bastion.sh             # Bastion EC2 setup & access
│   └── README.md                    # Script usage guide
├── security/
│   └── ARCHITECTURE.md              # Security architecture details
├── CONTRIBUTING.md                  # Git workflow and contribution guide
└── README.md                        # This file
```

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI v2** installed and configured
3. **kubectl** installed (v1.28+)
4. **helm** installed (v3.0+)
5. **Terraform** (v1.5+) for infrastructure deployment

## Quick Start

### Deploy Full Infrastructure

```bash
# 1. Set environment variables
export AWS_REGION=us-east-1
export EKS_CLUSTER_NAME=litellm-eks

# 2. Configure Terraform
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Deploy full infrastructure
cd ../scripts
./deploy.sh terraform

# 4. Deploy applications
./deploy.sh all
```

**Time:** ~35 minutes total
**Best for:** Production deployments, complete infrastructure control

### Option 4: Complete End-to-End (Terraform)

```bash
cd scripts
./deploy.sh complete
```

This deploys everything: infrastructure + applications in one command.

### 5. Set Up Bastion for Testing

```bash
./scripts/setup-bastion.sh create
```

Then connect and access services:

```bash
# Connect using the script (auto-discovers instance ID):
./scripts/setup-bastion.sh connect

# Or manually via SSM:
aws ssm start-session --target i-xxxxx --region $AWS_REGION

# Inside bastion:
llm-ui          # Port-forward OpenWebUI to localhost:8080
llm-grafana     # Port-forward Grafana to localhost:3000
llm-prometheus  # Port-forward Prometheus to localhost:9090
```

## Manual Deployment (Without Script)

If you prefer to deploy manually without using the deploy script:

### 1. Set Environment Variables

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export EKS_CLUSTER_NAME=my-eks-cluster
export OIDC_PROVIDER=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --region $AWS_REGION \
    --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')
```

### 2. Create IAM Roles (IRSA)

```bash
# Create LiteLLM Bedrock role
cat > /tmp/litellm-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
        "${OIDC_PROVIDER}:sub": "system:serviceaccount:litellm:litellm-sa"
      }
    }
  }]
}
EOF

aws iam create-role --role-name litellm-bedrock-role \
    --assume-role-policy-document file:///tmp/litellm-trust-policy.json
aws iam put-role-policy --role-name litellm-bedrock-role \
    --policy-name bedrock-invoke --policy-document file://iam/litellm-bedrock-policy.json

# Create External Secrets role
cat > /tmp/eso-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
        "${OIDC_PROVIDER}:sub": "system:serviceaccount:external-secrets:external-secrets"
      }
    }
  }]
}
EOF

aws iam create-role --role-name external-secrets-role \
    --assume-role-policy-document file:///tmp/eso-trust-policy.json
aws iam put-role-policy --role-name external-secrets-role \
    --policy-name secrets-manager-read --policy-document file://iam/external-secrets-policy.json
```

### 3. Create Secrets in AWS Secrets Manager

```bash
# Database URL (required - use your RDS endpoint)
aws secretsmanager create-secret --name litellm/database-url \
    --secret-string 'postgresql://litellm:password@your-rds-endpoint:5432/litellm' \
    --region $AWS_REGION

# Master key (auto-generate)
aws secretsmanager create-secret --name litellm/master-key \
    --secret-string "sk-$(openssl rand -hex 32)" --region $AWS_REGION

# Redis password (auto-generate)
aws secretsmanager create-secret --name litellm/redis-password \
    --secret-string "$(openssl rand -hex 16)" --region $AWS_REGION

# Salt key (auto-generate - IMPORTANT: cannot be changed after deployment)
aws secretsmanager create-secret --name litellm/salt-key \
    --secret-string "$(openssl rand -hex 32)" --region $AWS_REGION
```

### 4. Update Configuration Files

Replace `ACCOUNT_ID` in helm values with your actual account ID:

```bash
sed -i "s/ACCOUNT_ID/$AWS_ACCOUNT_ID/g" helm-values/litellm-values.yaml
sed -i "s/ACCOUNT_ID/$AWS_ACCOUNT_ID/g" helm-values/external-secrets-values.yaml
sed -i "s/us-east-1/$AWS_REGION/g" manifests/cluster-secret-store.yaml
```

### 5. Add Helm Repositories

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo add dandydev https://dandydeveloper.github.io/charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add open-webui https://helm.openwebui.com/
helm repo update
```

### 6. Deploy Components

```bash
# Create namespaces
kubectl apply -f manifests/namespaces.yaml

# Deploy External Secrets Operator
helm upgrade --install external-secrets external-secrets/external-secrets \
    -n external-secrets -f helm-values/external-secrets-values.yaml --wait

# Wait for webhook to be ready
kubectl rollout status deployment/external-secrets-webhook -n external-secrets --timeout=120s

# Create secret stores and wait for them to be ready
kubectl apply -f manifests/cluster-secret-store.yaml
kubectl wait --for=condition=Ready clustersecretstore/aws-secrets-manager --timeout=60s

# Create ExternalSecrets
kubectl apply -f manifests/litellm-external-secret.yaml
kubectl apply -f manifests/openwebui-external-secret.yaml

# Wait for secrets to sync
kubectl wait --for=condition=Ready externalsecret/litellm-secrets -n litellm --timeout=60s
kubectl wait --for=condition=Ready externalsecret/openwebui-secrets -n open-webui --timeout=60s

# Deploy monitoring stack
helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack \
    -n monitoring -f helm-values/kube-prometheus-stack-values.yaml --wait

# Deploy Redis HA (uses official Redis image)
helm upgrade --install redis dandydev/redis-ha \
    -n litellm -f helm-values/redis-values.yaml --wait

# Deploy LiteLLM
helm pull oci://ghcr.io/berriai/litellm-helm --untar -d /tmp/
helm upgrade --install litellm /tmp/litellm-helm \
    -n litellm -f helm-values/litellm-values.yaml --wait

# Deploy OpenWebUI
helm upgrade --install open-webui open-webui/open-webui \
    -n open-webui -f helm-values/openwebui-values.yaml --wait
```

### 7. Verify Deployment

```bash
kubectl get pods -A | grep -E 'litellm|open-webui|prometheus|redis|external-secrets'
kubectl get externalsecret -A
```

## Configuration Details

### LiteLLM Models

Pre-configured models in `litellm-values.yaml`:

| Model Name | Bedrock Model | Max Tokens |
|------------|---------------|------------|
| claude-3.5-sonnet | anthropic.claude-3-5-sonnet-20241022-v2:0 | 8192 |
| claude-3-sonnet | anthropic.claude-3-sonnet-20240229-v1:0 | 4096 |
| claude-3-haiku | anthropic.claude-3-haiku-20240307-v1:0 | 4096 |
| claude-3-opus | anthropic.claude-3-opus-20240229-v1:0 | 4096 |
| llama-3.1-70b | meta.llama3-1-70b-instruct-v1:0 | 2048 |
| llama-3.1-8b | meta.llama3-1-8b-instruct-v1:0 | 2048 |
| mistral-large | mistral.mistral-large-2407-v1:0 | 4096 |

LiteLLM image version: `v1.80.5-stable` (pinned for stability)

### Secrets Required

Create these in AWS Secrets Manager before deployment:

| Secret Name | Description | Auto-Generated |
|-------------|-------------|----------------|
| `litellm/database-url` | PostgreSQL connection string | No (must create manually) |
| `litellm/master-key` | LiteLLM admin key | Yes |
| `litellm/redis-password` | Redis password | Yes |
| `litellm/salt-key` | Salt key for secure hashing (cannot be changed after deployment) | Yes |

The deploy script auto-generates `master-key`, `redis-password`, and `salt-key` if they don't exist. You must create `database-url` manually before running the deployment.

### IAM Roles

Two IRSA roles are created:

1. **litellm-bedrock-role** - Allows LiteLLM to invoke Bedrock models
2. **external-secrets-role** - Allows ESO to read from Secrets Manager

## MCP Server Deployment

Model Context Protocol (MCP) servers can be deployed as in-cluster pods to provide tools and capabilities to AI models. MCP servers enable access to external data sources (GitHub, S3), system operations (CLI, Docker), and third-party APIs (Slack, Jira).

See [docs/MCP_DEPLOYMENT.md](docs/MCP_DEPLOYMENT.md) for:
- Deployment requirements and best practices
- Complete annotated example (GitHub MCP server)
- Security configuration (IRSA, secrets, network policies)
- Monitoring integration (Prometheus, Jaeger)

## Accessing Services

From the bastion instance:

| Service | Command | URL |
|---------|---------|-----|
| OpenWebUI | `kubectl port-forward svc/open-webui 8080:80 -n open-webui --address 0.0.0.0` | http://localhost:8080 |
| Grafana | `kubectl port-forward svc/kube-prometheus-grafana 3000:80 -n monitoring --address 0.0.0.0` | http://localhost:3000 |
| Prometheus | `kubectl port-forward svc/kube-prometheus-kube-prome-prometheus 9090:9090 -n monitoring --address 0.0.0.0` | http://localhost:9090 |
| Jaeger UI | `kubectl port-forward svc/jaeger-query 16686:16686 -n monitoring --address 0.0.0.0` | http://localhost:16686 |

## Observability

The stack includes comprehensive observability with metrics, tracing, and dashboards.

### Prometheus Metrics

LiteLLM exposes metrics at `/metrics`:

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

### Distributed Tracing (OpenTelemetry + Jaeger)

LiteLLM is configured to export traces via OpenTelemetry to Jaeger. This enables:

- **End-to-end request tracing** - See the full journey from OpenWebUI → LiteLLM → Bedrock
- **Latency breakdown** - Identify bottlenecks in the request pipeline
- **Error debugging** - Trace failed requests to their root cause

Access Jaeger UI at `http://localhost:16686` (after port-forward).

### Grafana Dashboards

Pre-installed dashboards:

| Dashboard | Description |
|-----------|-------------|
| **LiteLLM Proxy** | Request rates, latency, token usage, model health, spend |
| **Kubernetes / Compute Resources** | Default K8s cluster dashboards |
| **Node Exporter** | Host-level metrics |

Additional dashboards from LiteLLM:
https://github.com/BerriAI/litellm/tree/main/cookbook/misc/grafana_dashboard

### Datasources in Grafana

- **Prometheus** - Metrics (auto-configured)
- **Jaeger** - Distributed traces

## Cleanup

```bash
# Delete bastion (also accepts 'delete')
./scripts/setup-bastion.sh cleanup

# Delete Helm releases
helm uninstall open-webui -n open-webui
helm uninstall litellm -n litellm
helm uninstall redis -n litellm
helm uninstall jaeger -n monitoring
helm uninstall kube-prometheus -n monitoring
helm uninstall external-secrets -n external-secrets

# Delete namespaces
kubectl delete -f manifests/namespaces.yaml

# Delete IAM roles (optional)
aws iam delete-role-policy --role-name litellm-bedrock-role --policy-name bedrock-invoke
aws iam delete-role --role-name litellm-bedrock-role
aws iam delete-role-policy --role-name external-secrets-role --policy-name secrets-manager-read
aws iam delete-role --role-name external-secrets-role
```

## Troubleshooting

### Secrets not syncing

```bash
kubectl describe externalsecret litellm-secrets -n litellm
kubectl logs -l app.kubernetes.io/name=external-secrets -n external-secrets
```

### LiteLLM not starting

```bash
kubectl logs -l app.kubernetes.io/name=litellm -n litellm
kubectl describe pod -l app.kubernetes.io/name=litellm -n litellm
```

### Bedrock access denied

1. Verify IRSA role has correct trust policy
2. Check Bedrock model access is enabled in AWS console
3. Verify service account annotation matches role ARN

```bash
kubectl get sa litellm-sa -n litellm -o yaml
```

## Documentation

### Getting Started
- **[DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)** - Complete step-by-step deployment walkthrough
- **[scripts/README.md](scripts/README.md)** - Deployment script usage and options
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Git workflow and contribution guidelines

### Infrastructure
- **[terraform/README.md](terraform/README.md)** - Terraform deployment guide

### Advanced Features
- **[ECR_SETUP.md](docs/ECR_SETUP.md)** - Container registry setup and usage
- **[MCP_DEPLOYMENT.md](docs/MCP_DEPLOYMENT.md)** - Deploy Model Context Protocol servers
- **[JWT_AUTHENTICATION_SETUP.md](docs/JWT_AUTHENTICATION_SETUP.md)** - Okta/JWT authentication setup
- **[OPA Policies](manifests/opa-policies/README.md)** - Security policy documentation
- **[Security Architecture](security/ARCHITECTURE.md)** - Security design and best practices

## Common Workflows

### Deploy Infrastructure and Applications
```bash
# Use Terraform for complete infrastructure
./scripts/deploy.sh terraform
./scripts/deploy.sh all
```

### Update Applications Only
```bash
# Update specific components
./scripts/deploy.sh litellm
./scripts/deploy.sh openwebui
```

### Complete Teardown
```bash
# Destroy everything
./scripts/deploy.sh infrastructure-destroy
```

## Future Enhancements

### Observability
- [ ] **Loki Integration** - Centralized log aggregation and querying
- [ ] **Grafana Tempo** - Long-term trace storage (Jaeger currently uses in-memory)
- [ ] **Alertmanager Integration** - Slack/PagerDuty notifications for critical alerts
- [ ] **Custom Dashboards** - Additional Grafana dashboards for business metrics

### Scalability & Performance
- [ ] **Horizontal Pod Autoscaling** - Auto-scale LiteLLM based on CPU/memory/custom metrics
- [ ] **Cluster Autoscaler** - Auto-scale EKS nodes based on demand
- [ ] **Multi-AZ Redis** - Distribute Redis across availability zones
- [ ] **CDN Integration** - CloudFront for static asset delivery

### Security
- [ ] **Network Policies** - Fine-grained pod-to-pod network security
- [ ] **Service Mesh** - Istio/Linkerd for mTLS and advanced traffic management
- [ ] **WAF Integration** - AWS WAF for application-layer protection
- [ ] **Secrets Rotation** - Automated secret rotation via AWS Secrets Manager
- [ ] **Pod Security Standards** - Enforce restricted security policies

### Developer Experience
- [ ] **GitOps** - ArgoCD or FluxCD for declarative deployments
- [ ] **CI/CD Pipeline** - GitHub Actions workflows for automated deployments
- [ ] **Local Development** - Kind/minikube setup for local testing
- [ ] **Staging Environment** - Separate environment for pre-production testing

### Features
- [ ] **Multi-Region Deployment** - Active-active or active-passive regional setup
- [ ] **Rate Limiting** - Per-user/per-model rate limiting
- [ ] **Cost Tracking** - Enhanced cost allocation and budgeting
- [ ] **Model Fine-tuning** - Integration with SageMaker for custom models
