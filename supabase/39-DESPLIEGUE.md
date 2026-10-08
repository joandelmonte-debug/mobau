# 39 · Moderación de propuestas de productos

> **01–04 EJECUTADAS el 2026-10-06** (10:19–11:25 CEST), con autorización
> expresa paso a paso.
>
> Validación:
> - 39 moderación: **80/80**;
> - regresión de 38-C: **74/74**;
> - regresión de 38-B: **50/50**.
>
> Ninguna incidencia en la base de datos. No hay admins, MFA ni interfaz de
> moderación todavía.
>
> **Paquete de precios aplicado el 2026-10-06:**
> - 39-05 aplicada y registrada como `20261006120000`;
> - 39-06 aplicada y registrada como `20261006120100`.
>
> Pruebas:
> - 39-06 privacidad: **28/28**;
> - 39-05 superficie: **29/29**;
> - 39 moderación: **80/80**;
> - 38-C RLS: **74/74**;
> - 38-B RLS: **50/50**;
> - total: **261/261**.
>
> Huella final: sin cambios de datos; solo los cambios previstos en
> políticas y permisos de `product_prices` y 22 migraciones. **R1 y R2:
> cerrados.**

Mobau revisa las propuestas que envían los distribuidores verificados
(38-C) y decide: **aprobar** la propuesta exacta, **solicitar cambios** o
**rechazar**. Mobau no edita ningún campo del distribuidor.

## Estado de ejecución

| | |
|---|---|
| Ventana | 2026-10-06, 10:17 CEST, en un horario de poco uso. El piloto no se usó durante la ventana |
| Ejecutado por | Conexión de Supabase de la sesión de trabajo, rol `postgres`, con autorización expresa de cada paso |
| PostgreSQL | 17.6 |
| Integridad | Antes de enviar cada archivo se comprobó su MD5 frente al aprobado; los 11 coincidieron |

| Paso | Hora (CEST) | Resultado |
|---|---|---|
| 1 · Huella previa | 10:19–10:20 | Conforme. Dos correcciones de expectativa en la redacción del plan, CE1 y CE2 (ver abajo); ninguna diferencia en la base de datos |
| 2–3 · 39-01 | ≈10:26 | Aplicada, registrada y verificada |
| 4–5 · 39-02 | ≈10:31 | Aplicada, registrada y verificada |
| 6–7 · 39-03 | ≈10:41 | Aplicada, registrada y verificada |
| 8–9 · 39-04 | ≈10:45 | Aplicada, registrada y verificada |
| 10 · Pruebas de 39 | ≈11:05 | 80/80 |
| 11 · Regresiones | ≈11:21–11:24 | 38-C 74/74 · 38-B 50/50 |
| 12 · Huella final y avisos | ≈11:25 | Idéntica a la de después de 39-04; avisos como en CE2 |

## Migraciones aplicadas

| Versión | Nombre registrado | Archivo |
|---|---|---|
| `20261005130000` | `39_01_mobau_admins` | `migrations/20261005130000_39_01_mobau_admins.sql` |
| `20261005130100` | `39_02_moderation_read` | `migrations/20261005130100_39_02_moderation_read.sql` |
| `20261005130200` | `39_03_moderation_triggers` | `migrations/20261005130200_39_03_moderation_triggers.sql` |
| `20261005130300` | `39_04_moderate_function` | `migrations/20261005130300_39_04_moderate_function.sql` |
| `20261006120000` | `39_05_catalog_published_prices` | `migrations/20261006120000_39_05_catalog_published_prices.sql` (paquete de precios · A) |
| `20261006120100` | `39_06_product_prices_privacy` | `migrations/20261006120100_39_06_product_prices_privacy.sql` (paquete de precios · B) |

**Forma de ejecución:**
- Cada archivo se envió completo y literal, en una sola llamada, con su
  `BEGIN … COMMIT`.
- El registro en `supabase_migrations.schema_migrations` se hizo aparte,
  igual que en 38-B y 38-C (`version`, `name`; el resto a null). Cada
  inserción devolvió exactamente una fila.
- Registro final: **20 migraciones**, la última `20261005130300`, sin
  versiones mal formadas.
- Paquete de precios · A: 39-05 se ejecutó y registró de la misma forma.
  Registro tras A: **21 migraciones**, la última `20261006120000`.
- Paquete de precios · B: 39-06 se ejecutó y registró de la misma forma.
  Registro tras B: **22 migraciones**, la última `20261006120100`.
- Los SQL se conservan sin cambios, incluida la cabecera «PROPUESTA NO
  EJECUTADA»: son el artefacto que se aprobó y se ejecutó.

**MD5 de `prosrc` (esperado = real en las 9 funciones):**

| Función | Tipo | MD5 |
|---|---|---|
| `is_mobau_admin` | DEFINER | `05ea88e1c5e9d52585bbf477517e6098` |
| `mobau_admin_session` | DEFINER | `bf244e9e2550e0db8566c07b8d385f39` |
| `mobau_moderation_proposal_id` | DEFINER | `2f52ff63d67359cd7e74759a90f601db` |
| `mobau_moderating` | INVOKER | `05d24c51491e885059258b2624123f28` |
| `transition_proposal_status` | INVOKER | `19d26a925b9d97c89715254f219fbe7e` |
| `validate_proposal_changes` | INVOKER | `e5597c62fdd46f5db7c6ce40b82f06a6` |
| `log_proposal_event` | DEFINER | `248a79c97a2130b555c9cac904c36ad0` |
| `products_before_insert` | INVOKER | `33b25707669b8b29bcc788547052e1a6` |
| `moderate_product_proposal` | DEFINER | `a7b6b6405b93207fc9535fb14eaa7e02` |

Todas tienen `search_path=""` y propietario `postgres`. Ninguna es
ejecutable por `anon`.

## Resultado

**Objetos nuevos:**
- `mobau_admins` y `mobau_moderation_context`:
  - vacías;
  - RLS activada y sin políticas;
  - la ACL solo contiene a `postgres`;
  - sin ningún privilegio para `anon`, `authenticated` ni `service_role`.
- 5 funciones nuevas (tabla anterior).
- 3 políticas `SELECT` para `authenticated` condicionadas a
  `is_mobau_admin()`: `product_proposals_select_mobau`,
  `products_select_mobau` y `proposal_events_select_mobau`.
  - Total: 47 políticas; las 44 previas no cambian (MD5
    `c33a644090d97f1b671ca6567225f96d`).
- `product_proposals.created_product_id` (`text`, nullable), con la clave
  ajena a `products` y la restricción
  `product_proposals_created_product_only_create_approved`.
  - `authenticated` no puede escribirla.

**Objetos modificados:**
- `transition_proposal_status`, `validate_proposal_changes`,
  `log_proposal_event` y `products_before_insert`, con la rama de Mobau.
  Fuera de la moderación se comportan como antes (38-C 74/74, 38-B 50/50).

**Sin cambios:**
- Datos de todas las tablas de negocio.
- Políticas, permisos, triggers, índices y el resto de funciones y
  restricciones.

## Correcciones de expectativa (no son incidencias)

Detectadas en el paso 1, antes de cualquier escritura, y autorizadas.
Corrigen la redacción del plan; no hubo ninguna diferencia en la base de
datos y el SQL no cambió.

- **CE1:** antes de 39, la línea `39:funciones nuevas y reemplazadas` de la
  huella muestra las 4 funciones de 38-C 04 que 39-03 reemplaza, con sus
  MD5 de entonces. Las otras 6 líneas `39:*` muestran `no existe`,
  `no existen` o `0`.
- **CE2:** tras 39, los avisos de seguridad son:
  - los previos (1 INFO y 3 WARN);
  - más 4 WARN por funciones SECURITY DEFINER ejecutables por
    `authenticated`: `is_mobau_admin`, `mobau_admin_session`,
    `mobau_moderation_proposal_id` y `moderate_product_proposal`;
  - más 2 INFO por RLS sin políticas en `mobau_admins` y
    `mobau_moderation_context`.

  `mobau_moderating` no genera ese aviso porque es INVOKER. **Confirmado en
  el paso 12.**

## Validación

```text
39 moderación:   80/80
38-C regresión:  74/74
38-B regresión:  50/50
```

**Cómo se ejecutaron:**
- Las tres, completas y literales, dentro de `BEGIN … ROLLBACK`.
- Las tres terminaron con su error `MB999`, que lleva los resultados.
- 38-C se ejecutó con el ajuste de una línea en R07 (aprobado como D1): R07
  cuenta las 44 políticas de 38-B y 38-C excluyendo por nombre las 3 de
  lectura de 39. El total real de 47 lo comprueba R01 de
  `39_moderation_checks.sql`.

**Nota sobre el detalle:** la salida de la herramienta recortó un tramo
intermedio del JSON en 39 (F03–A01) y en 38-C (P33–K07). El recuento
global, calculado por cada archivo, confirma que todos los casos pasan. Las
pruebas no se repitieron.

**Límites de las pruebas:**
- Son pruebas unitarias con JWT simulado: **no validan el MFA real**.
- No hay concurrencia real entre sesiones.

## Huella (paso 1 → final)

Consulta: `tests/39_huella.sql`, solo lectura, misma conexión en todas las
ejecuciones.

| Línea | Previa (paso 1) | Final (paso 12) |
|---|---|---|
| `tabla:products` | `22 / e9db4c5d7118c0d7952ac1a421e86a2b` | Idéntica |
| `tabla:product_prices` | `14 / 6d02be484c2e3117338e30dba931d9b7` | Idéntica |
| `tabla:distributors` | `7 / bedbfda827fa39797f0f8ddb2f969d84` | Idéntica |
| `tabla:distributor_profiles` | `1 / d25725806f93a79e119cc80a749238a8` | Idéntica |
| `tabla:product_proposals (sin created_product_id)` | `0 / d41d8cd98f00b204e9800998ecf8427e` | Idéntica |
| `tabla:proposal_events` | `0 / d41d8cd98f00b204e9800998ecf8427e` | Idéntica |
| `tabla:profiles` | `7 / 094bbc11121c9578171aa8229c7abcdd` | Idéntica |
| `tabla:categories` | `6 / 30118e3ea789a081c8d18304aa829a58` | Idéntica |
| `tabla:projects` | `11 / 5e15ae2ef32546ec52c8de1b599f31c0` | Idéntica |
| `tabla:project_products` | `32 / 07d16ce71bfa020104c425198a04bcc8` | Idéntica |
| `tabla:rfqs` | `2 / 81133ec3d03ffa20f34379bc335299d5` | Idéntica |
| `politicas:previas` | `44 / c33a644090d97f1b671ca6567225f96d` | Idéntica |
| `permisos:tabla` | `265 / ea3d8bd0ba341e5e8eda898bf8d0a3fa` | Idéntica |
| `permisos:columna` | `932 / 53bc445803418132c2be0d23772c9101` | Idéntica |
| `funciones:previas` | `11 / f7ac297c3d2711ec0f46ce8ae613744c` | Idéntica |
| `triggers:public` | `18 / c55ba02dc9372c165e5b73c3280cbeb4` | Idéntica |
| `constraints:previas` | `89 / a242a32efdba8d0fc935597217ef9c1f` | Idéntica |
| `constraints:product_prices` | 9 restricciones | Idéntica (sin `rls39_fallo_simulado`) |
| `indices:public` | `28 / 88f4931cd1c3b2fc0b7cc9d3bead3584` | Idéntica |
| `politicas:public (todas)` | `44 / c33a6440…` | `47 / 77e501e24bdd8b4af3dd2cc025d23c5f` (cambio esperado) |
| `constraints:product_proposals` | 20 | 22 (cambio esperado: la clave ajena y la restricción nuevas) |
| `columnas:product_proposals` | 19 | 20 (cambio esperado: `created_product_id`) |
| `migraciones registradas` | `16 / 20261005120000` | `20 / 20261005130300` (cambio esperado) |
| `39:*` | No existen (CE1) | Objetos de 39 con los valores esperados; admins: 0 en el paso 12; desde A9 (alta del primer admin real), `39:tabla mobau_admins (filas)` se compara con la línea base tomada después de A9, no con 0; contexto 0 |
| `propuestas por estado` / eventos de Mobau / restos `rls39` | `ninguna` / 0 / 0 | Idénticos |

**Pruebas de comportamiento:** `tests/38b_rls_checks.sql`,
`tests/38c_rls_checks.sql`, `tests/39_05_catalog_prices_checks.sql`,
`tests/39_06_prices_privacy_checks.sql` y `tests/39_moderation_checks.sql`
se ejecutan siempre en una transacción revertida (`BEGIN … ROLLBACK`, error
final `MB999`) y no dejan datos. Las de 39 no suponen que `mobau_admins`
esté vacía: toman al empezar una línea base completa de la tabla y
comprueban al final que sigue idéntica. 38-B y 38-C no dependen de
`mobau_admins`. La huella es solo lectura.

**Comprobación adicional del paso 12:**
- 0 restos de 38-B y 38-C (`rls38%`, líneas `rls38b-aux`, RFQ de prueba,
  propuestas sintéticas de 38-C);
- 0 roles de prueba.

**Avisos de seguridad:**

| Momento | INFO | WARN |
|---|---|---|
| Antes (paso 1) | RLS sin políticas: `rfq_distributors` | SECURITY DEFINER ejecutable por `authenticated`: `is_supplier`, `my_verified_distributor_id` · protección de contraseñas filtradas desactivada |
| Después (paso 12) | Los mismos, más `mobau_admins` y `mobau_moderation_context` | Los mismos, más `is_mobau_admin`, `mobau_admin_session`, `mobau_moderation_proposal_id` y `moderate_product_proposal` |

Coinciden exactamente con CE2. `mobau_moderating` no aparece.

## Incidencias

Ninguna en la base de datos. Solo las dos correcciones de expectativa (CE1
y CE2), en la redacción del plan.

## Aviso operativo

```text
Las pruebas de 39 toman bloqueos breves sobre product_prices.
No ejecutar el archivo de pruebas mientras el piloto esté en uso.
```

Las pruebas A01, A02 y C13 añaden y retiran, dentro de su subtransacción,
una restricción `NOT VALID` en `product_prices`. Mientras dura (unos
milisegundos), la tabla queda bloqueada para otras sesiones.

## Regla de producto

Mobau:
- **aprueba exactamente la propuesta enviada**: aplica lo que el
  distribuidor propuso, sin añadir ni cambiar nada;
- **solicita cambios o rechaza con motivo**: el mensaje es obligatorio y
  el distribuidor lo ve en su propuesta;
- **no modifica ni sustituye campos del distribuidor**: la única vía es
  `moderate_product_proposal(proposal_id, decision, message,
  expected_version)`, que no acepta campos de producto;
- **no puede aprobar, pedir cambios ni rechazar propuestas de su propia
  empresa** (`distributor_profiles` en cualquier estado) **ni propias**
  (`author_id`): `42501` con el hint `self_moderation_forbidden`;
- **aplica una propuesta `create` como producto en `draft`**
  (`publication_status = 'draft'`, enlazado con `created_product_id`). Nunca
  se publica automáticamente;
- **aplica una propuesta `update` solo en los campos propuestos**;
- **bloquea los conflictos en campos propuestos**:
  - si un campo propuesto, la subcategoría (cuando hay una nueva) o el
    precio (si se propuso) cambió en el catálogo desde el envío, devuelve
    `ok:false` y `snapshot_conflict`;
  - si la versión no coincide, devuelve `version_conflict`;
  - ambos quedan auditados como `submitted → submitted`;
- **no fuerza la aplicación**: ante un conflicto, Mobau solicita cambios o
  rechaza.

**Precio** (comportamiento de 38-C sin cambios):
- se aplica solo si se propuso, tal cual;
- un estado no publicado puede llevar importe o no;
- nunca se convierte en `published`;
- `currency = 'USD'` e `includes_itbis = true`, según las restricciones.

**Visibilidad de `product_prices`.** Lo que sigue (hasta R3) describe el
estado **anterior a 39-06**, comprobado el 2026-10-06 en modo lectura
simulando cada rol dentro de `BEGIN … ROLLBACK`. Era un **riesgo real, no
aceptado**, y quedó cerrado con el paquete de precios (ver «Estado tras
B» y «Modelo final»).
- **Regla vigente:** una fila de precio es visible exactamente cuando su
  producto es visible para quien consulta
  (`product_prices_select_authenticated`: `EXISTS (… products p WHERE p.id
  = product_prices.product_id)`, evaluada con la RLS de `products`).
  - No filtra por `price_status`.
  - No restringe columnas: `anon` y `authenticated` tienen `SELECT` sobre
    las 13 columnas.
- **Qué ve hoy cada rol:**
  - `anon`: ninguna fila (no tiene política);
  - profesional, u otro distribuidor: todas las columnas de los precios de
    cualquier producto publicado, con cualquier `price_status`;
  - distribuidor verificado: además, sus propios productos no publicados;
  - admin con `aal2`: todos los precios (`products_select_mobau`),
    deducido de las políticas.
- **La interfaz** solo muestra el importe con `price_status =
  'published'`. Es una regla de presentación y **no** es un control de
  acceso.

**Riesgos y decisiones (2026-10-06):**
- **R1 · Importe no publicado (riesgo real).** Si un producto publicado
  tiene un precio `quote_required`, `pending_confirmation` o `unavailable`
  con importe guardado, hoy cualquier usuario autenticado puede leer ese
  importe por la API.
  - Hoy hay 0 casos, pero 39 puede crearlos al aprobar propuestas.
  - **Decisión:** ese importe no debe ser legible por profesionales ni por
    distribuidores ajenos, aunque esté guardado. La interfaz no puede ser
    el único control.
- **R2 · Campos internos (riesgo real).** `price_reference`,
  `price_reference_date`, `price_note` y `price_source` son internos.
  - Hoy son legibles en 9 filas para un profesional, 8 de ellas de otros
    distribuidores.
  - **Decisión:** solo deben leerlos el distribuidor propietario, un admin
    de Mobau con MFA y `postgres`.
- **R3 · Catálogo público.** **Decisión:** se mantiene como está; `anon` no
  consulta `product_prices`. No se abren precios públicos por la API ni se
  crea una vista o RPC pública para `anon`.

**Corrección: paquete de precios** (aprobado y **aplicado**: A, pasos
1–3; B, pasos 4–5). La
privacidad de la tabla **no se aplica aislada**: rompería el catálogo del
profesional. Va en un paquete coordinado, en este orden:
1. **39-05 · `catalog_published_prices`**
   (`20261006120000_39_05_catalog_published_prices`). Solo añade la
   superficie segura.
   - Solo para `authenticated` y con sesión (`auth.uid()`); `public` y
     `anon` sin EXECUTE. SECURITY DEFINER, propietario `postgres`,
     `search_path = ''`.
   - Devuelve el precio de los productos con `publication_status =
     'published'` y un `price_status` válido.
   - **7 columnas fijas:** `product_id`, `price_amount`, `currency`,
     `price_status`, `includes_itbis`, `itbis_rate` y **`es_demo`**
     (booleano calculado como `price_source = 'demo'`).
   - **`price_amount` solo con `price_status = 'published'`.** Con
     `quote_required`, `pending_confirmation` o `unavailable` devuelve el
     estado y `price_amount = NULL`, aunque haya importe guardado.
   - **`price_source`, `price_reference`, `price_reference_date` y
     `price_note` no salen al cliente.**
   - Producto sin precio: ninguna fila («bajo cotización», como hoy).
   - Límites: como máximo 200 ids; de 1 a 1000 filas por llamada;
     paginación por `product_id` con `p_after` de 200 caracteres como
     máximo. No acepta columnas, estados, SQL ni filtros libres.
2. **`script.js`:** el catálogo, la ficha, la selección y los proyectos
   leen precios por esa función y conservan el `price_status` que
   devuelve. Los textos no cambian:
   - `published`: importe + «ITBIS incluido»;
   - `quote_required` o sin precio: «Precio bajo cotización»;
   - `pending_confirmation`: «Precio pendiente de confirmación»;
   - `unavailable`: «Precio no disponible».

   El aviso de «precio de demostración» usa `es_demo`.
3. **Verificación del catálogo con Spectro** en el piloto, antes de cerrar
   la tabla.
4. **39-06 · privacidad de `product_prices`**
   (`20261006120100_39_06_product_prices_privacy`).
   - El distribuidor verificado, solo sus precios: todas las columnas,
     incluidos estados no publicados y campos internos.
   - Un admin con `aal2`, todo, para moderar.
   - El profesional, ninguna fila directa.
   - `anon`, sin permisos.
   - Nadie escribe directamente (sin cambios desde 38-B).
5. Pruebas de precios y regresiones ajustadas de 38-B, 38-C y 39.

**No se aplica 39-06 antes de verificar `script.js` en el catálogo.**

**Estado tras A:**

Durante A la tabla product_prices conserva temporalmente la política anterior.
Los riesgos R1 y R2 siguen abiertos hasta aplicar 39-06.
No se deben moderar propuestas reales con precio durante esa ventana.

| Paso | Resultado |
|---|---|
| Huella previa (nueva línea base, con `precios:*` aparte) | Tomada. Función: «no existe»; políticas y permisos de `product_prices` en su estado previo; 47 políticas (`77e501e2…`) |
| 39-05 aplicada, registrada (`20261006120000`) y verificada | Aplicada y registrada como `20261006120000_39_05_catalog_published_prices`. Firma `catalog_published_prices(text[],text,integer)`; DEFINER; `search_path = ''`; propietario `postgres`; 7 columnas; MD5 de `prosrc` `38e5e597619fd290b2255e8d9c224453` |
| `tests/39_05_catalog_prices_checks.sql` | **29/29** |
| Huella posterior y final | Sin cambios de datos: todas las líneas `tabla:*` idénticas. Solo cambian la nueva función y la migración 21. Sin restos de prueba, admins ni contextos |
| `script.js` desplegado en el piloto | Hecho: commit `1400d83` en `origin/master`, desplegado por Cloudflare Pages |
| Verificación del catálogo con Spectro (mismos importes, «bajo cotización» donde corresponde y aviso de demostración) | Correcta: catálogo, fichas, selección y detalle de proyecto usan `catalog_published_prices` (HTTP 200); ninguna llamada directa a `/rest/v1/product_prices`; la RPC devuelve solo las 7 columnas; precios publicados, bajo cotización, demo, subtotales y cantidades correctos; sin errores en consola |
| 39-06 | Aplicada después de la verificación (ver «Estado tras B») |
| Avisos de seguridad | 1 WARN más esperado: `catalog_published_prices`, DEFINER ejecutable por `authenticated` (intencionado). No se consultaron en este paso |

**Permisos de ejecución de `catalog_published_prices`** (comprobados tras
aplicar):
- `public`: sin EXECUTE;
- `anon`: sin EXECUTE;
- `authenticated`: EXECUTE autorizado;
- `service_role`: acceso operativo heredado/esperado. Viene de los permisos
  por defecto de Supabase; no es un rol de navegador ni de cliente y se
  decidió no revocarlo.

**Estado tras B** (R1 y R2 cerrados):

| Paso | Resultado |
|---|---|
| Huella previa a 39-06 (nueva línea base) | Tomada. `projects` y `project_products` cambiaron respecto a la huella final de A por el uso normal del piloto durante la verificación (confirmado; no es una incidencia) |
| 39-06 aplicada, registrada (`20261006120100`) y verificada | Aplicada y registrada como `20261006120100_39_06_product_prices_privacy`. Validación final superada: 4 políticas en `product_prices`, 48 en public, `anon` sin permisos y `authenticated` solo con SELECT |
| `tests/39_06_prices_privacy_checks.sql` | **28/28** |
| `tests/39_05_catalog_prices_checks.sql` (repetida con la tabla cerrada) | **29/29** |
| `tests/39_moderation_checks.sql` (R01 = 48) | **80/80** |
| Regresiones 38-C (R06, R07 = 43) y 38-B (V05, P01) | **74/74** · **50/50** |
| Total | **261/261** |
| Restos entre pruebas | Ninguno: 0 datos auxiliares, admins, contextos y restricciones temporales |
| Huella posterior y final | Sin cambios de datos: todas las líneas `tabla:*` idénticas a la línea base previa a 39-06. Solo cambian las políticas y los permisos de `product_prices` (políticas `b80ef51e…`), las políticas en public (47 → 48, `7d74acfd…`) y las migraciones (21 → 22). La huella final después de las pruebas es idéntica a la posterior a 39-06 |
| Rollback de 39-06 | No ejecutado |

**Modelo final de acceso a precios:**
- **`anon`:** sin acceso a `product_prices` ni a `catalog_published_prices`.
- **Profesional:** sin lectura directa de `product_prices`; el catálogo
  usa `catalog_published_prices`.
- **Distribuidor verificado:** solo sus propios precios, incluidas las
  columnas operativas necesarias (estados no publicados y campos internos)
  (`product_prices_select_own`).
- **Admin de Mobau con AAL2:** todos los precios, para moderar
  (`product_prices_select_mobau`).
- **Escritura:** ningún cliente modifica `product_prices` directamente.
  Los cambios operativos pasan por propuestas y moderación
  (`moderate_product_proposal`), que actualiza la tabla de forma controlada.

**No se moderarán propuestas reales con precio hasta que el paquete completo,
incluidas 39-05, script.js y 39-06, esté aplicado y probado.**

El paquete ya está aplicado y probado. Además, moderar propuestas reales con
precio requiere el primer admin, el MFA real y la interfaz de moderación.

## Subcategoría nueva

- Solo se incorpora si Mobau aprueba la propuesta exacta.
- Se añade a `categories.subcategories` dentro de la misma transacción que
  la aprobación. Si algo falla, no queda.
- No se duplica: si ya existe con otras mayúsculas o espacios, se reutiliza
  la existente (`existing`).
- Una vez aprobada, queda disponible en los filtros del catálogo.
- Si no encaja, Mobau solicita cambios o rechaza. **No la sustituye
  unilateralmente** por otra.

## Seguridad y operación

- **Primera cuenta admin pendiente:** `hola@mobau…`. Su alta es un paso
  aparte, con autorización y con un script revisado; todavía no se ha
  hecho.
- **MFA (`aal2`) obligatorio para moderar:** sin `aal2` no se lee la bandeja
  ni se puede decidir.
- **Todavía no hay** admins ni MFA activos (TOTP en Supabase Auth). La
  prueba MFA real está pendiente.
- **La interfaz de moderación** (consola y aviso en Mis productos) todavía
  no está implementada.
- **No ejecutar** `tests/39_moderation_checks.sql` mientras se usa el piloto.
- **No se moderarán propuestas reales con precio hasta que el paquete
  completo, incluidas 39-05, script.js y 39-06, esté aplicado y probado.**
- **Fuera de alcance:** no hay correo, automatizaciones, pagos, Stripe,
  Checkout, webhooks, Edge Functions ni cambios manuales en Cloudflare.
- La **auditoría de permisos heredados** (antes llamada «39-05») queda
  fuera de este ciclo. Los números 39-05 y 39-06 pasan al paquete de
  precios.

## Rollback

**Orden obligatorio:** 04 → 03 → 02 → 01. Cada archivo comprueba sus
condiciones y se niega si no es seguro. Después de cada rollback se borra
su fila de `schema_migrations` (con autorización) y se comprueba la huella.

| Archivo | Se niega si… | Qué hace |
|---|---|---|
| `rollback/20261005130300_39_04_moderate_function.rollback.sql` | Ya hay decisiones de Mobau registradas | Quita la función |
| `rollback/20261005130200_39_03_moderation_triggers.rollback.sql` | 04 sigue aplicada o alguna propuesta tiene `created_product_id` | Restaura el texto literal de 38-C 04 (comprobado por MD5) y quita la columna |
| `rollback/20261005130100_39_02_moderation_read.rollback.sql` | 04 sigue aplicada | Quita las 3 políticas (vuelve a 44) |
| `rollback/20261005130000_39_01_mobau_admins.rollback.sql` | 02, 03 o 04 siguen aplicadas, o hay admins | Quita las funciones y las dos tablas |

**Qué no debe revertirse cuando ya hay propuestas moderadas o productos
aplicados:**
- **No revertir 39-04 ni 39-03** si ya existe alguna decisión de Mobau.
  - Los rollbacks se niegan.
  - Los productos creados en `draft`, los cambios aplicados, los precios,
    las subcategorías añadidas y los eventos de auditoría **no se deshacen**
    quitando la función: quedarían datos sin la función que los explica.
  - Corregir eso requiere una decisión explícita, caso por caso.
- **No revertir 39-01** si hay admins dados de alta: se perdería el
  registro de altas y bajas.
- **Tras la primera decisión real, la salida segura no es el rollback**,
  sino una corrección nueva (fix forward), revisada y autorizada.

Durante este despliegue no hubo decisiones ni admins, así que el rollback
completo era limpio. **No se ejecutó ningún rollback.**

**Paquete de precios · A:**

| Archivo | Se niega si… | Qué hace |
|---|---|---|
| `rollback/20261006120000_39_05_catalog_published_prices.rollback.sql` | 39-06 está aplicada | Quita la función. **Antes** hay que volver a la versión anterior de `script.js` (no se puede comprobar desde la base de datos) |

**Paquete de precios · B:**

| Archivo | Se niega si… | Qué hace |
|---|---|---|
| `rollback/20261006120100_39_06_product_prices_privacy.rollback.sql` | Falta la confirmación explícita (línea comentada `mobau.reabrir_exposicion_precios = 'confirmo'`) o 39-06 no está como se aprobó | **Reabre R1 y R2.** Restaura la política y los permisos previos y comprueba el MD5 de las 47 políticas |

**Orden inverso:** 39-06 (con confirmación) → `script.js` anterior → 39-05.
Tras la primera moderación real con precio, el rollback de 39-06 expondría
esos importes: la salida segura es una corrección nueva (fix forward).

## Archivos

| Archivo | Contenido |
|---|---|
| `migrations/20261005130000_39_01_mobau_admins.sql` | Admins, contexto privado y funciones de autorización (`aal2`) |
| `migrations/20261005130100_39_02_moderation_read.sql` | 3 políticas de lectura para la consola |
| `migrations/20261005130200_39_03_moderation_triggers.sql` | `created_product_id` y rama de Mobau en 4 funciones de trigger |
| `migrations/20261005130300_39_04_moderate_function.sql` | `moderate_product_proposal` |
| `rollback/*.rollback.sql` | Rollback de cada migración (orden inverso) |
| `tests/39_moderation_checks.sql` | 80 pruebas en una transacción revertida |
| `tests/39_huella.sql` | Huella de solo lectura para comparar antes y después |
| `tests/38c_rls_checks.sql` | R07 ajustado para excluir las 3 políticas de lectura de 39 |
| `migrations/20261006120000_39_05_catalog_published_prices.sql` | Superficie segura de precios para el catálogo (7 columnas) |
| `rollback/20261006120000_39_05_catalog_published_prices.rollback.sql` | Rollback de 39-05 |
| `tests/39_05_catalog_prices_checks.sql` | 29 pruebas de la superficie, válidas antes y después de 39-06 |
| `tests/39_huella.sql` | (actualizada) `product_prices` y la función de 39-05 en líneas `precios:*` propias |
| `../script.js` | Precios del catálogo por `catalog_published_prices` |
| `migrations/20261006120100_39_06_product_prices_privacy.sql` | Privacidad de `product_prices` |
| `rollback/20261006120100_39_06_product_prices_privacy.rollback.sql` | Rollback de 39-06 (requiere confirmación explícita; reabre R1 y R2) |
| `tests/39_06_prices_privacy_checks.sql` | 28 pruebas de privacidad de `product_prices` |
| `tests/38b_rls_checks.sql`, `tests/38c_rls_checks.sql`, `tests/39_moderation_checks.sql` | Regresiones ajustadas a 39-06 (V05, P01; R06, R07 = 43; R01 = 48) |

**Nota (incorporación pendiente):** las migraciones 39-01 a 39-04, sus
rollbacks y la versión de `tests/38c_rls_checks.sql` con solo R07 ajustado
están aplicadas en Supabase, pero todavía no están en el repositorio.
Se incorporarán en un commit propio, con autorización aparte.

## Interfaz de moderación

Solo repositorio: no cambia políticas, funciones, migraciones ni datos.

| Archivo | Qué hace |
|---|---|
| `../moderacion.html` | Bandeja: «En revisión» por defecto; filtros de estado (nunca borradores), tipo y empresa; hasta 200 propuestas, las más antiguas primero |
| `../moderacion-propuesta.html?id=` | Detalle: comparación al enviar / actual / propuesto, precio, subcategoría nueva, historial y decisión |
| `../moderacion-acceso.js` | Puerta común y utilidades de pintado seguro |
| `../supabase-client.js` | Tipo de cuenta `mobau` (`profiles.role = 'admin'`), destino `moderacion.html`, sin alta profesional |
| `../nav-session.js` | Cabecera y menú de la cuenta de Mobau; «Moderación» solo con `mobau_admin_session().admin` |
| `../script.js`, `../producto.html` | Catálogo y ficha en solo lectura para la cuenta de Mobau. `script.js` filtra además `publication_status = 'published'` en la lista y en la consulta por ids: ni el distribuidor dueño ni Mobau con `aal2` ven borradores en el catálogo ni en la ficha, aunque `status` y `publication_status` dejen de coincidir |
| `../perfil-profesional.js` | `completeSignup()` no crea perfil profesional para la cuenta de Mobau |
| `../inscripcion-profesional.html` | La cuenta de Mobau va a `moderacion.html`: nunca ve ni envía el formulario profesional |
| `../distribuidor-productos.html` | «Decisiones recientes de Mobau» (30 días) y fecha de «Cambios solicitados» |

**Acceso:**
1. Sesión.
2. Profesional o distribuidor: «solo para el equipo de Mobau», sin más consultas.
3. `mobau_admin_session()` en el servidor.
4. Sin `aal2`: segundo factor con `auth.mfa.listFactors()`, `challenge()` y `verify()` sobre un factor TOTP **ya verificado**.
5. Nueva comprobación en el servidor: solo con `{ admin: true, aal2: true }` se leen propuestas.

El sitio **no** enrola factores: no usa `enroll` ni `unenroll`, ni muestra
QR, secreto o URI TOTP. Sin factor verificado, la consola muestra «La
verificación en dos pasos todavía no está configurada para esta cuenta.
Contacta con el equipo de Mobau.» El primer factor se configura fuera del
sitio, con un procedimiento local, temporal y autorizado aparte.

**Escritura:** solo `rpc("moderate_product_proposal", { p_proposal_id,
p_decision, p_message, p_expected_version })`, una llamada por decisión.
La consola nunca escribe directamente en `product_proposals`, `products`,
`product_prices`, `categories` ni `proposal_events`. Un producto nuevo
aprobado queda en borrador; la publicación sigue siendo manual.

**Pintado:** todo lo que propone el distribuidor se pinta con
`textContent`. Los enlaces solo admiten `http(s)` y se abren con
`target="_blank" rel="noopener noreferrer"`. La consola no carga imágenes.

**Aviso al distribuidor:** aprobadas y rechazadas de los últimos 30 días,
con el mensaje de Mobau. «Leído» solo en ese dispositivo (`localStorage`
`mobau_decisiones_vistas`). Sin correo, push ni SMS.

## Pendiente

Cada punto con su propia autorización:
1. Activar TOTP en Supabase Auth.
2. Alta del primer admin (`hola@mobau…`): cuenta, `profiles.role = 'admin'` y fila en `mobau_admins`.
3. Configurar su primer factor TOTP fuera del sitio (procedimiento local y temporal).
4. Prueba MFA real con una propuesta de prueba («Solicitar cambios», nunca aprobar) y su limpieza.
5. Incorporar 39-01 a 39-04 al repositorio.
