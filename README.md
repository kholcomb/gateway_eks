# LiteLLM + OpenWebUI EKS Deployment

This directory contains all configuration files and scripts to deploy a complete AI/LLM infrastructure on AWS EKS.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           AWS EKS Cluster                               │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────────────────────────┐│
│  │  OpenWebUI  │──▶│   LiteLLM   │──▶│        Amazon Bedrock           ││
│  │  (Frontend) │   │   (Proxy)   │   │   (Claude, Llama, Mistral)      ││
│  └─────────────┘   └──────┬──────┘   └─────────────────────────────────┘│
│                           │                                              │
│  ┌────────────────────────┴────────────────────────────────────────────┐│
│  │                    Observability Stack                               ││
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────────┐ ││
│  │  │ Prometheus │◀─│  Metrics   │  │  Grafana   │  │  Alertmanager  │ ││
│  │  │            │  │ (litellm)  │  │ Dashboards │  │                │ ││
│  │  └────────────┘  └────────────┘  └─────┬──────┘  └────────────────┘ ││
│  │                                        │                             ││
│  │  ┌────────────┐  ┌────────────────────┐│                            ││
│  │  │   Jaeger   │◀─│ OpenTelemetry      ││  (Distributed Tracing)     ││
│  │  │   (OTLP)   │  │ Traces (litellm)   ││                            ││
│  │  └────────────┘  └────────────────────┘│                            ││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────────────┐ │
│  │ External Secrets │  │      Redis       │  │     EC2 Bastion        │ │
│  │    Operator      │  │    (caching)     │  │     (testing)          │ │
│  └────────┬─────────┘  └──────────────────┘  └────────────────────────┘ │
└───────────┼─────────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────┐   ┌─────────────────────┐
│  AWS Secrets Manager│   │     Amazon RDS      │
│  (API keys, creds)  │   │    (PostgreSQL)     │
└─────────────────────┘   └─────────────────────┘
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

## Directory Structure

```
k8s-deploy/
├── helm-values/
│   ├── litellm-values.yaml          # LiteLLM configuration (+ OpenTelemetry)
│   ├── openwebui-values.yaml        # OpenWebUI configuration
│   ├── redis-values.yaml            # Redis configuration
│   ├── kube-prometheus-stack-values.yaml  # Prometheus/Grafana config
│   ├── jaeger-values.yaml           # Jaeger distributed tracing
│   └── external-secrets-values.yaml # ESO configuration
├── manifests/
│   ├── namespaces.yaml              # Kubernetes namespaces
│   ├── cluster-secret-store.yaml    # AWS Secrets Manager store
│   ├── litellm-external-secret.yaml # LiteLLM + Redis secrets
│   └── openwebui-external-secret.yaml # OpenWebUI secrets
├── grafana_dashboards/
│   └── litellm-prometheus.json      # LiteLLM metrics dashboard
├── iam/
│   ├── litellm-bedrock-policy.json  # Bedrock access policy
│   ├── external-secrets-policy.json # Secrets Manager policy
│   └── trust-policy-template.json   # IRSA trust policy template
├── scripts/
│   ├── deploy.sh                    # Main deployment script
│   └── setup-bastion.sh             # Bastion EC2 setup
└── README.md
```

## Prerequisites

1. **EKS Cluster** with OIDC provider enabled
2. **Amazon RDS PostgreSQL** instance in the EKS VPC
3. **AWS CLI v2**, **kubectl**, **helm**, and **eksctl** installed
4. **gp3 StorageClass** available in your cluster

## Quick Start

### 1. Configure Environment Variables

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export EKS_CLUSTER_NAME=my-eks-cluster
```

### 2. Update Configuration Files

Edit the following files and replace placeholder values:

- `helm-values/litellm-values.yaml` - Set `ACCOUNT_ID` in IRSA annotation
- `helm-values/external-secrets-values.yaml` - Set `ACCOUNT_ID` in IRSA annotation
- `manifests/cluster-secret-store.yaml` - Set your AWS region

### 3. Create RDS PostgreSQL Database

Create an RDS instance in the EKS VPC and store the connection string:

```bash
aws secretsmanager create-secret \
  --name litellm/database-url \
  --secret-string 'postgresql://litellm:password@your-rds-endpoint:5432/litellm' \
  --region $AWS_REGION
```

### 4. Run the Deployment Script

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Run full deployment
./scripts/deploy.sh all

# Or run individual steps:
./scripts/deploy.sh validate          # Validate all YAML files (syntax + K8s spec)
./scripts/deploy.sh irsa              # Create IRSA roles
./scripts/deploy.sh secrets           # Create AWS secrets
./scripts/deploy.sh helm-repos        # Add Helm repos
./scripts/deploy.sh namespaces        # Create namespaces
./scripts/deploy.sh external-secrets  # Deploy ESO + create secret stores
./scripts/deploy.sh monitoring        # Deploy Prometheus/Grafana + dashboards
./scripts/deploy.sh jaeger            # Deploy Jaeger for distributed tracing
./scripts/deploy.sh redis             # Deploy Redis
./scripts/deploy.sh litellm           # Deploy LiteLLM
./scripts/deploy.sh openwebui         # Deploy OpenWebUI
./scripts/deploy.sh verify            # Verify deployment
```

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

## Future Enhancements

- Configure Alertmanager with Slack/PagerDuty
- Add network policies for pod-to-pod security
- Configure HPA for auto-scaling LiteLLM
- Add Loki for log aggregation
- Add Grafana Tempo for long-term trace storage (Jaeger uses in-memory by default)
- Consider service mesh (Istio/Linkerd) for mTLS and advanced traffic management
