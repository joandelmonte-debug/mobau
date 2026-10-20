# 43 · Planes, perfiles y acceso al valor de Mobau

> **Aplicado y registrado:**
> - **T1** (`20261020120000`), el 2026-10-19;
> - **T3**, habilitación manual de `e2a655c1`, el 2026-10-19 a las 17:02:51 UTC; evento de habilitación 1;
> - **T4** (`20261020120100`): COMMIT el 2026-10-20 a las 09:03:39 UTC y registro a las 09:04:09 UTC. Quedan 33 migraciones.
>
> **Interfaz T2** publicada el 2026-10-20 (commit `19cc646`).
>
> **CC1** (Gratis sin proyectos, nombre y apellidos, permisos de moodboards): D3-B, D4 y D5 están versionadas aquí, pero **todavía no se han aplicado**. Cuando se apliquen se anotarán en «Registro de aplicación».
>
> Pagos y suscripciones quedan fuera de este punto: todo el acceso es `manual_pilot` con auditoría, y `subscription` es solo un valor reservado.

Proyecto Supabase: mobau-pilot (`skcoxtdppdcietgojdal`).
Cloudflare Pages: proyecto `mobau-pilot`, detrás de Access.

## Qué hace

- **Plan efectivo.** Lo determinan `profiles.plan` y `plans.includes_professional_tools`. La función INVOKER `my_professional_access()` lo comprueba. El plan solicitado nunca da acceso.
- **Gratis:**
  - sin precios, selección, proyectos, presupuestos ni solicitudes;
  - con CC1, tampoco puede leer proyectos ni solicitudes;
  - los datos se conservan ocultos y vuelven si la cuenta recupera un plan.
- **Individual y Estudio:**
  - precios publicados, selección, proyectos y solicitudes;
  - límite de proyectos activos, con bloqueo de fila antes de contar.
- **Nombre y apellidos** (D4): `first_name` y `last_name` son la fuente; un trigger calcula `professional_name`. Los perfiles anteriores conservan su nombre.
- **Moodboards** (D5):
  - `anon` no tiene ningún privilegio;
  - `authenticated` solo tiene SELECT, INSERT y UPDATE.

## Archivos

| Archivo | md5 |
|---|---|
| `migrations/20261020120000_43_d1_preparacion.sql` (T1, aplicada) | `7a50ed85b5561b057b205f5369679b89` |
| `migrations/20261020120100_43_d2_activacion.sql` (T4, aplicada) | `1482715a3557737763e27c60733b7201` |
| `migrations/20261020130000_43_d3_gratis_sin_proyectos.sql` (D3, opción B) | `e3062edb95099ae04f208881cf29c764` |
| `migrations/20261020130100_43_d4_nombre_apellidos.sql` (D4) | `23acb265cdd7741a44bad3e0cfd0e849` |
| `migrations/20261020130200_43_d5_moodboards_permisos.sql` (D5) | `77f7349831c6fdfd20068c009c60c466` |
| `rollback/20261020120000_43_d1_preparacion.rollback.sql` | `c0aeb415b682b3ad91f4e2fe6864da10` |
| `rollback/20261020120100_43_d2_activacion.rollback.sql` | `8660569229611f7d774c2462b95888d0` |
| `rollback/20261020130000_43_d3_gratis_sin_proyectos.rollback.sql` | `8962d70597b6441e7af99cbc5417eb68` |
| `rollback/20261020130100_43_d4_nombre_apellidos.rollback.sql` (R-D4C; la que se usa) | `2f0a3f60d05299a49fba26af747afd65` |
| `rollback/20261020130100_43_d4_nombre_apellidos.sin_copia.rollback.sql` (solo como referencia) | `d878c4122ecef3cc8a25bce48cb3892f` |
| `rollback/20261020130200_43_d5_moodboards_permisos.rollback.sql` | `140abd43233ef22ccb8e68fb1795d3fc` |
| `habilitacion/43_t3_habilitacion_e2a655c1.sql` (aplicado) | `744bea9195d3c955b28d0301d8f02876` |
| `habilitacion/43_t3_reversion_e2a655c1.sql` | `39589f58dd1d071091890436e6d4c366` |

Las pruebas, los ensayos y los mocks están en `tests/43/`. Nada de `supabase/` se publica: el build de Pages solo copia lo que lista `scripts/pages-manifest.txt` y rechaza `supabase/*`, `.sql` y `.md`.

## Reglas de ejecución

- **Ejecución.** Cada archivo se ejecuta como `postgres`, con el envoltorio que comprueba su md5 (MB997 si no coincide). Si falla o la respuesta es ambigua, se para, no se reintenta y se lee el estado.
- **Registro.** Cada migración se registra en `supabase_migrations.schema_migrations` (solo `version` y `name`), en una llamada aparte y únicamente después de confirmar su COMMIT.
- **Recuperaciones.** Nunca se borran filas de `schema_migrations`. Cada recuperación aplicada se registra como migración nueva:
  - con versión propia (marca UTC posterior a la última registrada) y nombre propio, por ejemplo `43_d3_revertir_gratis_sin_proyectos`;
  - con su copia en `migrations/`.

  Después de una recuperación vuelve el comportamiento, pero el número de migraciones sube en uno.
- **Volver a aplicar** una migración revertida también es una migración nueva.

## Orden de CC1

1. **Fase 0:** ensayo P3-R.
2. **Fase 1:**
   - versionado en este repositorio;
   - dos commits locales;
   - build local.
3. **Fase 2:**
   - lectura previa;
   - D3-B, su lectura y su registro;
   - D4, su lectura y su registro;
   - D5, su lectura y su registro;
   - lectura posterior.
4. **Fase 3:**
   - commit con este registro;
   - push;
   - comprobación de Pages;
   - C3.

D4 debe estar aplicada antes de publicar la web CC1, porque esa web escribe `first_name` y `last_name`. La web T2 es compatible con D3-B, D4 y D5.

**Plazo.** Desde el COMMIT de D3-B hasta que Pages sirve CC1, 20 minutos como máximo. Si se supera, se para y se informa. No hay reversión automática: cada opción necesita su propia autorización.

## Recuperación

1. **Interfaz primero:** `git revert` del commit de CC1 y push.
2. **D3 y D5:** son independientes. Cada una con su lectura y su registro como migración nueva.
3. **D4:** solo después de que Pages sirva la web revertida, con R-D4C.
   - R-D4C copia nombre, apellidos y `professional_name` a `mobau_private.professional_name_parts_backup`, con RLS, sin políticas y sin permisos de cliente, antes de quitar las columnas.
   - Durante la transacción bloquea las escrituras en `professional_profiles`, con un `lock_timeout` de 10 s.
   - Se detiene si la copia ya existe.

**Limitación temporal.** Mientras la web T2 conviva con D4, un perfil que ya tenga nombre y apellidos no puede cambiar su nombre: el trigger lo recalcula desde las partes y no da error. Por eso la edición de perfiles queda en pausa hasta el COMMIT de R-D4C.

**Restauración de las partes** desde la copia: es una operación aparte, todavía no preparada, y necesita su propia autorización.

## Ensayos y comprobaciones

| Prueba | Archivo (`tests/43/`) | Resultado |
|---|---|---|
| P2: T1 + T4, suite y recuperación | `P2_ensayo_43.sql` (`5fd2fbea…`), `P2-S_suite_43.sql` | 53/53; la huella final es igual a la inicial |
| C2: suite después de T4 | `C2_suite_43.sql` (`9a6b9595…`) | 57/57 y lecturas idénticas |
| C2-R1: concurrencia real (S1 en el editor, S2 en paralelo) | `C2-R1_S1_editor.sql`, `C2-R1_S2.sql` | S2 esperó 15,88 s; 2 activos como máximo |
| P3b: D3-B + D4, suite P3-S y recuperación | `P3b_ensayo_cc1.sql` (`bdf388e8…`) | 29/29, `cambia=t identico=t` |
| P3-M: D5 y recuperación | `P3M_ensayo_moodboards.sql` (`08c409f9…`) | 8/8, `identico=t` |
| P3-R: R-D4C | `P3R_ensayo_rd4c.sql` (`eb742767…`), `P3R_lectura.sql` (`9f1fde5a…`) | 4/4, `identico=t`; lecturas idénticas |
| P1: mocks de la interfaz | `interfaz/pruebas-p1-cc1.html` | 131/131 |

Lecturas: `43_lectura.sql` y `43_lectura_publicacion.sql`. Los generadores de los ensayos están en `tests/43/herramientas/`.

## Registro de aplicación de CC1

Pendiente.

## Fuera de este punto

- Pagos y suscripciones.
- El hallazgo de privilegios de `anon` y `authenticated` en otras tablas, que tiene su propio punto de seguridad.
- La limpieza de los proyectos de una cuenta Gratis de prueba, que es una decisión aparte.
