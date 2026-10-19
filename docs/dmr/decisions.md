# Decisions

## 2026-10-19 — Retire the DSL for deploys
Task definitions become ECS-native JSON in this repo (`deploy/ecs/<service>/taskdef.dev.json`), seeded once from `apps/judicial-system/*/infra/*.ts`. Matches the apro-accelerator pattern (`aproorg/terraform-modules//modules/ecs_service` + app-repo `taskdef.json`). The DSL files stay until the seed is verified, then get deleted with `infra/` in the deep prune.

## 2026-10-19 — No copy of the island.is API gateway (`apps/api`)
Judicial never calls `apps/api` at runtime. `judicial-system-web` → `judicial-system-api` (its own GraphQL gateway) → `judicial-system-backend`. Translations are served by `judicial-system-api` itself: it mounts `CmsTranslationsModule` (`libs/cms-translations` → `libs/cms` ContentfulRepository → Contentful, using `CONTENTFUL_ACCESS_TOKEN`).
The only link to `apps/api` is at compile time: `web/pages/_app.tsx` imports `Query`/`QueryGetTranslationsArgs` types from `@island.is/api/schema`, which is generated from `apps/api/src/api.graphql`.
Plan: replace those two types with local types (or types generated from judicial-system-api's own schema) before deleting `apps/api`. Do not extract or copy the gateway.
External runtime dependencies that stay island.is-owned: IDS login (`innskra.island.is`), X-Road, Contentful.
