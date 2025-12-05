# Feature: Prompt Caching

## Summary

Configure LiteLLM caching to reduce latency and costs by caching LLM responses, with support for multiple backend options including Redis, semantic caching, and S3.

## Supported Cache Backends

| Backend | Description |
|---------|-------------|
| In-Memory | Fast local caching (single instance only) |
| Disk | Persistent local caching |
| Redis | Distributed caching with cluster/sentinel support |
| Redis Semantic | Vector embeddings in Redis for similarity matching |
| Qdrant Semantic | Vector-based semantic similarity caching |
| S3 | Cloud storage-based caching |

## Key Features

- **TTL Control**: Set cache expiration per request
- **Namespace Support**: Organize cached responses by groups
- **Cache Controls**: `no-cache`, `no-store`, `s-maxage` per request
- **Opt-In Mode**: Default caching off with explicit enablement
- **Cache Deletion**: Remove specific keys via `/cache/delete` endpoint
- **Health Check**: `/cache/ping` endpoint for monitoring

## Required Actions

- [ ] Choose cache backend based on deployment requirements
- [ ] Deploy Redis if using distributed caching (recommended for multi-replica)
- [ ] Configure cache parameters in config.yaml
- [ ] Set appropriate TTL values for different use cases
- [ ] Create Kubernetes Secret for Redis credentials (if applicable)
- [ ] Configure cache namespaces for multi-tenant isolation
- [ ] Set up opt-in mode if caching should be explicit
- [ ] Define which call types should use caching
- [ ] Test cache hit/miss rates with `/cache/ping`
- [ ] Set up monitoring for cache performance
- [ ] Configure semantic cache if similarity matching needed

## Configuration Example

### Basic Redis Cache

```yaml
litellm_settings:
  cache: true
  cache_params:
    type: redis
    host: redis-master
    port: 6379
    password: os.environ/REDIS_PASSWORD
    ttl: 3600  # 1 hour default
    supported_call_types:
      - acompletion
      - completion
      - embedding
```

### Semantic Cache (Qdrant)

```yaml
litellm_settings:
  cache: true
  cache_params:
    type: qdrant-semantic
    qdrant_host: qdrant-service
    qdrant_port: 6333
    similarity_threshold: 0.8
    embedding_model: text-embedding-3-small
```

### Opt-In Caching

```yaml
litellm_settings:
  cache: true
  cache_params:
    type: redis
    mode: "opt-in"  # Caching disabled by default
```

## Per-Request Cache Control

```python
# Enable caching for specific request
response = client.chat.completions.create(
    model="gpt-4",
    messages=[...],
    extra_body={
        "cache": {
            "ttl": 7200,
            "namespace": "project-a"
        }
    }
)

# Skip cache for fresh response
response = client.chat.completions.create(
    model="gpt-4",
    messages=[...],
    extra_body={"cache": {"no-cache": True}}
)
```

## Kubernetes Redis Deployment

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: redis-secrets
type: Opaque
stringData:
  redis-password: "<strong-password>"
```

## Documentation

- https://docs.litellm.ai/docs/proxy/caching
