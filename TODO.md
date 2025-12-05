# Feature: MCP Management

## Summary

Configure LiteLLM as an MCP (Model Context Protocol) Gateway to provide centralized tool management with access control by API key, team, or organization.

## Key Features

- **MCP Gateway**: Centralized endpoint for all MCP tools
- **Transport Support**: HTTP Streamable, SSE, STDIO
- **Access Control**: Per API key, team, or organization permissions
- **OpenAPI Conversion**: Auto-convert OpenAPI specs to MCP tools
- **Multiple Auth Methods**: API Key, Bearer Token, Basic Auth, OAuth 2.0

## Supported Transports

| Transport | Description |
|-----------|-------------|
| HTTP Streamable | Direct HTTP endpoint connection |
| SSE | Server-Sent Events for real-time updates |
| STDIO | Standard input/output for local processes |

## Required Actions

- [ ] Enable database storage for MCP servers (`STORE_MODEL_IN_DB=True`)
- [ ] Configure MCP server definitions in config.yaml or via API
- [ ] Set up authentication credentials for backend MCP servers
- [ ] Create Kubernetes Secrets for MCP server credentials
- [ ] Configure access control policies per team/key
- [ ] Set up MCP aliases for user-friendly server names
- [ ] Define allowed/disallowed tools per server
- [ ] Configure custom headers for backend server communication
- [ ] Test MCP tool listing and execution
- [ ] Set up monitoring for MCP tool usage

## Configuration Example

```yaml
general_settings:
  store_model_in_db: true

mcp_servers:
  - server_name: "github-tools"
    transport: "sse"
    url: "https://mcp-server.example.com/sse"
    auth_type: "bearer"
    api_key: "os.environ/MCP_GITHUB_TOKEN"
    allowed_tools:
      - "search_repos"
      - "create_issue"

  - server_name: "internal-tools"
    transport: "http"
    url: "https://internal-mcp.example.com"
    auth_type: "api_key"
    api_key: "os.environ/MCP_INTERNAL_KEY"
    extra_headers:
      X-Custom-Header: "value"
```

## Kubernetes Secret Example

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mcp-secrets
type: Opaque
stringData:
  mcp-github-token: "<github-token>"
  mcp-internal-key: "<internal-key>"
```

## Access Control Example

```yaml
# Per-key MCP access
key_settings:
  - key_name: "dev-team-key"
    allowed_mcp_servers:
      - "github-tools"

  - key_name: "admin-key"
    allowed_mcp_servers:
      - "github-tools"
      - "internal-tools"
```

## Documentation

- https://docs.litellm.ai/docs/mcp
