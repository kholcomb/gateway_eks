# Feature: Redis TLS

## Summary

Configure secure TLS connections to Redis for LiteLLM caching and distributed state management, ensuring encrypted communication in production environments.

## Key Features

- **TLS/SSL Encryption**: Secure Redis connections
- **Certificate Authentication**: mTLS support for client certificates
- **Redis Cluster Support**: TLS with Redis Cluster deployments
- **Redis Sentinel Support**: TLS with high-availability Sentinel setups
- **GCP IAM Authentication**: Managed Redis with IAM

## Required Actions

- [ ] Obtain or generate TLS certificates for Redis
- [ ] Create Kubernetes Secret for Redis TLS certificates
- [ ] Configure Redis server with TLS enabled
- [ ] Update LiteLLM config with Redis TLS parameters
- [ ] Set `ssl: true` in Redis connection settings
- [ ] Configure certificate paths if using mTLS
- [ ] Test TLS connection with `/cache/ping` endpoint
- [ ] Verify certificate chain and expiration monitoring
- [ ] Set up certificate rotation procedures
- [ ] Configure Redis Sentinel/Cluster TLS if applicable

## Configuration Example

### Basic Redis TLS

```yaml
router_settings:
  redis_host: redis-master.redis.svc.cluster.local
  redis_port: 6379
  redis_password: os.environ/REDIS_PASSWORD
  redis_ssl: true

litellm_settings:
  cache: true
  cache_params:
    type: redis
    host: redis-master.redis.svc.cluster.local
    port: 6379
    password: os.environ/REDIS_PASSWORD
    ssl: true
```

### Redis TLS with Certificates (mTLS)

```yaml
litellm_settings:
  cache: true
  cache_params:
    type: redis
    host: redis-master.redis.svc.cluster.local
    port: 6379
    password: os.environ/REDIS_PASSWORD
    ssl: true
    ssl_certfile: /etc/redis-certs/client.crt
    ssl_keyfile: /etc/redis-certs/client.key
    ssl_ca_certs: /etc/redis-certs/ca.crt
```

### Redis Cluster with TLS

```yaml
litellm_settings:
  cache: true
  cache_params:
    type: redis
    startup_nodes:
      - host: redis-node-1
        port: 6379
      - host: redis-node-2
        port: 6379
      - host: redis-node-3
        port: 6379
    ssl: true
    cluster_mode: true
```

### Redis Sentinel with TLS

```yaml
litellm_settings:
  cache: true
  cache_params:
    type: redis
    sentinel_hosts:
      - host: sentinel-1
        port: 26379
      - host: sentinel-2
        port: 26379
    sentinel_master: mymaster
    ssl: true
```

## Kubernetes Secret for TLS Certificates

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: redis-tls-certs
type: Opaque
data:
  ca.crt: <base64-encoded-ca-cert>
  client.crt: <base64-encoded-client-cert>
  client.key: <base64-encoded-client-key>
```

## Volume Mount Configuration

```yaml
spec:
  containers:
    - name: litellm
      volumeMounts:
        - name: redis-certs
          mountPath: /etc/redis-certs
          readOnly: true
  volumes:
    - name: redis-certs
      secret:
        secretName: redis-tls-certs
```

## Environment Variables Alternative

```yaml
env:
  - name: REDIS_HOST
    value: "redis-master.redis.svc.cluster.local"
  - name: REDIS_PORT
    value: "6379"
  - name: REDIS_PASSWORD
    valueFrom:
      secretKeyRef:
        name: redis-secrets
        key: password
  - name: REDIS_SSL
    value: "true"
```

## Documentation

- https://docs.litellm.ai/docs/proxy/caching
- https://docs.litellm.ai/docs/proxy/configs
