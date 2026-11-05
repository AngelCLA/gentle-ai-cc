Prepare repository-facing documentation and help for maintainable, honest distribution readiness.
Branch: fix/state-and-installers; baseline e029290 plus pre-existing uncommitted probe/README work. No push, release or license choice authorized.
Verification: docs/help structural checks and existing fake-only tests as applicable; no real installs or namespace retries.

## Specs
S1. "prepara bien el repositorio... asi ya como si la herramienta esta terminada". Present coherent installation, prerequisites, commands, maintenance and support limitations; do not claim missing runtime proof.
S2. Preserve all pre-existing uncommitted changes including README probe documentation, tests/linux_release_probe.py, tests/test_linux_release_probe.py and odd/tasks/linux-distribution-validation.md. The cancelled independent verifier for that probe must not be retried, substituted or represented as approved.
S3. Correct factual contradictions: installation precedence and private release access; PATH and tool requirements; accurately distinguish Linux fixture evidence vs real integration and untested platforms; avoid universal reproducibility or rollback guarantees. Existing operator decisions (license, support policies, release publication) remain unchosen.
S4. Update CLI help and scripts' comments for documented options and consistent guidance; retain behavior except deliberate help output corrections and keep focused checks for changed help.

## Tasks
T1 | S1,S2,S3,S4 | delegated (context backstop) | done | commit 71370ad5fbfc2b03131c50f09ad18bd3ae125655; help RED 2/GREEN 3; parent help 3, wrapper 22 and installer 12 passed, 1 PowerShell skipped; blocked probe not verified.
T2 | S1-S4 | parent | done | assessed medium/native unassessable, RDD off; source Go pin requirement corrected RED/GREEN, syntax/diff passed; staged README omits prior WIP and working diff retains exactly its 46 lines.

## Log
L1. User request verbatim: "prepara bien el repositorio... asi ya como si la herramienta esta terminada".
L2. Existing tracked branch fix/state-and-installers has pre-existing uncommitted README probe text, odd/tasks/linux-distribution-validation.md, and untracked tests/linux_release_probe.py, tests/test_linux_release_probe.py. Their independent verifier was cancelled and cannot be retried or substituted; preserve these files and do not imply verification. User explicitly deferred Windows and declined namespace setup. No publishing, real installation or upstream licensing decision authorized.
L3. Read-only explorer found doc contradictions around installer precedence, private release URL, PATH, platform support, reproducibility, help options and Windows messaging; source file evidence in explorer task mw3op8g6-k-ujqb. Do not invent license, support commitments or policies.
L4. T1 documentation/help/hygiene corrections implemented; help RED 2 failures/GREEN 3 tests; parent reran help 3, wrapper 22 and installer 12 with 1 PowerShell skip; bash syntax and diff checks passed. Blocked probe tests deliberately not executed or independently retried. ASSESS returned medium/native unassessable due untracked files; RDD off; no separate verifier required for this bounded unit. Prior uncommitted README probe section remains intact.
L5. Parent corrected pinned source Go requirement to 1.25.10 or newer (other refs may differ): help test RED one failure then GREEN all 3. Final help/related docs assessment medium, native unassessable due untracked WIP, RDD off. Committed isolated repository-readiness unit 71370ad5fbfc2b03131c50f09ad18bd3ae125655 (268 changed lines); staged README intentionally excluded the entire pre-existing 46-line future-probe section. Working README diff confirms exactly that section remains uncommitted; probe files and its task doc remain untouched. No release, real install, sandbox retry, license selection or full probe verification was performed. Windows/macOS and real Linux end-to-end remain unverified.
