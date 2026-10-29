/* Ensayo 49 (solo pruebas locales; no se publica). Se carga después de supabase-client.js y de los simuladores de CC1 y
   de la mesa B, y sustituye solo el catálogo: catalog_products, categories y distributors (datos de datos-catalogo-49.js),
   catalog_version y los importes de catalog_published_prices. El permiso para ver precios lo sigue decidiendo el simulador
   anterior (CC1 o mesa B): si deniega, se devuelve su mismo error; si permite, se devuelven los importes simulados.
   El artículo archivado («viejo») solo existe en las páginas de proyecto, como en la mesa B.
   Para las pruebas, sessionStorage "__p49_catalogo" deja la lista colgada o fallando (ver más abajo). */
(() => {
  const PROYECTO = /(proyectos-detalle|proyectos|proyectos-resumen|proyectos-cotizacion|seleccion)\.html$/.test(location.pathname);
  const wait = ms => new Promise(r => setTimeout(r, ms));
  const datos = () => {
    const d = window.MOBAU_DATOS_49();
    return Object.assign({}, d, { rows: d.rows.filter(r => PROYECTO || !r.soloProyecto) });
  };
  const pick = (row, cols) => {
    if (!cols || cols === "*") return Object.assign({}, row);
    const out = {};
    cols.split(",").map(c => c.trim()).forEach(c => { out[c] = row[c] === undefined ? null : row[c]; });
    return out;
  };
  function table(name){
    const st = { cols: "*", filters: [], from: 0, to: Infinity, single: false, limit: Infinity };
    const b = {
      select(c){ if (c) st.cols = c; return b; }, order(){ return b; }, abortSignal(){ return b; },
      range(a, z){ st.from = a; st.to = z; return b; }, limit(n){ st.limit = n; return b; },
      eq(c, v){ st.filters.push(r => r[c] === v); return b; }, in(c, v){ st.filters.push(r => (v || []).includes(r[c])); return b; },
      maybeSingle(){ st.single = true; return b; }, single(){ st.single = true; return b; },
      then(ok, ko){
        /* Pruebas del Punto 49: sessionStorage "__p49_catalogo" = "colgada" (la lista no llega) | "error" (falla). */
        const modo = name === "catalog_products" ? (sessionStorage.getItem("__p49_catalogo") || "") : "";
        if (modo === "colgada") return new Promise(() => {});
        if (modo === "error") return wait(20).then(() => ({ data: null, error: { code: "PGRST000", message: "Fallo de red simulado" } })).then(ok, ko);
        return wait(20).then(() => {
          const d = datos();
          const src = name === "catalog_products" ? d.rows : name === "categories" ? d.categories : d.distributors;
          const rows = src.filter(r => st.filters.every(f => f(r))).slice(st.from, st.to + 1).slice(0, st.limit)
            .map(r => pick(r, name === "catalog_products" ? st.cols : "*"));
          return { data: st.single ? (rows[0] || null) : rows, error: null };
        }).then(ok, ko);
      }
    };
    return b;
  }
  const prevFrom = supabaseClient.from.bind(supabaseClient);
  supabaseClient.from = name => (["catalog_products", "categories", "distributors"].includes(name) ? table(name) : prevFrom(name));

  const prevRpc = supabaseClient.rpc.bind(supabaseClient);
  const thenable = produce => { const q = { abortSignal(){ return q; }, then(a, c){ return wait(20).then(produce).then(a, c); } }; return q; };
  supabaseClient.rpc = (fn, args) => {
    if (fn === "catalog_version") return thenable(() => ({ data: "maqueta-49", error: null }));
    if (fn === "catalog_published_prices") return thenable(async () => {
      const prev = await prevRpc(fn, args);
      if (prev && prev.error) return prev;
      const prices = datos().prices;
      let ids = args && args.p_product_ids ? args.p_product_ids : Object.keys(prices).sort();
      if (!(args && args.p_product_ids)){
        if (args && args.p_after) ids = ids.filter(id => id > args.p_after);
        if (args && args.p_limit) ids = ids.slice(0, args.p_limit);
      }
      return { data: ids.filter(id => prices[id] !== undefined).map(id => ({ product_id: id, price_status: "published", price_amount: prices[id], es_demo: false })), error: null };
    });
    return prevRpc(fn, args);
  };
})();
