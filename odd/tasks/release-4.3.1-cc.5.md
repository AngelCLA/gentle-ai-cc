# Release 4.3.1-cc.5

Publish the supported pink Gentle AI widget using an isolated release worktree.
Preserve the original banner and exclude the unverified shared-state recovery fix.

## Specs

- S1: "va, pon lo de  “Powered by Gentle AI” en rosa mediante la API soportada"
- S2: "haz commit y publicacion... y la release"

## Tasks

- [x] T1 (S1, S2): Update release defaults and documentation, preserve history, verify tests. Route: worker. Commits: 1904a2f, 7eca3f8. User supplied successful Go suite result after independent verifier quota failure.
- [x] T2 (S2): Verify and merge PR linked to approved issue #10. Route: parent. Commit: 38963bf (PR #13 merged; PR checks failed only on external GitHub 504s, main CI green).
- [x] T3 (S2): Build six wrappers, reuse verified companion assets, publish and verify all downloads. Route: parent. Tag: 4.3.1-cc.5 at 38963bf; release published and assets verified.

## Log

- L1: "va, pon lo de  “Powered by Gentle AI” en rosa mediante la API soportada"
- L2: "haz commit y publicacion... y la release"
- L3: Existing .4 release is immutable. Use .5. The main worktree contains unrelated uncommitted shared-state recovery changes; do not modify or include them. Pink uses documented ANSI styling in widget strings: RGB 255,121,198 with reset. Existing user-mod files are not overwritten; document manual update for existing installations.
- L4: Writer observed version-default RED then GREEN (79 Bash installer cases); Go suite/vet and syntax passed. Independent verifier passed 79 fixtures, syntax, exact pink/reset mock, source pin and scope checks; Go test compilation failed with disk quota exceeded. No verifier retry. PowerShell unavailable locally.
- L5: User ran the missing Go suite in this worktree and supplied verbatim: "?       gentle-cc/cmd/gentle-cc [no test files]" and "ok      gentle-cc/internal/wrapper      5.756s" after `GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go test ./... -count=1 -timeout=120s`. This completes the missing executable check through human-provided evidence, not a verifier relaunch. The authorized Go cache cleanup was performed; other evidence preserved.
- L6: Merged PR #13 as 38963bf after its checks failed only on HTTP 504 responses from the GitHub release download endpoint while fetching published 4.3.1-cc.3 assets; main CI for 38963bf passed both workflows. Built six wrappers from the merged commit in an isolated worktree and reused the six byte-identical 4.3.1-cc.3 companion assets verified against the 4.3.1-cc.4 manifest. Published https://github.com/AngelCLA/gentle-ai-cc/releases/tag/4.3.1-cc.5 with 12 binaries and checksums.txt. Downloaded all 13 assets back; sha256sum -c passed for all 12 binaries and the downloaded manifest matched the local one. The uncommitted shared-state recovery changes remain untouched and excluded.
