# Feature: Vector Storage

## Summary

Configure LiteLLM with vector storage backends for semantic caching and embedding operations, enabling similarity-based response retrieval and RAG workflows.

## Supported Embedding Providers

### Cloud AI Services
- OpenAI (text-embedding-3-small, text-embedding-3-large)
- Google Gemini
- Vertex AI
- Cohere
- Mistral AI
- Voyage AI

### Infrastructure Providers
- AWS Bedrock (Amazon Nova, Titan, TwelveLabs)
- NVIDIA NIM

### Open Source
- HuggingFace
- Nebius AI Studio

## Vector Storage Options

| Backend | Use Case |
|---------|----------|
| Qdrant | Dedicated vector database with semantic cache |
| Redis Semantic | Vector embeddings in Redis |
| Chroma | Local/embedded vector storage |
| Pinecone | Managed vector database |

## Key Features

- **Semantic Caching**: Cache responses by meaning, not exact match
- **Unified Embeddings API**: OpenAI-compatible `/embeddings` endpoint
- **Multi-Provider Support**: Route embeddings across providers
- **Image Embeddings**: Support for multimodal embedding models

## Required Actions

- [ ] Choose embedding provider(s) based on requirements
- [ ] Deploy vector database (Qdrant, Redis, etc.)
- [ ] Configure embedding model credentials
- [ ] Create Kubernetes Secrets for API keys
- [ ] Set up LiteLLM embedding model configuration
- [ ] Configure semantic cache with similarity threshold
- [ ] Set up vector database connection parameters
- [ ] Test embeddings endpoint with sample inputs
- [ ] Configure `input_type` for models that require it (Cohere, NVIDIA)
- [ ] Set up monitoring for embedding latency and costs

## Configuration Example

### Embedding Models

```yaml
model_list:
  - model_name: text-embedding-3-small
    litellm_params:
      model: openai/text-embedding-3-small
      api_key: os.environ/OPENAI_API_KEY

  - model_name: embed-english-v3.0
    litellm_params:
      model: cohere/embed-english-v3.0
      api_key: os.environ/COHERE_API_KEY

  - model_name: voyage-large-2
    litellm_params:
      model: voyage/voyage-large-2
      api_key: os.environ/VOYAGE_API_KEY
```

### Qdrant Semantic Cache

```yaml
litellm_settings:
  cache: true
  cache_params:
    type: qdrant-semantic
    qdrant_host: qdrant.vector.svc.cluster.local
    qdrant_port: 6333
    qdrant_api_key: os.environ/QDRANT_API_KEY
    similarity_threshold: 0.85
    embedding_model: text-embedding-3-small
    collection_name: litellm_cache
```

### Redis Semantic Cache

```yaml
litellm_settings:
  cache: true
  cache_params:
    type: redis-semantic
    host: redis-master.redis.svc.cluster.local
    port: 6379
    password: os.environ/REDIS_PASSWORD
    similarity_threshold: 0.8
    embedding_model: text-embedding-3-small
```

## Qdrant Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qdrant
spec:
  replicas: 1
  selector:
    matchLabels:
      app: qdrant
  template:
    metadata:
      labels:
        app: qdrant
    spec:
      containers:
        - name: qdrant
          image: qdrant/qdrant:latest
          ports:
            - containerPort: 6333
            - containerPort: 6334
          volumeMounts:
            - name: qdrant-storage
              mountPath: /qdrant/storage
      volumes:
        - name: qdrant-storage
          persistentVolumeClaim:
            claimName: qdrant-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: qdrant
spec:
  selector:
    app: qdrant
  ports:
    - name: http
      port: 6333
    - name: grpc
      port: 6334
```

## Kubernetes Secrets

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: embedding-secrets
type: Opaque
stringData:
  openai-api-key: "<openai-key>"
  cohere-api-key: "<cohere-key>"
  voyage-api-key: "<voyage-key>"
  qdrant-api-key: "<qdrant-key>"
```

## Usage Examples

### Generate Embeddings

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://litellm-proxy:4000",
    api_key="sk-your-key"
)

# Text embedding
response = client.embeddings.create(
    model="text-embedding-3-small",
    input="Hello, world!"
)

# With input_type (required for some models)
response = client.embeddings.create(
    model="embed-english-v3.0",
    input="Hello, world!",
    extra_body={"input_type": "search_document"}
)
```

## Documentation

- https://docs.litellm.ai/docs/embedding/supported_embedding
- https://docs.litellm.ai/docs/proxy/caching
