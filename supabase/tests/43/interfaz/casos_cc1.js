const detail = () => {
  const d = D();
  return { prices: d.querySelectorAll(".sp-price").length,
           inputsEnabled: [...d.querySelectorAll(".dp-qty-input, .dp-qty-increment, .remove-product-btn")].filter(e => !e.disabled).length,
           archive: vis(d.getElementById("archive-btn")), addNav: vis(d.getElementById("project-add-products")),
           quote: vis(d.getElementById("request-quote-btn")), summary: vis(d.getElementById("summary-link")),
           priceSummary: txt(d.getElementById("products-price-summary")), view: vis(d.getElementById("project-view")),
           calls: priceCalls(W()), errors: W().__mock.errors };
};
/* CC1: Gratis sin proyectos — solo el aviso de planes, sin ninguna consulta de proyectos, líneas ni solicitudes. */
const PGATE = "Los proyectos, los presupuestos y las solicitudes de cotización están incluidos en los planes Individual y Estudio.";
const projectQueries = (w) => w.__mock.calls.filter(c => /^select:(projects|project_products|rfqs)$/.test(c));
const gateCase = (name, url, extra) => add("Proyectos · Gratis (CC1)", name, async () => {
  await open(url, 1300);
  const g = gate("#projects-plan-gate, #plan-gate");
  const o = { g, queries: projectQueries(W()), crumb: vis(D().querySelector(".breadcrumb")), errors: W().__mock.errors };
  const more = extra ? extra(o) : true;
  return { ok: g.visible && g.title === PGATE && eqJ(g.buttons, ["Ver planes→planes.html"]) && o.queries.length === 0 && !o.crumb && o.errors.length === 0 && more, got: o };
});
gateCase("Mis proyectos (con datos): solo el aviso", "proyectos.html?pro=0", (o) => {
  o.filters = vis(D().getElementById("filter-active")); o.cards = D().querySelectorAll("#projects-grid .provider-card").length;
  return !o.filters && o.cards === 0;
});
gateCase("Mis proyectos (sin datos): solo el aviso", "proyectos.html?pro=0&datos=sin", (o) => !vis(D().getElementById("filter-active")));
gateCase("Detalle de un proyecto activo: solo el aviso", `proyectos-detalle.html?id=${P1}&pro=0`, (o) => { o.view = vis(D().getElementById("project-view")); return !o.view; });
gateCase("Detalle de un proyecto archivado: solo el aviso", `proyectos-detalle.html?id=${P2}&pro=0`, (o) => !vis(D().getElementById("project-view")));
gateCase("Presupuesto: solo el aviso", `proyectos-resumen.html?id=${P1}&pro=0`, (o) => !vis(D().getElementById("summary-content")) && !vis(D().getElementById("ps-print-btn")));
gateCase("Crear proyecto: solo el aviso", "proyectos-cotizacion.html?mode=save&pro=0", (o) => !vis(D().getElementById("view-save")) && !vis(D().getElementById("view-send")));
gateCase("Solicitar cotización de un proyecto: solo el aviso", `proyectos-cotizacion.html?id=${P1}&pro=0`, (o) => !vis(D().getElementById("view-send")));
add("Proyectos · Gratis (CC1)", "Fallo de acceso: aviso de recarga, sin contenido ni consultas", async () => {
  await open("proyectos.html?pro=err", 1300);
  const g = gate("#projects-plan-gate");
  const o = { g, queries: projectQueries(W()) };
  return { ok: g.visible && g.title === "No pudimos comprobar tu acceso." && eqJ(g.buttons, ["Recargar"]) && o.queries.length === 0, got: o };
});

/* CC1: navegación y Mi cuenta */
const menu = () => {
  const d = D();
  const item = (sel) => { const el = d.querySelector(sel); return el ? (el.hidden ? "oculto" : "visible") : "no existe"; };
  return { proyectos: item('#account-menu-panel a[href="proyectos.html?status=active"]:not(#account-menu-active-project)'),
           activo: item("#account-menu-active-project"), solicitudes: item('#account-menu-panel a[href="proyectos.html?status=requested"]'),
           moodboard: item("#account-menu-moodboard"), pie: d.querySelectorAll('.site-footer a[href="proyectos.html"]').length };
};
const menuCase = (name, qs, exp) => add("Navegación (CC1)", name, async () => {
  await open(`catalogo.html?${qs}`, 1300);
  const o = { ...menu(), queries: projectQueries(W()), errors: W().__mock.errors };
  const ok = ["proyectos", "activo", "solicitudes", "moodboard", "pie"].every(k => o[k] === exp[k]) && (exp.noQueries ? o.queries.length === 0 : true) && o.errors.length === 0;
  return { ok, got: o };
});
menuCase("Gratis: sin enlaces de proyectos (menú y pie), con «Mi moodboard», sin consultas", "pro=0",
  { proyectos: "oculto", activo: "oculto", solicitudes: "oculto", moodboard: "visible", pie: 0, noQueries: true });
menuCase("Individual: enlaces de proyectos y «Mi moodboard»", "pro=1",
  { proyectos: "visible", activo: "visible", solicitudes: "visible", moodboard: "visible", pie: 1 });
menuCase("Sin sesión: sin menú; el pie conserva «Mis proyectos»", "rol=anon",
  { proyectos: "no existe", activo: "no existe", solicitudes: "no existe", moodboard: "no existe", pie: 1 });
menuCase("Distribuidor: sin proyectos ni moodboard", "rol=supplier",
  { proyectos: "no existe", activo: "no existe", solicitudes: "no existe", moodboard: "no existe", pie: 0 });
menuCase("Mobau: sin proyectos ni moodboard", "rol=mobau",
  { proyectos: "no existe", activo: "no existe", solicitudes: "no existe", moodboard: "no existe", pie: 0 });
menuCase("Fallo de acceso: sin enlaces de proyectos ni moodboard", "pro=err",
  { proyectos: "oculto", activo: "oculto", solicitudes: "oculto", moodboard: "oculto", pie: 0, noQueries: true });
add("Mi cuenta (CC1)", "Gratis: solo el perfil, sin proyectos ni solicitudes", async () => {
  await open("cuenta.html?pro=0", 1300);
  const d = D();
  const o = { secciones: d.querySelectorAll("[data-pro-only]").length, intro: txt(d.getElementById("account-intro")), perfil: vis(d.getElementById("profile-box")),
              queries: projectQueries(W()), errors: W().__mock.errors };
  return { ok: o.secciones === 0 && o.intro === "Tu perfil profesional en Mobau." && o.perfil && o.queries.length === 0 && o.errors.length === 0, got: o };
});
add("Mi cuenta (CC1)", "Gratis sin perfil: completarlo es opcional", async () => {
  await open("cuenta.html?pro=0&pp=none", 1300);
  const o = { vacio: vis(D().getElementById("profile-empty")), texto: txt(D().getElementById("profile-empty-text")) };
  return { ok: o.vacio && o.texto === "Complétalo cuando quieras para identificar tu cuenta profesional en Mobau.", got: o };
});
add("Mi cuenta (CC1)", "Individual: igual que antes", async () => {
  await open("cuenta.html?pro=1", 1300);
  const o = { secciones: D().querySelectorAll("[data-pro-only]").length, queries: projectQueries(W()).length };
  return { ok: o.secciones === 3 && o.queries > 0, got: o };
});

/* CC1: Mi moodboard (solo informativo) */
const mbCase = (name, qs, exp) => add("Moodboard (CC1)", name, async () => {
  await open(`moodboard.html?${qs}`, 1200);
  if (exp.redirect) return { ok: page() === exp.redirect, got: { page: page() } };
  const box = D().getElementById("moodboard-info");
  const o = { visible: vis(box), texto: txt(box), controles: D().querySelectorAll("main input, main button, main select, main textarea, main form").length,
              escrituras: W().__mock.writes.length, h1: txt(D().querySelector("h1")) };
  return { ok: o.visible && o.h1 === "Mi moodboard" && o.texto.includes("Próximamente podrás reunir productos del catálogo en un moodboard.") && o.controles === 0 && o.escrituras === 0, got: o };
});
mbCase("Gratis: pantalla informativa, sin controles ni escrituras", "pro=0", {});
mbCase("Individual: pantalla informativa", "pro=1", {});
mbCase("Distribuidor: redirige a su panel", "rol=supplier", { redirect: "panel-distribuidor.html" });
mbCase("Mobau: redirige a moderación", "rol=mobau", { redirect: "moderacion.html" });
mbCase("Sin sesión: a iniciar sesión", "rol=anon", { redirect: "acceso.html" });

/* CC1: perfil de Gratis no bloqueante y caché de acceso */
const nextCase = (name, qs, opts, expUrl) => add("Perfil y destino (CC1)", name, async () => {
  await open(`index.html?${qs}`, 900);
  const s = await G("MobauAuth").getSession();
  const r = await G("MobauAccess").resolveNext(s, opts);
  return { ok: r.url === expUrl, got: r };
});
nextCase("Gratis sin perfil: entra sin completarlo", "pro=0&pp=none", {}, "index.html");
nextCase("Gratis sin perfil que pidió Individual: completa el perfil para la activación", "pro=0&pp=none", { explicitPlan: "individual" }, "inscripcion-profesional.html?paso=perfil&plan=individual");
nextCase("Individual habilitado sin perfil: lo completa (lo necesitan las solicitudes)", "pro=1&pp=none", {}, "inscripcion-profesional.html?paso=perfil");
nextCase("Gratis con perfil: destino normal", "pro=0", {}, "index.html");
add("Perfil y destino (CC1)", "Sesión iniciada en otra pestaña: el acceso se vuelve a pedir", async () => {
  const w = await open("catalogo.html?rol=anon", 1200);
  const before = await G("MobauAccess").access();
  w.__mock.login("a");
  const after = await G("MobauAccess").access();
  return { ok: before === "anon" && after === "pro", got: { before, after } };
});

/* 43-C1: nombre y apellidos */
add("Identidad (43-C1)", "Alta del perfil: nombre y apellidos por separado", async () => {
  const w = await open("inscripcion-profesional.html?pro=0&pp=none", 1300);
  const d = D();
  const set = (id, v) => { d.getElementById(id).value = v; };
  set("pp-first-name", "  Ana "); set("pp-last-name", " Rosario   Pérez "); set("pp-type", "arquitecto"); set("pp-city", "Santo Domingo");
  d.getElementById("pp-form").requestSubmit();
  await settle(400);
  const ins = w.__mock.writes.find(x => x.table === "professional_profiles" && x.op === "insert");
  const p = ins && ins.payload || {};
  return { ok: p.first_name === "Ana" && p.last_name === "Rosario Pérez" && p.professional_name === "Ana Rosario Pérez", got: { payload: p, sinNombre: !d.getElementById("pp-name") } };
});
add("Identidad (43-C1)", "Perfil anterior: no se divide; se pide separado y se conserva hasta guardar", async () => {
  const w = await open("inscripcion-profesional.html?pro=1&pp=legacy", 1300);
  const d = D();
  d.getElementById("personal-edit-btn").click();
  await settle(200);
  const o = { hint: txt(d.getElementById("personal-edit-name-hint")), hintVisible: !d.getElementById("personal-edit-name-hint").hidden,
              nombre: d.getElementById("personal-edit-first-name").value, apellidos: d.getElementById("personal-edit-last-name").value,
              vista: txt(d.getElementById("personal-view-name")) };
  d.getElementById("personal-edit-first-name").value = "Ana";
  d.getElementById("personal-edit-last-name").value = "Rosario";
  d.getElementById("personal-save-btn").click();
  await settle(400);
  const upd = w.__mock.writes.find(x => x.table === "professional_profiles" && x.op === "update");
  o.payload = upd && upd.payload;
  return { ok: o.hintVisible && o.hint === "Tu nombre actual es «Ana Demo». Indícalo separado en nombre y apellidos." && o.nombre === "" && o.apellidos === "" && o.vista === "Ana Demo"
    && o.payload && o.payload.first_name === "Ana" && o.payload.last_name === "Rosario" && o.payload.professional_name === "Ana Rosario", got: o };
});
add("Identidad (43-C1)", "Perfil con nombre y apellidos: se precargan", async () => {
  await open("inscripcion-profesional.html?pro=1&pp=split", 1300);
  const d = D();
  d.getElementById("personal-edit-btn").click();
  await settle(200);
  const o = { nombre: d.getElementById("personal-edit-first-name").value, apellidos: d.getElementById("personal-edit-last-name").value, hintVisible: !d.getElementById("personal-edit-name-hint").hidden };
  return { ok: o.nombre === "Ana" && o.apellidos === "Rosario" && !o.hintVisible, got: o };
});
add("Identidad (43-C1)", "Crear cuenta: el borrador guarda nombre y apellidos", async () => {
  localStorage.removeItem("mobau_signup_draft");
  await open("crear-cuenta.html?plan=gratis&rol=anon", 1200);
  const d = D();
  const set = (id, v) => { d.getElementById(id).value = v; };
  set("cc-first-name", "Ana"); set("cc-last-name", "Rosario"); set("cc-type", "arquitecto"); set("cc-city", "Santo Domingo"); set("cc-phone", "809 555 0142");
  d.getElementById("cc-form").requestSubmit();
  await settle(500);
  let draft = null;
  try { draft = JSON.parse(localStorage.getItem("mobau_signup_draft")); } catch (e) {}
  const p = draft && draft.profile || {};
  localStorage.removeItem("mobau_signup_draft");
  return { ok: p.first_name === "Ana" && p.last_name === "Rosario" && p.professional_name === "Ana Rosario", got: { profile: p } };
});
add("Textos (O1)", "Catálogo: nota del asterisco visible arriba", async () => {
  await open("catalogo.html?pro=0", 1200);
  const n = D().getElementById("catalog-price-note");
  return { ok: vis(n) && txt(n) === "*Los planes Individual y Estudio permiten consultar los precios publicados y solicitar cotizaciones. No todos los productos tienen precio publicado: algunos requieren cotización o están pendientes de confirmación.", got: { texto: txt(n) } };
});
