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
# Scope: JUD-69 covered web/api/backend. JUD-75 adds the two internal X-Road
# services (xrd-api, digital-mailbox-api) and JUD-74 adds message-handler (the
# SQS worker); their image-tag params are seeded here too, mirroring dev. JUD-73
# adds scheduler (scheduled ECS task). Each image was already built and pushed by
# the prod release pipeline, so the live tag is seeded so the task runs the right
# image on first create.

locals {
  initial_image_tags = {
    web     = "prod_bootstrap_none"
    api     = "prod_bootstrap_none"
    backend = "prod_bootstrap_none"

    # JUD-75: internal X-Road ECS services. The prod release pipeline already
    # built and pushed these images (judicial-v1.0.1); seed the live tag so the
    # services come up healthy on first create instead of a bootstrap placeholder.
    # Only read on first create — ignore_changes below hands ongoing ownership to
    # CI, exactly like web/api/backend.
    xrd-api             = "prod_1.0.1_7c7236c"
    digital-mailbox-api = "prod_1.0.1_7c7236c"

    # JUD-74: SQS worker. Seed the live release tag (image already in ECR).
    message-handler = "prod_1.0.1_7c7236c"

    # JUD-73: scheduled ECS task (run-once cron). Seed the live release tag
    # (image already in ECR) so a run — once the schedule is enabled — uses the
    # right image rather than a bootstrap placeholder.
    scheduler = "prod_1.0.1_7c7236c"
  }

  judicial_web_image_tag             = aws_ssm_parameter.image_tag["web"].insecure_value
  judicial_api_image_tag             = aws_ssm_parameter.image_tag["api"].insecure_value
  judicial_backend_image_tag         = aws_ssm_parameter.image_tag["backend"].insecure_value
  judicial_message_handler_image_tag = aws_ssm_parameter.image_tag["message-handler"].insecure_value
  judicial_scheduler_image_tag       = aws_ssm_parameter.image_tag["scheduler"].insecure_value
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
