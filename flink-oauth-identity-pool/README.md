# OAuth Identity Pool with Flink Service Account Delegation

This example demonstrates how to use OAuth identity pools with Confluent Cloud for Apache Flink using the **service account delegation** pattern.

## Architecture

In this pattern:
1. **Identity pool authenticates** the request using an OAuth token from your identity provider
2. **Service account executes** the Flink statement with its RBAC permissions
3. **Assigner role** grants the identity pool permission to delegate work to the service account

This provides separation between authentication (who you are) and execution (what permissions you have).

## Prerequisites

Before running this example, you must:

1. **Create an OAuth identity provider** in Confluent Cloud:
   - Follow the guide: [Configure OAuth/OIDC Identity Providers](https://docs.confluent.io/cloud/current/access-management/authenticate/oauth/identity-providers.html)
   - Note the identity provider ID (e.g., `op-abc123`)

2. **Configure your OAuth identity provider** with:
   - Token URL
   - Client ID and Client Secret
   - Appropriate scopes

3. **Create an identity pool** for Terraform provider authentication:
   - This pool is used by the Terraform provider itself to authenticate
   - Note the pool ID (e.g., `pool-xyz789`)

## Key Resources

This example creates:

- **`confluent_identity_pool`**: An identity pool with claim-based filters for Flink statement authentication
- **`confluent_service_account`**: A service account that will execute Flink statements
- **`confluent_role_binding` (Assigner)**: **CRITICAL** - Grants the identity pool permission to delegate work to the service account
- **`confluent_role_binding` (FlinkDeveloper)**: Grants the service account permission to run Flink statements
- **`confluent_flink_compute_pool`**: Compute resources for Flink
- **`confluent_flink_statement`**: Example statement using the service account as principal

## Configuration

Create a `terraform.tfvars` file with your values:

```hcl
# OAuth provider configuration (for Terraform provider authentication)
oauth_external_token_url     = "https://your-idp.example.com/oauth2/token"
oauth_external_client_id     = "your-client-id"
oauth_external_client_secret = "your-client-secret"
oauth_identity_pool_id       = "pool-xyz789"  # Pool for Terraform provider auth

# Identity provider for the Flink statements pool
identity_provider_id = "op-abc123"
```

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Important Notes

### The Assigner Role is Critical

The `confluent_role_binding.pool_assigner` resource is **required** for OAuth delegation to work:

```hcl
resource "confluent_role_binding" "pool_assigner" {
  principal   = "User:${confluent_identity_pool.flink_statements.id}"
  role_name   = "Assigner"
  crn_pattern = "${data.confluent_organization.main.resource_name}/service-account=${confluent_service_account.flink_statements_runner.id}"
}
```

Without this role binding, API requests will fail with authorization errors.

### Claim Filters

The example uses a simple claim filter:

```hcl
filter = "claims.sub.startsWith(\"flink-\")"
```

Adjust this filter to match your identity provider's token claims. For example:
- `claims.sub == "specific-client-id"`
- `claims.appid in ["app1", "app2"]`
- `'group-name' in claims.groups`

See [OAuth Identity Pool Filters](https://docs.confluent.io/cloud/current/access-management/authenticate/oauth/identity-pools.html#set-oauth-identity-pool-filters) for more examples.

### Service Account as Principal

Notice that the Flink statement uses the **service account** as the principal, not the identity pool:

```hcl
principal {
  id = confluent_service_account.flink_statements_runner.id
}
```

This is the key difference from using an identity pool directly as the principal.

## Alternative Pattern: Identity Pool as Principal

For a simpler setup (suitable for development/testing), you can use the identity pool directly as the principal:

```hcl
resource "confluent_flink_statement" "example" {
  # ... other configuration ...
  principal {
    id = confluent_identity_pool.flink_statements.id
  }
}
```

In this case:
- The identity pool both authenticates and executes
- Grant the identity pool `FlinkDeveloper` role directly at the environment level
- The `Assigner` role binding is not needed

For production use, the service account delegation pattern (shown in this example) is recommended.

## References

- [Use OAuth Identity Pools with Flink](https://docs.confluent.io/cloud/current/access-management/authenticate/oauth/identity-pools.html#use-with-af-statements)
- [Flink REST API OAuth Authentication](https://docs.confluent.io/cloud/current/flink/operate-and-deploy/flink-rest-api.html#flink-rest-api-oauth)
- [Flink RBAC Roles](https://docs.confluent.io/cloud/current/flink/operate-and-deploy/flink-rbac.html)
- [OAuth/OIDC Identity Providers](https://docs.confluent.io/cloud/current/access-management/authenticate/oauth/identity-providers.html)
- [Assigner Role](https://docs.confluent.io/cloud/current/access-management/access-control/rbac/predefined-rbac-roles.html#assigner)
