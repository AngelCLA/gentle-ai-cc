# Release 4.3.1-cc.4

Deliver the approved Gentle AI branding change through the repository release workflow.

## Specs

- S1: "haz commit y hay que publicar una version nueva"
- S2: "si te autorizo"
- S3: "Automático solo en `install`": `sync` does not restore a removed branding mod; the original Command Code banner remains.

## Tasks

- [x] T1 (S1, S3): Prepare version references, tests and release notes. Route: worker. Commit: this release-preparation commit.
- [ ] T2 (S1, S2, S3): Verify, create and merge PR. Route: parent. Commit: pending.
- [ ] T3 (S1, S2): Build verified release artifacts, publish and verify release. Route: parent. Commit: pending.

## Log

- L1: "haz commit y hay que publicar una version nueva"
- L2: "si te autorizo"
- L3: Branding commit 8d0b9f2 is on feat/gentle-ai-branding; it contains 486 authored changed lines, above the approximate 400-line review target. Keep the release preparation in a separate reviewable commit.
- L4: Go tests, vet, shell syntax and 79 installer fixtures passed; independent verification passed. PowerShell unavailable locally. Published-release E2E remains pinned to .3 until .4 exists.
