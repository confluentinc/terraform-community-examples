terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "2.67.0"
    }
  }
}

locals {
  cloud  = "AWS"
  region = "us-east-2"
}

# Configure the provider to use OAuth for authentication
provider "confluent" {
  oauth {
    oauth_external_token_url     = var.oauth_external_token_url
    oauth_external_client_id     = var.oauth_external_client_id
    oauth_external_client_secret = var.oauth_external_client_secret
    oauth_identity_pool_id       = var.oauth_identity_pool_id
  }
}

data "confluent_organization" "main" {}

# Reference existing OAuth identity provider
# The identity provider must be created beforehand in Confluent Cloud
data "confluent_identity_provider" "main" {
  id = var.identity_provider_id
}

# Create an identity pool with claim-based filters
# This pool will authenticate requests but delegate execution to a service account
resource "confluent_identity_pool" "flink_statements" {
  identity_provider {
    id = data.confluent_identity_provider.main.id
  }
  display_name = "flink-statements-pool"
  description  = "Identity pool for Flink statement execution via service account delegation"
  # Example claim filter: only allow specific client IDs or subjects
  # Adjust the filter to match your identity provider's token claims
  filter = "claims.sub.startsWith(\"flink-\")"
  # The identity_claim defaults to "claims.sub" if not specified
  # Uncomment to use a different claim for audit logging
  # identity_claim = "claims.email"
}

# Create environment for Flink resources
resource "confluent_environment" "flink_oauth" {
  display_name = "flink-oauth-example"

  stream_governance {
    package = "ESSENTIALS"
  }
}

# Create service account that will execute Flink statements
# This service account will have the necessary RBAC permissions
resource "confluent_service_account" "flink_statements_runner" {
  display_name = "flink-statements-runner"
  description  = "Service account for executing Flink statements via OAuth identity pool delegation"
}

# Grant Assigner role to the identity pool on the service account
# This is CRITICAL: allows the identity pool to delegate work to the service account
# https://docs.confluent.io/cloud/current/access-management/access-control/rbac/predefined-rbac-roles.html#assigner
resource "confluent_role_binding" "pool_assigner" {
  principal   = "User:${confluent_identity_pool.flink_statements.id}"
  role_name   = "Assigner"
  crn_pattern = "${data.confluent_organization.main.resource_name}/service-account=${confluent_service_account.flink_statements_runner.id}"
}

# Grant FlinkDeveloper role to the service account at environment level
# This gives the service account permission to run Flink statements
resource "confluent_role_binding" "sa_flink_developer" {
  principal   = "User:${confluent_service_account.flink_statements_runner.id}"
  role_name   = "FlinkDeveloper"
  crn_pattern = confluent_environment.flink_oauth.resource_name
}

# Create Kafka cluster for Flink to process data from
resource "confluent_kafka_cluster" "main" {
  display_name = "flink-oauth-cluster"
  availability = "SINGLE_ZONE"
  cloud        = local.cloud
  region       = local.region
  standard {}

  environment {
    id = confluent_environment.flink_oauth.id
  }
}

# Get Flink region information
data "confluent_flink_region" "main" {
  cloud  = local.cloud
  region = local.region
}

# Create Flink compute pool
resource "confluent_flink_compute_pool" "main" {
  display_name = "oauth-compute-pool"
  cloud        = local.cloud
  region       = local.region
  max_cfu      = 10

  environment {
    id = confluent_environment.flink_oauth.id
  }
}

# Create a Flink statement using service account as principal
# The OAuth identity pool authenticates the request, but the service account executes it
resource "confluent_flink_statement" "example" {
  organization {
    id = data.confluent_organization.main.id
  }
  environment {
    id = confluent_environment.flink_oauth.id
  }
  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }

  # IMPORTANT: Use service account as principal, not the identity pool
  # The identity pool authenticates (via OAuth token) but delegates execution to this service account
  principal {
    id = confluent_service_account.flink_statements_runner.id
  }

  statement = "SELECT 1"
  properties = {
    "sql.current-catalog"  = confluent_environment.flink_oauth.display_name
    "sql.current-database" = confluent_kafka_cluster.main.display_name
  }
  rest_endpoint = data.confluent_flink_region.main.rest_endpoint

  # Ensure RBAC permissions are set before creating the statement
  depends_on = [
    confluent_role_binding.pool_assigner,
    confluent_role_binding.sa_flink_developer
  ]
}
