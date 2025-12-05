# Feature: Guardrails

## Summary

Integrate LiteLLM guardrails for content filtering, PII protection, prompt injection detection, and security controls across LLM requests.

## Supported Providers

### Security/Content Filtering
- Aim Security
- Azure Content Safety
- AWS Bedrock Guardrails
- OpenAI Moderation
- Google Cloud Model Armor
- PANW Prisma AIRS
- Zscaler AI Guard

### PII Protection
- Presidio (PII/PHI masking)
- Lasso Security
- Noma Security

### Specialized Detection
- Prompt injection detection
- Secret detection (enterprise)
- Tool permissions

### Third-Party Services
- Aporia
- Guardrails AI
- Javelin
- Lakera AI
- Pangea

## Required Actions

- [ ] Choose guardrail provider(s) based on security requirements
- [ ] Obtain API keys/credentials for selected providers
- [ ] Create Kubernetes Secret for guardrail API credentials
- [ ] Add guardrails configuration to LiteLLM config.yaml
- [ ] Configure guardrail execution mode (`pre_call`, `post_call`, `during_call`, `logging_only`)
- [ ] Set up `default_on: true` for guardrails that should run on all requests
- [ ] Configure per-API-key guardrail enforcement if needed (enterprise)
- [ ] Test guardrails with `/guardrails/list` endpoint
- [ ] Set up monitoring/alerting for guardrail violations
- [ ] Document guardrail bypass procedures for authorized use cases

## Configuration Example

```yaml
litellm_settings:
  guardrails:
    - guardrail_name: "content-filter"
      guardrail: "azure_content_safety"
      mode: "pre_call"
      api_key: "os.environ/AZURE_CONTENT_SAFETY_KEY"
      api_base: "https://<resource>.cognitiveservices.azure.com"
      default_on: true

    - guardrail_name: "pii-masking"
      guardrail: "presidio"
      mode: "pre_call"
      default_on: true

    - guardrail_name: "prompt-injection"
      guardrail: "lakera"
      mode: "pre_call"
      api_key: "os.environ/LAKERA_API_KEY"
```

## Kubernetes Secret Example

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: guardrail-secrets
type: Opaque
stringData:
  azure-content-safety-key: "<your-key>"
  lakera-api-key: "<your-key>"
```

## Documentation

- https://docs.litellm.ai/docs/proxy/guardrails/quick_start
