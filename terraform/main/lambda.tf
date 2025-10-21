# Lambda function using local file (lambda zip must exist at var.lambda_package_path)
resource "aws_lambda_function" "newsapi_ingest" {
  filename         = var.lambda_package_path
  source_code_hash = filebase64sha256(var.lambda_package_path)
  function_name    = "newsapi_ingest_${var.environment}"
  role             = aws_iam_role.lambda_role.arn
  handler          = var.lambda_handler
  runtime          = var.lambda_runtime
  timeout          = 60
  memory_size      = 512

  environment {
    variables = {
      ENVIRONMENT          = var.environment
      NEWSAPI_SECRET_ARN   = aws_secretsmanager_secret.newsapi.arn
      KAFKA_SECRET_ARN     = aws_secretsmanager_secret.kafka.arn
      DDB_TABLE            = aws_dynamodb_table.checkpoint.name
      PAGE_SIZE            = "10"
      DEFAULT_FROM         = "2025-10-01T00:00:00Z"
      RAW_TOPIC            = "topic_private_${var.environment}_newsapi"
      CURATED_TOPIC        = "topic_${var.environment}_news"
    }
  }

  tags = {
    Environment = var.environment
    Project     = "news-ingest-mvp"
  }
}

# EventBridge rule (schedule every minute) and target
resource "aws_cloudwatch_event_rule" "every_minute" {
  name                = "newsapi_ingest_schedule_${var.environment}"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.every_minute.name
  target_id = "newsapi_ingest_lambda_${var.environment}"
  arn       = aws_lambda_function.newsapi_ingest.arn
}

resource "aws_lambda_permission" "allow_events" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.newsapi_ingest.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_minute.arn
}
