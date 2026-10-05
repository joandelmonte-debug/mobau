# 38-C · Propuestas de cambio de productos

> **EJECUTADO el 2026-10-02.** Ver "Estado de ejecución" a continuación.

Un distribuidor verificado propone cambios de información y precio de sus
propios productos. Mobau revisa cada propuesta antes de aplicarla: el
producto publicado no cambia mientras tanto. La moderación de Mobau
(aprobar, pedir cambios, rechazar y aplicar al producto) es el punto 39 y
no forma parte de 38-C.

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

## Archivos

| Archivo | Contenido |
|---|---|
| `migrations/20261002120000_38c_01_product_proposals_tables.sql` | Tablas, restricciones, índice de una propuesta abierta por producto, RLS activada sin acceso |
| `migrations/20261002120100_38c_02_product_proposals_logic.sql` | Funciones y triggers: autor y empresa, validación de campos, transiciones, copia del producto al enviar, historial |
| `migrations/20261002120200_38c_03_product_proposals_access.sql` | Políticas y permisos por columna del distribuidor verificado |
| `rollback/*.rollback.sql` | Rollback de cada migración (mismo prefijo); se ejecutan en orden inverso: 03, 02, 01 |
| `tests/38c_rls_checks.sql` | Pruebas RLS (40 casos) en una transacción revertida |
| `../distribuidor-propuestas.html` | Página del distribuidor: lista de propuestas y formulario |

## Reglas que aplica el servidor

- Solo el distribuidor verificado ve, crea y edita propuestas de **sus**
  productos; `anon` no tiene acceso. No hay `DELETE`: retirar es pasar a
  `withdrawn`.
- Una sola propuesta abierta (`draft`, `submitted`, `changes_requested`)
  por producto.
- Campos que se pueden proponer: `name`, `description`, `category_id`,
  `subcategory`, `image_url`, `availability`, `lead_time`, `brand`,
  `measurements`, `materials`, `finishes`, `technical_sheet_url`,
  `cad_bim_3d_url`, `use_context`, `space`; además precio
  (`proposed_price_status`, `proposed_price_amount`) y una nota interna.
- Transiciones del distribuidor: `draft → submitted | withdrawn`,
  `submitted → withdrawn`, `changes_requested → submitted | withdrawn`.
  Solo se edita en `draft` y `changes_requested`. Reenviar tras
  `changes_requested` sube la versión.
- Al enviar se guarda una copia del producto (`product_snapshot`); cada
  creación y cambio de estado queda en `proposal_events`.
- Los campos de Mobau (`rejection_reason`, `reviewed_at`, `reviewed_by`,
  `product_snapshot`, `submitted_at`, `version`) no son escribibles por el
  cliente.

## Uso para distribuidores

1. Entra con tu cuenta de distribuidor. Tu empresa debe estar verificada;
   si no lo está, las páginas de productos y propuestas te devuelven al
   panel.
2. Abre **Mis productos** y pulsa **Proponer cambios** en el producto, o
   ve a **Propuestas → Nueva propuesta** y elige el producto.
3. Cambia solo lo que quieras actualizar. Cada campo muestra el valor
   actual; a Mobau solo se envían los campos distintos.
4. **Guardar borrador** guarda sin enviar; puedes editarlo después.
   **Enviar a Mobau** lo deja en revisión y ya no se puede editar.
5. Si Mobau pide cambios, verás su nota en la propuesta. Usa **Corregir y
   reenviar**.
6. Puedes **Retirar** una propuesta abierta en cualquier momento. Para
   proponer otro cambio en el mismo producto, retira o espera a que se
   cierre la anterior.
7. Las altas de productos nuevos todavía se solicitan escribiendo a
   Mobau.

## Enlaces en la web

- Cabecera de distribuidor: Resumen · Mis productos · **Propuestas** ·
  Catálogo (escrita en las páginas de distribuidor y añadida por
  `nav-session.js` en el resto).
- Panel: tarjeta "Tus productos" con "Ver mis productos" y "Mis
  propuestas" (solo con empresa verificada), y nota "Propuestas de cambio".
- Mis productos: "Proponer cambios" en cada producto
  (`distribuidor-propuestas.html?producto=ID`). Si el producto ya tiene
  un borrador o cambios solicitados, se abre esa propuesta; si está
  enviada, se muestra la lista con un aviso.
