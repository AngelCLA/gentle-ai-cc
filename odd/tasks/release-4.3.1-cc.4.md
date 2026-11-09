# Release 4.3.1-cc.4

Deliver the approved Gentle AI branding change through the repository release workflow.

## Specs

- S1: "haz commit y hay que publicar una version nueva"
- S2: "si te autorizo"
- S3: "Automático solo en `install`": `sync` does not restore a removed branding mod; the original Command Code banner remains.
- S4: "si" — authorization to implement the proposed targeted recovery when a failed companion leaves `installed_agents: null`, preserving other state.

## Tasks

- [x] T1 (S1, S3): Prepare version references, tests and release notes. Route: worker. Commit: this release-preparation commit.
- [x] T2 (S1, S2, S3): Verify, create and merge PR. Route: parent. Commit: 16133c45 (PR #11, includes 8d0b9f2, 3117bbb, 4fa1237).
- [x] T3 (S1, S2): Build verified release artifacts, publish and verify release. Route: parent. Tag: 4.3.1-cc.4 at 16133c45.

- [ ] T4 (S4): Implement and verify targeted failed-companion null-state recovery. Route: worker and independent verifier. Commit: pending. BLOCKED: independent verifier failed to start with EDQUOT; explicitly excluded from published release.

## Log

- L1: "haz commit y hay que publicar una version nueva"
- L2: "si te autorizo"
- L3: Branding commit 8d0b9f2 is on feat/gentle-ai-branding; it contains 486 authored changed lines, above the approximate 400-line review target. Keep the release preparation in a separate reviewable commit.
- L4: Go tests, vet, shell syntax and 79 installer fixtures passed; independent verification passed. PowerShell unavailable locally. Published-release E2E remains pinned to .3 until .4 exists.
- L5: Issue #10 approved; PR #11 opened with Closes #10. CI twice failed on HTTP 504. Isolated Linux reproduction with published companion captured installed_agents:null after failed Engram download and before cleanup. User: "si" authorizes targeted recovery proposed in the preceding conversation. Pre-existing invalid state must remain rejected, unrelated state preserved, and child failure must remain visible.
- L6: Final wording is Powered by Gentle AI (4fa1237). All three hosted checks passed on that commit, testing published .3 assets. PR #11 confirmed merged as 16133c45 and issue #10 closed. Release .4 published with six rebuilt wrappers and six byte-identical .3 companions. All twelve assets downloaded back from GitHub and passed checksums; published manifest matched local manifest. These checks do not establish runtime E2E of .4 on every platform. T4 remains excluded and blocked; no local changes were discarded.
