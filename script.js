/* ============================================================
   MOBAU — datos y comportamiento compartido
   Catálogo multi-categoría — piloto en validación
   ============================================================ */

/* ---------- distribuidores / showrooms (NO son "marcas") ---------- */
const DISTRIBUTORS = {
  "spectro": {
    nombre: "Spectro Lighting",
    ubicacion: "Santo Domingo · Punta Cana",
    categorias: ["Iluminación"],
    descripcion: "Distribuidor de marcas internacionales de iluminación arquitectónica y decorativa, con showroom y stock local para proyectos residenciales y comerciales."
  },
  "altritempi": {
    nombre: "Altri Tempi",
    ubicacion: "Santo Domingo",
    categorias: ["Mobiliario", "Accesorios decorativos"],
    descripcion: "Showroom de mobiliario y objetos contemporáneos para proyectos residenciales, hotelería y espacios corporativos de alta gama."
  },
  "charo": {
    nombre: "Charo",
    ubicacion: "Santo Domingo · Santiago",
    categorias: ["Mobiliario"],
    descripcion: "Distribuidor de mobiliario de oficina y piezas de autor para proyectos corporativos, con capacidad de fabricación a medida."
  },
  "casalua": {
    nombre: "Casa Lúa",
    ubicacion: "Punta Cana · La Romana",
    categorias: ["Mobiliario", "Accesorios decorativos"],
    descripcion: "Showroom especializado en mobiliario y objetos para exteriores, terrazas y proyectos hospitality frente al mar."
  },
  "terraceramica": {
    nombre: "Terra Cerámica",
    ubicacion: "Santo Domingo",
    categorias: ["Revestimientos"],
    descripcion: "Distribuidor de pisos, porcelanatos y acabados para proyectos residenciales y comerciales."
  },
  "baccara": {
    nombre: "Baccara Baño",
    ubicacion: "Santiago",
    categorias: ["Baño"],
    descripcion: "Showroom especializado en sanitarios, griferías y accesorios de baño para proyectos residenciales y hospitality."
  },
  "fontanacocina": {
    nombre: "Fontana Cocina",
    ubicacion: "Santo Domingo",
    categorias: ["Cocina"],
    descripcion: "Distribuidor de griferías, fregaderos y accesorios de cocina para proyectos residenciales y comerciales."
  }
};

/* ---------- categorías del piloto, con subcategorías ---------- */
const CATEGORIES = {
  "iluminacion": {
    nombre: "Iluminación",
    subcategorias: ["Decorativa", "Arquitectónica", "Empotrada", "De superficie", "Exterior", "Rieles y perfiles"]
  },
  "mobiliario": {
    nombre: "Mobiliario",
    subcategorias: ["Residencial", "Oficina", "Hospitality", "Comercial", "Exterior"]
  },
  "revestimientos": {
    nombre: "Revestimientos",
    subcategorias: ["Pisos", "Paredes", "Cerámica", "Porcelanato", "Piedra", "Acabados"]
  },
  "bano": {
    nombre: "Baño",
    subcategorias: ["Sanitarios", "Griferías", "Duchas", "Accesorios"]
  },
  "cocina": {
    nombre: "Cocina",
    subcategorias: ["Griferías", "Fregaderos", "Accesorios", "Complementarios"]
  },
  "accesorios-decorativos": {
    nombre: "Accesorios decorativos",
    subcategorias: ["Alfombras", "Espejos", "Papel tapiz", "Objetos", "Decoración"]
  }
};

/* ---------- productos ---------- */
const PRODUCTS = [
  {
    id: "p1", nombre: "Lámpara de Piso Meridian", distribuidor: "spectro", marca: "marset",
    categoria: "iluminacion", subcategoria: "Decorativa", uso: "residencial", espacio: "sala",
    disponibilidad: "en-stock", icon: "lampFloor",
    descripcion: "Lámpara de piso con base de latón cepillado y difusor de vidrio soplado a mano. Luz cálida indirecta, pensada para salas y suites.",
    medidas: "H 162 cm · Base ⌀ 32 cm",
    materiales: "Latón cepillado, vidrio soplado",
    acabados: "Latón natural, Negro grafito",
    leadtime: "4–6 semanas · stock parcial en showroom"
  },
  {
    id: "p2", nombre: "Plafón Orbital LED", distribuidor: "spectro", marca: "leds-c4",
    categoria: "iluminacion", subcategoria: "Empotrada", uso: "comercial", espacio: "areas-comunes",
    disponibilidad: "en-stock", icon: "lampCeiling",
    descripcion: "Plafón LED de perfil bajo con difusor opal, temperatura de color ajustable. Ideal para lobbies, oficinas y áreas comunes.",
    medidas: "⌀ 60 cm · H 8 cm",
    materiales: "Aluminio anodizado, difusor opal",
    acabados: "Blanco mate, Bronce",
    leadtime: "Disponible en stock"
  },
  {
    id: "p3", nombre: "Spot Arquitectónico Track 24", distribuidor: "spectro", marca: "delta-light",
    categoria: "iluminacion", subcategoria: "Rieles y perfiles", uso: "comercial", espacio: "retail",
    disponibilidad: "bajo-pedido", icon: "spot",
    descripcion: "Spot direccional para riel trifásico, óptica intercambiable de 15°/24°/38°. Uso en retail, galerías y fachadas interiores.",
    medidas: "L 12 × 6 cm",
    materiales: "Aluminio fundido a presión",
    acabados: "Negro texturizado, Blanco",
    leadtime: "6–8 semanas · importación directa"
  },
  {
    id: "p8", nombre: "Farol de Piso Bahía", distribuidor: "spectro", marca: "leds-c4",
    categoria: "iluminacion", subcategoria: "Exterior", uso: "hospitality", espacio: "exterior",
    disponibilidad: "en-stock", icon: "wallLamp",
    descripcion: "Farol de piso IP65 para terrazas y jardines, difusor resistente a UV. Instalación autónoma o cableada.",
    medidas: "H 95 cm · Base ⌀ 24 cm",
    materiales: "Aluminio marino, policarbonato UV",
    acabados: "Negro grafito, Arena",
    leadtime: "3–4 semanas"
  },
  {
    id: "p12", nombre: "Aplique de Pared Vela", distribuidor: "spectro", marca: "marset",
    categoria: "iluminacion", subcategoria: "De superficie", uso: "residencial", espacio: "dormitorio",
    disponibilidad: "por-confirmar", icon: "wallLamp",
    descripcion: "Aplique de pared de perfil delgado con difusor cilíndrico soplado, luz cálida ascendente/descendente.",
    medidas: "H 28 cm · Proyección 14 cm",
    materiales: "Latón, vidrio soplado",
    acabados: "Latón envejecido",
    leadtime: "Por confirmar con distribuidor"
  },
  {
    id: "p4", nombre: "Sofá Modular Batisti", distribuidor: "altritempi", marca: "norden-studio",
    categoria: "mobiliario", subcategoria: "Residencial", uso: "residencial", espacio: "sala",
    disponibilidad: "en-stock", icon: "sofa",
    descripcion: "Sistema modular tapizado, estructura interna de roble macizo y espuma de alta densidad. Configurable en L o lineal.",
    medidas: "240 × 95 × 78 cm (módulo base)",
    materiales: "Estructura de roble, tapizado en lino",
    acabados: "Crudo, Gris piedra, Terracota",
    leadtime: "8–10 semanas · importación"
  },
  {
    id: "p6", nombre: "Mesa de Centro Dune", distribuidor: "altritempi", marca: "norden-studio",
    categoria: "mobiliario", subcategoria: "Residencial", uso: "residencial", espacio: "sala",
    disponibilidad: "en-stock", icon: "table",
    descripcion: "Mesa de centro de líneas orgánicas en piedra reconstituida, superficie pulida. Pieza de bajo perfil para salas contemporáneas.",
    medidas: "110 × 60 × 32 cm",
    materiales: "Piedra reconstituida",
    acabados: "Arena, Gris carbón",
    leadtime: "5–7 semanas"
  },
  {
    id: "p10", nombre: "Silla Lounge Cairo", distribuidor: "altritempi", marca: "norden-studio",
    categoria: "mobiliario", subcategoria: "Hospitality", uso: "hospitality", espacio: "areas-comunes",
    disponibilidad: "por-confirmar", icon: "chair",
    descripcion: "Silla lounge de líneas clásicas revisitadas, estructura en madera curvada y tapizado en boucle. Pieza de acento para lobbies.",
    medidas: "72 × 70 × 80 cm",
    materiales: "Madera curvada, boucle",
    acabados: "Roble claro / Crudo",
    leadtime: "Por confirmar con distribuidor"
  },
  {
    id: "p11", nombre: "Mesa Comedor Roble Nórdico", distribuidor: "altritempi", marca: "norden-studio",
    categoria: "mobiliario", subcategoria: "Residencial", uso: "residencial", espacio: "comedor",
    disponibilidad: "en-stock", icon: "table",
    descripcion: "Mesa de comedor en roble macizo con acabado natural, canto redondeado y base en A. Disponible en tres largos.",
    medidas: "220 × 95 × 75 cm",
    materiales: "Roble macizo",
    acabados: "Natural, Humo",
    leadtime: "6–7 semanas"
  },
  {
    id: "p5", nombre: "Silla Executive Contour", distribuidor: "charo", marca: "vero-contract",
    categoria: "mobiliario", subcategoria: "Oficina", uso: "oficina", espacio: "oficina",
    disponibilidad: "en-stock", icon: "chair",
    descripcion: "Silla ejecutiva con respaldo ergonómico ajustable y malla transpirable. Certificación de carga para uso intensivo.",
    medidas: "68 × 66 × 118 cm",
    materiales: "Malla técnica, aluminio pulido",
    acabados: "Negro, Gris grafito",
    leadtime: "2–3 semanas"
  },
  {
    id: "p9", nombre: "Escritorio Directorio Line", distribuidor: "charo", marca: "vero-contract",
    categoria: "mobiliario", subcategoria: "Oficina", uso: "oficina", espacio: "oficina",
    disponibilidad: "bajo-pedido", icon: "desk",
    descripcion: "Escritorio ejecutivo con superficie en chapa de nogal y estructura metálica integrada, incluye pasacables oculto.",
    medidas: "180 × 80 × 75 cm",
    materiales: "Chapa de nogal, acero pintado",
    acabados: "Nogal natural, Negro mate",
    leadtime: "5–6 semanas"
  },
  {
    id: "p7", nombre: "Butaca Exterior Palma", distribuidor: "casalua", marca: "palma-outdoor",
    categoria: "mobiliario", subcategoria: "Exterior", uso: "hospitality", espacio: "exterior",
    disponibilidad: "bajo-pedido", icon: "outdoorChair",
    descripcion: "Butaca de exterior en fibra sintética tejida sobre estructura de aluminio marino, resistente a sal y humedad constante.",
    medidas: "78 × 82 × 74 cm",
    materiales: "Fibra sintética, aluminio marino",
    acabados: "Natural, Grafito",
    leadtime: "6–9 semanas · importación"
  },
  {
    id: "p15", nombre: "Porcelanato Piedra Natural 60×60", distribuidor: "terraceramica", marca: "terra-ceramica",
    categoria: "revestimientos", subcategoria: "Porcelanato", uso: "residencial", espacio: "sala",
    disponibilidad: "en-stock", icon: "tile",
    descripcion: "Porcelanato rectificado con acabado mate, textura inspirada en piedra natural. Para pisos y paredes de alto tránsito.",
    medidas: "60 × 60 cm · esp. 9.5 mm",
    materiales: "Porcelanato rectificado",
    acabados: "Gris niebla, Arena, Blanco roto",
    leadtime: "Disponible en stock"
  },
  {
    id: "p16", nombre: "Piso de Madera Técnica Roble", distribuidor: "terraceramica", marca: "terra-ceramica",
    categoria: "revestimientos", subcategoria: "Pisos", uso: "residencial", espacio: "sala",
    disponibilidad: "bajo-pedido", icon: "tile",
    descripcion: "Piso laminado de alta resistencia con textura de roble natural, instalación flotante. Apto para uso residencial intensivo.",
    medidas: "120 × 19 cm · esp. 8 mm",
    materiales: "HDF laminado, capa de desgaste AC4",
    acabados: "Roble claro, Roble humo",
    leadtime: "3–5 semanas"
  },
  {
    id: "p17", nombre: "Grifería Monomando Line", distribuidor: "baccara", marca: "baccara",
    categoria: "bano", subcategoria: "Griferías", uso: "residencial", espacio: "bano",
    disponibilidad: "en-stock", icon: "faucet",
    descripcion: "Grifería monomando de perfil delgado para lavamanos, cartucho cerámico de larga duración.",
    medidas: "H 18 cm",
    materiales: "Latón cromado",
    acabados: "Cromo, Negro mate",
    leadtime: "Disponible en stock"
  },
  {
    id: "p18", nombre: "Sanitario Suspendido Compact", distribuidor: "baccara", marca: "baccara",
    categoria: "bano", subcategoria: "Sanitarios", uso: "residencial", espacio: "bano",
    disponibilidad: "por-confirmar", icon: "bath",
    descripcion: "Sanitario suspendido de diseño compacto, doble descarga, con tanque empotrable.",
    medidas: "36 × 53 × 34 cm",
    materiales: "Cerámica sanitaria vitrificada",
    acabados: "Blanco brillante",
    leadtime: "Por confirmar con distribuidor"
  },
  {
    id: "p19", nombre: "Fregadero Bajo Encimera Doble", distribuidor: "fontanacocina", marca: "fontana",
    categoria: "cocina", subcategoria: "Fregaderos", uso: "residencial", espacio: "cocina",
    disponibilidad: "bajo-pedido", icon: "faucet",
    descripcion: "Fregadero de dos tinas para instalación bajo encimera, en acero inoxidable calibre 18.",
    medidas: "86 × 46 × 20 cm",
    materiales: "Acero inoxidable",
    acabados: "Satinado",
    leadtime: "4–6 semanas"
  },
  {
    id: "p20", nombre: "Grifería de Cocina Extraíble", distribuidor: "fontanacocina", marca: "fontana",
    categoria: "cocina", subcategoria: "Griferías", uso: "residencial", espacio: "cocina",
    disponibilidad: "en-stock", icon: "faucet",
    descripcion: "Grifería de cocina con regadera extraíble y dos modos de salida de agua.",
    medidas: "H 42 cm",
    materiales: "Latón cromado",
    acabados: "Cromo, Negro mate, Acero",
    leadtime: "Disponible en stock"
  },
  {
    id: "p13", nombre: "Espejo de Piso Arco", distribuidor: "altritempi", marca: "norden-studio",
    categoria: "accesorios-decorativos", subcategoria: "Espejos", uso: "residencial", espacio: "dormitorio",
    disponibilidad: "en-stock", icon: "decor",
    descripcion: "Espejo de piso con marco delgado en acero y base curva autoportante. Remata suites, vestidores y recibidores.",
    medidas: "H 170 cm · An 60 cm",
    materiales: "Acero pintado, cristal",
    acabados: "Negro mate, Latón",
    leadtime: "3–5 semanas"
  },
  {
    id: "p14", nombre: "Set de Cerámica Decorativa Bahía", distribuidor: "casalua", marca: "palma-outdoor",
    categoria: "accesorios-decorativos", subcategoria: "Objetos", uso: "hospitality", espacio: "areas-comunes",
    disponibilidad: "bajo-pedido", icon: "decor",
    descripcion: "Set de tres piezas de cerámica esmaltada para mesas, consolas y áreas comunes. Resistente a exteriores cubiertos.",
    medidas: "H 18–34 cm (set de 3)",
    materiales: "Cerámica esmaltada",
    acabados: "Arena, Terracota, Blanco roto",
    leadtime: "6–8 semanas · importación"
  }
];

const LABELS = {
  categoria: {
    "iluminacion": "Iluminación",
    "mobiliario": "Mobiliario",
    "revestimientos": "Revestimientos",
    "bano": "Baño",
    "cocina": "Cocina",
    "accesorios-decorativos": "Accesorios decorativos"
  },
  marca: {
    "delta-light": "Delta Light",
    "marset": "Marset",
    "leds-c4": "Leds-C4",
    "norden-studio": "Norden Studio",
    "vero-contract": "Vero Contract",
    "palma-outdoor": "Palma Outdoor",
    "terra-ceramica": "Terra Cerámica",
    "baccara": "Baccara",
    "fontana": "Fontana"
  },
  uso: {
    "residencial": "Residencial", "comercial": "Comercial",
    "hospitality": "Hospitality", "oficina": "Oficina"
  },
  espacio: {
    "sala": "Sala", "comedor": "Comedor", "dormitorio": "Dormitorio",
    "cocina": "Cocina", "bano": "Baño", "exterior": "Exterior",
    "oficina": "Oficina", "areas-comunes": "Áreas comunes", "retail": "Retail / comercial"
  },
  disponibilidad: {
    "en-stock": "En stock habitual",
    "bajo-pedido": "Bajo pedido",
    "por-confirmar": "Por confirmar"
  }
};

/* ---------- archivos descargables por producto (simulado) ---------- */
const DOWNLOADS = [
  { label: "BIM", ext: ".rfa · .ifc" },
  { label: "CAD", ext: ".dwg · .dxf" },
  { label: "Modelo 3D", ext: ".3ds · .obj · .skp" },
  { label: "Ficha técnica", ext: ".pdf" },
  { label: "Fotos y renders", ext: ".jpg · .png" }
];

/* ---------- sprite de íconos de línea (placeholders, sin fotografía) ---------- */
const ICON_SPRITE = `
<svg xmlns="http://www.w3.org/2000/svg" style="display:none">
  <symbol id="ic-lampFloor" viewBox="0 0 48 64" fill="none" stroke="currentColor" stroke-width="1.5">
    <path d="M15 9h18l5 13H10z"/><line x1="24" y1="22" x2="24" y2="54"/><line x1="12" y1="58" x2="36" y2="58"/>
  </symbol>
  <symbol id="ic-lampCeiling" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5">
    <line x1="17" y1="5" x2="31" y2="5"/><line x1="24" y1="5" x2="24" y2="17"/>
    <path d="M12 17q12-9 24 0l-2 12q-10 6-20 0z"/>
  </symbol>
  <symbol id="ic-spot" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5">
    <circle cx="8" cy="12" r="3"/><line x1="11" y1="12" x2="22" y2="12"/>
    <rect x="22" y="6" width="18" height="12" rx="2"/>
    <line x1="40" y1="9" x2="46" y2="6"/><line x1="40" y1="15" x2="46" y2="18"/>
  </symbol>
  <symbol id="ic-wallLamp" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5">
    <line x1="6" y1="6" x2="6" y2="42"/><path d="M6 16h12"/><circle cx="26" cy="16" r="9"/>
  </symbol>
  <symbol id="ic-sofa" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5">
    <path d="M8 22v10a3 3 0 003 3h26a3 3 0 003-3V22"/>
    <path d="M8 22v-4a3 3 0 013-3h2a3 3 0 013 3v4"/>
    <path d="M32 22v-4a3 3 0 013-3h2a3 3 0 013 3v4"/>
    <line x1="12" y1="35" x2="12" y2="40"/><line x1="36" y1="35" x2="36" y2="40"/>
  </symbol>
  <symbol id="ic-chair" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5">
    <path d="M14 8h20v18H14z"/><path d="M14 26l-4 16"/><path d="M34 26l4 16"/>
    <line x1="16" y1="26" x2="14" y2="42"/><line x1="32" y1="26" x2="34" y2="42"/>
  </symbol>
  <symbol id="ic-table" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5">
    <rect x="6" y="12" width="36" height="6" rx="1"/>
    <line x1="10" y1="18" x2="10" y2="40"/><line x1="38" y1="18" x2="38" y2="40"/>
  </symbol>
  <symbol id="ic-desk" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5">
    <rect x="5" y="14" width="38" height="5" rx="1"/>
    <line x1="9" y1="19" x2="9" y2="40"/><line x1="39" y1="19" x2="39" y2="40"/>
    <rect x="28" y="19" width="11" height="10"/>
  </symbol>
  <symbol id="ic-outdoorChair" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5">
    <path d="M14 8h20v6H14z"/><path d="M14 17h20v9H14z"/>
    <line x1="18" y1="10" x2="18" y2="14"/><line x1="24" y1="10" x2="24" y2="14"/><line x1="30" y1="10" x2="30" y2="14"/>
    <line x1="16" y1="26" x2="14" y2="42"/><line x1="32" y1="26" x2="34" y2="42"/>
  </symbol>
  <symbol id="ic-decor" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5">
    <path d="M18 14h12l-3 20h-6z"/><ellipse cx="24" cy="12" rx="7" ry="3"/><ellipse cx="24" cy="35" rx="9" ry="3"/>
  </symbol>
  <symbol id="ic-tile" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5">
    <rect x="6" y="6" width="15" height="15" rx="1"/><rect x="27" y="6" width="15" height="15" rx="1"/>
    <rect x="6" y="27" width="15" height="15" rx="1"/><rect x="27" y="27" width="15" height="15" rx="1"/>
  </symbol>
  <symbol id="ic-bath" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5">
    <path d="M6 26h36"/><path d="M8 26v6a6 6 0 006 6h20a6 6 0 006-6v-6"/>
    <path d="M10 26v-8a5 5 0 015-5h2"/><circle cx="15" cy="16" r="1.1" fill="currentColor" stroke="none"/>
  </symbol>
  <symbol id="ic-faucet" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5">
    <path d="M14 34V22a5 5 0 015-5h6"/><path d="M25 17h9a4 4 0 014 4v3"/>
    <line x1="38" y1="24" x2="38" y2="30"/><line x1="14" y1="34" x2="14" y2="40"/><line x1="8" y1="40" x2="20" y2="40"/>
  </symbol>
  <symbol id="ic-user" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="1.5">
    <circle cx="24" cy="16" r="8"/><path d="M8 40c2-10 10-15 16-15s14 5 16 15"/>
  </symbol>
</svg>`;

function injectIconSprite(){
  if(document.getElementById("mobau-icon-sprite")) return;
  const div = document.createElement("div");
  div.id = "mobau-icon-sprite";
  div.innerHTML = ICON_SPRITE;
  document.body.prepend(div);
}

function iconMarkup(key, size){
  return `<svg width="${size||48}" height="${size||48}"><use href="#ic-${key}"></use></svg>`;
}

function badgeClass(disp){
  if(disp === "en-stock") return "b-stock";
  if(disp === "bajo-pedido") return "b-bajo-pedido";
  return "b-confirmar";
}

/* ============================================================
   PROYECTO (carrito) — persistido en la URL, sin localStorage
   ============================================================ */
function getCart(){
  const params = new URLSearchParams(window.location.search);
  const raw = params.get("carrito");
  if(!raw) return [];
  return raw.split(",").filter(Boolean).map(pair => {
    const [id, qty] = pair.split(":");
    return { id, qty: Math.max(1, parseInt(qty || "1", 10) || 1) };
  }).filter(item => PRODUCTS.some(p => p.id === item.id));
}

function cartParamString(cart){
  return cart.map(i => `${i.id}:${i.qty}`).join(",");
}

function setCartInURL(cart){
  const url = new URL(window.location.href);
  if(cart.length){
    url.searchParams.set("carrito", cartParamString(cart));
  } else {
    url.searchParams.delete("carrito");
  }
  window.history.replaceState({}, "", url.toString());
}

function inCart(id){
  return getCart().some(i => i.id === id);
}

function addToCart(id, qty){
  const cart = getCart();
  const existing = cart.find(i => i.id === id);
  if(existing) existing.qty += (qty || 1);
  else cart.push({ id, qty: qty || 1 });
  setCartInURL(cart);
  return cart;
}

function removeFromCart(id){
  const cart = getCart().filter(i => i.id !== id);
  setCartInURL(cart);
  return cart;
}

function updateCartQty(id, qty){
  const cart = getCart();
  const item = cart.find(i => i.id === id);
  if(item) item.qty = Math.max(1, qty || 1);
  setCartInURL(cart);
  return cart;
}

function cartUnitCount(){
  return getCart().reduce((sum, i) => sum + i.qty, 0);
}

/* distribuidores presentes en el carrito actual, en orden de aparición */
function cartDistributors(){
  const cart = getCart();
  const seen = [];
  cart.forEach(item => {
    const p = PRODUCTS.find(pp => pp.id === item.id);
    if(p && !seen.includes(p.distribuidor)) seen.push(p.distribuidor);
  });
  return seen;
}

function updateCartBadge(){
  const el = document.getElementById("cart-count");
  const link = document.getElementById("cart-link");
  if(!el) return;
  const n = cartUnitCount();
  el.textContent = n > 0 ? `Proyecto (${n})` : "Proyecto";
  if(link) link.classList.toggle("has-items", n > 0);
}

function withCartHref(href, cart){
  if(!href || /^https?:|^mailto:|^tel:|^#/.test(href)) return href;
  const [path, query = ""] = href.split("?");
  const p = new URLSearchParams(query);
  if(cart.length) p.set("carrito", cartParamString(cart));
  else p.delete("carrito");
  const qs = p.toString();
  return qs ? `${path}?${qs}` : path;
}

function propagateCartLinks(){
  const cart = getCart();
  document.querySelectorAll("a[href]").forEach(a => {
    const href = a.getAttribute("href");
    if(!href || /^https?:|^mailto:|^tel:|^#$/.test(href)) return;
    a.setAttribute("href", withCartHref(href, cart));
  });
}

/* ---------- toast ---------- */
let toastTimer = null;
function showToast(message){
  let el = document.getElementById("mobau-toast");
  if(!el){
    el = document.createElement("div");
    el.id = "mobau-toast";
    el.className = "toast";
    document.body.appendChild(el);
  }
  el.textContent = message;
  el.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove("show"), 2400);
}

/* ---------- búsqueda: nombre, categoría, marca y descripción ----------
   Punto 15. El catálogo (PRODUCTS, arriba en este mismo archivo) es un
   array estático de 20 productos incrustado en el JS de la página —
   no existe tabla "products" en Supabase, ni RPC, ni índices, así que
   no hay SQL que asegurar ni unaccent/pg_trgm que instalar: la
   tolerancia a acentos/mayúsculas/erratas se resuelve aquí, en JS,
   sobre el array ya cargado (no hay otra fuente de datos posible con
   esta arquitectura). searchProducts() es el único punto de entrada;
   catalogo.html no vuelve a tocar el texto de la búsqueda. */

function normalizeSearchText(str){
  return (str || "")
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "") // quita acentos
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

function searchTokens(str){
  return normalizeSearchText(str).split(/[^a-z0-9]+/).filter(Boolean);
}

/* Similitud aproximada por bigramas (coeficiente de Dice) — el
   equivalente que se puede calcular en JS sin pg_trgm (que aquí no
   aplica: no hay tabla que consultar). Solo se usa como último
   recurso para erratas pequeñas, nunca como primer criterio, y con
   umbral: por debajo de FUZZY_SIMILARITY_THRESHOLD no cuenta como
   coincidencia. */
function bigramSet(str){
  const set = new Map();
  for (let i = 0; i < str.length - 1; i++){
    const bg = str.slice(i, i + 2);
    set.set(bg, (set.get(bg) || 0) + 1);
  }
  return set;
}
function bigramSimilarity(a, b){
  if (!a || !b) return 0;
  if (a === b) return 1;
  const ba = bigramSet(a), bb = bigramSet(b);
  if (ba.size === 0 || bb.size === 0) return 0;
  let common = 0;
  ba.forEach((count, bg) => { if (bb.has(bg)) common += Math.min(count, bb.get(bg)); });
  let totalA = 0, totalB = 0;
  ba.forEach(v => totalA += v);
  bb.forEach(v => totalB += v);
  return (2 * common) / (totalA + totalB);
}
const FUZZY_SIMILARITY_THRESHOLD = 0.35;

/* Un producto es "relevante" si TODAS las palabras de la consulta
   aparecen (como substring, en cualquier orden) en el campo — nunca
   basta con que aparezca una sola palabra de varias. El score decide
   el orden de prioridad pedido: nombre exacto > nombre por prefijo >
   todas las palabras en el nombre > categoría > marca > descripción >
   (distribuido entre varios campos, sin concentrarse en ninguno). */
function scoreProductBySubstring(product, queryWords, normalizedQuery){
  const nombre = normalizeSearchText(product.nombre);
  const categoria = normalizeSearchText(LABELS.categoria[product.categoria] || "");
  const marca = normalizeSearchText(LABELS.marca[product.marca] || "");
  const descripcion = normalizeSearchText(product.descripcion || "");
  const allWordsIn = (text) => queryWords.every(w => text.includes(w));

  if (normalizedQuery && nombre === normalizedQuery) return 100;
  if (normalizedQuery && nombre.startsWith(normalizedQuery)) return 90;
  if (allWordsIn(nombre)) return 80;
  if (allWordsIn(categoria)) return 70;
  if (allWordsIn(marca)) return 60;
  if (allWordsIn(descripcion)) return 50;
  if (allWordsIn(`${nombre} ${categoria} ${marca} ${descripcion}`)) return 40;
  return null; // ninguna palabra encaja de forma literal
}

/* Fallback aproximado — solo se prueba cuando NINGÚN producto pasó
   scoreProductBySubstring() para toda la consulta. Cada palabra de la
   búsqueda debe tener al menos una palabra del nombre del producto
   por encima del umbral de similitud; si una palabra no encuentra
   ninguna coincidencia razonable, el producto se descarta entero (no
   se muestran productos sin relación solo porque una palabra sí
   aproxima). */
function fuzzyScoreProduct(product, queryWords){
  const nombreTokens = searchTokens(product.nombre);
  if (!nombreTokens.length) return null;
  let totalSim = 0;
  const matchedTokens = [];
  for (const w of queryWords){
    let best = 0, bestTok = null;
    for (const tok of nombreTokens){
      const sim = bigramSimilarity(w, tok);
      if (sim > best){ best = sim; bestTok = tok; }
    }
    if (best < FUZZY_SIMILARITY_THRESHOLD) return null;
    totalSim += best;
    matchedTokens.push(bestTok);
  }
  const avgSim = totalSim / queryWords.length;
  return { score: 10 + avgSim * 20, matchedTerm: matchedTokens.join(" ") };
}

/* Punto de entrada único. Devuelve:
   - results: productos relevantes, cada uno con "_score" (mayor =
     más relevante) añadido para que sortList() pueda usarlo cuando
     el orden elegido sea "relevancia".
   - fuzzyTerm: solo viene relleno si se usó el fallback aproximado
     (para mostrar "Resultados similares a: ..."), null en cualquier
     otro caso. Nunca modifica el texto que escribió el usuario.
   Consultas de menos de 2 caracteres no filtran nada — se tratan
   igual que una búsqueda vacía. */
function searchProducts(products, rawQuery){
  const normalizedQuery = normalizeSearchText(rawQuery);
  if (normalizedQuery.length < 2){
    return { results: products.map(p => Object.assign({ _score: 0 }, p)), fuzzyTerm: null };
  }

  const queryWords = searchTokens(rawQuery);
  const scored = [];
  products.forEach(product => {
    const score = scoreProductBySubstring(product, queryWords, normalizedQuery);
    if (score !== null) scored.push(Object.assign({ _score: score }, product));
  });
  if (scored.length) return { results: scored, fuzzyTerm: null };

  /* Sin ninguna coincidencia literal: único momento en que se intenta
     la similitud aproximada, y solo por encima del umbral. */
  const fuzzy = [];
  let fuzzyTerm = null;
  products.forEach(product => {
    const match = fuzzyScoreProduct(product, queryWords);
    if (match){
      fuzzy.push(Object.assign({ _score: match.score }, product));
      if (!fuzzyTerm) fuzzyTerm = match.matchedTerm;
    }
  });
  return { results: fuzzy, fuzzyTerm: fuzzy.length ? fuzzyTerm : null };
}

/* ---------- unidades de medida (Bloque cantidades) ---------- */

/* Única fuente de verdad para determinar la unidad de un producto.
   Prioridad: 1) campo explícito del producto (measurement_unit, si
   algún día existe en el catálogo) 2) mapa por categoría 3) "ud."
   por defecto, documentado. No repetir esta lógica en ningún otro
   archivo — todo debe llamar a esta función. */
const CATEGORY_UNITS = {
  iluminacion: "ud.",
  mobiliario: "ud.",
  revestimientos: "m²",
  bano: "ud.",
  cocina: "ud.",
  "accesorios-decorativos": "ud."
};

function getProductUnit(product){
  if (product && product.measurement_unit) return product.measurement_unit;
  if (product && CATEGORY_UNITS[product.categoria]) return CATEGORY_UNITS[product.categoria];
  return "ud.";
}

/* Única fuente de verdad para "¿esta cantidad es cotizable?".
   Cubre 0, null, undefined, "", NaN y negativos con una sola condición. */
function isValidQuantity(q){
  return Number.isFinite(Number(q)) && Number(q) > 0;
}

/* ---------- tarjeta de producto reutilizable (catálogo + relacionados) ---------- */

/* Estado de sesión, para decidir qué hace el botón de guardar.
   Cada página que sabe comprobar sesión (catalogo.html, producto.html)
   asigna estas dos variables después de consultar a Supabase — si
   una página no lo hace, quedan en sus valores por defecto y el
   catálogo se comporta exactamente igual que antes (carrito anónimo). */
let isLoggedIn = false;
let myActiveProjects = [];

function renderProductCard(p){
  const dist = DISTRIBUTORS[p.distribuidor];
  const marcaLabel = LABELS.marca[p.marca];
  const inSel = inSelection(p.id);
  const selectButton = `
    <button type="button" class="btn ${inSel ? "btn-added" : "btn-primary"} btn-add-selection" data-id="${p.id}" ${inSel ? "disabled" : ""}>
      ${inSel ? "En mi selección" : "Añadir a la selección"}
    </button>`;
  return `
    <article class="product-card" data-product-id="${p.id}">
      <div class="card-media">
        <span class="badge ${badgeClass(p.disponibilidad)}">${LABELS.disponibilidad[p.disponibilidad]}</span>
        ${iconMarkup(p.icon, 72)}
      </div>
      <div class="card-body">
        <span class="card-brand">${marcaLabel}</span>
        <span class="card-name">${p.nombre}</span>
        <span class="card-meta">${dist.nombre} · ${LABELS.categoria[p.categoria]}</span>
        <div class="card-actions">
          <a class="btn btn-outline" href="producto.html?id=${p.id}">Ver ficha</a>
          ${selectButton}
        </div>
      </div>
    </article>`;
}

/* Actualiza el enlace "Mi selección (N)" del header, en las
   páginas que lo tengan — no hace nada si el elemento no existe. */
function updateSelectionBadge(){
  const el = document.getElementById("selection-count-link");
  if (!el) return;
  const n = getSelectionCount();
  el.textContent = n > 0 ? `Mi selección (${n})` : "Mi selección";
}

function bindAddButtons(container, onChange){
  container.querySelectorAll(".btn-add-selection").forEach(btn => {
    btn.addEventListener("click", async () => {
      btn.disabled = true;
      const originalLabel = btn.textContent;
      btn.textContent = "Añadiendo…";

      await new Promise(resolve => setTimeout(resolve, 220));

      const productId = btn.dataset.id;
      const product = PRODUCTS.find(p => p.id === productId);
      const unit = getProductUnit(product);
      const initialQuantity = unit === "ud." ? 1 : 0;

      const addResult = addToSelection(productId, initialQuantity, unit);
      if (!addResult.success){
        btn.textContent = originalLabel;
        btn.disabled = false;
        if (addResult.error) alert(addResult.error);
        return;
      }
      btn.textContent = "En mi selección";
      btn.classList.remove("btn-primary");
      btn.classList.add("btn-added");
      // queda deshabilitado a propósito — comportamiento sin cambios
      updateSelectionBadge();
      if (onChange) onChange();
    });
  });
}

/* ---------- navegación móvil ---------- */
function initNavToggle(){
  const toggle = document.querySelector(".nav-toggle");
  if(!toggle) return;
  toggle.addEventListener("click", () => {
    document.body.classList.toggle("nav-open");
  });
}

/* ---------- init general ---------- */
document.addEventListener("DOMContentLoaded", () => {
  injectIconSprite();
  initNavToggle();
  updateCartBadge();
  propagateCartLinks();
  updateSelectionBadge();
});
