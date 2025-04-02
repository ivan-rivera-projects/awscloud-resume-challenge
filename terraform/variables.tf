variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "The root domain name for the website (e.g., example.com)."
  type        = string
  default     = "iam-ivan.com" # Replace if different
}

variable "s3_backend_bucket" {
  description = "The name of the S3 bucket for Terraform state."
  type        = string
  default     = "iam-ivan-terraform-state-bucket" # Replace if different
}

variable "dynamodb_lock_table" {
  description = "The name of the DynamoDB table for Terraform state locking."
  type        = string
  default     = "iam-ivan-terraform-locks" # Replace if different
}

variable "notification_email" {
  description = "The email address for sending feedback notifications (must be verified in SES)."
  type        = string
  default     = "1shotmanagement@gmail.com" # Replace if different
}

variable "tags" {
  description = "Default tags to apply to all resources."
  type        = map(string)
  default = {
    Project     = "CloudResumeChallenge"
    ManagedBy   = "Terraform"
    Environment = "Production" # Or "Development"
  }
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for the CloudFront distribution (must be in us-east-1 for CloudFront)."
  type        = string
  # Replace with your actual ACM certificate ARN
  default = "arn:aws:acm:us-east-1:954976299507:certificate/30b5287d-4c07-49db-a4d7-f1d865c7bd34"
}

variable "waf_web_acl_arn" {
  description = "ARN of the WAFv2 Web ACL to associate with CloudFront (must be global)."
  type        = string
  # Replace with your actual WAF ARN or set to null if not using WAF
  default = "arn:aws:wafv2:us-east-1:954976299507:global/webacl/CreatedByCloudFront-e543817f-4ff9-41f7-92be-2a9df90c738d/7c6c5170-efef-4ebd-b82e-cfb4f3d2b8dd"
}