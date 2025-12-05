# Feature: OpenWebUI Okta SSO

## Summary

Configure Okta SSO authentication for OpenWebUI integrated with LiteLLM proxy, enabling enterprise single sign-on for the chat interface.

## Key Features

- **Okta OIDC Integration**: Enterprise SSO via OpenID Connect
- **JWT Validation**: Secure token verification against Okta
- **User Provisioning**: Automatic user creation on first login
- **Role Mapping**: Map Okta groups to LiteLLM/OpenWebUI roles

## Supported Identity Providers

LiteLLM supports JWT-based auth with:
- Okta (via generic OIDC)
- Azure AD
- Keycloak
- Google Cloud
- Any OIDC-compliant provider

## Required Actions

- [ ] Create Okta Application (OIDC - Web Application)
- [ ] Configure Okta authorization server and scopes
- [ ] Obtain Okta domain, client ID, and client secret
- [ ] Create Kubernetes Secret for Okta credentials
- [ ] Configure `JWT_PUBLIC_KEY_URL` pointing to Okta JWKS endpoint
- [ ] Set up OpenWebUI OAuth environment variables
- [ ] Configure callback URLs in Okta application settings
- [ ] Map Okta groups to application roles
- [ ] Test SSO login flow end-to-end
- [ ] Configure logout URL for single logout
- [ ] Set up user attribute mapping (email, name, groups)

## Okta Application Setup

1. Create new App Integration in Okta Admin Console
2. Select "OIDC - OpenID Connect" and "Web Application"
3. Configure redirect URIs: `https://<your-domain>/oauth/callback`
4. Enable required scopes: `openid`, `profile`, `email`
5. Note Client ID and Client Secret

## Configuration Example

### LiteLLM Proxy Config

```yaml
general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY

litellm_settings:
  # JWT validation against Okta
  jwt_public_key_url: "https://<okta-domain>/oauth2/default/v1/keys"
```

### OpenWebUI Environment Variables

```yaml
env:
  - name: OAUTH_PROVIDER
    value: "oidc"
  - name: OAUTH_PROVIDER_NAME
    value: "Okta"
  - name: OPENID_PROVIDER_URL
    value: "https://<okta-domain>/oauth2/default/.well-known/openid-configuration"
  - name: OAUTH_CLIENT_ID
    valueFrom:
      secretKeyRef:
        name: okta-secrets
        key: client-id
  - name: OAUTH_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: okta-secrets
        key: client-secret
  - name: OAUTH_SCOPES
    value: "openid profile email"
  - name: ENABLE_OAUTH_SIGNUP
    value: "true"
```

## Kubernetes Secret Example

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: okta-secrets
type: Opaque
stringData:
  client-id: "<okta-client-id>"
  client-secret: "<okta-client-secret>"
```

## Documentation

- https://docs.litellm.ai/docs/proxy/token_auth
- https://developer.okta.com/docs/guides/implement-oauth-for-okta/main/
