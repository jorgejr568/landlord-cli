# Retire Android and macOS Apps Design

## Objective

Remove the Android and macOS applications and every repository capability or product reference that exists solely to build, test, package, configure, document, or support those apps. After this change, Rentivo supports the browser application and the native iOS application.

## Scope

The removal is atomic. The repository must not retain compatibility stubs, disabled jobs, placeholder directories, obsolete configuration, or documentation that suggests either retired app remains supported.

The following are removed:

- the complete `android/` and `macos/` source trees;
- Android and macOS CI actions, path classifiers, helper tests, Make targets, packaging scripts, and icon-generation scripts;
- Android Digital Asset Links API behavior, settings, environment variables, proxy routing, tests, and generated contract entries;
- Android and macOS setup, support, release, privacy, architecture, testing, and contributor documentation;
- historical repository prose that presents either application as part of the product, including the Android changelog entry and superseded design-spec comparisons;
- pull-request checklist items and agent instructions that require Android or macOS work.

## Necessary Platform References That Remain

This is an application retirement, not a ban on the operating-system names. References remain when they describe infrastructure still required by supported software. Examples include:

- macOS GitHub runners used to build or test iOS;
- SwiftPM macOS host compatibility needed for `swift test --package-path ios`;
- conditional Darwin behavior needed by iOS package tests running on a macOS host;
- dependency lock entries for macOS wheels;
- iOS deployment and App Store documentation that requires Xcode on macOS.

These references must not claim that a Rentivo macOS app exists.

## Source and Backend Changes

Delete both application trees. Remove the `/.well-known/assetlinks.json` route and its response-building logic from the public API. Remove `android_package_name` and `android_cert_fingerprints` from settings and from `.env.example`. Remove the dedicated Nginx location for Asset Links.

The API removal changes the public schema. Regenerate `frontend/openapi.json`, `frontend/src/lib/api/schema.d.ts`, and the byte-identical iOS contract copy at `ios/Rentivo/openapi.json`. No Android contract copy remains.

The iOS `RentivoCore` package continues to support its macOS test host because the repository's iOS test command executes SwiftPM tests on macOS. App-sharing comments and product-facing macOS language are removed, while test-host compatibility remains.

## CI and Developer Tooling

Delete `.github/actions/android-unit-tests`, `.github/actions/macos-app-tests`, `scripts/android-ci.sh`, `scripts/macos-ci.sh`, their test scripts, the Android OpenAPI sync helper, and macOS packaging/icon helpers.

Update the release-gate workflow to expose and consume only the remaining change areas. Remove Android and macOS jobs and script-test steps, and remove those jobs from downstream `needs` lists and success assertions. Preserve iOS, backend, frontend, E2E, migration, infrastructure, image, and security gates.

Update the Makefile to remove every Android/macOS application target and leave the iOS and general repository targets intact. Update iOS classifier comments and tests so they describe iOS jobs only.

## Documentation

Rewrite repository entry points and contributor guidance to describe browser and iOS clients only. Delete `docs/macos.md`. Convert mobile documentation to iOS-only material or remove sections that have no remaining supported consumer. Remove Android/macOS application references from configuration, development, release, security, App Store privacy, agent, and PR-template guidance.

Historical prose in `CHANGELOG.md` and design specs is also in scope because the requested end state contains no application references. Necessary generic operating-system references remain under the rule above.

## Verification

Verification must cover both absence and repository health:

1. Confirm no tracked `android/` or `macos/` tree, app-specific action, script, Make target, workflow job, backend setting, or Asset Links route remains.
2. Scan product/configuration prose for retired-app references, manually excluding only technically necessary host/platform mentions.
3. Run repository script tests.
4. Run backend lint, format checks, full tests, and the 100% coverage gate.
5. Regenerate and check OpenAPI artifacts, including byte identity between frontend and iOS snapshots.
6. Run frontend tests, typechecking, lint, and production build.
7. Run the iOS Swift package tests.
8. Inspect the final diff for accidental changes to unrelated functionality.

## Delivery

The removal ships as one reviewable change. Automated agents may create a branch, commit, push, and open a pull request, but they must not merge it. A human performs the merge.
