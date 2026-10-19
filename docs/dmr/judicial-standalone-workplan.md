# Judicial standalone repo — workplan

Branch: `chore/judicial-prune` (off `origin/main` + fast-forwarded to `upstream/main` @ `3811f5a58a`).
Target: dev only — build/push to ECR `592944621100`, deploy to ECS in judicial dev `640538430394`.

## Current state (as found)

- 22 apps; judicial = `apps/judicial-system/{web,api,backend,digital-mailbox-api,message-handler,scheduler,xrd-api}`. 50 libs; judicial libs = `libs/judicial-system/{audit-trail,auth,consts,court-client,formatters,message,types}`.
- Builds: Nx. `web` = `@nx/next:build` + `build-custom-server` (webpack); other 6 = `@nx/esbuild`. Docker target markers: `docker-next` (web), `docker-express-yarn` (the rest).
- Images: one shared multi-stage `scripts/ci/Dockerfile` (`ARG APP / APP_HOME / APP_DIST_HOME`), driven by `scripts/ci/90_docker-*.sh` + `_docker.sh`. Deps stage copies `apps/native/app/package.json` (root `workspaces: ["apps/native/*"]`).
- Deploy today: DSL per service in `apps/judicial-system/*/infra/*.ts` → aggregated in `infra/src/uber-charts/judicial-system.ts` → rendered to `charts/judicial-system*/values.*.yaml` → `merge-queue.yml` ("Update helm-values repository with judicial system DEV/PROD") → ArgoCD → EKS.
- DSL carries the real env/secret contract: env per env, secrets as SSM paths (`/k8s/judicial-system/*`), `.xroad(...)`, `.db(...)`, liveness/readiness, ingress, service refs (`ref(h => h.svc(...))`).

## Cross-boundary dependencies (prune risks)

Non-judicial `@island.is/*` imports used by judicial (top): `logging`, `island-ui/core|theme`, `nest/config`, `email-service`, `cms-translations`, `nova-sms`, `localization`, `infra-nest-server`, `dokobit-signing`, `nest/problem|sequelize`, `auth-nest-tools`, `infra-tracing`, `cache`, `auth/scopes`, `api/schema`. All are in `libs/` → safe under a light prune.

Blockers found:
1. `@island.is/api/schema` (used by `web/pages/_app.tsx` for `getTranslations` types) is codegen'd from **`apps/api/src/api.graphql`**. This is a compile-time link only: at runtime `getTranslations` is served by `judicial-system-api` (`CmsTranslationsModule` → Contentful). Fix: replace the 2 types locally, then delete `apps/api` (see `decisions.md`). Do not copy the gateway.
2. `tsconfig.base.json` paths point into deleted apps (`@island.is/web/*`, `air-discount-scheme-web`, `consultation-portal`, `financial-aid-web/*`, `skilavottord-web`). Remove; any lib importing them breaks lint/typecheck (not the judicial build unless in closure).
3. `scripts/ci/Dockerfile` copies `apps/native/app/package.json`; root `workspaces` = `apps/native/*` → remove both together, regenerate `yarn.lock`.
4. Workflows (`merge-queue`, `pullrequest`, `push`, `install`, `e2e`, …) assume the full monorepo, helm-values repo and island.is runners/secrets — will not work in DMR org; replace, don't patch.
5. Infra values are island.is-specific (Redis cluster endpoints, S3 bucket names `island-is-*-upload-judicial-system`, SQS names, audit log group `k8s/judicial-system/audit-log`, SSM `/k8s/...`). Must be remapped to the DMR dev contract (env-secret-matrix, JM-36 doc — not in this checkout; need from `clients/DMR/docs`).

## Phases

### P0 — Baseline (local, now)
- [ ] Record a pre-prune baseline: `yarn install`, `nx run-many -t build -p <7 judicial projects>`, judicial tests. Save timings + failures to `docs/dmr/phase-evidence.md`.
- [ ] `nx graph --file` for the 7 projects → exact lib/app closure; confirm nothing beyond `apps/api` (schema) is needed from other apps.

### P1 — Light prune (story)
- [ ] Delete the 21 non-judicial `apps/*` (keep `apps/judicial-system`; decide on `apps/tools` / `github-actions-cache` / `system-e2e` after graph check).
- [ ] Fix blockers 1–3 above; drop `charts/` for non-judicial (`islandis*`, `identity-server*`) and their uber-charts.
- [ ] Remove root `workspaces`, react-native-only deps can stay for now (deep prune later); `yarn install` → new lockfile.
- [ ] Gate: all 7 `build` targets green, judicial `test`/`lint` green vs. P0 baseline. Commit.

### P2 — Images (story)
- [ ] Slim per-service build: keep the shared multi-stage Dockerfile (proven) but move to `apps/judicial-system/Dockerfile` (or keep in `scripts/ci`) with `next` and `express-yarn` final stages only.
- [ ] Local `docker build` for all 7; smoke-run web/api/backend with liveness endpoints.
- [ ] Confirm image tags/naming match what JM-32 mirrored to ECR (so M1 services keep the same repos).

### P3 — Task-def source — DECIDED: retire DSL (see `decisions.md`)
Remaining work: a one-off seed script DSL → `deploy/ecs/<service>/taskdef.dev.json`, following the apro-accelerator `taskdef.json` convention. The options below are kept for the record.
Options:
- A. **ECS renderer on the DSL** — new output-generator next to the helm one in `infra/src/dsl/output-generators`: env → `environment`, secrets → `secrets[].valueFrom` (SSM/Secrets Manager ARNs), liveness → `healthCheck`/target group path, resources → cpu/memory. Keeps one source of truth; costs: keeping the k8s-shaped DSL (`ref(h.svc)`, xroad, ingress, initContainers → no clean ECS mapping).
- B. **Retire DSL** — hand-maintained `deploy/ecs/<service>/taskdef.dev.json` (or a tiny TS/jsonnet template), seeded once by a one-off script that reads the DSL. Simple, ECS-native, what `amazon-ecs-render-task-definition` expects.
- Recommendation going in: **B**, seeded from the DSL. The DSL's value is k8s plumbing we're leaving; ECS task defs are already a declarative format. Spike output = decision record in `docs/dmr/decisions.md`.
- Migrations: backend `.db()` today runs via initContainer → need an ECS one-off task (`run-task` with `migrate` target) in the pipeline before the service roll.

### P4 — Infra/app seam (story, needs infra repo)
- [ ] App repo owns: task definition + `aws_ecs_service` (deploy-time: image, desired count, task-def revision).
- [ ] Infra keeps: cluster, ALB/listeners/TGs, SGs, task + exec IAM roles, secret containers, log groups, ECR, OIDC deploy role for GitHub.
- [ ] Handover: infra exposes outputs (TG ARNs, role ARNs, subnets, SGs, cluster name) via SSM params the pipeline reads; remove `_envcommon/judicial_*.hcl` task-def resources (`terraform state rm`/`removed {}` — no destroy of running services). Requires infra-repo PR + plan review.
- Open: does the app repo create the service (`aws ecs create-service` / CDK / small TF in this repo) or does infra create it with `ignore_changes = [task_definition]`? Pragmatic answer: infra creates the service with `ignore_changes`, app repo owns task defs + rolls. Revisit after spike.

### P5 — GitHub Actions pipeline (story, blocked on DMR org access)
- [ ] `.github/workflows/judicial-deploy.yml`: on push to main / manual dispatch per service → OIDC assume deploy role → `nx affected` (or matrix of 7) → build + push to `592944621100` → render task def (`aws-actions/amazon-ecs-render-task-definition`) → (backend: run migration task) → `amazon-ecs-deploy-task-definition` with `wait-for-service-stability`.
- [ ] PR workflow: install + lint/test/build judicial only.
- [ ] Delete inherited island.is workflows.
- Local substitute until access: `act` dry-runs + a `scripts/dmr/deploy.sh` doing the same steps with a local profile (read-only `describe-*` only until approved).

### P6 — Runbook + cutover (story)
- [ ] `docs/dmr/runbook.md`: build locally, deploy a service to dev, rollback (previous task-def revision), run migrations, add an env var/secret.
- [ ] Cutover web/api/backend (M1) from infra-managed task defs to repo-managed; other 4 services build + task defs land but stay `desiredCount=0` / undeployed.

## Needs from outside this repo
- DMR org access (GitHub repo settings, Actions OIDC role, ECR push).
- env-secret-matrix: not needed yet (comes in at P3 seeding). JM-36 doc: not available.
- Infrastructure Terragrunt repo (`_envcommon/judicial_*.hcl`) for P4.
- Infra reference: `/Users/snojo/Andes/Apro/apro-accelerator` (`aproorg/terraform-modules` `ecs_service`, `_envcommon/ecs_deployment_pipeline.hcl`) stands in for the DMR Terragrunt repo, which we can't access.
