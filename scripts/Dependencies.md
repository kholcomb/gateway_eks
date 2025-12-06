# LiteLLM Deployment Dependency Diagram

## Overview

This document visualizes the deployment dependencies for the LiteLLM EKS infrastructure, showing the relationships between components and the correct deployment order.

## Prerequisites

```mermaid
graph TD
    PREREQ[Prerequisites]
    PREREQ --> AWS[AWS CLI]
    PREREQ --> KUBECTL[kubectl]
    PREREQ --> HELM[helm]

    KUBECTL --> EKS[EKS Cluster]
    EKS --> VPC[VPC & Subnets]
    EKS --> OIDC[OIDC Provider]
    EKS --> SEC[Security]
    EKS --> K8S[K8s API]

    style PREREQ fill:#ff9999
    style EKS fill:#99ccff
```

## Phase 1: Foundation Resources

```mermaid
graph LR
    YAML[YAML Validation]
    REPOS[Helm Repos]
    SECRETS[AWS Secrets Manager]

    SECRETS --> MK[litellm/master-key]
    SECRETS --> SK[litellm/salt-key]
    SECRETS --> RP[litellm/redis-password]
    SECRETS --> DB[litellm/database-url]

    style YAML fill:#ffffcc
    style REPOS fill:#ffffcc
    style SECRETS fill:#ffcc99
```

## Phase 2: IAM & Namespaces

```mermaid
graph TD
    OIDC[OIDC Provider]
    EKS[EKS Cluster]

    OIDC --> BR[litellm-bedrock-role]
    OIDC --> ESR[external-secrets-role]

    EKS --> NS1[litellm namespace]
    EKS --> NS2[open-webui namespace]
    EKS --> NS3[monitoring namespace]
    EKS --> NS4[external-secrets namespace]

    style OIDC fill:#99ccff
    style EKS fill:#99ccff
    style BR fill:#ccffcc
    style ESR fill:#ccffcc
```

## Phase 3: External Secrets Operator

```mermaid
graph TD
    NS[external-secrets namespace]
    ROLE[external-secrets-role]
    REPO[Helm repo: external-secrets]

    NS --> ESO[External Secrets Operator]
    ROLE --> ESO
    REPO --> ESO

    ESO --> DEP[external-secrets deployment]
    ESO --> WH[external-secrets-webhook]
    ESO --> CERT[external-secrets-cert-controller]

    style ESO fill:#ff99ff
    style DEP fill:#ffccff
    style WH fill:#ffccff
    style CERT fill:#ffccff
```

## Phase 4: Secret Stores & Secret Sync

```mermaid
graph TD
    ESO[External Secrets Operator]
    AWS[AWS Secrets exist]

    ESO --> CSS[ClusterSecretStore: aws-secrets-manager]
    AWS --> CSS

    CSS --> ES1[ExternalSecret<br/>litellm-secrets]
    CSS --> ES2[ExternalSecret<br/>openwebui-secrets]

    ES1 --> K8S1[K8s Secret<br/>litellm-secrets]
    ES2 --> K8S2[K8s Secret<br/>openwebui-secrets]

    style CSS fill:#ff99ff
    style ES1 fill:#ffccff
    style ES2 fill:#ffccff
    style K8S1 fill:#99ff99
    style K8S2 fill:#99ff99
```

## Phase 5: Observability Stack

```mermaid
graph TD
    NS[monitoring namespace]
    REPOS[Helm repos]

    NS --> PROM[kube-prometheus-stack]
    REPOS --> PROM

    PROM --> P[Prometheus deployment]
    PROM --> G[Grafana deployment]
    PROM --> AM[AlertManager deployment]
    PROM --> GD[Grafana Dashboards]

    NS --> JAEGER[Jaeger Helm]
    REPOS --> JAEGER
    JAEGER --> JD[Jaeger deployment]

    style PROM fill:#9999ff
    style JAEGER fill:#9999ff
```

## Phase 6: Redis (Data Layer)

```mermaid
graph TD
    NS[litellm namespace]
    SEC[litellm-secrets synced]
    REPO[Helm repo: dandydev]

    NS --> REDIS[Redis HA Helm]
    SEC --> REDIS
    REPO --> REDIS

    REDIS --> SS[Redis StatefulSet<br/>3 replicas]
    REDIS --> SENT[Redis Sentinel]

    style REDIS fill:#ff6666
    style SS fill:#ff9999
    style SENT fill:#ff9999
```

## Phase 7: LiteLLM (Application Layer)

```mermaid
graph TD
    NS[litellm namespace]
    ROLE[litellm-bedrock-role]
    SEC[litellm-secrets]
    REDIS[Redis healthy]
    DB[Database]

    NS --> LITE[LiteLLM Helm]
    ROLE --> LITE
    SEC --> LITE
    REDIS --> LITE
    DB --> LITE

    LITE --> DEP[LiteLLM deployment]
    LITE --> SVC[LiteLLM service]

    style LITE fill:#66cc66
    style DEP fill:#99ff99
    style SVC fill:#99ff99
```

## Phase 8: OpenWebUI (Frontend Layer)

```mermaid
graph TD
    NS[open-webui namespace]
    SEC[openwebui-secrets synced]
    LITE[LiteLLM healthy]

    NS --> OW[OpenWebUI Helm]
    SEC --> OW
    LITE --> OW

    OW --> DEP[OpenWebUI deployment]
    OW --> SVC[OpenWebUI service]

    style OW fill:#6666ff
    style DEP fill:#9999ff
    style SVC fill:#9999ff
```

## Critical Dependency Paths

### Path 1: Secrets Flow

```mermaid
graph TD
    ASM[AWS Secrets Manager]
    ASM --> ESO[External Secrets Operator]
    ESO --> CSS[ClusterSecretStore]
    CSS --> ES[ExternalSecret litellm-secrets]
    ES --> K8S[K8s Secret litellm-secrets]
    K8S --> REDIS[Redis needs redis-password]
    K8S --> LITE[LiteLLM needs all secrets]

    style ASM fill:#ffcc99
    style K8S fill:#99ff99
```

### Path 2: LiteLLM Deployment Flow

```mermaid
graph TD
    PREREQ[Prerequisites]
    PREREQ --> IRSA[IRSA Roles<br/>litellm-bedrock-role]
    IRSA --> NS[Namespaces litellm]
    NS --> ESO[External Secrets Operator]
    ESO --> CSS[ClusterSecretStore]
    CSS --> SYNC[litellm-secrets synced]
    SYNC --> REDIS[Redis HA deployed & healthy]
    REDIS --> DB[Database external RDS]
    DB --> LITE[LiteLLM deployed]

    style PREREQ fill:#ff9999
    style LITE fill:#66cc66
```

### Path 3: OpenWebUI Full Stack

```mermaid
graph TD
    PREREQ[Prerequisites]
    PREREQ --> PATH2[All of Path 2: LiteLLM]
    PATH2 --> OWSEC[openwebui-secrets synced]
    OWSEC --> OW[OpenWebUI deployed]

    style PREREQ fill:#ff9999
    style PATH2 fill:#66cc66
    style OW fill:#6666ff
```

## Complete Deployment Flow

```mermaid
graph TD
    START[Start Deployment]

    START --> P1[Prerequisites Check]
    P1 --> P2[YAML Validation]
    P2 --> P3[IRSA Roles]
    P3 --> P4[AWS Secrets]
    P4 --> P5[Helm Repos]
    P5 --> P6[Namespaces]
    P6 --> P7[External Secrets Operator]
    P7 --> P8[ClusterSecretStore & ExternalSecrets]
    P8 --> P9[kube-prometheus-stack]
    P8 --> P10[Grafana Dashboards]
    P8 --> P11[Jaeger]
    P8 --> P12[Redis HA]
    P9 --> P10
    P12 --> P13[LiteLLM]
    P13 --> P14[OpenWebUI]
    P14 --> P15[Verification]
    P15 --> END[Deployment Complete]

    style START fill:#99ff99
    style END fill:#99ff99
    style P1 fill:#ff9999
    style P7 fill:#ff99ff
    style P12 fill:#ff6666
    style P13 fill:#66cc66
    style P14 fill:#6666ff
```

## Bastion Host Architecture

```mermaid
graph TD
    EKS[EKS Cluster]

    EKS --> VPC[Extract VPC ID]
    EKS --> SG[Security Group]

    VPC --> SUBNET[Subnet ID from VPC]

    SG --> ROLE[bastion-ssm-role]
    SUBNET --> ROLE

    ROLE --> TP[Trust Policy: EC2]
    ROLE --> MP[Managed: AmazonSSMManagedInstanceCore]
    ROLE --> IP[Inline: EKS describe permissions]

    ROLE --> PROFILE[bastion-profile]
    PROFILE --> EC2[EC2 Instance: bastion]

    EC2 --> UD[User Data:<br/>- Install kubectl<br/>- Install helm<br/>- Install aws-cli<br/>- Configure kubeconfig]

    style EKS fill:#99ccff
    style EC2 fill:#ffcc99
```

## Skip Validation Rules

### ✓ CAN SKIP if:
- Resource exists AND is healthy
- No dependent resources being deployed
- User explicitly chooses to skip

### ✗ CANNOT SKIP if:
- Resource doesn't exist
- Resource exists but is unhealthy (status != "deployed" for Helm)
- Dependent resource is being deployed in this session
- Resource is marked as critical dependency

### ⚠️ WARN BEFORE SKIP if:
- Resource is critical (external-secrets, redis)
- Resource has dependents deployed

### 🛑 BLOCK PROCEED if:
- Regenerating `litellm/salt-key` (data corruption risk)

### ⚠️ DOUBLE CONFIRM before:
- Regenerating `litellm/master-key` (breaks all API keys)
- Terminating existing bastion instance
- Changing `litellm/database-url` (different database)

## Deployment Order Summary

| Phase | Component | Can Skip? | Notes |
|-------|-----------|-----------|-------|
| 1 | Prerequisites Check | ❌ Never | Always first, never skip |
| 2 | YAML Validation | ⚠️ Not recommended | Fast failure, recommend always run |
| 3 | IRSA Roles | ✅ If exists & healthy | Can skip if exist & healthy |
| 4 | AWS Secrets | ⚠️ With warning | Can skip if exist, WARN on regenerate |
| 5 | Helm Repos | ✅ Yes | Can skip, idempotent |
| 6 | Namespaces | ✅ If exists | Can skip if exist |
| 7 | External Secrets Operator | ⚠️ Critical | Can skip if healthy, CRITICAL dependency |
| 8 | ClusterSecretStore & ExternalSecrets | ✅ If synced | Can skip if secrets synced |
| 9 | kube-prometheus-stack | ✅ If healthy | Can skip if healthy, independent |
| 10 | Grafana Dashboards | ✅ Yes | Can skip, requires prometheus |
| 11 | Jaeger | ✅ If healthy | Can skip if healthy, independent |
| 12 | Redis HA | ⚠️ Critical | Can skip if healthy, CRITICAL for LiteLLM |
| 13 | LiteLLM | ⚠️ Critical | Can skip if healthy, CRITICAL for OpenWebUI |
| 14 | OpenWebUI | ✅ If healthy | Can skip if healthy, depends on LiteLLM |
| 15 | Verification | ⚠️ Recommended | Always last, recommended |
