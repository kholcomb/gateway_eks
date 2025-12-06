# Feature: Redis TLS

## Summary

Configure secure TLS connections to Redis for LiteLLM caching and distributed state management, ensuring encrypted communication in production environments.

## Key Features

- **TLS/SSL Encryption**: Secure Redis connections for in-cluster deployments
- **Redis Cluster Support**: TLS with Redis Cluster deployments
- **Redis Sentinel Support**: TLS with high-availability Sentinel setups
- **Service Mesh Ready**: Compatible with future Istio/Linkerd integration
- **Advanced mTLS**: Client certificate authentication for external Redis (optional)

## Required Actions (In-Cluster Basic TLS)

- [ ] Configure Redis server with TLS enabled
- [ ] Update LiteLLM config with `ssl: true` in Redis connection settings
- [ ] Test TLS connection with `/cache/ping` endpoint
- [ ] Verify Redis server certificate validity
- [ ] Configure Redis Sentinel/Cluster TLS if applicable

## Optional Actions (External Redis with mTLS)

- [ ] Obtain or generate TLS certificates for Redis client authentication
- [ ] Create Kubernetes Secret for Redis TLS certificates
- [ ] Configure certificate paths (ssl_certfile, ssl_keyfile, ssl_ca_certs)
- [ ] Set up certificate rotation procedures
- [ ] Verify certificate chain and expiration monitoring

## Configuration Examples

### Basic Redis TLS (Recommended for In-Cluster EKS)

For Redis pods in the same namespace/cluster, basic TLS provides encryption in transit. When you add a service mesh (Istio/Linkerd), it will handle mutual authentication between pods automatically.

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

### Advanced: Redis TLS with Certificates (mTLS)

For external/managed Redis services requiring client certificate authentication:

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

## Service Mesh Integration (Future)

When implementing a service mesh (Istio/Linkerd/Consul), you'll get:
- **Automatic mTLS** between LiteLLM and Redis pods
- **Zero configuration** for mutual authentication within the mesh
- **Centralized certificate management** via mesh control plane
- **Observability** with encrypted traffic metrics

The basic TLS configuration above remains compatible - the mesh will add an additional mTLS layer at the sidecar level.

## Advanced: Kubernetes Secret for mTLS Certificates

Only needed for external Redis requiring client certificates:

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

## Advanced: Volume Mount Configuration

Only needed for external Redis requiring client certificates:

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
