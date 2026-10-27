/* Ensayo 46 · inicio del alta «Producto o componente» (solo pruebas locales, sin red).
   Se carga después de supabase-client.js, sobre el cliente simulado de CC1 (rol=supplier en el formulario, rol=mobau&aal=2 en
   la moderación), y solo en distribuidor-propuestas.html y moderacion-propuesta.html. Sustituye las tablas que lee y escribe ese formulario, con datos en memoria:
     products, categories, product_proposals (select, insert, update), product_finishes, product_prices,
     product_component_groups, product_component_options. El resto (product_assets, perfiles…) lo contesta CC1.
   Datos: tres productos propios (ex-principal, ex-componente, ex-ambos, los tres de «Iluminación»);
   un grupo «Fuente de luz» en ex-principal. Seis categorías como las del piloto.
   Configuración en sessionStorage "__alta46" (JSON): { proposals: [filas de product_proposals ya existentes] }.
   Registro: window.__alta46 = { proposals, writes: [{ op, table, payload, id }] } (persistidos en sessionStorage). */
(() => {
  if (!/(distribuidor-propuestas|moderacion-propuesta)\.html$/.test(location.pathname)) return;
  const FORM = /distribuidor-propuestas\.html$/.test(location.pathname);
  let conf = {};
  try { conf = JSON.parse(sessionStorage.getItem("__alta46") || "{}"); } catch (e) { conf = {}; }
  const now = new Date().toISOString();
  const base = { brand: "Demo", category_id: "iluminacion", subcategory: "Decorativa", use_context: "residencial", space: "sala",
    availability: "en-stock", lead_time: "2 semanas", description: "Producto simulado", measurements: "10 cm", materials: "Acero",
    finishes: null, image_url: null, technical_sheet_url: null, cad_bim_3d_url: null, publication_status: "published",
    reference_code: "REF-1", cover_asset_id: null, environment: null, light_source: null, electrical_connection: null,
    color_temperature: null, distributor_id: "spectro" };
  const products = [
    { id: "ex-principal", name: "Principal existente", catalog_role: "principal" },
    { id: "ex-componente", name: "Componente existente", catalog_role: "componente" },
    { id: "ex-ambos", name: "Ambos existente", catalog_role: "ambos" }
  ].map(p => Object.assign({}, base, p));
  const categories = [
    { id: "bano", name: "Baño", subcategories: ["Sanitarios", "Griferías"] },
    { id: "cocina", name: "Cocina", subcategories: ["Griferías", "Fregaderos"] },
    { id: "accesorios-decorativos", name: "Accesorios decorativos", subcategories: ["Espejos", "Objetos"] },
    { id: "iluminacion", name: "Iluminación", subcategories: ["Decorativa", "Arquitectónica"] },
    { id: "mobiliario", name: "Mobiliario", subcategories: ["Residencial", "Oficina"] },
    { id: "revestimientos", name: "Revestimientos", subcategories: ["Pisos", "Paredes"] }
  ];
  const groups = [{ id: "g1", product_id: "ex-principal", code: "fuente", label: "Fuente de luz", requirement: "necesario", choice: "una",
    depends_on_option_id: null, status: "activo", sort_order: 1 }];
  const options = [{ id: "o1", group_id: "g1", code: "led", kind: "ajuste", component_product_id: null, component_finish_code: null,
    setting_label: "LED", supply: null, quantity: null, quantity_mode: null, attributes: [], status: "activo", sort_order: 1 }];
  /* Usos sembrados (sessionStorage "__alta46_cfg"): { uses: [{ parent, component, status?, groupStatus? }], usageError: true }.
     Cada uso es un grupo de «parent» con una opción de componente «component» (activa salvo que se diga otra cosa).
     usageError: la lectura de opciones por componente (la comprobación de «Cambiar función») falla como sin permiso. */
  let cfg = {};
  try { cfg = JSON.parse(sessionStorage.getItem("__alta46_cfg") || "{}"); } catch (e) { cfg = {}; }
  (cfg.uses || []).forEach((u, i) => {
    groups.push({ id: `gu${i}`, product_id: u.parent, code: `uso${i}`, label: "Uso", requirement: "opcional", choice: "una",
      depends_on_option_id: null, status: u.groupStatus || "activo", sort_order: 10 + i });
    options.push({ id: `ou${i}`, group_id: `gu${i}`, code: `c${i}`, kind: "componente", component_product_id: u.component, component_finish_code: null,
      setting_label: null, supply: "incluido", quantity: "1.000", quantity_mode: "fija", attributes: [], status: u.status || "activo", sort_order: 1 });
  });
  /* Propuestas y registro de escrituras sobreviven a las navegaciones del formulario (guardar vuelve a Mis productos,
     «Crear componente» abre otra URL): viven en sessionStorage "__alta46" / "__alta46_log". */
  let log = [];
  try { log = JSON.parse(sessionStorage.getItem("__alta46_log") || "[]"); } catch (e) { log = []; }
  const T = window.__alta46 = { proposals: (conf.proposals || []).map(p => Object.assign({}, p)), writes: log, seq: Number(conf.seq || 0) };
  const persist = () => {
    sessionStorage.setItem("__alta46", JSON.stringify({ proposals: T.proposals, seq: T.seq }));
    sessionStorage.setItem("__alta46_log", JSON.stringify(T.writes));
  };

  const ok = (data) => ({ data, error: null });
  /* El formulario solo existe para un distribuidor verificado: se contesta aquí, sin depender de la URL (que usa «rol»). */
  const FIXED = !FORM ? {} : { profiles: [{ id: "x", role: "supplier", plan: "free_trial" }],
    distributor_profiles: [{ user_id: "x", verification_status: "verified", distributor_id: "spectro", nombre_comercial: "Spectro Lighting" }] };
  const table = (name) => FIXED[name] || ({ products, categories, product_component_groups: groups, product_component_options: options,
    product_finishes: [], product_prices: [], product_proposals: T.proposals,
    distributors: [{ id: "spectro", name: "Spectro Lighting" }], proposal_events: [] })[name];

  function builder(name) {
    const st = { filters: [], op: "select", single: false, maybe: false, payload: null };
    const run = () => {
      const rows = table(name);
      if (name === "product_component_options" && cfg.usageError && st.filters.some(f => f.col === "component_product_id")) {
        return Promise.resolve({ data: null, error: { code: "42501", message: "permission denied" } });
      }
      let out = rows;
      if (!FIXED[name]) st.filters.forEach(f => {
        out = out.filter(r => f.op === "eq" ? r[f.col] === f.val : (f.val || []).includes(r[f.col]));
      });
      if (st.op === "insert") {
        const row = Object.assign({ id: `00000000-0000-4000-8000-${String(++T.seq).padStart(12, "0")}`, status: "draft", version: 1,
          created_at: now, updated_at: now, submitted_at: null, rejection_reason: null, proposed_changes: {},
          proposed_new_subcategory: null, proposed_price_status: null, proposed_price_amount: null, internal_note: null,
          proposed_media: null, proposed_components: null, product_id: null }, st.payload);
        rows.push(row);
        T.writes.push({ op: "insert", table: name, payload: JSON.parse(JSON.stringify(st.payload)) });
        persist();
        return Promise.resolve(ok(st.single ? row : [row]));
      }
      if (st.op === "update") {
        out.forEach(r => Object.assign(r, st.payload));
        T.writes.push({ op: "update", table: name, payload: JSON.parse(JSON.stringify(st.payload)), id: (st.filters.find(f => f.col === "id") || {}).val });
        persist();
        return Promise.resolve(ok(st.single ? (out[0] || null) : out));
      }
      return Promise.resolve(ok(st.single ? (out[0] || null) : out));
    };
    const b = new Proxy({}, {
      get(_, prop) {
        if (prop === "then") return (resolve, reject) => {
          return run().then(resolve, reject);
        };
        if (prop === "eq" || prop === "in") return (col, val) => { st.filters.push({ op: prop, col, val }); return b; };
        if (prop === "single" || prop === "maybeSingle") return () => { st.single = true; return b; };
        if (prop === "insert" || prop === "update") return (payload) => { st.op = prop; st.payload = payload; return b; };
        return () => b;   // select, order…
      }
    });
    return { b, st, run };
  }

  const original = supabaseClient.from.bind(supabaseClient);
  supabaseClient.from = (name) => {
    if (!table(name)) return original(name);
    return builder(name).b;
  };
})();
