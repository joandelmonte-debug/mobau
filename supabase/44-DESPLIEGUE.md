# Punto 44 · Vibia 3225: archivos, MD5, criterios de éxito y plan de validación

## Estado real (2026-10-22)

- **44-01 aplicada y registrada** el 2026-10-21 (`20261021120000 · 44_01_archivos_producto`, MD5 `872f463c…`). Se aplicó sin el ensayo `P44_ensayo.sql`, por decisión de alcance: el ensayo se versiona, pero no se ha ejecutado. Interfaz publicada en `4bef176` y `4f9ef26`.
- **Acabados simplificados** (`f5ec483`): cada acabado lleva solo código, nombre y predeterminado; en la ficha se eligen con botones de texto, sin foto.
- **Vibia 3225 publicado** por Spectro y aprobado por Mobau (`spectro-d3016bf1`, 13 archivos, acabados 25 y 11, portada `_04`).
- **44-02 aplicada y registrada** el 2026-10-22 (`20261022120000 · 44_02_ficha_iluminacion`, MD5 `44cfe8d7d56f88dc460bb060ffee3830`; recuperación `dbf31dfe3adfce033ee84598d3e0599e`, no ejecutada). Hay 39 migraciones.
  - Columnas `environment` (interior, exterior o ambos), `light_source` y `electrical_connection`.
  - Marca y medidas, obligatorias al enviar un producto nuevo.
  - La moderación, la copia al enviar y el catálogo incluyen los campos nuevos.
  - 3225 no cambió.
- **Interfaz de 44-02:**
  - en el formulario, primero la categoría, con la plantilla de Iluminación;
  - «Interior o exterior» sustituye a Uso y Espacio en el formulario; los datos antiguos se conservan;
  - en moderación, los archivos se abren con enlaces ya firmados, sin ventanas emergentes. Caducan a los 30 minutos y se renuevan recargando la página.
- **Ajustes de la ficha cerrados** (`6f6f33c`, `40105a9`, verificados en Pages): acordeón de descargas, flechas de la galería y «Tiempo de entrega».
- **Aplicado y registrado el 2026-10-22**, con 41 migraciones. Cada una con su COMMIT confirmado por lectura y su registro en una llamada aparte. 3225 no cambió.
  - **44-03 · temperatura de color** (`20261023120000_44_03_temperatura_color`, MD5 `20000731ac02e93f818379b38856f95f`; recuperación `27f607858e095b98e8e9c49f1a0fce43`).
    - Columna opcional `products.color_temperature`, en texto canónico: opciones fijas «2700» o «2700,3000», o intervalo regulable «2700-6500».
    - Validación del servidor: 1000–20000 K, hasta 10 opciones, sin repetidos e intervalo de menor a mayor.
    - El tono no se guarda: lo calcula la interfaz con los criterios adoptados por Mobau (cálida por debajo de 3300 K, neutra de 3300 a 5300 K y fría por encima de 5300 K).
    - La ficha lo muestra como «Tono de luz».
  - **44-04 · permisos de `products`** (`20261023120100_44_04_permisos_products`, MD5 `67591b8487e4a37faecbc772a79ca5fa`; recuperación `80277591961f6f5b881cc92354eebc8b`). Retira REFERENCES y TRIGGER a `anon` y `authenticated`. Son concesiones directas de `postgres`, sin PUBLIC ni herencia, y no hacen falta.
    - Después: la tabla de permisos de `products` queda solo con `postgres` y `service_role`.
    - No cambian los 56 permisos por columna, las políticas, RLS, las 6 claves ajenas ni los 4 triggers.
    - `distributors` y `profiles` tienen el mismo patrón, pero no entran aquí.
  - **Moderación:** aviso «Los enlaces caducan a los 30 minutos. Recarga la página para renovarlos.», sin botón ni renovación automática.
  - **Ficha:** la elección de acabado pasa a estar debajo del precio y su nota, antes de «Antes de sumarlo a tu proyecto…».
- **Acabado de cada foto, aplicado y registrado el 2026-10-22** (42 migraciones; COMMIT confirmado por lectura; ninguna foto con acabado asignado; 3225 sin cambios): 44-05 (`20261024120000_44_05_acabado_de_cada_foto`, MD5 `dfcacf3551cb1d0350761a06a4264c10`; recuperación `8ec2b961f99fc185f109b1404af3e4bb`).
  - Cada foto aprobada puede tener un acabado (`product_assets.finish_code`) o quedar como imagen de referencia sin asignar; un acabado puede tener varias fotos.
  - La relación tiene una clave ajena a `product_finishes (product_id, code)`, con `ON UPDATE CASCADE` y `ON DELETE SET NULL (finish_code)`.
  - En la propuesta, cada foto lleva `finish` (un código de sus acabados). Al aprobar se reescriben a la vez acabados y asociaciones.
  - No exige recorte 4:5. 3225 queda sin asociaciones hasta que se propongan.
- **Sigue fuera del alcance:** los demás campos opcionales de iluminación (control, flujo, CRI, potencia, driver, IP y clase energética) y los filtros del catálogo por tono.

Lo que sigue es la entrega original, previa a la aplicación.

**Lectura de partida de la entrega original (solo SELECT):**
- 37 migraciones; la última es `20261020180000`.
- 44-01 no está aplicada.
- Transición `19d26a92…`; vista `44a582cd…` con opciones y permisos de siempre.
- Sin buckets ni políticas de Storage del 44.
- 34 líneas de proyecto; 20 productos publicados.

## 1. Archivos y MD5

### Servidor (scratchpad `44/servidor/`, se generan con `44/herramientas/generar_44.py`)

| Archivo | MD5 | Qué es |
|---|---|---|
| `20261021120000_44_01_archivos_producto.sql` | `872f463c2aee16659b76dee96d15573d` | Migración única (38,9 KB) |
| `20261021120000_44_01_archivos_producto.rollback.sql` | `4e0b2ef941a70e20c6f2efe00a08ecc7` | Recuperación |
| `44_01_lectura.sql` | `886721990a7fdf76eda0e230b2f658da` | Lectura, solo SELECT; ya ejecutada una vez como partida |
| `P44_ensayo.sql` | `96522685b14c5cbc878e02af5710de76` | Ensayo revertido (96 KB; lleva dentro la migración y la recuperación) |

Herramientas:

| Archivo | MD5 |
|---|---|
| `generar_44.py` | `2439af0d30d378fd07142e7b8b717295` |
| `plantilla_migracion.sql` | `aa0e52acfa5f75af2a0a775325a0730f` |
| `plantilla_recuperacion.sql` | `56c2771e993ec8bc046bb33bd263843e` |
| `plantilla_ensayo.sql` | `b1b3e46efd61e2451a13e8263a5aee19` |
| `plantilla_lectura.sql` | `a39e28756204cbc7591cd1b06eb7b5e6` |
| `transicion_original.txt` | `19d26a925b9d97c89715254f219fbe7e` (= cuerpo vigente) |
| `balance.py` | `64850a12af9737914ea5aaef2d36d5b8` |

Cuerpo nuevo de `transition_proposal_status`: `3eef0e1ad9a754c54fcc1ac536301b53`. Lleva dos cambios exactos:
- Mobau no puede modificar `proposed_media`.
- Una propuesta de cambio que solo trae archivos ya no es «sin cambios».

**Qué hace 44-01:**
- **`products`:** nuevas columnas `reference_code` (única por empresa) y `cover_asset_id`.
- **`product_assets`:**
  - 8 tipos con formatos cerrados;
  - el distribuidor solo inserta filas «pendiente» en su carpeta y solo borra las pendientes;
  - nunca puede actualizarlas.
- **`product_finishes`:** solo lectura desde la web.
- **`product_proposals.proposed_media`:**
  - el trigger 35 la valida;
  - el trigger 60 la aplica al aprobar;
  - sin referencia o sin portada da 55000 y no se aprueba.
- **`project_products.finish_code`:**
  - índice único por producto y acabado;
  - sin UPDATE para la web.
- **`catalog_products`:** 4 columnas nuevas al final; mismas opciones y permisos.
- **Buckets:**
  - `productos-imagenes`, público, solo JPEG, MP4 y WebM;
  - `productos-archivos`, privado; descarga con `can_download_product_file`, mismas reglas del punto 42.
- **Permisos:** EXECUTE explícitos, por SEG-01.

### Repositorio (sin commit)

| Archivo | MD5 | Cambio |
|---|---|---|
| `producto-archivos.js` (nuevo) | `10794919ade526b7e3fd60bb3388ab43` | Tipos, subida (fila y luego archivo; si falla, borra la fila), recorte 4:5 (1600×2000 y 800×1000, fondo blanco), galería a 2400 px, descarga firmada |
| `distribuidor-propuestas.html` | `477f06b9b4b60640a346800792022b7d` | Fuera los 3 campos de enlace. Nuevos: referencia, portada (recorte), acabados con foto y uno por defecto, galería, ficha, vídeos y archivos profesionales |
| `moderacion-propuesta.html` | `562df89cdf54b22786a54ad19b0c96e4` | Sección «Referencia, fotos y archivos»: miniaturas, acabados, archivos con enlace firmado. «Aprobar» bloqueado si falta referencia o portada |
| `producto.html` | `6fe2a5c3f31a738ce9c4162f709e88d7` | Referencia, galería 4:5 con miniaturas, selector de acabado (cambia la foto), descargas por tipo, añadir con acabado |
| `script.js` | `78bbb4e0b341380f7fe8921cf93dd1c4` | 25 columnas, caché v3, portada 4:5 en tarjetas, referencia en la tarjeta, acabado por defecto, ayudas de texto de línea |
| `seleccion-data.js` | `ccc19f019b8c416a312adcbbcad6a8af` | Líneas `{productId, finish?, quantity, unit}`: clave producto y acabado |
| `proyectos-data.js` | `de63e0c5e1838b0f3055dd50bf8e9279` | Guardar, listar y transferir con `finish_code` |
| `seleccion.html` | `48c5ca46c9af7f79a30fedda4dc1e58e` | Acabado y referencia por línea; botones por línea |
| `proyectos-detalle.html` | `4d63b692ae24bad000c9f0b9527ea242` | Muestra referencia y acabado |
| `proyectos-resumen.html` | `219b3c69fd995acf57e43f2425499071` | Muestra referencia y acabado |
| `proyectos-cotizacion.html` | `0525f3a95a1268b1f14d482dfa5b3410` | Muestra referencia y acabado; conserva el acabado al pasar de la selección |
| `catalogo.html` | `67346077abc9b2ca8b09e1e4df3b6dd0` | «Añadir a mi proyecto activo» con el acabado por defecto |
| `product-lifecycle.js` | `2d3c2b142b1e8488bd4a6e7066bf49ad` | Claves de caché v3 |
| `styles.css` | `b661c24d253fc41ed57c01028e4701b6` | Tarjeta y galería 4:5; miniaturas |
| `scripts/pages-manifest.txt` | `fc0b281e184604676683883e6555d573` | Añade `producto-archivos.js` (51 rutas) |
| `CLAUDE.md` | `40867a475aa09768c7f4f166eba06cd3` | Regla: una línea por producto y acabado |
| `.gitignore` | `7e06f60050cd717ba9bbf61a3e584c30` | `/materiales/` |
| `supabase/tests/44/interfaz/pruebas-44.html` (nuevo) | `e144d6afcd5544d017a9b612292c4d25` | Pruebas con simulaciones: **39/39 pasadas** |

`.claude/launch.json` es solo el servidor local de las pruebas y no entra en git.

### Preparación local de 3225 (`materiales/preparado/vibia/3225/`, fuera de git)

Contiene 15 copias exactas en 7 carpetas numeradas y un `LEEME.md`. El LEEME indica qué subir en cada sección del formulario y lista los MD5 de cada copia. Por ejemplo, la portada `01-portada/Vibia_Dama_3225-25_04.jpg` tiene `0d7e95f4f3c7e178a5d7531085a45223`.

## 2. Criterios de éxito

### Ensayo P44 (revertido)

El ensayo debe terminar exactamente en MB990 con `cambia=true identico=true sondas=true fallos=0`. En la lista no puede aparecer ningún `!` ni ningún `ABORTO`.

| Grupo | Casos | Qué comprueba |
|---|---|---|
| Archivos | S01–S08 | Alta de 9 archivos como Spectro. Rechazos: otra empresa 42501, estado aprobado 42501, PNG 23514, ruta con `..` 23514, versión de tarjeta en un PDF 23514, CAD en el bucket de imágenes 23514, anónimo 42501 |
| Storage | S09–S11 | Subida a la carpeta propia (9 objetos); carpeta ajena 42501; anónimo 42501 |
| Propuesta | S12–S19 | Archivo ajeno 23514. Borrador. Portada sin recorte, dos acabados por defecto y un archivo repetido: 23514. Envío sin referencia 23514. Envío correcto. Edición en revisión 42501 |
| Moderación | S20–S24 | Aprobar sin portada da 55000 y no crea producto. Se solicitan cambios, se elige la portada, se reenvía y se aprueba |
| Resultado | S25–S27 | `3225\|true\|published\|active\|Beige D1, Black`. Archivos: 8 aprobados y 1 pendiente. Acabados `25` y `11` con su foto |
| Público | S28–S31 | El catálogo anónimo trae referencia, portada, tarjeta y acabados. El anónimo ve 8 archivos y ningún pendiente ni ajeno; no lista archivos privados (0); `can_download` le da 42501 |
| Descargas | S32–S35 | Gratis 4, Individual 4, Spectro 5 (los suyos), Mobau 5 |
| Proyecto | S36–S41 | Individual guarda las líneas 25 y 11. Repetir 25 da 23505. Cambiar la cantidad funciona; cambiar el acabado da 42501. Acabado con espacios 23514. Sin acabado entra una vez; la segunda da 23505 |
| Cambio | S42–S45 | Un cambio solo con archivos (añade el LDT) se envía y se aprueba: 9 archivos. Un cambio vacío sigue dando 23514 |
| Recuperación con datos | S46–S47 | Con líneas por acabado se detiene (MB441). Tras dejar una línea, copia `10\|2\|1\|2\|1\|9`, conserva los 2 buckets con archivos y deja transición y vista originales |

Al terminar, la recuperación sin datos debe dejar la huella final idéntica a la de partida.

### Aplicación de 44-01

**Tras confirmar el COMMIT, `44_01_lectura.sql` debe dar:**
- `aplicada=true` y `registrada=false`;
- `md5_transicion=3eef0e1a…`;
- vista con `{security_invoker=true,security_barrier=true}` y los mismos permisos;
- buckets `productos-archivos:false:52428800,productos-imagenes:true:52428800`;
- 5 políticas de Storage, 8 de tablas y 0 objetos;
- 34 líneas de proyecto y 20 productos publicados, sin cambios.

**El registro va después, en otra llamada:** `20261021120000 · 44_01_archivos_producto`, con 38 migraciones en total.

### Interfaz

- Pruebas con simulaciones 39/39: ya pasadas.
- **Orden obligatorio: la migración, antes que la interfaz.** La interfaz nueva pide las 4 columnas nuevas; la antigua sigue funcionando con la vista nueva.
- La compilación de Pages debe publicar 51 archivos.

## 3. Plan de validación con 3225

Cada paso necesita su propia autorización. Si algo falla, se para, no se reintenta y se lee el estado.

1. **V0 · Ensayo `P44_ensayo.sql`.**
   - Se ejecuta con el control MD5 del archivo y debe cumplir los criterios del apartado 2.
2. **V1 · Aplicar 44-01**, con su control MD5.
3. **V2 · Lectura.**
4. **V3 · Registrar**, en otra llamada y solo tras confirmar el COMMIT.
5. **V4 · Commits, push y despliegue.**
   - Un commit con la interfaz y la regla.
   - Otro con el SQL, las pruebas y el documento del 44 en `supabase/`.
   - Después, la compilación (51 archivos) y el despliegue en Pages.
6. **V5 · Tú, como Spectro**, creas el producto siguiendo el `LEEME.md`:
   - nombre «Dama sobremesa», marca Vibia, Iluminación · Decorativa;
   - referencia 3225;
   - portada `_04` recortada en 4:5;
   - acabados 25 Beige D1 (3225-25, por defecto) y 11 Black (3225-11), cada uno con su silueta;
   - galería `_03` y `_02`, y `_01` si quieres;
   - ficha PDF, DWG, 3DS, MAX, OBJ, IES, LDT, OXL e informe fotométrico.
   - Guardas un borrador, lo vuelves a abrir (todo debe seguir ahí) y lo envías.
7. **V6 · Lectura:** 14 o 15 archivos pendientes y la propuesta enviada.
8. **V7 · Mobau (con aal2)** revisa la sección de archivos: miniaturas, abrir 2 o 3 archivos y portada marcada. Aprueba.
9. **V8 · Lectura y comprobaciones por rol.**
   - La lectura debe dar `producto_3225 = <id>|3225|published|portada=true|acabados=2|archivos=14 o 15`.
   - En la web:
     - **Catálogo:** tarjeta 4:5 con la portada y «Ref. 3225».
     - **Ficha:** referencia, miniaturas, selector de acabado (cambia la foto) y descargas.
   - **Descargas por rol:**

     | Rol | Resultado esperado |
     |---|---|
     | Anónimo | Botones desactivados |
     | Gratis 46ea4397 | Descarga el DWG |
     | Individual e2a655c1 | Descarga la ficha y el IES |
     | Spectro | Descarga |
10. **V9 · Individual e2a655c1** añade 3225 en Beige D1 y en Black.
   - En Mi selección aparecen 2 líneas.
   - Al pasarlas al proyecto activo quedan 2 filas con `finish_code` 25 y 11.
   - Resumen y cotización muestran el acabado.
   - **No se envía solicitud.**
11. **V10 · Limpieza autorizada** de esas 2 líneas de prueba. El producto 3225 queda publicado como primera subida real.

## 4. Notas y límites

- **Hofflights:** las fotos de 850 px se aceptan como excepción del piloto. Conviene pedir a Spectro los originales en mayor resolución más adelante.
- **Archivos huérfanos en Storage.** La web no borra objetos de Storage. Quedan huérfanos en tres casos:
  - lo que se quita de una propuesta;
  - lo que se sustituye;
  - lo de los productos purgados (la fila se borra en cascada).

  No son públicos salvo las fotos, que tienen ruta con uuid. Su limpieza queda para un punto posterior, con la API de Storage.
- **Acabados en el texto del producto:** al aprobar con acabados, `products.finishes` pasa a ser la lista de nombres.
- **Cambios con archivos:** un cambio que toca los archivos envía la lista completa. Lo que no esté en la lista pasa a «retirado».
- **Recuperación con archivos:** si los buckets tienen archivos, la recuperación los conserva (y siguen servidos). Si hay líneas por acabado duplicadas, se detiene (MB441).
- **Verificación sin servidor:** el SQL tiene los paréntesis y las comillas comprobados en local. El servidor no ha validado la sintaxis: eso lo hará el ensayo.
- **Material de Spectro ya señalado:**
  - duplicados: 3225-25_01 = 3230-25; 5500-07 tiene una copia « 2»;
  - referencias que no cuadran;
  - Athens sin PDF;
  - 5520 con `.mtl` sin `.obj`.

## 5. Punto 45 (nota breve)

- **Estado (2026-10-22):** 45-01 **aplicada y registrada** (`20261025120000 · 45_01_restaurar_sin_publicar`, 43 migraciones).
  - Migración: `migrations/20261025120000_45_01_restaurar_sin_publicar.sql`, MD5 `6066795e…`.
  - Recuperación: `rollback/…rollback.sql`, MD5 `05175129…` (no ejecutada).
  - Lectura posterior: productos, archivos, acabados, propuestas, permisos y políticas sin cambios.
- **45-01:** al restaurar desde la papelera, lo que la empresa retiró vuelve a «retirado», no a publicado. Para volver al catálogo: proponer cambios (si hace falta) y después solicitar la republicación. El resto de casos y restricciones no cambia.
- **Orden de despliegue:** 45-01 antes que la interfaz. Sin 45-01 aplicada, restaurar sigue publicando, y la interfaz lo dice así.
- **Interfaz:**
  - Resumen: datos por completar con portada, fotos y descargables aprobados; sin papelera.
  - Mis productos: pestañas, filas compactas, búsqueda por código y selección en memoria.
- **Acabados sin código comercial:** nombre obligatorio y código comercial opcional (2026-10-22).
  - `product_finishes.code` es la clave técnica: estable y oculta, generada por el editor en los acabados nuevos.
  - `reference_code` es el «Código del acabado», opcional.
- **45-02 aplicada y registrada** (`20261026120000 · 45_02_codigo_comercial_acabado`, 44 migraciones).
  - Migración: `migrations/20261026120000_45_02_codigo_comercial_acabado.sql`, MD5 `849ceacf…`.
  - Recuperación: `rollback/…rollback.sql`, MD5 `a87ab024…` (no ejecutada).
  - Copió `code` → `reference_code` en los 22 acabados aprobados. Claves, fotos, líneas, productos, propuestas, permisos y políticas sin cambios.
- **Acciones de grupo en Mis productos** (2026-10-22): mover a papelera, preparar cambios, descartar borradores, solicitar republicación y restaurar para revisar.
  - Una llamada por elemento, con las funciones existentes; no hay envío masivo ni eliminación definitiva masiva.
- **45-03 aplicada y registrada** (`20261027120000 · 45_03_purga_lampara_prueba`, 45 migraciones).
  - Migración: `migrations/…45_03…sql`, MD5 `88718ac4…`.
  - Respaldo: `rollback/…rollback.sql`, MD5 `58d8b2ed…` (no ejecutado).
  - Purgó solo `spectro-a7a2cfba` y su precio. Auditoría: `actor_kind` mobau, `actor_id` nulo, `meta.via` sql_admin.
- **Segunda lámpara (2026-10-23):**
  - La línea `899b0af5…` del proyecto de prueba `a33bb396…` se quitó con autorización. El proyecto sigue activo con 5 líneas. Script ya ejecutado: `limpieza/45_04a_quitar_linea_899b0af5.EJECUTADA.sql`.
  - **45-04 aplicada y registrada** (`20261028120000 · 45_04_purga_lampara_prueba_2`, 46 migraciones). Purgó `spectro-02988ada` y su precio, con la misma auditoría que 45-03 más `meta.project_line_removed`.
  - Migración MD5 `9735593d…`; respaldo MD5 `c0632508…`, no ejecutado.
- **Pendiente del punto 45:** revisión real de las acciones de grupo y prueba real de restauración y republicación.

## 6. Punto 45.1 (nota breve)

- **Quitar notificaciones en Mis productos** (2026-10-25): botón «Quitar» en «Avisos de Mobau» y «Decisiones recientes».
  - Cada sección muestra 3 como máximo; el resto queda bajo «Ver más avisos (N)» / «Ver más decisiones (N)».
  - El descarte es por usuario y solo oculta la notificación: no borra auditoría, propuestas ni motivos.
- **45.1-01 aplicada y registrada** (`20261029120000 · 45_1_01_descartes_notificaciones`, 47 migraciones).
  - Tabla `public.notification_dismissals` con RLS: cada usuario lee, crea y borra solo lo suyo; sin UPDATE y sin acceso para anon.
  - Migración MD5 `72e9ddaf…`; recuperación MD5 `272a2686…` (no ejecutada; perdería los descartes).
  - Prueba real con identidad de prueba y UUID ficticio, como `authenticated`: persistencia, aislamiento entre usuarios, UPDATE denegado y anon denegado. Filas sintéticas eliminadas.

## 7. Punto 46 · componentes y accesorios (bloque 1, base de datos)

- **46-01 aplicada y registrada** (`20261030120000 · 46_01_componentes_base`).
  - Añade `products.catalog_role` (principal, componente o ambos; todos los existentes, principal).
  - Crea `product_component_groups` y `product_component_options`, con claves estables, estado activo o retirado e integridad diferida (mismo distribuidor, sin ciclos, como máximo principal → componente → subcomponente).
  - Crea las vistas públicas `catalog_component_groups` y `catalog_component_options`.
  - Añade `catalog_role` a `catalog_products`, que conserva sus columnas, filas y permisos.
  - Lectura con RLS; sin escritura directa para `anon` ni `authenticated`.
  - Migración MD5 `446faa96…`; recuperación MD5 `5e40e565…`.
- **46-02 aplicada y registrada** (`20261030130000 · 46_02_corrige_comprobacion_componentes`): corrige el defecto de 46-01 que detectó el ensayo (la comprobación leía `new.kind` en filas de grupos). Migración MD5 `dd5278e8…`; recuperación MD5 `64f9beb3…`.
- **Ensayo** `tests/46/P46_01_ensayo.sql` (MD5 `5ce196bb…`): 27 correctos, 0 fallos inesperados, todo revertido.
- **Recuperaciones:** sin ejecutar. Se probarán en un entorno aislado; la de 46-02 restaura la función con el defecto.
- Mobau organiza las elecciones que declara el distribuidor; no certifica compatibilidad técnica.
