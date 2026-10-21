/* ============================================================
   MOBAU — Archivos reales de producto (punto 44)
   ------------------------------------------------------------
   Compartido por la propuesta del distribuidor, la moderación y la ficha.
     - Fotos y vídeos: bucket público productos-imagenes (URL fija).
     - Ficha técnica, CAD 2D, CAD 3D, BIM, cálculo de iluminación y
       manual: bucket privado productos-archivos, con enlace firmado de
       pocos minutos. Pueden descargarlos los profesionales (Gratis
       incluido), Mobau y la empresa del producto (reglas del punto 42).
   Cada archivo subido es una fila de product_assets «pendiente» en la
   carpeta <empresa>/<uuid>/ y pasa a «aprobado» cuando Mobau aprueba la
   propuesta que lo incluye. Los archivos no se modifican: un recorte nuevo
   es un archivo nuevo.
   Fotos: se preparan en el navegador. Portada y fotos de acabados se
   recortan en 4:5 (1600×2000 y versión de tarjeta 800×1000, JPEG, fondo
   blanco); las de galería se reducen a 2400 px en el lado largo.
   La seguridad real está en RLS, permisos por columna, políticas de
   Storage y triggers; aquí solo se adelantan los mensajes.
   ============================================================ */

const MobauArchivos = (() => {
  const IMAGES_BUCKET = "productos-imagenes";
  const FILES_BUCKET = "productos-archivos";
  const MAX_BYTES = 50 * 1024 * 1024;
  const SIGNED_SECONDS = 300;
  const ASSET_COLUMNS = "id, distributor_id, product_id, kind, bucket, path, variants, original_name, format, label, bytes, width, height, sort_order, status";

  /* Mismos tipos y formatos que product_assets_format_valid (44-01). */
  const KINDS = Object.freeze({
    foto:                { label: "Foto",                   formats: ["jpg"] },
    video:               { label: "Vídeo",                  formats: ["mp4", "webm"] },
    ficha_tecnica:       { label: "Ficha técnica",          formats: ["pdf"] },
    cad_2d:              { label: "CAD 2D",                 formats: ["dwg", "dxf"] },
    cad_3d:              { label: "CAD 3D",                 formats: ["dwg", "dxf", "3ds", "max", "obj", "mtl", "fbx", "skp", "stp", "step"] },
    bim:                 { label: "BIM",                    formats: ["ifc", "rfa", "rvt"] },
    calculo_iluminacion: { label: "Cálculo de iluminación", formats: ["ies", "ldt", "oxl", "ulf", "pdf"] },
    manual:              { label: "Manual",                 formats: ["pdf"] }
  });
  /* Orden de las descargas en la ficha y en la moderación. */
  const DOWNLOAD_KINDS = ["ficha_tecnica", "cad_2d", "cad_3d", "bim", "calculo_iluminacion", "manual"];
  const PHOTO_INPUT_TYPES = "image/jpeg,image/png,image/webp";
  const CROP = Object.freeze({ width: 1600, height: 2000, cardWidth: 800, cardHeight: 1000, quality: 0.82 });
  const GALLERY_MAX = 2400;
  const GALLERY_QUALITY = 0.85;

  function bucketFor(kind){ return kind === "foto" || kind === "video" ? IMAGES_BUCKET : FILES_BUCKET; }

  function extensionOf(name){
    const match = /\.([A-Za-z0-9]+)$/.exec(String(name || ""));
    return match ? match[1].toLowerCase() : "";
  }

  function formatFor(kind, name){
    const ext = extensionOf(name);
    const format = ext === "jpeg" ? "jpg" : ext;
    return KINDS[kind] && KINDS[kind].formats.includes(format) ? format : null;
  }

  function acceptFor(kind){
    return KINDS[kind] ? KINDS[kind].formats.map(f => `.${f}`).join(",") : "";
  }

  /* URL pública de una ruta del bucket de imágenes. */
  function publicUrl(path){
    if (typeof path !== "string" || !path) return null;
    return `${SUPABASE_URL}/storage/v1/object/public/${IMAGES_BUCKET}/${path.split("/").map(encodeURIComponent).join("/")}`;
  }

  function cardUrl(asset){
    return publicUrl((asset && asset.variants && asset.variants.card) || (asset && asset.path));
  }

  function sizeText(bytes){
    if (!Number.isFinite(bytes)) return "";
    if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
    return `${(bytes / (1024 * 1024)).toLocaleString("es-DO", { maximumFractionDigits: 1 })} MB`;
  }

  /* Nombre de archivo seguro para la ruta (sin acentos, espacios ni barras). */
  function safeFileName(name, ext){
    const base = String(name || "archivo").replace(/\.[A-Za-z0-9]+$/, "")
      .normalize("NFD").replace(/[̀-ͯ]/g, "")
      .replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^[-.]+|[-.]+$/g, "").slice(0, 80) || "archivo";
    return `${base}.${ext}`;
  }

  /* ---------- lectura ---------- */
  async function listApproved(productId){
    const { data, error } = await supabaseClient.from("product_assets").select(ASSET_COLUMNS)
      .eq("product_id", productId).eq("status", "aprobado").order("sort_order", { ascending: true });
    if (error) throw error;
    return data || [];
  }

  async function listByIds(ids){
    const unique = [...new Set((ids || []).filter(Boolean))];
    if (!unique.length) return [];
    const { data, error } = await supabaseClient.from("product_assets").select(ASSET_COLUMNS).in("id", unique);
    if (error) throw error;
    return data || [];
  }

  /* Enlace de descarga: público para fotos y vídeos; firmado (con el nombre
     original) para el resto. Sin permiso, Storage no firma: devuelve error.
     inline: true lo abre en el navegador (PDF) en lugar de descargarlo. */
  async function downloadUrl(asset, { inline = false, seconds = SIGNED_SECONDS } = {}){
    if (asset.bucket === IMAGES_BUCKET) return publicUrl(asset.path);
    const { data, error } = await supabaseClient.storage.from(FILES_BUCKET)
      .createSignedUrl(asset.path, seconds, inline ? {} : { download: asset.original_name || true });
    if (error || !data || !data.signedUrl) throw error || new Error("No pudimos preparar la descarga.");
    return data.signedUrl;
  }

  /* ---------- subida ---------- */
  /* Registra la fila (pendiente) y sube el archivo y su versión de tarjeta.
     Si la subida falla, borra la fila: no quedan filas sin archivo. */
  async function registerAndUpload({ distributorId, kind, originalName, format, uploads, variants, width, height, bytes }){
    const bucket = bucketFor(kind);
    const { data: row, error } = await supabaseClient.from("product_assets").insert({
      distributor_id: distributorId, kind, bucket, path: uploads[0].path, variants: variants || {},
      original_name: String(originalName || "archivo").slice(0, 200), format,
      bytes: Number.isFinite(bytes) ? bytes : null, width: width || null, height: height || null
    }).select(ASSET_COLUMNS).single();
    if (error || !row) throw error || new Error("No pudimos registrar el archivo.");
    for (const upload of uploads){
      const { error: uploadError } = await supabaseClient.storage.from(bucket)
        .upload(upload.path, upload.body, { contentType: upload.contentType, upsert: false, cacheControl: "31536000" });
      if (uploadError){
        await supabaseClient.from("product_assets").delete().eq("id", row.id);
        throw uploadError;
      }
    }
    return row;
  }

  function checkSize(file){
    if (file.size > MAX_BYTES) throw new Error(`«${file.name}» supera los 50 MB.`);
  }

  /* Vídeo, ficha técnica o archivo profesional, tal cual. */
  async function uploadFile({ distributorId, kind, file }){
    const format = formatFor(kind, file.name);
    if (!format) throw new Error(`«${file.name}» no es un formato admitido para ${KINDS[kind] ? KINDS[kind].label.toLowerCase() : "este tipo"} (${KINDS[kind] ? KINDS[kind].formats.join(", ") : ""}).`);
    checkSize(file);
    const folder = `${distributorId}/${crypto.randomUUID()}`;
    const contentType = kind === "video" ? (format === "webm" ? "video/webm" : "video/mp4")
      : (format === "pdf" ? "application/pdf" : "application/octet-stream");
    return registerAndUpload({
      distributorId, kind, originalName: file.name, format, bytes: file.size,
      uploads: [{ path: `${folder}/${safeFileName(file.name, format)}`, body: file, contentType }]
    });
  }

  /* Foto: crop=true abre el recorte 4:5 (portada y acabados); si no, se
     reduce para la galería. Devuelve null si se cancela el recorte. */
  async function uploadPhoto({ distributorId, file, crop }){
    if (!/^image\/(jpeg|png|webp)$/.test(file.type)) throw new Error(`«${file.name}» no es una foto JPG, PNG o WebP.`);
    const prepared = crop ? await cropDialog(file) : await resizeForGallery(file);
    if (!prepared) return null;
    if (prepared.main.size > MAX_BYTES) throw new Error("La foto preparada supera los 50 MB.");
    const folder = `${distributorId}/${crypto.randomUUID()}`;
    const name = safeFileName(file.name, "jpg");
    const uploads = [{ path: `${folder}/${name}`, body: prepared.main, contentType: "image/jpeg" }];
    let variants = {};
    if (prepared.card){
      const cardPath = `${folder}/${name.replace(/\.jpg$/, "")}-card.jpg`;
      uploads.push({ path: cardPath, body: prepared.card, contentType: "image/jpeg" });
      variants = { card: cardPath };
    }
    return registerAndUpload({
      distributorId, kind: "foto", originalName: file.name, format: "jpg", bytes: prepared.main.size,
      width: prepared.width, height: prepared.height, uploads, variants
    });
  }

  /* ---------- imágenes en el navegador ---------- */
  function canvasToJpeg(canvas, quality){
    return new Promise((resolve, reject) => {
      canvas.toBlob(blob => blob ? resolve(blob) : reject(new Error("No pudimos preparar la foto.")), "image/jpeg", quality);
    });
  }

  /* Decodifica la foto y, si es muy grande, la reduce a la mitad mientras
     siga teniendo al menos maxSide en el lado largo (mejor calidad que una
     sola reducción grande). */
  async function loadSource(file, maxSide = 3000){
    let bitmap;
    try {
      bitmap = await createImageBitmap(file);
    } catch (e) {
      throw new Error(`No pudimos abrir «${file.name}». Prueba con otra foto.`);
    }
    let source = bitmap;
    let w = bitmap.width, h = bitmap.height;
    while (Math.max(w, h) / 2 >= maxSide){
      w = Math.round(w / 2); h = Math.round(h / 2);
      const step = document.createElement("canvas");
      step.width = w; step.height = h;
      const ctx = step.getContext("2d");
      ctx.imageSmoothingQuality = "high";
      ctx.drawImage(source, 0, 0, w, h);
      if (source !== bitmap) source.width = source.height = 0;
      source = step;
    }
    if (source !== bitmap && bitmap.close) bitmap.close();
    return { source, width: w, height: h };
  }

  function whiteCanvas(width, height){
    const canvas = document.createElement("canvas");
    canvas.width = width; canvas.height = height;
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0, 0, width, height);
    ctx.imageSmoothingQuality = "high";
    return { canvas, ctx };
  }

  async function resizeForGallery(file){
    const { source, width, height } = await loadSource(file, GALLERY_MAX);
    const scale = Math.min(1, GALLERY_MAX / Math.max(width, height));
    const w = Math.round(width * scale), h = Math.round(height * scale);
    const { canvas, ctx } = whiteCanvas(w, h);
    ctx.drawImage(source, 0, 0, w, h);
    return { main: await canvasToJpeg(canvas, GALLERY_QUALITY), card: null, width: w, height: h };
  }

  let cropStyleAdded = false;
  function addCropStyle(){
    if (cropStyleAdded) return;
    cropStyleAdded = true;
    const style = document.createElement("style");
    style.textContent = `
      .mobau-crop{ position:fixed; inset:0; z-index:1000; display:flex; align-items:center; justify-content:center; padding:16px; background:rgba(20,20,20,.55); }
      .mobau-crop__box{ background:var(--bg, #fff); border-radius:var(--radius-lg, 8px); padding:20px; width:min(380px, 100%); max-height:100%; overflow:auto; }
      .mobau-crop__box h2{ font-size:18px; margin:0 0 6px; }
      .mobau-crop__canvas{ display:block; width:100%; max-width:320px; aspect-ratio:4/5; margin:12px auto; border:1px solid var(--line, #ddd); background:#fff; cursor:grab; touch-action:none; }
      .mobau-crop__canvas:active{ cursor:grabbing; }
      .mobau-crop__canvas:focus-visible{ outline:2px solid var(--accent, #333); outline-offset:2px; }
      .mobau-crop__zoom{ display:flex; align-items:center; gap:10px; font-size:13.5px; margin:0 0 14px; }
      .mobau-crop__zoom input{ flex:1; }
      .mobau-crop__actions{ display:flex; flex-wrap:wrap; justify-content:flex-end; gap:10px; }`;
    document.head.appendChild(style);
  }

  /* Recorte 4:5: arrastrar para encuadrar, control para acercar o alejar
     (alejando, el hueco queda blanco). Teclado: flechas y + / −. */
  async function cropDialog(file){
    const { source, width: iw, height: ih } = await loadSource(file);
    addCropStyle();
    const W = 320, H = 400;
    const contain = Math.min(W / iw, H / ih);
    const cover = Math.max(W / iw, H / ih);
    const max = cover * 3;
    const scaleAt = (t) => contain * Math.pow(max / contain, t);
    let t = Math.log(cover / contain) / Math.log(max / contain);
    let cx = W / 2, cy = H / 2;

    const overlay = document.createElement("div");
    overlay.className = "mobau-crop";
    overlay.innerHTML = `
      <div class="mobau-crop__box" role="dialog" aria-modal="true" aria-labelledby="mobau-crop-title">
        <h2 id="mobau-crop-title">Recorta la foto en 4:5</h2>
        <p class="card-meta" style="margin:0;">Arrastra para encuadrar el producto y usa el control para acercar o alejar. El espacio vacío queda en blanco.</p>
        <canvas class="mobau-crop__canvas" tabindex="0" aria-label="Encuadre de la foto"></canvas>
        <label class="mobau-crop__zoom">Alejar <input type="range" min="0" max="1000" step="1" aria-label="Zoom"> Acercar</label>
        <div class="mobau-crop__actions">
          <button type="button" class="btn btn-outline" data-crop-cancel>Cancelar</button>
          <button type="button" class="btn btn-primary" data-crop-ok>Usar este recorte</button>
        </div>
      </div>`;
    document.body.appendChild(overlay);
    const canvas = overlay.querySelector("canvas");
    const range = overlay.querySelector("input[type=range]");
    const ratio = Math.min(2, window.devicePixelRatio || 1);
    canvas.width = W * ratio; canvas.height = H * ratio;
    const ctx = canvas.getContext("2d");
    ctx.imageSmoothingQuality = "high";
    range.value = String(Math.round(t * 1000));

    function clamp(){
      cx = Math.min(W, Math.max(0, cx));
      cy = Math.min(H, Math.max(0, cy));
    }
    function draw(target, k){
      const s = scaleAt(t);
      target.fillStyle = "#ffffff";
      target.fillRect(0, 0, W * k, H * k);
      target.drawImage(source, (cx - iw * s / 2) * k, (cy - ih * s / 2) * k, iw * s * k, ih * s * k);
    }
    const redraw = () => draw(ctx, ratio);
    redraw();

    let drag = null;
    canvas.addEventListener("pointerdown", (e) => {
      drag = { x: e.clientX, y: e.clientY, cx, cy, k: W / canvas.getBoundingClientRect().width };
      canvas.setPointerCapture(e.pointerId);
    });
    canvas.addEventListener("pointermove", (e) => {
      if (!drag) return;
      cx = drag.cx + (e.clientX - drag.x) * drag.k;
      cy = drag.cy + (e.clientY - drag.y) * drag.k;
      clamp(); redraw();
    });
    canvas.addEventListener("pointerup", () => { drag = null; });
    canvas.addEventListener("pointercancel", () => { drag = null; });
    range.addEventListener("input", () => { t = Number(range.value) / 1000; redraw(); });
    canvas.addEventListener("keydown", (e) => {
      const moves = { ArrowLeft: [-10, 0], ArrowRight: [10, 0], ArrowUp: [0, -10], ArrowDown: [0, 10] };
      if (moves[e.key]){ cx += moves[e.key][0]; cy += moves[e.key][1]; clamp(); redraw(); e.preventDefault(); }
      else if (e.key === "+" || e.key === "-"){
        t = Math.min(1, Math.max(0, t + (e.key === "+" ? 0.05 : -0.05)));
        range.value = String(Math.round(t * 1000)); redraw(); e.preventDefault();
      }
    });
    canvas.focus();

    const result = await new Promise(resolve => {
      overlay.querySelector("[data-crop-cancel]").addEventListener("click", () => resolve(null));
      overlay.addEventListener("keydown", (e) => { if (e.key === "Escape") resolve(null); });
      overlay.querySelector("[data-crop-ok]").addEventListener("click", async (e) => {
        e.target.disabled = true;
        e.target.textContent = "Preparando…";
        try {
          const main = whiteCanvas(CROP.width, CROP.height);
          draw(main.ctx, CROP.width / W);
          const card = whiteCanvas(CROP.cardWidth, CROP.cardHeight);
          draw(card.ctx, CROP.cardWidth / W);
          resolve({
            main: await canvasToJpeg(main.canvas, CROP.quality),
            card: await canvasToJpeg(card.canvas, CROP.quality),
            width: CROP.width, height: CROP.height
          });
        } catch (error) {
          resolve({ error });
        }
      });
    });
    overlay.remove();
    if (result && result.error) throw result.error;
    return result;
  }

  return Object.freeze({
    IMAGES_BUCKET, FILES_BUCKET, MAX_BYTES, KINDS, DOWNLOAD_KINDS, PHOTO_INPUT_TYPES,
    bucketFor, extensionOf, formatFor, acceptFor, publicUrl, cardUrl, sizeText,
    listApproved, listByIds, downloadUrl, uploadFile, uploadPhoto
  });
})();

/* ============================================================
   Punto 44 · temperatura de color y tono de luz (plantilla de Iluminación)
   ------------------------------------------------------------
   products.color_temperature, texto canónico:
     opciones fijas       «2700» o «2700,3000» (hasta 10, sin repetir)
     intervalo regulable  «2700-6500» (de menor a mayor)
   El tono se calcula a partir de los K con los criterios adoptados por
   Mobau (no es una norma oficial): cálida < 3300 K ≤ neutra ≤ 5300 K < fría.
   ============================================================ */
const MobauTonoLuz = (() => {
  const MIN = 1000, MAX = 20000, MAX_OPTIONS = 10;
  const TONES = [
    { id: "calida", label: "Luz cálida", help: "Tono dorado y acogedor", min: -Infinity, max: 3299 },
    { id: "neutra", label: "Luz neutra", help: "Tono equilibrado, entre cálido y frío", min: 3300, max: 5300 },
    { id: "fria",   label: "Luz fría",   help: "Tono blanco y fresco", min: 5301, max: Infinity }
  ];
  const toneOf = (k) => TONES.find(t => k >= t.min && k <= t.max);
  const nf = (k) => String(k);

  /* Valor guardado -> { kind: "fixed", values } | { kind: "range", from, to } | null. */
  function parse(value){
    const s = String(value || "").trim();
    if (!s) return null;
    let m = /^(\d{4,5})-(\d{4,5})$/.exec(s);
    if (m) return { kind: "range", from: Number(m[1]), to: Number(m[2]) };
    if (/^\d{4,5}(,\d{4,5})*$/.test(s)) return { kind: "fixed", values: s.split(",").map(Number) };
    return { kind: "invalid", raw: s };
  }

  /* Opciones fijas escritas por la persona («2700, 3000 K») -> canónico, o error. */
  function fixedFromText(text){
    const parts = String(text || "").replace(/k/gi, " ").split(/[,;/\s]+/).filter(Boolean);
    if (!parts.length) return { value: "" };
    if (parts.some(p => !/^\d{4,5}$/.test(p))) return { error: "Temperatura de color: escribe solo números en K, separados por comas (por ejemplo 2700, 3000)." };
    const values = [...new Set(parts.map(Number))].sort((a, b) => a - b);
    if (values.some(v => v < MIN || v > MAX)) return { error: `Temperatura de color: cada valor debe estar entre ${MIN} y ${MAX} K.` };
    if (values.length > MAX_OPTIONS) return { error: `Temperatura de color: como máximo ${MAX_OPTIONS} opciones fijas.` };
    return { value: values.join(",") };
  }

  /* Intervalo regulable -> canónico, o error (vacío los dos = sin valor). */
  function rangeFromText(fromText, toText){
    const a = String(fromText || "").trim(), b = String(toText || "").trim();
    if (!a && !b) return { value: "" };
    if (!/^\d{4,5}$/.test(a) || !/^\d{4,5}$/.test(b)) return { error: "Temperatura regulable: indica los dos extremos en K (por ejemplo 2700 y 6500)." };
    const from = Number(a), to = Number(b);
    if ([from, to].some(v => v < MIN || v > MAX)) return { error: `Temperatura regulable: los extremos deben estar entre ${MIN} y ${MAX} K.` };
    if (from >= to) return { error: "Temperatura regulable: el primer valor debe ser menor que el segundo." };
    return { value: `${from}-${to}` };
  }

  /* Presentación: líneas { text, help } para la ficha pública. */
  function describe(value){
    const p = parse(value);
    if (!p || p.kind === "invalid") return [];
    if (p.kind === "range"){
      const covered = TONES.filter(t => t.max >= p.from && t.min <= p.to).map(t => t.label.replace("Luz ", ""));
      const list = covered.length > 1 ? `${covered.slice(0, -1).join(", ")} y ${covered.at(-1)}` : covered[0];
      return [{ text: `Temperatura de color regulable · ${nf(p.from)}–${nf(p.to)} K`, help: `Abarca luz ${list}.` }];
    }
    return TONES.map(t => ({ tone: t, values: p.values.filter(v => toneOf(v) === t) }))
      .filter(g => g.values.length)
      .map(g => ({ text: `${g.tone.label} · ${g.values.map(nf).join(" / ")} K`, help: g.tone.help }));
  }

  /* Una sola línea (moderación, «Actual» del formulario). */
  function summary(value){
    const lines = describe(value);
    if (!lines.length) return value ? String(value) : "";
    return lines.map(l => l.text).join(" · ");
  }

  return Object.freeze({ MIN, MAX, MAX_OPTIONS, TONES, parse, fixedFromText, rangeFromText, describe, summary, toneOf });
})();
