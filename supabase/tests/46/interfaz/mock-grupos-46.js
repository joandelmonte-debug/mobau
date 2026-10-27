/* Ensayo 46 · bloque 4 · paso 1 (datos del catálogo, interfaz, sin red).
   Se carga después de supabase-client.js, sobre el cliente simulado de CC1, y
   sustituye solo las dos vistas catalog_component_groups y
   catalog_component_options, con datos sintéticos y una cadena de consulta
   mínima de supabase-js (select, order, range, abortSignal).
   Datos (productos de CC1):
     demo-pub: fuente (necesario, una: comp = componente aparte, calida = ajuste),
               extras (opcional, varias: cable = componente incluido, cantidad a calcular),
               control (necesario, una, condicionado a fuente=comp: dim, onoff = ajustes)
     demo-cot: carcasa (necesario, una: x, y) — subcomponente
     demo-pend: vacio (necesario sin opciones disponibles)
     demo-sin y demo-nodisp: sin grupos
   Comportamiento en sessionStorage "__grupos46" (JSON):
     modo: "normal" | "error" | "rechazo" | "colgada" (no termina, ni al cancelar) |
           "tardia" (responde a los 5,5 s, sin atender la cancelación) |
           "malformada" (grupos sin código) | "sin_arreglo" (data no es una lista)
     retraso: ms que tarda cada consulta (por defecto 5; se puede cambiar en caliente)
     soloOpciones: true → el modo anómalo solo afecta a la vista de opciones
     validacion: "ok" | "pendiente" | "error" | "rechazo" | "colgada" | "tardia" → responde line_configuration_resolve
                 (sin esta clave no se toca esa RPC); modosVal: [modo de la 1.ª llamada, de la 2.ª, …] y
                 retrasosVal: [ms de la 1.ª, de la 2.ª, …] los afinan; se pueden cambiar en caliente
     acabados: true → demo-pub con los acabados «11» (Black) y «25» (Beige, por defecto)
     fuera: ["demo-cot", …] → esos productos no salen en la lista del catálogo (solo se leen «por identificadores»),
            como un producto que solo existe para usarse de componente
     acabadoComp: true → la opción «comp» lleva el acabado «11» de demo-cot (C-11 · Negro)
     roles: { id: valor, … } → catalog_role de esos productos (el resto de filas no trae la columna, como antes de 46-01);
            valor puede ser "principal" | "componente" | "ambos" | un valor desconocido | null
     carcasaOpcional: true → el grupo «carcasa» de demo-cot es opcional (simula un grupo Driver cambiado a opcional)
     refs: { id: "1.1122.0218", … } → reference_code de esos productos (el resto de filas no la trae)
     errorPorId: true → la lectura por identificadores falla; ausenteSiempre: true → tampoco devuelve los de «fuera»
     profundo: true → demo-cot con el grupo opcional «tapa» (t1 = componente demo-nodisp, aparte, 2 por unidad)
                 y demo-nodisp con el grupo necesario «tono» (warm, cool): un componente dentro de un componente
     conNuevo: true → añade un grupo a demo-sin (grupo nuevo en la base)
     precios: { id: { amount, status? }, … } → responde catalog_published_prices con estas filas (status por defecto «published»; un id sin fila = sin precio);
              preciosError: true → la segunda consulta de precios (la de los componentes) falla
     conPrecios: true → demo-pub gana el grupo «Driver» (opcional, una): d-sin (demo-sin, aparte, 1), d-dos (demo-nodisp, aparte, 2),
              d-inc (demo-pend, incluido, 1) y d-calc (demo-cot, aparte, cantidad a calcular)
     nombres: { id: "Nombre", … } → name de esos productos (para ver nombres reales en una captura)
     cotQty: "3" → la opción «comp» (demo-cot) lleva esta cantidad por unidad
     vacio: true → sin ningún grupo
   Registro: window.__grupos46 = { calls: [], tardias: [], validaciones: [], conf }, window.__sinCapturar. */
(() => {
  let conf = {};
  try { conf = JSON.parse(sessionStorage.getItem("__grupos46") || "{}"); } catch (e) { conf = {}; }
  const log = window.__grupos46 = { calls: [], tardias: [], validaciones: [], productosPorId: [], precios: [], conf }; // conf se puede cambiar en caliente (p. ej. modo) para probar la recuperación
  window.__sinCapturar = [];
  window.addEventListener("unhandledrejection", e => window.__sinCapturar.push(String(e.reason)));
  window.addEventListener("error", e => window.__sinCapturar.push(String(e.message)));

  const g = (id, product_id, code, label, requirement, choice, sort_order, depends_on_option_id, available_options) =>
    ({ id, product_id, code, label, requirement, choice, depends_on_option_id: depends_on_option_id || null, sort_order, available_options });
  const o = (id, group_id, product_id, code, kind, sort_order, extra) =>
    Object.assign({ id, group_id, product_id, code, kind, component_product_id: null, component_finish_code: null, setting_label: null,
                    supply: null, quantity: null, quantity_mode: null, attributes: [], sort_order }, extra);
  const groups = conf.vacio ? [] : [
    g("g-fuente", "demo-pub", "fuente", "Fuente", "necesario", "una", 1, null, 2),
    g("g-extras", "demo-pub", "extras", "Extras", "opcional", "varias", 2, null, 1),
    g("g-control", "demo-pub", "control", "Control", "necesario", "una", 3, "o-comp", 2),
    g("g-carcasa", "demo-cot", "carcasa", "Carcasa", conf.carcasaOpcional ? "opcional" : "necesario", "una", 1, null, 2),
    g("g-vacio", "demo-pend", "vacio", "Sin opciones", "necesario", "una", 1, null, 0)
  ];
  const options = conf.vacio ? [] : [
    o("o-comp", "g-fuente", "demo-pub", "comp", "componente", 1, { component_product_id: "demo-cot", supply: "aparte", quantity: "1.000", quantity_mode: "fija",
       attributes: [{ label: "Potencia", value: "24 W" }] }),
    o("o-calida", "g-fuente", "demo-pub", "calida", "ajuste", 2, { setting_label: "Cálida" }),
    o("o-cable", "g-extras", "demo-pub", "cable", "componente", 1, { component_product_id: "demo-pend", supply: "incluido", quantity_mode: "a_calcular" }),
    o("o-dim", "g-control", "demo-pub", "dim", "ajuste", 1, { setting_label: "Regulable" }),
    o("o-onoff", "g-control", "demo-pub", "onoff", "ajuste", 2, { setting_label: "Encendido" }),
    o("o-x", "g-carcasa", "demo-cot", "x", "ajuste", 1, { setting_label: "Blanca" }),
    o("o-y", "g-carcasa", "demo-cot", "y", "ajuste", 2, { setting_label: "Negra" })
  ];
  if (conf.conPrecios){
    groups.push(g("g-driver", "demo-pub", "driver", "Driver", "opcional", "una", 4, null, 4));
    options.push(o("o-d1", "g-driver", "demo-pub", "d-sin", "componente", 1, { component_product_id: "demo-sin", supply: "aparte", quantity: "1", quantity_mode: "fija" }),
                 o("o-d2", "g-driver", "demo-pub", "d-dos", "componente", 2, { component_product_id: "demo-nodisp", supply: "aparte", quantity: "2", quantity_mode: "fija" }),
                 o("o-d3", "g-driver", "demo-pub", "d-inc", "componente", 3, { component_product_id: "demo-pend", supply: "incluido", quantity: "1", quantity_mode: "fija" }),
                 o("o-d4", "g-driver", "demo-pub", "d-calc", "componente", 4, { component_product_id: "demo-cot", supply: "aparte", quantity_mode: "a_calcular" }));
  }
  if (conf.cotQty) options.find(x => x.id === "o-comp").quantity = conf.cotQty;
  if (conf.acabadoComp) options.find(x => x.id === "o-comp").component_finish_code = "11";
  if (conf.profundo){
    groups.push(g("g-tapa", "demo-cot", "tapa", "Tapa", "opcional", "una", 2, null, 1),
                g("g-tono", "demo-nodisp", "tono", "Tono", "necesario", "una", 1, null, 2));
    options.push(o("o-t1", "g-tapa", "demo-cot", "t1", "componente", 1, { component_product_id: "demo-nodisp", supply: "aparte", quantity: "2", quantity_mode: "fija" }),
                 o("o-warm", "g-tono", "demo-nodisp", "warm", "ajuste", 1, { setting_label: "Cálido" }),
                 o("o-cool", "g-tono", "demo-nodisp", "cool", "ajuste", 2, { setting_label: "Frío" }));
  }
  if (conf.conNuevo){
    groups.push(g("g-nuevo", "demo-sin", "nuevo", "Nuevo", "opcional", "una", 1, null, 1));
    options.push(o("o-nuevo", "g-nuevo", "demo-sin", "n1", "ajuste", 1, { setting_label: "Uno" }));
  }
  const malformedGroups = groups.map(x => Object.assign({}, x, { code: "" }));

  /* Consulta cancelable como en supabase-js. */
  function query(vista){
    const st = { from: 0, to: 9999, signal: null, ordered: false };
    const modo = conf.modo || "normal";
    const anomala = modo !== "normal" && (!conf.soloOpciones || vista === "catalog_component_options");
    const b = {
      select(){ return b; }, order(){ st.ordered = true; return b; },
      range(from, to){ st.from = from; st.to = to; return b; },
      abortSignal(s){ st.signal = s; return b; },
      then(onDone, onFail){
        log.calls.push({ vista, from: st.from, to: st.to });
        return new Promise((done, fail) => {
          if (anomala && modo === "rechazo") return fail(new Error("Fallo de red simulado"));
          if (anomala && modo === "colgada") return;
          let aborted = false, timer = null;
          const ignoraAborto = anomala && modo === "tardia";
          if (st.signal) st.signal.addEventListener("abort", () => {
            aborted = true;
            if (!ignoraAborto){ clearTimeout(timer); done({ data: null, error: { message: "AbortError" } }); }
          });
          timer = setTimeout(() => {
            if (aborted) log.tardias.push(vista);
            if (anomala && modo === "error") return done({ data: null, error: { message: "Fallo simulado" } });
            if (anomala && modo === "sin_arreglo") return done({ data: { no: "lista" }, error: null });
            const base = vista === "catalog_component_groups" ? (anomala && modo === "malformada" ? malformedGroups : groups) : options;
            const rows = base.slice().sort((a, c) => (a.id < c.id ? -1 : 1)).slice(st.from, st.to + 1);
            done({ data: JSON.parse(JSON.stringify(rows)), error: null });
          }, anomala && modo === "tardia" ? 5500 : (Number(conf.retraso) || 5));
        }).then(onDone, onFail);
      }
    };
    return b;
  }
  /* catalog_products: acabados sintéticos, productos fuera de la lista y fallos de la lectura por identificadores. */
  const FINISHES = [{ code: "11", name: "Black", reference_code: "R-11", is_default: false }, { code: "25", name: "Beige", reference_code: "R-25", is_default: true }];
  function patchProducts(res, st){
    if (st.ids){ log.productosPorId.push(st.ids.slice()); if (conf.errorPorId) return { data: null, error: { message: "Fallo simulado" } }; }
    if (!res || !Array.isArray(res.data)) return res;
    let rows = res.data;
    if (conf.fuera && (!st.filtered || (st.ids && conf.ausenteSiempre))) rows = rows.filter(r => !conf.fuera.includes(r.id));
    if (conf.refs) rows = rows.map(r => (Object.prototype.hasOwnProperty.call(conf.refs, r.id) ? Object.assign({}, r, { reference_code: conf.refs[r.id] }) : r));
    if (conf.nombres) rows = rows.map(r => (Object.prototype.hasOwnProperty.call(conf.nombres, r.id) ? Object.assign({}, r, { name: conf.nombres[r.id] }) : r));
    if (conf.roles) rows = rows.map(r => (Object.prototype.hasOwnProperty.call(conf.roles, r.id) ? Object.assign({}, r, { catalog_role: conf.roles[r.id] }) : r));
    rows = rows.map(r => (r.id === "demo-pub" && conf.acabados ? Object.assign({}, r, { finish_options: FINISHES })
      : r.id === "demo-cot" && conf.acabadoComp ? Object.assign({}, r, { finish_options: [{ code: "11", name: "Negro", reference_code: "C-11", is_default: true }] }) : r));
    return Object.assign({}, res, { data: rows });
  }
  const productsProxy = (b, st = { filtered: false, ids: null }) => new Proxy(b, { get(t, k){
    if (k === "then") return (a, c) => t.then(res => patchProducts(res, st)).then(a, c);
    const v = t[k];
    return typeof v === "function" ? (...args) => {
      if (k === "in" || k === "eq"){ st.filtered = true; if (k === "in") st.ids = args[1]; }
      const r = v.apply(t, args);
      return r && typeof r.then === "function" ? productsProxy(r, st) : r;
    } : v;
  } });
  const originalFrom = supabaseClient.from.bind(supabaseClient);
  supabaseClient.from = (name) => (name === "catalog_component_groups" || name === "catalog_component_options") ? query(name)
    : (name === "catalog_products" && (conf.acabados || conf.fuera || conf.acabadoComp || conf.errorPorId || conf.roles || conf.refs || conf.nombres)) ? productsProxy(originalFrom(name)) : originalFrom(name);

  /* line_configuration_resolve controlable (cancelable como en supabase-js). */
  const originalRpc = supabaseClient.rpc.bind(supabaseClient);
  supabaseClient.rpc = (fn, args) => {
    if (fn === "catalog_published_prices" && conf.precios){
      log.precios.push(args && args.p_product_ids ? args.p_product_ids.slice() : null);
      const fail = conf.preciosError && log.precios.length > 1;
      const ids = args && args.p_product_ids;
      const rows = Object.keys(conf.precios).filter(id => !ids || ids.includes(id)).map(id => {
        const c = conf.precios[id], status = c.status || "published";
        return { product_id: id, price_amount: status === "published" ? c.amount : null, currency: "USD", price_status: status, includes_itbis: true, itbis_rate: 0.18, es_demo: false };
      });
      return { then: (a, c) => Promise.resolve(fail ? { data: null, error: { message: "Fallo simulado de precios" } } : { data: rows, error: null }).then(a, c) };
    }
    if (fn !== "line_configuration_resolve" || !conf.validacion) return originalRpc(fn, args);
    log.validaciones.push(JSON.parse(JSON.stringify(args)));
    const n = log.validaciones.length;
    const modo = (conf.modosVal || [])[n - 1] || conf.validacion;
    const retraso = (conf.retrasosVal || [])[n - 1] || 5;
    let signal = null;
    const b = {
      abortSignal(sg){ signal = sg; return b; },
      then(onDone, onFail){
        return new Promise((done, fail) => {
          if (modo === "rechazo") return fail(new Error("Fallo de red simulado"));
          if (modo === "colgada") return;
          let aborted = false, timer = null;
          const ignoraAborto = modo === "tardia";
          if (signal) signal.addEventListener("abort", () => { aborted = true; if (!ignoraAborto){ clearTimeout(timer); done({ data: null, error: { message: "AbortError" } }); } });
          timer = setTimeout(() => {
            if (aborted) log.tardias.push("validacion " + n);
            if (modo === "error") return done({ data: null, error: { message: "Fallo simulado" } });
            if (modo === "pendiente" || modo === "tardia") return done({ data: { status: "pendiente", reasons: [{ message: "Una opción elegida en «Fuente» ya no está disponible." }], notices: [], items: [], summary: "" }, error: null });
            done({ data: { status: "completa", reasons: [], notices: [], items: [], summary: "" }, error: null });
          }, modo === "tardia" ? 5500 : retraso);
        }).then(onDone, onFail);
      }
    };
    return b;
  };
})();
