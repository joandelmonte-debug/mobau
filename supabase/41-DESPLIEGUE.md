# 41 · Ciclo de vida de productos

> **41-06 (activación) aplicada el 2026-10-15** en la ventana V4, y **41-07
> (flujo del distribuidor) aplicada el 2026-10-16** y publicada en la web el
> 2026-10-19. Las dos están registradas: 31 migraciones, la última
> `20261016120000`.
>
> Estado actual:
> - interruptor del servidor encendido;
> - interfaz con la gestión del ciclo de vida activa (commit `f3f5af9`);
> - auditoría conservada: eventos 700–702 (41-T) y 1293–1298 (prueba del
>   flujo de papelera).
>
> **Bloque cerrado.** No quedan pendientes técnicos de este punto (ver
> «Decisiones aceptadas»).

Proyecto Supabase: mobau-pilot (`skcoxtdppdcietgojdal`), PostgreSQL 17.6.
Cloudflare Pages: proyecto `mobau-pilot`, detrás de Access.

## Qué hace

**Distribuidor** («Mis productos», pestañas **Productos** y **Papelera**):
- **Retirar** quita el producto del catálogo y lo lleva directamente a la
  Papelera, en una sola acción.
- **Restaurar** no tiene plazo:
  - un producto retirado por la propia empresa vuelve publicado, con el
    contenido que Mobau aprobó;
  - un borrador vuelve como borrador;
  - si hay una intervención de Mobau vigente, vuelve «retirado por Mobau»;
  - lo que movió Mobau a la papelera solo lo restaura Mobau.
- **Eliminar definitivamente** cualquier producto propio de la papelera,
  también si lo movió Mobau. Se bloquea si está en proyectos o RFQ, si otra
  tabla lo referencia o si tiene una propuesta abierta.
- **Avisos de Mobau** muestra las intervenciones del moderador de los
  últimos 30 días, con su motivo. **Productos eliminados** (en la Papelera)
  conserva nombre, identificador, fecha y quién lo eliminó, sin límite de
  fecha.

**Mobau** (Moderación):
- Retirar temporalmente, mover a la papelera, restaurar y eliminar
  definitivamente desde cualquier estado gestionable. Toda intervención exige
  un motivo, que la empresa ve.
- Historial de productos ya eliminados en `moderacion-producto.html?id=…` y
  bloque «Eliminaciones definitivas» en Moderación.

**Intervención vigente**: retirada o papelera de Mobau posterior a la última
republicación que Mobau aprobó. Solo cuentan los eventos del ciclo actual de
ese identificador (posteriores a su última eliminación definitiva) y de la
empresa del producto; no depende de la fecha de creación.

## Migraciones y archivos

| Archivo | MD5 | Estado |
|---|---|---|
| `migrations/20261015120000_41_06_lifecycle_activation.sql` | `1b67be6b5b4cfc30de014f62b8ec8801` | Aplicada 2026-10-15 16:15:50 UTC; registrada |
| `migrations/20261016120000_41_07_distributor_trash_flow.sql` | `46c37b336efee2d40c63743a8b503860` | Aplicada 2026-10-16; registrada |
| `rollback/20261016120000_41_07_distributor_trash_flow.rollback.sql` | `67928ff16921973d21cfaf7ddf06c416` | **No ejecutada.** Solo ensayada (E7) |
| `parada/41_07_parada.sql` | `00d288cb8b17028a8cacfaa25c37dd6d` | **No ejecutada.** Parada vigente |
| `parada/41_06_parada.sql` | `13dbdb51417395a14bb817c8424aa0c3` | **No ejecutada.** Histórica: sustituida por la de 41-07 |
| `tests/41_06_humo_checks.sql` | `fd3abac5d6e7e3712dc913d611752c42` | Validó 41-06 (24/24). Histórica: sus expectativas son las de antes de 41-07 |
| `tests/41_07_checks.sql` | `82295f67e3e8f10dc6e2da3b1d912d84` | Suite vigente de 41-07 (32/32) |
| `tests/41_07_lectura.sql` | `62053c5f020d2f6c3c64b42c151db958` | Lectura de estado, solo SELECT |

Cada archivo se envió con un control de integridad: el servidor comprobó el
MD5 del texto recibido antes de ejecutarlo.

## 41-06 · Activación (ventana V4, 2026-10-15)

- **Qué hizo:** `GRANT EXECUTE` a `authenticated` en las 9 funciones de
  entrada de V3 y encendido del interruptor.
- **Antes de la ventana:** ensayo revertido E4 (activación + humo + parada,
  vuelta idéntica al estado de partida).
- **En la ventana** (piloto sin uso confirmado):
  - lecturas antes y después: solo cambiaron permisos, interruptor y
    registro; huella `b509fec4…` tras la activación;
  - humo H4 sobre el servidor activado: **24/24**;
  - interfaz D3 (`e989542`) publicada: Pages Success, 49 archivos,
    comprobación A2 **16/16** en el dominio principal y en la URL única.
- **Validado por el usuario en la interfaz:** pestañas renovadas, interruptor
  de interfaz activo y revisión visual sin pulsar acciones.

## 41-T · Prueba real con un producto temporal (2026-10-15/16)

- Producto `spectro-6860c437` «PRUEBA 41-T · no usar», creado y aprobado
  desde la web.
- Retirado y movido a la papelera por la empresa; eliminado
  anticipadamente por Mobau (reglas de 41-06).
- **Comprobado en el servidor:**
  - el producto, su propuesta y sus 3 eventos de propuesta no existen;
  - quedan 3 eventos de auditoría: 700 retirar, 701 papelera, 702
    eliminación, con recuentos y huella SHA-256 válida;
  - el resto de datos no cambió.
- **Validado por el usuario en la interfaz:** cada paso, el catálogo y la
  ficha pública.

## 41-07 · Flujo del distribuidor (2026-10-16)

**Ensayo E7** (revertido, sin registrar):
- primera ejecución: **24/31**, con un fallo del servidor (las reglas
  dependían de la fecha de creación), un nombre ausente en el historial y un
  fallo de la propia prueba. Corregidos (A, B y C), sin cambiar expectativas
  salvo reforzar D06;
- segunda ejecución: suite **32/32** (31 casos + D16, identificador
  reutilizado), recuperación sobre estados nuevos **1/1/1** y vuelta
  **idéntica** al estado de partida.

**Aplicación:**
- lectura previa conforme;
- aplicada una vez; las 12 funciones instaladas coinciden con el archivo;
- registro en llamada aparte, tras confirmar el COMMIT;
- suite sobre el servidor actualizado: **32/32**, deshecha, sin restos;
- datos, auditoría previa y proyectos idénticos a la lectura previa (solo
  avanzaron las secuencias).

**Interfaz:** commit `f3f5af9` (6 archivos de interfaz + migración +
recuperación), publicado el 2026-10-19.
- El push se hizo con la sesión en aprobación manual, porque el modo
  automático lo bloqueó.
- **Validado por el usuario:** Cloudflare Success y comprobación A2 **6/6**
  en el dominio principal.

**Compatibilidad durante la publicación:** la interfaz D3 funciona con el
servidor 41-07, salvo una pestaña abierta antes de aplicar 41-07: su
«Retirar del catálogo» falla con 42501 sin escribir nada y deja la página sin
acciones hasta recargar. Por eso el orden fue: cerrar pestañas → servidor →
web → abrir de nuevo.

### Prueba manual del flujo (2026-10-19)

Producto temporal `spectro-dff118e4` «PRUEBA FLUJO PAPELERA · no usar»
(Spectro Lighting), hecho todo por el usuario desde la web:
crear y aprobar → Retirar → Restaurar → Retirar → Eliminar definitivamente.

- **Comprobado en el servidor** (una lectura final):
  - el producto no está en `products` ni en el catálogo; 0 precios, 0
    propuestas y 0 líneas de proyecto;
  - eventos 1293–1298 de la empresa: retirar, papelera, restaurar (a
    publicado), retirar, papelera, eliminación;
  - eliminación con meta `{"name": "PRUEBA FLUJO PAPELERA · no usar"}`,
    recuentos 1 producto / 0 precios / 1 propuesta / 3 eventos y SHA-256
    válido;
  - productos y precios con la misma huella que antes; eventos 700–702
    intactos.
- **Validado por el usuario en la interfaz:** creación y aprobación,
  pestañas y contadores, vuelta a Productos como Publicado, papelera vacía y
  la línea en «Productos eliminados».
- No se comprobó con lectura la identidad y las referencias antes de
  eliminar; el servidor bloquea la eliminación si hay referencias y la
  lectura final confirma 0 líneas de proyecto.

## Procedimientos

**Leer el estado** (`tests/41_07_lectura.sql`): antes y después de cualquier
cambio, y ante cualquier respuesta ambigua. Una respuesta ambigua o una
conexión perdida significa estado desconocido hasta leerlo.

**Parada** (`parada/41_07_parada.sql`, una transacción): apaga el interruptor
y retira `EXECUTE` de las 11 funciones de entrada.
- No borra datos ni auditoría, no termina sesiones y no toca el registro de
  migraciones.
- Ensayada solo dentro de la suite (caso K03). Nunca ejecutada de verdad.
- Si se ejecuta, la reactivación posterior necesita una **migración nueva**:
  41-06 no se vuelve a aplicar.

**Recuperación** (`rollback/…41_07…rollback.sql`): vuelve al código y los
permisos de V3 + 41-06 sin borrar datos ni auditoría.
- Primero se devuelve la web a D3 (`e989542`); después se ejecuta la
  recuperación como migración nueva, registrada aparte tras su COMMIT.
- Efecto: las papeleras sin plazo reciben `purge_after = trashed_at + 30
  días`; con las reglas de V3, la empresa ya no puede restaurar lo que lleve
  más de 30 días en la papelera (Mobau sí).
- Ensayada solo dentro de E7. Nunca ejecutada de verdad.

**Publicación de la web:** Pages publica solo los 49 archivos de
`scripts/pages-manifest.txt`; nada de `supabase/` se sirve. Un push no
ejecuta migraciones (no hay integración de Supabase con GitHub ni
workflows).

## Decisiones aceptadas por el usuario

- **Sin mensaje de éxito** tras eliminar definitivamente un producto propio:
  basta con la papelera vacía y la entrada en «Productos eliminados».
- **«Avisos de Mobau»** se reserva para intervenciones del moderador; las
  eliminaciones de la propia empresa no generan aviso.
- **Mensajes de error y bloqueo:** se mantienen.
- **«Nueva»** en «Decisiones recientes de Mobau» se acepta como lectura por
  dispositivo; no se sincroniza entre dispositivos.
