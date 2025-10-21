locals {
  confluent_cluster_id = var.confluent_kafka_cluster_id
  raw_topic_name        = "topic_private_${var.environment}_newsapi"
  curated_topic_name    = "topic_${var.environment}_news"
}

resource "confluent_kafka_topic" "raw" {
  count = local.confluent_cluster_id != "" ? 1 : 0

  kafka_cluster {
    id = local.confluent_cluster_id
  }

  topic_name       = local.raw_topic_name
  partitions_count = var.kafka_raw_partitions
  rest_endpoint    = var.confluent_rest_endpoint

  config = {
    "retention.ms"   = tostring(var.kafka_raw_retention_ms)
    "cleanup.policy" = "delete"
  }

  credentials {
    key    = var.confluent_api_key
    secret = var.confluent_api_secret
  }
}

resource "confluent_kafka_topic" "curated" {
  count = local.confluent_cluster_id != "" ? 1 : 0

  kafka_cluster {
    id = local.confluent_cluster_id
  }

  topic_name       = local.curated_topic_name
  partitions_count = var.kafka_curated_partitions
  rest_endpoint    = var.confluent_rest_endpoint

  config = {
    "retention.ms"   = tostring(var.kafka_curated_retention_ms)
    "cleanup.policy" = var.kafka_curated_cleanup_policy
  }

  credentials {
    key    = var.confluent_api_key
    secret = var.confluent_api_secret
  }
}
