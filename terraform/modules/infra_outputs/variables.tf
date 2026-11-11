variable "state_bucket_name" {
  description = "S3 bucket holding the judicial infrastructure terraform state (owned by the infra repo). e.g. dev-dmr-judicial-terraform-state."
  type        = string
}

variable "aws_region" {
  description = "AWS region of the infra state bucket."
  type        = string
  default     = "eu-west-1"
}

variable "legacy_secrets_manager_enabled" {
  description = <<-EOT
    Whether the judicial foundation still has the legacy Secrets Manager
    app-secret units (judicial_secrets + judicial_xroad_secrets). Dev has them
    (default true). Prod never provisioned them — all app secrets, including the
    5 XROAD_* keys, live in SSM Parameter Store (judicial_ssm_secrets) — so prod
    sets this to false to skip the Secrets Manager remote-state reads. When
    false, secret_names and xroad_secret_names are empty maps and services must
    source everything from parameter_names (SSM).
  EOT
  type        = bool
  default     = true
}
