/* Ensayo 46 · bloque 4 · proyecto y cotización (interfaz, sin red).
   Se carga después de supabase-client.js, sobre el cliente simulado de CC1
   (supabase/tests/43/interfaz/mock-supabase-cc1.js, con rol=individual&pro=1&uid=a),
   y sustituye solo:
   - las tablas project_products y rfqs, con datos sintéticos y estado en
     memoria (insert, update y delete modifican las filas de esta carga);
   - las llamadas project_line_states y line_configuration_resolve.
   Proyectos de CC1: P1 activo, P2 archivado sin copia, P3 archivado con RFQ.
     P1: misma referencia y acabado (demo-pub, sin acabado) sin configuración,
         con A (fuente: comp) y con B (fuente: calida); demo-cot sin configurar;
         con «conPendiente», además X (fuente: zzz, pendiente).
     P2: una línea con A (información actual, sin copia).
     P3: línea actual con A y cantidad 9; su RFQ guarda una copia distinta
         (cantidad 4, «Fuente: Módulo LED (enviado)», 4 ud. en total).
   Comportamiento en sessionStorage "__proyecto46" (JSON):
     estados: "normal" | "error" | "rechazo" | "colgada" (no termina, ni al
              cancelar) | "tardia" (responde a los 5,5 s, sin atender la
              cancelación) | "ausente" (falta la línea A) | "desconocido"
              (la línea A con un estado que no existe)
     retrasos: [ms de la 1.ª consulta, de la 2.ª, …] (atienden la cancelación)
     conPendiente: true
     sinConfigPendiente: true (demo-cot, sin configuración, vuelve como pendiente)
   Registro: window.__escrituras46 (insert/update/delete), window.__estadosCalls,
   window.__resolveCalls, window.__respuestasTardias, window.__sinCapturar. */
(() => {
  const UID = "aaaaaaaa-0000-4000-8000-00000000000a";
  const P = (n) => `0000000${n}-1111-4111-8111-111111111111`;
  let conf = {};
  try { conf = JSON.parse(sessionStorage.getItem("__proyecto46") || "{}"); } catch (e) { conf = {}; }
  window.__escrituras46 = [];
  window.__estadosCalls = 0;
  window.__resolveCalls = [];
  window.__respuestasTardias = [];
  window.__sinCapturar = [];
  window.addEventListener("unhandledrejection", e => window.__sinCapturar.push(String(e.reason)));
  window.addEventListener("error", e => window.__sinCapturar.push(String(e.message)));

  const now = new Date().toISOString();
  const A = { choices: [{ path: [], group: "fuente", options: ["comp"] }] };
  const B = { choices: [{ path: [], group: "fuente", options: ["calida"] }] };
  const X = { choices: [{ path: [], group: "fuente", options: ["zzz"] }] };
  const line = (id, project, product_id, quantity, configuration, order) => ({
    id, project_id: P(project), product_id, finish_code: null, configuration: configuration || null,
    config_key: configuration ? `clave-${id}` : "", quantity, unit: "ud.", notes: null, room_or_area: null,
    selected_for_rfq: true, created_at: now, order_position: order, area_id: null });   // area_id: columna de 47-01 (sin áreas, siempre null)
  const lines = [
    line("l-sin", 1, "demo-pub", 2, null, 1),
    line("l-a", 1, "demo-pub", 3, A, 2),
    line("l-b", 1, "demo-pub", 1, B, 3),
    line("l-cot", 1, "demo-cot", 1, null, 4),
    line("l-p2", 2, "demo-pub", 1, A, 1),
    line("l-p3", 3, "demo-pub", 9, A, 1)
  ];
  /* conNota: nota técnica en la línea viva l-sin y en la línea de la copia de la RFQ (con HTML y salto de línea). */
  if (conf.conNota) lines.find(l => l.id === "l-sin").notes = "Montar a 2,40 m <b>no negrita</b>\nsegunda línea";
  if (conf.conPendiente) lines.push(line("l-x", 1, "demo-pub", 1, X, 5));
  const rfqs = [{ id: "rfq-p3", project_id: P(3), requester_user_id: UID, requester_company: "Estudio", status: "submitted", created_at: now,
    lines_snapshot: { version: 1, taken_at: now, project_id: P(3), distributors: [{ distributor_id: "spectro", distributor_name: "Spectro Lighting", lines: [{
      line_id: "l-p3", product_id: "demo-pub", product_name: "Publicado", finish_code: null, quantity: 4, unit: "ud.",
      configuration: A, config_key: "clave-l-p3", config_status: "completa", config_summary: "Fuente: Módulo LED (enviado)",
      config_reasons: [], config_notices: [],
      items: [{ kind: "componente", group: "fuente", option: "comp", product_id: "demo-cot", product_name: "Módulo LED",
                supply: "aparte", quantity: 1, quantity_mode: "fija", factor: 1, unit: "ud.", total_quantity: 4, quantity_status: "calculada" }] }] }] } }];
  if (conf.conNota) rfqs[0].lines_snapshot.distributors[0].lines[0].notes = "Nota enviada <i>x</i>\nlínea 2";

  /* Resolución sintética (mismo criterio que mock-resolucion-46.js). n = número de consulta. */
  function resolve(configuration, n){
    const choice = ((configuration && configuration.choices) || []).find(c => c.group === "fuente");
    const opts = (choice && choice.options) || [];
    const tag = n ? ` (consulta ${n})` : "";
    if (opts.includes("comp")) return { status: "completa", review: "sin_cambios", summary: `Fuente: Módulo LED${tag}`, reasons: [], notices: [],
      items: [{ kind: "componente", group: "fuente", option: "comp", product_id: "demo-cot", product_name: "Módulo LED", supply: "aparte", quantity: 1, quantity_mode: "fija" }] };
    if (opts.includes("calida")) return { status: "completa", review: "sin_cambios", summary: `Fuente: Cálida${tag}`, reasons: [], notices: [],
      items: [{ kind: "ajuste", group: "fuente", option: "calida", setting_label: "Cálida" }] };
    return { status: "pendiente", review: "revisar", summary: "", notices: [], items: [],
      reasons: [{ code: "opcion_no_disponible", message: "Una opción elegida en «Fuente» ya no está disponible." }] };
  }
  function lineStates(projectId, n){
    return lines.filter(l => l.project_id === projectId)
      .filter(l => !(conf.estados === "ausente" && l.id === "l-a"))
      .map(l => {
        const base = l.configuration ? resolve(l.configuration, n)
          : { status: "no_requiere", review: "sin_cambios", summary: "", reasons: [], notices: [], items: [] };
        if (conf.estados === "desconocido" && l.id === "l-a") base.status = "otro";
        if (conf.sinConfigPendiente && l.id === "l-cot") Object.assign(base, { status: "pendiente", review: "revisar",
          reasons: [{ code: "configuracion_requerida", message: "Este producto ahora requiere elegir «Fuente»." }] });
        return Object.assign({ line_id: l.id, product_id: l.product_id, finish_code: l.finish_code, config_key: l.config_key }, base);
      });
  }

  /* Consulta que se puede cancelar como en supabase-js (abortSignal). */
  function cancellable(plan, produce){
    let signal = null, aborted = false;
    const run = () => new Promise((done, fail) => {
      if (plan.modo === "rechazo") return fail(new Error("Fallo de red simulado"));
      let timer = null;
      const onAbort = () => { aborted = true; if (!plan.ignoraAborto){ clearTimeout(timer); done({ data: null, error: { message: "AbortError" } }); } };
      if (signal) signal.addEventListener("abort", onAbort);
      if (plan.modo === "colgada") return;
      timer = setTimeout(() => {
        const result = plan.modo === "error" ? { data: null, error: { message: "Fallo simulado" } } : { data: produce(), error: null };
        if (aborted) window.__respuestasTardias.push(plan.etiqueta || "consulta");
        done(result);
      }, plan.retraso || 0);
    });
    const query = { abortSignal(s){ signal = s; return query; }, then(onDone, onFail){ return run().then(onDone, onFail); } };
    return query;
  }

  const originalRpc = supabaseClient.rpc.bind(supabaseClient);
  supabaseClient.rpc = (fn, args) => {
    if (fn === "project_line_states"){
      const n = ++window.__estadosCalls;
      const modo = conf.estados || "normal";
      const plan = modo === "colgada" ? { modo, ignoraAborto: true }
        : modo === "tardia" ? { retraso: 5500, ignoraAborto: true, etiqueta: `consulta ${n}` }
        : { modo, retraso: (conf.retrasos || [])[n - 1] || 0 };
      return cancellable(plan, () => lineStates(args.p_project_id, n));
    }
    if (fn === "line_configuration_resolve"){
      window.__resolveCalls.push(args);
      return cancellable({}, () => resolve(args.p_configuration, 0));
    }
    return originalRpc(fn, args);
  };

  /* project_products y rfqs: cadena de consulta mínima de supabase-js. */
  function table(name){
    const st = { op: "select", filters: [], payload: null, single: false, notNull: [] };
    const b = {
      select(){ return b; }, order(){ return b; }, limit(){ return b; }, abortSignal(){ return b; },
      eq(col, val){ st.filters.push(["eq", col, val]); return b; },
      is(col, val){ st.filters.push(["is", col, val]); return b; },
      in(col, val){ st.filters.push(["in", col, val]); return b; },
      not(col){ st.notNull.push(col); return b; },
      maybeSingle(){ st.single = true; return b; }, single(){ st.single = true; return b; },
      insert(payload){ st.op = "insert"; st.payload = payload; return b; },
      update(payload){ st.op = "update"; st.payload = payload; return b; },
      delete(){ st.op = "delete"; return b; },
      then(onDone, onFail){ return new Promise(r => setTimeout(r, 5)).then(() => runTable(name, st)).then(onDone, onFail); }
    };
    return b;
  }
  const matches = (row, st) => st.filters.every(([op, col, val]) =>
    op === "eq" ? row[col] === val : op === "is" ? row[col] === val : (val || []).includes(row[col]))
    && st.notNull.every(col => row[col] !== null && row[col] !== undefined);
  const result = (rows, st) => ({ data: st.single ? (rows[0] || null) : rows, error: null });
  function runTable(name, st){
    const store = name === "project_products" ? lines : rfqs;
    if (st.op === "insert"){
      const row = name === "project_products"
        ? Object.assign({ id: `nuevo-${store.length + 1}`, finish_code: null, configuration: null, config_key: "", selected_for_rfq: true, created_at: now, order_position: 0 }, st.payload)
        : Object.assign({ id: `rfq-nueva-${store.length + 1}`, created_at: now, lines_snapshot: null }, st.payload);
      store.push(row);
      window.__escrituras46.push({ tabla: name, op: "insert", fila: JSON.parse(JSON.stringify(st.payload)) });
      return result([row], st);
    }
    const hits = store.filter(row => matches(row, st));
    if (st.op === "update"){
      /* errorNota: «line_note_archived» o «line_note_too_long» (como el trigger de 46-06): rechaza los UPDATE de notes. */
      if (conf.errorNota && "notes" in st.payload){
        window.__escrituras46.push({ tabla: name, op: "update-rechazado", ids: hits.map(r => r.id), cambios: JSON.parse(JSON.stringify(st.payload)) });
        return { data: null, error: { code: conf.errorNota === "line_note_archived" ? "42501" : "23514", message: "rechazo del servidor", hint: conf.errorNota } };
      }
      hits.forEach(row => Object.assign(row, st.payload));
      window.__escrituras46.push({ tabla: name, op: "update", ids: hits.map(r => r.id), cambios: JSON.parse(JSON.stringify(st.payload)) });
      return result(hits, st);
    }
    if (st.op === "delete"){
      hits.forEach(row => store.splice(store.indexOf(row), 1));
      window.__escrituras46.push({ tabla: name, op: "delete", ids: hits.map(r => r.id) });
      return { data: null, error: null };
    }
    const sorted = name === "rfqs" ? hits.slice().reverse() : hits.slice().sort((a, b) => a.order_position - b.order_position);
    return result(sorted.map(r => JSON.parse(JSON.stringify(r))), st);
  }
  const originalFrom = supabaseClient.from.bind(supabaseClient);
  supabaseClient.from = (name) => (name === "project_products" || name === "rfqs") ? table(name) : originalFrom(name);
})();
