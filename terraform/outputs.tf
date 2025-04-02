output "website_url" {
  description = "The URL of the CloudFront distribution for the website."
  value       = "https://${var.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "The ID of the CloudFront distribution."
  value       = aws_cloudfront_distribution.website_distribution.id
}

output "cloudfront_distribution_domain_name" {
  description = "The domain name of the CloudFront distribution."
  value       = aws_cloudfront_distribution.website_distribution.domain_name
}

output "visitor_counter_lambda_url" {
  description = "The URL for the visitor counter Lambda function."
  value       = aws_lambda_function_url.visitor_counter_url.function_url
}

output "feedback_api_endpoint" {
  description = "The base URL for the feedback form API Gateway."
  value       = aws_apigatewayv2_api.feedback_api.api_endpoint
}

output "feedback_api_submit_url" {
  description = "The full URL to POST feedback form submissions to."
  # Note: The route key is hardcoded here; ensure it matches aws_apigatewayv2_route.post_feedback
  value = "${aws_apigatewayv2_api.feedback_api.api_endpoint}/submit-form"
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket hosting website content."
  value       = aws_s3_bucket.website_bucket.bucket
}