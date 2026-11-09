# Deployed image tag per service, kept in SSM Parameter Store.
#
# CI (deploy job) writes the new tag here, then runs `terraform apply`.
# Terraform reads the live value on refresh and ignores drift, so a manual apply
# never rolls a service back to an old tag. This is the "external party updates
# the image tag in a shared location" pattern from the APRÓ ecs_service module
# docs.
#
# The values below only seed the parameters on first create. They are bootstrap
# placeholders in the prod_<sha>_<rand> shape (dd version = split("_", tag)[1]);
# the first CI run on the prod ref overwrites them before it applies.
#
# Scope: JUD-69 covers web/api/backend only. The other judicial services
# (message-handler, scheduler, xrd-api, digital-mailbox-api) get their image-tag
# params when those services are added to prod (separate tickets), mirroring dev.

locals {
  initial_image_tags = {
    web     = "prod_bootstrap_none"
    api     = "prod_bootstrap_none"
    backend = "prod_bootstrap_none"
  }

  judicial_web_image_tag     = aws_ssm_parameter.image_tag["web"].insecure_value
  judicial_api_image_tag     = aws_ssm_parameter.image_tag["api"].insecure_value
  judicial_backend_image_tag = aws_ssm_parameter.image_tag["backend"].insecure_value
}

resource "aws_ssm_parameter" "image_tag" {
  for_each = local.initial_image_tags

  name           = "/judicial-system/${local.env}/${each.key}/image-tag"
  type           = "String"
  insecure_value = each.value

  lifecycle {
    ignore_changes = [insecure_value]
  }
}
