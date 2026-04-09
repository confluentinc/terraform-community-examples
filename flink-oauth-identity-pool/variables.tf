# OAuth provider configuration
# These variables configure the Terraform provider to authenticate using OAuth
variable "oauth_external_token_url" {
  description = "The token URL for your OAuth identity provider (e.g., https://your-idp.example.com/oauth2/token)"
  type        = string
}

variable "oauth_external_client_id" {
  description = "The client ID for OAuth authentication"
  type        = string
  sensitive   = true
}

variable "oauth_external_client_secret" {
  description = "The client secret for OAuth authentication"
  type        = string
  sensitive   = true
}

variable "oauth_identity_pool_id" {
  description = "The ID of the OAuth identity pool to use for Terraform provider authentication"
  type        = string
}

# Identity provider configuration
variable "identity_provider_id" {
  description = "The ID of the existing OAuth identity provider in Confluent Cloud (e.g., op-abc123)"
  type        = string
}
