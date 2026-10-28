/* Mesa B · copia de mock-areas-47.js para ver la página integrada (solo pruebas locales; no se publica).
   Añade: la configuración también por la URL (?caso=…), el caso "e" (60 líneas en 5 áreas y «Sin área», con las fotos
   públicas reales del catálogo descargadas en fotos/) y el caso "f" (proyecto pequeño sin áreas, con fotos).
   Nombres, marcas y acabados de esos productos son los del catálogo público; precios, cantidades y notas son simulados.
   El resto, igual que el ensayo 47:
   Se carga después de supabase-client.js, sobre el cliente simulado de CC1 (rol=individual&pro=1&uid=a), y sustituye:
   - las tablas projects, project_products, project_areas, rfqs, catalog_products, categories y distributors, con datos
     sintéticos y estado en memoria (insert, update y delete modifican las filas de esta carga);
   - las llamadas project_line_states, catalog_published_prices, project_lines_transfer y project_area_delete. Las dos últimas
     reproducen las reglas del servidor de 47-01 (conflictos re-comprobados al ejecutar, nada cambia si hay conflicto sin resolver).
   Configuración en sessionStorage "__p47" (JSON):
     caso:   "a" vacío | "b" 5 productos sin áreas | "c" 20 líneas en 3 áreas y «Sin área» | "d" 100 líneas en 6 áreas
     areas:  "ready" (por defecto) | "missing" (la tabla no existe: PGRST205) | "error" (fallo de red) | "error1" (falla solo la primera vez)
     precios: false -> sin acceso a precios (error 42501 plan_required)
     plan:   "estudio" (por defecto) | "individual"
     ficticias: { lineasPara: n } no usado
   Proyectos: P1 activo (según el caso), P2 archivado sin solicitud (4 líneas, 2 áreas), P3 archivado con solicitud (copia v2 con áreas).
   Registro: window.__p47 = { writes: [{ op, table, ... }], calls: [rpc], selects: [{ table, columns }] }. */
(() => {
  if (!/(proyectos-detalle|proyectos|proyectos-resumen|proyectos-cotizacion|seleccion)\.html$/.test(location.pathname)) return;
  let conf = {};
  try { conf = JSON.parse(sessionStorage.getItem("__p47") || "{}"); } catch (e) { conf = {}; }
  const qp = new URLSearchParams(location.search);
  if (qp.get("caso")) conf.caso = qp.get("caso");
  if (qp.get("areas")) conf.areas = qp.get("areas");
  if (qp.get("precios") === "0") conf.precios = false;
  if (qp.get("estadoP1")) conf.estadoP1 = qp.get("estadoP1");
  const CASO = conf.caso || "c";
  const P = n => `0000000${n}-1111-4111-8111-111111111111`;
  const A = (n) => `aaaa000${n}-2222-4222-8222-222222222222`;
  const now = new Date().toISOString();
  const T = window.__p47 = { writes: [], calls: [], selects: [], conf, seq: 0 };
  /* Mesa B: en los casos con fotos, una selección de ejemplo para probar «Añadir aquí» (solo si no hay otra). */
  const SELKEY = "mobau_seleccion:aaaaaaaa-0000-4000-8000-00000000000a";
  const semilla = () => [{ productId: fotos.find(p => !p.finish_options.length).id, quantity: 2, unit: "ud." }, { productId: "silla-tolu", quantity: 4, unit: "ud.", finish: "roble" }];
  const clone = v => JSON.parse(JSON.stringify(v));
  const wait = ms => new Promise(r => setTimeout(r, ms));
  const err = (code, message, hint, details) => ({ data: null, error: { code, message, hint: hint || null, details: details || null } });

  /* ---------- catálogo sintético ---------- */
  const base = { brand: "Demo", distributor_id: "spectro", subcategory: "General", use_context: "residencial", space: "sala", availability: "en-stock",
    description: "Producto simulado.", measurements: "40 cm", materials: "Acero", finishes: "Negro", lead_time: "2 semanas", icon: "lampFloor", image_url: null,
    status: "active", created_at: now, updated_at: now, technical_sheet_url: null, cad_bim_3d_url: null, catalog_role: "principal" };
  const fin = (code, name, ref, def) => ({ code, name, reference_code: ref, is_default: !!def });
  const catalog = [
    { id: "silla-tolu", name: "Silla Tolú", category_id: "mobiliario", reference_code: "ST-100", brand: "Tolú", icon: "chair", finish_options: [fin("roble", "Roble", "R1", true), fin("nogal", "Nogal", "N2")] },
    { id: "mesa-aro", name: "Mesa Aro", category_id: "mobiliario", reference_code: "MA-200", brand: "Tolú", icon: "table", finish_options: [fin("blanco", "Blanco", null, true)] },
    { id: "sofa-bruma", name: "Sofá Bruma", category_id: "mobiliario", reference_code: "SB-300", brand: "Bruma", icon: "sofa", finish_options: [fin("lino", "Lino", "L1", true), fin("gris", "Gris", "G2")] },
    { id: "lamp-orbe", name: "Lámpara Orbe", category_id: "iluminacion", reference_code: "LO-10", brand: "Spectro", icon: "lampFloor", finish_options: [fin("negro", "Negro", "K1", true)] },
    { id: "lamp-riel", name: "Riel Lineal", category_id: "iluminacion", reference_code: "RL-20", brand: "Spectro", icon: "lampFloor", finish_options: [fin("blanco", "Blanco", "B1", true)] },
    { id: "comp-led", name: "Módulo LED", category_id: "iluminacion", reference_code: "ML-01", brand: "Spectro", icon: "lampFloor", catalog_role: "componente", finish_options: [] },
    { id: "comp-driver", name: "Driver 24 V", category_id: "iluminacion", reference_code: "DR-24", brand: "Spectro", icon: "lampFloor", catalog_role: "componente", finish_options: [] },
    { id: "rev-porc", name: "Porcelánico Arena", category_id: "revestimientos", reference_code: "PA-60", brand: "Arena", icon: "tile", finish_options: [fin("mate", "Mate", null, true)] },
    { id: "rev-madera", name: "Madera Natural", category_id: "revestimientos", reference_code: "MN-12", brand: "Arena", icon: "tile", finish_options: [] },
    { id: "bano-grifo", name: "Grifo Cascada", category_id: "bano", reference_code: "GC-5", brand: "Agua", icon: "tap", finish_options: [fin("cromo", "Cromo", "C1", true)] },
    { id: "cot-pieza", name: "Pieza bajo cotización", category_id: "mobiliario", reference_code: "BC-1", brand: "Tolú", icon: "chair", finish_options: [] },
    { id: "viejo", name: "Producto archivado", category_id: "mobiliario", reference_code: "VJ-0", brand: "Tolú", icon: "chair", status: "archived", finish_options: [] }
  ].map(p => Object.assign({}, base, p));

  /* Mesa B: productos del catálogo público con su portada real (versión de tarjeta 4:5, fondo blanco), servida en local. */
  const FOTO = id => `${location.origin}/supabase/tests/mesa-b/fotos/${id}.jpg`;
  const fotos = [
    { id: "spectro-02651803", name: "Sweden Mesa Port\u00e1til", category_id: "iluminacion", reference_code: "2.9003.1318", brand: "Hoff Light", icon: "lampFloor", image_url: FOTO("spectro-02651803"), finish_options: [fin("fe58c844e258b", "Blanco", null, true),fin("f30abf718a862", "Negro", null, false)] },
    { id: "spectro-16e21399", name: "Duro Petra Plaf\u00f3n", category_id: "iluminacion", reference_code: "4881", brand: "Vibia", icon: "lampFloor", image_url: FOTO("spectro-16e21399"), finish_options: [fin("93", "Blanco", null, true),fin("18", "Grafito", null, false),fin("58", "Crema", null, false)] },
    { id: "spectro-19caf9e2", name: "DRIVER DALI & PUSH EU 125-500mA 5,5- 22W 100-240V", category_id: "iluminacion", reference_code: "4.3069.6102", brand: "Hoff Light", icon: "lampFloor", image_url: FOTO("spectro-19caf9e2"), finish_options: [] },
    { id: "spectro-2cc63dca", name: "MALTA 8-12 GEN 3 CTT SWITCH | MODULO LED", category_id: "iluminacion", reference_code: "1.1122.0218", brand: "Hoff Light", icon: "lampFloor", image_url: FOTO("spectro-2cc63dca"), finish_options: [] },
    { id: "spectro-2e12589a", name: "Mayfair Colgante", category_id: "iluminacion", reference_code: "5520", brand: "Vibia", icon: "lampFloor", image_url: FOTO("spectro-2e12589a"), finish_options: [fin("07", "GRAFITO Y VERDE", null, true),fin("08", "GRAFITO Y NARANJA", null, false)] },
    { id: "spectro-3470d67d", name: "Mayfair Mesa", category_id: "iluminacion", reference_code: "5500", brand: "Vibia", icon: "lampFloor", image_url: FOTO("spectro-3470d67d"), finish_options: [fin("08", "Grafito y Naranja", null, true),fin("07", "Grafito y Verde", null, false)] },
    { id: "spectro-402d4c08", name: "BOGOTA SURFACE DOWNLIGHT - GU10", category_id: "iluminacion", reference_code: "1.2020.1190", brand: "Hoff Light", icon: "lampFloor", image_url: FOTO("spectro-402d4c08"), finish_options: [fin("fe7732f235dcd", "Blanco", null, true),fin("f26d58f633b2f", "Negro", null, false)] },
    { id: "spectro-5add2cfd", name: "Alba Port\u00e1til", category_id: "iluminacion", reference_code: "3780", brand: "Vibia", icon: "lampFloor", image_url: FOTO("spectro-5add2cfd"), finish_options: [fin("38", "Terra Dark", null, true),fin("56", "Green D1", null, false),fin("24", "Beige M1", null, false)] },
    { id: "spectro-8ae12824", name: "Musa Pared", category_id: "iluminacion", reference_code: "7415", brand: "Vibia", icon: "lampFloor", image_url: FOTO("spectro-8ae12824"), finish_options: [fin("03", "Blanco", null, true),fin("24", "Beige D1", null, false),fin("36", "Soft Pink", null, false)] },
    { id: "spectro-8f6c2029", name: "Driver ON-OFF 150- 500mA 6,3-21W 240V", category_id: "iluminacion", reference_code: "4.1069.1101", brand: "Hoff Light", icon: "lampFloor", image_url: FOTO("spectro-8f6c2029"), finish_options: [] },
    { id: "spectro-b029fd1b", name: "Musa Mesa", category_id: "iluminacion", reference_code: "7400", brand: "Vibia", icon: "lampFloor", image_url: FOTO("spectro-b029fd1b"), finish_options: [fin("93", "Blanco", null, true),fin("36", "Soft Pink", null, false),fin("24", "Beige M1", null, false)] },
    { id: "spectro-b6ffb730", name: "Athens 9 Redondo", category_id: "iluminacion", reference_code: "2.3511.1312", brand: "Hoff Light", icon: "lampFloor", image_url: FOTO("spectro-b6ffb730"), finish_options: [fin("00", "Antracita", null, true)] },
    { id: "spectro-cb1cc62f", name: "Dama Pie", category_id: "iluminacion", reference_code: "3230", brand: "Vibia", icon: "lampFloor", image_url: FOTO("spectro-cb1cc62f"), finish_options: [fin("11", "Black", null, true),fin("25", "Beige D1", null, false)] },
    { id: "spectro-d3016bf1", name: "Dama Sobremesa", category_id: "iluminacion", reference_code: "3225", brand: "Vibia", icon: "lampFloor", image_url: FOTO("spectro-d3016bf1"), finish_options: [fin("25", "Beige D1", null, true),fin("11", "Black", null, false)] },
    { id: "spectro-e9436bca", name: "COPENHAGUE PARED", category_id: "iluminacion", reference_code: "1.3011.1111", brand: "Hoff Light", icon: "lampFloor", image_url: FOTO("spectro-e9436bca"), finish_options: [fin("f9eceb2c452ce", "Blanco", null, true)] }
  ].map(p => Object.assign({}, base, p));
  catalog.push(...fotos);
  if ((CASO === "e" || CASO === "f") && !localStorage.getItem(SELKEY)) localStorage.setItem(SELKEY, JSON.stringify(semilla()));
  const prices = { "silla-tolu": 150, "mesa-aro": 480, "sofa-bruma": 1200, "lamp-orbe": 260, "lamp-riel": 90, "comp-led": 35, "comp-driver": 22.5, "rev-porc": 18.4, "rev-madera": 41, "bano-grifo": 210, "viejo": 99 };
  fotos.forEach((p, i) => { if (i % 7 !== 3) prices[p.id] = [46.5, 1120, 38, 412, 520, 29.5, 540, 398, 465, 58, 845, 610, 31, 69, 22.4][i % 15]; });
  const unitOf = id => (id === "rev-porc" || id === "rev-madera" ? "m²" : "ud.");

  /* Configuraciones: A = fuente con módulo LED aparte (2 por unidad) y driver incluido; B = solo ajuste; X = pendiente. */
  const CFG = {
    A: { choices: [{ path: [], group: "fuente", options: ["led"] }] },
    B: { choices: [{ path: [], group: "fuente", options: ["calida"] }] },
    X: { choices: [{ path: [], group: "fuente", options: ["zzz"] }] },
    Q: { choices: [{ path: [], group: "fuente", options: ["cot"] }] }
  };
  const stateFor = cfg => {
    const opt = (((cfg && cfg.choices) || [])[0] || {}).options || [];
    if (opt.includes("led")) return { status: "completa", review: "sin_cambios", summary: "Fuente: Módulo LED aparte", reasons: [], notices: [],
      items: [{ kind: "componente", group: "fuente", option: "led", product_id: "comp-led", product_name: "Módulo LED", reference_code: "ML-01", supply: "aparte", quantity: 2, quantity_mode: "fija", factor: 2 },
              { kind: "componente", group: "driver", option: "d", product_id: "comp-driver", product_name: "Driver 24 V", reference_code: "DR-24", supply: "incluido", quantity: 1, quantity_mode: "fija", factor: 1 }] };
    if (opt.includes("calida")) return { status: "completa", review: "sin_cambios", summary: "Luz cálida", reasons: [], notices: [], items: [{ kind: "ajuste", group: "fuente", option: "calida", setting_label: "Cálida" }] };
    if (opt.includes("cot")) return { status: "completa", review: "sin_cambios", summary: "Fuente: a calcular", reasons: [], notices: [],
      items: [{ kind: "componente", group: "fuente", option: "cot", product_id: "comp-led", product_name: "Módulo LED", reference_code: "ML-01", supply: "aparte", quantity: null, quantity_mode: "a_calcular", factor: null }] };
    return { status: "pendiente", review: "revisar", summary: "", notices: [], items: [], reasons: [{ code: "opcion_no_disponible", message: "Una opción elegida en «Fuente» ya no está disponible." }] };
  };

  /* ---------- datos de los casos ---------- */
  const lines = [];
  const areas = [];
  let nline = 0;
  const addLine = (project, product, qty, o = {}) => {
    const p = catalog.find(c => c.id === product);
    const fo = (p && p.finish_options[0]) || null;
    lines.push({ id: `l${String(++nline).padStart(3, "0")}`, project_id: project, product_id: product, finish_code: o.finish !== undefined ? o.finish : (fo ? fo.code : null),
      configuration: o.cfg ? clone(CFG[o.cfg]) : null, config_key: o.cfg ? `k-${o.cfg}` : "", quantity: qty, unit: unitOf(product), notes: o.note || null,
      room_or_area: null, selected_for_rfq: o.sel !== false, created_at: now, order_position: nline, area_id: o.area || null });
  };
  const addArea = (project, n, name, sort) => areas.push({ id: A(n), project_id: project, name, sort_order: sort, created_at: new Date(Date.now() + n).toISOString() });
  if (CASO === "b"){
    addLine(P(1), "silla-tolu", 4); addLine(P(1), "mesa-aro", 1, { note: "Verificar altura con el cliente." }); addLine(P(1), "lamp-orbe", 2, { cfg: "A" });
    addLine(P(1), "rev-porc", 24.5); addLine(P(1), "cot-pieza", 1, { finish: null });
  } else if (CASO === "c"){
    addArea(P(1), 1, "Sala", 1); addArea(P(1), 2, "Cocina", 2); addArea(P(1), 3, "Baño", 3);
    addLine(P(1), "sofa-bruma", 1, { area: A(1) }); addLine(P(1), "mesa-aro", 1, { area: A(1) }); addLine(P(1), "lamp-orbe", 3, { area: A(1), cfg: "A" });
    addLine(P(1), "lamp-riel", 2, { area: A(1), cfg: "B" }); addLine(P(1), "silla-tolu", 6, { area: A(2), note: "Pedir muestra del tapizado." });
    addLine(P(1), "mesa-aro", 1, { area: A(2) }); addLine(P(1), "rev-porc", 12, { area: A(2) }); addLine(P(1), "lamp-orbe", 4, { area: A(2), cfg: "A" });
    addLine(P(1), "bano-grifo", 2, { area: A(3) }); addLine(P(1), "rev-porc", 8.5, { area: A(3) }); addLine(P(1), "cot-pieza", 1, { area: A(3), finish: null });
    addLine(P(1), "silla-tolu", 2, { note: "Medida del brazo: confirmar con el cliente." }); addLine(P(1), "lamp-riel", 1, { cfg: "X" }); addLine(P(1), "rev-madera", 30);
    addLine(P(1), "sofa-bruma", 1, { finish: "gris" }); addLine(P(1), "lamp-orbe", 1, { cfg: "Q" }); addLine(P(1), "bano-grifo", 1); addLine(P(1), "viejo", 1, { finish: null });
  } else if (CASO === "e"){
    /* 60 líneas: 5 áreas de tamaños desiguales (Cocina con 22) y 7 sin área; fotos reales, iconos, configuraciones,
       metros cuadrados, precios bajo cotización y un producto retirado. */
    ["Sala y comedor", "Cocina y desayunador", "Dormitorio principal", "Baño principal", "Terraza"].forEach((n, i) => addArea(P(1), i + 1, n, i + 1));
    const combos = [];
    fotos.forEach(p => (p.finish_options.length ? p.finish_options : [null]).forEach(f => combos.push([p.id, { finish: f ? f.code : null }])));
    const extras = [["lamp-orbe", { cfg: "A" }], ["lamp-riel", { cfg: "X" }], ["rev-porc", {}], ["rev-madera", {}], ["bano-grifo", {}], ["cot-pieza", { finish: null }],
      ["viejo", { finish: null }], ["silla-tolu", {}], ["sofa-bruma", {}], ["mesa-aro", {}], ["lamp-orbe", { cfg: "Q" }]];
    const seq = combos.slice(0, 29).concat(extras).concat(combos.slice(0, 20));
    const sizes = [[1, 12], [2, 22], [3, 8], [4, 6], [5, 5], [null, 7]];
    const LARGA = "Colocar a 1,65 m del suelo terminado, centrados sobre cada vano de la librería. Confirmar con el electricista la posición de las cajas de registro antes de cerrar el tablero de yeso. La clienta prefiere una luz ligeramente cálida en la zona de lectura; si el aplique no admite 2700 K, valorar otra versión antes de pedir la cotización. En el vano central la librería tiene 12 cm menos de fondo: revisar con el carpintero que el aplique no choque con la puerta abatible.";
    let k = 0;
    sizes.forEach(([area, n]) => { for (let j = 0; j < n; j++, k++){
      const [pid, o] = seq[k];
      const qty = pid.startsWith("rev-") ? [38.5, 12.6, 24.75][k % 3] : (k % 6) + 1;
      const note = k === 3 ? LARGA : k === 15 ? "Altura del cable a 75 cm sobre la encimera de la isla." : k === 40 ? "Confirmar con el electricista." : undefined;
      addLine(P(1), pid, qty, Object.assign({ area: area ? A(area) : null, note }, o));
    } });
  } else if (CASO === "f"){
    fotos.slice(0, 5).forEach((p, i) => addLine(P(1), p.id, i + 1, { note: i === 1 ? "Ver muestra del acabado con la clienta." : undefined }));
  } else if (CASO === "d"){
    ["Sala", "Cocina", "Baño", "Dormitorio 1", "Dormitorio 2", "Terraza"].forEach((n, i) => addArea(P(1), i + 1, n, i + 1));
    const prods = ["silla-tolu", "mesa-aro", "sofa-bruma", "lamp-orbe", "lamp-riel", "rev-porc", "rev-madera", "bano-grifo"];
    for (let i = 0; i < 100; i++){
      const pid = prods[i % prods.length], fo = catalog.find(c => c.id === pid).finish_options[0];
      /* Líneas distintas: el mismo producto en varias áreas o acabados, nunca repetido en la misma área. */
      addLine(P(1), pid, (i % 5) + 1, { area: i < 90 ? A((i % 6) + 1) : null, cfg: pid === "lamp-orbe" && i % 2 ? "A" : null, finish: fo ? (i >= 48 && catalog.find(c => c.id === pid).finish_options[1] ? catalog.find(c => c.id === pid).finish_options[1].code : fo.code) : null });
    }
  }
  /* P2: archivado sin solicitud, con áreas. P3: archivado con solicitud (copia v2). */
  addArea(P(2), 11, "Recepción", 1); addArea(P(2), 12, "Sala de juntas", 2);
  addLine(P(2), "silla-tolu", 8, { area: A(12) }); addLine(P(2), "mesa-aro", 1, { area: A(12) }); addLine(P(2), "sofa-bruma", 2, { area: A(11) }); addLine(P(2), "rev-porc", 20);
  addLine(P(3), "silla-tolu", 6); addLine(P(3), "mesa-aro", 2);
  const snapshotLine = (id, product, qty, area, areaName, order) => ({ line_id: id, product_id: product, product_name: catalog.find(c => c.id === product).name, finish_code: null, quantity: qty, unit: "ud.", notes: null,
    configuration: null, config_key: "", config_status: "no_requiere", config_summary: "", config_reasons: [], config_notices: [], items: [], area_id: area, area_name: areaName, area_sort_order: order });
  const rfqs = [{ id: "rfq-p3", project_id: P(3), requester_user_id: "aaaaaaaa-0000-4000-8000-00000000000a", requester_company: "Estudio", status: "submitted", created_at: now,
    lines_snapshot: { version: 2, taken_at: now, project_id: P(3), areas: [{ id: A(21), name: "Terraza", sort_order: 1 }, { id: A(22), name: "Comedor", sort_order: 2 }],
      distributors: [{ distributor_id: "spectro", distributor_name: "Spectro Lighting", lines: [
        snapshotLine("sl1", "silla-tolu", 6, A(22), "Comedor", 2), snapshotLine("sl2", "mesa-aro", 2, A(21), "Terraza", 1)] }] } }];
  const projects = [
    { id: P(1), name: "Casa Norte", client_name: "Familia Rosario", project_type: "residencial", location: "Santo Domingo", description: "Remodelación completa.", status: "active", created_at: now, updated_at: now },
    { id: P(2), name: "Oficina Sur", client_name: null, project_type: null, location: null, description: null, status: "archived", created_at: now, updated_at: now },
    { id: P(3), name: "Hotel Este", client_name: null, project_type: null, location: null, description: null, status: "archived", created_at: now, updated_at: now }
  ];
  if (conf.estadoP1 === "archived") projects[0].status = "archived";
  T.lines = lines; T.areas = areas; T.projects = projects; T.rfqs = rfqs;

  /* ---------- servidor simulado: mover/copiar y eliminar áreas (reglas de 47-01) ---------- */
  const same = (a, b) => a.product_id === b.product_id && (a.finish_code || "") === (b.finish_code || "") && a.config_key === b.config_key;
  const note = (existing, incoming, mode) => {
    const e = (existing || "").trim(), i = (incoming || "").trim();
    if (e && i && e !== i) return mode === "incoming" ? incoming : mode === "both" ? existing + "\n\n" + incoming : existing;
    return e || i || null;
  };
  const projectActive = id => (projects.find(p => p.id === id) || {}).status === "active";
  function rpcTransfer({ p_line_ids: ids, p_area_id: area, p_kind: kind, p_resolutions: res }){
    const mine = lines.filter(l => ids.includes(l.id));
    if (!mine.length || new Set(mine.map(l => l.project_id)).size !== 1 || mine.length !== new Set(ids).size) return err("23514", "Alguna línea no existe o no pertenece a un único proyecto.", "line_invalid");
    const project = mine[0].project_id;
    if (!projectActive(project)) return err("42501", "Solo se pueden reorganizar las líneas de un proyecto activo.", "project_not_active");
    if (area && !areas.some(a => a.id === area && a.project_id === project)) return err("23514", "El área no existe o no pertenece a este proyecto.", "area_invalid");
    const twinOf = l => lines.find(x => x.id !== l.id && x.project_id === project && same(x, l) && (x.area_id || null) === (area || null));
    const conflicts = [];
    mine.forEach(l => {
      if (kind === "move" && (l.area_id || null) === (area || null)) return;
      const t = twinOf(l); if (!t) return;
      const r = (res || {})[l.id];
      const needsNote = l.notes && t.notes && l.notes.trim() !== t.notes.trim();
      if (!r || !["sum", "skip"].includes(r.action) || (r.action === "sum" && needsNote && !["existing", "incoming", "both"].includes(r.note))) conflicts.push({ line_id: l.id, twin_id: t.id });
    });
    if (conflicts.length) return err("23514", "Hay líneas equivalentes en el destino: resuélvelas antes de continuar.", "transfer_conflict", JSON.stringify(conflicts));
    const out = { moved: 0, copied: 0, summed: 0, skipped: 0 };
    mine.forEach(l => {
      if (kind === "move" && (l.area_id || null) === (area || null)){ out.skipped++; return; }
      const t = twinOf(l), r = (res || {})[l.id];
      if (t){
        if (r.action === "skip"){ out.skipped++; return; }
        t.quantity = Math.round((Number(t.quantity) + Number(l.quantity)) * 100) / 100; t.notes = note(t.notes, l.notes, r.note);
        if (kind === "move") lines.splice(lines.indexOf(l), 1);
        out.summed++;
      } else if (kind === "move"){ l.area_id = area || null; out.moved++; }
      else { lines.push(Object.assign(clone(l), { id: `n${String(++T.seq).padStart(3, "0")}`, area_id: area || null, order_position: 9000 + T.seq })); out.copied++; }
    });
    return { data: out, error: null };
  }
  function rpcDeleteArea({ p_area_id: id, p_resolutions: res }){
    const a = areas.find(x => x.id === id);
    if (!a) return err("23514", "El área no existe.", "area_invalid");
    if (!projectActive(a.project_id)) return err("42501", "Solo se pueden modificar las áreas de un proyecto activo.", "project_not_active");
    const mine = lines.filter(l => l.area_id === id), conflicts = [];
    mine.forEach(l => {
      const t = lines.find(x => x.id !== l.id && x.project_id === a.project_id && same(x, l) && !x.area_id); if (!t) return;
      const r = (res || {})[l.id];
      const needsNote = l.notes && t.notes && l.notes.trim() !== t.notes.trim();
      if (!r || !["sum", "move"].includes(r.action)) return conflicts.push({ line_id: l.id, twin_id: t.id });
      if (r.action === "sum" && needsNote && !["existing", "incoming", "both"].includes(r.note)) return conflicts.push({ line_id: l.id, twin_id: t.id });
      if (r.action === "move" && (!r.area_id || r.area_id === id || !areas.some(x => x.id === r.area_id && x.project_id === a.project_id)
          || lines.some(x => x.id !== l.id && x.project_id === a.project_id && same(x, l) && x.area_id === r.area_id))) conflicts.push({ line_id: l.id, twin_id: t.id });
    });
    if (conflicts.length) return err("23514", "Hay líneas equivalentes en «Sin área»: resuélvelas antes de eliminar el área.", "area_conflict", JSON.stringify(conflicts));
    const out = { unassigned: 0, summed: 0, moved: 0 };
    mine.forEach(l => {
      const t = lines.find(x => x.id !== l.id && x.project_id === a.project_id && same(x, l) && !x.area_id), r = (res || {})[l.id];
      if (t && r.action === "move"){ l.area_id = r.area_id; out.moved++; }
      else if (t){ t.quantity = Math.round((Number(t.quantity) + Number(l.quantity)) * 100) / 100; t.notes = note(t.notes, l.notes, r.note); lines.splice(lines.indexOf(l), 1); out.summed++; }
      else { l.area_id = null; out.unassigned++; }
    });
    areas.splice(areas.indexOf(a), 1);
    return { data: out, error: null };
  }

  /* ---------- motor de tablas en memoria ---------- */
  let areaErrorOnce = conf.areas === "error1";
  function table(name){
    const st = { op: "select", filters: [], payload: null, single: false, notNull: [], columns: "*" };
    const b = {
      select(cols){ if (cols) st.columns = cols; return b; }, order(){ return b; }, limit(){ return b; }, range(){ return b; }, abortSignal(){ return b; },
      eq(col, val){ st.filters.push(["eq", col, val]); return b; }, is(col, val){ st.filters.push(["is", col, val]); return b; },
      in(col, val){ st.filters.push(["in", col, val]); return b; }, not(col){ st.notNull.push(col); return b; },
      maybeSingle(){ st.single = true; return b; }, single(){ st.single = true; return b; },
      insert(p){ st.op = "insert"; st.payload = p; return b; }, update(p){ st.op = "update"; st.payload = p; return b; }, delete(){ st.op = "delete"; return b; },
      then(a, c){ return wait(4).then(() => runTable(name, st)).then(a, c); }
    };
    return b;
  }
  const hit = (row, st) => st.filters.every(([op, col, val]) => op === "in" ? (val || []).includes(row[col]) : row[col] === val) && st.notNull.every(c => row[c] !== null && row[c] !== undefined);
  const res = (rows, st) => ({ data: st.single ? (rows[0] || null) : rows, error: null });
  function runTable(name, st){
    T.selects.push({ table: name, op: st.op, columns: st.columns });
    if (name === "project_areas"){
      if (conf.areas === "missing") return err("PGRST205", "Could not find the table 'public.project_areas' in the schema cache");
      if (conf.areas === "error") return err("PGRST000", "Fallo de red simulado");
      if (areaErrorOnce){ areaErrorOnce = false; return err("PGRST000", "Fallo de red simulado (una vez)"); }
    }
    if (name === "project_products" && conf.areas === "missing" && /area_id/.test(st.columns)) return err("42703", "column project_products.area_id does not exist");
    if (name === "project_products" && conf.lineasError) return err("PGRST000", "Fallo simulado leyendo las líneas");
    const store = { project_products: lines, project_areas: areas, projects, rfqs }[name];
    if (name === "catalog_products") return res(catalog.filter(p => !st.filters.length || st.filters.every(([op, col, val]) => op === "in" ? val.includes(p[col]) : p[col] === val)), st);
    if (name === "categories") return res([{ id: "mobiliario", name: "Mobiliario", subcategories: ["General"] }, { id: "iluminacion", name: "Iluminación", subcategories: ["General"] },
      { id: "revestimientos", name: "Revestimientos", subcategories: ["General"] }, { id: "bano", name: "Baño", subcategories: ["General"] }], st);
    if (name === "distributors") return res([{ id: "spectro", name: "Spectro Lighting", location: "Santo Domingo", categories: ["iluminacion"] }], st);
    if (!store) return null;
    if (st.op === "insert"){
      const row = Object.assign(name === "project_products" ? { id: `i${String(++T.seq).padStart(3, "0")}`, finish_code: null, configuration: null, config_key: "", selected_for_rfq: true, created_at: now, order_position: 9000 + T.seq, area_id: null, notes: null, room_or_area: null }
        : { id: A(30 + ++T.seq), created_at: new Date().toISOString() }, st.payload);
      if (name === "project_areas" && areas.some(a => a.project_id === row.project_id && a.name.toLowerCase() === row.name.toLowerCase())) return err("23505", "duplicate key value violates unique constraint \"project_areas_name_unique\"");
      if (name === "project_products" && lines.some(x => x.project_id === row.project_id && same(x, row) && (x.area_id || null) === (row.area_id || null))) return err("23505", "duplicate key value violates unique constraint \"project_products_area_line_unique\"");
      store.push(row); T.writes.push({ op: "insert", table: name, payload: clone(st.payload) });
      return res([row], st);
    }
    const rows = store.filter(r => hit(r, st));
    if (st.op === "update"){
      if (name === "project_products" && "notes" in st.payload && conf.errorNota) return err("42501", "rechazo", conf.errorNota);
      rows.forEach(r => Object.assign(r, st.payload)); T.writes.push({ op: "update", table: name, ids: rows.map(r => r.id), payload: clone(st.payload) });
      return res(rows, st);
    }
    if (st.op === "delete"){
      if (name === "project_areas" && rows.some(a => lines.some(l => l.area_id === a.id))) return err("23503", "violates foreign key constraint \"project_products_area_fk\"");
      rows.forEach(r => store.splice(store.indexOf(r), 1)); T.writes.push({ op: "delete", table: name, ids: rows.map(r => r.id) });
      return { data: null, error: null };
    }
    const sorted = name === "rfqs" ? rows.slice().reverse() : rows.slice().sort((a, b) => (a.sort_order ?? a.order_position ?? 0) - (b.sort_order ?? b.order_position ?? 0));
    return res(clone(sorted), st);
  }

  const originalFrom = supabaseClient.from.bind(supabaseClient);
  supabaseClient.from = name => (["project_products", "project_areas", "projects", "rfqs", "catalog_products", "categories", "distributors"].includes(name) ? table(name) : originalFrom(name));
  const originalRpc = supabaseClient.rpc.bind(supabaseClient);
  const rpcPromise = produce => { const q = { abortSignal(){ return q; }, then(a, c){ return wait(4).then(produce).then(a, c); } }; return q; };
  supabaseClient.rpc = (fn, args) => {
    if (fn === "project_line_states") return rpcPromise(() => { T.calls.push(fn); return { data: lines.filter(l => l.project_id === args.p_project_id)
      .map(l => Object.assign({ line_id: l.id, product_id: l.product_id, finish_code: l.finish_code, config_key: l.config_key },
        l.configuration ? stateFor(l.configuration) : { status: "no_requiere", review: "sin_cambios", summary: "", reasons: [], notices: [], items: [] })), error: null }; });
    if (fn === "catalog_published_prices") return rpcPromise(() => {
      T.calls.push(fn);
      if (conf.precios === false) return err("42501", "El acceso a precios está incluido en los planes Individual y Estudio.", "plan_required");
      const ids = (args && args.p_product_ids) || Object.keys(prices);
      return { data: ids.filter(id => prices[id] !== undefined).map(id => ({ product_id: id, price_status: "published", price_amount: prices[id], es_demo: false })), error: null };
    });
    if (fn === "project_lines_transfer") return rpcPromise(() => { T.calls.push(fn); T.writes.push({ op: "rpc", fn, args: clone(args) }); return rpcTransfer(args); });
    if (fn === "project_area_delete") return rpcPromise(() => { T.calls.push(fn); T.writes.push({ op: "rpc", fn, args: clone(args) }); return rpcDeleteArea(args); });
    return originalRpc(fn, args);
  };
})();
