# =============================================================================
# Cluster Linking: Enterprise (Private) → Public Dedicated Cluster
# =============================================================================
# Source-initiated cluster link from the private-networked enterprise cluster
# to a public dedicated cluster in a separate environment.
#
# Source-initiated is required because the enterprise cluster is behind
# PrivateLink — the destination cannot initiate connections to the source.
#
# Flow: Source (Enterprise, private) --OUTBOUND--> Destination (Dedicated, public)
# =============================================================================

terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "2.62.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

# =============================================================================
# Source Cluster (Enterprise, Private Network)
# =============================================================================
# Reference to existing enterprise cluster with private networking
data "confluent_kafka_cluster" "enterprise" {
  id = var.source_kafka_cluster_id
  environment {
    id = var.source_kafka_cluster_environment_id
  }
}

# Service account for managing the source enterprise cluster
resource "confluent_service_account" "app-manager-source-cluster" {
  display_name = "app-manager-source-cluster"
  description  = "Service account to manage source enterprise Kafka cluster"
}

# CloudClusterAdmin role on the source cluster
# See https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/security-cloud.html#rbac-roles-and-kafka-acls-summary
resource "confluent_role_binding" "app-manager-source-cluster-admin" {
  principal   = "User:${confluent_service_account.app-manager-source-cluster.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = data.confluent_kafka_cluster.enterprise.rbac_crn
}

# API key for the source cluster
resource "confluent_api_key" "app-manager-kafka-api-key" {
  display_name = "app-manager-source-cluster-api-key"
  description  = "Kafka API Key for source enterprise cluster"
  owner {
    id          = confluent_service_account.app-manager-source-cluster.id
    api_version = confluent_service_account.app-manager-source-cluster.api_version
    kind        = confluent_service_account.app-manager-source-cluster.kind
  }

  managed_resource {
    id          = data.confluent_kafka_cluster.enterprise.id
    api_version = data.confluent_kafka_cluster.enterprise.api_version
    kind        = data.confluent_kafka_cluster.enterprise.kind

    environment {
      id = data.confluent_kafka_cluster.enterprise.environment[0].id
    }
  }

  depends_on = [
    confluent_role_binding.app-manager-source-cluster-admin
  ]
}

# =============================================================================
# Source Topics (on Enterprise Cluster)
# =============================================================================
# Topics to be replicated via cluster link

resource "confluent_kafka_topic" "orders" {
  kafka_cluster {
    id = data.confluent_kafka_cluster.enterprise.id
  }
  topic_name    = "orders"
  rest_endpoint = data.confluent_kafka_cluster.enterprise.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_topic" "s3_sink_topic" {
  kafka_cluster {
    id = data.confluent_kafka_cluster.enterprise.id
  }
  topic_name    = "s3-sink-data"
  rest_endpoint = data.confluent_kafka_cluster.enterprise.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_topic" "s3_source_topic" {
  kafka_cluster {
    id = data.confluent_kafka_cluster.enterprise.id
  }
  topic_name    = "s3-source-data"
  rest_endpoint = data.confluent_kafka_cluster.enterprise.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

# =============================================================================
# Destination Cluster (Public Dedicated)
# =============================================================================
# Data source for the destination public dedicated cluster
data "confluent_kafka_cluster" "destination" {
  id = var.destination_kafka_cluster_id
  environment {
    id = var.destination_kafka_cluster_environment_id
  }
}

# Service account for managing the destination cluster
resource "confluent_service_account" "cluster-link-destination-manager" {
  display_name = "cluster-link-destination-manager"
  description  = "Service account to manage destination cluster for cluster linking"
}

# CloudClusterAdmin role on the destination cluster
# See https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/security-cloud.html#rbac-roles-and-kafka-acls-summary
resource "confluent_role_binding" "cluster-link-destination-admin" {
  principal   = "User:${confluent_service_account.cluster-link-destination-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = data.confluent_kafka_cluster.destination.rbac_crn
}

# API key for the destination cluster
resource "confluent_api_key" "cluster-link-destination-api-key" {
  display_name = "cluster-link-destination-api-key"
  description  = "Kafka API Key for cluster link destination cluster"
  owner {
    id          = confluent_service_account.cluster-link-destination-manager.id
    api_version = confluent_service_account.cluster-link-destination-manager.api_version
    kind        = confluent_service_account.cluster-link-destination-manager.kind
  }

  managed_resource {
    id          = data.confluent_kafka_cluster.destination.id
    api_version = data.confluent_kafka_cluster.destination.api_version
    kind        = data.confluent_kafka_cluster.destination.kind

    environment {
      id = data.confluent_kafka_cluster.destination.environment[0].id
    }
  }

  depends_on = [
    confluent_role_binding.cluster-link-destination-admin
  ]
}

# =============================================================================
# Cluster Link Configuration
# =============================================================================

# -----------------------------------------------------------------------------
# Cluster Link: Destination side (INBOUND) — created first
# The destination cluster accepts the incoming connection from the source
# -----------------------------------------------------------------------------
resource "confluent_cluster_link" "destination-inbound" {
  link_name       = var.cluster_link_name
  link_mode       = "DESTINATION"
  connection_mode = "INBOUND"

  destination_kafka_cluster {
    id            = data.confluent_kafka_cluster.destination.id
    rest_endpoint = data.confluent_kafka_cluster.destination.rest_endpoint
    credentials {
      key    = confluent_api_key.cluster-link-destination-api-key.id
      secret = confluent_api_key.cluster-link-destination-api-key.secret
    }
  }

  source_kafka_cluster {
    id                 = data.confluent_kafka_cluster.enterprise.id
    bootstrap_endpoint = data.confluent_kafka_cluster.enterprise.bootstrap_endpoint
  }

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Cluster Link: Source side (OUTBOUND) — source initiates connection
# The enterprise cluster pushes data to the destination
# NOTE: rest_endpoint on the source is private — terraform must be able to
# reach it (via proxy/bastion or run from within VPC)
# -----------------------------------------------------------------------------
resource "confluent_cluster_link" "source-outbound" {
  link_name       = var.cluster_link_name
  link_mode       = "SOURCE"
  connection_mode = "OUTBOUND"

  source_kafka_cluster {
    id            = data.confluent_kafka_cluster.enterprise.id
    rest_endpoint = data.confluent_kafka_cluster.enterprise.rest_endpoint
    credentials {
      key    = confluent_api_key.app-manager-kafka-api-key.id
      secret = confluent_api_key.app-manager-kafka-api-key.secret
    }
  }

  destination_kafka_cluster {
    id                 = data.confluent_kafka_cluster.destination.id
    bootstrap_endpoint = data.confluent_kafka_cluster.destination.bootstrap_endpoint
    credentials {
      key    = confluent_api_key.cluster-link-destination-api-key.id
      secret = confluent_api_key.cluster-link-destination-api-key.secret
    }
  }

  depends_on = [
    confluent_cluster_link.destination-inbound
  ]

  lifecycle {
    prevent_destroy = true
  }
}

# =============================================================================
# Mirror Topics on Destination Cluster
# =============================================================================
# One mirror topic per source topic. The mirror topic is created on the
# destination (public dedicated) cluster and continuously replicates from
# the source (private enterprise) cluster via the cluster link.
# =============================================================================

resource "confluent_kafka_mirror_topic" "orders" {
  source_kafka_topic {
    topic_name = confluent_kafka_topic.orders.topic_name
  }
  cluster_link {
    link_name = confluent_cluster_link.source-outbound.link_name
  }
  kafka_cluster {
    id            = data.confluent_kafka_cluster.destination.id
    rest_endpoint = data.confluent_kafka_cluster.destination.rest_endpoint
    credentials {
      key    = confluent_api_key.cluster-link-destination-api-key.id
      secret = confluent_api_key.cluster-link-destination-api-key.secret
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "confluent_kafka_mirror_topic" "s3_sink_data" {
  source_kafka_topic {
    topic_name = confluent_kafka_topic.s3_sink_topic.topic_name
  }
  cluster_link {
    link_name = confluent_cluster_link.source-outbound.link_name
  }
  kafka_cluster {
    id            = data.confluent_kafka_cluster.destination.id
    rest_endpoint = data.confluent_kafka_cluster.destination.rest_endpoint
    credentials {
      key    = confluent_api_key.cluster-link-destination-api-key.id
      secret = confluent_api_key.cluster-link-destination-api-key.secret
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "confluent_kafka_mirror_topic" "s3_source_data" {
  source_kafka_topic {
    topic_name = confluent_kafka_topic.s3_source_topic.topic_name
  }
  cluster_link {
    link_name = confluent_cluster_link.source-outbound.link_name
  }
  kafka_cluster {
    id            = data.confluent_kafka_cluster.destination.id
    rest_endpoint = data.confluent_kafka_cluster.destination.rest_endpoint
    credentials {
      key    = confluent_api_key.cluster-link-destination-api-key.id
      secret = confluent_api_key.cluster-link-destination-api-key.secret
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
