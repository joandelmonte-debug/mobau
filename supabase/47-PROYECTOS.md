# Punto 47 — Proyectos por áreas y filas compactas

Documento de alcance y progreso. **Fase actual: prototipo local para revisión visual.** No hay implementación de datos, migraciones, commit ni push.

## Objetivo
Que la página de proyecto sirva para trabajar con 20–100 líneas: organizar productos por espacios (áreas), identificar configuraciones y consultar importes conocidos, sin formularios de nota permanentemente abiertos ni filas muy altas.

## Diseño aprobado (referencia de implementación)
Aprobado tras cuatro revisiones; no se hacen más ajustes estéticos por iniciativa propia. Resumen de lo que fija la implementación (el detalle está en las secciones siguientes y en el prototipo):
- **Simplicidad por defecto:** proyecto sin áreas = lista normal (sin «Sin área», sin filtro ni gestión de áreas, sin selector de área en filas ni al añadir); la organización es opcional y desaparece al borrar la última área.
- **Cabecera:** nombre y estado; «Añadir productos ▾», «Ver resumen preliminar», «Solicitar cotización» y, al extremo derecho, el icono de archivar en rojo teja con tooltip «Archivar proyecto / Puedes recuperarlo o eliminarlo desde Archivados.».
- **Cuadro económico** bajo la cabecera (importe conocido, barra de cobertura con leyenda, aviso de importe preliminar) y, con filtro, el cuadro del resultado filtrado; **una sola moneda**.
- **Barra:** búsqueda a todo el ancho + «Categoría ▾» + «Organizar por áreas ▾» (crear primera área, filtrar, gestionar, plegar/desplegar).
- **Filas compactas**, notas y configuraciones desplegables, avisos importantes visibles, selección múltiple solo al seleccionar.
- **Archivar** archiva (también un proyecto vacío) y nunca elimina; **eliminar** solo desde Archivados, con las protecciones de solicitudes; restaurar según las reglas vigentes.
- Conflictos al mover, copiar o eliminar un área: se resuelven antes, sin fusiones silenciosas ni pérdida de notas, cantidades o configuración.

## Propuesta técnica recomendada (fase 3)

### A. Servidor: una sola migración aditiva `47-01`
1. **Tabla `public.project_areas`** (`id uuid`, `project_id → projects ON DELETE CASCADE`, `name` 1–60 caracteres sin espacios sobrantes, `position int`, `created_at`, `updated_at`). Nombre único por proyecto sin distinguir mayúsculas; como máximo 50 áreas por proyecto (trigger). El orden es `position, created_at, id`; reordenar son dos `UPDATE` (sin unicidad en `position`, así que no hay choques).
2. **Columna `project_products.area_id`** (`uuid null → project_areas ON DELETE SET NULL`; `NULL` = «Sin área»). Se añade `area_id` a los `UPDATE` permitidos de `authenticated` (hoy: `quantity, unit, notes, room_or_area, selected_for_rfq, order_position`); el resto no cambia.
3. **Identidad de línea por área.** Se crea `project_products_area_line_unique (project_id, product_id, coalesce(finish_code,''), config_key, coalesce(area_id, <uuid nulo>))` y después se elimina `project_products_config_line_unique` (mismo patrón que 46-05). Es una unicidad **más débil** que la actual (añade una columna), así que ninguna fila existente puede violarla; con `area_id` nulo el comportamiento es idéntico al de hoy.
4. **Dos funciones pequeñas, `SECURITY INVOKER` y con `search_path` vacío** (la RLS sigue aplicando), para lo que debe ser atómico: `project_lines_transfer(p_line_ids, p_area_id, p_kind 'move'|'copy', p_resolutions jsonb)` y `project_area_delete(p_area_id, p_resolutions jsonb)`. Sin conflicto hacen el movimiento o la copia (copia: mismo producto, acabado, configuración, cantidad, unidad y nota, que luego quedan independientes). Con una línea equivalente en el destino **exigen una resolución explícita por línea** (`sum` con elección de nota `existing | incoming | both`, `move` a otra área o `skip`); sin ella abortan con `23514` y pista `transfer_conflict` / `area_conflict`, **sin cambiar nada**. Bloquean las filas implicadas para evitar carreras.
5. **Copia de RFQ.** `project_request_lines` añade a cada línea `area_id`, `area_name` y `area_position`; `rfqs_lines_snapshot` añade a la copia (que sigue generándose en el servidor e inmutable) un arreglo `areas` con las áreas usadas por las líneas solicitadas (id, nombre y posición) y sube `version` a 2. Son claves nuevas: el lector actual (`distributors`, `lines`) sigue funcionando y **las RFQ ya enviadas no se tocan** (su copia es inmutable y no se vuelve a generar).
6. **Políticas de `project_areas`**, copiando el patrón vigente de `project_products`: permisivas de propietario (select/insert/update/delete por el dueño del proyecto) y restrictivas ya existentes para los demás roles (proveedor sin escritura; escritura solo con `my_professional_access()`; Gratis sin acceso, `D3`; estudio propio). Guarda opcional y barata: sin cambios de áreas en proyectos archivados (como el trigger de notas de 46-06).
7. **`room_or_area` (texto) no se toca**: se conserva tal cual, sigue viajando en la copia de RFQ y la interfaz nueva no lo usa. Su contenido real se desconoce desde el repositorio (ver «Lecturas necesarias»); **nunca se sobrescribe**. Si resulta que hay datos, la opción es una importación puntual **aparte y autorizada** (un área por valor distinto y por proyecto, asignando sus líneas), no automática.

### B. Interfaz (cambios por archivo)
- `proyectos-detalle.html`: rehacer la lista según el prototipo (cabecera con icono de archivar, cuadro económico, barra, filas compactas, áreas, notas y configuraciones desplegables, conflictos, modo de solo consulta). Se reutilizan `MobauLineConfig`, `getPriceInfo`, `priceAccessInfo`, `loadPricesFor` y `project_line_states`.
- `proyectos-data.js`: CRUD de áreas; `saveProductToProject` y la transferencia desde selección reciben `areaId` y buscan la línea por producto + acabado + configuración + área; `listProductsInProject` trae `area_id`; llamadas a las dos funciones; **`excludeFromRfq` pasa a actuar por identificador de línea, no por producto**.
- `proyecto-importes.js` (nuevo, compartido): el cálculo del prototipo (`calc`, `aggregate`: precio del principal × cantidad, componentes aparte con cantidad fija, incluidos sin doble suma, «a calcular»/sin precio = incompleta, configuración pendiente fuera del importe) para detalle, resumen y solicitud. Se añade a `scripts/pages-manifest.txt`.
- `proyectos-resumen.html` y `proyectos-cotizacion.html`: lista normal sin áreas; seccionada con áreas (también la vista previa de la solicitud); sin pasos extra; se pide siempre el proyecto completo.
- `proyectos.html`: «Archivar» **archiva siempre**, también un proyecto vacío (hoy lo elimina: se corrige aquí y en el detalle); «Eliminar» solo en Archivados, oculto en proyectos con solicitudes, como hoy.
- `seleccion.html` + `seleccion-data.js`: al incorporar al proyecto activo, selector de área opcional que solo aparece si el proyecto tiene áreas.
- Si la web se publicara antes que la migración, las consultas de áreas fallarían (`42P01`): la interfaz las trata como «áreas no disponibles» y se comporta como lista sencilla.

### C. Importes y moneda (limitación pendiente)
Se reutiliza el mecanismo existente: precios de `catalog_published_prices` (una consulta adicional para los componentes, ya implementada) y los permisos de precios de hoy. **Hoy todo precio es USD** (restricción `product_prices_currency_usd`, el cliente formatea «US$», no hay preferencia ni tipo de cambio), así que la primera versión muestra **una sola moneda: USD**. El escenario DOP del prototipo queda como referencia; implementarlo exige antes la decisión de la fuente de los pesos (precios publicados en pesos o tipo de cambio con fecha y origen) y no se hace ahora.

### D. Compatibilidad y orden de despliegue
- **Proyectos existentes:** no se crea ningún área; todas las líneas quedan con `area_id` nulo y se ven como lista sencilla; orden (`order_position`), cantidades, notas y configuraciones intactos. `room_or_area` se conserva.
- **Orden:** (1) migración `47-01` en Production, aditiva y compatible con la web actual (sin áreas el comportamiento es el mismo; las claves nuevas de la copia se ignoran); (2) registro de la migración tras confirmar su `COMMIT`; (3) publicación de la web (un único commit coherente). Una pestaña con la web antigua abierta sobre un proyecto que ya tenga áreas podría sumar cantidad a una línea de un área en vez de a «Sin área»: efecto menor y acotado a esa ventana.
- **Historial:** las RFQ enviadas no se modifican; las nuevas llevan `areas` y `area_*`.

### E. Riesgos y recuperación
- **Reemplazo de las dos funciones de la copia de RFQ** (afecta a toda solicitud nueva): ensayo rollback-only que compare las copias existentes antes y después y genere una nueva con y sin áreas; recuperación = restaurar las definiciones de 46-04 (huellas registradas).
- **Cambio de índice:** al ser más débil no puede fallar con datos actuales; recuperación del índice antiguo solo si ningún proyecto repite la misma identidad en áreas distintas (el script de recuperación lo comprueba y aborta listando los casos).
- **Funciones de conflicto:** mayor superficie lógica; se cubren con casos de conflicto, cancelación y bloqueo concurrente.
- **Rendimiento con 100 líneas:** la resolución de configuraciones es por línea (ya existente); se mide en el escenario de 100 líneas con el panel visible.
- **Datos en `room_or_area` desconocidos:** se leen antes de decidir nada (abajo).
- **Recuperación general:** script inverso (`DROP` de funciones y tabla, restaurar funciones de 46-04 e índice, quitar `area_id`), respaldo previo reciente y sin tocar datos de `project_products` salvo `area_id`. Las áreas creadas se pierden en una recuperación (se avisa).

### F. Validación proporcionada (reutilizando lo existente)
- **Servidor** (un ensayo rollback-only en `mobau-pruebas`, en el patrón de los ensayos 46): lista sencilla sin áreas (comportamiento idéntico); mismo producto + acabado + configuración en áreas distintas y rechazo del duplicado en la misma área; mover y copiar con y sin conflicto, con notas iguales y distintas; eliminar área con conflicto y cancelar sin cambios; notas y configuraciones conservadas; copia de RFQ con áreas y copias antiguas con huella idéntica; exclusión por línea; archivar un proyecto vacío y uno con productos sin eliminar; eliminar solo archivado y sin solicitudes (`23503` si las hay); RLS por rol y plan (Gratis, propietario ajeno, proveedor) sin ampliar permisos.
- **Interfaz** (se amplía el mock de proyecto de 46 y se reutiliza el arnés del service worker): cantidades, cobertura y una sola moneda, permisos de precios, resumen y solicitud con y sin áreas, historial, conflictos, y los escenarios de escritorio, móvil y 100 líneas, con captura frente al prototipo. Las series cerradas de 46 se vuelven a ejecutar solo donde se toque `proyectos-*`/`seleccion-*`.
- No se preparan ensayos redundantes.

### G. Orden de implementación
1. Lecturas de Production (abajo) y decisión sobre `room_or_area`.
2. Migración `47-01`, recuperación y ensayo rollback-only en `mobau-pruebas`.
3. Interfaz local con mocks; ampliación del mock y de las pruebas.
4. Revisión del diff, un único commit coherente.
5. Respaldo previo; aplicar `47-01` en Production y registrar la migración; publicar la web (push); comprobación posterior sin modificar datos.

### H. Lecturas necesarias en Production (solo lectura, ninguna hasta que las autorices)
1. **Definición de `project_products.room_or_area`** (tipo, nulabilidad, valor por defecto, restricciones) y de `order_position`/`selected_for_rfq`, más índices y triggers de `project_products` y `projects`: el repositorio no contiene la definición original de la tabla y la migración debe ser exacta.
2. **Conteo de líneas con `room_or_area` no nulo ni vacío y de valores distintos por proyecto** (agregados, sin nombres de clientes): decide si hay datos que conservar o importar.
3. **Políticas (`pg_policies`) de `project_products`, `projects` y `rfqs`:** para copiarlas exactamente en `project_areas` y detectar desvíos respecto a las migraciones.
4. **Escala:** número de proyectos y máximo de líneas por proyecto, para dimensionar la validación de 100 líneas.
5. **Dependencias:** funciones o vistas que mencionen `room_or_area`.

### I. Autorizaciones que se necesitarán
(a) Las lecturas H1–H5; (b) implementar la interfaz en local y preparar migración, recuperación y ensayos; (c) ejecutar el ensayo rollback-only (y, si hace falta para las pruebas de interfaz, aplicar la migración de forma persistente) **solo en `mobau-pruebas`**; (d) refrescar el respaldo antes de Production; (e) aplicar `47-01` en Production y registrarla tras su `COMMIT`; (f) commit y push de la web, en ese orden; (g) solo si H2 muestra datos: la importación puntual de `room_or_area`.

## Criterio fundamental: simplicidad por defecto, organización avanzada opcional
Mobau no es solo para arquitectos o interioristas: cualquier persona debe poder crear un proyecto y trabajar sin áreas ni tareas de organización. No hay selector «simple/avanzado»: la misma interfaz muestra las funciones cuando se necesitan.
- **Sin áreas** (por defecto, para siempre si se quiere): lista normal de productos. Sin «Sin área», sin filtro ni gestión de áreas, sin selector de área en las filas, sin preguntar el área al añadir. Solo una acción secundaria discreta: **«Organizar por áreas»**.
- **Al organizar:** se crea la primera área; no se clasifica nada solo. Aparecen la agrupación y el filtro «Áreas»; lo no asignado queda en «Sin área»; añadir productos y «Desde mi selección» siguen sin exigir área (asignarla es opcional). Si se eliminan todas las áreas, vuelve la lista sencilla.
- **Cabecera ligera:** nombre y estado, Añadir productos (con el icono de archivar al lado), Resumen preliminar y Solicitar cotización. *(El resumen económico de una línea con «Desglose» de la segunda revisión fue sustituido por el cuadro económico: ver «Decisiones vigentes».)* Sin permiso de precios, un aviso discreto con enlace a planes y «—» en las filas.
- **Resumen y solicitud:** sin áreas, resumen normal; con áreas, seccionado. Solicitar cotización no añade pasos por admitir áreas.

## Decisiones vigentes (cuarta revisión) — sustituyen a las anteriores sobre resumen económico y acciones del proyecto
Estas decisiones **sustituyen** a las de las revisiones anteriores en lo siguiente (el resto sigue vigente: filas compactas, notas y configuraciones desplegables, áreas opcionales, avisos visibles y moneda única):
- **Resumen económico:** vuelve el **cuadro independiente bajo la cabecera** (sustituye a la línea única con «Desglose»): «Importe conocido» bien visible, barra de cobertura con su leyenda y el aviso «Importe preliminar… No es una cotización final». Todo en **una sola moneda de visualización** (USD o DOP); no vuelve la mezcla de monedas. Con filtro activo aparece al lado el cuadro «Resultado filtrado». Sin permiso de precios se mantiene el aviso discreto con «Ver planes».
- **Barra de búsqueda:** `[ Buscar en el proyecto (ancho flexible) ] [ Categoría ▾ ] [ Organizar por áreas ▾ ]`, mismo alto y estilo; el borde derecho de «Organizar por áreas» queda alineado con el del listado. No hay más botones («Áreas», «Gestionar áreas», «Plegar/Desplegar todo» salen de la barra) ni contador de líneas (el recuento está en la cabecera y en el cuadro). En móvil, la búsqueda ocupa una fila y los dos botones se reparten la siguiente. «Organizar por áreas ▾» contiene: sin áreas → «Crear la primera área…»; con áreas → filtrar por áreas, «Gestionar áreas…», «Plegar todas» y «Desplegar todas».
- **Archivar:** sustituye al control «Acciones del proyecto». Un botón compacto con icono de archivar (no una papelera), colocado en el **extremo derecho del grupo de acciones, justo después de «Solicitar cotización»** (orden: Añadir productos ▾ · Ver resumen preliminar · Solicitar cotización · icono), con una pequeña separación que lo distingue de las acciones principales. Color **rojo teja discreto** (icono y borde en ese tono, fondo suave, hover y foco claramente visibles, sin bloque rojo grande), para que se entienda como retirar el proyecto de la lista activa. Nombre accesible «Archivar proyecto» (`aria-label`) y tooltip por hover o foco con el texto exacto «Archivar proyecto / Puedes recuperarlo o eliminarlo desde Archivados.» (enlazado con `aria-describedby`). Pide una confirmación breve que aclara que se archiva y **no se elimina**. Se retira Archivar de «Información del proyecto» (no hay duplicado).
- **Eliminar:** se **retira de la página del proyecto** (se anula la petición anterior de eliminar desde el proyecto activo). Solo se ofrece desde **Archivados**, con confirmación que nombra el proyecto y explica qué se borra. Desde Archivados también se restaura según las reglas existentes (con Estudio y cupo; con Individual o prueba no hay restauración, como hoy). Un proyecto con solicitudes enviadas **no se puede eliminar** (se explica el motivo): se conservan la protección y las RFQ históricas. La vista de Archivados del prototipo es mínima y simulada, solo para enseñar restaurar y eliminar.

**Regla resuelta, pendiente de aplicar en las páginas reales.** Hoy «Archivar» en un proyecto **vacío no archiva: lo elimina** (archiva y borra en dos pasos, tras una confirmación que dice «se eliminará de forma permanente»). Pasa en `proyectos-detalle.html` (botón «Archivar») y en `proyectos.html` (la tarjeta del listado, que también llama a `deleteProject()` tras archivar). **Decisión:** Archivar archiva **también un proyecto vacío y nunca lo elimina**; la eliminación explícita existe únicamente en Archivados, con confirmación y respetando las protecciones de solicitudes enviadas. Esta regla **tendrá que aplicarse después tanto en el detalle como en el listado de proyectos**; todavía no se ha cambiado ninguna página real (el prototipo ya la cumple: Archivar siempre archiva).

## Autorización vigente
Solo: (1) lectura breve del código y las migraciones y (2) prototipo local interactivo con mocks. Sin consultas a Production, escrituras externas, migraciones, cambios en páginas publicadas, commit ni push.

## Progreso
| Fase | Estado |
|---|---|
| 1. Lectura breve del código (mapa de cambios y límites) | **Hecha** (abajo) |
| 2. Prototipo local con mocks | **Aprobado** (referencia de implementación: `supabase/tests/47/interfaz/prototipo-proyecto-47.html`) |
| 3. Propuesta técnica (modelo, migración, RFQ, validación) | **Hecha (abajo), pendiente de autorización** |
| 4. Implementación local, migración y ensayos | No iniciada: requiere las autorizaciones de «Autorizaciones que se necesitarán» |

## Cómo abrir y usar el prototipo
Servir la raíz del repositorio (por ejemplo `python3 -m http.server 8046` o el servidor `mobau-local-46`) y abrir  
`http://127.0.0.1:8046/supabase/tests/47/interfaz/prototipo-proyecto-47.html`.
- Barra negra superior, claramente separada y rotulada «DEMOSTRACIÓN» (no forma parte de la interfaz): elige el **caso** (A proyecto vacío · B 5 productos sin áreas · C 20 productos por áreas · D 100 líneas), **precios con acceso / sin permiso (Gratis)**, **moneda USD / DOP**, **estado del proyecto** (Activo · Archivado · Solicitud enviada) y **plan** (Individual · Estudio, que solo afecta a reactivar); «Reiniciar caso» recarga los datos.
- Atajos por dirección: `?caso=a|b|c|d`, `?precios=0`, `?moneda=dop`, `?estado=archivado|solicitud`, `?plan=individual`, `?demo=detalles|nota|filtro|menu|resumen|solicitud|areas|seleccion|organizar|conflicto|desglose|acciones|archivar|eliminar|conflicto-area`.
- Todo está en memoria: recargar la página lo reinicia. No hay red ni Supabase; los importes, referencias y nombres son sintéticos (solo las referencias 1.1120.8111 y 1.1122.0218 recuerdan a la familia Malta).

## Lectura breve del código: qué habría que tocar

**Página de proyecto (`proyectos-detalle.html`, 1523 líneas).** Layout de dos columnas (ficha fija a la izquierda, listado a la derecha); cada fila (`renderProductRow`) es una tarjeta alta con nombre, detalle, líneas de configuración, **textarea de nota siempre abierto** (`noteHtml`), cantidad, precio y «Quitar»; filtro de categoría (`renderCategoryFilter`) y resumen de precio (`buildProjectPriceSummaryHtml`, `buildFilteredPriceSummaryHtml`). Hay que rehacer cabecera, listado y notas; se puede reutilizar `MobauLineConfig`, `getPriceInfo` y `priceLineHtmlForQuantity`.

**Resumen preliminar (`proyectos-resumen.html`) y solicitud (`proyectos-cotizacion.html`).** Listan las líneas planas y calculan el total con `price × cantidad` del producto principal. Habría que seccionarlos por áreas y sumar componentes aparte.

**Datos (`proyectos-data.js`).** `listProductsInProject` ordena por `order_position, created_at`; `saveProductToProject` busca la línea existente por producto + acabado + clave de configuración y **actualiza o inserta**; `transferSelectionToProject` la llama por cada elemento de la selección (modo `replace`); `updateLineNote` solo escribe `notes`; `excludeFromRfq` marca `selected_for_rfq = false` **por `product_id`**.

**Modelo.**
- `project_products` ya tiene `room_or_area` (texto, hoy sin uso en la interfaz), `order_position` y `selected_for_rfq`, y `authenticated` puede actualizar esas columnas (38-B 04: `quantity, unit, notes, room_or_area, selected_for_rfq, order_position`).
- **Unicidad (punto clave).** El único índice vigente es `project_products_config_line_unique (project_id, product_id, coalesce(finish_code,''), config_key)` (46-04; 46-05 retiró el anterior). **No incluye el área**, así que hoy el mismo producto + acabado + configuración **no puede estar en dos áreas** del mismo proyecto: el segundo insert da `23505`, y `saveProductToProject` lo fusionaría como «ya existe». Para permitirlo hay que **ampliar el índice con el área** (nueva migración) y hacer que la búsqueda de línea existente también compare el área. Con `room_or_area` como texto la identidad sería (producto, acabado, configuración, texto de área); con un `area_id` sería por identificador.
- **Áreas como entidad.** `room_or_area` de texto no permite áreas vacías, orden propio, renombrado atómico ni «eliminar área → Sin área» sin reescribir todas las líneas. Para crear/renombrar/ordenar áreas hace falta una tabla de áreas del proyecto (`project_areas`: id, proyecto, nombre, posición, con RLS como `project_products`) y una columna `area_id` en las líneas (o una lista de áreas dentro del proyecto). Es una decisión de modelo pendiente (ver más abajo).
- **Notas y cantidades** ya son por línea; al separar líneas por área quedan independientes sin más cambios. La nota sigue con el límite de 1000 caracteres y el trigger de 46-06 (solo lectura en archivados).
- **Configuraciones.** `configuration`/`config_key` no cambian. El resumen corto («Módulo MALTA + Driver DALI») se puede construir con `line_configuration_resolve` (ya devuelve `items`, suministro, cantidades y `summary`); el prototipo lo simula.

**Copia histórica de la RFQ.** `rfqs.lines_snapshot` la genera el servidor al crear la RFQ (`project_request_lines`, 46-04) y es **inmutable**; cada línea ya lleva `room_or_area` y `notes`. Para conservar **nombre y orden de las áreas** en las solicitudes nuevas hay que ampliar esa función para incluir una lista ordenada de áreas (nombre y posición) y la pertenencia de cada línea. Las RFQ ya enviadas no se tocan ni se reescriben; las nuevas copias llevarían claves adicionales. Hoy el envío solicita **todas** las líneas con `selected_for_rfq = true`: coincide con «inicialmente se solicita el proyecto completo».

**Incorporación desde la selección.** `transferSelectionToProject` y `seleccion.html` hay que ampliarlos con un área de destino (por defecto, Sin área) y con la nueva identidad de línea.

**Importes.**
- El cliente solo conoce precios por producto (`PRICE_STATE`, `catalog_published_prices`) y **siempre los formatea en US$**: ignora `currency`, `includes_itbis` e `itbis_rate`, que la función ya devuelve. Mostrar monedas separadas exige empezar a leer `currency`.
- Los precios de componentes que no son líneas del proyecto necesitan una consulta adicional con la misma función (`loadPricesFor`, ya usada en el configurador).
- La cantidad total de un componente (por unidad y por nivel) ya la calcula `line_configuration_resolve` (`total_quantity`, `factor`); el prototipo imita esa regla.
- La visibilidad por permisos se mantiene con `priceAccessInfo()`.

## Limitaciones y riesgos relevantes
1. **Unicidad sin área** (arriba): sin migración no se puede repetir una línea en otra área.
2. **`excludeFromRfq` actúa por producto**, no por línea: con el mismo producto en varias áreas excluiría todas sus líneas; habría que pasarlo a identificador de línea.
3. **Áreas vacías, orden y renombrado** requieren estructura propia (tabla o lista), no solo texto en la línea.
4. **Importes**: no hay motor definitivo; las líneas con configuración pendiente no se pueden solicitar y no aportan importe. Moneda: ver «Moneda de visualización» abajo.
5. **Rendimiento**: 100 líneas con detalle de configuración y precios de componentes implican una consulta de precios adicional y una resolución por línea configurada; conviene cachear y resolver solo al abrir los detalles.
6. **RFQ**: las áreas nuevas viajan en la copia inmutable; no se puede corregir después de enviar.
7. **Miniatura**: el prototipo usa una figura sintética (color del acabado + icono de la categoría); en producción se usaría la foto del producto o del acabado (`productMediaMarkup`, `productWithFinishImage`).

## Decisiones tomadas en el prototipo (segunda ronda)
- Copiar a otra área copia también la nota; después, cantidad y nota quedan independientes.
- Mover o copiar a un destino con una línea equivalente **no fusiona en silencio**: pregunta línea a línea («Sumar cantidades» o «No hacer nada»); si las notas difieren, la persona elige (conservar la existente, usar la otra o conservar las dos) y no se puede sumar hasta elegir.
- Una configuración pendiente queda fuera del importe calculable y su motivo es visible (en la fila y en el detalle).
- Cantidad a calcular: la línea queda incompleta («+ N pendientes»), sin multiplicar.
- Recordar el plegado de áreas: secundario, no bloquea la revisión.
- La fila ya no lleva selector de área (la sección la indica); mover y copiar están en el menú «⋯» y en la selección múltiple. «Ficha» pasa al menú en móvil.
- La selección múltiple solo aparece al seleccionar líneas (barra inferior); sin áreas ofrece solo «Quitar del proyecto».
- La decisión de la tabla de áreas se revisa después; la interfaz no depende de ella.

## Tercera revisión visual: acciones del proyecto, moneda única y conflictos al eliminar un área

**Acciones del proyecto (SUSTITUIDO por la cuarta revisión: ver «Decisiones vigentes» arriba).** El menú «Acciones del proyecto ▾» y la acción «Eliminar proyecto» en la página del proyecto se retiraron; archivar es el icono junto a «Añadir productos» y eliminar solo existe en Archivados. Se mantiene: un proyecto archivado o con solicitud es de solo consulta (cantidades, notas, áreas y añadir productos desactivados) y las confirmaciones nombran el proyecto.

**Reglas vigentes que lo condicionan (lectura de `proyectos-detalle.html`, `proyectos.html`, `proyectos-data.js`).**
- Hoy «Archivar» en un proyecto **vacío** lo **elimina** (archiva y borra en dos pasos, con una confirmación que dice «se eliminará de forma permanente»): es el comportamiento ambiguo que se corrige. En el prototipo «Archivar» siempre archiva y «Eliminar» siempre elimina; para un proyecto vacío, la confirmación de archivar sugiere «Eliminar proyecto» si solo se quiere descartar. Un proyecto activo con productos no se podía eliminar sin archivarlo antes: «Eliminar» lo resolvería con los mismos dos pasos ya existentes, sin cambiar reglas del servidor (la política exige `status = 'archived'` para borrar; si el segundo paso fallara, el proyecto quedaría archivado y se avisa).
- La eliminación está prohibida por integridad referencial cuando existen solicitudes (`rfqs.project_id` sin `ON DELETE CASCADE`, error `23503`); hoy el botón se oculta en proyectos con solicitud. En el prototipo se muestra desactivado con la explicación. Las RFQ históricas no se tocan. Al borrar un proyecto sin solicitudes, `project_products` y `moodboards` se eliminan en cascada.
- **Reactivar** depende del plan (`planAllowsMultipleActive`): con Estudio y cupo se ofrece «Reactivar proyecto»; con Individual o prueba no hay reactivación (hoy se oculta el botón). El prototipo lo refleja con el selector de plan de la demostración.
- «Solicitud enviada» es un estado derivado (archivado + RFQ propia), no un valor nuevo.

**Moneda de visualización (lectura breve).**
- Hoy todo precio es **USD**: la columna `product_prices.currency` tiene una restricción a `'USD'` (`product_prices_currency_usd`), el cliente formatea siempre «US$» (`formatUSD`, ignora `currency`, `includes_itbis` e `itbis_rate`) y el catálogo etiqueta sus filtros en «US$». **No existe** preferencia ni selector de moneda, **ni tipo de cambio** ni conversión en ninguna parte del código ni de las migraciones; no hay precios en pesos.
- Por tanto, un escenario DOP real **no tiene hoy mecanismo**: no se debe cambiar solo el símbolo. Decisión mínima a tomar antes de implementar (no se ha implementado nada): (a) mantener USD como única moneda mientras no haya precios en pesos, o (b) si se quiere DOP, definir la **fuente de los importes en pesos** —precios publicados por el distribuidor en pesos, o un tipo de cambio mantenido por Mobau con fecha y origen visibles— y dónde se elige la moneda (por proyecto, con USD por defecto). En ambos casos el proyecto se muestra en **una sola moneda**: nunca se suman ni se mezclan.
- En el prototipo, USD y DOP son dos escenarios independientes con importes simulados escritos a mano en cada moneda (sin conversión ni tipo de cambio), coherentes en filas, componentes, áreas, resumen, filtrado y resumen preliminar. Esto sustituye a la instrucción anterior de mostrar monedas separadas.

**Eliminar un área.** Sin conflictos: confirmación breve («sus N líneas pasarán a Sin área»; avisa si era la última y el proyecto volverá a lista sencilla). Con conflictos (una línea del área ya tiene su equivalente en «Sin área»): se resuelven **antes** de completar, línea a línea, eligiendo *sumar cantidades* (y, si las notas difieren, cuál queda: la de «Sin área», la del área o las dos) o *mover la línea a otra área* donde no choque; el botón de aplicar no se habilita hasta resolver todos; **cancelar no cambia nada**. No se pierden notas, cantidades ni configuraciones. Reemplaza la limitación anterior.

## Decisiones pendientes
- ¿Texto de área en la línea (`room_or_area`) o entidad de áreas con identificador y posición? (recomendación técnica: entidad, por las áreas vacías y el orden; se revisa después).
- Moneda de visualización: mantener USD o definir la fuente de importes en pesos (ver arriba).
- «Eliminar proyecto» sobre un proyecto activo: ¿mantener el doble paso (archivar y borrar) detrás de una sola confirmación explícita, o pedir antes una regla de servidor? (hoy sin cambios de servidor).
- Plegado de áreas: ¿recordarlo por proyecto y usuario o siempre desplegado al entrar?
- Orden de líneas dentro del área: hoy `order_position`; reordenar manualmente queda fuera de alcance.

## Fuera de alcance
Equipos y permisos, plantas o áreas anidadas, planos, pagos, contabilidad, presupuesto objetivo, comparación de proveedores y arrastrar y soltar como requisito.

## Archivos creados (todos bajo `supabase/`, sin publicar)
- `supabase/47-PROYECTOS.md` (este documento)
- `supabase/tests/47/interfaz/prototipo-proyecto-47.html` (página y estilos del prototipo)
- `supabase/tests/47/interfaz/prototipo-47.js` (lógica: áreas, filas, notas, importes, ventanas)
- `supabase/tests/47/interfaz/mock-datos-47.js` (catálogo, configuraciones y escenarios de 20 y 100 líneas sintéticos)
- Capturas (fuera del repositorio): `~/mobau-evidencias/punto-47/`

Sin cambios en las páginas publicadas, en el manifiesto, en el servidor ni en Production. Sin commit ni push.

---

# Punto 47 — fase actual y progreso (preparación local de 47-01, 2026-10-28)

**Estado:** interfaz aprobada implementada en las páginas reales (solo local) y migración 47-01, recuperación y ensayo preparados. **Nada ejecutado** en mobau-pruebas ni en Production; sin migración persistente, sin importar `room_or_area`, sin commit ni push.

## Lecturas en Production (solo estructura, políticas, dependencias y agregados)
- `project_products.room_or_area`: **0 líneas con valor** → no hay organización existente que el nuevo modelo pueda ocultar; la columna se conserva intacta y la copia de RFQ la sigue incluyendo. Nada que importar ni descartar.
- No se leyó ningún contenido de notas ni dato personal. Cabecera personalizada `x-mobau-areas` verificada con CORS (el servidor la acepta).

## Cambios de diseño técnico respecto a la propuesta
- **Pestañas antiguas (bloqueante resuelto):** trigger `project_products_areas_guard`. Si el proyecto tiene áreas (aunque estén vacías), toda escritura sobre sus líneas desde un cliente sin la cabecera `x-mobau-areas` se **rechaza** (42501, pista `client_outdated`, «recarga la página») sin modificar nada. La web nueva la envía solo a `/rest/v1/`. No afecta a proyectos sin áreas ni a SQL/servicio. Con la migración sin aplicar, la web nueva funciona igual (lista sencilla).
- **Estados de áreas en la interfaz:** `ready` / `missing` (PGRST205/42P01: migración aún no existe → lista sencilla, no se pide `area_id`) / `error` (red o permisos → aviso con «Reintentar», sin lista, sin operaciones, nunca «proyecto sin áreas»; guardar productos se rechaza sin escribir).
- **Sin límite de 50 áreas** (no era requisito aprobado). Nombre único por proyecto sin distinguir mayúsculas (1–60 caracteres): se mantiene por no ser ambiguo en filtros y copias; ver pendientes.
- Integridad en servidor: FK compuesta `(project_id, area_id)`; unicidad con «Sin área» (`coalesce(area_id, uuid nulo)`); mover/copiar/sumar (`project_lines_transfer`) y eliminar área (`project_area_delete`) atómicos con conflictos re-comprobados al ejecutar y filas bloqueadas; copiar crea identidad nueva; RLS de áreas como `project_products` (solo proyecto activo, sin escritura de proveedor, plan profesional).
- RFQ: `project_request_lines` añade `area_id/area_name/area_sort_order`; `rfqs_lines_snapshot` pasa a versión 2 con `areas` usadas. Las RFQ ya enviadas no se tocan. Exclusión por id de línea (`excludeFromRfq` ahora por línea).
- Moneda: solo USD; sin selector ni conversión.
- Archivar siempre archiva (también vacío); eliminar solo desde Archivados con confirmación que cuenta líneas y áreas; se conservan protección de RFQ y límites de plan.

## Archivos
- Nuevos: `supabase/migrations/20261110120000_47_01_proyectos_areas.sql`, `supabase/rollback/…47_01…rollback.sql` (se detiene sin tocar nada si hay áreas o líneas asignadas), `supabase/tests/47/P47_01_ensayo.sql` (rollback-only), `proyecto-importes.js`, `proyecto-vista.js`, mocks y pruebas en `supabase/tests/47/interfaz/`, `supabase/tests/47/capturas/`.
- Modificados: `supabase-client.js` (cabecera), `proyectos-data.js` (MobauAreas, loadProjectLines, getRequestedView, saveProductToProject por área, excludeFromRfq por línea), `proyectos-detalle.html` (reescrita al diseño aprobado), `proyectos.html`, `proyectos-resumen.html`, `proyectos-cotizacion.html` (área por línea, exclusión por línea), `scripts/pages-manifest.txt` (+2 JS), pruebas 43/46 adaptadas.

## Pruebas locales
- SQL en un Postgres 18 local desechable (esquema mínimo, **no** Supabase): migración aplica; ensayo **35/35** (RLS, FK, unicidad, pestaña antigua, mover/copiar/sumar, eliminar área, archivado, snapshot v2 con exclusión por línea, cascada); recuperación: se detiene con áreas sin cambiar nada, restaura md5 exactos de las dos funciones de 46-04 sin ellas, y se puede reaplicar. **No probado contra el esquema real** hasta el ensayo rollback-only.
- Interfaz (mocks con reglas del servidor): suite 47 **61/61**; suite 46 portada **54/54**; selección **25/25**; precios **21/21**; cierre **9/9**; suite 43 **122/131** — los 9 fallos («Catálogo») son idénticos en HEAD (preexistentes).
- Capturas de las páginas reales: `supabase/tests/47/capturas/*.png` (escritorio y tablet; móvil verificado en emulación sin desbordamiento, las capturas móviles de Chrome sin cabeza no valen por su ancho mínimo).

## Limitaciones y decisiones pendientes
1. La cabecera solo se verificó contra CORS y con el trigger en SQL local; falta comprobar una petición real en el ensayo.
2. «Ver resumen preliminar» y «Solicitar cotización» siguen abriendo las páginas existentes (no los modales del prototipo); el resumen agrupa por área.
3. En proyectos archivados no se muestran importes (regla previa del Punto 6, sin cambios).
4. Los importes de configuraciones ahora suman componentes aparte con cantidad determinada (como aprobó el prototipo): sustituye el aviso anterior «solo cuenta el principal».
5. Unicidad de nombre de área y su longitud: confirmar.
6. Resolución de conflictos de «sumar» exige elegir nota si ambas difieren (igual que el prototipo).

## Orden propuesto
Ensayo: (1) revisar esta entrega; (2) aprobar y ejecutar `P47_01_ensayo.sql` rollback-only en mobau-pruebas tras aplicar 47-01 allí; (3) probar cabecera real. Despliegue: respaldo → aplicar 47-01 en Production y registrar tras COMMIT → publicar web (commit con lista explícita de archivos). Compatible en cualquier orden entre migración y web.

---

# Punto 47 — fase actual y progreso (ensayo SQL real en mobau-pruebas, 2026-10-28)

## Decisiones cerradas (no se reabren)
Nombres de área 1–60 caracteres, únicos por proyecto sin distinguir mayúsculas; resumen y solicitud por sus páginas existentes; importes ocultos en archivados; componentes aparte con cantidad determinada incluidos en el importe conocido, sin sumar los incluidos y señalando importes incompletos.

## Ensayo SQL rollback-only
- **Destino confirmado:** `mobau-pruebas`, ref `icuhaivgmfbgsmpffcjv` (Postgres 17.11, eu-west-1). No Production. No existe `supabase_migrations.schema_migrations` allí, así que la comprobación de registro de la migración se omite por diseño.
- **Archivos y MD5 (migración y recuperación sin cambios):** `20261110120000_47_01_proyectos_areas.sql` 1ec786cffbcc0e2f9e1da7cb4cd7798c · `…47_01_proyectos_areas.rollback.sql` f5b9f500db10c579284bba532c6351a1 · `P47_01_ensayo.sql` ef98f8f1fc86bb3eced7a22815b7678e (versión final tras los ajustes de abajo; la ejecutada tuvo el A9c anterior).
- **Método:** una sola llamada de SQL = una transacción: migración (sin BEGIN/COMMIT) + ensayo, que termina siempre con `RAISE` (rollback). Se quitaron solo los comentarios de cabecera del texto enviado.
- **Línea base previa** (lectura): sin `project_areas`, sin `area_id`, índice antiguo presente, md5 de `project_request_lines` y `rfqs_lines_snapshot` = los de 46-04, 23 tablas públicas, 2 proyectos / 2 líneas / 2 RFQ / 10 productos / 0 estudios, y huellas md5 de funciones, índices, políticas, grants y de los datos de `projects`, `project_products`, `rfqs`, `products`, `studios`.
- **Intento 1:** falló en la preparación (el distribuidor `spectro` no existe en mobau-pruebas; usa `distribuidor-prueba`). Revirtió entero (comprobado). Corrección: el ensayo usa `distribuidor-prueba` y la identidad Individual `24fb0c2f…` (plan `individual_founder`) en lugar de la de Production/local.
- **Intento 2 (real):** la migración se aplicó dentro de la transacción y su validación final pasó. Resultado del ensayo: **34 OK, 1 FALLO**. OK: RLS de áreas (propietario, otro usuario, proveedor, archivado), clave compuesta, unicidad con «Sin área», pestaña antigua rechazada sin cambios (suma, alta y borrado; también con áreas vacías), web nueva con cabecera sí opera, proyecto sin áreas sigue funcionando con web antigua, mover/copiar/sumar/omitir con conflictos y notas, eliminar área (sin conflicto, conflicto, sumar, mover a área con equivalente), archivado de solo lectura, copia de RFQ versión 2 con áreas y exclusión por línea, cascada al eliminar proyecto, `room_or_area` intacto.
- **Fallo A9c = defecto de la aserción, no de 47-01:** esperaba una excepción al modificar `lines_snapshot` como usuario, pero `rfqs` no tiene política de UPDATE para usuarios (verificado: solo INSERT/SELECT), así que el UPDATE afecta 0 filas sin error. Ya está corregido en el archivo (ahora comprueba que la copia no cambia). La rama de actualización del trigger es idéntica a la de 46-04. **No se ha vuelto a ejecutar en mobau-pruebas** para no repetir el ensayo entero; el archivo corregido sí da 35/35 en el Postgres local desechable.
- **Reversión verificada por lectura independiente** (consulta separada tras el ensayo): todas las huellas idénticas a la línea base (objetos, md5 de funciones, índices, políticas, grants, columnas y filas de las cinco tablas). No quedan datos z47-* ni estudios.
- No se dejó 47-01 aplicada, ni registro de migración, ni cambios persistentes.

## Propuesta mínima para la comprobación HTTP real (requiere autorización adicional)
Necesita 47-01 aplicada de forma **persistente** en mobau-pruebas (no en Production).
1. **Preparación:** respaldo lógico de las 5 tablas afectadas + huellas (ya tomadas); aplicar 47-01 en mobau-pruebas en transacción; verificar; **no** registrar en schema_migrations (no existe allí).
2. **Datos sintéticos (z47-*), creados con SQL de servicio:** 1 proyecto con 2 áreas y 3 líneas, 1 proyecto sin áreas con 1 línea, para el Individual `24fb0c2f…` y otro usuario de prueba; sesión de prueba obtenida con la cuenta de pruebas.
3. **Peticiones reales (PostgREST con JWT de usuario):**
   a. PATCH de cantidad con `x-mobau-areas: 1` sobre línea del proyecto con áreas → 200 y cambia.
   b. El mismo PATCH **sin** cabecera → 403/42501 `client_outdated` y la línea no cambia.
   c. POST/DELETE sobre línea del proyecto con áreas sin cabecera → rechazados; sin cambios.
   d. PATCH sin cabecera sobre el proyecto sin áreas → 200.
   e. Con cabecera, pero otro usuario sobre el proyecto ajeno → 0 filas / rechazo (la cabecera no sustituye RLS); y con cabecera desde un proveedor o sin plan → rechazo.
   f. RPC `project_lines_transfer` y `project_area_delete` con la web nueva.
   g. Confirmar que CORS acepta la cabecera en el preflight real.
4. **Limpieza y restauración:** borrar los proyectos z47-* (cascada), y ejecutar `…47_01….rollback.sql` (se detiene si quedara algo; entonces limpiar primero); comparar contra las huellas de línea base.

## Revisión visual
- Corregida `18-escritorio-desde-mi-seleccion.png` (el arnés no abría el menú antes de pulsar «Desde mi selección»).
- Añadida `30-movil-areas.png` (390 px reales dentro de un marco; las capturas móviles anteriores de Chrome sin cabeza se habían descartado). Las otras 23 no se regeneraron.
- Páginas locales para revisar: `http://localhost:8051/cap-proyectos-detalle.html?id=00000001-1111-4111-8111-111111111111&rol=individual&pro=1&uid=a&c={"caso":"c"}` (casos a/b/c/d; `&demo=…`), marco móvil `http://localhost:8051/marco-movil.html`, y el arnés de pruebas en `http://localhost:8050/supabase/tests/47/interfaz/pruebas-proyecto-47.html`. Se regeneran con `supabase/tests/47/capturas/preparar-copia.py <carpeta>`.

## Limitaciones pendientes
1. Falta la comprobación HTTP real (propuesta arriba).
2. A9c corregido pero sin reejecutar en mobau-pruebas.
3. El ensayo valida el esquema de mobau-pruebas; Production se valida con el mismo ensayo antes de aplicar (nunca con datos reales).

## Archivos modificados (rastreados)
`proyectos-cotizacion.html`, `proyectos-data.js`, `proyectos-detalle.html`, `proyectos-resumen.html`, `proyectos.html`, `scripts/pages-manifest.txt`, `supabase-client.js`, `supabase/tests/43/interfaz/casos_cc1.js`, `supabase/tests/43/interfaz/pruebas-p1-cc1.html`, `supabase/tests/46/interfaz/mock-proyecto-46.js`, `supabase/tests/46/interfaz/pruebas-proyecto-46.html`.
## Archivos nuevos
`proyecto-importes.js`, `proyecto-vista.js`, `supabase/migrations/20261110120000_47_01_proyectos_areas.sql`, `supabase/rollback/20261110120000_47_01_proyectos_areas.rollback.sql`, `supabase/47-PROYECTOS.md`, y `supabase/tests/47/` (`P47_01_ensayo.sql`, `interfaz/*`, `capturas/*`). Fuera de la lista de commit: `.claude/`, `MOBAU_CONTEXT.md`, `images/acceso/alternativa-crear/`, los `supabase/acceso-spectro-*` y `supabase/registro_septiembre/`.

---

# Punto 47 — fase actual y progreso (comprobaciones HTTP reales en mobau-pruebas, 2026-10-28)

**Aclaración sobre el ensayo SQL:** el resultado real del ensayo rollback-only sigue siendo **34 OK y 1 fallo de aserción (A9c)**. La cifra «35/35» solo existe en el Postgres local desechable y no cuenta como resultado real. La A9c corregida se ha comprobado aparte contra Supabase real (abajo), no repitiendo el ensayo entero.

## Preparación y línea base
- Proyecto: `mobau-pruebas` (`icuhaivgmfbgsmpffcjv`), solo ese. Línea base previa idéntica a la registrada (objetos, md5 de funciones, índices, políticas, grants, filas de las cinco tablas); sin cambios ajenos.
- MD5: migración `1ec786cffbcc0e2f9e1da7cb4cd7798c` · recuperación `f5b9f500db10c579284bba532c6351a1` · ensayo corregido `ef98f8f1fc86bb3eced7a22815b7678e`.
- Respaldo local: `~/mobau-pruebas-estructura/respaldo-47/` (filas de `projects`/`project_products`, definiciones, ACL, cuerpos 46-04, copias de los tres archivos, huellas). Sin Auth, claves ni tokens. Límite: `lines_snapshot` y `config_snapshot` se respaldan por referencia y huella md5 (la base no los modifica).
- 47-01 aplicada de forma persistente solo durante el bloque, en una transacción; sin registro de migración (esa base no tiene `schema_migrations`). Datos sintéticos `z47-*`: 2 productos, 2 proyectos de Individual 1 (uno con 2 áreas y 3 líneas, otro sin áreas con 1 línea).
- Identidades reales (sesión iniciada por el usuario; yo no vi contraseñas; sin `service_role` en las comprobaciones de permisos): Individual 1, Individual 2 y proveedor verificado; peticiones lanzadas desde el navegador con el token de cada sesión (no se exportó). La web usada es la copia de pruebas con el código nuevo (`~/mobau-copia-pruebas`).

## Resultados (y estado de los datos verificado después por SQL)
| Comprobación | Resultado |
|---|---|
| Individual 1, PATCH con cabecera `x-mobau-areas: 1` | 200, modifica exactamente la línea esperada (2→5) |
| Sin cabecera, proyecto con áreas: PATCH, POST, DELETE | los tres 403 `42501` / `client_outdated`; la línea no cambió, no se creó ni se borró nada |
| Proyecto sin áreas, PATCH sin cabecera | 200, cambia (compatible con la web anterior) |
| Individual 2 con cabecera sobre proyecto ajeno | SELECT de líneas y áreas: 0 filas; PATCH y DELETE: 200 con 0 filas (RLS); POST de línea y de área: 403 RLS; RPC mover: `line_invalid`. Datos intactos |
| Proveedor verificado con cabecera | igual que Individual 2: 0 filas, 403 RLS, `line_invalid`. Datos intactos |
| Web nueva (capa de datos real: `MobauProjects`/`MobauAreas`) | actualizar cantidad (5→6; funciona solo porque el navegador envía la cabecera: el proyecto tenía áreas), mover a «Sin área», copiar con conflicto (`transfer_conflict` con las líneas), copiar sumando, eliminar área con conflicto (`area_conflict`), eliminar área sumando y eliminar área vacía: todos correctos; estado final por SQL = esperado (15 = 6 + 9; 0 áreas; la línea de intrusos nunca llegó a 77 ni 99) |
| Preflight CORS | las peticiones cross-origin reales con la cabecera personalizada (origen `127.0.0.1:8053`) pasaron el preflight del navegador. Un OPTIONS manual devolvió 200 sin `Access-Control-Allow-Headers` legible; no concluyente por sí solo, la prueba válida es la de las peticiones reales |
| **A9c corregida (HTTP)** | Individual 1 (dueño), PATCH de `lines_snapshot` de su RFQ: 200, **0 filas** (no hay política UPDATE en `rfqs`); `md5` de `rfqs` posterior = línea base → copia idéntica |
| **A9c trigger (aparte)** | `postgres` alcanza la fila: `rfq_snapshot_immutable` (42501) con la función de 47-01 instalada; en transacción revertida. No se confunde con la RLS: son dos defensas distintas |

## Limpieza y recuperación
- Borrados solo los datos z47-* de esta ejecución (2 proyectos con sus líneas/áreas por cascada, 2 productos). Contadores de vuelta a 2/2/2/10/0.
- Recuperación preparada ejecutada (sin forzar; no detectó áreas ni líneas asignadas ni ajenas).
- Comparación final independiente contra la línea base: idéntica en objetos, md5 de funciones (46-04 exactas), índices, políticas, grants, columnas y datos de las cinco tablas. Una única discrepancia aparente fue un error de comillas de mi propia consulta de comparación (el `idx_md5` global es idéntico).
- Sesiones de prueba: quedan abiertas en el navegador de la app; se cierran con «Cerrar sesión» de `pruebas-entrar.html`.

## Pendiente antes de Production
1. Decidir cuándo aplicar 47-01 en Production (respaldo, aplicación en una transacción, registro tras COMMIT, publicación de la web con commit de lista explícita).
2. En Production no hay preflight ni cabecera verificados: confirmar CORS con una petición real tras publicar (la web antigua seguirá funcionando mientras ningún proyecto tenga áreas).
3. Revisión de la limitación CORS manual (OPTIONS) si se quiere una evidencia directa de `Access-Control-Allow-Headers`.
4. Commit: aún sin hacer (lista de archivos abajo).

## Archivos modificados (rastreados)
`proyectos-cotizacion.html`, `proyectos-data.js`, `proyectos-detalle.html`, `proyectos-resumen.html`, `proyectos.html`, `scripts/pages-manifest.txt`, `supabase-client.js`, `supabase/tests/43/interfaz/casos_cc1.js`, `supabase/tests/43/interfaz/pruebas-p1-cc1.html`, `supabase/tests/46/interfaz/mock-proyecto-46.js`, `supabase/tests/46/interfaz/pruebas-proyecto-46.html`.
## Archivos nuevos
`proyecto-importes.js`, `proyecto-vista.js` (con `git add -N`), `supabase/migrations/20261110120000_47_01_proyectos_areas.sql`, `supabase/rollback/20261110120000_47_01_proyectos_areas.rollback.sql`, `supabase/47-PROYECTOS.md`, `supabase/tests/47/` (`P47_01_ensayo.sql`, `interfaz/`, `capturas/`).

---

# Punto 47 — fase actual y progreso (entrega de despliegue; nada ejecutado en Production)

Pruebas cerradas según lo documentado arriba. Esta sección solo **prepara** el despliegue: no hay lecturas nuevas de Production, respaldo, aplicación, registro, commit ni push.

## 1. Aclaraciones
**Identificador de la migración (`20261110120000_47_01_proyectos_areas`) — se mantiene.**
- El repositorio usa versiones secuenciales que no siguen el calendario real: 46-06 lleva `20261101140000` y se versionó el 2026-10-26; 45-04 lleva `20261028…`. Hoy es 2026-10-28, y `20261110120000` es solo la siguiente de esa serie.
- Orden: es **estrictamente posterior** a la última versión registrada que consta (46-06, `20261101140000`, 53 entradas según el último registro conocido, sin lecturas nuevas), y a todas las del directorio (46 archivos, la última 46-06). La propia migración lo comprueba al aplicarse: exige 46-06 registrada y 47-01 no registrada.
- El hueco del 1 al 10 de noviembre es cosmético. Renombrarla a `20261102…` cambiaría el nombre de la recuperación, las referencias en comentarios y todos los MD5 sin ningún beneficio de orden; por eso no se renombra. Si prefieres la serie sin hueco, el nombre definitivo propuesto sería `20261102120000_47_01_proyectos_areas.sql` y habría que regenerar los MD5; no lo hago sin tu decisión.

**Incorporar desde selección con área opcional — resuelto, no se ha perdido.**
- `seleccion.html` y `seleccion-data.js` no cambian porque ya llaman a `MobauProjects.transferSelectionToProject(proyecto, items, "sum")`, y esa función (en `proyectos-data.js`) ahora acepta un `areaId` opcional. Sin él, la transferencia actúa siempre sobre «Sin área», sin ambigüedad y sin tocar líneas de otras áreas.
- La asignación a un área es opcional y está en la página del proyecto: «Añadir productos ▾ → Desde mi selección» abre la ventana con el selector «Asignar a un área (opcional)» (`proyecto-vista.js`, `selectionModal` / `selectionDo`). La selección solo se limpia si todo se transfirió bien.
- Cubierto por pruebas: suite 47 S1 (suma solo en «Sin área»), S2 (con área de destino) y la captura `18-…desde-mi-seleccion.png`; suite de selección 25/25.
- Se conserva la regla: los productos nuevos entran primero en `mobau_seleccion` y se revisan antes de transferir.

## 2. Revisión final del diff
- **Sin instrumentación ni credenciales en archivos publicados:** búsqueda de `mock`, `z47`, `__p47`, `localhost`, `127.0.0.1`, tokens `eyJ…`, claves secretas, `service_role` (solo el comentario previo de aviso en `supabase-client.js`), `console.log`, `debugger`, `FIXME`: sin coincidencias nuevas. `SUPABASE_URL` y `SUPABASE_ANON_KEY` sin cambios.
- **Manifiesto:** `proyecto-importes.js` y `proyecto-vista.js` añadidos (líneas 44–45) y cargados por `proyectos-detalle.html` tras `script.js`. Lista cerrada; nada de `supabase/` entra.
- **Cabecera de compatibilidad:** `mobauDataFetch` solo la añade si la URL contiene `/rest/v1/` (datos y RPC); no se envía a sesión ni almacenamiento. Identifica compatibilidad del cliente, no autentica ni autoriza: RLS, plan y políticas se aplican igual (comprobado: otro usuario y proveedor con cabecera siguen sin acceso).
- **Diseño aprobado:** `proyectos-detalle.html` implementa el prototipo aprobado; las desviaciones declaradas son resumen y solicitud por sus páginas existentes (aceptado) e importes ocultos en archivados (aceptado). Sin cambios en `styles.css` ni en el catálogo.
- **Sin cambios ajenos al Punto 47** (`git status`): aparte de lo listado abajo, solo hay elementos sin versionar anteriores que quedan fuera.

Resumen del diff (líneas +/−): `proyecto-importes.js` +83 · `proyecto-vista.js` +832 · `proyectos-detalle.html` +282/−1300 (reescrita al diseño aprobado) · `proyectos-data.js` +186/−19 · `proyectos.html` +18/−39 · `proyectos-cotizacion.html` +12/−3 · `proyectos-resumen.html` +15/−2 · `supabase-client.js` +15/−1 · `scripts/pages-manifest.txt` +2.

## 3. Rutas propuestas para el commit (cada una por su ruta; nunca `git add -A` ni carpetas)
**Código publicado (9):**
`proyecto-importes.js` · `proyecto-vista.js` · `proyectos-cotizacion.html` · `proyectos-data.js` · `proyectos-detalle.html` · `proyectos-resumen.html` · `proyectos.html` · `supabase-client.js` · `scripts/pages-manifest.txt`

**SQL (no se publica) (2):**
`supabase/migrations/20261110120000_47_01_proyectos_areas.sql` · `supabase/rollback/20261110120000_47_01_proyectos_areas.rollback.sql`

**Pruebas (modificadas, 4):**
`supabase/tests/43/interfaz/casos_cc1.js` · `supabase/tests/43/interfaz/pruebas-p1-cc1.html` · `supabase/tests/46/interfaz/mock-proyecto-46.js` · `supabase/tests/46/interfaz/pruebas-proyecto-46.html`

**Pruebas nuevas del Punto 47 (5):**
`supabase/tests/47/P47_01_ensayo.sql` · `supabase/tests/47/interfaz/abrir-47.html` · `supabase/tests/47/interfaz/mock-areas-47.js` · `supabase/tests/47/interfaz/pruebas-proyecto-47.html` · `supabase/tests/47/interfaz/sw-paginas-47.js`

**Referencia de diseño aprobada (3, opcional pero recomendada: prototipo del que sale la interfaz):**
`supabase/tests/47/interfaz/mock-datos-47.js` · `supabase/tests/47/interfaz/prototipo-47.js` · `supabase/tests/47/interfaz/prototipo-proyecto-47.html`

**Documentación (1):** `supabase/47-PROYECTOS.md`

**Materiales auxiliares que NO necesitan entrar en git** (siguen en disco): las 24 capturas `supabase/tests/47/capturas/*.png` y sus scripts (`demo-capturas.js`, `hacer-capturas.sh`, `preparar-copia.py`). Se regeneran con `preparar-copia.py`; si se quieren conservar, mejor fuera del repositorio.

**Fuera, como acordado:** `.claude/`, `MOBAU_CONTEXT.md`, `images/acceso/alternativa-crear/`, `supabase/acceso-spectro-sync-profiles-email.EJECUTADA-2026-10-27.sql`, `supabase/acceso-spectro-temporal.md`, `supabase/registro_septiembre/`.

Nota de índice: `proyecto-importes.js` y `proyecto-vista.js` están con `git add -N` (intención de añadir); el commit los incluirá por su ruta explícita.

## 4. Preparación de Production
**Destino:** `mobau-pilot`, ref `skcoxtdppdcietgojdal` (confirmar el ref en cada llamada; nunca `mobau-pruebas`).

**Archivos definitivos y MD5 completos**
- `…47_01_proyectos_areas.sql` — `1ec786cffbcc0e2f9e1da7cb4cd7798c`
- `…47_01_proyectos_areas.rollback.sql` — `f5b9f500db10c579284bba532c6351a1`
- `P47_01_ensayo.sql` — `ef98f8f1fc86bb3eced7a22815b7678e` (NO se ejecuta en Production)
- Los archivos no cambian respecto a lo ensayado. Nota de método: en pruebas el texto enviado fue el archivo **sin** `BEGIN;`/`COMMIT;` ni comentarios de cabecera; en Production se aplicará el archivo tal cual (con su `BEGIN;`/`COMMIT;`), precedido de dos sentencias de protección que no forman parte del archivo: `set local lock_timeout = '5s'; set local statement_timeout = '60s';`.
- MD5 esperados **después** de aplicar (cuerpo `prosrc`): `project_request_lines` `87693d922901b1a7f74e1f4199a9839c` · `rfqs_lines_snapshot` `a44af916a8484a3a1b4e644e0a6dd285`. Antes: `eda482e41007f05fa96d77909cc6abee` y `a2a34a983f128532dce2a7bcdfbfb96a`.

**Precomprobaciones (lecturas de solo consulta, justo antes de aplicar; si una falla, parar)**
1. Ref del proyecto = `skcoxtdppdcietgojdal`; 46-06 registrada (`20261101140000`) y 47-01 (`20261110120000`) no registrada; conteo y última versión de `schema_migrations` anotados.
2. Ausentes: `project_areas`, `project_products.area_id`, `project_lines_transfer`, `project_area_delete`, `project_products_areas_guard`. Presentes: `set_updated_at`, `is_supplier`, `my_professional_access`.
3. Índice `project_products_config_line_unique` con la definición exacta esperada; md5 de las dos funciones de la copia de RFQ = los de 46-04 (arriba). La migración vuelve a comprobar 1–3 dentro de la transacción.
4. Dependencias: `catalog_products`, `distributors`, `product_finishes`, `line_configuration_resolve`, `rfqs`, `projects`, `profiles` existentes; `rfqs` con su trigger `trg_rfqs_10_lines_snapshot`.
5. Datos: `room_or_area` con valor = 0 (última lectura); si ya no es 0, **parar** (se conserva, se informa del agregado y se decide aparte). Ninguna línea puede violar el nuevo índice (es más débil que el actual).
6. Sin actividad de escritura que bloquee: lectura de `pg_stat_activity`/bloqueos; si hay transacciones largas sobre `project_products`, esperar.
7. Huellas previas (md5 de `to_jsonb(t)` por tabla `projects`, `project_products`, `rfqs`; md5 de funciones, índices, políticas, grants) para comparar después.

**Respaldo recuperable (previo, lo ejecuta el usuario)**
- Ejecutar `~/mobau-respaldo-produccion/respaldo.sh` (solo lectura, `pg_dump` completo; la URI se teclea sin eco). Comprobar con `pg_restore -l` que incluye `projects`, `project_products`, `rfqs` y las definiciones de funciones/políticas/índices, y anotar su SHA-256 y fecha. Las huellas sirven para comparar, no sustituyen este respaldo. Si no está hecho el mismo día de aplicar, **no se aplica**. Recuerda que el respaldo anterior fue parcial (sin archivos de Storage); aquí solo importa la base de datos.

**Aplicación:** una sola llamada = una transacción: las dos sentencias de protección + el archivo completo. Cualquier excepción revierte todo (comprobado en pruebas). Si el resultado no es explícitamente correcto, no se continúa.

**Verificación independiente posterior (conexión nueva):** `project_areas` existe con RLS y 11 políticas; `area_id` presente y 0 líneas con área; índice nuevo presente y el antiguo ausente; trigger y 2 funciones presentes con permisos solo para `authenticated`; md5 de las dos funciones = los esperados; md5 de `to_jsonb(t) - 'area_id'` por tabla = huellas previas (contadores iguales); políticas y grants preexistentes idénticos salvo lo añadido (`grant update (area_id)`); Security Advisor sin hallazgos nuevos aparte de los ya aceptados.

**Registro de la migración:** solo tras confirmar el COMMIT **y** pasar la verificación; una sola inserción en `supabase_migrations.schema_migrations` con `version='20261110120000'`, `name='47_01_proyectos_areas'` (mismo formato que 46-05/46-06; comprobar columnas y que no exista). Nunca en la misma llamada que la migración.

**Orden de publicación**
1. Respaldo (usuario) → precomprobaciones → aplicar → verificar → registrar.
2. Commit con la lista exacta de §3 (sin `git add -A`), y solo con tu aprobación explícita; push (publica Cloudflare automáticamente).
3. Confirmar en Cloudflare el despliegue en verde con ese commit y pasar la revisión de §5.
- La web nueva funciona con o sin la migración (estado `missing`) y la migración no afecta a la web antigua mientras ningún proyecto tenga áreas; por eso el orden no es crítico, pero este orden permite usar las áreas desde el primer momento.

**Condiciones que obligan a detenerse:** discrepancia con cualquier huella o definición esperada; ref distinto; respaldo ausente o no verificable; `room_or_area` con valores; locks o transacciones largas; error o resultado no explícito en la aplicación; verificación posterior con cualquier diferencia; Security Advisor con hallazgos nuevos; fallo del registro. Ante cualquiera: no encadenar reintentos sin explicar y proponer la corrección.

**Recuperación (no destructiva)**
- Antes de que existan áreas: `…rollback.sql` restaura funciones de 46-04 (md5 exactos), índice y columna. Se **detiene sin cambios** si existe cualquier área o asignación, y **nunca las elimina** para forzar la vuelta atrás; entonces hace falta una decisión separada (exportar las áreas, mover líneas a «Sin área» y unir equivalentes con criterio).
- Después de publicar y con uso real, el plan por defecto ante un problema de la web es **revertir el commit web** (la web antigua rechaza de forma controlada solo los proyectos con áreas), no la migración.

## 5. Revisión breve tras publicar (preparada, sin crear datos todavía)
1. **Proyecto existente sin áreas:** se abre como lista sencilla con sus líneas, cantidades, notas y configuraciones intactas; botones y filtros operativos.
2. **Proyecto de prueba autorizado** (a designar contigo): crear un área, mover y copiar una línea, resolver un conflicto, guardar una nota, eliminar el área; comprobar el estado resultante por lectura.
3. **Importes y configuración:** importe conocido, cobertura y líneas parciales/pendientes coherentes; detalle de una configuración.
4. **Resumen y solicitud sin enviar RFQ real:** «Ver resumen preliminar» agrupa por área; abrir «Solicitar cotización» sin enviar el formulario (no se crea ninguna RFQ).
5. **Archivado sin eliminación:** archivar el proyecto de prueba y comprobar que queda en Archivados, con el aviso del tooltip; eliminar solo desde Archivados y solo el proyecto de prueba.
6. **Petición real desde el dominio publicado:** una operación de la web con la cabecera `x-mobau-areas` (cantidad de una línea del proyecto de prueba con áreas) debe funcionar, y confirmar en la pestaña de red que el preflight (`OPTIONS`) responde con la cabecera permitida; el mismo `PATCH` sin cabecera debe dar 403 `client_outdated` sin cambiar nada.
Limpieza de lo creado: borrar el proyecto de prueba desde Archivados al terminar.

---

# Punto 47 — fase actual y progreso (plan aprobado; precomprobaciones y respaldo; aún sin aplicar)

## Decisiones del plan aprobado
- Identificador **`20261110120000_47_01_proyectos_areas`** se mantiene. MD5 definitivos sin cambios: migración `1ec786cffbcc0e2f9e1da7cb4cd7798c` · recuperación `f5b9f500db10c579284bba532c6351a1` · ensayo `ef98f8f1fc86bb3eced7a22815b7678e`.
- **Lista de commit: 24 archivos, cada uno por su ruta** (9 de código publicado + 2 SQL + 4 pruebas modificadas + 5 pruebas nuevas + 3 de referencia de diseño + este documento). Las 3 de referencia de diseño: `supabase/tests/47/interfaz/mock-datos-47.js`, `prototipo-47.js` y `prototipo-proyecto-47.html`. Fuera: capturas, sus scripts y todos los elementos excluidos ya enumerados. Sin commit ni push todavía.
- **Proyecto de la revisión posterior: «VALIDACIÓN P47»**, nuevo y aislado, que creará el usuario desde su cuenta profesional tras publicar. Todas las pruebas de escritura se limitan a él; no se envía ninguna RFQ real; antes de eliminarlo (solo desde Archivados) se confirma que no contiene nada que quiera conservar. Un proyecto existente sin áreas solo se abre para leer, sin modificarlo. No se crea ningún dato de prueba hasta entonces.

## Precomprobaciones en Production (solo lectura, 2026-10-28)
Proyecto `mobau-pilot`, ref `skcoxtdppdcietgojdal` (base `postgres`, PG 17.6). Resultado: **sin discrepancias ni bloqueos**.
- **Registro:** 53 migraciones; 46-06 (`20261101140000`) registrada; 47-01 no registrada; ninguna versión posterior a `20261110120000`. Columnas de `schema_migrations`: `version, statements, name, created_by, idempotency_key, rollback` (el registro de 47-01 se hará como el de 46-05/46-06: solo `version` y `name`).
- **Estado de partida:** sin `project_areas` en ningún esquema, sin `area_id`, sin las 3 funciones nuevas; índice `project_products_config_line_unique` con la definición esperada; md5 de `project_request_lines` = `eda482e4…` y de `rfqs_lines_snapshot` = `a2a34a98…` (los de 46-04).
- **Dependencias presentes:** `set_updated_at`, `is_supplier`, `my_professional_access`, `line_configuration_resolve`, `catalog_products`, `distributors`, `product_finishes`, `rfqs`, `profiles`; triggers actuales de `project_products` (`…10_configuration`, `…20_note`) y de `rfqs` (`…10_lines_snapshot`); 11 políticas en `project_products`.
- **`room_or_area`:** 0 líneas con valor. Sin vistas que dependan de `project_products`; sin claves foráneas hacia ella; solo `project_line_states` y `project_request_lines` citan la tabla (ya conocidas). 0 duplicados que violen el índice nuevo (es más débil que el actual).
- **Sin bloqueos:** 0 transacciones activas de más de 30 s, 0 bloqueos no concedidos.
- **Huellas previas** (se vuelven a tomar al aplicar; el tráfico real las cambia): datos hoy — 9 proyectos, 22 líneas, 2 RFQ, 38 productos, 0 estudios; md5 de `to_jsonb(t)`: `project_products` `35ef377c77dfe9f3de28b936a5fd7aaf`, `projects` `41426efc43cafc9eb7ee13a8b397cd47`, `rfqs` `d3baca9f2c80be87f6819c002dc7899d`. Estructura: 23 tablas públicas; funciones `3c2fb757…`; índices `6d016d05…`; políticas `2778d470…`; grants `3469399f…`; columnas de `project_products` `8cbae538…`; privilegios por columna `fbe8ea41…` (todas idénticas a las de mobau-pruebas, lo que confirma que el ensayo se hizo sobre la misma estructura).
- **Cambios ajenos:** los conteos son mayores que en la última lectura de octubre (uso normal: 8→9 proyectos, 18→22 líneas, 35→38 productos); no hay objetos ni estructura distintos, así que no son incompatibles con la aplicación.

## Respaldo del día (lo ejecuta el usuario) y su verificación
**Requisitos:** terminal en tu Mac con Postgres.app (usa `/Applications/Postgres.app/Contents/Versions/18/bin`), la URI del «Session pooler» de Production a mano (se teclea sin eco; el script no la imprime ni la guarda) y permiso de escritura en `~/mobau-respaldo-produccion/`.

**Ajuste hecho en el script (para que arranque):** `respaldo.sh` exigía exactamente 52 migraciones y por eso se habría detenido hoy (53). He cambiado ese único valor a 53, con copia del original en `/tmp/respaldo.sh.bak-52`; el resto no cambia (solo lectura en cada conexión, comprobación del destino por catálogo, carpeta marcada INCOMPLETO si falla). Con esto, si hubiera otra migración distinta de 53, el script se detiene a propósito.

**Comando exacto:**
```bash
~/mobau-respaldo-produccion/respaldo.sh
```
Pega la URI cuando la pida y pulsa Intro. Al terminar, dime solo «hecho» y la ruta de la carpeta creada (formato `~/mobau-respaldo-produccion/AAAA-MM-DD_HHMM`).

**Verificación que haré después (sin red ni credenciales)** con `~/mobau-respaldo-produccion/verificar.sh <carpeta>`:
1. Fecha de hoy y archivos no vacíos (`produccion_completo.dump`, `produccion_estructura.sql`, manifiesto, lista y recuentos).
2. SHA-256 recalculados y comparados con el MANIFIESTO (se anotan en la entrega).
3. `pg_restore --list` lee el volcado; el volcado se hizo con 53 migraciones.
4. Definición **y datos** de `projects`, `project_products`, `rfqs` (y `products`, `profiles`, `schema_migrations`): están los bloques `TABLE DATA` y el recuento real de filas extraído con `pg_restore --data-only` coincide con el del manifiesto y es mayor que 0.
5. Las dos funciones que se sustituyen: definición presente y cuerpo extraído con md5 = el de 46-04 (`eda482e4…`, `a2a34a98…`).
Probado hoy sobre el respaldo del 2026-10-26: todas las comprobaciones válidas salvo la esperada (ese volcado tenía 52 migraciones y 8/18/2 filas). Un respaldo de otro día, o sin alguna tabla o función, no pasa.

**Restauración documentada (no se restaura nada en Production):**
- Datos de una tabla afectada, a una base de cotejo (nunca Production): `pg_restore --data-only --table=<tabla> --schema=public --file=- <dump>` y cargar el `COPY` resultante en una base desechable para comparar con Production.
- Definición de una función: `pg_restore -P 'project_request_lines(uuid)' --file=- <dump>` (o `rfqs_lines_snapshot()`); es el texto exacto que debe coincidir con `eda482e4…` / `a2a34a98…`. Reponerla en Production solo se hace con la recuperación `…rollback.sql`, que ya lleva esos cuerpos.
- Una restauración completa de Production (de este volcado o de las copias de la plataforma) sería una decisión aparte, con su propio plan; este respaldo no incluye archivos de Storage, roles ni ajustes de Auth/Cloudflare.

## Recuperación de la web: qué es y qué no es posible
1. **Antes de que exista ninguna área** (es decir, tras aplicar 47-01 y publicar, pero sin proyectos con áreas): volver a la web anterior (revertir el commit web) es seguro y completo; el cliente antiguo funciona porque el trigger solo actúa cuando un proyecto tiene áreas. Si además hay que volver al esquema anterior, `…rollback.sql` lo hace sin pérdida y se detiene si encuentra algo.
2. **Después de que existan áreas** (aunque sea una, aunque esté vacía): **revertir la web no garantiza recuperar el funcionamiento completo.** Un cliente antiguo (pestaña sin recargar o web revertida) tiene sus escrituras sobre las líneas de esos proyectos **bloqueadas por el trigger de compatibilidad** (`client_outdated`); la lectura sigue funcionando. Es la protección contra escrituras ambiguas y se conserva.
   - **No se retira el trigger y no se borran áreas ni asignaciones para forzar la recuperación**; la recuperación del esquema se detiene si hay datos de áreas.
   - Ante una incidencia con áreas existentes, la vía es una **corrección compatible hacia delante**: arreglar la web nueva y republicar (o, si el problema está en el servidor, una migración correctiva nueva y revisada), manteniendo el esquema y los datos de los usuarios. Procedimiento: (a) tratar los proyectos con áreas como solo lectura para el cliente antiguo y avisar si hace falta; (b) reproducir y corregir en local con las suites ya existentes; (c) ensayo en mobau-pruebas; (d) aplicar la corrección con respaldo del día y verificación independiente; (e) publicar. Si algún cambio de datos fuera inevitable, se decide aparte, con los datos exportados primero.
   - No se implementa ahora ningún mecanismo adicional (p. ej. un interruptor para desactivar el trigger): queda fuera de este despliegue.

---

# Punto 47 — fase actual y progreso (respaldo del día verificado; aún sin aplicar)

**Respaldo:** `/Users/joandelmonte/mobau-respaldo-produccion/2026-10-28_1234` (creado 2026-10-28 12:35 +0100 con `respaldo.sh`, solo lectura; `pg_dump` 18.6 sobre servidor 17.6, 53 migraciones registradas, 964 entradas, 62 tablas con datos). **Verificación con `verificar.sh`: completa, sin fallos.**

| Archivo | Bytes | SHA-256 |
|---|---|---|
| `produccion_completo.dump` | 776 488 | `ddf88255762ee33b0f2b4b73a62c3d671e89d8f9625cb750b93b73cf32c40ce5` |
| `produccion_estructura.sql` | 515 345 | `4256a7b6004a5c9096d937e7b21a87b2275bd64750afcf1508989a1c6f606f62` |
| `filas_por_tabla_en_el_volcado.tsv` | 1 538 | `eaae0bba6488ee75ee30ce32fa3d0c702afd26be80d49d1f0e97cad38b4de972` |
| `contenido_del_volcado.txt` | 73 892 | `f1b25df2c8c0ddfebe737ce307364167751dbe095516052e19f810ac1658d6ca` |

Los cuatro SHA-256 recalculados coinciden con el MANIFIESTO. Contenido recuperable comprobado (extraído con `pg_restore --data-only`, no solo nombres): `public.projects` 9 filas, `public.project_products` 22, `public.rfqs` 2 (más `products` 38, `profiles` 8 y `schema_migrations`), con recuentos idénticos a los del manifiesto y a las precomprobaciones. Las dos funciones a sustituir están en el volcado con cuerpo de md5 `eda482e4…` (`project_request_lines`) y `a2a34a98…` (`rfqs_lines_snapshot`) = 46-04.

Limitaciones: la restauración no se ha probado (no se restaura nada en Production); no incluye archivos de Storage, roles ni ajustes de Auth/Cloudflare. El volcado contiene el esquema `auth` (usuarios, sesiones, tokens): mantenerlo fuera del repositorio y con los permisos actuales (carpeta 700, archivos 600).

---

# Punto 47 — fase actual y progreso (47-01 APLICADA y REGISTRADA en Production, 2026-10-28)

**Destino:** `mobau-pilot`, ref `skcoxtdppdcietgojdal`. **Archivo:** `supabase/migrations/20261110120000_47_01_proyectos_areas.sql`, MD5 `1ec786cffbcc0e2f9e1da7cb4cd7798c` (comprobado antes de aplicar). Aplicado **una sola vez**, en una transacción (`BEGIN`/`COMMIT` del archivo, precedido de `set local lock_timeout = '5s'` y `set local statement_timeout = '60s'`), sin modificar el SQL ni añadir limpiezas o transformaciones de datos.

**Antes de escribir:** 53 migraciones, 46-06 registrada, 47-01 no; sin objetos nuevos; índice y funciones de 46-04 con sus md5; dependencias presentes; `room_or_area` 0; sin transacciones largas ni bloqueos; 9/22/2/38 (proyectos/líneas/RFQ/productos) y todas las huellas idénticas a las de la precomprobación anterior.

**Aplicación:** terminó sin error (la validación final de la propia migración pasó) y el COMMIT quedó confirmado.

**Verificación independiente (conexión nueva):**
- `project_areas` con RLS, 6 columnas, 4 restricciones (check de nombre, PK, FK a `projects`, único `(project_id,id)`), 4 índices y 11 políticas; `project_products.area_id` uuid nullable con la FK compuesta `(project_id, area_id)`; índice `project_products_area_line_unique` con la definición esperada y el antiguo retirado.
- Triggers: `trg_project_products_05_areas_guard` (+ los dos previos), `trg_project_areas_updated_at`, `trg_rfqs_10_lines_snapshot` intacto. Funciones nuevas SECURITY INVOKER; permisos de ejecución solo para `postgres`, `authenticated` y `service_role` (la del guard, solo `postgres` y `service_role`); sin permisos para `anon`.
- Grants: `authenticated` sobre `project_areas` = DELETE, INSERT, SELECT, y UPDATE solo de `name` y `sort_order`; UPDATE de `area_id` en `project_products`. Resto de grants (md5 `3469399f…`), políticas anteriores (md5 `2778d470…`) y privilegios por columna previos (md5 `fbe8ea41…`) idénticos. Nota: `anon` tiene sobre `area_id` los mismos privilegios de tabla que sobre las demás columnas (preexistentes, bloqueados por RLS); no es una exposición nueva.
- md5 de las funciones sustituidas = los esperados: `project_request_lines` `87693d922901b1a7f74e1f4199a9839c`, `rfqs_lines_snapshot` `a44af916a8484a3a1b4e644e0a6dd285`.
- Datos intactos: 9/22/2/38; md5 de `project_products` (sin la columna nueva) `35ef377c…`, `projects` `41426efc…` y `rfqs` `d3baca9f…` idénticos a los previos (cantidades, notas, configuraciones y RFQ históricas sin cambios; las 2 RFQ existentes siguen sin copia, como antes). 0 áreas, 0 líneas con área, ningún dato sintético; 24 tablas públicas (23 + `project_areas`).

**Registro (operación separada, tras COMMIT y verificación):** una inserción protegida (`where not exists`, 53 entradas, tabla presente) en `supabase_migrations.schema_migrations`: `version = 20261110120000`, `name = 47_01_proyectos_areas`, con el mismo formato que 46-06 (solo versión y nombre). Comprobado: 54 entradas, 47-01 aparece **una vez**.

**Estado del repositorio:** sin commit ni push; sin cambios respecto a antes de esta operación (los 24 archivos de la lista siguen pendientes, `proyecto-importes.js` y `proyecto-vista.js` con `git add -N`). El respaldo `~/mobau-respaldo-produccion/2026-10-28_1234` contiene datos de Auth: sigue fuera del repositorio y no se publica. La web publicada todavía es la anterior (compatible: ningún proyecto tiene áreas).

**Siguiente paso:** con tu autorización expresa, commit con la lista de 24 archivos por ruta y push (publica Cloudflare); confirmar el despliegue en verde; revisión posterior con el proyecto «VALIDACIÓN P47» que crearás tú.

---

# Punto 47 — revisión final: ajustes de texto aprobados y revisión funcional aprobada (2026-10-28)

La revisión funcional en «VALIDACIÓN P47» (web publicada, proyecto con áreas) queda **aprobada sin más incidencias**. Ajustes de texto aprobados:

1. **Texto al quitar un producto** (revisión en «VALIDACIÓN P47»): la confirmación de la acción «Quitar del proyecto» pasa de «¿Quitar esta línea del proyecto? El producto no se elimina del catálogo.» a **«¿Quitar este producto del proyecto?»** (`proyecto-vista.js`, caso `remove`). Solo cambia el texto del `confirm`; la acción es la misma: `removeLines([id])` → `MobauProjects.removeProductsFromProject` (`DELETE` de esa fila de `project_products` por su id) y actualiza la fecha del proyecto; no toca el catálogo ni otras líneas, y cancelar no cambia nada.
2. **Resto de textos de quitar productos alineados** (`proyecto-vista.js`; solo mensajes y singular/plural, la lógica de eliminación no cambia):
   - Tras quitar uno: «Producto quitado del proyecto.»
   - Confirmación al quitar varios (selección múltiple): «¿Quitar estos N productos del proyecto?» (N = cantidad seleccionada).
   - Tras quitar varios: «Productos quitados del proyecto.»
   - Si la selección múltiple contiene un solo producto se usan los textos en singular («¿Quitar este producto del proyecto?» / «Producto quitado del proyecto.»).
   - Comprobado en la página real con datos simulados: menú de la fila (1), selección de 1 (singular), selección de 2 («¿Quitar estos 2 productos…?», «Productos quitados…»); cada operación hizo un único `DELETE` de las filas elegidas (1, 1 y 2) y la actualización de la fecha del proyecto; sin errores en consola. Las suites no se repiten (solo cambian textos).
