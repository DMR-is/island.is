# GitHub Actions -> AWS login (OIDC) for the judicial dev account.
#
# The account had no GitHub OIDC provider. This adds it, plus one CI role that
# only DMR-is/island.is workflows can assume. The role mirrors the shared
# account's github-ci role (ReadOnlyAccess) so CI can run `terraform plan`.
# Deploy (apply) rights are added later, once the deploy workflow is settled.
#
# ECR push lives in the shared account (592944621100) and is granted there by
# the infrastructure repo's github-ci role, not by this file.

locals {
  github_org  = "DMR-is"
  github_repo = "island.is"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS trusts GitHub's OIDC CA directly; no thumbprint needed (aws >= 5.81).
}

data "aws_iam_policy_document" "github_ci_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_org}/${local.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_ci" {
  name               = "${local.env}-judicial-system-github-ci-role"
  assume_role_policy = data.aws_iam_policy_document.github_ci_trust.json
}

resource "aws_iam_role_policy_attachment" "github_ci_readonly" {
  role       = aws_iam_role.github_ci.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# `terraform plan` must lock and read the app state key in the infra state bucket.
data "aws_iam_policy_document" "github_ci_state" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.infra_state_bucket}/services/judicial-system/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.infra_state_bucket}"]
  }
}

resource "aws_iam_role_policy" "github_ci_state" {
  name   = "terraform-state"
  role   = aws_iam_role.github_ci.id
  policy = data.aws_iam_policy_document.github_ci_state.json
}
