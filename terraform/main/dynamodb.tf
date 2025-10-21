resource "aws_dynamodb_table" "checkpoint" {
  name         = "newsapi_checkpoint_${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Environment = var.environment
    Project     = "news-ingest-mvp"
  }
}
