variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key (also referred as Cloud API ID)"
  type        = string
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
}

variable "source_kafka_cluster_id" {
  description = "ID of the Source Enterprise Kafka Cluster (private networked)"
  type        = string
}

variable "source_kafka_cluster_environment_id" {
  description = "ID of the Environment that the Source Kafka Cluster belongs to"
  type        = string
}

variable "destination_kafka_cluster_id" {
  description = "ID of the Destination Kafka Cluster (public dedicated)"
  type        = string
}

variable "destination_kafka_cluster_environment_id" {
  description = "ID of the Environment that the Destination Kafka Cluster belongs to"
  type        = string
}

variable "cluster_link_name" {
  description = "Name of the Cluster Link to create"
  type        = string
  default     = "enterprise-to-dedicated-link"
}
