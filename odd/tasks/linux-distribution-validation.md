Validate companion state isolation and a real Linux distribution flow, then evaluate installation recovery limits.
Branch: fix/state-and-installers; baseline b5286c3; prior user-selected review delivery: feature-branch-chain. No publication authorized.
Tests: isolated real binary, local assets, network-denied confinement where available; existing Python suite. Risks: items 1,2,4,5.

## Specs
S1. User: "hazlo entonces!", accepting "Primero estudiaría una prueba aislada del estado independiente" and "Que la variable se aplique solo al companion, no accidentalmente al oficial." "Qué pasa con los manifiestos, backups y demás archivos que también se separan." "Cómo conservar o migrar de forma segura una instalación existente." "Si ambos binarios podrían seguir escribiendo otros archivos comunes, aunque su estado esté separado."
S2. User accepts "Y en paralelo haría la prueba real de instalación en Linux antes de distribuir." Use disposable isolated state and real binaries; no public release, no modification of user installation.
S3. User accepts "Después decidiría si el registro de transacción justifica su complejidad" and "detectar la interrupción, preservar evidencia y ofrecer una recuperación verificable"; evaluate in light of concrete risks without inventing guarantees or operating recovery on user data.
S4. "Es viable, pero todavía no está demostrado que elimine toda la concurrencia." "No activaría la separación sin probar esos efectos y definir la migración." Keep current behavior until evidence and consequential migration design support a change.
S5. "publicar requiere tu autorización." Windows proof remains deferred by the user; no push, publish, release, real HOME mutation, or external checkout writes.

## Tasks
T1 | S1,S2,S4 | inline | blocked | user/network/mount namespace creation denied; waits for an authorized environment with real network and filesystem isolation.
T2 | S1,S2,S4 | inline/background | blocked | waits for an authorized Linux environment with network and filesystem confinement; real build/install/sync unrun.
T3 | S1,S3,S4 | inline | done | read-only evaluation: state isolation moves manifests/backups/telemetry; HOME-derived agent files remain shared, migration may change selection; defer journal implementation until real proof and safe recovery design; no state changes.
T4 | S1-S5 | independent verify + parent | blocked | waits for real isolated Linux evidence; Windows remains deferred; no source changes to verify.

## Log
L1. User request verbatim: "hazlo entonces!" accepting the immediately preceding proposal: isolated state proof first, evaluate transaction journal, and real Linux installation test.
L2. Baseline b5286c3, clean branch. Previous external checkout /home/claangel/dev/gentle-ai is user-authorized for reading only. Explorer found GENTLE_AI_HOME moves a state family; companion self-updates/detects dependencies unless explicitly constrained, no global offline flag established, and full-gentleman may acquire packages. A real probe requires proven no-network confinement and only scratch writes, explicit env isolation; do not trust flags alone. Windows proof remains deferred. Go 1.25.10 available.
L3. `unshare --user --map-root-user --net --mount true` returned exit 1 `unshare: error de escritura /proc/self/uid_map: Operación no permitida`. This is a permission denial, not evidence of safe isolation. No alternate tool used to bypass denial. Real companion probe remains unrun. Proceed with independent read-only evaluation of migration and transaction journal.
L4. Parent confirmed companion state/home.go:9-27 resolves GENTLE_AI_HOME for a family including manifest, journal, backups and telemetry; state/state.go:227-245 reads state only from chosen directory, no automatic migration. commandcode/adapter.go:73-95 retains HOME-based AGENTS.md/skills/mcp.json targets. Hence separate state alone does not prove nonconflicting writes; no automatic migration. Installer publication code has snapshots, conditional rollback and retained backups on restore failure, but no durable transaction journal; a crash journal would need scoped path ownership, durable phases and tested recovery. Recommend deferring journal rather than claim crash safety, pending safe isolated evidence and explicit recovery design. No installation/build/release or state mutation was performed.
