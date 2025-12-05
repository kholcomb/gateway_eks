# Feature: LiteLLM Reliability

## Summary

Configure LiteLLM reliability features including load balancing, fallbacks, retries, timeouts, and cooldowns for high-availability LLM deployments.

## Key Features

- **Fallbacks**: Route to alternative models when primary fails
- **Load Balancing**: Distribute requests across model instances
- **Retries**: Automatic retry on transient failures
- **Timeouts**: Request duration limits
- **Cooldowns**: Temporarily disable failing models
- **Pre-call Checks**: Validate requests before sending

## Routing Strategies

- `simple-shuffle`: Random distribution
- `least-busy`: Route to least loaded instance
- `usage-based-routing`: Based on usage metrics
- `latency-based-routing`: Route to fastest responding model

## Required Actions

- [ ] Define model groups for load balancing in config.yaml
- [ ] Configure fallback model chains for each primary model
- [ ] Set `num_retries` for automatic retry attempts
- [ ] Configure `request_timeout` for request duration limits
- [ ] Set up cooldown parameters (`allowed_fails`, `cooldown_time`)
- [ ] Choose routing strategy based on requirements
- [ ] Deploy Redis for distributed state if running multiple proxy instances
- [ ] Configure health check endpoints for Kubernetes probes
- [ ] Set up monitoring for model failure rates and latency
- [ ] Test fallback chains with simulated failures
- [ ] Configure content policy violation fallbacks if needed
- [ ] Set up context window fallbacks for capacity issues

## Configuration Example

```yaml
model_list:
  - model_name: gpt-4
    litellm_params:
      model: azure/gpt-4-deployment-1
      api_base: https://region1.openai.azure.com
      api_key: os.environ/AZURE_API_KEY_1
  - model_name: gpt-4
    litellm_params:
      model: azure/gpt-4-deployment-2
      api_base: https://region2.openai.azure.com
      api_key: os.environ/AZURE_API_KEY_2

router_settings:
  routing_strategy: "latency-based-routing"
  num_retries: 3
  request_timeout: 30
  allowed_fails: 3
  cooldown_time: 60
  redis_host: redis-master
  redis_port: 6379
  redis_password: os.environ/REDIS_PASSWORD

litellm_settings:
  fallbacks:
    - gpt-4: [gpt-4-turbo, gpt-3.5-turbo]
  context_window_fallbacks:
    - gpt-4: [gpt-4-32k]
```

## Kubernetes Considerations

```yaml
# Liveness/Readiness probes
livenessProbe:
  httpGet:
    path: /health
    port: 4000
  initialDelaySeconds: 10
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /health/readiness
    port: 4000
  initialDelaySeconds: 5
  periodSeconds: 5
```

## Documentation

- https://docs.litellm.ai/docs/proxy/reliability
