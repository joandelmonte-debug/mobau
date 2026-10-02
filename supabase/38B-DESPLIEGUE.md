# 38-B · Seguridad de servidor y visibilidad de productos

> **EJECUTADO el 2026-10-02.** Ver "Estado de ejecución" a continuación.
> El resto del documento describe el plan tal como se aprobó y ejecutó.

Despliegue, validación y rollback de las migraciones de 38-B en Supabase
(proyecto del piloto).

## Estado de ejecución — 2026-10-02

**Migraciones**
- 01, 02, 03 y 04 aplicadas en producción el 2026-10-02.
- Las cuatro figuran registradas una sola vez en
  `supabase_migrations.schema_migrations`, con la versión y el nombre de
  su archivo (`20261002090000` a `20261002090300`).
- Los SQL de migraciones y rollbacks se conservan sin cambios, incluida
  su cabecera "PROPUESTA NO EJECUTADA": son el artefacto que se aprobó y
  se ejecutó. Esta sección es la constancia de la ejecución.

**Pruebas RLS** (`tests/38b_rls_checks.sql`)
- 50 casos: **50 PASS, 0 FAIL**.
- Ejecutadas en una sola transacción que terminó en `ROLLBACK`.
- Huellas (recuento y MD5) idénticas antes y después de la prueba para:
  `products`, `product_prices`, `projects`, `project_products`, `rfqs`,
  `rfq_distributors` y `profiles`; las políticas de `pg_policies` del
  esquema `public`; y los permisos de tabla y de columna de `anon` y
  `authenticated` sobre las seis tablas de 38-B.
- No quedaron filas de prueba ni cambios persistentes.

**Copias de seguridad**
- Las copias previas a 38-B están fuera del repositorio porque contienen
  datos personales. No se versionan.

**Efectos funcionales confirmados por las pruebas**

| Efecto | Casos |
|---|---|
| Productos `published`: visibles para anónimos, profesionales y distribuidores | V01, V04, V06, V09, V11, M03 |
| Productos no publicados: no visibles para anónimos ni profesionales; visibles, con su precio, para el distribuidor verificado propietario | V02, V03, V07, V08, V10, V12–V14, P02–P04 |
| Productos y precios: `anon` y `authenticated` no pueden crearlos ni modificarlos | S07–S11, C11, C12, N03 |
| Profesionales: añaden a su proyecto solo productos publicados, editan cantidad y selección de sus líneas sin cambiar el producto, y crean RFQ solo sobre un proyecto propio sin líneas no publicadas seleccionadas | C01–C09, C14 |
| Distribuidores: no crean ni modifican proyectos ni líneas de proyecto, y no crean RFQs | S01–S04, S06 |
| `rfq_distributors`: sin escrituras de cliente | S12, C13 |
| Anónimos: no crean proyectos ni RFQs | N01, N02 |

**No cubierto por estas pruebas**
- Visibilidad para otro distribuidor verificado o para uno no
  verificado (las pruebas con identidades temporales quedaron excluidas).
- `DELETE` de productos y precios desde cliente, `UPDATE` de RFQs y
  acceso de un profesional a líneas de proyectos ajenos.

## Archivos

| Archivo | Contenido |
|---|---|
| `migrations/20261002090000_38b_01_products_publication_status.sql` | Columna `publication_status`, relleno explícito, índice y trigger espejo de `status` |
| `migrations/20261002090100_38b_02_products_visibility.sql` | Lectura de productos y precios según publicación y propiedad |
| `migrations/20261002090200_38b_03_supplier_write_lockdown.sql` | Sin escrituras de cliente en `products` y `product_prices`; distribuidor sin altas ni cambios en proyectos, líneas y solicitudes |
| `migrations/20261002090300_38b_04_projects_rfqs_guards.sql` | Líneas solo con productos publicados, `product_id` inmutable y guardas de RFQ |
| `rollback/*.rollback.sql` | Rollback exacto de cada migración (mismo prefijo) |
| `tests/38b_rls_checks.sql` | Pruebas de RLS (50 casos) en una transacción revertida, solo con cuentas reales existentes y sin modificarlas |
| `moderacion/38b_moderacion_manual.sql` | Publicar, revisar, pedir cambios y archivar desde Supabase |

Los prefijos de versión son los previstos. Si se aplican con la
herramienta `apply_migration`, Supabase asigna su propia versión: después
de aplicar, se renombra cada archivo para que coincida con
`list_migrations`. Las migraciones anteriores a 38-B (`phase0` a
`professional_profiles_type_add_particular`) solo existen en Supabase y no
se versionan aquí.

## Plan de ejecución (cada bloque con su propia aprobación)

**A. Migraciones**
1. Prechecks (abajo). Guardar la salida fuera del repositorio.
2. Aplicar `38b_01` → postchecks de 01. El archivo es una transacción
   atómica explícita (`BEGIN … COMMIT`): se ejecuta completo, de una
   vez, sin partirlo ni ejecutarlo por fragmentos. Si falla, no queda
   nada aplicado y **no se continúa con 02, 03 ni 04** (ver "Migración
   01" más abajo).
3. Aplicar `38b_02` → postchecks de 02. También es una transacción
   atómica explícita (`BEGIN … COMMIT`) que se ejecuta completa; valida
   las políticas antes y después y aborta si no cuadran. Si falla, no
   queda ningún estado parcial de visibilidad y **no se continúa con 03
   ni 04** (ver "Migración 02" más abajo).
4. Aplicar `38b_03` → postchecks de 03. Transacción atómica explícita
   (`BEGIN … COMMIT`), ejecutada completa; muestra una auditoría del rol
   ejecutor, comprueba el estado inicial, los permisos efectivos tras
   cada `REVOKE` y el estado final, y aborta si algo no cuadra. Si falla,
   **no se continúa con 04** (ver "Migración 03" más abajo).
5. Aplicar `38b_04` → postchecks de 04. Transacción atómica explícita
   (`BEGIN … COMMIT`), ejecutada completa; comprueba que 01 y 03 están
   aplicadas, el estado inicial, el permiso efectivo de UPDATE en
   `project_products` y el estado final, y aborta si algo no cuadra
   (ver "Migración 04" más abajo). 03 y 04 se aplican en la misma
   ventana: entre ambas siguen abiertos los huecos que cierra 04.

Cada migración corre en su propia transacción: si falla a medias, no
queda nada aplicado de esa migración. Si un postcheck no cuadra, se
detiene el plan y se pasa al bloque E.

**B. Validaciones post-migración (solo lectura)**
- Conteos 20 `published`/`active` y 2 `archived`/`archived`; 0 incoherentes.
- `updated_at` idéntico a la copia del precheck.
- Políticas, permisos por columna y funciones según los postchecks.

**C. Pruebas RLS**
- Ejecución inicial: `tests/38b_rls_checks.sql`, en una sola llamada.
  Debe terminar con el error controlado `MOBAU_38B_RLS total=50 ok=50 fallos=0`.
  Solo usa el distribuidor verificado real, un profesional real y
  anónimo; no modifica perfiles ni filas existentes.
- Fuera de la ejecución inicial: pruebas de "otro distribuidor
  verificado" y "distribuidor no verificado" (identidades temporales en
  `auth.users`). Requieren staging, cuentas de prueba o una aprobación
  específica; no se versionan todavía.

**D. Pruebas frontend**
- Batería de navegador (suites S, W2 y regresiones) contra la copia local
  con el Supabase simulado: no debe empeorar.
- Comprobación manual en el piloto (`mobau-pilot.pages.dev`), sin crear
  datos: catálogo (20 productos), ficha publicada, ficha archivada por URL
  (debe mostrar "No encontramos este producto"), selección, proyectos,
  cotización y panel de distribuidor.

**E. Rollback**
- Si falla cualquier paso: rollback en orden inverso (04 → 03 → 02 → 01)
  hasta el último paso correcto, con los archivos de `rollback/` (ver
  "Rollback exacto").

## Migración 01: ejecución y trigger de espejo

- **Transacción atómica explícita.** El archivo empieza con `BEGIN;` y
  termina con `COMMIT;`, con la validación `DO $$ … $$` dentro. Si
  cualquier sentencia falla, se revierten columna, restricción, relleno,
  índice, función, trigger y el estado de `trg_products_updated_at`
  (desactivarlo y reactivarlo también es transaccional).
- **No partirlo.** Se ejecuta el archivo completo en una sola llamada
  (editor SQL de Supabase o `execute_sql`). Nunca por fragmentos.
- **Si falla, el plan se detiene:** no se ejecutan 02, 03 ni 04.
- **Herramienta.** Ejecutar este archivo como una sola llamada en una
  herramienta que no envuelva automáticamente su contenido en otra
  transacción. Si se utiliza una herramienta de migraciones que ya
  garantiza una transacción por archivo, no ejecutar un `BEGIN`/`COMMIT`
  anidado: adaptar el mecanismo de ejecución sin partir el contenido,
  verificando antes que la herramienta mantiene la atomicidad completa.
- **Trigger de espejo** (`BEFORE INSERT OR UPDATE OF publication_status`):
  - en un INSERT nuevo sin `publication_status`, el valor por defecto
    `draft` genera `status = 'archived'`;
  - la moderación manual cambia siempre `publication_status`, nunca
    `status`;
  - las actualizaciones de nombre, descripción, imágenes o datos técnicos
    no disparan el trigger y no reescriben `status`;
  - tras 38-B ningún rol de cliente puede editar `status`;
  - `moderacion/38b_moderacion_manual.sql` incluye la comprobación de
    coherencia `publication_status = 'published'` ↔ `status = 'active'`.

## Migración 02: políticas combinadas, guardas y caché

- **Transacción atómica explícita** (`BEGIN … COMMIT`), con el mismo
  criterio de ejecución que 01: una sola llamada, sin fragmentos, sin
  `BEGIN`/`COMMIT` anidados.
- **Las políticas SELECT `PERMISSIVE` se combinan con OR.** Tras 02, un
  producto es visible si es `published` OR (usuario autenticado y
  distribuidor verificado propietario). Por eso **cualquier política
  SELECT adicional sobre `products`** (o una `FOR ALL`) podría abrir
  visibilidad inesperada.
- **Guardas dentro de la migración** (abortan toda la transacción):
  - antes: `products` tiene exactamente 1 política SELECT/ALL y es
    `catalogo_lectura_publica_productos`; `product_prices` tiene
    exactamente 1 y es `product_prices_select_authenticated`; existe
    `products.publication_status`;
  - después: `products` tiene exactamente 2 políticas SELECT/ALL,
    `products_select_published` (PERMISSIVE, anon y authenticated) y
    `products_select_own_distributor` (PERMISSIVE, solo authenticated), y
    ya no existe `catalogo_lectura_publica_productos`; `product_prices`
    tiene exactamente 1, `product_prices_select_authenticated`
    (PERMISSIVE, solo authenticated) y condicionada a `products`.
  - Los roles se comparan como conjuntos (`roles @> …` y `roles <@ …`),
    sin depender del orden en que Postgres guarde el array.
  - La migración valida estructura y dependencia declarada de `products`;
    la semántica exacta del filtro `EXISTS` se verifica mediante pruebas
    RLS por rol antes de aprobar el despliegue. El texto de la condición
    no se analiza dentro de la migración.
- **Caché del cliente.** RLS bloquea cualquier consulta nueva y el
  acceso por URL directa a un producto no publicado. Pero un navegador
  que ya descargó el catálogo antes de despublicar un producto puede
  conservarlo un periodo breve (`sessionStorage`, 60 s).
- **38-C** debe decidir si hace falta invalidar o reducir esa caché al
  habilitar la moderación activa.

## Migración 03: bloqueo de escrituras, permisos efectivos y guardas

- **Transacción atómica explícita** (`BEGIN … COMMIT`), mismo criterio
  de ejecución que 01 y 02. El rollback también va en `BEGIN … COMMIT`.
- **Quién puede aplicarla:** un rol de administración de Supabase capaz
  de retirar los permisos actuales de `products` y `product_prices`
  (por ejemplo `postgres`). Rol ejecutor, superusuario, propietarios
  (`pg_get_userbyid(relowner)`), permisos actuales y grantor son
  **solo auditoría**: se muestran en el precheck T0a y en un `NOTICE` al
  inicio de la migración, sin abortar por ellos.
- **La capacidad práctica queda demostrada por el resultado efectivo
  posterior al `REVOKE`, no por una inferencia previa incompleta sobre
  ownership.** Tras cada `REVOKE` la migración comprueba el **permiso
  efectivo** de `anon` y `authenticated` con `has_table_privilege`,
  `has_any_column_privilege` y `has_column_privilege` (todas las
  columnas, incluidas `status` y `publication_status`). Si queda
  cualquiera, lanza una excepción y se revierte toda la transacción.
- **Validaciones previas** (abortan): existe `publication_status` (01 aplicado); no existe
  `is_supplier()`; no existe ninguna de las cinco políticas objetivo; RLS
  activa en `projects`, `project_products` y `rfqs`; existen las
  políticas permisivas que usan los profesionales (`proyectos_select`,
  `_insert`, `_update`, `_delete`; `project_products_select`, `_insert`,
  `_update`, `_delete`; `rfqs_select`, `_insert`). Se guarda una copia
  de las políticas de `projects`, `project_products`, `rfqs` y
  `rfq_distributors` en una tabla temporal de la transacción.
- **Validaciones finales** (abortan): las cinco políticas nuevas
  existen, son RESTRICTIVE, solo para `authenticated` (comparación de
  roles como conjunto) y con la operación correcta; hay exactamente cinco
  restrictivas en esas tablas; ninguna política previa se eliminó ni se
  modificó (comparación con la copia); `is_supplier()` es SECURITY
  DEFINER y STABLE, sin EXECUTE para `anon` ni `PUBLIC` y con EXECUTE
  para `authenticated`; la escritura de productos y precios es
  efectivamente falsa para `anon` y `authenticated`.
- **`search_path` de `is_supplier()`:** la migración no aborta por la
  forma en que se serialice `proconfig`; si no encuentra ninguna entrada
  `search_path=…` solo emite un aviso. Se revisa en el postcheck T4b con
  `pg_get_functiondef`: la definición debe contener un `SET search_path`
  vacío (equivalente al `set search_path = ''` del archivo).
- **No se valida el texto de las condiciones** de las políticas: el
  comportamiento por rol lo verifican las pruebas RLS del bloque C.
- **Rollback 03:** borra las cinco políticas, después `is_supplier()`,
  restaura los permisos exactos y comprueba dentro de la transacción:
  cero restrictivas de 03, función inexistente, ningún permiso de tabla
  nuevo, `anon` sin escritura y la matriz original de `authenticated`
  columna a columna. El grantor de los permisos restaurados será el rol
  que ejecute el rollback y puede diferir del original, aunque el
  privilegio efectivo sea el mismo.

## Migración 04: líneas de proyecto, solicitudes y guardas

- **Transacción atómica explícita** (`BEGIN … COMMIT`), mismo criterio
  de ejecución que 01–03. El rollback también va en `BEGIN … COMMIT`.
- **Validaciones previas** (abortan): existe `publication_status` (01);
  existen `is_supplier()` y las cinco restrictivas de 03; no existe
  ninguna de las dos políticas objetivo; RLS activa en `projects`,
  `project_products` y `rfqs`; existen las políticas permisivas de
  profesionales. Auditoría (NOTICE, no aborta): rol ejecutor,
  propietario de `project_products` y UPDATE de tabla actual de
  `authenticated`.
- **Permiso efectivo tras el `REVOKE`/`GRANT`** (aborta): `authenticated`
  sin UPDATE de tabla sobre `project_products` y con UPDATE efectivo
  exactamente en `quantity`, `unit`, `notes`, `room_or_area`,
  `selected_for_rfq` y `order_position`.
- **Validaciones finales** (abortan): las dos políticas nuevas
  (`project_products_only_published_insert` y `rfqs_insert_guard`) son
  RESTRICTIVE, INSERT y solo `authenticated` (comparación como
  conjunto); hay exactamente 7 restrictivas en las tablas de cliente (5
  de 03 + 2 de 04); `rfq_distributors` sigue sin ninguna política;
  ninguna política previa cambió (copia en tabla temporal);
  `authenticated` conserva SELECT, INSERT y DELETE sobre
  `project_products`; `product_id` y `project_id` no son actualizables.
- **`rfq_distributors` no se toca en 38-B.** Ya tiene RLS activa y
  ninguna política, así que los clientes no tienen acceso. No se añade
  una política redundante sobre un flujo que todavía no existe; si 38-C
  implementa el reparto de solicitudes, diseñará políticas específicas y
  verificables para esa operación.
- **Supuesto de RFQ verificado** (lectura de código y esquema, sin
  ejecutar SQL):
  - la única inserción de solicitudes es `MobauProjects.createRfq()`
    (`proyectos-data.js`), llamada desde `proyectos-cotizacion.html` con
    `project_id: project.id` (el UUID del proyecto cargado o creado);
  - `rfqs.project_id` es `uuid NOT NULL` con clave foránea a `projects`
    y es la única columna que vincula una solicitud con un proyecto;
  - el frontend no usa ninguna función RPC y el proyecto no tiene Edge
    Functions; las funciones SECURITY DEFINER existentes no crean
    solicitudes. Cualquier vía de la API de datos aplica las mismas
    políticas RLS;
  - con `project_id = NULL`, la RFQ queda bloqueada. El motor puede
    devolver 42501 por RLS o 23502 por NOT NULL; ambos resultados son
    válidos y no deben crear una fila. El orden de evaluación entre RLS y
    NOT NULL no es un contrato de la aplicación: la garantía es que no se
    crea la fila. La prueba C14 acepta 42501 o 23502, falla con cualquier
    otro resultado (incluido el éxito) y comprueba, dentro de su propia
    subtransacción y sin RLS, que no quedó ninguna RFQ auxiliar.
- **Sin oráculo de existencia:** la comprobación de RLS de un INSERT se
  evalúa antes que las claves foráneas, así que añadir una línea con un
  ID no publicado o inexistente devuelve el mismo error de RLS (42501).
- **Rollback 04:** borra las dos políticas, restaura el UPDATE de tabla
  de `authenticated` sobre `project_products` y comprueba que no queda
  ninguna política de 04 y que el UPDATE de tabla vuelve a ser efectivo.
  No toca 03 ni `rfq_distributors`.

## Prechecks (solo lectura)

```sql
-- Productos: 22 en total, 20 active y 2 archived
select status, count(*) from public.products group by status order by status;

-- No existe aún nada de 38-B
select count(*) as debe_ser_0 from information_schema.columns
 where table_schema = 'public' and table_name = 'products' and column_name = 'publication_status';
select count(*) as debe_ser_0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('is_supplier', 'products_sync_legacy_status');

-- Políticas actuales (guardar la salida completa)
select tablename, policyname, cmd, roles::text, permissive, qual, with_check
  from pg_policies where schemaname = 'public'
   and tablename in ('products', 'product_prices', 'projects', 'project_products', 'rfqs', 'rfq_distributors')
 order by 1, 3, 2;

-- Permisos por columna actuales (guardar)
select table_name, grantee, privilege_type, string_agg(column_name, ',' order by column_name)
  from information_schema.column_privileges
 where table_schema = 'public' and grantee in ('anon', 'authenticated') and privilege_type in ('INSERT', 'UPDATE')
   and table_name in ('products', 'product_prices', 'project_products')
 group by 1, 2, 3 order by 1, 2, 3;

-- Triggers de products (3: before_insert, updated_at, validate_subcategory)
select tgname from pg_trigger where tgrelid = 'public.products'::regclass and not tgisinternal order by 1;

-- my_verified_distributor_id: authenticated sí, anon no
select has_function_privilege('authenticated', 'public.my_verified_distributor_id()', 'execute') as auth_true,
       has_function_privilege('anon', 'public.my_verified_distributor_id()', 'execute') as anon_false;

-- Copia de estado de productos (guardar)
select id, distributor_id, status, updated_at from public.products order by id;
```

## Postchecks

**Tras 38b_01**

Además de los prechecks generales, antes de aplicar 01 se guarda la
huella de las filas:
```sql
-- P2 (antes de 01): huella de todas las columnas actuales
select count(*) as filas,
       md5(string_agg(to_jsonb(p)::text, '|' order by p.id)) as huella
  from public.products p;
```

Después de aplicar 01 (solo lectura):
```sql
-- Q1: estados (esperado: published/active = 20, archived/archived = 2)
select publication_status, status, count(*)
  from public.products group by 1, 2 order by 1, 2;

-- Q2: combinaciones incoherentes (esperado: 0 filas)
select id, publication_status, status
  from public.products
 where (publication_status = 'published') <> (status = 'active');

-- Q3: misma huella que P2 sin la columna nueva (esperado: idéntica → ninguna columna existente cambió, incluido updated_at)
select count(*) as filas,
       md5(string_agg((to_jsonb(p) - 'publication_status')::text, '|' order by p.id)) as huella
  from public.products p;

-- Q4: updated_at fila a fila (esperado: idéntico a la copia del precheck)
select id, updated_at from public.products order by id;

-- Q5: definición de la columna (esperado: text, NO, 'draft'::text)
select data_type, is_nullable, column_default
  from information_schema.columns
 where table_schema = 'public' and table_name = 'products' and column_name = 'publication_status';

-- Q6: restricción e índice (esperado: 1 fila cada uno)
select conname, pg_get_constraintdef(oid) from pg_constraint
 where conrelid = 'public.products'::regclass and conname = 'products_publication_status_check';
select indexname, indexdef from pg_indexes
 where schemaname = 'public' and indexname = 'products_publication_status_idx';

-- Q7: triggers habilitados (esperado: trg_products_before_insert, trg_products_sync_legacy_status,
--     trg_products_updated_at, trg_products_validate_subcategory; todos con tgenabled = 'O')
select tgname, tgenabled from pg_trigger
 where tgrelid = 'public.products'::regclass and not tgisinternal order by tgname;

-- Q8: definición exacta del trigger de espejo; solo INSERT y UPDATE OF publication_status
select pg_get_triggerdef(oid) from pg_trigger
 where tgrelid = 'public.products'::regclass and tgname = 'trg_products_sync_legacy_status';
-- esperado (el prefijo de esquema puede aparecer o no según el search_path):
-- CREATE TRIGGER trg_products_sync_legacy_status BEFORE INSERT OR UPDATE OF publication_status
--   ON public.products FOR EACH ROW EXECUTE FUNCTION products_sync_legacy_status()
-- lo esencial: "BEFORE INSERT OR UPDATE OF publication_status" y "FOR EACH ROW"

-- Q9: la función de espejo no la ejecuta ningún rol de cliente (esperado: false, false)
select has_function_privilege('anon', 'public.products_sync_legacy_status()', 'execute') as anon,
       has_function_privilege('authenticated', 'public.products_sync_legacy_status()', 'execute') as authenticated;

-- Q10: la visibilidad todavía no cambia (esperado: sigue catalogo_lectura_publica_productos)
select policyname, cmd, qual from pg_policies
 where schemaname = 'public' and tablename = 'products' and cmd = 'SELECT';
```

Durante el despliegue inicial **no se hace ninguna prueba de
actualización de productos en producción**, para no tocar datos reales.
El comportamiento del trigger (publicar → `active`, pedir cambios →
`archived`) se prueba en `tests/38b_rls_checks.sql` (M01–M03), solo
sobre un producto auxiliar dentro de una transacción revertida.

**Tras 38b_02**

La migración ya valida número y nombres de políticas; estos postchecks
lo confirman desde fuera y revisan otras vías de lectura:
```sql
-- R1: políticas de products (esperado: SELECT products_select_own_distributor y products_select_published,
--     INSERT products_insert_own_verified, UPDATE products_update_own_verified; ninguna FOR ALL;
--     ya no existe catalogo_lectura_publica_productos)
select policyname, cmd, permissive, roles::text, qual, with_check
  from pg_policies where schemaname = 'public' and tablename = 'products'
 order by cmd, policyname;

-- R2: políticas de product_prices (esperado: SELECT product_prices_select_authenticated {authenticated}
--     con EXISTS sobre products; INSERT/UPDATE *_own sin cambios)
select policyname, cmd, permissive, roles::text, qual, with_check
  from pg_policies where schemaname = 'public' and tablename = 'product_prices'
 order by cmd, policyname;

-- R3: RLS activada en ambas tablas (esperado: true, true)
select relname, relrowsecurity from pg_class
 where oid in ('public.products'::regclass, 'public.product_prices'::regclass);

-- R4: ninguna vista lee products ni product_prices (esperado: 0 filas)
select view_schema, view_name, table_name from information_schema.view_table_usage
 where table_schema = 'public' and table_name in ('products', 'product_prices');

-- R5: funciones SECURITY DEFINER de public, para revisión
--     (esperado: enforce_active_project_limit, handle_new_user, my_verified_distributor_id; ninguna devuelve productos)
select p.proname, pg_get_function_result(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prosecdef order by 1;

-- R6: permisos de my_verified_distributor_id (esperado: authenticated true, anon false)
select has_function_privilege('authenticated', 'public.my_verified_distributor_id()', 'execute') as auth_true,
       has_function_privilege('anon', 'public.my_verified_distributor_id()', 'execute') as anon_false;

-- R7: los datos no cambian (esperado: published 20, archived 2)
select publication_status, count(*) from public.products group by 1 order by 1;
```
La visibilidad por rol (anon, profesional, distribuidor) no se puede
comprobar con estas consultas de administración: la cubre el bloque C
(`tests/38b_rls_checks.sql`, V01–V14 y P01–P04).

**Antes de 38b_03** (auditoría, solo lectura):
```sql
-- T0a: rol ejecutor, propietarios y grantor actual (solo auditoría; no condiciona la ejecución:
--      la capacidad práctica la demuestra la comprobación efectiva posterior al REVOKE)
select current_user,
       (select rolsuper from pg_roles where rolname = current_user) as superusuario,
       pg_get_userbyid((select relowner from pg_class where oid = 'public.products'::regclass)) as propietario_products,
       pg_get_userbyid((select relowner from pg_class where oid = 'public.product_prices'::regclass)) as propietario_prices;
select distinct table_name, grantor
  from information_schema.column_privileges
 where table_schema = 'public' and table_name in ('products', 'product_prices')
   and grantee = 'authenticated' and privilege_type in ('INSERT', 'UPDATE');

-- T0b: copia de las políticas actuales (guardar)
select tablename, policyname, cmd, permissive, roles::text, qual, with_check
  from pg_policies where schemaname = 'public'
   and tablename in ('projects', 'project_products', 'rfqs', 'rfq_distributors')
 order by 1, 3, 2;
```

**Tras 38b_03** (la migración ya lo valida; esto lo confirma desde fuera):
```sql
-- T1: ningún permiso de escritura por columna en products / product_prices (esperado: 0 filas)
select table_name, grantee, privilege_type, column_name, grantor
  from information_schema.column_privileges
 where table_schema = 'public' and table_name in ('products', 'product_prices')
   and grantee in ('anon', 'authenticated') and privilege_type in ('INSERT', 'UPDATE');

-- T2: permisos de tabla sin cambios (esperado: anon y authenticated → REFERENCES, SELECT, TRIGGER)
select table_name, grantee, string_agg(privilege_type, ',' order by privilege_type)
  from information_schema.role_table_grants
 where table_schema = 'public' and table_name in ('products', 'product_prices')
   and grantee in ('anon', 'authenticated')
 group by 1, 2 order by 1, 2;

-- T3: permiso efectivo (esperado: todo false)
select has_any_column_privilege('authenticated', 'public.products', 'INSERT')                     as prod_ins,
       has_any_column_privilege('authenticated', 'public.products', 'UPDATE')                     as prod_upd,
       has_column_privilege('authenticated', 'public.products', 'status', 'UPDATE')               as prod_status_upd,
       has_column_privilege('authenticated', 'public.products', 'publication_status', 'UPDATE')   as prod_pub_upd,
       has_any_column_privilege('authenticated', 'public.product_prices', 'INSERT')               as price_ins,
       has_any_column_privilege('authenticated', 'public.product_prices', 'UPDATE')               as price_upd,
       has_any_column_privilege('anon', 'public.products', 'UPDATE')                              as anon_prod_upd;

-- T4: is_supplier (esperado: prosecdef true, provolatile 's'; anon false, authenticated true)
select p.prosecdef, p.provolatile, p.proconfig
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'is_supplier';
select has_function_privilege('anon', 'public.is_supplier()', 'execute')          as anon_false,
       has_function_privilege('authenticated', 'public.is_supplier()', 'execute') as auth_true;

-- T4b: inspección de la definición (revisión manual): debe contener SECURITY DEFINER,
--      STABLE y un SET search_path vacío (p. ej. SET search_path TO '' o equivalente)
select pg_get_functiondef('public.is_supplier()'::regprocedure);

-- T5: las 5 restrictivas (esperado: 5 filas, RESTRICTIVE, {authenticated})
select tablename, policyname, cmd, permissive, roles::text
  from pg_policies where schemaname = 'public' and policyname like '%supplier_no_%'
 order by 1, 2;

-- T6: resto de políticas idénticas a T0b (esperado: misma salida que T0b más las 5 de T5)
select tablename, policyname, cmd, permissive, roles::text, qual, with_check
  from pg_policies where schemaname = 'public'
   and tablename in ('projects', 'project_products', 'rfqs', 'rfq_distributors')
 order by 1, 3, 2;
```

**Tras 38b_04** (la migración ya lo valida; esto lo confirma desde fuera):
```sql
-- U1: UPDATE por columna de authenticated en project_products
--     (esperado: notes,order_position,quantity,room_or_area,selected_for_rfq,unit)
select privilege_type, string_agg(column_name, ',' order by column_name)
  from information_schema.column_privileges
 where table_schema = 'public' and table_name = 'project_products' and grantee = 'authenticated' and privilege_type = 'UPDATE'
 group by 1;

-- U2: permiso efectivo (esperado: tabla_update false, product_id false, project_id false, quantity true,
--     selected_for_rfq true, insert true, delete true)
select has_table_privilege('authenticated', 'public.project_products', 'UPDATE')                        as tabla_update,
       has_column_privilege('authenticated', 'public.project_products', 'product_id', 'UPDATE')        as product_id,
       has_column_privilege('authenticated', 'public.project_products', 'project_id', 'UPDATE')        as project_id,
       has_column_privilege('authenticated', 'public.project_products', 'quantity', 'UPDATE')          as quantity,
       has_column_privilege('authenticated', 'public.project_products', 'selected_for_rfq', 'UPDATE')  as selected_for_rfq,
       has_table_privilege('authenticated', 'public.project_products', 'INSERT')                       as insert,
       has_table_privilege('authenticated', 'public.project_products', 'DELETE')                       as delete;

-- U3: las 2 políticas nuevas (esperado: 2 filas RESTRICTIVE, INSERT, {authenticated})
select tablename, policyname, cmd, permissive, roles::text from pg_policies
 where schemaname = 'public'
   and policyname in ('project_products_only_published_insert', 'rfqs_insert_guard')
 order by 1, 2;

-- U3b: rfq_distributors sin políticas y con RLS activa (esperado: 0 filas; true)
select policyname from pg_policies where schemaname = 'public' and tablename = 'rfq_distributors';
select relrowsecurity from pg_class where oid = 'public.rfq_distributors'::regclass;

-- U4: total de restrictivas en tablas de cliente (esperado: 7 = 5 de 03 + 2 de 04)
select count(*) from pg_policies
 where schemaname = 'public' and permissive = 'RESTRICTIVE'
   and tablename in ('projects', 'project_products', 'rfqs', 'rfq_distributors');

-- U5: resto de políticas idénticas a T0b + las 5 de 03 (comparar con la salida guardada)
select tablename, policyname, cmd, permissive, roles::text, qual, with_check
  from pg_policies where schemaname = 'public'
   and tablename in ('projects', 'project_products', 'rfqs', 'rfq_distributors')
 order by 1, 3, 2;
```
El comportamiento (líneas solo con productos publicados, solicitudes
solo sobre proyecto propio sin líneas no publicadas incluidas) lo
verifican las pruebas RLS del bloque C (C01–C09, C14, S03, S06, N02).
Las pruebas S12 y C13 confirman que `rfq_distributors` sigue sin acceso
de cliente sin políticas nuevas.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| El relleno dejara productos en `draft` y el catálogo se vaciara | La validación de `38b_01` aborta la migración si los conteos no cuadran; `38b_02` va después |
| Editar `status` a mano desde el panel de Supabase | El trigger solo actúa en INSERT y UPDATE OF `publication_status`, así que un cambio directo de `status` lo desalinearía. Se modera siempre con `publication_status`; la comprobación de coherencia de `moderacion/` lo detecta. Ningún rol de cliente puede editar `status` tras 38-B |
| Bloquear por error a un profesional | Las políticas nuevas de distribuidor son RESTRICTIVE y solo actúan si `is_supplier()`; lo cubren las pruebas C01–C13 |
| Proyectos con productos que dejan de publicarse | El frontend ya muestra "Producto no disponible" y los excluye de la solicitud (`isProductAvailable`) |
| Caché del catálogo en el navegador | `sessionStorage`, 60 s: un producto ya descargado puede seguir visible hasta un minuto tras despublicarse; RLS bloquea las consultas nuevas y la URL directa. 38-C decide si invalidar o reducir la caché |
| Una política SELECT adicional sobre `products` abriría visibilidad (OR entre permisivas) | 02 valida número y nombres de políticas antes y después y aborta si no cuadran; postcheck R1 |
| Respaldo estático del catálogo (`staticFallback`) | Si la base de datos falla, se muestran los 20 productos de demostración incluidos en `script.js` (todos publicados hoy). Se retira en 38-C |
| El distribuidor no puede archivar ni borrar su proyecto activo | Borrar un proyecto exige que esté archivado y archivar es un UPDATE bloqueado; se hace a mano desde Supabase si hace falta |

## Rollback exacto

En orden inverso, cada archivo en su propia ejecución:

1. `rollback/20261002090300_38b_04_projects_rfqs_guards.rollback.sql`
2. `rollback/20261002090200_38b_03_supplier_write_lockdown.rollback.sql`
3. `rollback/20261002090100_38b_02_products_visibility.rollback.sql`
4. `rollback/20261002090000_38b_01_products_publication_status.rollback.sql`

Tras el rollback completo, los prechecks deben devolver exactamente lo
mismo que antes del despliegue. Excepción: `products.status` conserva el
último valor reflejado por la moderación. Después de cada rollback se
borra el registro de la migración en Supabase (`supabase_migrations`) solo
si se va a volver a aplicar con el mismo nombre.

## Matriz de permisos tras 38-B

Tipos de producto: **P** publicado · **N-propio** no publicado del
distribuidor verificado que consulta · **N-ajeno** no publicado de otro
distribuidor.

| Operación | Anónimo | Profesional | Distribuidor no verificado | Distribuidor verificado | Supabase (manual) |
|---|---|---|---|---|---|
| Leer producto P | ✓ | ✓ | ✓ | ✓ | ✓ |
| Leer producto N-propio | — | — | — | ✓ | ✓ |
| Leer producto N-ajeno | ✗ | ✗ | ✗ | ✗ | ✓ |
| Leer precio de P | ✗ (como hoy) | ✓ | ✓ | ✓ | ✓ |
| Leer precio de N-propio / N-ajeno | ✗ / ✗ | ✗ / ✗ | ✗ / ✗ | ✓ / ✗ | ✓ |
| Crear o editar producto | ✗ | ✗ | ✗ | ✗ | ✓ |
| Cambiar `publication_status` o `status` | ✗ | ✗ | ✗ | ✗ | ✓ |
| Crear o editar precio | ✗ | ✗ | ✗ | ✗ | ✓ |
| Crear proyecto | ✗ | ✓ (límite de plan) | ✗ | ✗ | ✓ |
| Editar proyecto propio | ✗ | ✓ | ✗ | ✗ | ✓ |
| Borrar proyecto propio archivado | ✗ | ✓ | ✓ | ✓ | ✓ |
| Añadir línea con producto P | ✗ | ✓ (proyecto propio activo) | ✗ | ✗ | ✓ |
| Añadir línea con producto N | ✗ | ✗ | ✗ | ✗ | ✓ |
| Editar línea (cantidad, unidad, notas, incluir en RFQ) | ✗ | ✓ | ✗ | ✗ | ✓ |
| Cambiar producto o proyecto de una línea | ✗ | ✗ | ✗ | ✗ | ✓ |
| Borrar línea de proyecto propio activo | ✗ | ✓ | ✓ | ✓ | ✓ |
| Crear RFQ | ✗ | ✓ solo proyecto propio, con ≥1 línea P incluida y ninguna línea N incluida | ✗ | ✗ | ✓ |
| `rfq_distributors` (RLS activa, sin políticas; no cambia en 38-B) | ✗ | ✗ | ✗ | ✗ | ✓ |

## Frontend

**Indispensable en 38-B: ningún archivo.** El espejo de `status`
mantiene el filtro actual del catálogo, RLS oculta lo no publicado y el
frontend ya trata un producto ausente como no disponible.

**Decidido para 38-B, pendiente de aplicar (propuesta aparte):** un
producto no visible debe mostrarse solo como "Producto no disponible",
sin ID, nombre, marca, distribuidor, precio, imagen ni detalles. Hoy se
añade su ID, y los productos creados por un distribuidor tienen IDs con
el prefijo del distribuidor (por ejemplo `spectro-…`), así que el ID
revela de quién es. Quitar el ID en:
- `seleccion.html` (fila no disponible)
- `proyectos-detalle.html` (fila no disponible)
- `proyectos-resumen.html` (fila no disponible)
- `proyectos-cotizacion.html` (lista de productos)

**38-C:** etiquetas de `publication_status` en el panel y
`PRODUCT_COLUMNS` (`script.js`); envío a revisión con una función
controlada; reactivar la gestión de productos; retirar el respaldo
estático del catálogo.
