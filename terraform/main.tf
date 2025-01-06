###############################################################################
# IAM-IVAN.COM AWS CLOUD RESUME TERRAFORM BLOCK
# - Using S3 backend with DynamoDB for state locking
###############################################################################
terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.47.0, < 5.0"  # Updated to ensure aws_default_tags is supported
    }
  }

  backend "s3" {
    bucket         = "iam-ivan-terraform-state-bucket"       # Change to your real state bucket
    key            = "./terraform/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "iam-ivan-terraform-locks"               # Change if you used a different lock table name
    encrypt        = true
  }
}

###############################################################################
# AWS PROVIDER
###############################################################################
provider "aws" {
  region = "us-east-1"
}

###############################################################################
# GLOBAL TAGS - Add "Project = CloudResumeChallenge" to all resources
###############################################################################
# resource "aws_default_tags" "default" {
#  tags = {
#    Project = "CloudResumeChallenge"
#   }
# }

###############################################################################
# EXISTING S3 BUCKET (hosting your website)
###############################################################################
resource "aws_s3_bucket" "website_bucket" {
  # You can add website hosting configuration, etc. if needed
  bucket = "iam-ivan.com"  # This must match your actual bucket name
}

###############################################################################
# ROUTE 53 HOSTED ZONE (read-only data source for zone info)
###############################################################################
data "aws_route53_zone" "main_zone" {
  name         = "iam-ivan.com."
  private_zone = false
}

###############################################################################
# CLOUDFRONT DISTRIBUTION (matches your real config)
###############################################################################
resource "aws_cloudfront_distribution" "website_distribution" {
  enabled         = true
  is_ipv6_enabled = true

  # Keep your custom domain aliases
  aliases = [
    "iam-ivan.com",
    "www.iam-ivan.com"
  ]

  # Keep your WAF ID if you’re using a WAF
  web_acl_id = "arn:aws:wafv2:us-east-1:954976299507:global/webacl/CreatedByCloudFront-e543817f-4ff9-41f7-92be-2a9df90c738d/7c6c5170-efef-4ebd-b82e-cfb4f3d2b8dd"

  # Match your existing origin
  origin {
    domain_name = "iam-ivan.com.s3-website-us-east-1.amazonaws.com"
    origin_id   = "iam-ivan.com.s3-website-us-east-1.amazonaws.com"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = [
        "SSLv3",
        "TLSv1",
        "TLSv1.1",
        "TLSv1.2",
      ]
    }
  }

default_cache_behavior {
  target_origin_id       = "iam-ivan.com.s3-website-us-east-1.amazonaws.com"
  viewer_protocol_policy = "https-only"
  allowed_methods        = ["GET", "HEAD"]
  cached_methods         = ["GET", "HEAD"]
  compress               = true
  default_ttl            = 0
  max_ttl                = 0
  min_ttl                = 0
  cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"  # Ensure this matches your existing policy

  # Remove forwarded_values if using cache_policy_id
}





#  # Match your default cache behavior exactly
#  default_cache_behavior {
#    target_origin_id       = "iam-ivan.com.s3-website-us-east-1.amazonaws.com"
#    viewer_protocol_policy = "https-only"
#    allowed_methods        = ["GET", "HEAD"]
#    cached_methods         = ["GET", "HEAD"]
#    compress               = true
#
#    # From your plan, these were 0 in your actual config
#    default_ttl = 0
#    max_ttl     = 0
#    min_ttl     = 0
#
#    forwarded_values {
#      query_string = false
#      cookies {
#        forward = "none"
#      }
#    }
#  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # Keep your custom ACM certificate
    acm_certificate_arn            = "arn:aws:acm:us-east-1:954976299507:certificate/30b5287d-4c07-49db-a4d7-f1d865c7bd34"
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
    cloudfront_default_certificate = false
  }
}

###############################################################################
# EXISTING LAMBDA FUNCTION
###############################################################################
resource "aws_lambda_function" "cloudresume_visit_api" {
  function_name = "CloudResume-visit-api"

  # Use the same role your Lambda is actually using
  role = "arn:aws:iam::954976299507:role/service-role/CloudResume-visit-api-role-42h32yl1"

  # Match your real handler & runtime
  handler = "lambda_function.lambda_handler"
  runtime = "python3.10"  # Updated to a supported runtime

  filename         = "path/to/your/deployment-package.zip"  # Add your deployment package path
#  source_code_hash = filebase64sha256("path/to/your/deployment-package.zip")  # Optional

  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash
    ]
  }
}

###############################################################################
# EXISTING DYNAMODB TABLE (CloudResume-Visit)
###############################################################################
resource "aws_dynamodb_table" "cloudresume_visit" {
  name         = "CloudResume-Visit"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}