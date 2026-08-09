# Production Release Runbook

This runbook governs releases of the React/Vite, FastAPI, worker, MariaDB, and
Nginx stack. A release is atomic: one immutable source SHA supplies every
application image, one Alembic job runs before application services, and
traffic moves to that tested stack once.

The 5.0 big-bang cutover it was originally written for is done: `5.0.0`
shipped on 2026-07-19 and `5.1.0` on 2026-08-06 (`CHANGELOG.md`). Everything in
the body of this runbook is the normal release path. The cutover-only material
is retained verbatim in the final section, "Appendix: the first 5.0 cutover",
because `.github/workflows/rollback.yml` still accepts its `first-5.0-cutover`
kind; it is history, not a step you perform.

Recovery for a normal release means the previous React/FastAPI digests, a
forward fix, or a matching verified database restore — never the pre-cutover
legacy images.

Platforms release on independent tracks. This runbook covers the web stack;
`docs/runbooks/ios-release.md` covers the iOS app. The Android app has no
release automation at all: `android/` appears in `.github/workflows/` only as
the PR-gate `android` job, so there is no publishing, signing, or store-upload
workflow to run for it yet.

## Ownership and release record

Assign named people before the window. One person may hold more than one role,
but every role needs a primary and a backup.

| Role | Responsibility |
|---|---|
| Release commander | Owns go/abort decisions and the release timeline |
| Database operator | Owns backup, restore rehearsal, migration, and revision checks |
| Runtime operator | Owns image verification, automated rollout, health, and rollback |
| Application verifier | Runs smoke tests and checks critical user workflows |
| Incident lead | Owns alerts, communications, and recovery coordination |

Create a release record containing the UTC window, owners, immutable Git SHA,
API/worker/frontend image references and digests, previous production SHA and
digests, expected Alembic revision, backup identifier, restore-rehearsal result,
migration duration, rollout timestamps, smoke result, and final decision.

## Preflight

Complete every item before announcing the maintenance window:

1. Confirm the protected release gate passed for the exact release SHA: backend
   and frontend tests, 100% coverage, lint, OpenAPI freshness, production
   Compose validation, backend dependency, secret, and configuration scans,
   image builds, the real-stack smoke/E2E suite, and the populated production
   migration rehearsal from `55dc25bae00d` to the repository's single Alembic
   head.

   `scripts/ci-changed-areas.sh` path filtering applies **only on a pull
   request**. The `changes` job in `.github/workflows/test-pr.yaml` runs the
   classifier under `if [ "$EVENT_NAME" = "pull_request" ]` and otherwise
   hardcodes `backend=true frontend=true docker=true scripts=true`. A gate
   invoked through `workflow_call` — which is how both `deploy.yml` and
   `release.yml` run it — therefore executes those four areas in full, as does
   a `workflow_dispatch` or a direct push. The reason is in the job's own
   comment: interleaved merges mean an area verified at PR time can be stale by
   the time the deploy-path gate runs. Do not expect skipped `backend`,
   `frontend`, `docker`, or `scripts` jobs on a release run; a skip there means
   something is wrong, not that the area was untouched.

   The two mobile jobs are the one legitimate exception. `ios` (macOS,
   `RentivoCore` plus the Xcode-hosted `RentivoTests`) and `android` (Ubuntu,
   `assembleDebug`, `testDebugUnitTest`, `lintDebug`, and the OpenAPI copy
   check) are both blockers in the `release-gate` job's `needs` list, but their
   filters — `scripts/ios-ci.sh paths-changed` and
   `scripts/android-ci.sh paths-changed` — are computed unconditionally, for
   every event, against `github.event.before`. On a `deploy.yml` run that base
   is the real previous tip of `main`, so a deployment whose commits touched
   neither `ios/` nor `android/` (nor `frontend/openapi.json`, which the
   Android filter also watches) will legitimately show both jobs skipped, and
   `release-gate` counts a skip as passing. Confirm the skip matches the diff
   rather than assuming it. On a `release.yml` tag run the base is unusable
   (all zeros for a new tag), and both helpers deliberately report `true` in
   that case, so both mobile jobs run in full on every tag.

   Production images are built and published without a blocking vulnerability
   scan, and frontend dependency auditing is not part of the gate either; see
   [Weekly image vulnerability scan](#weekly-image-vulnerability-scan) and
   [Weekly npm audit report](#weekly-npm-audit-report) for the scheduled
   workflows that cover them instead.
2. Confirm the release SHA is the commit being deployed. Do not rebuild from a
   moving branch or retag an image after the gate.
3. Validate production configuration with secret-managed files:

   ```bash
   make stack-config \
     RENTIVO_DB_ENV_FILE=/etc/rentivo/db.env \
     RENTIVO_APP_ENV_FILE=/etc/rentivo/app.env
   ```

4. Confirm the canonical HTTPS origin, WebAuthn RP ID, secure `__Host-`
   cookies, SES, S3, KMS, structured JSON logging, TLS terminator CIDR, and
   database credentials are production values. Production startup fails closed
   when these requirements are not met.
5. Record the expected migration head:

   ```bash
   uv run --project backend alembic -c backend/alembic.ini heads
   # Record the single head reported for the release SHA; the deploy job
   # derives the expected revision from the same command, so there is no
   # pinned value to bump.
   ```

6. Verify free database capacity, application host capacity, certificate
   validity, DNS/load-balancer control, and access to logs, traces, and database
   consoles. The protected automation performs the authoritative production
   configuration check and real KMS, S3, SES, and job backend reachability
   checks before migration; a failure aborts without changing the schema.
7. Confirm support is ready for the one-time forced login. Existing browser
   sessions are intentionally invalidated by this release.

## Backup and restore rehearsal

The database operator must create a transactionally consistent backup after
write traffic is stopped and record its identifier, checksum, start/end time,
and retention location. A backup is not considered verified until a restore
rehearsal succeeds in an isolated MariaDB instance.

The rehearsal must verify:

- MariaDB accepts the restored data and `alembic current` reports the backed-up
  revision.
- Critical row counts match the source for users, organizations, memberships,
  API keys, billings, bills, receipts, jobs, and audit logs.
- Foreign keys and indexes are present and sampled encrypted fields decrypt
  through the application with the production KMS key.
- A restored user can authenticate in the isolated stack and retrieve an
  existing invoice.
- Measured restore time fits the approved recovery-time objective and the
  backup timestamp fits the recovery-point objective.

Record the rehearsal evidence and the exact restore procedure in the release
record. Abort before migration if either objective is missed.

## Enter maintenance and drain work

1. Put the external TLS terminator/load balancer into maintenance mode. Reject
   browser and API mutations; leave operator health access available. Confirm a
   synthetic write is blocked before continuing.
2. Stop scheduled producers and integrations that can enqueue work.
3. For the default database driver, monitor `jobs` until `running` reaches zero
   and all due `pending` work has completed. Record pending, running, failed,
   oldest-pending age, and in-flight job types. Then stop the worker:

   ```bash
   RENTIVO_APP_ENV_FILE=/etc/rentivo/app.env \
     docker compose --env-file /etc/rentivo/db.env stop worker --timeout 120
   ```

   The worker does handle `SIGTERM`: `Worker.run_forever` in
   `backend/rentivo/jobs/worker.py` installs a handler that only sets a
   `_stopping` flag, so the current `tick()` finishes its whole claimed batch,
   the loop exits, and the process logs `worker_stopped`. It does not abandon a
   job it has already started.

   The risk is the stop timeout, not the signal. `docker compose stop` sends
   `SIGTERM` and then `SIGKILL` after 10 seconds by default, and the `worker`
   service in `docker-compose.yml` declares no `stop_grace_period`. A batch
   still running a slow job — PDF generation, an S3 upload, an SES send — is
   killed mid-flight, and its `jobs` row stays `running` with `claimed_at` set
   until another worker reclaims it after
   `RENTIVO_JOB_WORKER_STUCK_AFTER_SECONDS` (default 600). Pass a `--timeout`
   comfortably longer than the slowest job so the batch can finish, and still
   prefer stopping only once `running` is zero. Stopping while `running` is
   nonzero means accepting that reclaim delay and a possible re-run of a
   partially applied job; that call belongs to the release commander.
4. For Temporal, wait for running workflows on `rentivo-jobs` to complete, stop
   producers, then stop the worker. Record outstanding workflow IDs.
5. Create the verified cutover backup and recheck that no writes occurred after
   its consistency point.

Abort if maintenance cannot block writes, work cannot drain inside the approved
window, a non-idempotent side effect is uncertain, or the backup cannot be
verified.

## Pin immutable artifacts

Set `RELEASE_SHA` to the complete tested commit. Resolve and record the registry
digest for every application image; tags alone are insufficient.

```bash
export RELEASE_SHA=<40-character-tested-sha>
docker buildx imagetools inspect "${REGISTRY}/api:${RELEASE_SHA}"
docker buildx imagetools inspect "${REGISTRY}/worker:${RELEASE_SHA}"
docker buildx imagetools inspect "${REGISTRY}/frontend:${RELEASE_SHA}"
```

Verify the deployment manifest resolves to those exact digests. The API and
migration use the same API artifact. Do not continue if an image is mutable,
missing, built from another SHA, or was not produced by the complete gate.
The workflow tests these exact images; they are never rebuilt after
verification. Image vulnerability scanning is not part of this path — it runs
on the weekly schedule described below.

## Weekly image vulnerability scan

`.github/workflows/image-vulnerability-scan.yml` runs every Monday at 06:00 UTC
and can also be started manually with `workflow_dispatch`. It rebuilds the API,
worker, and frontend production images, scans each one with Trivy for fixed
HIGH and CRITICAL vulnerabilities, and maintains a single open issue titled
`Weekly image vulnerability report` carrying the `image-vulnerability-report`
label. The scan never blocks a build: when findings exist the issue is created
or refreshed with the full table per image, and when a run finds nothing the
issue is closed.

Review that issue before a release. Findings are not an automatic release
blocker, but a CRITICAL finding reachable from production traffic should be
patched — usually by bumping the base image in the affected Dockerfile — before
the rollout rather than after.

## Weekly npm audit report

`.github/workflows/npm-audit-report.yml` runs every Monday at 06:00 UTC and can
also be started manually with `workflow_dispatch`. It audits
`frontend/package-lock.json` and maintains a single open issue titled
`Weekly npm audit report` carrying the `npm-audit-report` label. It reports
every HIGH and CRITICAL finding, including the ones with no fix available, and
never blocks a build: when findings exist the issue is created or refreshed
with the full table, and when a run finds nothing the issue is closed.

Review that issue before a release. Findings are not an automatic release
blocker, but a CRITICAL finding in a dependency that reaches the browser bundle
should be patched — usually by bumping the affected package in
`frontend/package-lock.json` — before the rollout rather than after.

## Migrate and roll out exactly once

`.github/workflows/deploy.yml` ("Deploy Tested Production SHA") is the
canonical production entrypoint, and it is **not** operator-dispatched. Its
only trigger is `push: branches: [main]`, so every merge to `main` starts a
deployment run; the `rentivo-production` concurrency group with
`cancel-in-progress: false` queues runs rather than cancelling them. There is
no "trigger it once" step to perform.

The operator's go/no-go control is the approval gate, not the trigger. The run
proceeds unattended through four jobs and then stops:

1. `gate` — calls `test-pr.yaml` through `workflow_call` (the full gate, with
   PR-only path filtering disabled as described in Preflight).
2. `publish-images` — builds and pushes the API, worker, and frontend images
   tagged with the commit SHA and attests each digest's provenance.
3. `resolve-images` — re-resolves each tag to a digest, requires it to equal
   the published digest, verifies the `org.opencontainers.image.revision` and
   `.source` labels, and runs `gh attestation verify` against
   `deploy.yml` as the expected signer workflow.
4. `verify-images` — boots a production-shaped Compose stack from those exact
   digests and runs `scripts/smoke-production-stack.sh` plus the
   `production-stack` Playwright project against it. Nothing is rebuilt.

The fifth job, `deploy`, declares `environment: production`. The run pauses
there awaiting that environment's approval, and approving it is the release
commander's go decision. Only after approval does `deploy` resolve the expected
Alembic revision with `alembic heads` and POST the deployment request.

The request must complete these ordered stages: `configuration`,
`production_integrations`, `migration`, `rollout`, and `smoke`. Configuration
validation and real KMS, S3, SES, and job backend reachability must succeed
before migration. The receiver then runs one `migrate` job, waits for success,
starts `api`, `worker`, `frontend`, and `proxy`, and reports all five stages as
one result. It must deploy image references by recorded digest, never rebuild
or resolve mutable tags.

There is no supported direct/manual production rollout. The repository Compose
services contain local `build:` definitions and therefore cannot consume the
recorded registry digests as a production deployment contract. Local stack
targets, Docker builds, ad hoc Compose overrides, and host-side migration
commands must not be used for production. If protected automation cannot accept
and report the complete-gate-tested SHA and digest references, abort the release
until that contract is available.

The `rentivo.deploy.v2` request includes the expected Alembic revision, which
the deploy job resolves from the release SHA with `alembic heads` (the
repository's single head). Its response must echo the tested SHA and exact
image digests,
report one deployment, and return the exact ordered stage list. Every stage
must include UTC start/end timestamps. Migration evidence must include exit
code zero, a content-addressed log checksum, and the current Alembic revision;
that revision must equal the expected head before traffic is enabled.

## Health, alerts, and smoke

Keep maintenance mode active while validating:

```bash
curl --fail --silent --show-error https://rentivo.example.com/health
curl --fail --silent --show-error https://rentivo.example.com/api/v1/ready
./scripts/smoke-production-stack.sh https://rentivo.example.com
```

Confirm `/health` is JSON liveness, `/api/v1/ready` is dependency-aware JSON
readiness, `/` serves the React landing page, crawler endpoints have their
declared media types, and request responses include `X-Request-ID`. The shell
smoke covers signup, password login, protected-session behavior, logout, and
server-side token revocation. Use the gated production-stack Playwright project
for fresh-account empty states, billing/invoice work, worker-produced output,
and organization-grant denial. Delete or disable smoke data afterward.

For the first 15 minutes, abort or re-enter maintenance immediately on any of:

- readiness fails twice consecutively or for more than 60 seconds;
- any migration error, unexpected revision, integrity error, or data-loss
  signal;
- sustained 5xx rate above 1% for 5 minutes, or any burst above 5% for 1 minute;
- p95 API latency more than twice the pre-release baseline for 5 minutes;
- authentication, MFA, billing, invoice download, or logout smoke failure;
- the worker is not visibly progressing — see below — or a `running` job is
  older than `RENTIVO_JOB_WORKER_STUCK_AFTER_SECONDS`, failed jobs are growing,
  or queue age exceeds 5 minutes;
- elevated frontend runtime errors, KMS/SES/S3 failures, or a security control
  failing closed for valid production traffic.

The worker publishes no heartbeat and the `worker` service in
`docker-compose.yml` declares no `healthcheck`, so there is no liveness signal
to poll and no "heartbeat absent" condition to alert on. Judge it from what it
actually emits:

- its startup log line `worker_started` with its `worker_id`, and the absence
  of a later `worker_stopped`;
- `jobs` rows advancing — `claimed_at`/`claimed_by` being set on newly claimed
  work and rows leaving `running`;
- the per-job logs `job_succeeded`, `job_retry_scheduled`, and `job_failed`;
- the container still running under `docker compose ps`.

A worker that has claimed nothing is indistinguishable from an idle one when
the queue is empty, so enqueue a known job (for example by exercising a
smoke-test flow that produces one) rather than inferring health from silence.

Alert thresholds are not defined in this repository. Every numeric threshold
above is a target for the operator's external monitoring and must be configured
there; nothing in the repo evaluates them. Do not ignore an alert because
health endpoints are green. Record the decision and request IDs for every
failure.

## Enable traffic and verify

1. Remove maintenance mode once every smoke check passes.
2. Confirm real traffic reaches the new release SHA and no host runs a different
   application digest.
3. Re-run readiness and the read-only smoke checks at 5, 15, 30, and 60 minutes.
4. Watch 4xx/5xx rate, p50/p95/p99 latency, frontend errors and Web Vitals,
   worker progress (`worker_started` without a later `worker_stopped`, and
   `jobs.claimed_at`/`claimed_by` advancing — there is no heartbeat to watch),
   pending/running/failed jobs, oldest queue age, database connections/locks,
   KMS, SES, S3, CPU, memory, and disk.
5. Verify existing users receive the expected fresh-login experience, new
   accounts have empty billings/invoices/organizations/config state, API-key
   organization grants and scopes are enforced, and logout revokes the hidden
   one-day login key.
6. Close the release only after the 60-minute observation window, alert state is
   normal, smoke data is removed, support has no unexplained regression, and
   the release record is complete.

## Tag and publish the GitHub Release

Tagging is a separate, later action from deploying: `deploy.yml` runs off the
merge to `main` and never creates a tag. Publishing the release is done by
pushing an annotated `vX.Y.Z` tag at the already-deployed SHA, which triggers
`.github/workflows/release.yml` ("Release Tested Production SHA", `on: push:
tags: v*.*.*`).

Prepare two things in the commit *before* tagging, because the workflow
hard-fails on either and a failed run leaves the tag pushed:

- `CHANGELOG.md` must contain a section headed exactly `## [X.Y.Z]` for the
  tag's version. The `release` job extracts everything between that heading and
  the next `## [` (or the link-reference block) into `release-notes.md` and
  errors with `No CHANGELOG.md section found for version <X.Y.Z>` if the
  extraction is empty.
- `backend/pyproject.toml`'s `version` must equal the tag minus its leading
  `v`. A mismatch fails with `backend/pyproject.toml version (...) does not
  match tag (...)`.

The workflow runs three jobs:

1. `gate` — the full `test-pr.yaml` gate again, on the tagged SHA, via
   `workflow_call` (so, again, no PR path filtering).
2. `verify-images` — for each of `api`, `worker`, and `frontend`, resolves
   `ghcr.io/<repo>/<image>:<sha>` to a digest, pulls it, requires the
   `org.opencontainers.image.revision` label to equal the tagged SHA and
   `.source` to equal this repository, and runs `gh attestation verify` with
   `--signer-workflow .../deploy.yml --source-digest <sha>
   --deny-self-hosted-runners`. It builds nothing. Tagging a SHA whose images
   `deploy.yml` never published will fail here.
3. `release` — extracts the notes, checks the backend version, and calls
   `gh release create <tag> --notes-file release-notes.md --verify-tag`. It is
   idempotent: an existing release for the tag is left alone.

Because the tag itself is what triggers the run, a failure means fixing the
underlying commit and tagging again. Record the release URL in the release
record.

## Recovery

Choose recovery based on schema compatibility and data written since cutover.

All artifact/database rollbacks use the protected **Protected Production
Rollback** workflow in `.github/workflows/rollback.yml`. Dispatch it from the
failed release's repository Actions page and obtain the required `production`
environment approval. The workflow sends one authenticated, idempotent HTTPS
request and never builds images or resolves tags.

Every dispatch supplies `rollback_kind`, the artifact's 40-character
`target_sha`, and `expected_alembic_revision`. Image inputs must be immutable
references in their exact GHCR repositories and contain `@sha256:`. The
workflow pulls every image, verifies its OCI source and revision, and verifies
its GitHub attestation from the expected trusted workflow before contacting the
production receiver.

- `first-5.0-cutover` is historical and not a recovery path for any current
  release; it is documented in the appendix. The workflow still accepts the
  kind and still hard-requires `expected_alembic_revision` to be
  `55dc25bae00d`.
- For `new-stack`, supply `api_ref`, `worker_ref`, and `frontend_ref` from the
  same verified release. This is an image-only rollback: leave both legacy refs
  and both database backup inputs empty. The receiver must perform a
  `schema_check` and preserve all post-release database writes.
- For `new-stack-restore`, supply `api_ref`, `worker_ref`, `frontend_ref`,
  `database_backup_id`, and `database_backup_sha256` from one matching verified
  release. Leave both legacy refs empty.

The idempotency key is the SHA-256 of the full normalized rollback payload, so
changing an image, backup, revision, kind, or stage contract creates a new key.
Accept success only from a `rentivo.rollback.v1` response that echoes that key,
the rollback kind, target SHA, exact digest references, optional backup, and
expected revision. It must report one rollback and the exact mode-specific
ordered stages: `maintenance`, `drain`, `schema_check`, `rollout`, `smoke` for
`new-stack`, or `maintenance`, `drain`, `database_restore`, `rollout`, `smoke`
for either restore mode. Every stage must include exit code zero, a
content-addressed log checksum, and ordered RFC 3339 UTC timestamps parsed
numerically, including fractional seconds. Restore evidence must echo the
backup ID, checksum, and resulting revision; image-only evidence must echo the
live schema revision and must not report a database restore. Attach the
dispatch URL and response evidence to the release record.

### Redeploy the previous new-stack version

If the schema remains compatible, enter maintenance, drain the current worker,
and dispatch `new-stack` with the previously recorded React/FastAPI API, worker,
and frontend digest references. This image-only path forbids backup inputs,
checks the live Alembic revision, and must not restore or downgrade the
database. The automation redeploys those exact immutable references; never
rebuild the old SHA, retag an image, or fall back to local Compose. Run the
previous stack's readiness and smoke checks before enabling traffic.

### Forward fix

Use a forward fix when reverting artifacts would conflict with the migrated
schema or when post-release writes must be retained. The fix receives a new
immutable SHA, the complete release gate, a reviewed migration if needed, and
the same one-shot rollout procedure. Keep maintenance active until it passes.

### Restore the database

Restore only when corruption, incompatible schema changes, or unacceptable data
mutation makes artifact redeployment/forward repair unsafe. Keep maintenance
active, stop API and worker, preserve the failed database for investigation,
and dispatch `new-stack-restore` with the verified backup and matching previous
new-stack digests. Verify revision and critical row counts, then run the full
smoke suite. Record and communicate all data lost after the backup consistency
point.

## Appendix: the first 5.0 cutover (completed 2026-07-19)

**This is a historical record, not a procedure to run.** The big-bang cutover
from the pre-5.0 stack completed with the `5.0.0` release on 2026-07-19
(`CHANGELOG.md`); `5.1.0` followed on 2026-08-06. Nothing here applies to a
current release. It is retained because
`.github/workflows/rollback.yml` still declares the `first-5.0-cutover`
rollback kind and still hard-requires `expected_alembic_revision` to equal
`55dc25bae00d`, so the inputs below remain the only correct way to drive that
kind if it were ever dispatched.

### Rollback artifact and release record (historical)

The cutover had one narrowly scoped exception to the normal rollback policy:
the verified pre-cutover legacy web and worker image digests were retained
together with the verified pre-cutover database backup as a single, inseparable
rollback artifact, because the pre-cutover images must never run against the
5.0 schema.

The release record additionally carried the pre-cutover web and worker image
digests, their OCI source/revision and attestation verification, the paired
backup identifier and checksum, and the restore rehearsal. All three parts were
retained or expired together.

### Cutover migration rehearsal (historical)

The gate had to first upgrade a populated schema at revision `55dc25bae00d`
through the complete migration chain to the repository's single Alembic head.
Its before/after evidence had to preserve representative users, MFA and
passkeys, organizations and memberships, billings and billing items, bills,
receipts, expenses, and audit data; it also had to prove all billing-item UUIDs
were populated and distinct. An empty-database upgrade or a final-migration
round trip was not a populated production migration rehearsal. (The gate's
`migrations` job still runs this same populated upgrade from `55dc25bae00d`
today — see Preflight item 1.)

### Legacy rollback image preparation (historical)

Before entering the release window, the protected
`.github/workflows/prepare-legacy-rollback.yml` workflow was run with the exact
40-character pre-cutover SHA. It had to prove that SHA was an ancestor of
`main`, run the detached legacy test suite, build separate `Dockerfile` web and
`Dockerfile.worker` worker images, scan both exact images, attest both digests,
and record their immutable `legacy-web@sha256:...` and
`legacy-worker@sha256:...` references. A retry publishes a distinct traceable
tag, so only the final digest references counted as rollback evidence.

Both prepared images were pulled by digest, their OCI source/revision labels and
GitHub attestations verified, started against the isolated restored database,
and exercised with the pre-cutover web and worker smoke suite. Both digests were
recorded beside the backup as the one rollback artifact. An untested local
image, a rebuilt image, or either image paired with a different backup was not
a rollback artifact.

### First 5.0 cutover rollback procedure (historical)

This procedure applied only during the first 5.0 cutover, and only when the
release commander decided that forward recovery could not fit the approved
outage. The verified pre-cutover legacy web and worker image digests and their
paired database backup were the one rollback artifact; no part was ever to be
mixed with another version.

To dispatch it, `rollback_kind` was `first-5.0-cutover` with
`expected_alembic_revision` set to `55dc25bae00d`, supplying `legacy_web_ref`,
`legacy_worker_ref`, the `legacy_attestation_source_sha` recorded by the
preparation workflow, `database_backup_id`, and the verified
`database_backup_sha256` including its `sha256:` prefix, leaving `api_ref`,
`worker_ref`, and `frontend_ref` empty.

1. Enter maintenance mode and verify that browser, API, scheduler, and
   integration writes are blocked.
2. Stop the API and worker, drain or stop all job producers, and preserve the
   failed 5.0 database for investigation.
3. Restore the verified pre-cutover database backup to the production database;
   verify its checksum, expected pre-cutover schema revision, critical row
   counts, foreign keys, and sampled decryptions.
4. Redeploy the verified pre-cutover legacy web and worker images by digest
   through the protected runtime path with rebuild and tag resolution disabled.
   Verify both running containers report exactly the recorded digests.
5. Run the pre-cutover smoke suite against operator-only traffic, including
   authentication, billing reads/writes, invoice retrieval, and worker output.
6. Re-enable traffic only after readiness, smoke, alerts, and database checks
   pass; record the rollback timestamps and the data-loss interval from the
   restored backup consistency point.

Normal deployment access to these artifacts was to be destroyed once the 5.0
cutover was formally closed. Later releases must not use the legacy images,
even if the digests remain in retention storage.

Outside the explicitly bounded first 5.0 procedure, never route traffic to,
rebuild, or restore the pre-cutover application. It is not a supported artifact,
schema owner, or recovery target for later releases.
