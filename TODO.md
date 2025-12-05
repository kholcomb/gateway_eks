# Feature: Administration

## Summary

Enable the LiteLLM Admin UI for centralized management of API keys, models, users, and spend tracking through a web interface.

## Key Features

- **Key Management**: Create and manage API keys through the UI
- **Spend Tracking**: Monitor LLM usage costs per key/user
- **Model Management**: Add new models without restarting the proxy
- **User Management**: Invite users, bulk edit, SCIM integration
- **Logging**: Comprehensive UI logs for monitoring

## Required Actions

- [ ] Configure `LITELLM_MASTER_KEY` environment variable
- [ ] Set up database connection for persistent storage
- [ ] Configure `UI_USERNAME` and `UI_PASSWORD` for admin access
- [ ] Update Kubernetes deployment with Admin UI environment variables
- [ ] Create Kubernetes Secret for admin credentials
- [ ] Configure Ingress/Service to expose UI on port 4000 at `/ui` path
- [ ] Set up RBAC for user management if multi-user access required
- [ ] Enable SSO integration if enterprise authentication needed
- [ ] Configure custom root path if running behind reverse proxy
- [ ] Test UI access and key creation workflow

## Configuration Example

```yaml
env:
  - name: LITELLM_MASTER_KEY
    valueFrom:
      secretKeyRef:
        name: litellm-secrets
        key: master-key
  - name: UI_USERNAME
    valueFrom:
      secretKeyRef:
        name: litellm-secrets
        key: ui-username
  - name: UI_PASSWORD
    valueFrom:
      secretKeyRef:
        name: litellm-secrets
        key: ui-password
```

## Documentation

- https://docs.litellm.ai/docs/proxy/ui
