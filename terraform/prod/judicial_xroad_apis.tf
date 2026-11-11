# judicial-system-xrd-api + judicial-system-digital-mailbox-api (ECS/Fargate), PROD.
#
# Prod copy of terraform/dev/judicial_xroad_apis.tf (JUD-11) for JUD-75.
#
# Source: island.is apps/judicial-system/{xrd-api,digital-mailbox-api}/infra/*.ts
# Both are internal HTTP APIs that OTHER X-Road members call through a security
# server: xrd-api by police and courts, digital-mailbox-api by the island.is
# mailbox. On island.is they sat behind the internal nginx ingress.
#
# Here they run with no ALB: APRÓ ecs_service_worker + a CloudMap name
# (judicial-system-<svc>.dmr.local:3333). The DMR prod security server reaches
# them over the TGW; each service SG allows only the prod X-Road VPC private
# subnets on 3333 (the shared services SG stays closed to the X-Road VPC).
#
# Network path (prod-todo.md section 1): the judicial prod VPC
# (vpc-08e6c4b171676f656, 10.74.144.0/20) and the prod X-Road VPC
# (vpc-04ec1e947af96200b, 10.68.0.0/22, account 148850346625) are attached to
# the shared TGW (account 405032865706); the SS->our-APIs direction is live
# (judicial prod CIDR is propagated into the xroad_prod TGW route table). The
# CloudMap namespace already authorizes the prod X-Road VPC (JUD-61).

locals {
  # Private subnets of the DMR prod X-Road VPC (vpc-04ec1e947af96200b, account
  # 148850346625), where the security server ECS tasks run. Derived from the
  # X-Road prod network: infrastructure/xroad/config/prod.yml network_cidr
  # 10.68.0.0/22 + _envcommon/network.hcl private_subnets =
  # cidrsubnet(cidr, 4, 0..2) (num_azs = 3). Same first-three-/26 layout as dev
  # (10.67.0.0/26, .64, .128). These are the ranges routed to the TGW.
  xroad_ss_private_cidrs = {
    euw1a = "10.68.0.0/26"
    euw1b = "10.68.0.64/26"
    euw1c = "10.68.0.128/26"
  }

  judicial_xroad_apis = {
    xrd-api = {
      service_name = "judicial-system-xrd-api"
      image_tag    = aws_ssm_parameter.image_tag["xrd-api"].insecure_value
      extra_env    = {}
      # xrd-api posts failed calls to this URL (env.required, no default).
      extra_parameters = {
        ERROR_EVENT_URL = module.infra_outputs.parameter_names["backend/ERROR_EVENT_URL"]
      }
    }
    digital-mailbox-api = {
      service_name = "judicial-system-digital-mailbox-api"
      image_tag    = aws_ssm_parameter.image_tag["digital-mailbox-api"].insecure_value
      # Validates island.is IDS tokens from the mailbox. Prod island.is IDS
      # (innskra.island.is), same issuer the prod api uses (judicial_api.tf).
      # prod-todo.md section 3: confirm DMR stays on island.is IDS before go-live.
      extra_env = {
        IDENTITY_SERVER_ISSUER_URL = "https://innskra.island.is"
      }
      extra_parameters = {}
    }
  }
}

module "judicial_xroad_api" {
  # module source must be a string literal — keep the version in sync with the other services.
  source   = "s3::https://apro-terraform-modules.s3.eu-west-1.amazonaws.com/v3.26.1/ecs_service_worker.zip"
  for_each = local.judicial_xroad_apis

  service_name = each.value.service_name
  env          = local.env

  cluster_name         = module.infra_outputs.ecs_cluster_name
  subnet_ids           = module.infra_outputs.private_subnets
  security_group_ids   = [module.infra_outputs.services_shared_sg_id]
  service_discovery_id = module.infra_outputs.ecs_namespace_id

  # Only the DMR prod security server may call these, over the TGW. The rules
  # go on each service's OWN SG (made by the module), not the shared one, so
  # backend/api stay closed to the X-Road VPC.
  security_group_ingress_rules = {
    for k, cidr in local.xroad_ss_private_cidrs : "xroad-ss-${k}" => {
      cidr_ipv4   = cidr
      from_port   = 3333
      to_port     = 3333
      description = "DMR prod X-Road security server (${k}) to ${each.value.service_name}"
    }
  }

  container_image  = "${local.shared_ecr_registry}/${each.value.service_name}:${each.value.image_tag}"
  cpu_architecture = "X86_64"
  container_cpu    = 256
  container_memory = 512

  desired_count      = 1
  enable_autoscaling = false

  # No ALB, so the container checks itself. Image has node but no curl.
  container_health_check = {
    command = [
      "CMD-SHELL",
      "node -e \"fetch('http://localhost:3333/liveness').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\"",
    ]
    startPeriod = 60
  }

  dd_enabled      = true
  dd_service_name = each.value.service_name
  dd_tags = {
    service = each.value.service_name
    version = split("_", each.value.image_tag)[1]
  }

  environment_variables = merge({
    # Shared services SG only opens 3333.
    PORT         = "3333"
    NODE_OPTIONS = "--max-old-space-size=384"
    LOG_LEVEL    = "info"

    DD_ENV     = local.env
    DD_SERVICE = each.value.service_name
    DD_VERSION = split("_", each.value.image_tag)[1]

    BACKEND_URL                    = local.backend_internal_url
    AUDIT_TRAIL_USE_GENERIC_LOGGER = "false"
    AUDIT_TRAIL_GROUP_NAME         = local.audit_log_group_name
    AUDIT_TRAIL_REGION             = local.aws_region
  }, each.value.extra_env)

  # All app secrets come from SSM Parameter Store (judicial_ssm_secrets); prod
  # has no Secrets Manager app-secret unit. The app reads them by env-var name;
  # the worker module auto-grants the exec role ssm:GetParameters on these ARNs.
  #
  # Only BACKEND_ACCESS_TOKEN is wired (matches dev and the island.is infra DSL
  # for both services). The ticket also lists AUTH_JWT_SECRET, but neither
  # app reads it (apps/judicial-system/{xrd-api,digital-mailbox-api}/infra/*.ts
  # declare no AUTH_JWT_SECRET; no jwtSecret reference in their source) — these
  # are X-Road-facing APIs, not IDS/JWT session auth. Omitted to match what the
  # container actually consumes. LAWYERS_ICELAND_API_KEY is likewise skipped
  # (ticket note: appears in island.is infra but is never read; the backend
  # owns that call).
  parameter_store_secret_names = merge({
    BACKEND_ACCESS_TOKEN = module.infra_outputs.parameter_names["shared/BACKEND_ACCESS_TOKEN"]
  }, each.value.extra_parameters)
}

# ecs_service_worker has no tasks_iam_role_statements input; attach to its role.
data "aws_iam_policy_document" "judicial_xroad_api_audit" {
  statement {
    sid       = local.audit_log_task_statement.sid
    effect    = local.audit_log_task_statement.effect
    actions   = local.audit_log_task_statement.actions
    resources = local.audit_log_task_statement.resources
  }
}

resource "aws_iam_role_policy" "judicial_xroad_api_audit" {
  for_each = module.judicial_xroad_api

  name   = "audit-log"
  role   = each.value.tasks_iam_role_name
  policy = data.aws_iam_policy_document.judicial_xroad_api_audit.json
}
