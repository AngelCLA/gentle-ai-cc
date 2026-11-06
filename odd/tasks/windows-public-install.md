# Windows public-install readiness
Objective: Make the public Windows release installation and first-use smoke reliably testable for developer distribution.
Branch: `fix/release-defaults`; base: `134ac7a50d5bceac1bf3b4a8a6407553fc0fcf7c`.

## Specs
S1. User: "ahora quiero que funcione para windows tambien" — ensure public Windows installation can fall back safely when native `gh` reports an authentication failure, and test the real Windows PowerShell behavior.
S2. User: "ahora quiero que funcione para windows tambien" — make hosted Windows smoke coverage exercise the public installer path and the installed wrapper, rather than only a prepared local `dist/` pair.
S3. Scope: Preserve the existing Linux path and release artifacts; do not publish or push. Update Windows support documentation to accurately state what CI proves and what remains unverified.

## Tasks
T1 | S1 | parent | done | Fix native `gh auth status` stderr handling with native `.cmd` stderr fixture; PowerShell 7.6 full fixtures pass. Windows PowerShell 5.1 attempt blocked locally because its runtime lacks `Get-FileHash`; commit: pending.
T2 | S2 | parent | pending | Exercise Windows public HTTPS installation in hosted E2E and ensure workflow triggers on Windows installer changes; commit: pending.
T3 | S3 | parent | pending | Update platform support docs alongside tests; commit: pending.
T4 | S1-S3 | parent | pending | Run relevant Windows-capable and local checks; assess candidate; commit: pending.

## Log
L1. User original request: "okay... lo tomare como de que ya puedo distribuirlo... mas que nada para compartirlo y otros desarrolladores me ayuden. Pero ahora quiero que funcione para windows tambien"
