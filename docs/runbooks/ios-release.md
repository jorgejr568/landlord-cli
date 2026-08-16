# iOS Release Runbook

The iOS app ships to App Store Connect from CI. A release is triggered by one
thing: merging any change under `ios/` to `main`. Every such push archives,
signs, uploads, and distributes a TestFlight build — the point is to get changes
in front of testers without waiting for a version bump.

`MARKETING_VERSION` is still the release train, but it no longer decides
*whether* a release happens, only what the build is labelled. Several builds
under one marketing version are normal and expected: the build number is
`github.run_number`, so each push takes the next one.

## How a release happens

1. Open a PR touching `ios/`. Bump `MARKETING_VERSION` (for example `1.2` ->
   `1.3`) when the change starts a new release train; leave it alone for a
   change that belongs to the current one. Leave `CURRENT_PROJECT_VERSION`
   alone either way — CI supplies the build number.
2. The PR runs the normal release gate. The macOS `ios` job runs only when the
   PR touches `ios/`, `.github/actions/ios-unit-tests/`, `scripts/ios-ci.sh`,
   `scripts/sync-ios-openapi.sh`, `scripts/tests/ios-ci-test.sh`,
   `.github/workflows/ios-release.yml`, or `.github/workflows/test-pr.yaml`
   itself — that last file is the repo-wide "Complete Release Gate" that
   defines the `ios` job, not an iOS-specific workflow; it's in the trigger
   list so edits to the job's own definition still get checked. The list is
   `IOS_PATH_PATTERN` in `scripts/ios-ci.sh`, and it must name every input the
   job actually runs: the composite action holding its steps and the OpenAPI
   sync script are in there for exactly that reason, and
   `scripts/tests/ios-ci-test.sh` asserts they stay — it constructs a repo with
   only `.github/actions/ios-unit-tests/action.yml` or only
   `scripts/sync-ios-openapi.sh` changed and requires `paths-changed` to answer
   `true`. Those shell tests are not a backend suite: they run in the gate's
   own `scripts` job (which is never path-filtered, precisely because it owns
   the tests for the classifiers that gate everything else) and locally under
   `make scripts-test`.
3. Merging to `main` starts `.github/workflows/ios-release.yml`. Whether it
   starts at all is decided entirely by its `on.push.paths` filter; there is no
   second gate inside the workflow. `detect` only reads `MARKETING_VERSION` out
   of `project.pbxproj` so the later jobs know what to label the build. The
   filter is `ios/**` minus three things that live under `ios/` but never reach
   the binary: `RentivoTests/`, `RentivoUITests/`, and `Rentivo/openapi.json` —
   the reference contract copy `Package.swift` excludes from its sources and
   `make ios-openapi-sync` rewrites on every backend schema change, which would
   otherwise make backend contract PRs release the app. A push that touches one
   of those *and* real app code still releases. The whole filter is narrower
   than `IOS_PATH_PATTERN` in `scripts/ios-ci.sh`, which additionally covers the
   composite action, the sync script, and the workflow files — CI inputs that
   must re-run the checks but must not burn a build number. Two jobs then run
   against the pushed commit:
   - `verify` (macOS): `./scripts/sync-ios-openapi.sh check`, then
     `swift test --package-path ios` and the Xcode-hosted `RentivoTests`
     target via the `ios-unit-tests` composite action.
   - `preflight` (Linux): asks App Store Connect whether the marketing version
     plus build number is already consumed, and fails fast if it is.
   Only if both succeed does `release` (macOS) run, and only when the workflow
   is executing on `main` (`github.ref == 'refs/heads/main'`): it archives
   **unsigned**, exports **signed**, checks the signature is
   `Apple Distribution` for team `Q87D3V95YZ`, checks the embedded
   `CFBundleShortVersionString`/`CFBundleVersion`, validates, uploads, polls
   until the build reports `state=VALID`, and then attaches it to a TestFlight
   beta group.

The upload is automatic and irreversible. A build number is consumed
permanently and an uploaded build can only be expired, never deleted. There is
no approval step between merging an `ios/` change and the upload.

Pushes are serialised by the `ios-appstore-release` concurrency group with
`cancel-in-progress: false`, so a running release always finishes. A queued one
does not: GitHub keeps a single pending run per group, so if two more `ios/`
pushes land while a release is running, the middle commit's run is cancelled
before it starts and only the newest reaches TestFlight. Merging `ios/` changes
in quick succession therefore ships the last of them, not each one.

## Tagging a marketing version

`ios-release.yml` creates no tag and no GitHub Release — it has no
`contents: write` on the `release` job and never calls `git tag` or
`gh release`. Tagging is a manual step the operator does afterwards, and the
convention in this repository is an annotated `ios/v<MARKETING_VERSION>` tag
(`ios/v1.1` and `ios/v1.2` exist, subjects `Release iOS 1.1` and
`Release iOS 1.2`). The `ios/` prefix keeps these off the `v*.*.*` pattern that
triggers `.github/workflows/release.yml` for the backend stack — the two
release trains share no version and no cadence.

Tags mark marketing versions, not builds. Most uploads are intermediate builds
of a train that is already tagged, and those get no tag of their own. Tag when
a version is what you actually shipped — the build promoted to the App Store,
or the one testers should treat as that version:

```bash
git fetch origin main
git tag -a ios/v<MARKETING_VERSION> <release-commit-sha> \
  -m "Release iOS <MARKETING_VERSION>"
git push origin ios/v<MARKETING_VERSION>
```

Tag the commit the workflow actually built for that build — not whatever `main`
has drifted to since. Pushing this tag starts nothing; it is a record.

## Triage: why a release didn't happen

Five things stop or skip a release before it uploads. Each is the pipeline
working as designed, not a bug:

- **The push didn't touch shipping `ios/` code.** The workflow's `on.push.paths`
  filter means it never starts at all — no run appears for that commit in the
  Actions list, not even a skipped one. That covers changes to
  `scripts/ios-ci.sh`, the `ios-unit-tests` composite action, or
  `ios-release.yml` itself, and changes confined to `ios/RentivoTests/`,
  `ios/RentivoUITests/`, or `ios/Rentivo/openapi.json`: all of them run the
  PR's `ios` gate job but ship nothing. Dispatch the workflow manually from
  `main` to release one of them anyway.
- **A newer `ios/` push superseded it while queued.** The run shows as
  cancelled with no jobs having started, because `ios-appstore-release` holds
  only one pending run. The newer commit releases instead, and it contains the
  superseded one — testers get the changes either way, just under one build.
- **The version/build pair was already consumed.** `preflight` runs
  `asc_builds.py check` and fails with
  `Build <version> (<build>) is already consumed: ...`. Re-running the same
  workflow run reuses its run number and fails the same way — dispatch a
  fresh run instead.
- **The run was dispatched from a ref other than `main`.** `detect`,
  `verify`, and `preflight` can all succeed, but `release` shows as skipped
  in the Actions UI because of its `github.ref == 'refs/heads/main'`
  condition.
- **`skip_upload` was checked on a manual dispatch.** This is the *default* for
  a manual run. `release` runs and succeeds through "Validate with App Store
  Connect," but its "Upload to App Store Connect" and "Wait for the build to
  reach VALID" steps show as skipped — no build reaches App Store Connect.

## Triage: the upload succeeded but the job is red

Every case above is a non-upload, where the cheap reaction — fix and re-run —
is also the right one. This one is the opposite, so read it before reacting.

If "Upload to App Store Connect" succeeded and a later step failed, the binary
is already at Apple and the build number is already consumed. **Do not
re-dispatch first.** Confirm the build's real state in App Store Connect —
either in the TestFlight tab, or with your own key (see "Querying App Store
Connect by hand" below for the prerequisite):

```bash
ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id> \
  uv run --quiet --with pyjwt --with cryptography python scripts/asc_builds.py \
  list --bundle-id br.com.rentivo.ios
```

- The build is listed at `state=VALID` — the release worked and only the
  reporting failed. Nothing to do; do not re-dispatch.
- The build is listed as still processing — wait for it. Re-dispatching would
  upload the identical binary under a fresh build number.
- The build is listed at `FAILED` or `INVALID` — Apple rejected it during
  processing. That build number is spent regardless. Fix the cause and let the
  next run take the next build number; the emailed rejection from Apple says
  what to fix.

The step most likely to be red on its own is "Wait for the build to reach
VALID". It tolerates transient App Store Connect failures (network errors,
`429`, `5xx`) and re-mints its bearer token between polls, so it goes red only
on a real rejection, a genuine auth or client error, or the 30-minute timeout
elapsing while the build is still processing — the last of which is normal for
a slow processing queue and is *not* a failed release.

## Versioning

- `MARKETING_VERSION` is the release train (`CFBundleShortVersionString`) and is
  the only value a human edits. Debug and Release must agree; `scripts/ios-ci.sh
  marketing-version` fails loudly if they diverge instead of guessing. It labels
  the build; it does not gate the release, so one marketing version normally
  covers many builds.
- The build number (`CFBundleVersion`) is `github.run_number`, injected via
  `CURRENT_PROJECT_VERSION="$BUILD_NUMBER"` at archive time. The project file's
  own `CURRENT_PROJECT_VERSION` stays `1` and is not used for a release build.
- The export step's `ExportOptions.plist` sets
  `manageAppVersionAndBuildNumber` to `false`, so `xcodebuild -exportArchive`
  cannot rewrite the version/build numbers it was just archived with — the
  "Verify the embedded version numbers" step is checking the number CI passed
  in, not one Xcode picked afterward.
- Re-running a failed workflow run reuses its run number, so the build number
  never changes on a re-run — see "the version/build pair was already
  consumed" under Triage above for what that means for retries.

## Signing

There is no distribution certificate and no provisioning profile on the Apple
account, and none is needed. The archive is produced with
`CODE_SIGNING_ALLOWED=NO`, and `xcodebuild -exportArchive` with
`method: app-store-connect` and `-allowProvisioningUpdates` uses Xcode
cloud-managed distribution signing driven by the App Store Connect API key.

The two macOS jobs exclude betas the same way but rank the survivors
differently, and the difference is deliberate.

`release` picks strictly the newest non-beta toolchain: its "Select the newest
non-beta installed Xcode" step is
`ls -d /Applications/Xcode_*.app | grep -vi beta | sort -V | tail -1`, and it
fails outright if that yields nothing rather than falling back. The chosen
toolchain is printed by `xcodebuild -version` into the job log and the evidence
artifact.

`verify` delegates its steps to `.github/actions/ios-unit-tests`, whose "Select
an Xcode with an available iPhone simulator" step iterates the same non-beta
list newest-first (`sort -Vr`) and takes the first candidate for which
`xcrun simctl list devices available` actually reports an iPhone, with the
image-default `/Applications/Xcode.app` appended as the last fallback. It has
to: the runner images pre-install iOS simulator runtimes only for the image's
default Xcode, so blindly selecting the newest one can leave `xcodebuild
-showdestinations` with no iPhone destination and the unit tests unrunnable.

Why they may legitimately disagree: only the `release` job's output reaches
Apple. Betas are excluded from both because App Store Connect rejects a binary
built with a beta toolchain during processing — after the build number has
already been consumed. But beyond that, the binary must be built with the
newest shipping toolchain, whereas the tests only need *a* working simulator,
so `verify` is free to drop back to an older Xcode that has one.

Archiving with signing enabled does **not** work on this account: automatic
signing asks for an *iOS App Development* profile during an archive, and
development profiles must enumerate registered devices. This team has none.
App Store distribution profiles have no device requirement, which is why all
signing is deferred to the export step.

## Credentials

| Where | Name | Value |
|---|---|---|
| Secret | `APPSTORE_CONNECT_KEY_ID` | CI-only App Store Connect API key ID |
| Secret | `APPSTORE_CONNECT_ISSUER_ID` | account issuer ID |
| Secret | `APPSTORE_CONNECT_PRIVATE_KEY` | full `.p8` contents |
| Variable | `APPLE_TEAM_ID` | `Q87D3V95YZ` |
| Variable | `IOS_BUNDLE_ID` | `br.com.rentivo.ios` |

The Key ID and Issuer ID are secrets rather than variables because this
repository is public. The `.p8` is written to
`~/.appstoreconnect/private_keys/AuthKey_<key id>.p8` on the runner, which is
where both `xcodebuild -authenticationKeyPath` and `xcrun altool --apiKey`
look. Its contents are never printed, and the signed `.ipa` is never uploaded
as a workflow artifact — public-repo artifacts are downloadable by anyone. The
export log itself does get kept as part of the run's evidence artifact, but a
dedicated step scrubs the Key ID and Issuer ID out of it (`sed`-replaced with
`REDACTED`) before that upload, since `xcodebuild -exportArchive`'s own output
otherwise echoes both values back. The run keeps `DistributionSummary.plist`,
the `codesign` output, the redacted export log, and the `xcodebuild -version`
output that records which toolchain signed the build, for 30 days.

Two placements in `release` are load-bearing and should not be reordered. The
key directory is deleted by an `if: always()` step placed immediately before
`actions/upload-artifact` — that upload is the only `uses:` step that runs
after the key exists on disk, and external actions here are referenced by
mutable major-version tag. And the Key ID and Issuer ID are attached as `env:`
to only the steps that authenticate, rather than to the whole job, so the
archive and verification steps never see them.

Rotating the key: create a new key in App Store Connect -> Users and Access ->
Integrations, run `gh secret set APPSTORE_CONNECT_PRIVATE_KEY --repo
jorgejr568/rentivo < AuthKey_<new>.p8` and `gh secret set
APPSTORE_CONNECT_KEY_ID --repo jorgejr568/rentivo --body <new key id>`, then
revoke the old key.

## Manual runs

`workflow_dispatch` bypasses the `on.push.paths` filter, so it is how you
release a commit that changed nothing under `ios/`. `detect`, `verify`, and
`preflight` execute against whatever `MARKETING_VERSION` is on the dispatched
ref. The `release` job, however, is additionally gated on `github.ref ==
'refs/heads/main'`: dispatching from any other branch runs `detect`, `verify`,
and `preflight` and then stops — nothing is archived, signed, or uploaded. To
actually produce a build you must dispatch with `main` selected as the ref.

The `skip_upload` input archives, signs, and validates without uploading (the
upload and the VALID-polling step are both conditioned on
`!inputs.skip_upload`); use it from `main` to prove the signing path still
works without consuming a build number.

**`skip_upload` defaults to checked.** A manual dispatch releases whatever the
ref currently holds, so the default has to be the safe one: clicking "Run
workflow" to see what the pipeline does must not consume a build number for a
duplicate binary. Uploading by hand means deliberately unchecking the box. The
automatic `push` path never reads this input — it is intentionally ungated and
always uploads.

## TestFlight

There is no separate TestFlight build. TestFlight and App Store review consume
the same binary, so a build at `state=VALID` is already the TestFlight build.

`state=VALID` is *not* the same as testable, though. It means the binary
finished processing; a build that belongs to no beta group is invisible in the
TestFlight app no matter how valid it is. Version 1.1 (build 5) shipped exactly
that way before the release workflow attached builds to a group. The
"Distribute the build to its TestFlight group" step now closes that gap:

- **Internal testers** — the workflow attaches the build automatically. It
  picks the app's single internal group; set the `IOS_BETA_GROUP` repository
  variable to a group name when there is more than one, or none is internal.
  The group is resolved by name at release time, never pinned to an id.
- **External testers** — still manual; needs Beta App Review first.

The TestFlight-side records for a build appear minutes *after* it reports
`VALID` — until they do, App Store Connect answers a group association with
`404 NOT_FOUND` for a build id it will happily return from `/v1/builds`. The
step treats that 404 as "not yet" and re-polls, so it is not a failure unless
its 30-minute deadline elapses.

Export compliance is already answered: `ios/Config/Rentivo-Info.plist` sets
`ITSAppUsesNonExemptEncryption` to `false`, so App Store Connect does not
prompt per build. If that key is removed the prompt returns, and the correct
value depends on the app's actual cryptography — ask rather than guess.

## Querying App Store Connect by hand

This requires your own App Store Connect API key to already exist at
`~/.appstoreconnect/private_keys/AuthKey_<key id>.p8` on the machine running
the command (create one in App Store Connect -> Users and Access ->
Integrations if you don't have one) — `ASC_KEY_ID` below must match that
file's `<key id>` exactly, since that's the only place the script looks for
it; otherwise it exits with `No App Store Connect API key at <path>.`.

```bash
ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id> \
  uv run --quiet --with pyjwt --with cryptography python scripts/asc_builds.py \
  list --bundle-id br.com.rentivo.ios
```

`scripts/asc_builds.py` is CI tooling rather than application code, so it runs
with `uv run --with pyjwt` instead of `uv run --project backend`; adding
`pyjwt` to the backend's locked dependencies for a release script would be
worse. Its pure helpers (`normalize_builds`, `find_build`, `classify`,
`next_page_path`, `is_transient_status`, `is_pending_association_status`,
`select_beta_group`) and the `command_wait` and `command_distribute` polling
loops are unit-tested under the backend environment by
`scripts/tests/test_asc_builds.py`, which the release-gate `scripts` job runs
with `uv run --project backend --no-sync pytest
scripts/tests/test_asc_builds.py -q`, and `make scripts-test` runs locally
alongside the shell tests. `jwt` itself is imported lazily inside the script so
those pure helpers stay importable without `pyjwt` installed.

Besides `list`, the same script exposes three more subcommands: `check` (used
by the `preflight` job), `wait` (used by `release` after upload, with
`--timeout`/`--interval`), and `distribute` (used by `release` to attach the
build to its TestFlight group — also `--timeout`/`--interval`, plus an optional
`--group` that defaults to `None` so `select_beta_group` derives the app's
single internal group). All four take `--bundle-id`; every one except `list`
also requires `--version` and `--build`.

## What CI still does not do

- `RentivoUITests` is not in the required path. It is slower and more
  timing-sensitive, and at least one interaction (tapping the small in-row
  buttons on the API-key list screen) was unreliable with XCUITest's
  synthesized taps during local verification. Run it locally with
  `xcodebuild test -only-testing:RentivoUITests` against a booted simulator.
- Nothing submits a build for App Store review, sets phased rollout, or
  updates store metadata. Those stay manual in App Store Connect.
- iOS releases are independent of `release.yml`; the app and the backend do not
  share a version or a cadence.
