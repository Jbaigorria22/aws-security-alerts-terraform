data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "${var.project_name}-cloudtrail-${local.account_id}"
}

resource "aws_s3_bucket" "trail_logs" {
  bucket        = local.bucket_name
  force_destroy = true
}


resource "aws_s3_bucket_public_access_block" "trail_logs" {
  bucket                  = aws_s3_bucket.trail_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail_logs" {
  bucket = aws_s3_bucket.trail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail_logs" {
  bucket = aws_s3_bucket.trail_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter {}

    expiration {
      days = 30
    }
  }
}