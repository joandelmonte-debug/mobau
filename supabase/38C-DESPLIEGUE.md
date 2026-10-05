# 38-C · Propuestas de productos por distribuidores

> **01–03 EJECUTADAS el 2026-10-02; 04 EJECUTADA el 2026-10-05.** Ver
> "Estado de ejecución" (01–03) y "38-C 04" a continuación.

Un distribuidor verificado propone a Mobau productos nuevos (`create`) o
cambios de información y precio de sus propios productos (`update`). Mobau
revisa cada propuesta antes de aplicarla: el catálogo no cambia mientras
tanto. La moderación de Mobau (aprobar, pedir cambios, rechazar y aplicar
al catálogo) es el punto 39 y no forma parte de 38-C.

## Estado de ejecución — 2026-10-02

**Migraciones**
- 01, 02 y 03 aplicadas en producción el 2026-10-02 y registradas una sola
  vez en `supabase_migrations.schema_migrations` (`20261002120000`,
  `20261002120100`, `20261002120200`), con el nombre de su archivo.
- La 01 se ejecutó desde `BEGIN`, sin los comentarios de cabecera ni un
  comentario interno; las sentencias son idénticas al archivo.
- Los SQL se conservan sin cambios, incluida la cabecera "PROPUESTA NO
  EJECUTADA": son el artefacto que se aprobó y se ejecutó.

**Resultado**
- Tablas `product_proposals` y `proposal_events`, con RLS activada.
- 5 funciones (`log_proposal_event` es la única `SECURITY DEFINER`) y
  7 triggers en `product_proposals`.
- 4 políticas nuevas: 44 en total en `public`.
- Huellas (recuento y MD5) idénticas antes y después para `products`,
  `product_prices`, `projects`, `project_products`, `rfqs`,
  `distributors`, `distributor_profiles`, `profiles`, `categories`, las 40
  políticas previas y los permisos existentes.

**Pruebas RLS**
- `tests/38c_rls_checks.sql`: 40 casos, **40 PASS, 0 FAIL**.
- `tests/38b_rls_checks.sql` (regresión): 50 casos, **50 PASS, 0 FAIL**.
- Ambas en una transacción terminada en `ROLLBACK`; no quedaron filas de
  prueba.

**No cubierto por estas pruebas**
- Un distribuidor con usuario pero sin verificar (se dejó para más
  adelante; el caso sin empresa verificada sí está cubierto).
- La moderación de Mobau y la aplicación de cambios al producto (39).

## 38-C 04 · Producto nuevo (`create`) y cambio (`update`) — 2026-10-05

**Migración**
- `20261005120000_38c_04_product_proposals_kinds`: **aplicada y
  registrada** en `supabase_migrations.schema_migrations` el 2026-10-05
  (16 migraciones en total). Se ejecutó completa, con sus comentarios, de
  una sola vez; los cuerpos de las 5 funciones en la base coinciden con el
  archivo (MD5 de `prosrc`).
- Antes de aplicarla no había propuestas reales: ninguna fila que
  convertir.

**Resultado**
- `product_proposals`: nuevas columnas `proposal_kind` (`create` |
  `update`, por defecto `update`) y `proposed_new_subcategory`;
  `product_id` admite null solo en `create`.
- 5 restricciones nuevas: `product_proposals_kind_check`,
  `_kind_product`, `_new_subcategory_length`, `_new_subcategory_exclusive`,
  `_create_has_name`. Las 15 anteriores, incluidas las 4 de precio, sin
  cambios.
- Índices: `product_proposals_one_open_per_product` limitado a `update`;
  nuevo `product_proposals_one_open_create_per_name`.
- Las 5 funciones de 02 reemplazadas; los mismos 7 triggers; políticas sin
  cambios (44 en `public`).
- Permisos por columna de `authenticated`: INSERT añade `proposal_kind` y
  `proposed_new_subcategory`; UPDATE añade solo `proposed_new_subcategory`.
  `anon`, sin permisos.
- Huellas (recuento y MD5) idénticas antes, después y tras las pruebas para
  `products`, `product_prices`, `distributors`, `distributor_profiles`,
  `profiles`, `categories`, `projects`, `project_products`, `rfqs`, las 44
  políticas y los permisos de `anon` y `authenticated` fuera de
  `product_proposals`.

**Pruebas RLS**
- `tests/38c_rls_checks.sql`: 74 casos, **74/74**.
- `tests/38b_rls_checks.sql` (regresión): 50 casos, **50/50**.
- Ambas dentro de `BEGIN … ROLLBACK`; sin filas de prueba ni residuos.

**Tipos de propuesta**
- `create`: producto nuevo. Sin `product_id`. No crea ni modifica nada en
  `products`.
- `update`: cambio de un producto existente. `product_id` obligatorio y de
  la empresa verificada del distribuidor. Solo se guardan los campos que
  cambian.
- El tipo se fija al crear la propuesta y no se puede cambiar.

**Producto nuevo: obligatorios al enviar**
- Nombre, descripción, categoría, disponibilidad y una subcategoría (de la
  lista de la categoría o una subcategoría nueva propuesta).
- Un borrador `create` puede estar incompleto, pero siempre con nombre.
- El precio es opcional, con las mismas restricciones que en `update`:
  importe no negativo, `published` exige importe e importe exige estado.
- Una sola propuesta `create` abierta por empresa y nombre normalizado
  (minúsculas, espacios recortados y colapsados; sin tratar tildes ni
  equivalencias). Coincidir con un producto existente no bloquea: la web
  solo avisa.

**Subcategoría nueva** (`create` y `update`)
- Opción "No encuentro una subcategoría adecuada": se guarda en
  `proposed_new_subcategory` (1–100 caracteres).
- Excluye a la vez una subcategoría de la lista (`proposed_changes ?
  'subcategory'`).
- No puede repetir una subcategoría que ya exista en la categoría
  (comparación sin mayúsculas ni espacios sobrantes).

**Regla de clasificación en `update` (D5)**
- Si no toca `category_id`, `subcategory` ni `proposed_new_subcategory`, no
  exige subcategoría (por ejemplo, solo precio, marca, imagen o
  descripción).
- Si cambia `category_id`, debe aportar a la vez una subcategoría válida de
  la nueva categoría o una subcategoría nueva.
- Si cambia `subcategory`, debe ser válida para la categoría resultante (o
  usar una subcategoría nueva); nunca vacía.

**Sin escrituras en el catálogo**
- Ninguna función escribe en `products` ni en `product_prices`. En `update`
  solo se leen para la copia (`product_snapshot`) al enviar; en `create`,
  `product_snapshot` queda null. Lo comprueban K29 y K34.

**Reservado al punto 39**
- Moderación (pedir cambios, rechazar, aprobar) y su historial como Mobau.
- Creación real del producto a partir de un `create`, incluida la decisión
  sobre una subcategoría nueva (añadirla al catálogo o usar una existente),
  el identificador del producto y su publicación.
- Aplicación de un `update` al producto y del precio a `product_prices`
  (precio efectivo).
- Enlace final entre la propuesta y el producto creado
  (`created_product_id`, si hace falta).

**Rollback**
- `rollback/20261005120000_38c_04_product_proposals_kinds.rollback.sql`.
  Se niega si hay propuestas `create`, con subcategoría nueva, sin
  `product_id` o con más de una abierta por producto. Restaura las 5
  funciones de 02 (texto literal), el índice de 01 y los permisos por
  columna de 03. No borra propuestas ni eventos.

## Archivos

| Archivo | Contenido |
|---|---|
| `migrations/20261002120000_38c_01_product_proposals_tables.sql` | Tablas, restricciones, índice de una propuesta abierta por producto, RLS activada sin acceso |
| `migrations/20261002120100_38c_02_product_proposals_logic.sql` | Funciones y triggers: autor y empresa, validación de campos, transiciones, copia del producto al enviar, historial |
| `migrations/20261002120200_38c_03_product_proposals_access.sql` | Políticas y permisos por columna del distribuidor verificado |
| `migrations/20261005120000_38c_04_product_proposals_kinds.sql` | Tipos `create` / `update`, subcategoría nueva, reglas D1–D5, índices únicos parciales y permisos por columna nuevos |
| `rollback/*.rollback.sql` | Rollback de cada migración (mismo prefijo); se ejecutan en orden inverso: 04, 03, 02, 01 |
| `tests/38c_rls_checks.sql` | Pruebas RLS (74 casos) en una transacción revertida |
| `../distribuidor-propuestas.html` | Formulario de propuesta: crear nuevo producto o proponer cambios de un producto (sin lista ni historial) |

## Reglas que aplica el servidor

- Solo el distribuidor verificado ve, crea y edita **sus** propuestas
  (productos nuevos o cambios de **sus** productos); `anon` no tiene
  acceso. No hay `DELETE`: retirar es pasar a `withdrawn`.
- Una sola propuesta `update` abierta (`draft`, `submitted`,
  `changes_requested`) por producto, y una sola `create` abierta por
  empresa y nombre normalizado (38-C 04).
- Campos que se pueden proponer: `name`, `description`, `category_id`,
  `subcategory`, `image_url`, `availability`, `lead_time`, `brand`,
  `measurements`, `materials`, `finishes`, `technical_sheet_url`,
  `cad_bim_3d_url`, `use_context`, `space`; además precio
  (`proposed_price_status`, `proposed_price_amount`) y una nota interna.
- Transiciones del distribuidor: `draft → submitted | withdrawn`,
  `submitted → withdrawn`, `changes_requested → submitted | withdrawn`.
  Solo se edita en `draft` y `changes_requested`. Reenviar tras
  `changes_requested` sube la versión.
- Al enviar un `update` se guarda una copia del producto
  (`product_snapshot`); en un `create` queda null. Cada creación y cambio
  de estado queda en `proposal_events`, con el tipo de propuesta.
- Los campos de Mobau (`rejection_reason`, `reviewed_at`, `reviewed_by`,
  `product_snapshot`, `submitted_at`, `version`) no son escribibles por el
  cliente.

## Uso para distribuidores

1. Entra con tu cuenta de distribuidor. Tu empresa debe estar verificada;
   si no lo está, las páginas de productos y propuestas te devuelven al
   panel.
2. Todo empieza en **Mis productos**:
   - **Crear nuevo producto** (el único botón general): describe el
     producto (nombre, descripción, categoría, subcategoría y
     disponibilidad son obligatorios para enviarlo; el precio es
     opcional). Hasta que Mobau lo incorpore aparece en **Productos
     propuestos**.
   - Para cambiar un producto existente, parte de su tarjeta: **Proponer
     cambios** o, si ya tiene una propuesta abierta, **Continuar
     borrador**, **Corregir y reenviar** o **Ver propuesta enviada** (se
     despliega en la propia tarjeta, en solo lectura). Nunca se abre una
     segunda propuesta sobre el mismo producto.
   - Los filtros **Estado en el catálogo** y **Propuesta** ayudan a ver qué
     está publicado y qué está pendiente.
3. En un cambio, modifica solo lo que quieras actualizar. Cada campo
   muestra el valor actual; a Mobau solo se envían los campos distintos.
   Si cambias la categoría, elige también su subcategoría.
   Si no encuentras una subcategoría adecuada, marca **No encuentro una
   subcategoría adecuada** y escribe la que propones.
4. **Guardar borrador** guarda sin enviar; puedes editarlo después.
   **Enviar a Mobau** lo deja en revisión y ya no se puede editar.
5. Si Mobau pide cambios, verás su nota en la propuesta. Usa **Corregir y
   reenviar**.
6. Puedes **Retirar propuesta** mientras esté abierta: en el formulario
   (borrador o cambios solicitados) o en **Ver propuesta enviada** (en
   revisión). Se pide confirmación y la propuesta pasa a `withdrawn`;
   después puedes crear otra para ese producto, o un producto nuevo con el
   mismo nombre. Las propuestas aprobadas, rechazadas o retiradas no se
   pueden retirar.
7. Enviar una propuesta no publica nada: Mobau la revisa y, si la aprueba,
   aplica el cambio o crea el producto (punto 39).

## Enlaces en la web

**Mis productos** (`distribuidor-productos.html`) es la única página
principal: catálogo, productos propuestos, filtros, estado de las
propuestas abiertas y todas las acciones. `distribuidor-propuestas.html`
es solo el formulario de propuesta; no tiene lista ni historial, y las
propuestas cerradas no se muestran al distribuidor (siguen guardadas para
Mobau y el punto 39).

- Cabecera de distribuidor: Resumen · Mis productos · Catálogo (escrita en
  las páginas de distribuidor y añadida por `nav-session.js` en el resto).
- Panel: tarjeta "Tus productos" con "Gestionar mis productos" (solo con
  empresa verificada) y nota "Propuestas de productos".
- Mis productos → formulario (`distribuidor-propuestas.html`):
  - `?nueva=1`: "Crear nuevo producto" (tipo create fijo).
  - `?producto=ID`: "Proponer cambios" de ese producto (tipo update y
    producto fijos), o su propuesta abierta si es editable; si está en
    revisión, vuelve a Mis productos y la muestra desplegada.
  - `?propuesta=ID` (compatibilidad): la abre si es editable; si está en
    revisión o cerrada, vuelve a Mis productos con el aviso "Esta
    propuesta se consulta desde Mis productos".
  - Sin parámetros: redirige a Mis productos.
  Al guardar, retirar o volver se regresa siempre a Mis productos.
- Única escritura desde Mis productos: retirar una propuesta en revisión
  (`submitted → withdrawn`) desde su detalle desplegable.
