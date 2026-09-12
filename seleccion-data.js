/* ============================================================
   MOBAU — Selección local (con cantidades y unidades)
   ------------------------------------------------------------
   Selección temporal de productos. El storage real depende de si hay
   sesión guardada en este navegador (MobauAuth.hasStoredSession(),
   comprobación síncrona definida en supabase-client.js):
     - CON sesión  -> localStorage (comportamiento de siempre: sobrevive
       a cerrar la pestaña o el navegador).
     - SIN sesión  -> sessionStorage (sobrevive a navegar o recargar en
       la misma pestaña, pero desaparece al cerrarla, y nunca reaparece
       en una pestaña o visita nueva sin haber iniciado sesión).
   No toca Supabase directamente, no sustituye el flujo real de
   proyectos ya construido.

   Cada elemento tiene la forma:
     { productId: "p1", quantity: 1, unit: "ud." }

   Formato antiguo (solo IDs, ["p1","p3"]) se normaliza de forma
   transparente la primera vez que se lee — sin perder productos,
   conservando quantity/unit si ya existían en el formato nuevo.

   Clave distinta y sin relación con el carrito anónimo antiguo
   (que persiste en ?carrito= de la URL, nunca en localStorage).
   ============================================================ */

const SELECCION_KEY = "mobau_seleccion";

/* Storage real a usar ahora mismo. Solo se lee/escribe SELECCION_KEY
   dentro de él — nunca localStorage.clear() ni sessionStorage.clear(),
   para no arrastrar ni borrar ningún otro dato de la app (la sesión de
   Supabase incluida, que también vive en localStorage). */
function getSelectionStorage(){
  const hasSession = (typeof MobauAuth !== "undefined" && typeof MobauAuth.hasStoredSession === "function")
    ? MobauAuth.hasStoredSession()
    : false;
  return hasSession ? localStorage : sessionStorage;
}

/* Normaliza un único elemento, sea del formato antiguo (string) o
   ya del formato nuevo (objeto). Nunca descarta un productId válido;
   conserva quantity/unit existentes en vez de recalcularlos. */
function normalizeSelectionItem(item){
  if (typeof item === "string") {
    const product = (typeof PRODUCTS !== "undefined") ? PRODUCTS.find(p => p.id === item) : null;
    const unit = (typeof getProductUnit === "function") ? getProductUnit(product) : "ud.";
    return { productId: item, quantity: unit === "ud." ? 1 : 0, unit };
  }
  if (item && typeof item === "object" && item.productId) {
    const product = (typeof PRODUCTS !== "undefined") ? PRODUCTS.find(p => p.id === item.productId) : null;
    const unit = item.unit || ((typeof getProductUnit === "function") ? getProductUnit(product) : "ud.");
    const quantity = (typeof item.quantity === "number" && Number.isFinite(item.quantity))
      ? item.quantity
      : (unit === "ud." ? 1 : 0);
    return { productId: item.productId, quantity, unit };
  }
  return null;
}

/* Normaliza el arreglo completo. Conserva todos los productId
   válidos (mismo filtro contra el catálogo real que ya existía),
   sin duplicar ninguno. */
function normalizeSelection(raw){
  if (!Array.isArray(raw)) return [];
  const seen = new Set();
  const normalized = [];
  raw.forEach(rawItem => {
    const item = normalizeSelectionItem(rawItem);
    if (!item) return;
    if (typeof PRODUCTS !== "undefined" && !PRODUCTS.some(p => p.id === item.productId)) return;
    if (seen.has(item.productId)) return;
    seen.add(item.productId);
    normalized.push(item);
  });
  return normalized;
}

/* Devuelve la selección ya normalizada — {productId, quantity, unit}
   por cada elemento. Si lo que había en localStorage era el formato
   antiguo, lo convierte y lo vuelve a guardar de inmediato (migración
   transparente, ocurre una sola vez). */
function getSelection(){
  let raw;
  try {
    raw = JSON.parse(getSelectionStorage().getItem(SELECCION_KEY) || "[]");
  } catch (e) {
    console.error("Error leyendo la selección:", e);
    raw = [];
  }
  const normalized = normalizeSelection(raw);
  saveSelection(normalized);
  return normalized;
}

function saveSelection(items){
  try {
    getSelectionStorage().setItem(SELECCION_KEY, JSON.stringify(items));
    return { success: true };
  } catch (e) {
    console.error("Error guardando la selección:", e);
    return { success: false, error: "No pudimos guardar tu selección en este navegador." };
  }
}

/* Añade un producto real del catálogo a la selección, con su
   cantidad y unidad iniciales. No duplica: si ya estaba, devuelve
   alreadyExists: true sin tocar la cantidad que ya tuviera. */
function addToSelection(productId, initialQuantity, initialUnit){
  if (typeof PRODUCTS !== "undefined" && !PRODUCTS.some(p => p.id === productId)) {
    return { success: false, error: "Este producto no existe en el catálogo." };
  }
  const items = getSelection();
  if (items.some(item => item.productId === productId)) {
    return { success: true, alreadyExists: true };
  }
  const product = (typeof PRODUCTS !== "undefined") ? PRODUCTS.find(p => p.id === productId) : null;
  const unit = initialUnit || ((typeof getProductUnit === "function") ? getProductUnit(product) : "ud.");
  const quantity = (typeof initialQuantity === "number" && Number.isFinite(initialQuantity))
    ? initialQuantity
    : (unit === "ud." ? 1 : 0);
  items.push({ productId, quantity, unit });
  const result = saveSelection(items);
  return { ...result, alreadyExists: false };
}

function removeFromSelection(productId){
  const items = getSelection().filter(item => item.productId !== productId);
  return saveSelection(items);
}

function inSelection(productId){
  return getSelection().some(item => item.productId === productId);
}

/* Actualiza la cantidad de un producto ya presente en la selección.
   Redondea a 2 decimales (misma precisión que numeric(10,2) en la
   base de datos), nunca permite negativos, y nunca permite bajar de
   1 en productos medidos en "ud." mientras sigan seleccionados. */
function updateSelectionQuantity(productId, quantity){
  const items = getSelection();
  const item = items.find(i => i.productId === productId);
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

/* Al iniciar sesión (SIGNED_IN/INITIAL_SESSION, ver supabase-client.js):
   une la selección anónima (sessionStorage) a la de la cuenta
   (localStorage). Nunca duplica productId ni sobrescribe una cantidad
   que la cuenta ya tuviera guardada — un producto que ya estaba ahí se
   deja tal cual, solo se añaden los que faltaban. */
function migrateAnonymousSelectionToAccount(){
  let anonymousRaw;
  try {
    anonymousRaw = JSON.parse(sessionStorage.getItem(SELECCION_KEY) || "[]");
  } catch (e) {
    anonymousRaw = [];
  }
  const anonymousItems = normalizeSelection(anonymousRaw);
  if (!anonymousItems.length) return { migratedCount: 0 };

  let accountRaw;
  try {
    accountRaw = JSON.parse(localStorage.getItem(SELECCION_KEY) || "[]");
  } catch (e) {
    accountRaw = [];
  }
  const accountItems = normalizeSelection(accountRaw);
  const accountIds = new Set(accountItems.map(item => item.productId));

  let migratedCount = 0;
  anonymousItems.forEach(item => {
    if (accountIds.has(item.productId)) return; // ya está en la cuenta: no se sobrescribe ni se duplica
    accountItems.push(item);
    accountIds.add(item.productId);
    migratedCount++;
  });

  try {
    localStorage.setItem(SELECCION_KEY, JSON.stringify(accountItems));
    sessionStorage.removeItem(SELECCION_KEY);
  } catch (e) {
    console.error("Error migrando la selección anónima a la cuenta:", e);
  }
  return { migratedCount };
}

/* Al cerrar sesión (SIGNED_OUT, ver supabase-client.js): la selección
   temporal del usuario, ya anónimo de nuevo, debe quedar vacía. Solo
   borra esta clave concreta de sessionStorage — nunca localStorage ni
   ningún otro dato de la app. */
function clearAnonymousSelection(){
  try {
    sessionStorage.removeItem(SELECCION_KEY);
  } catch (e) {
    console.error("Error limpiando la selección anónima:", e);
  }
}
