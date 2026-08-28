## Summary
<!-- 1-3 bullets: what changed and why. Lead with the "why". -->

-

## What changed
<!-- Concrete list of the modifications. Files, components, or behavior. Keep it scannable. -->

-

## Test plan
<!-- Checklist of what was verified and what the reviewer should verify. -->

Always:

- [ ] `make test` passes locally
- [ ] `make lint` clean
- [ ] Manual smoke: <!-- describe the flow you exercised in a browser / CLI, or write "N/A" -->

Only if the area is touched — mark **N/A** otherwise:

- [ ] Frontend: `make frontend-check` / `make e2e`
- [ ] API schema: `make openapi-check`, `make ios-openapi-check`
- [ ] `scripts/`: `make scripts-test`
- [ ] `ios/`: `make ios-test`

## Screenshots / recordings
<!-- Delete section if no UI changes. Otherwise paste before/after.
     Two UI surfaces exist: React (browser) and SwiftUI (iOS).
     For iOS changes attach simulator captures. -->

## Config / deployment notes
<!-- Env vars added, migrations needed, feature flags, rollout order. Write "None" if nothing. -->

- Env vars:
- Migrations:
- Feature flags:
- Touches `ios/`? <!-- yes/no. "yes" means merging this PR automatically archives, signs, and uploads a build to App Store Connect and distributes it to TestFlight — an irreversible release action. Note whether `MARKETING_VERSION` is bumped too. -->

## Risk & rollback
<!-- What could break, and how to revert. -->

- Risk:
- Rollback:

## Related
<!-- Issues, specs, prior PRs, Slack threads. Delete section if N/A. -->

-

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)
