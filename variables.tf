variable "aws_region" {
  description = "Region for every resource. Must be us-east-1."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "This lab must run in us-east-1. See docs/adr/0001."
  }
}

variable "project_name" {
  description = "Prefix used to name resources."
  type        = string
  default     = "sec-alerts"
}

variable "alert_email" {
  description = "Email address that receives the security alerts."
  type        = string
  sensitive   = true
}