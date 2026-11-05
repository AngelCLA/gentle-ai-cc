Harden shared-state handling and installation failures accepted after the project review.
Branch: fix/state-and-installers. Delivery: auto-chain, chain_strategy=feature-branch-chain (local commit slices only; no publishing authorized); two cohesive work units, revised forecast ~600 authored lines excluding this log (T1 is ~332 lines).
Runner: python3 -m unittest discover -s tests -v; bash -n. Risk: items 1, 4, 5 (shared data, concurrency, installers).

## Specs
S1. User: "hazlo", accepting the review recommendation: "corregir primero la integridad del estado y el chequeo previo de Python". Preserve unrelated state, fail before companion mutation without Python, atomically replace valid state, serialize wrapper mutations. Assumption: external binaries cannot honor a wrapper-only lock; document that limitation rather than promise cross-program isolation.
S2. User: "hazlo", accepting finding "Ayuda y simulación también escriben en el estado". Forward help and dry-run without wrapper state writes.
S3. User: "hazlo", accepting "la instalación parcial y la caché de versiones". Verify all requested release artifacts before destination replacement; do not reuse stale/incomplete Windows release downloads.
S4. User: "hazlo", accepting "El instalador autenticado deja temporales". Clean authenticated download staging on success and failure, preserving child exit status.
S5. User: "hazlo", accepting "Esas correcciones deberían acompañarse con pruebas aisladas del wrapper y de fallos de instalación." Include focused regression tests and relevant documentation; do not install into the real HOME, download real releases, or publish.

## Tasks
T1 | S1,S2,S5 | delegated (context backstop) | done | RED: 12 failures across 7 tests; GREEN and parent spot check: all 12 tests pass; unit commit pending; independent final verification is T3.
T2 | S3,S4,S5 | delegated (context backstop) | in_progress | installer fixes, tests and docs; commit pending.
T3 | S1-S5 | independent verify + parent | pending | final assessment and verification; evidence pending.

## Log
L1. User's original implementation request verbatim: "hazlo". Context: the preceding read-only review listed six findings concerning atomic shared-state writes, Python preflight, help/dry-run mutation, release validation ordering, Windows cache, and leaked download temporary directories.
L2. Baseline 307f672, clean main. Review reproduced dry-run/help mutation and missing-python exit 127 in isolated HOME. All four Bash scripts passed syntax checks; shellcheck and pwsh unavailable. Background subagent policy is off; independent units cannot be launched together in background, so no parallel writers.
L3. Context backstop fired after parent wrote initial T1 tests; delegated T1 to gentle-ai-worker. Worker observed RED (12 failures across 7 tests), then GREEN (12 tests); parent reran all 12 successfully. bash -n and git diff --check passed. Wrapper owns a fail-fast mkdir lock through all of sync-all, validates state before mutation, preserves file permissions using atomic replacement, skips cleanup for help/dry-run, and documents external writer limitations. Revised total forecast exceeds 400 authored lines.
L4. User selected "Cadena sobre rama de trabajo — recomendada". Keep two local work-unit boundaries; no push or PR authorization. T1 assessment: high through escalation item 1, native unassessable because untracked files need explicit declaration. RDD off; no review lifecycle invoked. Follow self-checks plus independent final verifier (T3).
