# Punto 46 · Componentes y accesorios: decisiones y estado de entrega

Documento vivo de entrega. Versionado en local; el push está pendiente de autorización. Las pruebas se hicieron solo en `mobau-pruebas` con datos sintéticos. En Production están aplicadas y registradas las migraciones 46-01 a 46-06; la web de esta entrega aún no está publicada.

## Decisiones de producto

- **Quién ve el configurador (decisión del 2026-10-26, sustituye a «Gratis en solo lectura»).**
  - **Gratis** (cuenta con sesión sin herramientas profesionales) **no ve el configurador**: ni el panel «Configurar», ni los grupos, opciones, componentes anidados o avisos internos. Ve la ficha normal del producto (imágenes, descripción, acabados, información no exclusiva). No hay otra vía para añadir al proyecto un producto que requiere configuración. No se muestra tarjeta promocional ni aviso de mejora de plan.
  - **Individual y Estudio con acceso habilitado** conservan el configurador interactivo.
  - **Visitantes sin sesión** (decisión del 2026-10-27, que sustituye a «mantienen el comportamiento anterior»): tampoco ven el bloque de componentes. Sin sesión y con Gratis la ficha no muestra grupos, opciones, componentes anidados ni enlaces «Ver ficha», ni un panel de solo lectura ni un bloque bloqueado; si no se puede comprobar el acceso se trata como sin acceso. El distribuidor dueño y la cuenta de Mobau conservan su panel de solo lectura. No cambian la vista transversal, las URL directas de las fichas ni los permisos de descarga.
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

- **Componentes consultables (decisión del 2026-10-27, a raíz del alta real de Malta; implementado en local, sin publicar).**
  - Laguna detectada: un artículo «solo componente» estaba publicado y bien dado de alta, pero solo se llegaba a su ficha tecleando la URL; el configurador no enlazaba a él y no había vista ni búsqueda de componentes.
  - **«Ver ficha»** junto a cada opción de componente del configurador (interactivo y de solo lectura, también anidados): enlace normal a `producto.html?id=…` en otra pestaña (`target="_blank"`, `rel="noopener"`, aviso accesible), fuera de la etiqueta de la opción. La página del configurador no cambia.
  - **Vista «Componentes y accesorios»** dentro del catálogo (`catalogo.html`): la vista de productos es la principal y predeterminada; un enlace secundario de texto «Componentes y accesorios» bajo el buscador (y «← Volver a productos» dentro de la vista), accesible con teclado, más el enlace directo `?vista=componentes`: lista los artículos «componente» y «ambos». Es una vista transversal a las seis categorías, no una categoría. Tarjetas solo con «Ver ficha»; el precio sigue las reglas de siempre por cuenta y plan.
  - **Los «solo componente» siguen fuera del catálogo principal** (listado, búsqueda y relacionados).
  - **Decisión del 2026-10-27 (sustituye a «no añadible por separado»):** «principal / componente / ambos» decide **dónde aparece** el artículo, no si se puede solicitar. Los tres se solicitan por separado (por ejemplo, un recambio) con los permisos por cuenta y plan de siempre, desde su ficha y desde la vista de componentes; sin duplicar artículos ni referencias. Solo un valor de función desconocido (dato anómalo) no se ofrece para solicitar. Se mantienen la ocultación del bloque de componentes sin sesión y con Gratis y la separación entre Productos y Componentes.
  - **Grupos obligatorios y opcionales (sin migración, sin 46-07):** «obligatorio» significa obligatorio **para solicitar**; un accesorio técnicamente necesario puede ser opcional si el cliente puede tenerlo ya o conseguirlo por otra vía. Es una propiedad de cada grupo, y no se generaliza: los demás grupos siguen obligatorios si el distribuidor lo exige. Con «Ninguna» no se añade nada automáticamente. Dos configuraciones distintas del mismo artículo y acabado son líneas distintas (la unicidad es proyecto + artículo + acabado + configuración). **Pendiente (lo hace el usuario, no realizado):** cambiar el grupo «Drivers» del módulo Malta a «Opcional» con Proponer cambios y moderación; hasta entonces, pedir el módulo suelto o la carcasa con módulo sigue exigiendo driver en Production.
  - **Textos de estado:** «Falta una elección exigida para solicitar» (sin cambios de comportamiento), «Elecciones registradas según el catálogo actual» (sustituye a «completa/completas») y, una sola vez por bloque, «Mobau no valida la compatibilidad técnica entre piezas.» (ficha, selección, proyecto, resumen, cotización y solicitudes enviadas). No hay avisos de «pieza faltante».
  - **Interfaz de gestión:** «Mis productos» muestra una etiqueta informativa Principal / Componente / Ambos; el contador por distribuidor dice «N productos de catálogo»; el formulario del distribuidor y la moderación explican la función en esos términos.
  - **Búsqueda por referencia** (completa o parcial) en el catálogo principal y en la vista de componentes. Cada vista busca solo dentro de su propia lista, así que la referencia de un «solo componente» no lo trae al catálogo principal.
  - **Sin cambios:** visibilidad de la vista, permisos de fichas y descargas, Cloudflare Access y migraciones (no hay ninguna migración en este cambio).
  - Pruebas con mocks: `pruebas-grupos-46.html`, casos V1–V13 y Q15/Q15g (128/128); `pruebas-44.html` 39/39 (se actualizó su caso P06 por la nota técnica).
  - **Limitaciones declaradas de este cambio:** la comprobación con Malta en Production está pendiente (solo hay evidencia con mocks y con la copia de pruebas con datos sintéticos); las descargas no se probaron en esta revisión y el código de permisos no cambia; Estudio no tiene un caso diferenciado de Individual en los mocks (comparten el acceso profesional).
  - **Pendiente aparte (decisión de no cambiarlo ahora):** revisar la política de descargas para Gratis. Hoy `can_download_product_file` exige rol individual o estudio y no comprueba el plan, por lo que Gratis descarga archivos de cualquier producto (comportamiento del punto 44).
  - **Pendiente aparte, lo hace el usuario por «Proponer cambios» y moderación:** retirar del módulo Malta el archivo de Norway (`1.1112.0118.ldt`) y, temporalmente, `1.1122.0218 - 24D.ldt` mientras se valida. No está hecho.

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

- **Estabilidad de dos pruebas con mocks (G15 y P10, `pruebas-grupos-46.html`), abierta.** En una ejecución con el panel del navegador oculto fallaron G15 (esperaba `["error", true, …]`, obtuvo `["error", false, …]`) y P10 (esperaba tarjetas «pending» y 0 consultas, obtuvo «configurable» y 1 consulta); con el panel visible la serie completa pasó (128/128). Causa **no confirmada**: hipótesis de que con el panel oculto los temporizadores se desfasan, porque ambos casos dependen de plazos o del momento de una respuesta. Una ejecución posterior (2026-10-27) con el panel oculto volvió a fallar Q10, otro caso con plazo (4–6,5 s), y pasó con el panel visible: más indicios de la misma hipótesis, tampoco demostrada. Otra incidencia de entorno: el navegador de pruebas conservó copias antiguas de los archivos del sitio (cabeceras de caché) y provocó fallos espurios hasta forzar su recarga. No se aisló ni se repitió la ejecución oculta. Los casos no se han modificado ni debilitado.
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

## Ensayo de servidor v2 · solicitar componentes por separado (2026-10-27, mobau-pruebas)

- Archivo `~/mobau-pruebas-estructura/12_ensayo_solicitud_componentes_v2.sql` (MD5 `7ca09953407dae607c83730f1e5c4893`), ejecutado **una sola vez** en `mobau-pruebas` (`icuhaivgmfbgsmpffcjv`), con datos sintéticos y todo revertido por diseño. Resultado aceptado: **OK=13, FALLO=0**.
- Casos: R0 (3 referencias sintéticas no nulas, solo dentro de la transacción), C0a/C0b (el requisito del grupo Driver decide pendiente o completa), T1 (driver solo), T2 (módulo solo con Driver opcional), T3 (módulo con driver: copia con referencias, suministro y cantidad leídos de los datos), T4a/T4b (dos configuraciones del mismo producto y acabado = dos líneas; duplicada, 23505; copia de la RFQ con las referencias exactas), T5 (elección necesaria pendiente: 23514 `configuration_pending`, sin RFQ), T6 (Gratis: 42501 en proyecto, línea y RFQ), I1a, I1b, I2.
- Diagnóstico observado de I1b: la única columna distinta de la línea base dentro de la transacción es `grupos.updated_at` (el trigger de `updated_at` usa `now()`), con 5 grupos y 10 opciones como al inicio.
- Lectura independiente antes y después: grupos y opciones `4ef10b94…`, proyectos+líneas+RFQ `0368ad1f…`, products `d40e683a…`, estructura `86133b1d…`, Driver «necesario» con el mismo `updated_at`, 0 referencias en products, 7 usuarios, 0 sesiones, 2 objetos de Storage, sin rastros del ensayo. Sin cambios persistentes.
- **Limitación conservada:** el driver «aparte» no tiene un caso propio. En los datos sintéticos el driver es «incluido» y solo el módulo es «aparte» (T4b). No se probó un driver «aparte» con su cantidad total.
- No se repite ni se amplía.

## Inicio del alta «Producto o componente» (local, sin commit ni push)

- «Mis productos»: el acceso se llama «Crear producto o componente». El alta empieza con «¿Qué quieres crear?»: **Producto** o **Componente o accesorio**; después Categoría, Subcategoría y el resto.
- La elección es la única fuente de la función (`catalog_role`), sin campo ni migración nuevos y sin segundo selector. Se puede corregir antes de guardar sin perder datos y queda visible al guardar y reabrir. Producto sin grupos no guarda función (queda principal); un componente creado desde un producto llega con la elección fijada.
- Artículos existentes: no se convierten. En edición no hay selector: se muestra su función actual como información («ambos» se conserva al guardar y enviar). Un borrador de alta anterior con «ambos» lo conserva hasta que se elija otra opción.
- **«Cambiar función» (artículos existentes):** la función actual es informativa y una acción secundaria «Cambiar función» abre Producto / Componente o accesorio / Ambos. El cambio es explícito, muestra «Propuesta de cambio de función: A → B», se puede deshacer antes de enviar y va por la moderación habitual (`proposed_components.catalog_role`); el artículo publicado no cambia hasta que se apruebe. «Ambos» solo se asigna si se elige; ningún borrador ni artículo se reclasifica por abrirlo o guardarlo.
- **Aviso anticipado (solo de cliente):** al pasar de Componente o Ambos a Producto, el formulario lee con la política de lectura propia (`product_component_options_select_own` y la de grupos) qué artículos propios lo usan en opciones activas de grupos activos; si los hay, deshabilita Producto y los nombra. Si esa lectura falla, deja Producto habilitada y avisa de que Mobau validará el cambio al aprobar. No se amplían permisos ni el servidor: la garantía es la regla 3a de 46-01 y la comprobación final de 46-03 (revierte la aprobación incompatible). **Limitación:** el aviso puede estar desfasado y no ve usos desde propuestas aún sin aprobar.
- **Reclasificación y RFQ/proyectos (diagnóstico de lectura):** las líneas de proyecto no guardan la función y la copia `lines_snapshot` de una RFQ es inmutable y no la incluye; ninguna reclasificación, aprobada o no, las altera. No se ejecutó un ensayo del caso bloqueado (los ensayos existentes cubren el cambio de función solo en artículos sin uso).
- **Corrección en moderación:** la consulta del producto actual no incluía `catalog_role`, así que el detalle habría mostrado siempre «Producto» como función actual; ahora la pide (columna ya legible por `authenticated`).
- Etiquetas de función unificadas: «Producto», «Componente o accesorio», «Principal y también componente»; en moderación, «Función en el catálogo: …».
- Pruebas locales con mocks: `pruebas-alta-46.html` (59/59, formulario, «Cambiar función» y moderación), más `pruebas-componentes-propuesta-46.html` 79/79, `pruebas-seleccion-46.html` 25/25, `pruebas-proyecto-46.html` 54/54 y `pruebas-grupos-46.html` 142/142 (con el panel visible). No se probó la subida real de la portada ni nada contra servicios externos.
- Archivos nuevos de prueba: `mock-alta-46.js`, `pruebas-alta-46.html`; `sw-paginas-46.js` inyecta además `mock-alta-46.js`.
