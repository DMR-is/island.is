module "infra_outputs" {
  source            = "../modules/infra_outputs"
  state_bucket_name = local.infra_state_bucket
  aws_region        = local.aws_region

  # Prod has NO Secrets Manager app-secret units (judicial_secrets /
  # judicial_xroad_secrets) — every app secret, including the 5 XROAD_* keys,
  # lives in the single SSM Parameter Store unit (judicial_ssm_secrets). Disable
  # the legacy Secrets Manager remote-state reads so infra_outputs does not try
  # to read state that does not exist in prod. Services consume parameter_names
  # (SSM) exclusively. Dev keeps the default (true) and is unaffected.
  legacy_secrets_manager_enabled = false
}
