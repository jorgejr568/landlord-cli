# iOS Release Runbook

The iOS app ships to App Store Connect from CI. A release is triggered by one
thing: changing `MARKETING_VERSION` in `ios/Rentivo.xcodeproj/project.pbxproj`
and merging that change to `main`.

## How a release happens

1. Open a PR that bumps `MARKETING_VERSION` (for example `1.0.1` -> `1.0.2`).
   Leave `CURRENT_PROJECT_VERSION` alone — CI supplies the build number.
2. The PR runs the normal release gate. The macOS `ios` job runs only when the
   PR touches `ios/`, `scripts/ios-ci.sh`, `scripts/tests/ios-ci-test.sh`, or
   either iOS workflow file.
3. Merging to `main` starts `.github/workflows/ios-release.yml`. Its `detect`
   job diffs `project.pbxproj` against the previous commit; if
   `MARKETING_VERSION` did not change, the run stops there. If `HEAD^` cannot
   be resolved at all (for example a history rewrite), `detect` fails outright
   rather than guessing — errors err toward *not* releasing, not toward
   releasing. If `detect` decides a release is warranted, two jobs run against
   that commit:
   - `verify` (macOS): `./scripts/sync-ios-openapi.sh check`, then
     `swift test --package-path ios` and the Xcode-hosted `RentivoTests`
     target via the `ios-unit-tests` composite action.
   - `preflight` (Linux): asks App Store Connect whether the marketing version
     plus build number is already consumed, and fails fast if it is.
   Only if both succeed does `release` (macOS) run, and only when the workflow
   is executing on `main` (`github.ref == 'refs/heads/main'`): it archives
   **unsigned**, exports **signed**, checks the signature is
   `Apple Distribution` for team `Q87D3V95YZ`, checks the embedded
   `CFBundleShortVersionString`/`CFBundleVersion`, validates, uploads, and
   polls until the build reports `state=VALID`.

The upload is automatic and irreversible. A build number is consumed
permanently and an uploaded build can only be expired, never deleted. There is
no approval step between merging a version bump and the upload.

## Versioning

- `MARKETING_VERSION` is the release train (`CFBundleShortVersionString`) and is
  the only value a human edits. Debug and Release must agree; `scripts/ios-ci.sh
  marketing-version` fails loudly if they diverge instead of guessing.
- The build number (`CFBundleVersion`) is `github.run_number`, injected via
  `CURRENT_PROJECT_VERSION="$BUILD_NUMBER"` at archive time. The project file's
  own `CURRENT_PROJECT_VERSION` stays `1` and is not used for a release build.
- The export step's `ExportOptions.plist` sets
  `manageAppVersionAndBuildNumber` to `false`, so `xcodebuild -exportArchive`
  cannot rewrite the version/build numbers it was just archived with — the
  "Verify the embedded version numbers" step is checking the number CI passed
  in, not one Xcode picked afterward.
- Re-running a failed workflow run reuses its run number. If a run fails after
  the upload succeeded, the preflight on the re-run fails with
  "already consumed" — dispatch a fresh run instead of re-running.

## Signing

There is no distribution certificate and no provisioning profile on the Apple
account, and none is needed. The archive is produced with
`CODE_SIGNING_ALLOWED=NO`, and `xcodebuild -exportArchive` with
`method: app-store-connect` and `-allowProvisioningUpdates` uses Xcode
cloud-managed distribution signing driven by the App Store Connect API key.

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
the `codesign` output, and the redacted export log for 30 days.

Rotating the key: create a new key in App Store Connect -> Users and Access ->
Integrations, run `gh secret set APPSTORE_CONNECT_PRIVATE_KEY --repo
jorgejr568/rentivo < AuthKey_<new>.p8` and `gh secret set
APPSTORE_CONNECT_KEY_ID --repo jorgejr568/rentivo --body <new key id>`, then
revoke the old key.

## Manual runs

`workflow_dispatch` skips the version-change check — `detect` sets
`release=true` unconditionally for a manual run, so `verify` and `preflight`
always execute against whatever `MARKETING_VERSION` is on the dispatched ref.
The `release` job, however, is additionally gated on `github.ref ==
'refs/heads/main'`: dispatching from any other branch runs `detect`, `verify`,
and `preflight` and then stops — nothing is archived, signed, or uploaded. To
actually produce a build you must dispatch with `main` selected as the ref.

The `skip_upload` input archives, signs, and validates without uploading (the
upload and the VALID-polling step are both conditioned on
`!inputs.skip_upload`); use it from `main` to prove the signing path still
works without consuming a build number.

## TestFlight

There is no separate TestFlight build. TestFlight and App Store review consume
the same binary, so a build at `state=VALID` is already the TestFlight build.
What remains is distribution configuration in App Store Connect:

- **Internal testers** — assign in the TestFlight tab; no review, immediate.
- **External testers** — needs Beta App Review first.

Export compliance is already answered: `ios/Config/Rentivo-Info.plist` sets
`ITSAppUsesNonExemptEncryption` to `false`, so App Store Connect does not
prompt per build. If that key is removed the prompt returns, and the correct
value depends on the app's actual cryptography — ask rather than guess.

## Querying App Store Connect by hand

```bash
ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id> \
  uv run --quiet --with pyjwt --with cryptography python scripts/asc_builds.py \
  list --bundle-id br.com.rentivo.ios
```

`scripts/asc_builds.py` is CI tooling rather than application code, so it runs
with `uv run --with pyjwt` instead of `uv run --project backend`; adding
`pyjwt` to the backend's locked dependencies for a release script would be
worse. Its pure helpers (`normalize_builds`, `find_build`, `classify`,
`next_page_path`) are unit-tested under the backend environment by
`scripts/tests/test_asc_builds.py`, which the release-gate `scripts` job runs
with `uv run --project backend --no-sync pytest scripts/tests/test_asc_builds.py
-q`. `jwt` itself is imported lazily inside the script so those pure helpers
stay importable without `pyjwt` installed.

Besides `list`, the same script exposes `check` (used by the `preflight` job)
and `wait` (used by `release` after upload, with `--timeout`/`--interval`).

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
