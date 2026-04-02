# Define an S3 bucket for static website hosting
resource "aws_s3_bucket" "weather_app" {
  bucket = "weather-tracker-app-bucket-8jh7"  # Use a globally unique name

  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  # Set bucket ownership controls
  lifecycle {
    prevent_destroy = true  # Prevent accidental deletion
  }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket                  = aws_s3_bucket.weather_app.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Upload website files to the S3 bucket
resource "aws_s3_object" "website_index" {
  bucket = aws_s3_bucket.weather_app.id
  key    = "index.html"
  source = "website/index.html"
  content_type = "text/html"
}

resource "aws_s3_object" "website_style" {
  bucket = aws_s3_bucket.weather_app.id
  key    = "styles.css"
  source = "website/styles.css"
  content_type = "text/css"
}

resource "aws_s3_object" "website_script" {
  bucket = aws_s3_bucket.weather_app.id
  key    = "script.js"
  source = "website/script.js"
  content_type = "application/javascript"
}

# Upload assets (images) to the S3 bucket
resource "aws_s3_object" "website_assets" {
  for_each = fileset("website/assets", "*")
  bucket   = aws_s3_bucket.weather_app.id
  key      = "assets/${each.value}"
  source   = "website/assets/${each.value}"
}

# Add a bucket policy to allow public read access
resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.weather_app.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "PublicReadGetObject",
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "arn:aws:s3:::${aws_s3_bucket.weather_app.id}/*"
      },
      {
        Sid       = "CloudFrontLogsWrite",
        Effect    = "Allow",
        Principal = {
          Service = "cloudfront.amazonaws.com"
        },
        Action    = "s3:PutObject",
        Resource  = "arn:aws:s3:::${aws_s3_bucket.weather_app.id}/cloudfront-logs/*"
      }
    ]
  })
}

resource "aws_route53_health_check" "aws_health_check" {
  type              = "HTTPS"
  fqdn              = "d1c0j68povfl4e.cloudfront.net"
  port              = 443
  request_interval  = 30
  failure_threshold = 3
}

resource "aws_route53_zone" "main" {
  name = "techsubscribers.com"
}

import {
  to = aws_route53_zone.main
  id = "Z07353383V6MGP04V2K9L"
}

resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "techsubscribers.com"
  type    = "A"

  alias {
    name                   = "d1c0j68povfl4e.cloudfront.net"
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = true
  }

  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier  = "primary-root"
  health_check_id = aws_route53_health_check.aws_health_check.id
}

resource "aws_route53_record" "primary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.techsubscribers.com"
  type    = "CNAME"
  records = ["d1c0j68povfl4e.cloudfront.net"]
  ttl     = 300


  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier = "primary"
  health_check_id = aws_route53_health_check.aws_health_check.id
}
