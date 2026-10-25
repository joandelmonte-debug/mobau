/* Ensayo 46 · bloque 4 (interfaz, sin red). Se carga después de
   supabase-client.js, sobre el cliente simulado de CC1
   (supabase/tests/43/interfaz/mock-supabase-cc1.js), y sustituye solo la
   llamada line_configuration_resolve por una resolución sintética:
     fuente = comp   → completa, con un componente aparte (Módulo LED, 1 por unidad)
     fuente = calida → completa, solo un ajuste (Cálida)
     otra opción     → pendiente (opción no disponible)
   Devuelve, como supabase-js, un objeto con abortSignal(señal) que se puede
   esperar; al cancelar, responde con un error (salvo ignoraAborto).
   Comportamiento en sessionStorage "__resolucion46" (JSON), para todas las
   llamadas o, con "porOpcion", según la opción elegida en «fuente»:
     {}                                   normal
     {"modo": "error"}                    responde con error
     {"modo": "rechazo"}                  la promesa falla (p. ej. sin red)
     {"retraso": ms}                      responde tarde
     {"porOpcion": {"comp": {"modo": "colgada", "ignoraAborto": true}}}
                                          no responde nunca, ni al cancelar
     {"porOpcion": {"comp": {"retraso": 5500, "ignoraAborto": true}}}
                                          responde después del límite de la página
   Registra las llamadas en window.__resolveCalls, las respuestas entregadas
   después de una cancelación en window.__respuestasTardias y los errores sin
   capturar de la página en window.__sinCapturar. */
(() => {
  const original = supabaseClient.rpc.bind(supabaseClient);
  let conf = {};
  try { conf = JSON.parse(sessionStorage.getItem("__resolucion46") || "{}"); } catch (e) { conf = {}; }
  window.__resolveCalls = [];
  window.__respuestasTardias = [];
  window.__sinCapturar = [];
  window.addEventListener("unhandledrejection", e => window.__sinCapturar.push(String(e.reason)));
  window.addEventListener("error", e => window.__sinCapturar.push(String(e.message)));

  const fuente = configuration => {
    const choice = ((configuration && configuration.choices) || []).find(c => c.group === "fuente");
    return (choice && choice.options) || [];
  };

  function resolve(configuration){
    const opts = fuente(configuration);
    if (opts.includes("comp")) return { status: "completa", summary: "Fuente: Módulo LED", reasons: [], notices: [],
      items: [{ kind: "componente", group: "fuente", option: "comp", product_id: "demo-cot", product_name: "Módulo LED",
                supply: "aparte", quantity: 1, quantity_mode: "fija" }] };
    if (opts.includes("calida")) return { status: "completa", summary: "Fuente: Cálida", reasons: [], notices: [],
      items: [{ kind: "ajuste", group: "fuente", option: "calida", setting_label: "Cálida" }] };
    return { status: "pendiente", summary: "", notices: [], items: [],
      reasons: [{ code: "opcion_no_disponible", message: "Una opción elegida en «Fuente» ya no está disponible." }] };
  }

  supabaseClient.rpc = (fn, args) => {
    if (fn !== "line_configuration_resolve") return original(fn, args);
    window.__resolveCalls.push(args);
    const porOpcion = conf.porOpcion || {};
    const plan = fuente(args.p_configuration).map(o => porOpcion[o]).find(Boolean) || conf;
    let signal = null;
    let aborted = false;
    const run = () => new Promise((done, fail) => {
      if (plan.modo === "rechazo") return fail(new Error("Fallo de red simulado"));
      let timer = null;
      const onAbort = () => { aborted = true; if (!plan.ignoraAborto){ clearTimeout(timer); done({ data: null, error: { message: "AbortError" } }); } };
      if (signal) signal.addEventListener("abort", onAbort);
      if (plan.modo === "colgada") return;
      const result = plan.modo === "error"
        ? { data: null, error: { message: "Fallo simulado" } }
        : { data: resolve(args.p_configuration), error: null };
      timer = setTimeout(() => {
        if (aborted) window.__respuestasTardias.push(fuente(args.p_configuration).join("+"));
        done(result);
      }, plan.retraso || 0);
    });
    const query = {
      abortSignal(s){ signal = s; return query; },
      then(onDone, onFail){ return run().then(onDone, onFail); }
    };
    return query;
  };
})();
