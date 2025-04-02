###############################################################################
# IAM-IVAN.COM AWS CLOUD RESUME TERRAFORM BLOCK
# - Using S3 backend with DynamoDB for state locking
###############################################################################
terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Loosen version constraint slightly, ensure compatibility
    }
  }

  backend "s3" {
    bucket         = "iam-ivan-terraform-state-bucket" # Use hardcoded value - Variables not allowed in backend block
    key            = "terraform.tfstate"               # Store state at the root of the bucket
    region         = "us-east-1"                       # Use hardcoded value - Variables not allowed in backend block
    dynamodb_table = "iam-ivan-terraform-locks"        # Use hardcoded value - Variables not allowed in backend block
    encrypt        = true
  }
}

###############################################################################
# AWS PROVIDER
###############################################################################
provider "aws" {
  region = var.aws_region

  # Configure default tags directly in the provider block (AWS provider v5+)
  default_tags {
    tags = var.tags
  }
}

###############################################################################
# Default tags are now configured in the provider block above
###############################################################################
# resource "aws_default_tags" "default" { ... } # This block is removed

###############################################################################
# S3 BUCKET (hosting website content)
###############################################################################
# Note: Website configuration (static hosting, public access) and content upload
# are often handled outside core infrastructure TF, e.g., via CI/CD or separate TF.
# This definition ensures the bucket exists and is tagged.
resource "aws_s3_bucket" "website_bucket" {
  bucket = var.domain_name
}

# TODO: Add S3 bucket policy for CloudFront access if needed (using Origin Access Identity/Control)
# TODO: Add S3 website configuration if accessing directly via S3 URL (not recommended with CloudFront)

# S3 Bucket Policy allowing CloudFront OAC access
data "aws_iam_policy_document" "s3_oac_policy_doc" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.website_bucket.arn}/*"] # Allow access to all objects in the bucket

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    # Condition restricts access to only the specific CloudFront distribution
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.website_distribution.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "s3_oac_policy" {
  bucket = aws_s3_bucket.website_bucket.id
  policy = data.aws_iam_policy_document.s3_oac_policy_doc.json
}

###############################################################################
# CLOUDFRONT ORIGIN ACCESS CONTROL (OAC) for S3 Origin
###############################################################################
resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "${var.domain_name}-s3-oac"
  description                       = "OAC for S3 bucket ${var.domain_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always" # Always sign requests for S3
  signing_protocol                  = "sigv4"  # Use SigV4
}
###############################################################################
# ROUTE 53 HOSTED ZONE (Data source to get Zone ID)
###############################################################################
data "aws_route53_zone" "main_zone" {
  name         = "${var.domain_name}." # Ensure trailing dot
  private_zone = false
}

###############################################################################
# CLOUDFRONT DISTRIBUTION
###############################################################################
resource "aws_cloudfront_distribution" "website_distribution" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "CloudFront distribution for ${var.domain_name}"

  aliases = [
    var.domain_name,
    "www.${var.domain_name}"
  ]

  default_root_object = "index.html" # Serve index.html for root requests

  # Associate WAF if ARN is provided
  web_acl_id = var.waf_web_acl_arn != "" ? var.waf_web_acl_arn : null

  # Match your existing origin
  # Origin: S3 Bucket
  # Using S3 website endpoint requires public bucket access.
  # Consider using S3 REST API endpoint + Origin Access Control (OAC) for private bucket access.
  origin {
    # Use the S3 REST API endpoint (recommended over website endpoint)
    domain_name = aws_s3_bucket.website_bucket.bucket_regional_domain_name
    origin_id   = "S3-${var.domain_name}" # Logical ID for this origin

    # Use Origin Access Control (OAC) instead of custom_origin_config
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
    # CloudFront will handle the protocol.
    # For private buckets, use Origin Access Control (OAC) instead.
    # origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  # TODO: Implement Origin Access Control (OAC) for enhanced security
  # resource "aws_cloudfront_origin_access_control" "oac" { ... }
  # Update origin block: origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  # Remove custom_origin_config block
  # Update S3 bucket policy to allow OAC access


  default_cache_behavior {
    target_origin_id       = "S3-${var.domain_name}"    # Must match origin_id above
    viewer_protocol_policy = "redirect-to-https"        # Redirect HTTP to HTTPS
    allowed_methods        = ["GET", "HEAD", "OPTIONS"] # Allow OPTIONS for potential CORS
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # Use a managed caching policy (CachingOptimized is a good default)
    # Or define your own aws_cloudfront_cache_policy resource
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed CachingOptimized policy ID

    # Optional: Origin Request Policy (e.g., for CORS headers)
    # origin_request_policy_id = "..." # Managed CORS-S3Origin policy ID if needed
  }





  # Removed commented out section

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
    cloudfront_default_certificate = false # Required when using custom ACM cert
  }
}


###############################################################################
# IAM ROLE & POLICY (Visitor Counter Lambda)
###############################################################################
resource "aws_iam_role" "visitor_counter_lambda_role" {
  name = "CloudResume-VisitorCounterLambdaRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
  tags = merge(var.tags, { Name = "CloudResume-VisitorCounterLambdaRole" })
}

resource "aws_iam_policy" "visitor_counter_lambda_policy" {
  name        = "CloudResume-VisitorCounterLambdaPolicy"
  description = "Policy for Visitor Counter Lambda"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.visitor_counter.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*" # Standard CloudWatch Logs permissions
      }
    ]
  })
  tags = merge(var.tags, { Name = "CloudResume-VisitorCounterLambdaPolicy" })
}

resource "aws_iam_role_policy_attachment" "visitor_counter_lambda_attach" {
  role       = aws_iam_role.visitor_counter_lambda_role.name
  policy_arn = aws_iam_policy.visitor_counter_lambda_policy.arn
}


###############################################################################
# IAM ROLE & POLICY (Feedback Form Lambda)
###############################################################################
resource "aws_iam_role" "feedback_form_lambda_role" {
  name = "CloudResume-FeedbackFormLambdaRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
  tags = merge(var.tags, { Name = "CloudResume-FeedbackFormLambdaRole" })
}

resource "aws_iam_policy" "feedback_form_lambda_policy" {
  name        = "CloudResume-FeedbackFormLambdaPolicy"
  description = "Policy for Feedback Form Lambda"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["dynamodb:PutItem"]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.feedback_submissions.arn
      },
      {
        Action = ["ses:SendEmail"]
        Effect = "Allow"
        # SES SendEmail action requires resource "*" or specific verified identities ARN
        Resource = "*"
        # Optional: Add condition to restrict source email if needed
        # Condition = {
        #   StringEquals = {
        #     "ses:FromAddress" = var.notification_email
        #   }
        # }
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
  tags = merge(var.tags, { Name = "CloudResume-FeedbackFormLambdaPolicy" })
}

resource "aws_iam_role_policy_attachment" "feedback_form_lambda_attach" {
  role       = aws_iam_role.feedback_form_lambda_role.name
  policy_arn = aws_iam_policy.feedback_form_lambda_policy.arn
}

###############################################################################
# IAM ROLE & POLICY (CORS Options Handler Lambda)
###############################################################################
resource "aws_iam_role" "cors_handler_lambda_role" {
  name = "CloudResume-CorsHandlerLambdaRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
  tags = merge(var.tags, { Name = "CloudResume-CorsHandlerLambdaRole" })
}

# Basic execution role policy (CloudWatch Logs only)
data "aws_iam_policy" "lambda_basic_execution_role" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "cors_handler_lambda_attach" {
  role       = aws_iam_role.cors_handler_lambda_role.name
  policy_arn = data.aws_iam_policy.lambda_basic_execution_role.arn
}

###############################################################################
# LAMBDA FUNCTION (Visitor Counter)
###############################################################################
# Note: This replaces the previous "EXISTING LAMBDA FUNCTION" block

# Note: Lambda code is zipped by the CI/CD workflow into lambda_zips/

resource "aws_lambda_function" "visitor_counter" {
  function_name = "CloudResume-visit-api"
  role          = aws_iam_role.visitor_counter_lambda_role.arn
  handler       = "lambda_function.lambda_handler" # Assumes filename is lambda_function.py
  runtime       = "python3.10"                     # Or match your specific version
  timeout       = 10                               # Example timeout in seconds

  filename         = "${path.module}/lambda_zips/CloudResume-visit-api.zip"                   # Reference pre-built zip
  source_code_hash = filebase64sha256("${path.module}/lambda_zips/CloudResume-visit-api.zip") # Calculate hash from file

  # Add environment variables if needed, e.g., table name
  # environment {
  #   variables = {
  #     TABLE_NAME = aws_dynamodb_table.visitor_counter.name
  #   }
  # }

  tags = merge(var.tags, { Name = "CloudResume-VisitorCounterLambda" })

  # Remove the lifecycle block that ignores code changes
}

###############################################################################
# LAMBDA FUNCTION URL (Visitor Counter)
###############################################################################
resource "aws_lambda_function_url" "visitor_counter_url" {
  function_name      = aws_lambda_function.visitor_counter.function_name
  authorization_type = "NONE" # Publicly accessible

  # Optional: Add CORS configuration if needed (though likely not for simple GET)
  # cors {
  #   allow_origins = ["https://${var.domain_name}"] # Restrict to your domain
  #   allow_methods = ["GET"]
  #   allow_headers = ["*"]
  # }
}

# TODO: Update index.html to use this generated URL: aws_lambda_function_url.visitor_counter_url.function_url

###############################################################################
# LAMBDA FUNCTION (Feedback Form Processor)
###############################################################################
# Note: Lambda code is zipped by the CI/CD workflow into lambda_zips/

resource "aws_lambda_function" "feedback_form" {
  function_name = "CloudResume-ProcessFeedbackForm"
  role          = aws_iam_role.feedback_form_lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.10" # Or match your specific version
  timeout       = 15           # Allow a bit more time for SES/DynamoDB

  filename         = "${path.module}/lambda_zips/CloudResume-ProcessFeedbackForm.zip"                   # Reference pre-built zip
  source_code_hash = filebase64sha256("${path.module}/lambda_zips/CloudResume-ProcessFeedbackForm.zip") # Calculate hash from file

  environment {
    variables = {
      TABLE_NAME         = aws_dynamodb_table.feedback_submissions.name
      NOTIFICATION_EMAIL = var.notification_email
    }
  }

  tags = merge(var.tags, { Name = "CloudResume-FeedbackFormLambda" })
}

###############################################################################
# LAMBDA FUNCTION (CORS Options Handler)
###############################################################################
# Note: Lambda code is zipped by the CI/CD workflow into lambda_zips/

resource "aws_lambda_function" "cors_handler" {
  function_name = "CloudResume-CorsHandler"
  role          = aws_iam_role.cors_handler_lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.10" # Or match your specific version
  timeout       = 5

  filename         = "${path.module}/lambda_zips/CloudResumeOptionsHandler.zip"                   # Reference pre-built zip
  source_code_hash = filebase64sha256("${path.module}/lambda_zips/CloudResumeOptionsHandler.zip") # Calculate hash from file

  tags = merge(var.tags, { Name = "CloudResume-CorsHandlerLambda" })
}

###############################################################################
# API GATEWAY V2 (HTTP API for Feedback Form)
###############################################################################
resource "aws_apigatewayv2_api" "feedback_api" {
  name          = "CloudResume-FeedbackAPI"
  protocol_type = "HTTP"
  description   = "API Gateway for Cloud Resume Feedback Form"

  # Define CORS configuration directly on the API for simplicity
  # This handles the browser's preflight OPTIONS request automatically
  # if no specific OPTIONS route is matched.
  # Alternatively, keep the OPTIONS route + Lambda if more complex logic is needed.
  cors_configuration {
    allow_origins = ["https://${var.domain_name}", "http://localhost:8080"] # Allow deployed site and potentially local dev
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
    max_age       = 300 # Cache preflight response for 5 minutes
  }

  tags = merge(var.tags, { Name = "CloudResume-FeedbackAPI" })
}

# Integration for the POST request -> Feedback Form Lambda
resource "aws_apigatewayv2_integration" "feedback_lambda_integration" {
  api_id                 = aws_apigatewayv2_api.feedback_api.id
  integration_type       = "AWS_PROXY" # Standard Lambda proxy integration
  integration_uri        = aws_lambda_function.feedback_form.invoke_arn
  payload_format_version = "2.0" # Use latest payload format
}

# Integration for the OPTIONS request -> CORS Handler Lambda (Optional if using API CORS config)
# If using the API's cors_configuration block above, this integration and the OPTIONS route might be redundant
# unless you need custom OPTIONS logic beyond what API Gateway provides.
# Keeping it for now to match the 3-Lambda structure, but consider simplifying.
resource "aws_apigatewayv2_integration" "cors_lambda_integration" {
  api_id                 = aws_apigatewayv2_api.feedback_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.cors_handler.invoke_arn
  payload_format_version = "2.0"
}

# Route for POST /submit-form
resource "aws_apigatewayv2_route" "post_feedback" {
  api_id    = aws_apigatewayv2_api.feedback_api.id
  route_key = "POST /submit-form" # Matches the path in index.html fetch
  target    = "integrations/${aws_apigatewayv2_integration.feedback_lambda_integration.id}"
}

# Route for OPTIONS /submit-form (Optional if using API CORS config)
resource "aws_apigatewayv2_route" "options_feedback" {
  api_id    = aws_apigatewayv2_api.feedback_api.id
  route_key = "OPTIONS /submit-form"
  target    = "integrations/${aws_apigatewayv2_integration.cors_lambda_integration.id}"
}

# Default stage for the API (auto-deploys changes)
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.feedback_api.id
  name        = "$default" # Special name for default stage
  auto_deploy = true

  tags = merge(var.tags, { Name = "CloudResume-FeedbackAPI-DefaultStage" })
}

# Permissions for API Gateway to invoke the Lambda functions
resource "aws_lambda_permission" "allow_apigw_feedback" {
  statement_id  = "AllowAPIGatewayInvokeFeedback"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.feedback_form.function_name
  principal     = "apigateway.amazonaws.com"

  # Restrict to the specific API Gateway API and route
  source_arn = "${aws_apigatewayv2_api.feedback_api.execution_arn}/*/${aws_apigatewayv2_route.post_feedback.route_key}"
}

resource "aws_lambda_permission" "allow_apigw_cors" {
  statement_id  = "AllowAPIGatewayInvokeCORS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cors_handler.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.feedback_api.execution_arn}/*/${aws_apigatewayv2_route.options_feedback.route_key}"
}

###############################################################################
# ROUTE 53 RECORDS
###############################################################################
# Record for the apex domain (e.g., iam-ivan.com)
resource "aws_route53_record" "apex_domain" {
  zone_id = data.aws_route53_zone.main_zone.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.website_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

# Record for the www subdomain (e.g., www.iam-ivan.com)
resource "aws_route53_record" "www_subdomain" {
  zone_id = data.aws_route53_zone.main_zone.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.website_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

# Optional: Add AAAA records for IPv6 if desired (CloudFront supports IPv6)
resource "aws_route53_record" "apex_domain_ipv6" {
  zone_id = data.aws_route53_zone.main_zone.zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.website_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.website_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www_subdomain_ipv6" {
  zone_id = data.aws_route53_zone.main_zone.zone_id
  name    = "www.${var.domain_name}"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.website_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.website_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

###############################################################################
# DYNAMODB TABLE (Visitor Counter)
###############################################################################
resource "aws_dynamodb_table" "visitor_counter" {
  name         = "CloudResume-Visit" # Keep original name if it exists
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id" # Partition key

  # Define attributes used in keys or indexes
  attribute {
    name = "id"
    type = "S" # String type for the key '1'
  }

  # Note: The 'views' attribute is added/updated by the Lambda,
  # no need to define it in the table schema unless it's part of a key/index.

  tags = merge(var.tags, { Name = "CloudResume-VisitCounterTable" })
}

###############################################################################
# DYNAMODB TABLE (Feedback Form Submissions)
###############################################################################
resource "aws_dynamodb_table" "feedback_submissions" {
  name         = "CloudResume-Feedback"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "SubmissionId" # Unique ID for each submission

  attribute {
    name = "SubmissionId"
    type = "S" # String type for UUID
  }

  # Optional: Add Global Secondary Index (GSI) if needed later, e.g., to query by Email
  # global_secondary_index {
  #   name            = "EmailIndex"
  #   hash_key        = "Email"
  #   projection_type = "ALL" # Or INCLUDE specific attributes
  # }
  # attribute {
  #   name = "Email"
  #   type = "S"
  # }

  tags = merge(var.tags, { Name = "CloudResume-FeedbackTable" })
}