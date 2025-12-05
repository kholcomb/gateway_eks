# Feature: Spend Tracking

## Summary

Configure LiteLLM spend tracking to monitor LLM usage costs across projects, teams, and API keys with automatic cost calculation and reporting.

## Key Features

- **Automatic Cost Tracking**: `response_cost` returned in all API responses
- **Per-Key Budgets**: Set spending limits per virtual key
- **Team/Org Budgets**: Hierarchical budget management
- **Usage Dashboard**: Visual spend monitoring via Admin UI
- **Custom Pricing**: Register custom model pricing
- **Token Counting**: Accurate token usage tracking

## Cost Tracking Capabilities

| Feature | Description |
|---------|-------------|
| `response_cost` | Automatic cost in API responses |
| `completion_cost()` | Calculate cost from responses |
| `cost_per_token()` | Get per-token pricing |
| `token_counter()` | Count tokens for inputs |
| Custom pricing | Register non-standard model costs |

## Required Actions

- [ ] Enable database connection for persistent spend data
- [ ] Configure `LITELLM_MASTER_KEY` for admin access
- [ ] Set up virtual keys with budget limits
- [ ] Configure team/organization hierarchies
- [ ] Enable Admin UI for spend dashboard access
- [ ] Set up spend alerts/notifications
- [ ] Configure custom pricing for proprietary models if needed
- [ ] Set up spend reports export (if required)
- [ ] Configure budget reset periods (daily/weekly/monthly)
- [ ] Test budget enforcement and alerting

## Configuration Example

### Basic Spend Tracking

```yaml
general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL

litellm_settings:
  success_callback: ["langfuse"]  # Optional: external tracking
```

### Virtual Key with Budget

```bash
# Create key with budget via API
curl -X POST "http://localhost:4000/key/generate" \
  -H "Authorization: Bearer sk-master-key" \
  -H "Content-Type: application/json" \
  -d '{
    "models": ["gpt-4", "gpt-3.5-turbo"],
    "max_budget": 100.00,
    "budget_duration": "monthly",
    "metadata": {
      "team": "engineering",
      "project": "chatbot"
    }
  }'
```

### Team Budget Configuration

```bash
# Create team with budget
curl -X POST "http://localhost:4000/team/new" \
  -H "Authorization: Bearer sk-master-key" \
  -H "Content-Type: application/json" \
  -d '{
    "team_alias": "engineering",
    "max_budget": 1000.00,
    "budget_duration": "monthly"
  }'
```

### Custom Model Pricing

```python
import litellm

# Register custom pricing for proprietary model
litellm.register_model({
    "custom-model": {
        "max_tokens": 8192,
        "input_cost_per_token": 0.00001,
        "output_cost_per_token": 0.00002
    }
})
```

## Environment Variables

```yaml
env:
  - name: LITELLM_MASTER_KEY
    valueFrom:
      secretKeyRef:
        name: litellm-secrets
        key: master-key
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: litellm-secrets
        key: database-url
  # Optional: Use local pricing map (for air-gapped environments)
  - name: LITELLM_LOCAL_MODEL_COST_MAP
    value: "true"
```

## Kubernetes Database Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: litellm-secrets
type: Opaque
stringData:
  master-key: "sk-your-master-key"
  database-url: "postgresql://user:password@postgres:5432/litellm"
```

## Spend Monitoring Queries

```bash
# Get spend by key
curl "http://localhost:4000/spend/logs?api_key=sk-..." \
  -H "Authorization: Bearer sk-master-key"

# Get spend by team
curl "http://localhost:4000/spend/logs?team_id=..." \
  -H "Authorization: Bearer sk-master-key"

# Get total spend
curl "http://localhost:4000/spend/calculate" \
  -H "Authorization: Bearer sk-master-key"
```

## Admin UI Access

Access spend dashboard at `http://<litellm-host>:4000/ui` with configured credentials.

## Documentation

- https://docs.litellm.ai/docs/completion/token_usage
- https://docs.litellm.ai/docs/proxy/virtual_keys
