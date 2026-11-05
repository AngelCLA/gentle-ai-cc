Harden source installation, agent isolation, installation recovery and wrapper locking; investigate shared-state isolation.
Branch: fix/state-and-installers; delivery: feature-branch-chain as previously selected. Baseline: 3e4eae6.
Runner: PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v; bash -n. Risks: items 1, 2, 4, 5.

## Specs
S1. "Tomarlo de esta distribución, con una versión coherente con el instalador." "Comprobar que esté disponible antes de modificar el destino." "Si no está y no se pidió `--no-wrapper`, terminar con error." "Probar que nunca se informe una instalación completa dejando un wrapper viejo o ausente."
S2. "Comprobar primero cómo interpreta el companion los `--agent` repetidos." "Impedir que el wrapper permita seleccionar agentes ajenos a Command Code." "Rechazar argumentos incompatibles antes de ejecutar cualquiera de los binarios." "Probar código de salida, mensaje exacto y ausencia de modificaciones ante el rechazo."
S3. "Preparar los archivos nuevos dentro del mismo sistema de archivos del destino." "Conservar los archivos anteriores hasta completar ambos reemplazos." "Ante un error de reemplazo, restaurar únicamente los archivos de esa instalación." "Probar fallos controlados durante cada paso." "No prometería atomicidad absoluta entre dos archivos ni recuperación garantizada ante un corte de energía."
S4. "Preferir un bloqueo que el sistema operativo libere al terminar el proceso, si podemos sostenerlo en las plataformas soportadas. Si mantenemos el directorio de bloqueo, necesitamos identificar al propietario y ofrecer una recuperación segura; no borrarlo automáticamente solo porque sea antiguo."
S5. "Hay que investigar si gentle-ai permite usar un estado independiente para el companion y qué implicaciones tiene. Si no lo permite, la solución completa requiere cambios en el código que gestiona ese estado: separación o coordinación entre escritores. Hasta entonces, la prohibición de ejecución simultánea sigue siendo una limitación real."
S6. "Cada corrección tiene que incluir su prueba de fallo antes del cambio, no solamente una prueba de que el caso normal funciona." "Mantendría Bash/Go; ninguno de estos problemas exige migrar a npm."

## Tasks
T1 | S1,S6 | delegated (context backstop) | done | RED 4 failures; GREEN 8 installer tests, one Windows skip; parent spot check and syntax passed; commit pending; independent verification T6.
T2 | S2,S6 | delegated (context backstop) | in_progress | agent isolation and tests; external parser proof may require consent.
T3 | S3,S6 | inline | pending | recover installer replacements with failure-injection tests.
T4 | S4,S6 | inline | pending | reliable lock design and tests.
T5 | S5 | read-only exploration | pending | inspect only authorized project evidence; report exact additional proof needed.
T6 | S1-S6 | independent verifier + parent | pending | assess high-risk and verify all feasible behavior, preserve existing Windows proof blocker.

## Log
L1. User's original request verbatim: "procede". It accepts the immediately preceding five-part proposal quoted in Specs.
L2. Current branch was clean at 3e4eae6. Previous feature remains blocked on Windows PowerShell proof; user explicitly deferred it until tomorrow. Initial bounded explorer found source wrapper incorrectly sourced from external module, wrapper forwards --agent, destination files are overwritten without rollback, lock uses ownerless mkdir, and no independent-state or companion parser implementation exists inside this repository. Never read external checkout without target-specific authorization. No actual installation, rollback, cleanup of user files, network, push, or release authorized.
L3. T1 worker used distribution sibling wrapper staged before destination/clone/build; --no-wrapper bypasses requirement. RED four failures, GREEN 8 installer tests and one Windows skip; full suite 22 passed, one skipped; parent spot check passed. Assessment escalated item 5, native unassessable due untracked feature document, RDD off; independent verify due T6. External companion parser evidence remains unavailable under outside-path boundary.
