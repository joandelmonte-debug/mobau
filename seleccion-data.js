/* ============================================================
   MOBAU — Selección local (MVP)
   ------------------------------------------------------------
   Selección temporal de productos guardada en localStorage del
   navegador. No requiere sesión, no toca Supabase, no sustituye
   el flujo real de proyectos ya construido — es el paso previo:
   catálogo → selección → (más adelante) crear proyecto.

   Clave distinta y sin relación con el carrito anónimo antiguo
   (que persiste en ?carrito= de la URL, nunca en localStorage).
   ============================================================ */

const SELECCION_KEY = "mobau_seleccion";

/* Devuelve el arreglo de IDs en la selección, ya filtrado contra
   el catálogo real cuando PRODUCTS está disponible. */
function getSelection(){
  let ids;
  try {
    const raw = localStorage.getItem(SELECCION_KEY);
    ids = raw ? JSON.parse(raw) : [];
    if (!Array.isArray(ids)) ids = [];
  } catch (e) {
    console.error("Error leyendo la selección:", e);
    ids = [];
  }
  if (typeof PRODUCTS !== "undefined") {
    ids = ids.filter(id => PRODUCTS.some(p => p.id === id));
  }
  return ids;
}

function saveSelection(ids){
  try {
    localStorage.setItem(SELECCION_KEY, JSON.stringify(ids));
    return { success: true };
  } catch (e) {
    console.error("Error guardando la selección:", e);
    return { success: false, error: "No pudimos guardar tu selección en este navegador." };
  }
}

/* Añade un producto real del catálogo a la selección.
   No duplica: si ya estaba, devuelve alreadyExists: true. */
function addToSelection(productId){
  if (typeof PRODUCTS !== "undefined" && !PRODUCTS.some(p => p.id === productId)) {
    return { success: false, error: "Este producto no existe en el catálogo." };
  }
  const ids = getSelection();
  if (ids.includes(productId)) {
    return { success: true, alreadyExists: true };
  }
  ids.push(productId);
  const result = saveSelection(ids);
  return { ...result, alreadyExists: false };
}

function removeFromSelection(productId){
  const ids = getSelection().filter(id => id !== productId);
  return saveSelection(ids);
}

function inSelection(productId){
  return getSelection().includes(productId);
}

function clearSelection(){
  return saveSelection([]);
}

function getSelectionCount(){
  return getSelection().length;
}
