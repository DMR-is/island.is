# Release flow

Dev deploys on every merge to `main`. Prod deploys only from a tagged release,
started by hand and approved in GitHub. Prod never rebuilds: it runs the exact
image dev tested.

```
merge to main ─> ci.yml ─> dev images dev_<sha7>_<rand> ─> deploy.yml (dev)
                                     │
Run "Release" ─> release.yml ─> retag prod_<ver>_<sha7> ─> GitHub release ─> approve ─> deploy.yml (prod)
```

## Dev

Workflow: `.github/workflows/ci.yml`

| Trigger                      | What runs                                            |
| ---------------------------- | ---------------------------------------------------- |
| Pull request                 | lint, test, build                                    |
| Push to `main`               | lint, test, build, docker, deploy to dev             |
| Manual (`workflow_dispatch`) | Same, pick `images`; deploys only with `deploy=true` |

1. `docker` pushes each service image to ECR as `dev_<sha7>_<rand>`.
2. `deploy` calls `deploy.yml` with `environment: dev`:
   writes the tag to SSM `/judicial-system/dev/<svc>/image-tag`,
   then `terraform apply` in `terraform/dev`.
3. The GitHub `dev` environment has no reviewers, so it runs straight away.

Terraform reads image tags from SSM, so a manual apply never rolls a service back.

## Prod release

Workflow: `.github/workflows/release.yml`

Trigger: Actions -> Release -> Run workflow, branch `main`.

| Input     | Default | Meaning                                         |
| --------- | ------- | ----------------------------------------------- |
| `version` | empty   | Force a version (`1.2.0`). Empty = from commits |
| `deploy`  | `true`  | Deploy to prod after the release                |

Steps:

1. **Guards.** Fails unless run on `main` and `ci.yml` passed for this commit.
2. **Version.** git-cliff reads conventional commits since the last
   `judicial-v*` tag:

   | Commit                       | Bump  |
   | ---------------------------- | ----- |
   | `fix:`                       | patch |
   | `feat:`                      | minor |
   | `feat!:` / `BREAKING CHANGE` | major |

   Fails if the tag already exists (nothing new to release).

3. **Release notes.** Built by git-cliff from `scripts/dmr/cliff.toml`.
   Only PR titles (`... (#123)`) of type feat, fix, perf, refactor, revert.
   `chore`, `docs`, `ci` etc. are left out. The first release (`1.0.0`) has a
   one-line note, since there is no earlier tag.
4. **Promote images.** Each dev image of this commit gets a second tag,
   `prod_<version>_<sha7>`. Same digest, no rebuild. Fails if an image is missing.
5. **GitHub release.** Tag and release `judicial-v<version>` with the notes.
6. **Deploy.** `deploy.yml` with `environment: prod`. It pauses until a
   reviewer approves.

Preview the next version and notes locally:

```bash
git fetch --tags
git-cliff -c scripts/dmr/cliff.toml --unreleased --bumped-version
git-cliff -c scripts/dmr/cliff.toml --unreleased --strip all
```

## Approval

The GitHub `prod` environment
([Settings -> Environments](https://github.com/DMR-is/island.is/settings/environments)):

- Required reviewer must click **Review deployments -> Approve** on the run.
- Only `main` may deploy to it.
- The AWS prod CI role trusts only `repo:DMR-is/island.is:environment:prod`
  (`terraform/prod/github_oidc.tf`), so no other job can reach prod.

## Redeploy or roll back

Workflow: `.github/workflows/deploy-prod.yml`

Trigger: Actions -> Deploy prod -> Run workflow, input `version` (e.g. `1.0.1`).
Finds tag `judicial-v<version>`, deploys its `prod_<version>_<sha7>` images.
Same approval as a release.

Only images roll back. Terraform always comes from `main`.

## Clean up a test release

```bash
gh release delete judicial-v<version> --cleanup-tag
aws ecr batch-delete-image --repository-name judicial-system-<svc> \
  --image-ids imageTag=prod_<version>_<sha7>
```
