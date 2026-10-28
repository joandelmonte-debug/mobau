/* Punto 47 · prototipo local (solo mocks, sin red ni Supabase). Datos sintéticos: ningún importe, referencia ni nombre
   de este archivo es real, salvo la referencia 1.1120.8111 / 1.1122.0218 que se usan como ejemplo de la familia Malta.
   Expone window.MOCK47 = { CATEGORIES, GLYPHS, CATALOG, CONFIGS, scenario(n) }. */
(() => {
  const CATEGORIES = {
    "iluminacion": "Iluminación", "mobiliario": "Mobiliario", "revestimientos": "Revestimientos",
    "bano": "Baño", "cocina": "Cocina", "accesorios-decorativos": "Accesorios decorativos"
  };
  /* Miniaturas sintéticas (el proyecto real usa la foto del producto o del acabado). */
  const GLYPHS = {
    "iluminacion": '<path d="M8 5h8l3 8H5z"/><path d="M12 13v7M8 20h8"/>',
    "mobiliario": '<path d="M7 4v9h10V4"/><path d="M5 13h14v3H5z"/><path d="M7 16v4M17 16v4"/>',
    "revestimientos": '<rect x="4" y="4" width="7" height="7"/><rect x="13" y="4" width="7" height="7"/><rect x="4" y="13" width="7" height="7"/><rect x="13" y="13" width="7" height="7"/>',
    "bano": '<path d="M6 10a6 6 0 0 1 12 0"/><path d="M12 4v3M8 14v2M12 14v4M16 14v2"/>',
    "cocina": '<path d="M5 10h14v8H5z"/><path d="M3 10h18M9 6c0-2 3-2 3-4"/>',
    "accesorios-decorativos": '<ellipse cx="12" cy="11" rx="6" ry="8"/><path d="M12 19v3"/>'
  };
  const FIN = {
    blanco: { code: "W", name: "Blanco", color: "#F3F1EC" }, negro: { code: "B", name: "Negro mate", color: "#2B2B2A" },
    latón: { code: "L", name: "Latón cepillado", color: "#C9A560" }, roble: { code: "R", name: "Roble natural", color: "#C8A47A" },
    gris: { code: "G", name: "Gris piedra", color: "#B9B6AD" }, arena: { code: "A", name: "Arena", color: "#E2D3B8" },
    verde: { code: "V", name: "Verde salvia", color: "#A9B79F" }
  };
  /* [id, nombre, marca, ref, categoría, unidad, acabados, precio] precio: [USD, DOP] se resuelve en PRICES | "cotizacion" | null */
  const rows = [
    ["malta-doble", "MALTA CARDAN DOUBLE", "Hofflights", "1.1120.8111", "iluminacion", "ud.", ["blanco", "negro"], [38, "USD"]],
    ["aplique-meridian", "Aplique de pared Meridian", "Marset", "AP-1021", "iluminacion", "ud.", ["negro", "latón"], [96, "USD"]],
    ["colgante-arco", "Colgante Arco de tres luces con difusor opal de vidrio soplado a mano y base de latón cepillado", "Vibia", "CG-3310", "iluminacion", "ud.", ["latón", "negro"], [412, "USD"]],
    ["downlight-bogota", "Downlight de superficie Bogotá GU10", "Hofflights", "1.2020.1190", "iluminacion", "ud.", ["blanco", "negro"], [22, "USD"]],
    ["riel-track", "Riel Track ON-OFF 2 m", "Hofflights", "1.5000.8202", "iluminacion", "ud.", ["blanco", "negro"], [54, "USD"]],
    ["lampara-pie", "Lámpara de pie Nórdica", "Vibia", "LP-2204", "iluminacion", "ud.", ["roble", "negro"], "cotizacion"],
    ["silla-tolu", "Silla Tolú con brazos", "Casa Lúa", "SL-100", "mobiliario", "ud.", ["roble", "gris", "verde"], [185, "USD"]],
    ["mesa-comedor", "Mesa de comedor Ancla 220 × 100 cm en roble macizo con tratamiento mate", "Casa Lúa", "MS-220", "mobiliario", "ud.", ["roble"], [1240, "USD"]],
    ["sofa-modular", "Sofá modular Lisboa 3 plazas", "Casa Lúa", "SF-330", "mobiliario", "ud.", ["gris", "arena"], [2890, "USD"]],
    ["banco-entrada", "Banco de entrada Tolú", "Casa Lúa", "BN-040", "mobiliario", "ud.", ["roble", "negro"], null],
    ["cama-queen", "Cama Queen con cabecero tapizado", "Casa Lúa", "CM-160", "mobiliario", "ud.", ["gris", "arena"], [1480, "USD"]],
    ["escritorio-recto", "Escritorio recto 140 cm", "Casa Lúa", "ES-140", "mobiliario", "ud.", ["roble", "blanco"], [640, "USD"]],
    ["porcelanato-gris", "Porcelanato rectificado Cantera 60 × 120 cm", "Terra Cerámica", "PC-6120", "revestimientos", "m²", ["gris", "arena"], [38.5, "USD"]],
    ["ceramica-muro", "Cerámica de muro Bruma 30 × 60 cm", "Terra Cerámica", "CM-3060", "revestimientos", "m²", ["blanco", "verde"], [1450, "DOP"]],
    ["piso-vinilico", "Piso vinílico Roble Claro", "Terra Cerámica", "PV-120", "revestimientos", "m²", ["roble"], [24.9, "USD"]],
    ["piedra-natural", "Piedra natural Travertino pulido", "Terra Cerámica", "PN-040", "revestimientos", "m²", ["arena"], "cotizacion"],
    ["inodoro-suspendido", "Inodoro suspendido Aura con tapa de cierre suave", "Baccara Baño", "IN-210", "bano", "ud.", ["blanco"], [320, "USD"]],
    ["lavabo-sobre", "Lavabo sobre encimera Aura 50 cm", "Baccara Baño", "LV-050", "bano", "ud.", ["blanco", "negro"], [210, "USD"]],
    ["griferia-lavabo", "Grifería monomando de lavabo Delta", "Baccara Baño", "GR-310", "bano", "ud.", ["negro", "latón"], [9800, "DOP"]],
    ["ducha-lluvia", "Set de ducha de lluvia Delta", "Baccara Baño", "DU-400", "bano", "ud.", ["negro", "latón"], [455, "USD"]],
    ["espejo-redondo", "Espejo redondo Eclipse 80 cm", "Casa Lúa", "EJ-080", "accesorios-decorativos", "ud.", ["negro", "latón"], [175, "USD"]],
    ["fregadero-doble", "Fregadero doble seno acero", "Fontana Cocina", "FR-200", "cocina", "ud.", ["gris"], [380, "USD"]],
    ["griferia-cocina", "Grifería de cocina extraíble Nova", "Fontana Cocina", "GC-120", "cocina", "ud.", ["negro", "latón"], [14500, "DOP"]],
    ["alfombra-lana", "Alfombra de lana tejida a mano 200 × 300 cm", "Casa Lúa", "AF-230", "accesorios-decorativos", "ud.", ["arena", "gris"], "cotizacion"],
    ["papel-tapiz", "Papel tapiz Selva", "Casa Lúa", "PT-014", "accesorios-decorativos", "m²", ["verde"], [32, "USD"]],
    ["campana-isla", "Campana de isla Brisa 90 cm", "Fontana Cocina", "CP-090", "cocina", "ud.", ["negro", "gris"], null]
  ];
  /* Importes SIMULADOS en cada moneda (escritos a mano, no calculados con ningún tipo de cambio): el proyecto se muestra en
     dólares O en pesos, nunca mezclados. */
  const PRICES = {
    "malta-doble": [38, 2250], "aplique-meridian": [96, 5700], "colgante-arco": [412, 24500], "downlight-bogota": [22, 1300], "riel-track": [54, 3200],
    "silla-tolu": [185, 11000], "mesa-comedor": [1240, 73500], "sofa-modular": [2890, 171000], "cama-queen": [1480, 87800], "escritorio-recto": [640, 38000],
    "porcelanato-gris": [38.5, 2290], "ceramica-muro": [24.7, 1450], "piso-vinilico": [24.9, 1480], "inodoro-suspendido": [320, 19000], "lavabo-sobre": [210, 12500],
    "griferia-lavabo": [165, 9800], "ducha-lluvia": [455, 27000], "espejo-redondo": [175, 10400], "fregadero-doble": [380, 22500], "griferia-cocina": [245, 14500], "papel-tapiz": [32, 1900]
  };
  const CATALOG = rows.map(([id, name, brand, ref, cat, unit, fins, price]) => ({
    id, name, brand, ref, cat, unit, finishes: fins.map(k => FIN[k]),
    price: price === "cotizacion" ? { status: "quote_required" } : price ? { status: "published", amounts: { USD: PRICES[id][0], DOP: PRICES[id][1] } } : { status: "none" }
  }));

  /* Configuraciones simuladas: lo que devolvería line_configuration_resolve (items con suministro, cantidad por unidad y
     precio del componente). status «pendiente» = falta una elección necesaria. */
  const CONFIGS = {
    "malta-modulo-driver": { summary: "Módulo MALTA + Driver DALI", status: "completa", items: [
      { name: "MALTA 8–12 GEN 3 CTT SWITCH | MÓDULO LED", ref: "1.1122.0218", supply: "aparte", qty: 2, mode: "fija", price: { amounts: { USD: 24, DOP: 1425 } } },
      { name: "Driver DALI 30 W", ref: "DRV-DALI-30", supply: "aparte", qty: 1, mode: "fija", price: { amounts: { USD: 31, DOP: 1840 } } },
      { name: "Portalámparas GU10", ref: "1.1120.8001", supply: "incluido", qty: 2, mode: "fija", price: { amounts: { USD: 4, DOP: 240 } } }
    ], notices: ["Mobau no valida la compatibilidad técnica entre piezas."] },
    "malta-sin-driver": { summary: "Módulo MALTA · falta elegir Driver", status: "pendiente", items: [
      { name: "MALTA 8–12 GEN 3 CTT SWITCH | MÓDULO LED", ref: "1.1122.0218", supply: "aparte", qty: 2, mode: "fija", price: { amounts: { USD: 24, DOP: 1425 } } }
    ], reasons: ["Falta elegir «Driver»."], notices: [] },
    "colgante-lamparas": { summary: "Difusor opal + Soporte (3 lámparas E27, cantidad por determinar)", status: "completa", items: [
      { name: "Difusor opal de repuesto", ref: "DF-OP-01", supply: "aparte", qty: 1, mode: "fija", price: { amounts: { USD: 65, DOP: 3850 } } },
      { name: "Soporte de techo con cableado", ref: "ST-220", supply: "aparte", qty: 1, mode: "fija", price: { amounts: { USD: 38, DOP: 2250 } }, nested: [
        { name: "Lámpara LED E27 8 W", ref: "LD-E27-8", supply: "aparte", qty: null, mode: "a_calcular", price: { amounts: { USD: 6, DOP: 355 } } }
      ] }
    ], notices: [] },
    "riel-accesorios": { summary: "Riel + Foco orientable ×4 + Conector en L", status: "completa", items: [
      { name: "Foco orientable para riel", ref: "FO-100", supply: "aparte", qty: 4, mode: "fija", price: { amounts: { USD: 29, DOP: 1720 } } },
      { name: "Conector en L", ref: "CN-L90", supply: "aparte", qty: 1, mode: "fija", price: null },
      { name: "Alimentador 24 V", ref: "AL-24", supply: "incluido", qty: 1, mode: "fija", price: null }
    ], notices: [] },
    "aplique-driver-dop": { summary: "Aplique + Driver regulable", status: "completa", items: [
      { name: "Driver regulable 15 W", ref: "DRV-15R", supply: "aparte", qty: 1, mode: "fija", price: { amounts: { USD: 38, DOP: 2250 } } }
    ], notices: [] }
  };
  const CONFIG_FOR = { "malta-doble": ["malta-modulo-driver", "malta-sin-driver"], "colgante-arco": ["colgante-lamparas"], "riel-track": ["riel-accesorios"], "aplique-meridian": ["aplique-driver-dop"] };

  /* PRNG determinista para que 20 y 100 líneas sean siempre las mismas. */
  function prng(seed){ return () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
  const LONG_NOTES = [
    "Confirmar con el distribuidor la medida exacta del hueco de empotrado antes de pedir; en esta área el falso techo es de 12 cm y la profundidad del módulo de 120 mm deja poco margen para el cableado del driver remoto.",
    "Entrega en dos fases: primero la obra gris y después el acabado. Coordinar con el contratista el acceso por el montacargas del lado norte.",
    "Referencia de obra: plano E-04, detalle 7.", "Cliente prefiere el acabado más claro; validar muestra física.",
    "Pedir muestra del tono antes de confirmar lote."
  ];
  const AREA_SETS = {
    20: ["Sala y comedor", "Cocina", "Baño principal", "Dormitorio principal"],
    100: ["Lobby", "Recepción", "Restaurante", "Habitación tipo A", "Habitación tipo B", "Suite", "Baños comunes", "Terraza", "Spa", "Oficinas"]
  };
  /* Escenario: n líneas con productos simples y configurados, notas, productos repetidos en áreas distintas,
     precios conocidos, ausentes y parcialmente calculables, nombres largos y componentes anidados. */
  function scenario(n){
    const r = prng(n * 7919);
    const names = AREA_SETS[n] || AREA_SETS[20];
    const areas = names.map((name, i) => ({ id: "a" + (i + 1), name }));
    const lines = [];
    const pick = a => a[Math.floor(r() * a.length)];
    let seq = 0;
    const add = (productId, finishIdx, qty, areaId, extra) => {
      const p = CATALOG.find(x => x.id === productId);
      const fin = p.finishes[finishIdx % p.finishes.length];
      lines.push(Object.assign({ id: "l" + (++seq), productId, finish: fin.code, qty, unit: p.unit, areaId, note: "", configId: null }, extra || {}));
    };
    /* Casos fijos que no pueden faltar. */
    add("malta-doble", 0, 6, areas[0].id, { configId: "malta-modulo-driver", note: LONG_NOTES[0] });
    add("malta-doble", 0, 4, areas[Math.min(1, areas.length - 1)].id, { configId: "malta-modulo-driver" });          // mismo producto + acabado + configuración en otra área
    add("malta-doble", 1, 2, areas[0].id, { configId: "malta-sin-driver" });                                       // pendiente
    add("colgante-arco", 0, 3, areas[0].id, { configId: "colgante-lamparas", note: LONG_NOTES[1] });
    add("riel-track", 1, 2, areas[Math.min(2, areas.length - 1)].id, { configId: "riel-accesorios" });
    add("aplique-meridian", 0, 5, areas[Math.min(2, areas.length - 1)].id, { configId: "aplique-driver-dop" });
    add("lampara-pie", 1, 1, null, { note: LONG_NOTES[3] });                                                       // sin área, cotización
    add("silla-tolu", 0, 6, areas[0].id);
    add("silla-tolu", 0, 4, areas[Math.min(1, areas.length - 1)].id);                                              // repetido en otra área
    add("porcelanato-gris", 0, 42.5, areas[Math.min(2, areas.length - 1)].id, { note: "Incluir 10 % de merma." });
    add("piedra-natural", 0, 12, areas[Math.min(2, areas.length - 1)].id);
    add("ceramica-muro", 1, 18.75, areas[Math.min(1, areas.length - 1)].id);                                       // precio en DOP
    add("griferia-lavabo", 0, 3, areas[Math.min(2, areas.length - 1)].id);
    add("banco-entrada", 0, 1, null);                                                                              // sin precio
    while (lines.length < n){
      const p = pick(CATALOG);
      const cfgIds = CONFIG_FOR[p.id];
      const area = r() < 0.08 ? null : pick(areas).id;
      const isM2 = p.unit === "m²";
      const qty = isM2 ? Math.round((5 + r() * 60) * 100) / 100 : 1 + Math.floor(r() * 6);
      add(p.id, Math.floor(r() * 3), qty, area, {
        configId: cfgIds && r() < 0.7 ? pick(cfgIds) : null,
        note: r() < 0.18 ? pick(LONG_NOTES) : ""
      });
    }
    return { project: { id: "p47", name: n === 100 ? "Hotel Costa Norte · fase 1" : "Apartamento Bella Vista", status: "active", client: n === 100 ? "Grupo Hotelero Caribe" : "Familia Rosario", location: n === 100 ? "Cabrera" : "Santo Domingo", type: n === 100 ? "Hospitality" : "Residencial", updated: "27 oct 2026" }, areas, lines };
  }
  /* Selección temporal simulada (mobau_seleccion) para «Añadir desde mi selección». */
  const SELECTION = [
    { productId: "silla-tolu", finish: "V", qty: 8, unit: "ud.", configId: null },
    { productId: "espejo-redondo", finish: "L", qty: 3, unit: "ud.", configId: null },
    { productId: "malta-doble", finish: "W", qty: 4, unit: "ud.", configId: "malta-modulo-driver" },
    { productId: "piso-vinilico", finish: "R", qty: 30, unit: "m²", configId: null }
  ];
  /* Casos de la demostración: A proyecto vacío, B sencillo (5 productos, sin áreas), C 20 por áreas, D 100 líneas por áreas. */
  function caso(key){
    if (key === "a") return { project: { id: "p47a", name: "Proyecto nuevo", status: "active", client: "—", location: "—", type: "—", updated: "27 oct 2026" }, areas: [], lines: [] };
    if (key === "b"){
      const mk = (id, productId, finish, qty, extra) => Object.assign({ id, productId, finish, qty, unit: prod(productId).unit, areaId: null, note: "", configId: null }, extra || {});
      const prod = id => CATALOG.find(p => p.id === id);
      return { project: { id: "p47b", name: "Remodelación de mi casa", status: "active", client: "Yo", location: "Santiago", type: "Residencial", updated: "27 oct 2026" }, areas: [], lines: [
        mk("l1", "silla-tolu", "R", 6), mk("l2", "mesa-comedor", "R", 1, { note: "Medir el paso por la puerta antes de pedirla." }),
        mk("l3", "malta-doble", "W", 8, { configId: "malta-modulo-driver" }), mk("l4", "porcelanato-gris", "A", 38.4), mk("l5", "lampara-pie", "B", 1)
      ] };
    }
    const sc = scenario(key === "d" ? 100 : 20);
    return sc;
  }
  window.MOCK47 = { CATEGORIES, GLYPHS, CATALOG, CONFIGS, SELECTION, scenario, caso };
})();
