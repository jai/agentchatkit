# agentchatkit

Instructions for agents working in this repo.

<!-- BEGIN jai/ci standard section -->
## CI, releases and deploys

This repo follows [RULES.md in jai/ci](https://github.com/jai/ci/blob/main/RULES.md), the
one place for these rules: push to main (no branches or pull requests), main stays green,
release-please releases hourly, the release tag deploys, and what you may run on Jai's
Macs. Read it before you change a workflow, release, deploy or run work on a Mac.
<!-- END jai/ci standard section -->

## About this repo

**Checks:** run `make setup` once per clone, and `make check` before you push.

See README.md.

## Never breaking

Apps take every release of this kit as it comes (`from:` ranges), so a release must never break one (Jai, 2026-11-16).

- Add to the public API; never remove a public declaration or change its signature. To replace one, add the new one
  and mark the old `@available(*, deprecated, message: "Use …")`.
- CI's `api` job runs `swift package diagnose-api-breaking-changes <latest release tag>` on every push and pull
  request, and a release waits for CI to pass. Run it yourself before you push a change to a public API.
- A deliberate break needs Jai's OK first, and a major version.
