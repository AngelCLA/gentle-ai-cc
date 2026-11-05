Prepare a manual CI test for the published companion and native wrapper on disposable hosted Windows and Linux runners.
Branch: fix/release-defaults; the user authorized pushing the branch and running the first diagnostic; no release publication or changes to user installation authorized.
Verification: local structural and fixture checks followed by a diagnostic on hosted runners; incomplete assertions do not establish full correctness.

## Specs
S1. User: "hay que comprobar eso" — "que el companion y el wrapper instalados realicen correctamente `install` y `sync` para Command Code en un entorno aislado".
S2. User: "es que no tengo ninguna maquina desechable... no se puede con CI/CD?" and "SI" to "prepare la prueba para Windows y Linux y después te muestre los cambios antes de subirlos".
S3. "Descargar e instalar la release publicada, verificando sus checksums." "Ejecutar el wrapper real con `install` y después `sync`." "Comprobar los archivos generados de Command Code, el estado y los códigos de salida." "Registrar los resultados sin incluir datos sensibles."
S4. "Usaríamos permisos mínimos, sin secretos y con un directorio de usuario de prueba." "primero habría que determinar qué descargas son necesarias y limitar o documentar el acceso de red."

## Tasks
T1 | S1-S4 | parent | done | Design: disposable GitHub-hosted VMs, no secrets, documented unrestricted network, scratch home.
T2 | S1-S4 | parent | done | Prepared diagnostic workflow and corrected Windows release selection; commit pending.
T3 | S1-S4 | independent verify + parent | in_progress | Local safety and syntax checks passed; independent diagnostic review found no blocker. Hosted run pending.

## Log
L1. User original request: "hay que comprobar eso"; "es que no tengo ninguna maquina desechable... no se puede con CI/CD?"; "SI" to preparation for Windows and Linux before push.
L2. Prior Linux network/filesystem confinement was denied. Hosted disposable VMs protect the user machine but do not establish offline confinement; this separate CI experiment cannot close the earlier confinement-specific task. Full-preset side effects and network endpoints remain unknown; no secrets or persistence credentials are passed.
L3. Draft workflow and PowerShell test written. PowerShell parser exits 0; local non-hosted execution refuses with exit 1 before side effects. ASSESS escalated item 5; native risk unassessable due undeclared untracked paths. No hosted execution performed.
L4. Independent verifier found Windows could select checkout dist instead of public assets, assertions were too weak, and full-preset network destinations remain unknown. Parent modified Windows staging to fetch the exact public assets and strengthened MCP assertions; managed marker and exact skill expectations remain unknown. The verifier also reported unintended /tmp log writes outside the project; do not touch those paths without authorization.
L5. User explicitly authorized: "subir y ejecutar esa primera prueba" after being informed that it is diagnostic only, runs with Internet access, may download other dependencies, and cannot prove full correctness. Network destinations beyond GitHub release assets remain unknown; no secrets are deliberately supplied. Push to fix/release-defaults triggers the diagnostic; future matching pushes retrigger it. No merge or release publication authorized.
L6. Independent follow-up found no concrete safety or execution blocker for the authorized diagnostic. It confirmed Windows now selects the explicit public assets and checks both hashes; AGENTS and skill assertions are still partial, and network destinations unknown. PowerShell syntax and non-hosted guard checks passed. Native review inspect returned native-status-unavailable (inconsistent unrelated target status); no native review approval is claimed.
