# Release 4.3.1-cc.5

Publish the supported pink Gentle AI widget using isolated release preparation.
Preserve the original banner and exclude the unverified shared-state recovery fix.

## Specs

- S1: "va, pon lo de  “Powered by Gentle AI” en rosa mediante la API soportada"
- S2: "haz commit y publicacion... y la release"

## Tasks

- [x] T1 (S1, S2): Update release defaults and documentation, preserve history, verify tests. Route: worker. Commits: 1904a2f, 7eca3f8. User supplied successful Go suite result after independent verifier quota failure.
- [ ] T2 (S2): Verify and merge PR linked to approved issue #10. Route: parent and verifier. Commit: pending.
- [ ] T3 (S2): Build six wrappers, reuse verified companion assets, publish and verify all downloads. Route: parent. Commit: pending.

## Log

- L1: "va, pon lo de  “Powered by Gentle AI” en rosa mediante la API soportada"
- L2: "haz commit y publicacion... y la release"
- L3: Existing .4 release is immutable. Use .5. The main worktree contains unrelated uncommitted shared-state recovery changes; do not modify or include them. Pink uses documented ANSI styling in widget strings: RGB 255,121,198 with reset. Existing user-mod files are not overwritten; document manual update for existing installations.
- L4: Writer observed version-default RED then GREEN (79 Bash installer cases); Go suite/vet and syntax passed. Independent verifier passed 79 fixtures, syntax, exact pink/reset mock, source pin and scope checks; Go test compilation failed with disk quota exceeded. No verifier retry. PowerShell unavailable locally.
- L5: User ran the missing Go suite in this worktree and supplied verbatim: "?       gentle-cc/cmd/gentle-cc [no test files]" and "ok      gentle-cc/internal/wrapper      5.756s" after `GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go test ./... -count=1 -timeout=120s`. This completes the missing executable check through human-provided evidence, not a verifier relaunch. The authorized Go cache cleanup was performed; other evidence preserved.
