# Windows public-install readiness
Objective: Make the public Windows release installation and first-use smoke reliably testable for developer distribution.
Branch: `fix/release-defaults`; base: `134ac7a50d5bceac1bf3b4a8a6407553fc0fcf7c`.

## Specs
S1. User: "Pero ahora quiero que funcione para windows tambien"
S2. User: "para compartirlo y otros desarrolladores me ayuden"

## Tasks
T1 | S1 | parent | done | Fix native `gh auth status` stderr handling with native `.cmd` stderr fixture; PowerShell 7.6 full fixtures pass. Windows PowerShell 5.1 attempt blocked locally because its runtime lacks `Get-FileHash`; commit: `7bf0f13`.
T2 | S1 | parent | done | E2E copies only installer, hides `gh`, uses local companion path for direct checks, and leaves Windows `GENTLE_CC_BIN` unset for sibling lookup; workflow triggers and Windows PowerShell 5.1 fixtures are in `e9e5186`, path correction commit pending. Hosted E2E pending.
T3 | S1-S2 | parent | done | README documents Windows amd64 hosted public-installer path, evidence limits and unverified arm64; commit: `e9e5186`.
T4 | S1-S2 | parent | in_progress | PowerShell 7.6 installer fixtures, PowerShell AST parsing, Windows PowerShell 5.1 native-stderr regression microcheck, workflow structural checks and independent post-install path recheck pass. Full PS5.1 fixture suite cannot run locally because that runtime lacks `Get-FileHash`; hosted E2E/YAML parser unavailable locally; assess and final correction commit pending.
T5 | S1 | parent | blocked | Awaiting explicit authorization to push `fix/release-defaults` and trigger hosted GitHub Actions Windows public-install E2E; no push/publish authorization inferred.

L2. Independent verifier found that the first E2E edit removed `GENTLE_CC_BIN` while shared post-install checks still referenced it, breaking both OS jobs. Parent reproduced the null-path failure; corrected all direct checks to use `$companionBin`, while preserving explicit Linux override and Windows sibling lookup. Independent follow-up and local structural path probe passed.

## Log
L1. User original request: "okay... lo tomare como de que ya puedo distribuirlo... mas que nada para compartirlo y otros desarrolladores me ayuden. Pero ahora quiero que funcione para windows tambien"
