# agentchatkit

Instructions for agents working in this repo.

## Tests on Jai's Macs

Before you run UI tests, or anything else that controls the screen, on one of Jai's Macs (directly or over SSH), read
`AGENTS.ci.md` in jai/ci (private):
`gh api repos/jai/ci/contents/AGENTS.ci.md -H 'Accept: application/vnd.github.raw'`.
It says which Macs are off limits and how to run Mac UI tests through CI. If you cannot read it, do not run them there.
