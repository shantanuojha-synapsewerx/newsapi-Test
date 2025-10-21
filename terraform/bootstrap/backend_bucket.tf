terraform {
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = "ap-south-1"
}

variable "bucket_name" {
  type    = string
  default = "terraform-state-shantanu"
}

# ARN of the IAM principal that should be allowed access to the state bucket.
# Default value uses the terraform user ARN you created earlier — override if different.
variable "terraform_user_arn" {
  type    = string
  default = "arn:aws:iam::375499005584:user/terraform"
}

resource "aws_s3_bucket" "tf_state" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Name        = var.bucket_name
    Environment = "dev"
    Project     = "news-ingest-mvp"
  }
}

# Block public access at bucket level
resource "aws_s3_bucket_public_access_block" "block" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable server-side encryption (SSE-S3: AES256)
resource "aws_s3_bucket_server_side_encryption_configuration" "sse" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Enable versioning (recommended for Terraform state)
resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Restrictive bucket policy — allow only the specified terraform user (and s3 actions required for TF backend)
data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid    = "AllowTerraformUserFullAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [var.terraform_user_arn]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]

    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "restrict" {
  bucket = aws_s3_bucket.tf_state.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}

output "bucket_name" {
  value = aws_s3_bucket.tf_state.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.tf_state.arn
}
