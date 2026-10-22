# DMR CI (GitHub-hosted runners)

The island.is workflows (ARC self-hosted runners, Helm, Nx Cloud, S3 buildkit
cache) and their `.github/actions` + `scripts/ci/*` tooling were removed. Only
`scripts/ci/Dockerfile` stays; `scripts/dmr/docker-build.sh` drives it.

| Workflow | Trigger | Does |
|---|---|---|
| `ci.yml` | PR, push to main | install, codegen, build / lint / unit-test the 7 judicial services |
| `images.yml` | push to main (app paths), manual | build web/api/backend, push to shared ECR as `dev_<sha7>_<nonce>` |
| `terraform.yml` | PR / push touching `terraform/` | fmt, validate, plan `terraform/dev` (no apply) |

AWS roles (OIDC, `DMR-is/island.is` only):

- ECR push: `arn:aws:iam::592944621100:role/shared-github-ci-role` (infra repo, `DMR-shared/_envcommon/github_oidc.hcl`)
- Judicial dev: `arn:aws:iam::640538430394:role/dev-judicial-system-github-ci-role` (`terraform/dev/github_oidc.tf`)

Terraform version is pinned in `terraform/.terraform-version` (tenv reads it too).

Not in CI yet: deploy (setting image tags + `terraform apply`), e2e, images for
the 4 services with no ECR repo.
