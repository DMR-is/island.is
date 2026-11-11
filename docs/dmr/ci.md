# DMR CI (GitHub-hosted runners)

The island.is workflows (ARC self-hosted runners, Helm, Nx Cloud, S3 buildkit
cache) were removed. Kept from island.is: `scripts/ci/Dockerfile` (driven by
`scripts/dmr/docker-build.sh`) and `scripts/ci/generate-files.mjs` (codegen +
tarball, used by `.github/actions/load-deps`).

## ci.yml

Same shape as island.is `push.yml`: one `prepare` job, then matrix legs.

```
prepare ─┬─ lint   (matrix: 7 services + system-e2e)
         ├─ test   (matrix: 7 services)
         ├─ build  (matrix: 7 services)
         └─ docker (matrix: web, api, backend)   push / dispatch only
                     └─ deploy (single job)      main / dispatch with deploy=true
```

- `prepare` installs and runs codegen once. node_modules is cached on
  `yarn.lock`; generated files are cached per commit (`generated-files-<sha>`).
  Every leg restores both, so codegen never runs twice for a commit.
- `docker` builds inside Docker, so it only restores the generated files.
- `deploy` is one job: all services share one Terraform state. It writes the
  new tag to SSM `/judicial-system/dev/<svc>/image-tag`, then `terraform apply`.
  Terraform reads the tag from SSM (`terraform/dev/image_tags.tf`), so a manual
  apply never rolls a service back. Runs in the GitHub `dev` environment — add
  required reviewers there to gate it.
- Service list comes from `scripts/dmr/docker-build-matrix.json`.

## deploy.yml

Reusable deploy (`workflow_call`), used by dev and prod. Writes the tag to SSM
`/judicial-system/<env>/<svc>/image-tag`, then applies `terraform/<env>`.
Runs in the GitHub environment of the same name.

## Prod releases

`release.yml`, manual (Actions -> Release -> Run workflow, on `main`):

1. Checks CI passed on `main` for this commit.
2. Next version from conventional commits since the last `judicial-v*` tag
   (git-cliff, `scripts/dmr/cliff.toml`): `feat` -> minor, `fix` -> patch,
   `!` / `BREAKING CHANGE` -> major. Input `version` forces one.
3. Retags this commit's dev images `prod_<version>_<sha7>`. No rebuild.
4. Creates GitHub release `judicial-v<version>` with the notes.
5. Deploys prod via `deploy.yml`. Waits for approval on the `prod` environment.

Notes list only PR titles (`... (#123)`) of type feat/fix/perf/refactor/revert.
Preview locally: `git-cliff -c scripts/dmr/cliff.toml --unreleased --bumped-version`.

`deploy-prod.yml`: redeploy or roll back prod to an existing release version.
Only images roll back; terraform comes from `main`.

Tag prefix `judicial-v` keeps clear of upstream tags (`v99.0.0`, `judicial-system-release-*`).

## terraform.yml

PR / push touching `terraform/`: fmt, validate, plan `terraform/dev` (no apply).

## AWS roles (OIDC, `DMR-is/island.is` only)

- ECR push: `arn:aws:iam::592944621100:role/shared-github-ci-role` (infra repo, `DMR-shared/_envcommon/github_oidc.hcl`)
- Judicial dev: `arn:aws:iam::640538430394:role/dev-judicial-system-github-ci-role` (`terraform/dev/github_oidc.tf`)
- Judicial prod: `arn:aws:iam::141145165006:role/prod-judicial-system-github-ci-role` (`terraform/prod/github_oidc.tf`, not built yet)

Terraform version is pinned in `terraform/.terraform-version` (tenv reads it too).

Not in CI yet: e2e, images for the 4 services with no ECR repo.
