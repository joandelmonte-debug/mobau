/* ============================================================
   MOBAU — Selección local (con cantidades y unidades)
   ------------------------------------------------------------
   Selección temporal de productos. Punto 43: la selección está incluida
   en los planes Individual y Estudio y es de cada cuenta:
     - solo con herramientas profesionales (MobauAccess.access() = "pro");
       sin ellas no se lee, no se muestra y no se puede añadir nada;
     - localStorage "mobau_seleccion:<id de la cuenta>", la cuenta con la
       que se decidió "pro" y que sigue guardada en este navegador
       (MobauAuth.storedUserId()); si no coinciden, no se lee nada;
     - sin selección anónima: sessionStorage ya no se escribe.
   Al cerrar sesión o perder el plan, la clave de la cuenta se conserva
   sin mostrarse (E6). La clave común antigua "mobau_seleccion" de
   localStorage ni se lee, ni se escribe, ni se borra (Q6).
   No toca Supabase directamente, no sustituye el flujo real de
   proyectos ya construido.

   Cada elemento tiene la forma:
     { productId: "p1", quantity: 1, unit: "ud." }
   y, si el producto tiene acabados (punto 44), además finish: "25".
   Una línea por producto y acabado; sin finish es el acabado por defecto
   de un producto sin acabados (finish_code nulo en el proyecto).

   Formato antiguo (solo IDs, ["p1","p3"]) se normaliza de forma
   transparente la primera vez que se lee — sin perder productos,
   conservando quantity/unit si ya existían en el formato nuevo.

   Clave distinta y sin relación con el carrito anónimo antiguo
   (que persiste en ?carrito= de la URL, nunca en localStorage).
   ============================================================ */

const SELECCION_KEY = "mobau_seleccion";
const SELECCION_ACCOUNT_PREFIX = "mobau_seleccion:";
const SELECCION_PLAN_REQUIRED = "La selección está incluida en los planes Individual y Estudio.";

/* Clave de la selección de la cuenta actual, o null si ahora no se puede
   usar (sin plan, acceso aún sin confirmar o sesión distinta de la que se
   comprobó). Solo se lee/escribe esa clave — nunca localStorage.clear(). */
function selectionAccountKey(){
  if (typeof MobauAccess === "undefined" || !MobauAccess.hasProfessionalTools()) return null;
  const userId = MobauAccess.accessUserId;
  if (!userId || typeof MobauAuth === "undefined" || MobauAuth.storedUserId() !== userId) return null;
  return SELECCION_ACCOUNT_PREFIX + userId;
}

/* Punto 41 (D1): PRODUCTS empieza vacío y solo contiene productos que el
   servidor ha confirmado. Un elemento sin unidad (formato antiguo) cuyo
   producto aún no está en PRODUCTS —catálogo sin cargar, fallo de red o
   producto no visible— no se convierte adivinando la unidad: en memoria
   lleva una unidad provisional y en el almacenamiento se conserva tal
   cual (PENDING_RAW guarda el original). Se convierte cuando el producto
   está cargado. */
const PENDING_RAW = Symbol("selectionPendingRaw");

/* Acabado de una línea: código de 1–20 caracteres o null (sin acabado). */
function normalizeFinish(finish){
  if (typeof finish !== "string") return null;
  const code = finish.trim();
  return code && code.length <= 20 ? code : null;
}

/* Punto 46-04: configuración elegida ({choices: [{path, group, options}]},
   elecciones por ruta). Forma normal para comparar líneas: el orden de los
   clics o de las claves no cuenta; null (o {}) = sin configuración. No la
   valida contra el catálogo (lo hace el servidor al guardarla en el
   proyecto) ni descarta nada: no quita repetidos (el servidor los rechaza)
   y, si la forma no es la esperada, la conserva tal cual. */
function normalizeSelectionConfiguration(configuration){
  if (configuration === null || configuration === undefined) return null;
  if (typeof configuration === "object" && !Array.isArray(configuration) && Object.keys(configuration).length === 0) return null;
  const choices = configuration && Array.isArray(configuration.choices) ? configuration.choices : null;
  const valid = choices && choices.every(c => c && typeof c.group === "string" && Array.isArray(c.options)
    && c.options.every(o => typeof o === "string")
    && (c.path === undefined || (Array.isArray(c.path) && c.path.every(s => s && typeof s.group === "string" && typeof s.option === "string"))));
  if (!valid) return configuration;
  if (!choices.length) return null;
  const normalized = choices.map(c => ({
    path: (c.path || []).map(s => ({ group: s.group, option: s.option })),
    group: c.group,
    options: [...c.options].sort()
  }));
  const keyOf = c => JSON.stringify([c.path.map(s => [s.group, s.option]), c.group]);
  normalized.sort((a, b) => (keyOf(a) < keyOf(b) ? -1 : keyOf(a) > keyOf(b) ? 1 : 0));
  return { choices: normalized };
}

/* Clave comparable de una configuración ("" = sin configuración). */
function selectionConfigurationKey(configuration){
  const normalized = normalizeSelectionConfiguration(configuration);
  return normalized ? JSON.stringify(normalized) : "";
}

/* Clave de una línea: producto + acabado + configuración (46-04). */
function selectionLineKey(productId, finish, configuration){
  return productId + "\u0000" + (normalizeFinish(finish) || "") + "\u0000" + selectionConfigurationKey(configuration);
}

/* Normaliza un único elemento, sea del formato antiguo (string) o
   ya del formato nuevo (objeto). Nunca descarta un productId válido;
   conserva quantity/unit existentes en vez de recalcularlos. */
function normalizeSelectionItem(item){
  if (typeof item === "string") {
    const product = (typeof PRODUCTS !== "undefined") ? PRODUCTS.find(p => p.id === item) : null;
    const unit = (typeof getProductUnit === "function") ? getProductUnit(product) : "ud.";
    const normalized = { productId: item, quantity: unit === "ud." ? 1 : 0, unit };
    if (!product) normalized[PENDING_RAW] = item;
    return normalized;
  }
  if (item && typeof item === "object" && item.productId) {
    const product = (typeof PRODUCTS !== "undefined") ? PRODUCTS.find(p => p.id === item.productId) : null;
    const unit = item.unit || ((typeof getProductUnit === "function") ? getProductUnit(product) : "ud.");
    const quantity = (typeof item.quantity === "number" && Number.isFinite(item.quantity))
      ? item.quantity
      : (unit === "ud." ? 1 : 0);
    const normalized = { productId: item.productId, quantity, unit };
    const finish = normalizeFinish(item.finish);
    if (finish) normalized.finish = finish;
    const configuration = normalizeSelectionConfiguration(item.configuration);
    if (configuration) normalized.configuration = configuration;
    if (!item.unit && !product) normalized[PENDING_RAW] = item;
    return normalized;
  }
  return null;
}

/* Forma guardada: los elementos pendientes vuelven a su original. */
function serializeSelection(items){
  return JSON.stringify(items.map(item => (item && item[PENDING_RAW] !== undefined) ? item[PENDING_RAW] : item));
}

/* Normaliza el arreglo completo. Conserva TODAS las líneas (producto +
   acabado), sin duplicar ninguna: nunca se descarta un producto por no estar en
   PRODUCTS (el catálogo puede no haber cargado todavía, o el producto
   estar archivado) — la selección solo se limpia tras completar una
   operación. Los renderers muestran "no disponible" si no lo encuentran. */
function normalizeSelection(raw){
  if (!Array.isArray(raw)) return [];
  const seen = new Set();
  const normalized = [];
  raw.forEach(rawItem => {
    const item = normalizeSelectionItem(rawItem);
    if (!item) return;
    const key = selectionLineKey(item.productId, item.finish, item.configuration);
    if (seen.has(key)) return;
    seen.add(key);
    normalized.push(item);
  });
  return normalized;
}

/* Devuelve la selección ya normalizada — {productId, quantity, unit}
   por cada elemento, o una lista vacía (sin leer nada) si la cuenta no
   puede usar la selección. Si lo guardado era el formato antiguo, lo
   convierte y lo vuelve a guardar (migración transparente); los elementos
   cuyo producto aún no está cargado se guardan sin tocar y se convierten
   en una lectura posterior. */
function getSelection(){
  const key = selectionAccountKey();
  if (!key) return [];
  let stored = null;
  let raw;
  try {
    stored = localStorage.getItem(key);
    raw = JSON.parse(stored || "[]");
  } catch (e) {
    console.error("Error leyendo la selección:", e);
    raw = [];
  }
  const normalized = normalizeSelection(raw);
  if (stored !== null && serializeSelection(normalized) !== stored) saveSelection(normalized);
  return normalized;
}

function saveSelection(items){
  const key = selectionAccountKey();
  if (!key) return { success: false, error: SELECCION_PLAN_REQUIRED };
  try {
    localStorage.setItem(key, serializeSelection(items));
    return { success: true };
  } catch (e) {
    console.error("Error guardando la selección:", e);
    return { success: false, error: "No pudimos guardar tu selección en este navegador." };
  }
}

/* Añade un producto real del catálogo a la selección, con su
   cantidad, unidad y acabado iniciales. No duplica: si ese producto con
   ese acabado ya estaba, devuelve alreadyExists: true sin tocar la
   cantidad que ya tuviera. */
function addToSelection(productId, initialQuantity, initialUnit, finish, configuration){
  /* Punto 38-A: una cuenta de distribuidor (rol confirmado, nunca la pista
     estética) no usa la selección. No borra nada de lo que ya hubiera. */
  if (typeof MobauAccess !== "undefined" && MobauAccess.confirmedKind === "supplier") {
    return { success: false, error: "Las cuentas de distribuidor no usan la selección." };
  }
  if (!selectionAccountKey()) return { success: false, error: SELECCION_PLAN_REQUIRED };
  if (typeof PRODUCTS !== "undefined" && !PRODUCTS.some(p => p.id === productId)) {
    return { success: false, error: "Este producto no existe en el catálogo." };
  }
  if (typeof PRODUCTS !== "undefined" && PRODUCTS.some(p => p.id === productId && p.status === "archived")) {
    return { success: false, error: "Este producto ya no está disponible." };
  }
  const items = getSelection();
  const key = selectionLineKey(productId, finish, configuration);
  if (items.some(item => selectionLineKey(item.productId, item.finish, item.configuration) === key)) {
    return { success: true, alreadyExists: true };
  }
  const product = (typeof PRODUCTS !== "undefined") ? PRODUCTS.find(p => p.id === productId) : null;
  const unit = initialUnit || ((typeof getProductUnit === "function") ? getProductUnit(product) : "ud.");
  const quantity = (typeof initialQuantity === "number" && Number.isFinite(initialQuantity))
    ? initialQuantity
    : (unit === "ud." ? 1 : 0);
  const line = { productId, quantity, unit };
  if (normalizeFinish(finish)) line.finish = normalizeFinish(finish);
  if (normalizeSelectionConfiguration(configuration)) line.configuration = normalizeSelectionConfiguration(configuration);
  items.push(line);
  const result = saveSelection(items);
  return { ...result, alreadyExists: false };
}

function removeFromSelection(productId, finish, configuration){
  const key = selectionLineKey(productId, finish, configuration);
  const items = getSelection().filter(item => selectionLineKey(item.productId, item.finish, item.configuration) !== key);
  return saveSelection(items);
}

function inSelection(productId, finish, configuration){
  const key = selectionLineKey(productId, finish, configuration);
  return getSelection().some(item => selectionLineKey(item.productId, item.finish, item.configuration) === key);
}

/* Actualiza la cantidad de una línea (producto + acabado) de la selección.
   Redondea a 2 decimales (misma precisión que numeric(10,2) en la
   base de datos), nunca permite negativos, y nunca permite bajar de
   1 en productos medidos en "ud." mientras sigan seleccionados. */
function updateSelectionQuantity(productId, quantity, finish, configuration){
  const items = getSelection();
  const key = selectionLineKey(productId, finish, configuration);
  const item = items.find(i => selectionLineKey(i.productId, i.finish, i.configuration) === key);
  if (!item) {
    return { success: false, error: "Este producto ya no está en tu selección." };
  }
  const rounded = Math.round(Number(quantity) * 100) / 100;
  if (!Number.isFinite(rounded) || rounded < 0) {
    return { success: false, error: "La cantidad no es válida." };
  }
  if (item.unit === "ud." && rounded < 1) {
    return { success: false, error: "La cantidad mínima para este producto es 1." };
  }
  item.quantity = rounded;
  return saveSelection(items);
}

function clearSelection(){
  return saveSelection([]);
}

function getSelectionCount(){
  return getSelection().length;
}

/* Al cerrar sesión (SIGNED_OUT, ver supabase-client.js): borra la selección
   anónima antigua de la pestaña, si quedara alguna de antes del Punto 43.
   Solo esta clave concreta de sessionStorage — nunca localStorage ni
   ningún otro dato de la app. */
function clearAnonymousSelection(){
  try {
    sessionStorage.removeItem(SELECCION_KEY);
  } catch (e) {
    console.error("Error limpiando la selección anónima:", e);
  }
}
