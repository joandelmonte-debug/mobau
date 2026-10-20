# SEG-01 · Privilegios de tabla y privilegios por defecto

> **Aplicada y registrada el 2026-10-20.** COMMIT confirmado por lectura a las 16:32:58 UTC; registro `20261020180000 · seg_01_privilegios` confirmado a las 16:35:09 UTC. Quedan 37 migraciones.
>
> Es un punto de seguridad separado del 43, que surgió de un hallazgo durante CC1. No cambia políticas, datos, funciones existentes, roles, planes ni habilitaciones.

Proyecto Supabase: mobau-pilot (`skcoxtdppdcietgojdal`).

## Qué hace

**O2 · Privilegios que no pasan por RLS.** `anon` y `authenticated` dejan de tener:
- **TRUNCATE, REFERENCES y TRIGGER** en las 8 tablas que conservaban los privilegios por defecto: categories, plans, professional_profiles, projects, project_products, rfqs, rfq_distributors y studios;
- **MAINTAIN** (PostgreSQL 17: VACUUM, ANALYZE, REINDEX, CLUSTER y LOCK TABLE) en todas las tablas de `public` donde lo tenían: 11 para `anon`, y 13 para `authenticated`, que son las mismas más moodboards y product_prices.

SELECT, INSERT, UPDATE y DELETE no cambian: RLS los sigue filtrando.

PostgreSQL permite LOCK TABLE a quien tenga UPDATE, DELETE o TRUNCATE, así que en las tablas donde un rol conserva UPDATE o DELETE ese rol todavía puede bloquear. Impedirlo exigiría quitar UPDATE y DELETE a `anon`: es la opción O3, no aprobada.

**O4 · Los objetos nuevos que cree `postgres` no nacen abiertos:**
- **tablas nuevas de `public`:** sin TRUNCATE, REFERENCES, TRIGGER ni MAINTAIN para `anon` y `authenticated`;
- **funciones nuevas de `public`:** sin EXECUTE para `anon` y `authenticated`;
- **funciones nuevas de `postgres` en cualquier esquema:** sin EXECUTE para PUBLIC.

Desde SEG-01, **cada migración que cree una función usada por la web, por RPC o dentro de una política debe conceder EXECUTE de forma explícita**. Los valores por defecto de `supabase_admin` no se pueden cambiar como `postgres` y no cambian.

## Archivos

| Archivo | md5 |
|---|---|
| `migrations/20261020180000_seg_01_privilegios.sql` | `577a2ba4558108b431b3fae6139e55c4` |
| `rollback/20261020180000_seg_01_privilegios.rollback.sql` | `b7a9353a9724ea95eb03743188868b68` |
| `tests/seguridad/seg_01_lectura.sql` (solo SELECT) | `a621e12bf3f8e90925a5de2ba3093956` |
| `tests/seguridad/SEG01_ensayo.sql` (ensayo revertido) | `c745188f34943f1d05d899460183cf37` |
| `tests/seguridad/herramientas/generar_seg01.py` | `8770bd97c5775ce444fade48a4d1e17e` |

## Comprobaciones

**Ensayo.** El primer intento falló por un paréntesis de más en la migración: error 42601, y la transacción se deshizo entera. El segundo, con el archivo corregido, terminó en MB990 con las 8 marcas en `true`:
- **sondas de la web (P01–P16):** dan lo mismo antes, con SEG-01 y tras recuperar;
- **TRUNCATE y LOCK** donde el rol solo lee: `ok`, luego 42501 y de nuevo `ok`;
- **tabla y función nuevas:** nacen cerradas con SEG-01 y vuelven a nacer como antes tras recuperar;
- **lecturas** de antes y después: idénticas.

**Aplicación.** La lectura posterior dio:
- ninguna tabla con TRUNCATE ni MAINTAIN para `anon` o `authenticated`;
- sondas de la web P01–P16 con los mismos valores que en el ensayo;
- datos, políticas (60), funciones de precios y del límite de proyectos, perfiles, planes y habilitaciones sin cambios;
- ningún objeto de prueba.

## Recuperación

`rollback/20261020180000_seg_01_privilegios.rollback.sql` devuelve exactamente los privilegios retirados y los privilegios por defecto anteriores. Se ensayó dentro del ensayo revertido. Si alguna vez se aplica:
- se registra como **migración nueva**, con versión y nombre propios, después de confirmar su COMMIT;
- la fila de SEG-01 no se borra;
- necesita su propia autorización.
