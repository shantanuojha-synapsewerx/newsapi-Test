output "lambda_function_name" {
  value = aws_lambda_function.newsapi_ingest.function_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.newsapi_ingest.arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.checkpoint.name
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.checkpoint.arn
}

output "secrets_newsapi_arn" {
  value = aws_secretsmanager_secret.newsapi.arn
}

output "secrets_kafka_arn" {
  value = aws_secretsmanager_secret.kafka.arn
}

output "kafka_raw_topic_name" {
  value       = length(confluent_kafka_topic.raw) > 0 ? confluent_kafka_topic.raw[0].topic_name : null
  description = "Name of the raw Kafka topic when Confluent resources are enabled."
}

output "kafka_curated_topic_name" {
  value       = length(confluent_kafka_topic.curated) > 0 ? confluent_kafka_topic.curated[0].topic_name : null
  description = "Name of the curated Kafka topic when Confluent resources are enabled."
}
