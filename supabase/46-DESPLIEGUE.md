# Punto 46 · Componentes y accesorios: decisiones y estado de entrega

Documento vivo de entrega. Sin commit hasta que se autorice. Pruebas solo en `mobau-pruebas` con datos sintéticos; nada de esto se ha aplicado en Production.

## Decisiones de producto

- **Quién ve el configurador (decisión del 2026-10-26, sustituye a «Gratis en solo lectura»).**
  - **Gratis** (cuenta con sesión sin herramientas profesionales) **no ve el configurador**: ni el panel «Configurar», ni los grupos, opciones, componentes anidados o avisos internos. Ve la ficha normal del producto (imágenes, descripción, acabados, información no exclusiva). No hay otra vía para añadir al proyecto un producto que requiere configuración. No se muestra tarjeta promocional ni aviso de mejora de plan.
  - **Individual y Estudio con acceso habilitado** conservan el configurador interactivo.
  - **Visitantes sin sesión** mantienen por ahora el comportamiento anterior (opciones en solo lectura). Cualquier cambio exige una decisión expresa.
  - Las restricciones de acceso del servidor no cambian: ocultar el panel no las sustituye.
  - Implementación: `cfgBoot` en `producto.html` (corta antes de pedir la configuración si `MobauAccess.access()` es `"gratis"`). Las tarjetas del catálogo ya no cargan configuración sin herramientas profesionales.
  - Pruebas (mocks): `supabase/tests/46/interfaz/pruebas-grupos-46.html`, caso Q15g y ajustes en P12 y Q21c; 107/107.

- **Nota técnica de línea (decisión del 2026-10-26).** Es un texto libre opcional que escribe el profesional en cada línea del proyecto; no es el resumen automático de la configuración.
  - Se guarda en `project_products.notes` (sin cambios de base: la columna, el permiso del propietario y la copia de la RFQ ya existían).
  - Se edita solo en líneas vivas de un proyecto activo (máx. 1000 caracteres en la interfaz, botón «Guardar nota»; vacío = sin nota). Se muestra siempre como texto, nunca como HTML, rotulada y con un bloque propio distinto del resumen.
  - Entra en la copia de la RFQ (`lines_snapshot`, ya generada en el servidor) y se ve en «Ver lo solicitado». En proyectos archivados y solicitudes enviadas es solo lectura. Las copias ya enviadas no cambian.
  - Sin bandeja nueva de distribuidor: la nota queda disponible en la copia para el flujo de consulta que corresponda.
  - Protección en el servidor (migración 46-06, abajo): la nota de una línea de un proyecto archivado no se puede cambiar y un valor nuevo no puede pasar de 1000 caracteres. La interfaz ya no es la única barrera; muestra el motivo si el servidor rechaza.
  - Pruebas con mocks: `pruebas-proyecto-46.html`, casos N1–N7 (53/53).
- **Bloque 5 «quote» (delimitación decidida el 2026-10-26, no es un requisito original recuperado).** Para esta entrega: crear la solicitud de cotización desde el proyecto, conservar su copia de líneas y consultar las solicitudes anteriores. Queda fuera: emitir presupuestos, precios ofertados, respuestas de distribuidores y negociación.

## Prueba integrada en la interfaz real (mobau-pruebas, 2026-10-26)

- Formulario del distribuidor: estructura de grupos y opciones, «Crear componente nuevo…» desde la propuesta del producto principal, referencia por propuesta, envío del componente y después del padre.
- Moderación: lista, tabla de diferencias, bloqueo de la aprobación del padre mientras el componente nuevo no esté aprobado, aprobación en orden. Resultado verificado en base: componente nuevo creado y estructura del padre sin duplicados.
- Vista «Solicitudes enviadas» del proyecto, verificada contra una RFQ existente.
- Cantidad: sobrevive a una recarga en Mi selección (3 ud.); cambiar cantidad, quitar y volver a configurar verificados sin tocar la RFQ original.
- Nota técnica: guardada y conservada tras recargar (HTML visible como texto), conservada al cambiar la cantidad; RFQ sintética nueva (`ec5e0600…`) con la nota y cantidad 2 en su copia; la RFQ original (`5f284909…`) intacta (md5 `a71bad42…`).
- Corregido: la clave de una opción cuyo artículo es un componente nuevo salía de la etiqueta «(nuevo, pendiente de aprobación)».
- Corregido: la condición de un grupo mostraba la clave técnica de la opción; ahora el nombre del artículo o del ajuste con su suministro.

## Migración 46-06 · protección servidor de la nota (aplicada solo en mobau-pruebas, NO en Production)

- Archivos: `supabase/migrations/20261101140000_46_06_nota_linea.sql` (MD5 `dafce2250e03bdcc7258dcb78ab876f5`), recuperación `supabase/rollback/20261101140000_46_06_nota_linea.rollback.sql` (MD5 `c8a4e05856a45af4e82433042a5ecc4a`), ensayo `supabase/tests/P46_06_ensayo.sql` (rollback-only).
- Qué hace: un trigger `BEFORE UPDATE OF notes` en `project_products` con función nueva `project_products_note_guard()`. Solo actúa si `notes` cambia: rechaza el cambio si el proyecto está archivado (42501, `line_note_archived`) y rechaza un valor nuevo de más de 1000 caracteres (23514, `line_note_too_long`). No toca políticas, columnas ni otros triggers.
- Impacto: ninguna otra operación. Insert, delete, cantidad, envío de solicitudes y reactivar un proyecto no escriben `notes`. Una nota antigua más larga de 1000 caracteres no se trunca ni se borra, y actualizar otras columnas de su línea sigue funcionando (el ensayo lo prueba con una nota simulada de 1500).
- Ensayo en mobau-pruebas: OK=11, FALLO=0 (guardar en activo; rechazo en archivado; límite 1000/1001; notas antiguas largas; copias de las dos RFQ y estado idénticos al final). Revertido por diseño; verificado después con lectura independiente. Mocks de interfaz: mensajes claros en los dos rechazos.
- La migración no incluye el registro en `schema_migrations`: va aparte, tras confirmar su COMMIT.

## Incidencias abiertas

- Error transitorio en el primer guardado del formulario («Indica el artículo de cada opción de componente del grupo «Lente»»), sin reproducir con los datos guardados (pendiente de reproducción dirigida).
- Comprobación visual del bloqueo de «Solicitar cotización» por línea pendiente: **aparcada, no ejecutada en la interfaz real**. Evidencia: ensayo de servidor 07 (A10/A17) y pruebas con mocks.

## Mejoras conocidas (no bloquean)

- «Sin cambios» en el detalle de una propuesta de componentes ya aprobada compara con el estado ya aplicado: la información que muestra no es incorrecta, pero no conserva qué cambió. Un historial de comparaciones queda como mejora futura.
- La lista de moderación ya no dice «incluye componentes» cuando el artículo solo declara su uso en el catálogo.

## Pendientes de aceptación (ninguno se clasifica como bloqueante sin decisión)

| Pendiente | Requisito vigente | ¿Lo afecta el punto 46? | Evidencia disponible | Riesgo estimado (no acreditado) |
|---|---|---|---|---|
| Vista previa de impresión | El resumen preliminar del proyecto es imprimible. | Sí, en parte: el resumen muestra líneas de configuración más largas. | Prueba R3 (solo que ninguna regla de impresión oculta las líneas). No se ha visto una vista previa real. | Estético (texto cortado o salto de página). |
| Tiempos de espera y cancelación con servidor real | Las cargas del catálogo y del proyecto tienen tiempo límite y reintento, y descartan respuestas tardías. | Sí: 46 añade consultas (configuración, estado de líneas, solicitudes). | Mocks de retraso, cancelación, error y reintento pasados. Con red o servidor reales no se ha probado ningún fallo. | Estados «Comprobando…» más largos. Pérdida o duplicado de datos bajo fallo de red: no acreditado ni descartado con evidencia; las escrituras de proyecto actualizan por id y hay índices únicos en el servidor, pero no se ha probado un corte real a mitad de escritura. |
| 9 casos CC1 antiguos de catálogo | Acceso por rol en catálogo y ficha (punto 43). | Sí: 46 cambió tarjetas y ficha, y la decisión sobre Gratis cambió el panel. | **Pendientes / no ejecutados.** El arnés no se puede lanzar desde el repositorio (necesita una copia con simulador generada fuera de él). No se sabe cuáles fallarían ni por qué. | Desconocido hasta ejecutarlos. |
| Margen en móvil | Presentación de la ficha. | No de forma sustancial. | Ninguna. | Estético. |

La comprobación visual del bloqueo de «Solicitar cotización» por línea pendiente sigue **aparcada**: hay evidencia de servidor (07 A10/A17) y de mocks, no pasada de extremo a extremo.

## Recuperaciones (pendientes de validación)

- Existen los scripts inversos de 46-01 a 46-06 (`supabase/rollback/`), sin ejecutar en ningún entorno. 46-06 solo se ha ensayado hacia delante (su ensayo es de la migración, no de su recuperación).
- No se ejecutan sobre `mobau-pruebas` (conserva las pruebas actuales) ni sobre Production. No hay clon ni rama desechable, ni Docker ni PostgreSQL local; hay dos proyectos y ninguna rama.
- Propuesta operativa (a confirmar): proyecto Supabase desechable `mobau-recuperacion-46`, organización Mobau, región eu-west-1, sin complementos. Reconstrucción con los scripts 01–06 de la fotografía y las migraciones 46-01 a 46-06 aplicadas una a una, con una huella de catálogo (columnas, índices, funciones, triggers, políticas y permisos de `public`) tomada antes de cada una. Después, la cadena inversa 46-06 → 46-01 comparando cada huella con la tomada antes de esa migración, con datos sintéticos cargados para activar las guardas.
- Qué demuestra: que cada script, ejecutado desde el estado que deja la migración siguiente, restaura el estado anterior, y que la cadena completa vuelve al estado previo a 46-01. No demuestra cada script aislado desde un estado arbitrario, ni la pérdida de datos propia de revertir (se ejecuta con datos sintéticos, no con los de Production).
- Antes de crearlo hay que confirmar el coste con la plataforma y comprobar el límite de proyectos del plan gratuito (la organización ya tiene dos).

## Propuesta de entrega (sin ejecutar)

**Commit sugerido (por orden, un mensaje de una línea cada uno):**
1. Producto: `feat(componentes): formulario de distribuidor y moderación de propuestas con componentes, vista de solicitudes enviadas, nota técnica de línea y configurador reservado a Individual y Estudio` — `catalogo.html`, `componentes-propuesta.js`, `distribuidor-productos.html`, `distribuidor-propuestas.html`, `distribuidores.html`, `moderacion-acceso.js`, `moderacion-propuesta.html`, `moderacion.html`, `producto.html`, `proyectos-data.js`, `proyectos-detalle.html`, `script.js`, `scripts/pages-manifest.txt`, `seleccion-data.js`.
2. Pruebas: `test(componentes): ensayos de interfaz de componentes, nota técnica y Gratis` — `supabase/tests/44/interfaz/pruebas-44.html`, `supabase/tests/46/interfaz/*`, `supabase/tests/P46_06_ensayo.sql`.
3. Base y documentación: `chore(supabase): versionar 46-06 nota técnica con su recuperación y la documentación de entrega` — `supabase/migrations/20261101140000_46_06_nota_linea.sql`, `supabase/rollback/20261101140000_46_06_nota_linea.rollback.sql`, `supabase/46-DESPLIEGUE.md`.

**Fuera del commit:** `.claude/`, `MOBAU_CONTEXT.md`, `images/acceso/alternativa-crear/`, `supabase/registro_septiembre/` (artefactos locales). Todo lo de `~/mobau-pruebas-estructura/` y `~/mobau-copia-pruebas/` queda fuera del repositorio.

**Despliegue en Production (cuando se decida):**
1. La web solo necesita 46-06 si se quiere la protección de la nota; la interfaz funciona sin ella, y muestra el motivo si el servidor rechaza.
2. Orden: aplicar 46-06 completa (como `postgres`, una transacción), confirmar el COMMIT por lectura (trigger y función presentes) y registrar la migración en una llamada aparte; después publicar la web (`pages-build.sh`, 52 archivos).
3. Comprobar en la web publicada: guardar una nota en un proyecto activo y ver el rechazo en uno archivado.

**Recuperación:** web, volver al despliegue anterior de Pages. Base, `20261101140000_46_06_nota_linea.rollback.sql` (quita trigger y función, no toca datos), registrada como migración nueva. Los scripts inversos 46-01 a 46-06 siguen sin validar en un destino desechable.
