# Architecture Documentation: LiteLLM EKS Deployment

## Overview

This document provides comprehensive architectural documentation for the LiteLLM EKS deployment, including system design, component interactions, data flows, and security architecture.

**Last Updated:** 2025-12-05
**Version:** 1.0
**Environment:** AWS EKS (Kubernetes)

---

## Table of Contents

1. [System Architecture Overview](#system-architecture-overview)
2. [Component Architecture](#component-architecture)
3. [Network Architecture](#network-architecture)
4. [Security Architecture](#security-architecture)
5. [Data Flow Diagrams](#data-flow-diagrams)
6. [Deployment Architecture](#deployment-architecture)
7. [High Availability & Resilience](#high-availability--resilience)
8. [Observability Architecture](#observability-architecture)

---

## System Architecture Overview

### High-Level Architecture

```mermaid
graph TB
    subgraph AWS["AWS Cloud (us-east-1)"]
        User([User]) -->|SSM Session Manager| Bastion[EC2 Bastion Host]

        subgraph EKS["EKS Cluster (VPC)"]
            Bastion -->|kubectl/port-forward| OpenWebUI

            subgraph NS_OpenWebUI["Namespace: open-webui"]
                OpenWebUI[OpenWebUI Pod x1]
                OpenWebUI_PV[(SQLite PV 10Gi)]
                OpenWebUI --> OpenWebUI_PV
            end

            subgraph NS_LiteLLM["Namespace: litellm"]
                LiteLLM[LiteLLM Proxy x2]
                Redis[Redis HA x3 + Sentinel]
                Redis_PV[(8Gi PV x3)]
                Redis --> Redis_PV
                LiteLLM --> Redis
            end

            subgraph NS_Monitoring["Namespace: monitoring"]
                Prometheus[Prometheus]
                Grafana[Grafana]
                Jaeger[Jaeger]
                Prometheus_PV[(50Gi PV)]
                Grafana_PV[(10Gi PV)]
                Prometheus --> Prometheus_PV
                Grafana --> Grafana_PV
            end

            subgraph NS_ESO["Namespace: external-secrets"]
                ESO[External Secrets Operator]
            end

            OpenWebUI -->|HTTP| LiteLLM
            Prometheus -->|Scrape /metrics| LiteLLM
            LiteLLM -->|OTLP Traces| Jaeger
            Grafana -->|Query| Prometheus
            Grafana -->|Query| Jaeger
        end

        LiteLLM -->|IRSA Auth| Bedrock[AWS Bedrock<br/>7 Models]
        LiteLLM -->|SSL/TLS| RDS[(Amazon RDS PostgreSQL)]
        ESO -->|IRSA Auth| SecretsManager[AWS Secrets Manager]
        ESO -->|Sync Secrets| NS_LiteLLM
        ESO -->|Sync Secrets| NS_OpenWebUI

        subgraph IRSA["IAM Roles for Service Accounts"]
            Role1[litellm-bedrock-role]
            Role2[external-secrets-role]
        end

        LiteLLM -.->|Uses| Role1
        ESO -.->|Uses| Role2
    end

    style User fill:#e1f5ff
    style Bastion fill:#fff4e1
    style LiteLLM fill:#d4f1d4
    style OpenWebUI fill:#d4f1d4
    style Redis fill:#ffd4d4
    style Prometheus fill:#e8d4f1
    style Grafana fill:#e8d4f1
    style Jaeger fill:#e8d4f1
    style Bedrock fill:#fff4d4
    style RDS fill:#fff4d4
    style SecretsManager fill:#fff4d4
    style ESO fill:#d4e8f1
```

### Key Characteristics

- **Architecture Pattern:** Microservices on Kubernetes
- **Deployment Model:** Multi-namespace, single-cluster
- **Security Model:** Defense in depth with IRSA, secrets management, network isolation
- **Availability Model:** High availability with replica sets, anti-affinity, PDBs
- **Observability Model:** Full-stack monitoring with metrics, logs, and traces

---

## Component Architecture

### Application Layer

#### OpenWebUI (Frontend)

```mermaid
graph TB
    subgraph OpenWebUI_Pod["OpenWebUI Pod"]
        WebServer[Web Server<br/>Python/FastAPI<br/>• Chat Interface<br/>• User Authentication<br/>• Session Management]
        SQLite[(SQLite Database<br/>PersistentVolume<br/>• User Profiles<br/>• Chat History<br/>• Preferences)]

        WebServer --> SQLite
    end

    Security["Security Context:<br/>• runAsUser: 1000<br/>• fsGroup: 1000<br/>• 10Gi gp3 PV"]

    Config["Configuration:<br/>• Replicas: 1<br/>• Service: ClusterIP :80<br/>• Resource Limits: Defined<br/>• Health Checks: HTTP"]

    style OpenWebUI_Pod fill:#d4f1d4
    style WebServer fill:#e8f9e8
    style SQLite fill:#ffd4d4
    style Security fill:#fff9e8
    style Config fill:#f9f9f9
```

#### LiteLLM Proxy (API Gateway)

```mermaid
graph TB
    subgraph LiteLLM_Pod["LiteLLM Proxy Pod"]
        Core[LiteLLM Core Python<br/>• OpenAI-compatible API<br/>• Model routing & load balancing<br/>• Request/response transformation<br/>• Auth Master Key]

        Cache[Rate Limiting & Caching<br/>• Redis integration<br/>• Response caching 1h TTL<br/>• Session management]

        Observability[Observability<br/>• Prometheus /metrics<br/>• OTLP traces to Jaeger<br/>• Structured logging]

        AWS[AWS Integration<br/>• Bedrock API boto3<br/>• IRSA authentication<br/>• PostgreSQL RDS]

        Core --> Cache
        Core --> Observability
        Core --> AWS
    end

    Config["Configuration:<br/>• Replicas: 2 anti-affinity<br/>• Service: ClusterIP :4000<br/>• PDB: minAvailable=1<br/>• Max Request: 50MB"]

    style LiteLLM_Pod fill:#d4f1d4
    style Core fill:#e8f9e8
    style Cache fill:#fff9e8
    style Observability fill:#e8e8ff
    style AWS fill:#fff4d4
    style Config fill:#f9f9f9
```

**Model Configuration (7 Models):**
1. Claude 3.5 Sonnet v2 (8192 tokens)
2. Claude 3 Sonnet (4096 tokens)
3. Claude 3 Haiku (4096 tokens)
4. Claude 3 Opus (4096 tokens)
5. Llama 3.1 70B (2048 tokens)
6. Llama 3.1 8B (2048 tokens)
7. Mistral Large (4096 tokens)

### Data Layer

#### Redis HA Cluster

```mermaid
graph TB
    subgraph Redis_HA["Redis High Availability"]
        Master[Redis Pod 1<br/>Master<br/>8Gi PV gp3]
        Replica1[Redis Pod 2<br/>Replica<br/>8Gi PV gp3]
        Replica2[Redis Pod 3<br/>Replica<br/>8Gi PV gp3]

        Master -->|Replication| Replica1
        Master -->|Replication| Replica2

        Sentinel[Redis Sentinel<br/>Quorum=2<br/>• Master election<br/>• Automatic failover<br/>• Config management]

        Master -.->|Monitor| Sentinel
        Replica1 -.->|Monitor| Sentinel
        Replica2 -.->|Monitor| Sentinel
    end

    Config["Configuration:<br/>• Replicas: 3 (hard anti-affinity)<br/>• Auth: Password from Secrets Mgr<br/>• Service: ClusterIP :6379<br/>• PDB: maxUnavailable=1<br/>• Persistence: AOF + RDB"]

    style Master fill:#ffd4d4
    style Replica1 fill:#ffe8e8
    style Replica2 fill:#ffe8e8
    style Sentinel fill:#d4e8f1
    style Config fill:#f9f9f9
```

#### Amazon RDS PostgreSQL

```mermaid
graph TB
    subgraph RDS["RDS PostgreSQL (External)"]
        subgraph Schema["Database Schema"]
            T1[users<br/>User accounts & profiles]
            T2[api_keys<br/>Key hashes & metadata]
            T3[request_logs<br/>LLM request audit trail]
            T4[usage_metrics<br/>Token consumption]
            T5[model_configs<br/>LiteLLM configurations]
        end

        subgraph Security["Security"]
            S1[SSL/TLS Connection]
            S2[Auth: Username/Password<br/>from Secrets Manager]
            S3[Private Subnet<br/>VPC-only access]
            S4[At-rest Encryption<br/>recommended]
        end
    end

    style RDS fill:#fff4d4
    style Schema fill:#ffe8e8
    style Security fill:#e8ffe8
    style T1 fill:#f9f9f9
    style T2 fill:#f9f9f9
    style T3 fill:#f9f9f9
    style T4 fill:#f9f9f9
    style T5 fill:#f9f9f9
    style S1 fill:#f9f9f9
    style S2 fill:#f9f9f9
    style S3 fill:#f9f9f9
    style S4 fill:#f9f9f9
```

### Observability Layer

#### Prometheus Stack

```mermaid
graph TB
    subgraph Prom_Ecosystem["Prometheus Ecosystem"]
        PromServer[Prometheus Server<br/>• TSDB: 50Gi gp3 PV<br/>• Scrape every 30s<br/>• 15-day retention<br/>• PromQL query engine]

        subgraph ServiceMon["ServiceMonitors"]
            SM1[litellm-proxy<br/>/metrics]
            SM2[redis-exporter]
            SM3[node-exporter<br/>host metrics]
            SM4[kube-state-metrics<br/>K8s objects]
        end

        Alertmgr[Alertmanager<br/>5Gi gp3 PV<br/>• Alert routing<br/>• Notifications TODO<br/>• Silencing rules]

        SM1 -->|Scrape| PromServer
        SM2 -->|Scrape| PromServer
        SM3 -->|Scrape| PromServer
        SM4 -->|Scrape| PromServer

        PromServer -->|Alerts| Alertmgr
    end

    style PromServer fill:#e8d4f1
    style ServiceMon fill:#f9f9f9
    style Alertmgr fill:#ffe8e8
    style SM1 fill:#e8f9e8
    style SM2 fill:#e8f9e8
    style SM3 fill:#e8f9e8
    style SM4 fill:#e8f9e8
```

**Metrics Collected:**
- **LiteLLM:** Requests, latency, tokens, spend, errors, model health
- **Redis:** Connections, memory, hit rate, latency, replication lag
- **Kubernetes:** Pod status, resource usage, node health, volume capacity
- **Infrastructure:** CPU, memory, disk I/O, network throughput

#### Jaeger (Distributed Tracing)

```mermaid
graph TB
    subgraph Jaeger["Jaeger All-in-One"]
        Collector[OTLP Collector<br/>• gRPC :4317<br/>• HTTP :4318]
        Storage[(In-Memory Storage<br/>Max 50k traces<br/>Ephemeral)]
        Query[Query Service<br/>• Trace search<br/>• Grafana datasource<br/>• Dependency graphs]

        Collector -->|Store| Storage
        Storage -->|Query| Query
    end

    LiteLLM_Traces[LiteLLM Traces] -->|Push OTLP| Collector

    Note["Trace Context:<br/>OpenWebUI → LiteLLM → Redis → Bedrock<br/>Metadata: User ID, model, tokens, latency"]

    style Collector fill:#e8d4f1
    style Storage fill:#ffd4d4
    style Query fill:#e8d4f1
    style LiteLLM_Traces fill:#d4f1d4
    style Note fill:#ffffcc
```

#### Grafana (Visualization)

```mermaid
graph TB
    subgraph Grafana["Grafana"]
        DS[Datasources<br/>• Prometheus<br/>• Jaeger]

        subgraph Dashboards["Pre-configured Dashboards"]
            D1[LiteLLM Overview<br/>Requests, latency, spend]
            D2[Model Health<br/>Per-model metrics]
            D3[Kubernetes Cluster<br/>Node/pod resources]
            D4[Redis Performance<br/>Cache, memory, replication]
        end

        DS --> Dashboards
    end

    Storage[Storage: 10Gi gp3 PV]
    Service[Service: ClusterIP :80]

    Grafana -.->|Uses| Storage
    Grafana -.->|Exposed via| Service

    style Grafana fill:#e8d4f1
    style DS fill:#f9f9f9
    style Dashboards fill:#e8f9e8
    style D1 fill:#fff9e8
    style D2 fill:#fff9e8
    style D3 fill:#fff9e8
    style D4 fill:#fff9e8
    style Storage fill:#ffd4d4
    style Service fill:#d4e8f1
```

### Secrets Management

#### External Secrets Operator (ESO)

```mermaid
graph TD
    ASM[AWS Secrets Manager<br/>Source of Truth]
    ASM -->|litellm/database-url| ASM
    ASM -->|litellm/master-key| ASM
    ASM -->|litellm/salt-key<br/>IMMUTABLE!| ASM
    ASM -->|litellm/redis-password| ASM

    ASM -->|IRSA Auth<br/>external-secrets-role| CSS[ClusterSecretStore]

    CSS -->|Refresh every 1h<br/>JWT Auth| ES1[ExternalSecret:<br/>litellm-secrets]
    CSS -->|Refresh every 1h<br/>JWT Auth| ES2[ExternalSecret:<br/>redis-credentials]
    CSS -->|Refresh every 1h<br/>JWT Auth| ES3[ExternalSecret:<br/>openwebui-secrets]

    ES1 -->|Creates/Updates| K8S1[K8s Secret<br/>litellm namespace]
    ES2 -->|Creates/Updates| K8S2[K8s Secret<br/>litellm namespace]
    ES3 -->|Creates/Updates| K8S3[K8s Secret<br/>open-webui namespace]

    K8S1 -->|Mounted as<br/>env vars| LiteLLM[LiteLLM Pods]
    K8S2 -->|Mounted as<br/>env vars| Redis[Redis Pods]
    K8S3 -->|Mounted as<br/>env vars| OpenWebUI[OpenWebUI Pods]

    style ASM fill:#fff4d4
    style CSS fill:#d4e8f1
    style ES1 fill:#d4e8f1
    style ES2 fill:#d4e8f1
    style ES3 fill:#d4e8f1
    style K8S1 fill:#ffd4d4
    style K8S2 fill:#ffd4d4
    style K8S3 fill:#ffd4d4
    style LiteLLM fill:#d4f1d4
    style Redis fill:#ffd4d4
    style OpenWebUI fill:#d4f1d4
```

---

## Network Architecture

### Service Mesh & Communication

```mermaid
graph TB
    User([User at Bastion]) -->|kubectl port-forward| OpenWebUI_Svc

    subgraph K8s["Kubernetes Service Network"]
        OpenWebUI_Svc[OpenWebUI Service<br/>ClusterIP<br/>open-webui.open-webui.svc:80]
        LiteLLM_Svc[LiteLLM Service<br/>ClusterIP<br/>litellm-proxy.litellm.svc:4000]
        Redis_Svc[Redis Service<br/>ClusterIP :6379]
        Jaeger_Svc[Jaeger Service<br/>ClusterIP<br/>• OTLP gRPC: 4317<br/>• OTLP HTTP: 4318<br/>• Query: 16686]

        OpenWebUI_Svc -->|HTTP| LiteLLM_Svc
        LiteLLM_Svc -->|TCP| Redis_Svc
        LiteLLM_Svc -->|HTTP| Jaeger_Svc
        Prometheus[Prometheus] -->|Scrape :4000| LiteLLM_Svc
    end

    LiteLLM_Svc -->|HTTPS| Bedrock[AWS Bedrock API<br/>External]

    style OpenWebUI_Svc fill:#d4f1d4
    style LiteLLM_Svc fill:#d4f1d4
    style Redis_Svc fill:#ffd4d4
    style Jaeger_Svc fill:#e8d4f1
    style Prometheus fill:#e8d4f1
    style Bedrock fill:#fff4d4
    style User fill:#e1f5ff
```

### Network Security Zones

```mermaid
graph TB
    Internet[SECURITY ZONE: Public Internet<br/>• No direct exposure<br/>• All services use ClusterIP]

    Internet -->|SSM Session Manager| Bastion

    Bastion[SECURITY ZONE: Bastion<br/>EC2 Instance<br/>• Access: SSM only no SSH<br/>• IAM Role: Bastion SSM + EKS<br/>• kubectl, port-forwarding]

    Bastion -->|kubectl API + port-forward| EKS_Cluster

    subgraph EKS_Cluster[SECURITY ZONE: Kubernetes Cluster EKS VPC]
        subgraph NS_OpenWebUI[NAMESPACE: open-webui]
            OW[OpenWebUI pods<br/>• Ingress: Port-fwd from bastion<br/>• Egress: LiteLLM service only]
        end

        subgraph NS_LiteLLM[NAMESPACE: litellm]
            LL[LiteLLM proxy pods<br/>IRSA: litellm-bedrock-role<br/>Redis HA pods<br/>• Ingress: OpenWebUI, Prometheus, Bastion<br/>• Egress: Bedrock, RDS, Redis, Jaeger]
        end

        subgraph NS_Monitoring[NAMESPACE: monitoring]
            Mon[Prometheus, Grafana<br/>Alertmanager, Jaeger<br/>• Ingress: Port-fwd from bastion<br/>• Egress: Scrape targets]
        end

        subgraph NS_ESO[NAMESPACE: external-secrets]
            ESO[ESO pods<br/>IRSA: external-secrets-role<br/>• Ingress: K8s API only<br/>• Egress: AWS Secrets Manager]
        end
    end

    LL -->|IRSA auth| Bedrock[SECURITY ZONE: AWS<br/>Bedrock<br/>• IRSA auth only]
    LL -->|SSL/TLS| RDS[AWS RDS<br/>PostgreSQL<br/>• VPC-only]
    ESO -->|IRSA auth| SecretsManager[AWS Secrets Manager<br/>• IRSA auth only]

    style Internet fill:#ffe8e8
    style Bastion fill:#fff4e1
    style EKS_Cluster fill:#e8f9e8
    style NS_OpenWebUI fill:#d4f1d4
    style NS_LiteLLM fill:#d4f1d4
    style NS_Monitoring fill:#e8d4f1
    style NS_ESO fill:#d4e8f1
    style Bedrock fill:#fff4d4
    style RDS fill:#fff4d4
    style SecretsManager fill:#fff4d4
```

**Recommended Network Policies** (not yet implemented):
```yaml
# Example: Allow only LiteLLM → Redis
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: redis-ingress
  namespace: litellm
spec:
  podSelector:
    matchLabels:
      app: redis
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: litellm-proxy
    ports:
    - protocol: TCP
      port: 6379
```

---

## Security Architecture

### Authentication & Authorization Flow

```mermaid
graph LR
    User([User])

    User -->|SSM MFA| Bastion[Bastion]
    Bastion -->|kubectl| EKS_RBAC[EKS RBAC]

    User -->|Session Auth| OpenWebUI
    OpenWebUI -->|Master Key| LiteLLM
    LiteLLM -->|username/password| PostgreSQL
    LiteLLM -->|IRSA temporary creds| Bedrock[Bedrock API]

    style User fill:#e1f5ff
    style Bastion fill:#fff4e1
    style EKS_RBAC fill:#d4e8f1
    style OpenWebUI fill:#d4f1d4
    style LiteLLM fill:#d4f1d4
    style PostgreSQL fill:#fff4d4
    style Bedrock fill:#fff4d4
```

### IAM Roles for Service Accounts (IRSA)

```mermaid
graph TB
    OIDC[EKS OIDC Provider<br/>• Trust: K8s ServiceAccount ↔ IAM Role<br/>• Token projection via webhook]

    OIDC --> Role1
    OIDC --> Role2
    OIDC --> Role3

    Role1[Role 1: LiteLLM<br/>Permissions:<br/>• bedrock:InvokeModel<br/>• bedrock:InvokeModelWithResponseStream<br/>• bedrock:ListFoundationModels]

    Role2[Role 2: External Secrets<br/>Permissions:<br/>• secretsmanager:GetSecretValue<br/>• secretsmanager:DescribeSecret<br/>litellm/* only]

    Role3[Role 3: Bastion SSM<br/>Permissions:<br/>• ssm:StartSession<br/>• eks:DescribeCluster]

    style OIDC fill:#d4e8f1
    style Role1 fill:#d4f1d4
    style Role2 fill:#e8d4f1
    style Role3 fill:#fff4e1
```

### Secrets Management Architecture

```mermaid
graph TB
    subgraph Phase1["Creation Phase (deploy.sh)"]
        C1[1. Check if secret exists<br/>in AWS Secrets Manager]
        C2[2. If missing, generate<br/>random value<br/>openssl rand]
        C3[3. Store in AWS<br/>Secrets Manager]
        C1 --> C2 --> C3
    end

    subgraph Phase2["Sync Phase (ESO)"]
        S1[1. ESO watches<br/>ExternalSecret CRDs]
        S2[2. Authenticate via IRSA<br/>no static creds]
        S3[3. Fetch secrets<br/>every 1h]
        S4[4. Create/update<br/>K8s Secret objects]
        S1 --> S2 --> S3 --> S4
    end

    subgraph Phase3["Consumption Phase"]
        P1[1. Secrets mounted as<br/>environment variables]
        P2[2. Never written to disk<br/>memory-backed]
        P3[3. Redacted from<br/>kubectl describe/logs]
        P1 --> P2 --> P3
    end

    Phase1 --> Phase2 --> Phase3

    Warning["⚠️ CRITICAL: salt-key cannot be rotated!<br/>Rotation invalidates all encrypted data"]

    style Phase1 fill:#fff9e8
    style Phase2 fill:#e8f9f9
    style Phase3 fill:#e8f9e8
    style Warning fill:#ffe8e8
```

### Security Controls Matrix

| Control Type | Implementation | Status |
|--------------|----------------|--------|
| **Authentication** | Master key (LiteLLM), IRSA (AWS), Session auth (OpenWebUI) | ✅ Implemented |
| **Authorization** | Kubernetes RBAC, IAM policies, API key validation | ✅ Implemented |
| **Encryption (Transit)** | TLS for Bedrock API, RDS SSL recommended | ⚠️ Partial |
| **Encryption (Rest)** | EBS encryption, RDS encryption recommended, etcd encryption | ⚠️ Partial |
| **Network Isolation** | ClusterIP services, no public ingress | ✅ Implemented |
| **Network Segmentation** | Namespace separation, NetworkPolicy (TODO) | ⚠️ Partial |
| **Secrets Management** | AWS Secrets Manager + ESO, no hardcoded secrets | ✅ Implemented |
| **Least Privilege** | IRSA scoped permissions, non-root containers | ✅ Implemented |
| **Audit Logging** | Prometheus metrics, Jaeger traces, K8s audit logs (TODO) | ⚠️ Partial |
| **High Availability** | Multi-replica, anti-affinity, PDBs, health checks | ✅ Implemented |
| **Resource Limits** | CPU/memory limits on all pods | ✅ Implemented |
| **Image Security** | Pinned versions, official charts, Dependabot updates | ✅ Implemented |
| **Pod Security** | Non-root users (partial), PSS enforcement (TODO) | ⚠️ Partial |
| **Service Mesh/mTLS** | Not implemented (planned enhancement) | ❌ Not Implemented |

---

## Data Flow Diagrams

### Request Flow (Happy Path)

```mermaid
sequenceDiagram
    actor User
    participant Bastion as EC2 Bastion
    participant OpenWebUI
    participant LiteLLM as LiteLLM Proxy
    participant PostgreSQL as RDS PostgreSQL
    participant Redis as Redis HA
    participant Bedrock as AWS Bedrock
    participant Prometheus
    participant Jaeger

    User->>Bastion: 1. SSH/SSM Session
    User->>Bastion: 2. kubectl port-forward<br/>open-webui:80
    User->>OpenWebUI: 3. HTTP POST /api/chat
    OpenWebUI->>LiteLLM: 4. Forward request<br/>POST /chat/completions

    LiteLLM->>PostgreSQL: 5. Validate API key<br/>(Master Key)
    PostgreSQL-->>LiteLLM: OK

    LiteLLM->>Redis: 6. Check cache
    Redis-->>LiteLLM: MISS

    LiteLLM->>Bedrock: 7. Invoke model<br/>(IRSA auth)
    Bedrock-->>LiteLLM: 8. Stream response

    LiteLLM->>Redis: 9. Cache response<br/>(1h TTL)
    LiteLLM->>Prometheus: 10. Export metrics
    LiteLLM->>Jaeger: 11. Send trace (OTLP)

    LiteLLM-->>OpenWebUI: 12. Return response
    OpenWebUI-->>User: 13. Display in chat UI
```

### Observability Data Flow

```mermaid
graph LR
    LiteLLM[LiteLLM Proxy]

    subgraph Metrics["Metrics Collection"]
        LiteLLM -->|Pull /metrics<br/>every 30s| Prometheus
        Prometheus -->|Store 15d| TSDB[(Time-Series DB<br/>50Gi PV)]
        TSDB -->|Query PromQL| Grafana
    end

    subgraph Traces["Distributed Tracing"]
        LiteLLM -->|Push OTLP HTTP<br/>:4318| Jaeger[Jaeger Collector]
        Jaeger -->|Store| InMem[(In-Memory<br/>50k traces)]
        InMem -->|Query| Grafana
    end

    Grafana -->|Port-forward| Bastion[EC2 Bastion]
    Bastion -->|Access| User([User])

    style LiteLLM fill:#d4f1d4
    style Prometheus fill:#e8d4f1
    style Jaeger fill:#e8d4f1
    style Grafana fill:#e8d4f1
    style TSDB fill:#ffd4d4
    style InMem fill:#ffd4d4
    style Bastion fill:#fff4e1
    style User fill:#e1f5ff
```

---

## Deployment Architecture

### Deployment Workflow

```mermaid
flowchart TD
    Start([deploy.sh]) --> Step1

    Step1[1. Pre-deployment Validation<br/>• YAML syntax validation<br/>• K8s schema validation<br/>• AWS credential check<br/>• EKS cluster connectivity]

    Step1 --> Step2

    Step2[2. IAM Infrastructure<br/>IRSA Roles<br/>• Create litellm-bedrock-role<br/>• Create external-secrets-role<br/>• Attach trust policies OIDC<br/>• Attach permission policies]

    Step2 --> Step3

    Step3[3. Secrets Initialization<br/>• Generate random values if not exist<br/>• Store in AWS Secrets Manager:<br/>  - litellm/database-url manual<br/>  - litellm/master-key auto<br/>  - litellm/salt-key auto IMMUTABLE<br/>  - litellm/redis-password auto]

    Step3 --> Step4

    Step4[4. Kubernetes Setup<br/>• Add Helm repositories 6 repos<br/>• Create namespaces 4 namespaces<br/>• Apply storage class gp3]

    Step4 --> Step5

    Step5[5. External Secrets Operator<br/>• Deploy ESO Helm chart v0.12.1<br/>• Wait for webhook readiness<br/>• Create ClusterSecretStore<br/>• Create ExternalSecret resources<br/>• Verify secret sync]

    Step5 --> Step6

    Step6[6. Observability Stack<br/>• Deploy kube-prometheus-stack<br/>• Deploy Jaeger<br/>• Apply ServiceMonitors<br/>• Import Grafana dashboards<br/>• Wait for all pods ready]

    Step6 --> Step7

    Step7[7. Data Layer<br/>• Deploy Redis HA<br/>  3 replicas + Sentinel<br/>• Wait for Redis ready<br/>• Verify Sentinel quorum]

    Step7 --> Step8

    Step8[8. Application Layer<br/>• Deploy LiteLLM proxy 2 replicas<br/>• Deploy OpenWebUI 1 replica<br/>• Wait for readiness probes]

    Step8 --> Step9

    Step9[9. Post-deployment Verification<br/>• Health check all services<br/>• Test LiteLLM /health/liveliness<br/>• Verify Prometheus metrics<br/>• Display access instructions]

    Step9 --> Done([Deployment Complete])

    style Start fill:#e1f5ff
    style Step1 fill:#fff9e8
    style Step2 fill:#ffe8e8
    style Step3 fill:#ffe8e8
    style Step4 fill:#e8f9e8
    style Step5 fill:#d4e8f1
    style Step6 fill:#e8d4f1
    style Step7 fill:#ffd4d4
    style Step8 fill:#d4f1d4
    style Step9 fill:#e8f9e8
    style Done fill:#d4f1d4
```

### Namespace Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                     EKS Cluster Namespaces                      │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  open-webui                                              │  │
│  │  ├── Deployment: openwebui (1 replica)                  │  │
│  │  ├── Service: ClusterIP (port 80)                       │  │
│  │  ├── PVC: 10Gi gp3 (SQLite database)                    │  │
│  │  └── Secret: openwebui-secrets (synced from ESO)        │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  litellm                                                 │  │
│  │  ├── Deployment: litellm-proxy (2 replicas)             │  │
│  │  ├── Service: ClusterIP (port 4000)                     │  │
│  │  ├── ServiceAccount: litellm-sa (IRSA annotated)        │  │
│  │  ├── PodDisruptionBudget: minAvailable=1                │  │
│  │  ├── Secret: litellm-secrets (ESO synced)               │  │
│  │  ├── Secret: redis-credentials (ESO synced)             │  │
│  │  ├── StatefulSet: redis-ha (3 replicas)                 │  │
│  │  ├── Service: redis-ha (ClusterIP port 6379)            │  │
│  │  ├── Service: redis-ha-announce-* (headless)            │  │
│  │  ├── PVC: redis-data-* (8Gi gp3 × 3)                    │  │
│  │  └── PodDisruptionBudget: redis-ha maxUnavailable=1     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  monitoring                                              │  │
│  │  ├── StatefulSet: prometheus (1 replica)                │  │
│  │  ├── PVC: prometheus-data (50Gi gp3)                    │  │
│  │  ├── Deployment: grafana (1 replica)                    │  │
│  │  ├── PVC: grafana-storage (10Gi gp3)                    │  │
│  │  ├── StatefulSet: alertmanager (1 replica)              │  │
│  │  ├── PVC: alertmanager-data (5Gi gp3)                   │  │
│  │  ├── Deployment: jaeger (1 replica)                     │  │
│  │  ├── Service: jaeger-collector (ClusterIP)              │  │
│  │  ├── Service: jaeger-query (ClusterIP port 16686)       │  │
│  │  ├── DaemonSet: node-exporter (all nodes)               │  │
│  │  ├── Deployment: kube-state-metrics                     │  │
│  │  └── ServiceMonitor: litellm-proxy, redis-exporter      │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  external-secrets                                        │  │
│  │  ├── Deployment: external-secrets (1 replica)           │  │
│  │  ├── Deployment: external-secrets-webhook               │  │
│  │  ├── Deployment: external-secrets-cert-controller       │  │
│  │  ├── ServiceAccount: external-secrets (IRSA)            │  │
│  │  ├── ClusterSecretStore: aws-secretsmanager             │  │
│  │  ├── ExternalSecret: litellm-secrets → litellm ns       │  │
│  │  ├── ExternalSecret: redis-credentials → litellm ns     │  │
│  │  └── ExternalSecret: openwebui-secrets → open-webui ns  │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## High Availability & Resilience

### Failure Scenarios & Mitigations

| Scenario | Impact | Mitigation | Recovery Time |
|----------|--------|------------|---------------|
| **Single LiteLLM pod crash** | 50% capacity reduction | 2 replicas with anti-affinity, PDB minAvailable=1 | <30s (readiness probe) |
| **Redis master failure** | Temporary cache unavailability | Sentinel auto-failover to replica, quorum=2 | <5s (failover) |
| **Redis complete outage** | No caching, rate limiting degraded | LiteLLM should handle gracefully (fallback to direct Bedrock calls) | Service-dependent |
| **PostgreSQL connection loss** | API key validation fails | RDS Multi-AZ recommended, connection retry logic | 60-120s (RDS failover) |
| **Bedrock API throttling** | Request failures | Exponential backoff, multi-model fallback (LiteLLM feature) | Variable |
| **Prometheus pod restart** | 15-min metrics gap | Persistent volume preserves historical data | 30-60s (pod restart) |
| **Jaeger pod restart** | Loss of in-memory traces | Recommendation: Use persistent backend (Elasticsearch) | 30-60s (no data recovery) |
| **EKS node failure** | Pods reschedule to other nodes | Multi-replica, pod anti-affinity, cluster autoscaler | 1-3 min (reschedule) |
| **AZ outage** | Depends on node distribution | Multi-AZ node groups recommended | Variable |
| **Secrets sync failure** | Pods use last-synced secrets | ESO retry logic, 1h refresh interval | 1h max (next sync) |

### Health Check Configuration

```yaml
# LiteLLM Health Checks
livenessProbe:
  httpGet:
    path: /health/liveliness
    port: 4000
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /health/readiness
    port: 4000
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 3

# Redis Health Checks
livenessProbe:
  exec:
    command:
      - redis-cli
      - ping
  periodSeconds: 10

readinessProbe:
  exec:
    command:
      - redis-cli
      - ping
  periodSeconds: 5
```

### Resource Quotas & Limits

```yaml
# Example resource configuration
resources:
  requests:
    cpu: 500m      # Guaranteed CPU
    memory: 1Gi    # Guaranteed memory
  limits:
    cpu: 2000m     # Max CPU (throttled if exceeded)
    memory: 4Gi    # Max memory (OOMKilled if exceeded)
```

**Recommendations:**
- Set requests = limits for guaranteed QoS (critical services)
- Monitor resource usage with Prometheus and adjust limits
- Implement HPA (Horizontal Pod Autoscaler) for LiteLLM based on CPU/request rate

---

## Observability Architecture

### Monitoring Strategy

```mermaid
graph TB
    subgraph Observability["Three Pillars of Observability"]
        Metrics[METRICS<br/>• Prometheus<br/>• 15d retention<br/>• PromQL<br/>• Alerting]
        Logs[LOGS<br/>• stdout/stderr<br/>• kubectl logs<br/>• TODO: Loki]
        Traces[TRACES<br/>• Jaeger<br/>• OTLP HTTP<br/>• In-memory<br/>• 50k traces]
    end

    Metrics --> Grafana[Grafana<br/>Unified View]
    Logs --> Grafana
    Traces --> Grafana

    style Metrics fill:#e8d4f1
    style Logs fill:#fff9e8
    style Traces fill:#d4e8f1
    style Grafana fill:#e8f9e8
    style Observability fill:#f9f9f9
```

### Key Metrics & Alerts

**LiteLLM Metrics:**
```promql
# Request rate by model
rate(litellm_proxy_total_requests_metric[5m])

# Error rate
rate(litellm_proxy_failed_requests_metric[5m]) / rate(litellm_proxy_total_requests_metric[5m])

# P95 latency
histogram_quantile(0.95, rate(litellm_request_total_latency_metric_bucket[5m]))

# Token spend rate (cost tracking)
rate(litellm_spend_metric[1h])

# Model health (0=healthy, 1=partial, 2=outage)
litellm_deployment_state
```

**Redis Metrics:**
```promql
# Cache hit rate
redis_keyspace_hits_total / (redis_keyspace_hits_total + redis_keyspace_misses_total)

# Memory usage
redis_memory_used_bytes / redis_memory_max_bytes

# Replication lag
redis_master_repl_offset - redis_slave_repl_offset
```

**Recommended Alerts:**
- LiteLLM error rate > 5% (5 min window)
- LiteLLM P95 latency > 10s
- Redis cache hit rate < 50%
- Redis memory usage > 90%
- Bedrock API spend > $X/hour
- Pod restart count > 3 (1 hour window)

---

## Appendix

### Technology Stack Summary

| Category | Technology | Version | Purpose |
|----------|-----------|---------|---------|
| **Orchestration** | Amazon EKS | 1.28+ | Kubernetes cluster management |
| **Container Runtime** | containerd | Latest | Container execution |
| **Package Manager** | Helm | 3.x | Application deployment |
| **Application** | LiteLLM | 1.80.5-stable | LLM API gateway |
| **Frontend** | OpenWebUI | 0.6.41 | Chat interface |
| **Caching** | Redis | 7.4.1-alpine | Distributed caching |
| **Database** | PostgreSQL | 15+ (RDS) | Relational data storage |
| **Metrics** | Prometheus | 2.x | Time-series metrics |
| **Visualization** | Grafana | 10.x | Dashboards |
| **Tracing** | Jaeger | 1.76.0 | Distributed tracing |
| **Secrets** | External Secrets Operator | 0.12.1 | Secrets management |
| **Storage** | AWS EBS gp3 | - | Persistent volumes |
| **AI Models** | AWS Bedrock | - | Foundation models (Claude, Llama, Mistral) |

### Port Reference

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| OpenWebUI | 80 | HTTP | Web interface |
| LiteLLM | 4000 | HTTP | API endpoint, /metrics |
| Redis | 6379 | TCP | Cache/session storage |
| PostgreSQL | 5432 | TCP | Database (RDS) |
| Prometheus | 9090 | HTTP | Metrics query |
| Grafana | 80 | HTTP | Dashboard UI |
| Alertmanager | 9093 | HTTP | Alert management |
| Jaeger Collector | 4317 | gRPC | OTLP ingestion |
| Jaeger Collector | 4318 | HTTP | OTLP ingestion |
| Jaeger Query | 16686 | HTTP | Trace UI |
| Redis Exporter | 9121 | HTTP | Redis metrics |
| Node Exporter | 9100 | HTTP | Host metrics |

### File Structure Reference

```
eks-deploy/
├── deploy.sh                    # Main deployment automation (699 lines)
├── scripts/
│   └── setup-bastion.sh        # Bastion provisioning (420 lines)
├── helm-values/
│   ├── external-secrets.yaml   # ESO configuration
│   ├── grafana-values.yaml     # Grafana settings
│   ├── jaeger-values.yaml      # Jaeger config
│   ├── litellm-values.yaml     # LiteLLM settings (model configs)
│   ├── openwebui-values.yaml   # OpenWebUI settings
│   ├── prometheus-values.yaml  # Prometheus stack config
│   ├── redis-values.yaml       # Redis HA config
│   └── values.yaml             # (Deprecated/unused)
├── manifests/
│   ├── clustersecretstore.yaml     # ESO secret store
│   ├── externalsecret-litellm.yaml # LiteLLM secrets sync
│   ├── externalsecret-redis.yaml   # Redis secrets sync
│   └── servicemonitor.yaml         # Prometheus scrape configs
├── iam/
│   ├── bedrock-policy.json         # Bedrock permissions
│   ├── external-secrets-policy.json # Secrets Manager permissions
│   └── trust-policy-template.json  # IRSA trust relationship
├── grafana_dashboards/
│   ├── litellm-dashboard.json      # LiteLLM metrics dashboard
│   └── litellm-model-health.json   # Model health dashboard
├── README.md                   # User documentation (470 lines)
└── .github/
    └── dependabot.yml          # Dependency updates config
```

---

## Document Maintenance

- **Review Frequency:** Quarterly or after major architecture changes
- **Owner:** Platform Engineering / DevOps Team
- **Last Updated:** 2025-12-05
- **Next Review:** 2026-03-05
- **Related Documents:** THREAT_MODEL.md, README.md

---

## Glossary

- **IRSA:** IAM Roles for Service Accounts - Pod-level AWS IAM authentication
- **ESO:** External Secrets Operator - Syncs secrets from AWS to Kubernetes
- **PDB:** PodDisruptionBudget - Controls voluntary pod evictions
- **PV/PVC:** PersistentVolume/PersistentVolumeClaim - Kubernetes storage abstraction
- **OTLP:** OpenTelemetry Protocol - Telemetry data transmission standard
- **ServiceMonitor:** Prometheus CRD for auto-discovering scrape targets
- **Sentinel:** Redis HA mechanism for automatic failover
- **ClusterIP:** Internal Kubernetes service (no external exposure)
- **Bedrock:** AWS managed service for foundation models
