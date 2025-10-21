variable "environment" {
  type    = string
  default = "dev"
}

# Sensitive secret values - supplied via TF_VAR_ env vars when running terraform
variable "newsapi_secret_value" {
  description = "NewsAPI secret JSON string or value (e.g. API key). Example: '{\"apiKey\":\"xxx\"}' or the raw key if you will wrap it."
  type        = string
  sensitive   = true
  default     = ""  # prefer to provide via TF_VAR_newsapi_secret_value
}

# Optional Kafka credentials object as JSON string: {"bootstrap":"...","username":"...","password":"..."}
variable "kafka_secret_value" {
  description = "Kafka secret JSON string (optional). Provide as JSON string."
  type        = string
  sensitive   = true
  default     = ""
}

# region variable (ap-south-1)
variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "confluent_cloud_api_key" {
  description = "Confluent Cloud control plane API key; provide via TF_VAR_confluent_cloud_api_key or set environment variables expected by the provider."
  type        = string
  sensitive   = true
  default     = null
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud control plane API secret; provide via TF_VAR_confluent_cloud_api_secret or set environment variables expected by the provider."
  type        = string
  sensitive   = true
  default     = null
}

# Local path to built lambda zip (you must create this prior to apply)
variable "lambda_package_path" {
  type    = string
  default = "../newsapi_ingest.zip"
}

variable "lambda_handler" {
  type    = string
  default = "newsapi_ingest.lambda_handler"
}

variable "lambda_runtime" {
  type    = string
  default = "python3.10"
}

variable "local_exec_bash" {
  description = "Override path to bash executable for local-exec provisioners (set on Windows if needed)."
  type        = string
  default     = ""
}

variable "confluent_environment_id" {
  description = "Confluent Cloud environment ID where the Kafka cluster lives (e.g. env-xxxxx)."
  type        = string
  default     = ""
}

variable "confluent_kafka_cluster_id" {
  description = "Confluent Cloud Kafka cluster ID (e.g. lkc-xxxxx)."
  type        = string
  default     = ""
}

variable "confluent_rest_endpoint" {
  description = "HTTPS REST endpoint for the Confluent Cloud Kafka cluster (e.g. https://pkc-xxxxx.ap-southeast-1.aws.confluent.cloud:443)."
  type        = string
  default     = ""
}

variable "confluent_api_key" {
  description = "Confluent Cloud API key with permissions for topic administration."
  type        = string
  sensitive   = true
  default     = null
}

variable "confluent_api_secret" {
  description = "Confluent Cloud API secret with permissions for topic administration."
  type        = string
  sensitive   = true
  default     = null
}

variable "kafka_raw_partitions" {
  description = "Number of partitions for the raw Kafka topic."
  type        = number
  default     = 3
}

variable "kafka_curated_partitions" {
  description = "Number of partitions for the curated Kafka topic."
  type        = number
  default     = 3
}

variable "kafka_raw_retention_ms" {
  description = "Retention period (ms) for the raw Kafka topic."
  type        = number
  default     = 604800000  # 7 days
}

variable "kafka_curated_retention_ms" {
  description = "Retention period (ms) for the curated Kafka topic."
  type        = number
  default     = 259200000  # 3 days
}

variable "kafka_curated_cleanup_policy" {
  description = "Cleanup policy for the curated Kafka topic."
  type        = string
  default     = "delete"
}

variable "confluent_ksql_endpoint" {
  description = "HTTPS endpoint for the target ksqlDB cluster (e.g. https://pksqlc-xxxxx.ap-south-2.aws.confluent.cloud)."
  type        = string
  default     = ""
}

variable "confluent_ksql_api_key" {
  description = "API key with permission to execute ksqlDB statements via REST." 
  type        = string
  sensitive   = true
  default     = null
}

variable "confluent_ksql_api_secret" {
  description = "API secret paired with confluent_ksql_api_key." 
  type        = string
  sensitive   = true
  default     = null
}
