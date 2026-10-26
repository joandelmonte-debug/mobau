# Punto 46 · Componentes y accesorios: decisiones y estado de entrega

Documento vivo de entrega. Versionado en local; el push está pendiente de autorización. Las pruebas se hicieron solo en `mobau-pruebas` con datos sintéticos. En Production están aplicadas y registradas las migraciones 46-01 a 46-06; la web de esta entrega aún no está publicada.

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

## Migración 46-06 · protección servidor de la nota (aplicada y registrada en Production el 2026-10-26)

- Archivos: `supabase/migrations/20261101140000_46_06_nota_linea.sql` (MD5 `dafce2250e03bdcc7258dcb78ab876f5`), recuperación `supabase/rollback/20261101140000_46_06_nota_linea.rollback.sql` (MD5 `c8a4e05856a45af4e82433042a5ecc4a`), ensayo `supabase/tests/P46_06_ensayo.sql` (rollback-only).
- Qué hace: un trigger `BEFORE UPDATE OF notes` en `project_products` con función nueva `project_products_note_guard()`. Solo actúa si `notes` cambia: rechaza el cambio si el proyecto está archivado (42501, `line_note_archived`) y rechaza un valor nuevo de más de 1000 caracteres (23514, `line_note_too_long`). No toca políticas, columnas ni otros triggers.
- Impacto: ninguna otra operación. Insert, delete, cantidad, envío de solicitudes y reactivar un proyecto no escriben `notes`. Una nota antigua más larga de 1000 caracteres no se trunca ni se borra, y actualizar otras columnas de su línea sigue funcionando (el ensayo lo prueba con una nota simulada de 1500).
- Ensayo en mobau-pruebas: OK=11, FALLO=0 (guardar en activo; rechazo en archivado; límite 1000/1001; notas antiguas largas; copias de las dos RFQ y estado idénticos al final). Revertido por diseño; verificado después con lectura independiente. Mocks de interfaz: mensajes claros en los dos rechazos.
- La migración no incluye el registro en `schema_migrations`: va aparte, tras confirmar su COMMIT.
- **Production (`mobau-pilot`, `skcoxtdppdcietgojdal`), aprobado por separado:**
  - Aplicada sin modificaciones (SHA-256 `7b2175df94bdfc9ff15ea647693b7261ca674d2880819142e40b5b7c8530d7ee`), en una sola transacción, como `postgres`, sin errores.
  - Verificado por lectura: trigger `trg_project_products_20_note` presente y habilitado junto al trigger de configuración; función `project_products_note_guard()` presente, sin `SECURITY DEFINER` y con `search_path` vacío; sin permiso de ejecución para `public`, `anon` ni `authenticated`; datos sin cambios (0 notas, 18 líneas, 8 proyectos, 2 RFQ, 21 propuestas, 31 productos).
  - Registrada después, aparte (`20261101140000 · 46_06_nota_linea`, solo versión y nombre, como 46-05): 53 entradas, la versión aparece una sola vez y es la última. Esquema y registro coinciden.
  - No se ha creado ni editado ninguna nota real en Production.

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

## Respaldo previo a la publicación: PARCIAL (declaración de alcance)

- Es una salvaguarda puntual para esta publicación, lo mejor disponible hoy. **No es una copia completa del proyecto ni un plan de continuidad suficiente a medio plazo.**
- Procedimiento: `~/mobau-respaldo-produccion/respaldo.sh` (fuera del repositorio), un volcado consistente de solo lectura de `public`, `auth`, `storage` (solo metadatos), `mobau_private` y `supabase_migrations`, con estructura, datos y permisos de objetos.
- **Excluye:** los archivos binarios de Storage (133 objetos, unos 102 MB en `productos-imagenes` y `productos-archivos`), definiciones y contraseñas de roles, los esquemas gestionados por la plataforma, los ajustes de Auth y del proyecto, y la configuración de Cloudflare.
- **Estado de restauración: no restaurado y no probado.** Hasta que se restaure en un entorno aislado, solo acredita que el volcado se generó y es legible (lista de contenido y recuento de filas por tabla), no que sirva para reconstruir el servicio.
- Contiene datos reales de Auth (correos y hashes de contraseña): no se versiona, no se comparte y queda con permisos solo del propietario.
- Verificación en vivo de Production antes de aplicar 46-06 (2026-10-26, solo lectura): 52 migraciones registradas con 46-01 a 46-05 y sin 46-06; la columna `notes` existía, el trigger y la función no; 0 líneas con nota.
- **Respaldo generado y comprobado, sin restauración probada.** Carpeta local `~/mobau-respaldo-produccion/2026-10-26_2245` (fuera del repositorio y de la web; archivos con permisos solo del propietario).
  - Archivos: `produccion_completo.dump` (748 471 bytes, SHA-256 `b50a1d801d618362c3eadafae9477db2224d7035d179b00cf58c65b44e0f2cd0`; «completo» es solo el nombre del archivo, **su alcance sigue siendo parcial**, como se detalla arriba; el nombre y el contenido no se han modificado), `produccion_estructura.sql`, `contenido_del_volcado.txt`, `filas_por_tabla_en_el_volcado.tsv` y `MANIFIESTO.txt`.
  - Comprobado: las huellas coinciden con el manifiesto; el volcado se lista con `pg_restore --list` (961 entradas, 62 tablas con datos); los conteos de las 38 tablas con filas coinciden con Production, contrastados por lectura. Las 24 tablas vacías del volcado no se contrastaron. Los conteos comparan cantidades, no el contenido de las filas.
  - Se tomó antes de aplicar 46-06 (no contiene su trigger ni su función). Cada conexión propia fue de solo lectura y no se intentó ninguna escritura.
  - **No restaurado y no probado:** no se ha cargado en ningún entorno.
- Pendiente tras la publicación (no bloquea esta): plan de madurez operativa, con copias recurrentes de base y Storage, restauración del servicio completo probada en un entorno aislado, documentación de la configuración crítica (Supabase, Cloudflare, variables, accesos, reversión) y calendario de comprobaciones de restauración.

## Estado de entrega y publicación (2026-10-26)

**Commits locales, sin push (tres por delante de `origin/master`):**
1. `4701fea` · producto: formulario y moderación de componentes, solicitudes enviadas, nota técnica de línea, productos solo componente y configurador reservado a Individual y Estudio (14 archivos).
2. `415f129` · pruebas de interfaz y ensayo de 46-06 (7 archivos).
3. `c21a4d4` · migración y recuperación de 46-06 y este documento.

**Production:**
- Base de datos: 46-06 aplicada y registrada (53 migraciones). 46-01 a 46-05 ya lo estaban.
- **Web: pendiente de publicar.** Production sirve `19c4d70`. Cloudflare Pages construye con `bash scripts/pages-build.sh` y publica `dist` (52 archivos); la rama de producción es `master` con despliegues automáticos, así que **cada push a `master` publica automáticamente**. Cualquier cambio de este documento que se incluya en el push también dispara el build.
- Hasta publicar la web, la protección de la nota existe en el servidor pero la interfaz de notas no está disponible. La web anterior no escribe `notes`, así que la combinación es compatible.

**Publicación de la web (cuando se apruebe, aparte):** commit del documento, `git push origin master` y esperar el despliegue en verde en Cloudflare.

**Comprobación posterior sin modificar datos:** despliegue en verde con el commit esperado; el catálogo carga; la ficha con configuración sigue abierta con Individual y Gratis no ve el panel; «Mis proyectos» muestra «Solicitudes enviadas» con las RFQ existentes; por lectura, 53 migraciones, trigger presente y mismos conteos. La prueba de una nota real se hará solo tras acordar proyecto y contenido.

**Reversión:** web, volver en Cloudflare (Deployments) al despliegue `19c4d70`, o `git revert` y push. Base, `20261101140000_46_06_nota_linea.rollback.sql` (quita trigger y función sin tocar datos; sin validar en un destino desechable) o corrección hacia delante, registrando cualquier cambio como migración nueva. Datos: solo existe el respaldo parcial, sin restauración probada.

**Dentro del repositorio, sin seguimiento y excluidos de los commits** (siguen físicamente en la carpeta del proyecto): `.claude/`, `MOBAU_CONTEXT.md`, `images/acceso/alternativa-crear/` y `supabase/registro_septiembre/`.

**Directorios externos al repositorio** (bajo `~/`, nunca en la carpeta del proyecto ni en la web): `~/mobau-pruebas-estructura/`, `~/mobau-copia-pruebas/` y `~/mobau-respaldo-produccion/`.

## Pendientes operativos (no resueltos)

- **Respaldos recurrentes** de base de datos y de archivos de Storage (133 objetos, unos 102 MB, que el respaldo actual no incluye), con una opción de recuperación verificada de verdad en el plan actual de Supabase (hoy se parte de que el plan Free no ofrece copias automáticas; sin comprobar con el proveedor).
- **Restauración del servicio completo probada desde respaldos**, en un entorno aislado: base de datos, archivos de Storage y la configuración necesaria (Auth, roles, ajustes de Supabase y Cloudflare). Hoy no hay respaldo de Storage ni de configuración y el volcado de la base no se ha restaurado nunca.
- **Validación de los scripts inversos 46-01 a 46-06 en un destino desechable**, como criterio de aceptación independiente de la restauración anterior y también pendiente (sin destino disponible; no se ejecutó ninguno en ningún entorno). Su resultado no sustituye a la restauración del servicio ni al revés.
- **Documentación de la configuración crítica** (Supabase, Cloudflare, variables, accesos y reversión) y **calendario de comprobaciones de restauración**, no solo de creación de copias.
