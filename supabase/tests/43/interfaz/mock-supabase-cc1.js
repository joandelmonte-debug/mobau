/* VISTA PREVIA LOCAL (punto 43 · T2, mocks P1) — datos simulados, sin red.
   Sustituye a supabase-js. Parámetros de la URL:
     rol     = individual | supplier | mobau | anon | unknown (fallo al leer el rol)
     uid     = a | b (dos cuentas profesionales distintas) — por defecto a
     pro     = 1 | 0 | err  (my_professional_access)
     perfil  = own | unverified | none | error   (solo supplier)
     aal     = 1 | 2 (Mobau: sin o con segundo factor; los precios no dependen de ello)
     t4      = 0 (servidor actual: precios a toda cuenta con sesión) | 1 (regla de T4)
     srv     = deny (el servidor responde 42501 plan_required aunque my_professional_access diga true)
     precios = err (fallo de red en cada consulta) | err1 (solo la primera falla)
     datos   = con | sin  (proyectos de la cuenta)
     del     = 23503 (cualquier borrado de proyecto responde 23503)
   Registro para las pruebas: window.__mock = { calls, storage, errors, emit(event, uid) }. */
(() => {
  /* La configuración viaja en la URL; en una redirección sin parámetros se
     conserva la última (sessionStorage "__mockqs", solo de la vista previa). */
  const MOCK_PARAMS = ["rol", "uid", "pro", "perfil", "aal", "t4", "srv", "precios", "datos", "del", "pp", "lentoacc", "nombre"];
  let q = new URLSearchParams(window.location.search);
  if (MOCK_PARAMS.some(k => q.has(k))) sessionStorage.setItem("__mockqs", q.toString());
  else q = new URLSearchParams(sessionStorage.getItem("__mockqs") || "");
  let ROL = q.get("rol") || "individual";
  const UIDS = { a: "aaaaaaaa-0000-4000-8000-00000000000a", b: "bbbbbbbb-0000-4000-8000-00000000000b",
                 s: "cccccccc-0000-4000-8000-00000000000c", m: "dddddddd-0000-4000-8000-00000000000d" };
  let UID = ROL === "supplier" ? UIDS.s : ROL === "mobau" ? UIDS.m : UIDS[q.get("uid") || "a"];
  const PP = q.get("pp") || "legacy";
  const LENTO_ACC = Number(q.get("lentoacc") || 0); // retraso de my_professional_access (ms) // perfil profesional: legacy (solo professional_name) | split | none
  const PRO = q.get("pro") || "1";
  const PERFIL = q.get("perfil") || "own";
  const T4 = q.get("t4") === "1";
  const SRV = q.get("srv");
  let PRECIOS = q.get("precios");
  const DATOS = q.get("datos") || "con";
  const DEL = q.get("del");
  const now = new Date().toISOString();
  const SB_KEY = "sb-skcoxtdppdcietgojdal-auth-token";

  /* Registro de accesos a localStorage/sessionStorage (clave y operación). */
  const M = window.__mock = { calls: [], storage: [], errors: [], writes: [] };
  const proto = Storage.prototype;
  for (const op of ["getItem", "setItem", "removeItem"]) {
    const orig = proto[op];
    proto[op] = function (key, ...rest) {
      M.storage.push({ area: this === window.sessionStorage ? "session" : "local", op, key });
      return orig.call(this, key, ...rest);
    };
  }
  const origError = console.error;
  console.error = (...args) => { M.errors.push(args.map(String).join(" ")); origError.apply(console, args); };
  window.addEventListener("error", e => M.errors.push("window.error: " + e.message));
  window.addEventListener("unhandledrejection", e => M.errors.push("unhandledrejection: " + (e.reason && e.reason.message || e.reason)));

  const base = { brand: "Demo", category_id: "iluminacion", subcategory: "Lámparas de pie", use_context: "residencial", space: "sala",
    availability: "en-stock", description: "Producto simulado para la vista previa.", measurements: "40 × 40 × 160 cm", materials: "Acero",
    finishes: "Negro mate", lead_time: "2 semanas", icon: "lampFloor", image_url: null, status: "active", created_at: now, updated_at: now,
    technical_sheet_url: null, cad_bim_3d_url: null };
  const products = [
    { id: "demo-pub", name: "Publicado", distributor_id: "spectro" },
    { id: "demo-cot", name: "Bajo cotización", distributor_id: "spectro" },
    { id: "demo-pend", name: "Pendiente", distributor_id: "altritempi" },
    { id: "demo-sin", name: "Sin fila de precio", distributor_id: "altritempi" },
    { id: "demo-nodisp", name: "Precio no disponible", distributor_id: "altritempi" }
  ].map(p => Object.assign({}, base, p));
  const priceRows = [
    { product_id: "demo-pub", price_status: "published", price_amount: 120, es_demo: false },
    { product_id: "demo-cot", price_status: "quote_required", price_amount: null, es_demo: false },
    { product_id: "demo-pend", price_status: "pending_confirmation", price_amount: null, es_demo: false },
    { product_id: "demo-nodisp", price_status: "unavailable", price_amount: null, es_demo: false }
  ];

  const P = (id) => `0000000${id}-1111-4111-8111-111111111111`;
  let projects = DATOS === "sin" ? [] : [
    { id: P(1), name: "Casa Norte", client_name: "Cliente A", project_type: null, location: "Santo Domingo", description: null, status: "active", created_at: now, updated_at: now, user_id: UID },
    { id: P(2), name: "Oficina Sur", client_name: null, project_type: null, location: null, description: null, status: "archived", created_at: now, updated_at: now, user_id: UID },
    { id: P(3), name: "Hotel Este", client_name: null, project_type: null, location: null, description: null, status: "archived", created_at: now, updated_at: now, user_id: UID }
  ];
  let projectProducts = DATOS === "sin" ? [] : [
    { id: "pp1", project_id: P(1), product_id: "demo-pub", quantity: 2, unit: "ud.", created_at: now, order_position: 1 },
    { id: "pp2", project_id: P(1), product_id: "demo-cot", quantity: 1, unit: "ud.", created_at: now, order_position: 2 },
    { id: "pp3", project_id: P(2), product_id: "demo-pend", quantity: 3, unit: "ud.", created_at: now, order_position: 1 },
    { id: "pp4", project_id: P(3), product_id: "demo-pub", quantity: 1, unit: "ud.", created_at: now, order_position: 1 }
  ];
  const rfqs = DATOS === "sin" ? [] : [{ id: "rfq1", project_id: P(3), requester_company: "Estudio", status: "submitted", created_at: now, requester_user_id: UID }];

  const err = (code, message, hint) => ({ data: null, error: { code, message, hint: hint || null, details: null } });
  const ok = (data, extra) => Object.assign({ data, error: null }, extra || {});
  const isPro = () => ROL === "individual" && PRO === "1";

  function tableResult(name, st) {
    const eq = (col) => (st.filters.find(f => f.op === "eq" && f.col === col) || {}).val;
    const inn = (col) => (st.filters.find(f => f.op === "in" && f.col === col) || {}).val;
    switch (name) {
      case "profiles":
        if (ROL === "unknown") return err("PGRST000", "fallo simulado al leer el rol");
        return ok([{ id: UID, role: ROL === "mobau" ? "admin" : ROL === "supplier" ? "supplier" : "individual",
                     plan: isPro() ? "individual_founder" : "free_trial" }]);
      case "plans":
        return ok([eq("id") === "individual_founder" ? { name: "Individual", max_active_projects: 1 } : { name: "Gratis", max_active_projects: 1 }]);
      case "distributor_profiles":
        if (PERFIL === "error") return err("PGRST000", "fallo simulado al leer el perfil");
        if (ROL !== "supplier" || PERFIL === "none") return ok([]);
        return ok([{ user_id: UID, nombre_comercial: "Spectro Lighting", verification_status: PERFIL === "unverified" ? "pending_verification" : "verified",
                     distributor_id: PERFIL === "unverified" ? null : "spectro" }]);
      case "professional_profiles": {
        if (st.op !== "select") return ok([]);
        if (ROL !== "individual" || PP === "none") return ok([]);
        const split = PP === "split";
        return ok([{ user_id: UID, professional_name: split ? "Ana Rosario" : "Ana Demo", first_name: split ? "Ana" : null, last_name: split ? "Rosario" : null,
                     professional_type: "arquitecto", city: "Santo Domingo", studio_name: "Estudio Demo", phone: "8090000000", website: null, instagram: null }]);
      }
      case "distributors":
        return ok([{ id: "spectro", name: "Spectro Lighting", location: "Santo Domingo", categories: ["iluminacion"] },
                   { id: "altritempi", name: "Altri Tempi", location: "Santiago", categories: ["iluminacion"] }]);
      case "categories":
        return ok([{ id: "iluminacion", name: "Iluminación", subcategories: ["Lámparas de pie"] }]);
      case "catalog_products": {
        let rows = products;
        if (eq("id")) rows = rows.filter(p => p.id === eq("id"));
        if (inn("id")) rows = rows.filter(p => inn("id").includes(p.id));
        return ok(rows);
      }
      case "projects": {
        if (ROL !== "individual") return ok([]);
        if (st.op === "delete") {
          M.calls.push(`delete:projects:${eq("id")}`);
          if (DEL === "23503" || rfqs.some(r => r.project_id === eq("id")))
            return err("23503", 'update or delete on table "projects" violates foreign key constraint "rfqs_project_id_fkey"');
          projects = projects.filter(p => !(p.id === eq("id") && p.status === "archived"));
          return ok(null);
        }
        if (st.op === "update" || st.op === "insert") { M.calls.push(`${st.op}:projects`); return ok([]); }
        let rows = projects;
        if (eq("status")) rows = rows.filter(p => p.status === eq("status"));
        if (eq("id")) rows = rows.filter(p => p.id === eq("id"));
        if (st.head) return ok(null, { count: rows.length });
        return ok(rows);
      }
      case "project_products": {
        if (st.op !== "select") { M.calls.push(`${st.op}:project_products`); return ok([]); }
        let rows = projectProducts.filter(r => projects.some(p => p.id === r.project_id));
        if (eq("project_id")) rows = rows.filter(r => r.project_id === eq("project_id"));
        if (inn("project_id")) rows = rows.filter(r => inn("project_id").includes(r.project_id));
        if (eq("product_id")) rows = rows.filter(r => r.product_id === eq("product_id"));
        return ok(rows);
      }
      case "rfqs":
        if (st.op !== "select") { M.calls.push(`${st.op}:rfqs`); return ok([]); }
        return ok(rfqs.filter(r => projects.some(p => p.id === r.project_id)));
      default:
        return ok([]);
    }
  }

  const RPC = {
    catalog_version: () => ok("mock-v1"),
    mobau_admin_session: () => ok({ admin: ROL === "mobau", aal2: ROL === "mobau" && q.get("aal") === "2" }),
    my_professional_access: () => {
      if (ROL === "anon") return err("42501", "permission denied for function my_professional_access");
      if (PRO === "err") return err("PGRST000", "fallo simulado");
      return ok(isPro());
    },
    catalog_published_prices: (args) => {
      if (ROL === "anon") return err("42501", "permission denied for function catalog_published_prices");
      if (PRECIOS === "err") return err("PGRST000", "fallo simulado de red");
      if (PRECIOS === "err1") { PRECIOS = null; return err("PGRST000", "fallo simulado de red (una vez)"); }
      if (SRV === "deny") return err("42501", "El acceso a precios está incluido en los planes Individual y Estudio.", "plan_required");
      if (T4) {
        if (ROL === "supplier" && !(PERFIL === "own"))
          return err("42501", "Verás los precios publicados cuando Mobau verifique tu empresa.", "distributor_unverified");
        if (ROL === "individual" && !isPro())
          return err("42501", "El acceso a precios está incluido en los planes Individual y Estudio.", "plan_required");
      }
      const ids = args && args.p_product_ids;
      return ok(ids ? priceRows.filter(r => ids.includes(r.product_id)) : priceRows);
    }
  };

  function builder(run) {
    const st = { filters: [], op: "select", head: false, single: false };
    const b = new Proxy({}, {
      get(_, prop) {
        if (prop === "then") return (resolve, reject) => run(st).then(out => {
          if (st.single && !out.error) out = { data: (out.data || [])[0] || null, error: null };
          return out;
        }).then(resolve, reject);
        if (prop === "eq" || prop === "in") return (col, val) => { st.filters.push({ op: prop, col, val }); return b; };
        if (prop === "maybeSingle" || prop === "single") return () => { st.single = true; return b; };
        if (prop === "select") return (_cols, opts) => { if (opts && opts.head) st.head = true; return b; };
        if (prop === "delete" || prop === "update" || prop === "insert" || prop === "upsert") return (payload) => { st.op = prop; st.payload = payload; return b; };
        return () => b;
      }
    });
    return b;
  }

  let session = ROL === "anon" ? null : { user: { id: UID, email: "demo@ejemplo.test", user_metadata: q.get("nombre") ? { name: q.get("nombre") } : {} }, access_token: "x" };
  try {
    if (session) localStorage.setItem(SB_KEY, JSON.stringify({ access_token: "x", user: { id: UID } }));
    else localStorage.removeItem(SB_KEY);
  } catch (e) {}
  const listeners = [];
  const wait = (ms) => new Promise(r => setTimeout(r, ms));
  /* Inicio de sesión hecho en otra pestaña: cambia la sesión guardada sin
     recargar esta página (para probar que el acceso se vuelve a pedir). */
  M.login = (uidKey) => {
    ROL = "individual";
    UID = UIDS[uidKey] || UIDS.a;
    session = { user: { id: UID, email: "demo@ejemplo.test", user_metadata: {} }, access_token: "x" };
    localStorage.setItem(SB_KEY, JSON.stringify({ access_token: "x", user: { id: UID } }));
  };
  M.emit = (event, uidKey) => {
    const s = event === "SIGNED_OUT" ? null : { user: { id: UIDS[uidKey] || UID, email: "otra@ejemplo.test", user_metadata: {} }, access_token: "y" };
    listeners.forEach(cb => cb(event, s));
  };
  window.supabase = { createClient: () => ({
    auth: {
      getSession: async () => ({ data: { session }, error: null }),
      getUser: async () => ({ data: { user: session && session.user }, error: null }),
      onAuthStateChange: (cb) => {
        listeners.push(cb);
        setTimeout(() => cb("INITIAL_SESSION", session), 0);
        return { data: { subscription: { unsubscribe() { const i = listeners.indexOf(cb); if (i >= 0) listeners.splice(i, 1); } } } };
      },
      signOut: async () => {
        M.calls.push("auth:signOut");
        session = null;
        try { localStorage.removeItem(SB_KEY); } catch (e) {}
        listeners.slice().forEach(cb => cb("SIGNED_OUT", null));
        return { error: null };
      },
      signInWithOtp: async () => ({ error: null })
    },
    from: (name) => builder(async (st) => {
      await wait(5);
      M.calls.push(`${st.op}:${name}`);
      if (st.op !== "select") M.writes.push({ op: st.op, table: name, payload: st.payload || null });
      return tableResult(name, st);
    }),
    rpc: (fn, args) => builder(async () => { await wait(fn === "my_professional_access" && LENTO_ACC ? LENTO_ACC : 5); M.calls.push(`rpc:${fn}`); return RPC[fn] ? RPC[fn](args) : ok(null); })
  }) };
})();
