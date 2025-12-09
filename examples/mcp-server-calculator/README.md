# MCP Calculator Server

A simple arithmetic calculator implemented as a Model Context Protocol (MCP) server using the [FastMCP](https://github.com/jlowin/fastmcp) framework.

## Features

### Tools

The calculator provides the following tools:

- `add(a, b)` - Add two numbers
- `subtract(a, b)` - Subtract b from a
- `multiply(a, b)` - Multiply two numbers
- `divide(a, b)` - Divide a by b (with zero-division handling)
- `power(base, exponent)` - Raise base to exponent
- `sqrt(n)` - Calculate square root
- `calculate(expression)` - Safely evaluate mathematical expressions

### Resources

- `calculator://constants` - Mathematical constants (π, e, τ, φ, √2)

### Prompts

- `calculate_prompt(operation)` - Generate calculation prompts

## Local Development

### Prerequisites

- Python 3.12+
- Docker (for containerization)

### Run Locally

```bash
# Install dependencies
pip install -r requirements.txt

# Run the server
python server.py
```

The server will start on `http://localhost:8080`

### Test Endpoints

```bash
# Health check
curl http://localhost:8080/health

# Readiness check
curl http://localhost:8080/ready

# Metrics
curl http://localhost:8080/metrics
```

### Test MCP Tools

```bash
# Using MCP client (example)
curl -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "add",
      "arguments": {"a": 5, "b": 3}
    }
  }'
```

## Build and Deploy to EKS

### Step 1: Build Docker Image

```bash
# Set variables
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export IMAGE_TAG=1.0.0

# Build image
docker build -t mcp-calculator:${IMAGE_TAG} .

# Test locally
docker run -p 8080:8080 mcp-calculator:${IMAGE_TAG}
```

### Step 2: Push to ECR

```bash
# Create ECR repository (first time only)
aws ecr create-repository \
  --repository-name mcp-calculator \
  --region ${AWS_REGION}

# Login to ECR
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Tag for ECR
docker tag mcp-calculator:${IMAGE_TAG} \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/mcp-calculator:${IMAGE_TAG}

# Push to ECR
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/mcp-calculator:${IMAGE_TAG}
```

### Step 3: Update OPA Allowed Repos

```bash
# Update the allowed-repos constraint to include your ECR
kubectl get constraint allowed-image-repos -o yaml > /tmp/allowed-repos.yaml

# Edit /tmp/allowed-repos.yaml to add:
# - ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/mcp-calculator

# Apply updated constraint
kubectl apply -f /tmp/allowed-repos.yaml
```

### Step 4: Deploy MCPServer Resource

```bash
# Update the image repository in calculator.yaml
export MCPServer_YAML=../../examples/mcpservers/calculator.yaml
sed -i "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" ${MCPServer_YAML}

# Deploy to Kubernetes
kubectl apply -f ${MCPServer_YAML}
```

### Step 5: Verify Deployment

```bash
# Check MCPServer status
kubectl get mcpserver calculator -n litellm
kubectl describe mcpserver calculator -n litellm

# Check generated resources
kubectl get deployment,service,pdb,servicemonitor -n litellm -l app.kubernetes.io/name=mcp-calculator

# Check pods
kubectl get pods -n litellm -l app.kubernetes.io/name=mcp-calculator

# View logs
kubectl logs -n litellm -l app.kubernetes.io/name=mcp-calculator --tail=50
```

### Step 6: Test from Inside Cluster

```bash
# Port-forward to test locally
kubectl port-forward -n litellm svc/mcp-calculator 8080:8080

# Test health
curl http://localhost:8080/health

# Test MCP endpoint
curl http://localhost:8080/mcp
```

## Integration with LiteLLM

Once deployed, the calculator will automatically register with LiteLLM proxy (if `litellm.autoRegister: true`).

### Using from Claude via LiteLLM

```python
# Example: Using calculator tools via LiteLLM
from anthropic import Anthropic

client = Anthropic(
    base_url="http://litellm-proxy.litellm.svc:4000",
    api_key="your-litellm-key"
)

response = client.messages.create(
    model="claude-3-5-sonnet-20241022",
    max_tokens=1024,
    tools=[
        {
            "name": "add",
            "description": "Add two numbers together",
            "input_schema": {
                "type": "object",
                "properties": {
                    "a": {"type": "number"},
                    "b": {"type": "number"}
                },
                "required": ["a", "b"]
            }
        }
    ],
    messages=[
        {"role": "user", "content": "What is 123 + 456?"}
    ]
)
```

## Monitoring

### Prometheus Metrics

Metrics are automatically exposed at `/metrics`:

- `mcp_requests_total{tool="add",status="success"}` - Total requests per tool
- `mcp_request_duration_seconds{tool="add"}` - Request duration histogram
- `mcp_errors_total{tool="add",error_type="..."}` - Error counts

### View in Grafana

```bash
# Port-forward to Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-grafana 3000:80

# Open http://localhost:3000
# Search for "mcp_requests_total"
```

### Distributed Tracing

Traces are automatically sent to Jaeger:

```bash
# Port-forward to Jaeger UI
kubectl port-forward -n monitoring svc/jaeger-query 16686:16686

# Open http://localhost:16686
# Select service: "mcp-calculator"
```

## Troubleshooting

### Pod Not Starting

```bash
# Check events
kubectl describe pod -n litellm -l app.kubernetes.io/name=mcp-calculator

# Check logs
kubectl logs -n litellm -l app.kubernetes.io/name=mcp-calculator --previous
```

### Image Pull Errors

```bash
# Verify ECR repository
aws ecr describe-repositories --repository-names mcp-calculator

# Verify image exists
aws ecr list-images --repository-name mcp-calculator

# Check node IAM role has ECR pull permissions
```

### Health Check Failing

```bash
# Exec into pod
kubectl exec -it -n litellm deployment/mcp-calculator -- /bin/bash

# Test health endpoint
curl http://localhost:8080/health
curl http://localhost:8080/ready
```

## Development Workflow

### Making Changes

1. Update `server.py`
2. Test locally: `python server.py`
3. Build new image: `docker build -t mcp-calculator:${NEW_TAG} .`
4. Push to ECR
5. Update MCPServer resource: `kubectl edit mcpserver calculator -n litellm`
6. Update image tag in spec

### Adding New Tools

```python
@mcp.tool
async def your_new_tool(param: type) -> return_type:
    """Tool description.

    Args:
        param: Parameter description

    Returns:
        Return value description
    """
    # Implementation
    return result
```

FastMCP automatically generates JSON schemas from your function signatures and docstrings.

## Security Considerations

- Container runs as non-root user (UID 1000)
- Read-only root filesystem (writable /tmp via emptyDir)
- All Linux capabilities dropped
- Resource limits enforced
- Expression evaluation uses AST (no `eval()` - prevents code injection)

## References

- FastMCP Framework: <https://github.com/jlowin/fastmcp>
- MCP Specification: <https://modelcontextprotocol.io>
- Operator Architecture: [../../docs/MCP_OPERATOR_ARCHITECTURE.md](../../docs/MCP_OPERATOR_ARCHITECTURE.md)
