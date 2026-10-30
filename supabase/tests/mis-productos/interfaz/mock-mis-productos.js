/* Ensayo de Mis productos (solo pruebas locales, sin red). Sustituye products, categories y product_proposals
   de distribuidor-productos.html con datos en memoria; el resto (perfiles, distribuidor verificado…) lo contesta CC1
   con ?rol=supplier&perfil=own. Escrituras: se registran en window.__mp.writes (ninguna debería ocurrir al filtrar u ordenar). Lecturas en window.__mp.reads (tablas y rpc:función).
   Datos: 33 productos publicados de «spectro» (4 marcas, tipos principal/componente/ambos/sin tipo, códigos como texto con
   ceros, puntos y guiones) y propuestas abiertas de cambios: 4 en borrador, 3 enviadas, 2 con cambios solicitados. */
(() => {
  if (!/distribuidor-productos\.html$/.test(location.pathname)) return;
  const stamp = (i) => new Date(Date.UTC(2026, 9, 1, 0, 0, 0) - i * 3600e3).toISOString();
  const BRANDS = ["Vibia", "Hoff Light", "Délta", "Faro"];
  const ROLES = ["principal", "componente", "ambos", null];
  const CODES = ["007.10", "1.2020.1190", "00123", "A-10", "A-2", "2.9003.1318", "0001", "B_5"];
  const NAMES = ["Aplique Pared", "Árbol Suspendido", "Downlight Redondo", "Driver DALI", "Riel 2 m", "Lámpara de Mesa", "Foco Exterior", "Módulo LED"];
  const products = [];
  for (let i = 0; i < 33; i++) {
    products.push({
      id: `p${String(i + 1).padStart(2, "0")}`, name: `${NAMES[i % NAMES.length]} ${i < 8 ? "" : i}`.trim(),
      distributor_id: "spectro", brand: i === 5 ? "" : BRANDS[i % BRANDS.length], category_id: i % 3 === 0 ? "iluminacion" : "mobiliario",
      subcategory: "x", availability: "en-stock", publication_status: "published", updated_at: stamp(i),
      reference_code: i === 9 ? null : (i < CODES.length ? CODES[i] : `${CODES[i % CODES.length]}-${i}`),
      catalog_role: ROLES[Math.floor(i / 2) % ROLES.length]
    });
  }
  const proposal = (n, productId, status) => ({ id: `q${n}`, proposal_kind: "update", product_id: productId, status, version: 1,
    submitted_at: status === "draft" ? null : stamp(n), updated_at: stamp(n), reviewed_at: null, proposed_changes: { name: "Nuevo" },
    proposed_new_subcategory: null, proposed_price_status: null, proposed_price_amount: null, internal_note: null,
    rejection_reason: status === "changes_requested" ? "Falta ficha" : null, proposed_components: null });
  const proposals = [
    proposal(1, "p01", "draft"), proposal(2, "p02", "draft"), proposal(3, "p05", "draft"), proposal(4, "p09", "draft"),
    proposal(5, "p03", "submitted"), proposal(6, "p06", "submitted"), proposal(7, "p10", "submitted"),
    proposal(8, "p04", "changes_requested"), proposal(9, "p13", "changes_requested")
  ];
  /* Con ?extra=1 se añaden filas para las otras pestañas (sin tocar los 33 publicados ni sus propuestas):
     borrador, en revisión, dos retirados (uno con propuesta de cambios abierta), dos en papelera y dos altas nuevas. */
  const EXTRA = /[?&]extra=1(&|$)/.test(location.search);
  const extraLife = {};
  if (EXTRA) {
    const xp = (id, name, status, role, code, brand) => ({ id, name, distributor_id: "spectro", brand, category_id: "iluminacion", subcategory: "x",
      availability: "en-stock", publication_status: status, updated_at: stamp(40 + products.length), reference_code: code, catalog_role: role });
    const life = (state, o) => Object.assign({ lifecycle_state: state, has_open_proposal: false, allowed_actions: [], restore_to: null, retired_at: null,
      retired_by_kind: null, retired_reason: null, mobau_hold: false, trashed_at: null, trashed_by_kind: null }, o);
    products.push(
      xp("x-draft", "Borrador sin publicar", "draft", "principal", "X-001", "Vibia"),
      xp("x-review", "Pieza en revisión", "in_review", "componente", "X-002", "Faro"),
      xp("x-ret-a", "Retirado propio", "archived", "ambos", "X-003", "Hoff Light"),
      xp("x-ret-b", "Retirado con cambios abiertos", "archived", null, "X-004", "Délta"),
      xp("x-trash-a", "Papelera propia", "archived", "principal", "X-005", "Vibia"),
      xp("x-trash-b", "Papelera de Mobau", "archived", null, "X-006", "Faro"));
    extraLife["x-draft"] = life("draft", { allowed_actions: ["trash"] });
    extraLife["x-review"] = life("in_review", { allowed_actions: ["trash"] });
    extraLife["x-ret-a"] = life("retired", { allowed_actions: ["trash", "request_republish"], retired_at: "2026-09-01T10:00:00Z", retired_by_kind: "distributor" });
    extraLife["x-ret-b"] = life("retired", { has_open_proposal: true, retired_at: "2026-09-02T10:00:00Z", retired_by_kind: "mobau", mobau_hold: true });
    extraLife["x-trash-a"] = life("trashed", { allowed_actions: ["restore", "purge"], restore_to: "draft", trashed_at: "2026-09-03T10:00:00Z", trashed_by_kind: "distributor" });
    extraLife["x-trash-b"] = life("trashed", { allowed_actions: ["purge"], restore_to: "retired", trashed_at: "2026-09-04T10:00:00Z", trashed_by_kind: "mobau", retired_by_kind: "mobau", retired_reason: "Datos incompletos" });
    proposals.push(proposal(20, "x-ret-b", "draft"));
    const create = (n, status, name, components) => Object.assign(proposal(n, null, status), { proposal_kind: "create", product_id: null,
      proposed_changes: { name, brand: "Vibia", reference_code: `ALTA-${n}`, category_id: "iluminacion" }, proposed_components: components });
    proposals.push(create(21, "draft", "Alta como ambos", { catalog_role: "ambos" }), create(22, "submitted", "Alta sin tipo", null));
  }
  const categories = [{ id: "iluminacion", name: "Iluminación" }, { id: "mobiliario", name: "Mobiliario" }];
  const T = window.__mp = { writes: [], reads: [], products, proposals };
  const TABLES = { products, categories, product_proposals: proposals };

  /* Ciclo de vida (la interfaz está encendida): el simulador de CC1 no tiene respuesta para estas dos funciones y devuelve null,
     que la página trata como «respuesta no válida» y avisa en rojo. Aquí responden con la forma real de my_products_lifecycle():
     un producto publicado, con «trash» permitido salvo que tenga una propuesta abierta (entonces el servidor no lo permite). */
  const openIds = new Set(proposals.map(p => p.product_id));
  const lifecycleRows = () => products.map(p => Object.assign({ id: p.id, lifecycle_state: "published", has_open_proposal: openIds.has(p.id),
    allowed_actions: openIds.has(p.id) ? [] : ["trash"], updated_at: p.updated_at, restore_to: null, retired_at: null, retired_by_kind: null,
    retired_reason: null, mobau_hold: false, trashed_at: null, trashed_by_kind: null }, extraLife[p.id] || {}));
  const rpcOriginal = supabaseClient.rpc.bind(supabaseClient);
  supabaseClient.rpc = (fn, args) => {
    if (fn === "my_products_lifecycle") { T.reads.push(`rpc:${fn}`); return Promise.resolve({ data: lifecycleRows(), error: null }); }
    if (fn === "my_product_lifecycle_events") { T.reads.push(`rpc:${fn}`); return Promise.resolve({ data: [], error: null }); }
    return rpcOriginal(fn, args);
  };

  const original = supabaseClient.from.bind(supabaseClient);
  supabaseClient.from = (name) => {
    if (!TABLES[name]) return original(name);
    const st = { filters: [], op: "select" };
    const run = () => {
      if (st.op !== "select") { T.writes.push({ table: name, op: st.op }); return Promise.resolve({ data: [], error: null }); }
      T.reads.push(name);
      let out = TABLES[name];
      st.filters.forEach(f => { out = out.filter(r => f.op === "eq" ? r[f.col] === f.val : (f.val || []).includes(r[f.col])); });
      return Promise.resolve({ data: out.map(r => Object.assign({}, r)), error: null });
    };
    const b = new Proxy({}, { get(_, prop) {
      if (prop === "then") return (resolve, reject) => run().then(resolve, reject);
      if (prop === "eq" || prop === "in") return (col, val) => { st.filters.push({ op: prop, col, val }); return b; };
      if (["insert", "update", "delete", "upsert"].includes(prop)) return () => { st.op = prop; return b; };
      return () => b;
    } });
    return b;
  };
})();
