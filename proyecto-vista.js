/* ============================================================
   MOBAU — Vista del proyecto: filas compactas y áreas opcionales (Punto 47)
   ------------------------------------------------------------
   Pinta proyectos-detalle.html con el diseño aprobado en el prototipo (supabase/tests/47/interfaz). Un proyecto
   sin áreas es una lista normal; las áreas aparecen cuando la persona las crea y desaparecen al borrar la última.
   Depende de supabase-client.js, proyectos-data.js (MobauProjects, MobauAreas, MobauLineConfig), seleccion-data.js,
   script.js (catálogo, precios, escapeHtml, showToast) y proyecto-importes.js.

   Todo lo que escribe pasa por proyectos-data.js. Si las áreas no se pudieron comprobar (error de red o permisos),
   la vista lo dice y no permite operar: nunca se muestra como «proyecto sin áreas». Si la migración de áreas aún no
   existe, el proyecto se trabaja como lista sencilla y no aparece ningún control de áreas.
   ============================================================ */
const ProyectoVista = (() => {
  const $ = (s, r = document) => r.querySelector(s);
  const esc = escapeHtml;
  const NOTE_MAX = 1000;
  const ICON = {
    search: '<svg class="i" viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/></svg>',
    note: '<svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 4h10l4 4v12H5z"/><path d="M8.5 11h7M8.5 15h7"/></svg>',
    more: '<svg class="i" viewBox="0 0 24 24" aria-hidden="true"><circle cx="5" cy="12" r="1.2" fill="currentColor"/><circle cx="12" cy="12" r="1.2" fill="currentColor"/><circle cx="19" cy="12" r="1.2" fill="currentColor"/></svg>',
    chev: '<svg class="i" viewBox="0 0 24 24" aria-hidden="true" style="width:16px;height:16px"><path d="M6 9l6 6 6-6"/></svg>',
    plus: '<svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
    check: '<svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>',
    close: '<svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg>',
    areas: '<svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="4" width="7" height="7" rx="1"/><rect x="13" y="4" width="7" height="7" rx="1"/><rect x="4" y="13" width="7" height="7" rx="1"/><rect x="13" y="13" width="7" height="7" rx="1"/></svg>'
  };

  /* ---------- estado ---------- */
  const S = {
    project: null, plan: null, session: null, userId: null,
    areasState: "ready", areas: [], lines: [], states: null, loadError: null,
    isRequested: false, fromCopy: false, pricesOn: false, busy: false,
    collapsed: new Set(), selected: new Set(), filters: { q: "", areas: new Set(), cats: new Set() },
    noteEdit: null, pop: null, renaming: null, infoOpen: false, infoEdit: false, infoError: "", canReactivate: false, reactivateWhy: "",
    open: null, selecting: false, current: null   /* mesa: ficha abierta, modo de selección y área que se está leyendo */
  };
  let loadSeq = 0;
  const hooks = { onPlanGate: null, onLoaded: null };

  const hasAreas = () => S.areasState === "ready" && S.areas.length > 0;
  const ro = () => S.project.status !== "active";
  const prod = id => PRODUCTS.find(p => p.id === id);
  const areaName = id => (id ? ((S.areas.find(a => a.id === id) || {}).name || "Área") : "Sin área");
  const lineById = id => S.lines.find(l => l.id === id);
  const keyOf = l => `${l.productId}|${l.finish || ""}|${selectionConfigurationKey(l.configuration)}`;
  const r2 = n => Math.round(n * 100) / 100;
  const unitOf = l => l.unit || (prod(l.productId) ? getProductUnit(prod(l.productId)) : "ud.");
  const money = n => formatUSD(n);
  const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

  /* ---------- carga ---------- */
  function normalize(row){
    return { id: row.id, productId: row.product_id, finish: row.finish_code || null, configuration: row.configuration || null,
             qty: Number(row.quantity), unit: row.unit, note: row.notes || "", areaId: row.area_id || null, requested: row.requested || null };
  }

  /* Vuelve a leer del servidor lo que hace falta y pinta. quiet: sin parpadeo de «Cargando». */
  async function load(){
    const seq = ++loadSeq;
    const archived = S.project.status === "archived";
    let rows, areas, areaState = "ready", fromCopy = false, error = null;
    if (archived){
      const view = await MobauProjects.getRequestedView(S.project.id);
      rows = view.rows; areas = view.areas; fromCopy = view.fromCopy; error = view.error; areaState = view.areaState || "ready";
    } else {
      const res = await MobauProjects.loadProjectLines(S.project.id);
      rows = res.rows; areas = res.areas.areas || []; areaState = res.areas.state; error = res.error;
    }
    if (seq !== loadSeq) return;
    if (error || !rows){
      S.loadError = { areasFailed: areaState === "error", message: (error && error.message) || "" };
      S.lines = []; S.areas = []; S.states = null;
      render();
      return;
    }
    S.loadError = null;
    S.areasState = areaState === "missing" ? "missing" : "ready";
    S.areas = S.areasState === "ready" ? areas : [];
    S.fromCopy = fromCopy;
    if (!(await whenProductsReady(rows.map(r => r.product_id), { status: "#list" }))) return;
    const states = rows.some(r => r.requested) ? null : await MobauProjects.listLineStates(S.project.id);
    if (seq !== loadSeq) return;
    S.states = states;
    S.lines = rows.map(normalize);
    if (!archived){
      /* Una sola consulta de precios para los productos de las líneas y los componentes de sus configuraciones. */
      const ids = new Set(S.lines.map(l => l.productId));
      if (states) states.forEach(st => (st.items || []).forEach(i => { if (i.kind === "componente" && i.product_id) ids.add(i.product_id); }));
      await loadPriceState([...ids]);
      if (seq !== loadSeq) return;
      if (!MobauAccess.hasProfessionalTools()){ if (hooks.onPlanGate) hooks.onPlanGate(); return; }
    }
    S.pricesOn = !archived && !priceAccessInfo();
    const ids = new Set(S.lines.map(l => l.id));
    S.selected.forEach(id => { if (!ids.has(id)) S.selected.delete(id); });
    if (S.open && !ids.has(S.open)) S.open = null;
    S.filters.areas.forEach(a => { if (a !== "none" && !S.areas.some(x => x.id === a)) S.filters.areas.delete(a); });
    if (!hasAreas()){ S.filters.areas.clear(); S.collapsed.clear(); }
    render();
    if (hooks.onLoaded) hooks.onLoaded();
  }

  /* ---------- importes ---------- */
  const calcCtx = () => ({ priceOf: getPriceInfo, pricesVisible: S.pricesOn, isAvailable: isProductAvailable });
  const calc = l => MobauImportes.line({ product_id: l.productId, quantity: l.qty, configuration: l.configuration },
    S.states ? S.states.get(l.id) || null : null, calcCtx());
  const aggregate = lines => MobauImportes.aggregate(lines.map(calc));

  /* ---------- filtros ---------- */
  const filtering = () => !!(S.filters.q.trim() || S.filters.areas.size || S.filters.cats.size);
  const finishText = l => { const p = prod(l.productId); return p && l.finish ? finishLabel(p, l.finish) : ""; };
  const cfgSummary = l => {
    if (l.requested) return l.requested.config_summary || "";
    const st = S.states ? S.states.get(l.id) : null;
    return st && st.summary ? st.summary : "";
  };
  function visible(l){
    const f = S.filters, p = prod(l.productId);
    if (f.areas.size && !f.areas.has(l.areaId || "none")) return false;
    if (f.cats.size && !(p && f.cats.has(p.categoria))) return false;
    const q = f.q.trim().toLowerCase();
    if (q){
      const hay = [p && p.nombre, p && p.referencia, p && LABELS.marca[p.marca], finishText(l), l.note, hasAreas() ? areaName(l.areaId) : "", cfgSummary(l)].join(" ").toLowerCase();
      if (!q.split(/\s+/).every(w => hay.includes(w))) return false;
    }
    return true;
  }

  /* ---------- piezas de la mesa ---------- */
  /* Dirección B: cada línea es una pieza (foto, nombre, marca y acabado, cantidad e importe); su detalle se abre en una
     ficha gris bajo la fila, con una muesca hacia la pieza. Solo cambia cómo se pinta: las operaciones son las de siempre. */
  const WORDS = ["cero", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez"];
  const word = n => (n <= 10 ? WORDS[n] : String(n));
  const productos = n => (n === 1 ? "Un producto" : `${n <= 10 ? WORDS[n].charAt(0).toUpperCase() + WORDS[n].slice(1) : n} productos`);
  const nw = s => `<span class="nw">${esc(s)}</span>`;
  const qtyText = l => { const u = unitOf(l); return `${u === "ud." ? Math.round(l.qty) : r2(l.qty)} ${u}`; };
  const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* Foto de la línea: la de su acabado si existe; si no, la portada. Si hay acabado y se usa la portada, la ficha lo dice
     junto al acabado («Foto general»: Mobau no sabe qué acabado muestra la portada). Las fotos se ven enteras, sin recortes ni filtros. */
  function photoOf(l){
    const p = prod(l.productId);
    if (!p) return { url: "", general: false };
    const option = l.finish ? (p.acabadosOpciones || []).find(f => f.codigo === l.finish) : null;
    const url = safeUrl((option && option.imagen) || p.imagen);
    return { url, general: !!(url && l.finish && !(option && option.imagen)) };
  }
  function photoHtml(l){
    const p = prod(l.productId), ph = photoOf(l);
    const none = `${p ? productFallbackMarkup(p, 34) : ""}<span class="phc">${esc(p ? (LABELS.categoria[p.categoria] || "Producto") : "Producto")}</span><span class="phs">Sin imagen</span>`;
    if (!ph.url) return `<span class="ph ph-none">${none}</span>`;
    return `<span class="ph"><img src="${esc(ph.url)}" alt="" loading="lazy" referrerpolicy="no-referrer" data-media-fallback><span class="media-fallback">${none}</span></span>`;
  }
  /* Importe breve de la pieza y su aviso (el detalle completo va en la ficha). */
  function tileAmount(l){
    const c = calc(l);
    if (c.status === "oculto") return [`<span class="a muted" title="Los precios se consultan con un plan Individual o Estudio">—</span>`, ""];
    if (c.status === "nodisp") return [`<span class="a muted">No disponible</span>`, `<span class="flag">No suma al importe</span>`];
    if (c.status === "pendiente") return [`<span class="a muted">Sin importe</span>`, `<span class="flag">Configuración pendiente</span>`];
    if (c.status === "completa") return [`<span class="a">${esc(money(c.known))}</span>`, ""];
    if (c.status === "parcial") return [`<span class="a">${esc(money(c.known))}</span>`, `<span class="flag">+ ${c.issues.length} pendiente${c.issues.length > 1 ? "s" : ""}</span>`];
    const info = getPriceInfo(l.productId);
    return [`<span class="a ochre">${info.kind === "quote-required" ? "Bajo cotización" : "Sin precio"}</span>`, ""];
  }
  function tileFlag(l, amountFlag){
    if (amountFlag) return amountFlag;
    const info = (l.configuration || l.requested) ? cfgInfo(l) : null;
    if (info && info.status === "sin_comprobar") return `<span class="flag quiet">Configuración sin comprobar</span>`;
    if (!l.configuration && info && info.status === "pendiente") return `<span class="flag">Configuración pendiente</span>`;
    return "";
  }
  function tileHtml(l){
    const p = prod(l.productId), open = S.open === l.id, picked = S.selected.has(l.id);
    const name = p ? p.nombre : "Producto no disponible";
    const meta = p ? [LABELS.marca[p.marca], finishText(l)].filter(Boolean).join(", ") : `ID: ${l.productId}`;
    const [amount, flag] = tileAmount(l);
    const act = S.selecting && !ro() ? `data-act="pick" aria-pressed="${picked}"` : `data-act="open" aria-expanded="${open}" aria-controls="ficha"`;
    return `<li class="tile${open ? " open" : ""}${picked ? " picked" : ""}" data-id="${esc(l.id)}">
      <span class="tick" aria-hidden="true">${ICON.check}</span>
      <button class="tile-btn" ${act} data-id="${esc(l.id)}">
        ${photoHtml(l)}
        <span class="nm" title="${esc(name)}">${esc(name)}</span>
        <span class="meta">${esc(meta)}</span>
        <span class="fw"><span class="foot"><span class="q">${esc(qtyText(l))}${l.note ? `${ICON.note}<span class="sr">, con nota</span>` : ""}</span>${amount}</span>${tileFlag(l, flag)}</span>
      </button></li>`;
  }

  /* ---------- ficha gris ---------- */
  /* Línea de configuración: estado actual (proyecto vivo) o lo enviado (copia de la RFQ), nunca mezclados. */
  function cfgInfo(l){
    return l.requested ? MobauLineConfig.sent(l.requested) : MobauLineConfig.current(l.configuration, S.states ? S.states.get(l.id) : null);
  }
  function cfgState(l){
    const info = cfgInfo(l);
    const summary = cfgSummary(l) || MobauLineConfig.rawChoices(l.configuration) || "";
    if (info.status === "pendiente") return `<p class="cfg-state"><span class="pbadge warn">Pendiente</span><span class="sum">${esc(info.reasons.join(" "))}</span></p>`;
    if (info.status === "sin_comprobar") return `<p class="cfg-state"><span class="pbadge cot">Sin comprobar</span><span class="sum">${esc(summary)}</span></p>`;
    const c = calc(l);
    const flag = c.status === "parcial" || c.status === "sin" ? `<span class="pbadge cot">Parte por cotizar</span>` : "";
    return `<p class="cfg-state"><span class="pbadge ok">Configurado</span><span class="sum">${esc(summary)}</span>${flag}</p>`;
  }
  function cfgDetail(l){
    const info = cfgInfo(l), c = calc(l);
    const st = l.requested ? null : (S.states ? S.states.get(l.id) : null);
    const items = l.requested ? (l.requested.items || []) : ((st && st.items) || []);
    const comps = items.filter(i => i.kind === "componente");
    const rows = comps.map(i => {
      const factor = l.requested ? (i.quantity_status === "calculada" ? Number(i.total_quantity) / (l.qty || 1) : null) : (typeof i.factor === "number" && i.factor > 0 ? i.factor : null);
      const tot = factor === null ? null : Math.round(factor * 1000) / 1000;
      const price = i.supply === "incluido" ? "No suma" : !S.pricesOn ? "—" : (() => {
        const pi = getPriceInfo(i.product_id);
        return pi.kind !== "published" ? "Sin precio" : (tot ? money(pi.amount * tot * l.qty) : `${money(pi.amount)} c/u`);
      })();
      return `<tr><td>${esc(i.product_name || i.product_id)}${i.reference_code ? `<br><span style="color:var(--ink-3)">Ref. ${esc(i.reference_code)}</span>` : ""}</td>
        <td class="n">${tot === null ? "Cantidad por determinar" : `${tot} por unidad`}</td>
        <td>${i.supply === "incluido" ? "Incluido" : "Se suministra aparte"}</td><td class="n">${esc(price)}</td></tr>`;
    }).join("");
    const notes = l.requested ? (l.requested.config_notices || []) : ((st && st.notices) || []);
    const archivedNow = S.project.status === "archived" && !l.requested;
    return `<div class="cfgd">${archivedNow ? `<p>Información actual del proyecto (no es la copia de lo enviado).</p>` : ""}${comps.length ? `<table><thead><tr><th>Componente</th><th class="n">Cantidad</th><th>Suministro</th><th class="n">Importe</th></tr></thead><tbody>${rows}</tbody></table>` : ""}
      ${info.lines.map(t => `<p>${esc(t)}</p>`).join("")}
      ${c.issues.length && c.status !== "oculto" ? `<p class="issue">${c.status === "pendiente" ? "Fuera del importe calculable: " : ""}${c.issues.map(esc).join(" · ")}</p>` : ""}
      ${notes.map(n => `<p>${esc(n.message || n)}</p>`).join("")}
      ${!l.requested && !ro() ? `<p>Para cambiar la configuración, quita esta línea y vuelve a configurarla en la ficha.</p>` : ""}
      <p>Los importes de componentes aparte se calculan con la cantidad de la línea; los incluidos no se suman. Es información para decidir, no una cotización final.</p></div>`;
  }
  function cfgBlock(l){
    const info = cfgInfo(l);
    if (!l.configuration && info.status !== "pendiente") return "";
    return `<div class="cfg"><span class="sec">Configuración</span>${cfgState(l)}${l.configuration ? cfgDetail(l) : ""}</div>`;
  }
  function moneyBlock(l){
    const c = calc(l), p = prod(l.productId), info = p ? getPriceInfo(l.productId) : null, rows = [];
    const row = (a, b, cls = "") => `<div class="${cls}"><span>${a}</span><span>${b}</span></div>`;
    if (S.pricesOn && info && info.kind === "published") rows.push(row(`Precio por ${unitOf(l) === "ud." ? "unidad" : esc(unitOf(l))}`, esc(money(info.amount))));
    let small = "";
    if (c.status === "completa"){ rows.push(row("Importe de la línea", esc(money(c.known)), "tot")); small = "ITBIS incluido. Importe preliminar, no es una cotización."; }
    else if (c.status === "parcial"){ rows.push(row("Importe conocido de la línea", esc(money(c.known)), "tot")); small = `<span class="ochre" style="color:var(--ochre)">${c.issues.map(esc).join(" · ")}</span>`; }
    else if (c.status === "oculto"){ rows.push(row("Importe", "—", "tot")); small = "Los precios se consultan con un plan Individual o Estudio."; }
    else if (c.status === "nodisp"){ rows.push(row("Importe", "No disponible", "tot muted")); small = "El producto ya no está disponible: no suma al importe."; }
    else if (c.status === "pendiente"){ rows.push(row("Importe", "Sin importe", "tot muted")); small = `Configuración pendiente: ${c.issues.map(esc).join(" · ")}`; }
    else { rows.push(row("Importe", esc(info ? info.text || "Sin precio" : "Sin precio"), "tot ochre")); small = "Se confirmará en la cotización."; }
    return `<div class="money">${rows.join("")}</div><p class="small">${small}</p>`;
  }
  function qtyBlock(l){
    const unit = unitOf(l), isU = unit === "ud.";
    const dis = ro() || l.requested || S.busy ? "disabled" : "";
    const name = prod(l.productId) ? prod(l.productId).nombre : l.productId;
    const qtyVal = isU ? String(Math.round(l.qty)) : String(r2(l.qty));
    return `<label class="sec" for="qty-${esc(l.id)}">Cantidad</label>
      <div style="display:flex;align-items:center"><span class="stepper"><button data-act="dec" data-id="${esc(l.id)}" aria-label="Reducir cantidad" ${dis}>−</button><input id="qty-${esc(l.id)}" type="number" class="dp-qty-input" data-act="qty" data-id="${esc(l.id)}" value="${qtyVal}" min="${isU ? 1 : 0.01}" step="${isU ? 1 : 0.01}" inputmode="decimal" aria-label="Cantidad de ${esc(name)}" ${dis}><button data-act="inc" data-id="${esc(l.id)}" aria-label="Aumentar cantidad" ${dis}>+</button></span><span class="unit">${esc(unit)}</span></div>
      ${moneyBlock(l)}`;
  }
  function noteBlock(l){
    if (S.noteEdit && S.noteEdit.id === l.id){
      const d = S.noteEdit.draft, dirty = d.trim() !== (l.note || "");
      return `<div class="noted"><label class="sec" for="ne-${esc(l.id)}">Nota técnica (opcional)</label>
        <textarea id="ne-${esc(l.id)}" maxlength="${NOTE_MAX}" data-id="${esc(l.id)}" placeholder="Ej. medidas especiales, referencia de obra, condiciones de montaje…">${esc(d)}</textarea>
        <div class="row-btns bar"><button class="btn btn-dark" data-act="note-save" data-id="${esc(l.id)}" ${dirty && !S.busy ? "" : "disabled"}>Guardar nota</button><button class="btn" data-act="note-cancel" data-id="${esc(l.id)}">Cancelar</button>
        ${dirty ? `<span class="dirty">Cambios sin guardar</span>` : ""}<span class="cnt">${d.length}/${NOTE_MAX}</span></div><p class="note-status" role="status">${esc(S.noteEdit.status || "")}</p></div>`;
    }
    const editable = !ro() && !l.requested;
    return `<span class="sec">Nota técnica</span>${l.note ? `<p class="note-text">${esc(l.note)}</p>` : `<p class="note-empty">${editable ? "Sin nota. Sirve para medidas, ubicación en obra o condiciones de montaje." : "Sin nota."}</p>`}
      ${editable ? `<div class="row-btns"><button class="btn" data-act="note" data-id="${esc(l.id)}">${l.note ? "Editar nota" : "Añadir nota"}</button></div>` : ""}`;
  }
  const targetList = l => [{ id: null, name: "Sin área" }].concat(S.areas).filter(a => a.id !== (l.areaId || null));
  const idOfTarget = a => (a.id || "none");
  function fichaHtml(l){
    const p = prod(l.productId), name = p ? p.nombre : "Producto no disponible";
    const editable = !ro() && !l.requested;
    const ficha = p ? `producto.html?id=${encodeURIComponent(p.id)}` : "";
    const long = !!(l.note && l.note.length > 260 && !(S.noteEdit && S.noteEdit.id === l.id));
    const ph = photoOf(l);
    const photoSrc = !ph.url ? `<p class="photo-src">Este producto no tiene foto.</p>` : "";
    const general = ph.general ? `<span class="finish-photo">Foto general del producto: puede no mostrar este acabado.</span>` : "";
    const spec = p ? `<dl class="spec">${p.referencia ? `<div><dt>Referencia</dt><dd>${esc(p.referencia)}</dd></div>` : ""}${finishText(l) ? `<div><dt>Acabado</dt><dd>${esc(finishText(l))}${general}</dd></div>` : ""}<div><dt>Marca</dt><dd>${esc(LABELS.marca[p.marca] || "—")}</dd></div>${p.status === "archived" ? `<div><dt>Estado</dt><dd>No disponible actualmente</dd></div>` : ""}</dl>` : `<dl class="spec"><div><dt>Producto</dt><dd>ID: ${esc(l.productId)}</dd></div></dl>`;
    const more = ficha ? `<a class="more" href="${ficha}">Ver ficha del producto</a>` : "";
    const targets = editable && hasAreas() ? targetList(l) : [];
    const menu = (kind, label) => `<span class="menu-wrap"><button class="btn" data-act="pop" data-key="${kind}:${esc(l.id)}" aria-haspopup="menu" aria-expanded="${S.pop === `${kind}:${l.id}`}">${label} ${ICON.chev}</button>
      ${S.pop === `${kind}:${l.id}` ? `<div class="pop up"><p class="h">${kind === "mv" ? "Mover a" : "Copiar a"}</p>${targets.map(a => `<button data-act="${kind === "mv" ? "move1" : "copy1"}" data-id="${esc(l.id)}" data-area="${esc(idOfTarget(a))}">${esc(a.name)}</button>`).join("")}</div>` : ""}</span>`;
    const place = hasAreas() ? `<span class="f-area">En <b>${esc(areaName(l.areaId))}</b></span>${targets.length ? menu("mv", "Mover") + menu("cp", "Copiar") : ""}` : "";
    return `<li class="ficha" id="ficha" role="region" aria-label="Detalle de ${esc(name)}">
      <button class="iconbtn ficha-close" data-act="close-ficha" aria-label="Cerrar el detalle">${ICON.close}</button>
      <div class="fg${long ? " long" : ""}${l.configuration ? " has-cfg" : ""}">
        <h3 class="f-head" id="ficha-title" tabindex="-1">${esc(name)}</h3>
        <div class="f-info">${spec}${photoSrc}${more ? more.replace('class="more"', 'class="more more-in"') : ""}</div>
        ${l.configuration || cfgInfo(l).status === "pendiente" ? `<div class="f-cfg">${cfgBlock(l)}</div>` : ""}
        <div class="f-qty">${qtyBlock(l)}</div>
        <div class="f-note">${noteBlock(l)}</div>
        <div class="f-foot">${place}<span class="f-sp"></span>${more.replace('class="more"', 'class="more more-foot"')}${editable ? `<button class="textbtn danger" data-act="remove" data-id="${esc(l.id)}">Quitar del proyecto</button>` : ""}</div>
      </div></li>`;
  }
  /* La ficha va justo después de la última pieza de la fila de la pieza abierta, a todo el ancho, con la muesca
     sobre su pieza. Si ya estaba abierta (otro pintado), no repite la animación. */
  let shownFicha = null;
  function placeFicha(){
    const old = $("#ficha"); if (old) old.remove();
    if (!S.open){ shownFicha = null; return; }
    const tile = document.querySelector(`.tile[data-id="${CSS.escape(S.open)}"]`), l = lineById(S.open);
    if (!tile || !l){ S.open = null; shownFicha = null; return; }
    const grid = tile.parentElement;
    let last = tile;
    [...grid.children].forEach(t => { if (t.classList.contains("tile") && Math.abs(t.offsetTop - tile.offsetTop) < 4) last = t; });
    last.insertAdjacentHTML("afterend", fichaHtml(l));
    const f = $("#ficha");
    if (shownFicha === S.open) f.classList.add("still");
    shownFicha = S.open;
    f.style.setProperty("--nx", (tile.offsetLeft - grid.offsetLeft + tile.offsetWidth / 2) + "px");
  }

  /* ---------- posición de lectura ---------- */
  const tileEl = id => document.querySelector(`.tile[data-id="${CSS.escape(id)}"]`);
  const dockH = () => { const d = $("#dock"); return d && !d.hidden && d.offsetHeight && getComputedStyle(d).position === "fixed" ? d.offsetHeight : 0; };
  /* La cabecera del sitio es fija (styles.css): la franja de áreas y la columna se colocan debajo, y los desplazamientos la descuentan. */
  const headH = () => { const h = document.querySelector(".site-header"); return h && /sticky|fixed/.test(getComputedStyle(h).position) ? h.offsetHeight : 0; };
  const topH = () => { const s = $("#strip"); return headH() + (s && s.offsetHeight && getComputedStyle(s).position === "sticky" ? s.offsetHeight : 0); };
  /* Ejecuta fn y compensa el desplazamiento para que la pieza siga en el mismo sitio de la pantalla. */
  function anchored(id, fn){
    const el = id ? tileEl(id) : null, before = el ? el.getBoundingClientRect().top : null;
    fn();
    const now = id ? tileEl(id) : null;
    if (before === null || !now) return;
    if (before < -now.offsetHeight + 40){ scrollBy(0, now.getBoundingClientRect().top - topH() - 24); return; }
    scrollBy(0, now.getBoundingClientRect().top - before);
  }
  /* Si la ficha no cabe, se desplaza lo justo para verla sin que la pieza salga por arriba ni quede bajo la franja. */
  function revealFicha(id){
    const f = $("#ficha"), t = tileEl(id); if (!f || !t) return;
    const over = f.getBoundingClientRect().bottom - (innerHeight - dockH()) + 16;
    if (over <= 0) return;
    const by = Math.max(0, Math.min(over, t.getBoundingClientRect().top - 16 - topH()));
    if (by) scrollBy({ top: by, behavior: reduced() ? "auto" : "smooth" });
  }
  function openLine(id){
    if (S.open === id){ closeFicha(); return; }
    if (S.noteEdit && S.noteEdit.id !== id && !leaveNote()) return;
    anchored(id, () => { S.open = id; S.pop = null; render(); });
    revealFicha(id);
    const h = $("#ficha-title"); if (h) h.focus({ preventScroll: true });
  }
  function closeFicha(){
    const was = S.open; if (!was) return;
    if (S.noteEdit && S.noteEdit.id === was && !leaveNote()) return;
    anchored(was, () => { S.open = null; S.noteEdit = null; S.pop = null; render(); });
    const t = tileEl(was);
    if (t){
      if (t.getBoundingClientRect().top < topH() + 8) scrollBy(0, t.getBoundingClientRect().top - topH() - 24);
      t.querySelector(".tile-btn").focus({ preventScroll: true });
    }
  }
  /* Mientras la ficha está abierta, cualquier repintado conserva la posición de su pieza. */
  const keepPlace = fn => (S.open ? anchored(S.open, fn) : fn());

  /* ---------- bloques ---------- */
  const infoRows = () => {
    const pr = S.project;
    return `<div><dt>Cliente</dt><dd>${esc(pr.client_name || "Sin cliente asignado")}</dd></div><div><dt>Ubicación</dt><dd>${esc(pr.location || "No definida")}</dd></div>
      <div><dt>Tipo</dt><dd>${esc(pr.project_type ? (PROJECT_TYPE_LABELS[pr.project_type] || pr.project_type) : "No definido")}</dd></div>
      <div><dt>Descripción</dt><dd>${esc(pr.description || "Sin descripción")}</dd></div>
      <div><dt>Creado</dt><dd>${esc(relativeDate(pr.created_at))}</dd></div><div><dt>Actualizado</dt><dd>${esc(relativeDate(pr.updated_at))}</dd></div>
      ${ro() ? "" : `<div><dt>Datos</dt><dd><button class="textbtn" data-act="info-edit">Editar datos</button></dd></div>`}`;
  };
  const infoForm = () => {
    const pr = S.project;
    const types = Object.keys(PROJECT_TYPE_LABELS).map(k => `<option value="${k}" ${pr.project_type === k ? "selected" : ""}>${esc(PROJECT_TYPE_LABELS[k])}</option>`).join("");
    return `<form class="ph-form" id="info-form" novalidate>
      <div class="field47"><label for="edit-name">Nombre del proyecto</label><input id="edit-name" type="text" value="${esc(pr.name)}" maxlength="120"></div>
      <div class="field47"><label for="edit-client">Cliente o estudio</label><input id="edit-client" type="text" value="${esc(pr.client_name || "")}" placeholder="Ej. Familia Rosario"></div>
      <div class="field47"><label for="edit-type">Tipo de proyecto</label><select id="edit-type"><option value="">Selecciona una opción</option>${types}</select></div>
      <div class="field47"><label for="edit-location">Ubicación</label><input id="edit-location" type="text" value="${esc(pr.location || "")}" placeholder="Ej. Santo Domingo, Piantini"></div>
      <div class="field47"><label for="edit-description">Descripción</label><textarea id="edit-description" rows="3">${esc(pr.description || "")}</textarea></div>
      ${S.infoError ? `<p class="alert bad" style="margin:0 0 12px">${esc(S.infoError)}</p>` : ""}
      <div class="bar"><button type="submit" class="btn btn-primary" data-act="info-save" ${S.busy ? "disabled" : ""}>Guardar cambios</button><button type="button" class="btn" data-act="info-cancel">Cancelar</button></div></form>`;
  };
  function renderHeader(){
    const pr = S.project, archived = pr.status === "archived";
    const st = !archived ? ["Proyecto activo", ""] : S.isRequested ? ["Solicitud enviada", " closed"] : ["Archivado", " closed"];
    document.title = `${pr.name} — Mobau`;
    const meta = [pr.client_name, pr.location, pr.project_type ? (PROJECT_TYPE_LABELS[pr.project_type] || pr.project_type) : ""].filter(Boolean).join(", ");
    const counts = S.lines.length ? `${plural(S.lines.length, "línea", "líneas")}${hasAreas() ? ` en ${plural(S.areas.length, "área", "áreas")}` : ""}` : "";
    $("#ph").innerHTML = `<p class="crumb"><a href="proyectos.html${archived ? "?status=archived" : ""}">Mis proyectos</a><span class="status${st[1]}"><b class="status-chip">${st[0]}</b>, actualizado ${esc(relativeDate(pr.updated_at))}</span></p>
      <h1>${esc(pr.name)}</h1>
      <p class="lede">${meta ? `${esc(meta)}. ` : ""}${counts ? `<span class="count">${esc(counts)}.</span> ` : ""}<button class="textbtn" data-act="info" aria-expanded="${S.infoOpen}">Datos del proyecto</button></p>
      ${S.infoOpen ? (S.infoEdit ? infoForm() : `<dl class="ph-info">${infoRows()}</dl>`) : ""}`;
    $("#banner").innerHTML = archived
      ? `<div class="archived-note"><p>Este proyecto está archivado y se conserva para consulta.${S.isRequested ? " Tiene una solicitud enviada: su copia y su historial se conservan." : ""}${S.lines.length && !S.fromCopy && S.isRequested ? " Esta solicitud es anterior al guardado de una copia: se muestran las líneas actuales." : ""}</p>
         ${S.canReactivate ? `<button class="btn" data-act="reactivate">Reactivar proyecto</button>` : (S.reactivateWhy ? `<span class="why">${esc(S.reactivateWhy)}</span>` : "")}<a class="textbtn" href="proyectos.html?status=archived">Ver Archivados</a></div>`
      : "";
  }
  /* Misma regla de siempre: hay que poder pedir cotización de al menos un producto disponible y todos con cantidad válida. */
  const quoteRows = () => S.lines.filter(l => isProductAvailable(l.productId));
  const quoteReady = () => quoteRows().length > 0 && quoteRows().every(l => isValidQuantity(l.qty));
  const quoteHint = () => !quoteRows().length ? "Ninguno de los productos está disponible actualmente." : "Indica la cantidad de todos los productos antes de solicitar una cotización.";
  const quoteOff = () => !S.lines.length || ro() || !!S.loadError || !quoteReady();

  function coverage(t){
    const tot = t.completa + t.parcial + t.sin + t.pendiente || 1;
    const seg = (k, c) => `<i class="${c}" style="flex:${t[k] / tot}"></i>`;
    return `<div class="cov" role="img" aria-label="Cobertura de importes">${seg("completa", "c1")}${seg("parcial", "c2")}${seg("sin", "c3")}${seg("pendiente", "c4")}</div>
      <ul class="covtxt"><li class="c1"><i></i><span>${t.completa} con importe completo</span></li><li class="c2"><i></i><span>${t.parcial} parciales</span></li><li class="c3"><i></i><span>${t.sin} sin precio</span></li><li class="c4"><i></i><span>${t.pendiente} con configuración pendiente</span></li>${t.nodisp ? `<li class="c5"><i></i><span>${t.nodisp} no disponibles</span></li>` : ""}</ul>`;
  }
  function renderLedger(){
    const pr = S.project, archived = pr.status === "archived", failed = !!S.loadError, empty = !S.lines.length;
    let amounts = "";
    if (!empty && !failed){
      const blocked = priceAccessInfo();
      if (archived) amounts = `<p class="slim price-archived-note">Los precios no están disponibles para proyectos archivados.</p>`;
      else if (blocked) amounts = `<p class="slim">${esc(blocked.text)}${blocked.kind === "plan-required" || blocked.kind === "no-session" ? ` <a class="textbtn" href="planes.html">Ver planes</a>` : ""}</p>`;
      else {
        const t = aggregate(S.lines), [ent, cents] = money(t.known).split(".");
        const vis = S.lines.filter(visible), tv = aggregate(vis);
        amounts = `<p class="known-k">Importe conocido</p>
          ${t.known > 0 ? `<p class="known">${esc(ent)}<small>.${esc(cents)}</small></p>` : `<p class="known" style="font-size:20px;color:var(--ink-2)">Sin importes conocidos todavía</p>`}
          <p class="known-sub">dólares, ITBIS incluido. Suma de ${t.completa + t.parcial} de ${t.n === 1 ? "1 línea" : `las ${t.n} líneas`}.</p>
          ${coverage(t)}
          <p class="tnote">Importe preliminar: suma parcial de los importes conocidos. No es una cotización final.</p>
          ${filtering() ? `<p class="filtered">Resultado filtrado: <b>${esc(money(tv.known))}</b> conocidos en ${vis.length} de ${S.lines.length} líneas.</p>` : ""}`;
      }
    }
    const hint = !empty && !ro() && !failed && !quoteReady() ? `<p class="quote-hint" role="status">${esc(quoteHint())}</p>` : "";
    const acts = `<div class="acts">
        <button class="btn ${quoteOff() ? "" : "btn-primary"}" id="request-quote-btn" data-act="rfq" ${quoteOff() ? "disabled" : ""} ${ro() ? 'title="El proyecto ya no admite cambios"' : ""}>Solicitar cotización</button>
        ${empty || failed ? `<button class="btn" disabled>Ver resumen preliminar</button>` : `<a class="btn" href="proyectos-resumen.html?id=${encodeURIComponent(pr.id)}">Ver resumen preliminar</a>`}
      </div>${hint}`;
    const groups = indexGroups();
    const index = groups.length ? `<nav class="index" aria-label="Áreas del proyecto"><h2>Áreas</h2><ol>${groups.map(g => `<li><button data-act="goto" data-board="${esc(g.key)}" aria-current="${S.current === g.key}"><span>${esc(g.name)}</span><span>${g.n}</span></button></li>`).join("")}</ol>
        ${!ro() ? `<button class="textbtn" data-act="areas">Gestionar áreas</button>` : ""}</nav>` : "";
    /* Archivar: enlace discreto con la misma confirmación de siempre. Archivado: reactivar y Archivados están en el aviso de arriba. */
    const quiet = !ro() ? `<div class="quiet"><button class="textbtn" data-act="archive-ask" ${failed ? "disabled" : ""}>Archivar proyecto</button></div>` : "";
    $("#ledger").innerHTML = `<div class="l-a"><div id="totals" aria-live="polite">${amounts}</div>${acts}</div><div class="l-b">${index}${quiet}</div>`;
    renderDock();
    fitLedger();
  }
  /* Tableta y móvil: barra inferior con el importe y la solicitud (no tapa contenido: la página reserva su alto). */
  function renderDock(){
    const dock = $("#dock");
    if (!S.lines.length || S.loadError || ro() || S.selecting){ dock.innerHTML = ""; dock.hidden = true; return; }
    const t = aggregate(S.lines);
    const sum = S.pricesOn ? `<b>${esc(money(t.known))}</b><span>${indexGroups().length ? "conocidos" : `conocidos, ${t.pend} ${t.pend === 1 ? "pendiente" : "pendientes"}`}</span>` : `<b>${esc(S.project.name)}</b><span>${plural(S.lines.length, "línea", "líneas")}</span>`;
    dock.hidden = false;
    const groups = indexGroups();
    const areas = groups.length ? `<span class="menu-wrap"><button class="iconbtn dock-areas" data-act="pop" data-key="dockAreas" aria-haspopup="menu" aria-expanded="${S.pop === "dockAreas"}" aria-label="Ir a un área">${ICON.areas}</button>
      ${S.pop === "dockAreas" ? `<div class="pop up"><p class="h">Ir a un área</p>${groups.map(g => `<button data-act="goto" data-board="${esc(g.key)}">${esc(g.name)}<span class="count">${g.n}</span></button>`).join("")}</div>` : ""}</span>` : "";
    dock.innerHTML = `${areas}<button class="sum" data-act="to-ledger">${sum}</button><button class="btn ${quoteOff() ? "" : "btn-primary"}" id="request-quote-dock" data-act="rfq" ${quoteOff() ? "disabled" : ""}>Solicitar cotización</button>`;
  }
  /* Escritorio: la columna del proyecto queda fija bajo la cabecera del sitio solo si cabe entera en la ventana; si no,
     se desplaza con la página (sin barra propia y sin ocultar el importe ni las acciones). */
  function fitLedger(){
    const l = $("#ledger"); if (!l) return;
    const desk = matchMedia("(min-width: 1180px)").matches;
    l.classList.toggle("flow", !desk || l.offsetHeight > innerHeight - headH());
    l.style.setProperty("--ledger-top", headH() + "px");
  }
  function indexGroups(){
    if (!hasAreas() || S.loadError) return [];
    const none = S.lines.filter(l => !l.areaId).length;
    return S.areas.map(a => ({ key: a.id, name: a.name, n: S.lines.filter(l => l.areaId === a.id).length })).concat(none ? [{ key: "none", name: "Sin área", n: none }] : []);
  }
  function renderStrip(){
    const strip = $("#strip");
    strip.innerHTML = indexGroups().map(g => `<button data-act="goto" data-board="${esc(g.key)}" aria-current="${S.current === g.key}">${esc(g.name)}<span>${g.n}</span></button>`).join("");
  }

  function popFilter(kind){
    if (kind === "org"){
      if (!hasAreas()) return `<div class="pop right"><p class="hint">Agrupa tus productos por habitación o zona. Es opcional: puedes trabajar siempre como lista normal.</p><button data-act="organize">Crear la primera área…</button></div>`;
      const unassigned = S.lines.filter(l => !l.areaId).length;
      const items = S.areas.concat(unassigned ? [{ id: "none", name: "Sin área" }] : []);
      return `<div class="pop right"><p class="h">Filtrar por áreas</p>${items.map(a => `<label><input type="checkbox" data-act="fa" data-v="${esc(a.id)}" ${S.filters.areas.has(a.id) ? "checked" : ""}> ${esc(a.name)}<span class="count">${S.lines.filter(l => (l.areaId || "none") === a.id).length}</span></label>`).join("")}${S.filters.areas.size ? `<button data-act="fa-clear">Quitar filtro de áreas</button>` : ""}<hr>${ro() ? "" : `<button data-act="areas">Gestionar áreas…</button>`}<button data-act="collapse-all">Plegar todas</button><button data-act="expand-all">Desplegar todas</button></div>`;
    }
    const codes = Object.keys(LABELS.categoria).filter(c => S.lines.some(l => prod(l.productId) && prod(l.productId).categoria === c));
    return `<div class="pop"><p class="h">Filtrar por categoría</p>${codes.map(c => `<label><input type="checkbox" data-act="fc" data-v="${esc(c)}" ${S.filters.cats.has(c) ? "checked" : ""}> ${esc(LABELS.categoria[c])}<span class="count">${S.lines.filter(l => prod(l.productId) && prod(l.productId).categoria === c).length}</span></label>`).join("")}<hr><button data-act="fc-clear">Quitar filtro</button></div>`;
  }
  function renderToolbar(){
    const tb = $("#toolbar"), chipsBox = $("#chips");
    if (!S.lines.length){ tb.innerHTML = ""; tb.hidden = true; chipsBox.innerHTML = ""; return; }
    tb.hidden = false;
    const f = S.filters, pr = S.project, failed = !!S.loadError;
    const keepQ = document.activeElement && document.activeElement.id === "q";
    const canOrganize = !ro() && S.areasState === "ready";
    const selCount = getSelection().filter(i => isProductAvailable(i.productId)).length;
    const cats = Object.keys(LABELS.categoria);
    const n = (k) => k ? ` <span class="n">${k}</span>` : "";
    tb.innerHTML = `<div class="search">${ICON.search}<input id="q" type="search" value="${esc(f.q)}" placeholder="Buscar en el proyecto" aria-label="Buscar en el proyecto"></div>
      <span class="menu-wrap"><button class="pill${f.cats.size ? " on" : ""}" data-act="pop" data-key="catF" aria-haspopup="menu" aria-expanded="${S.pop === "catF"}">Categoría${n(f.cats.size)} ${ICON.chev}</button>${S.pop === "catF" ? popFilter("catF") : ""}</span>
      ${canOrganize || (ro() && hasAreas()) ? `<span class="menu-wrap"><button class="pill${f.areas.size ? " on" : ""}" data-act="pop" data-key="org" aria-haspopup="menu" aria-expanded="${S.pop === "org"}">${hasAreas() ? "Áreas" : `Organizar<span class="long"> por áreas</span>`}${n(f.areas.size)} ${ICON.chev}</button>${S.pop === "org" ? popFilter("org") : ""}</span>` : ""}
      ${!ro() ? `<button class="pill" data-act="select-mode" aria-pressed="${S.selecting}">${S.selecting ? "Terminar selección" : "Seleccionar"}</button>` : ""}
      ${!ro() ? `<span class="menu-wrap push"><button class="pill" data-act="pop" data-key="add" aria-haspopup="menu" aria-expanded="${S.pop === "add"}" ${failed ? "disabled" : ""}>${ICON.plus}<span>Añadir<span class="long"> productos</span></span></button>
        ${S.pop === "add" ? `<div class="pop right"><button data-act="from-selection">Desde mi selección <span class="count">${selCount}</span></button><hr><p class="h">Catálogo por categoría</p>${cats.map(c => `<a class="popitem" href="catalogo.html?categoria=${encodeURIComponent(c)}&project_id=${encodeURIComponent(pr.id)}">${esc(LABELS.categoria[c])}</a>`).join("")}<hr><a class="popitem" href="catalogo.html?project_id=${encodeURIComponent(pr.id)}">Buscar en todo el catálogo</a></div>` : ""}</span>` : ""}`;
    if (keepQ){ const q = $("#q"); q.focus({ preventScroll: true }); q.setSelectionRange(q.value.length, q.value.length); }
    const chips = [];
    f.areas.forEach(a => chips.push(`<span class="chip47">Área: ${esc(areaName(a === "none" ? null : a))}<button data-act="fa" data-v="${esc(a)}" data-off="1" aria-label="Quitar">×</button></span>`));
    f.cats.forEach(c => chips.push(`<span class="chip47">Categoría: ${esc(LABELS.categoria[c])}<button data-act="fc" data-v="${esc(c)}" data-off="1" aria-label="Quitar">×</button></span>`));
    if (f.q.trim()) chips.push(`<span class="chip47">Búsqueda: «${esc(f.q.trim())}»<button data-act="q-clear" aria-label="Quitar">×</button></span>`);
    const vis = S.lines.filter(visible).length;
    chipsBox.innerHTML = chips.length ? chips.join("") + `<span>${vis} de ${S.lines.length} líneas</span><button class="textbtn" data-act="clear-all">Limpiar filtros</button>` : "";
  }
  function boardSummary(lines){
    const head = productos(lines.length);
    if (!S.pricesOn) return esc(head) + ".";
    const t = aggregate(lines), bits = [];
    if (t.known > 0) bits.push(`${nw(money(t.known))} conocidos`);
    if (t.pend) bits.push(`${word(t.pend)} con algo pendiente`);
    return `${esc(head)}${bits.length ? ", " + bits.join(" y ") : ""}.`;
  }
  function boardHtml(a, idx){
    const flat = a === undefined;
    const all = flat ? S.lines : S.lines.filter(l => (l.areaId || null) === (a ? a.id : null));
    const vis = all.filter(visible);
    if (filtering() && !vis.length) return "";
    if (!flat && !a && !all.length) return "";
    const key = flat ? "all" : a ? a.id : "none", col = !flat && S.collapsed.has(key);
    const name = flat ? "Todos los productos" : a ? a.name : "Sin área";
    const title = S.renaming === key && a ? `<input class="ren" id="ren" value="${esc(a.name)}" maxlength="60" data-id="${esc(a.id)}" aria-label="Nombre del área">`
      : `<b><span class="board-name">${esc(name)}</span>.</b> `;
    const why = key === "none" ? `<span class="why">Productos que todavía no has colocado en un área.</span>` : "";
    const popKey = "area:" + key;
    const menuItems = [];
    if (a && !ro()) menuItems.push(`<button data-act="ren" data-id="${esc(a.id)}">Cambiar nombre</button><button data-act="up" data-id="${esc(a.id)}" ${idx === 0 ? "disabled" : ""}>Subir</button><button data-act="down" data-id="${esc(a.id)}" ${idx === S.areas.length - 1 ? "disabled" : ""}>Bajar</button><hr>`);
    if (!flat) menuItems.push(`<button data-act="toggle" data-key="${esc(key)}">${col ? "Desplegar el área" : "Plegar el área"}</button>`);
    if (a && !ro()) menuItems.push(`<hr><button data-act="del-area" data-id="${esc(a.id)}" class="danger">Eliminar área…</button>`);
    const menu = menuItems.length ? `<span class="menu-wrap"><button class="iconbtn" data-act="pop" data-key="${esc(popKey)}" aria-haspopup="menu" aria-expanded="${S.pop === popKey}" aria-label="Acciones de ${esc(name)}">${ICON.more}</button>${S.pop === popKey ? `<div class="pop right">${menuItems.join("")}</div>` : ""}</span>` : "";
    const allSel = vis.length && vis.every(l => S.selected.has(l.id));
    /* «Añadir aquí»: abre «Desde mi selección» con esta área ya elegida (mismo flujo y mismas validaciones). */
    const addHere = a && !ro() && !S.selecting ? `<button class="addhere" data-act="from-selection" data-area="${esc(a.id)}" aria-label="Añadir a «${esc(a.name)}» desde mi selección">${ICON.plus}<span>Añadir aquí</span></button>` : "";
    const selAll = S.selecting && !ro() && vis.length ? `<label class="selall"><input type="checkbox" data-act="sel-area" data-key="${esc(flat ? "all" : key)}" ${allSel ? "checked" : ""}> Todo${flat ? "" : " el área"}</label>` : "";
    const sum = filtering() ? `${cap(word(vis.length))} de ${all.length} coinciden.` : boardSummary(all);
    const body = col ? `<p class="unfold"><button class="textbtn" data-act="toggle" data-key="${esc(key)}">Desplegar ${plural(all.length, "producto", "productos")}</button></p>`
      : `<ul class="grid" data-grid="${esc(key)}">${vis.map(tileHtml).join("")}</ul>`;
    return `<section class="board${col ? " collapsed" : ""}" ${flat ? "" : `data-area="${esc(key)}" id="board-${esc(key)}"`} data-board="${esc(key)}">
      <header class="board-head"><span class="tail">${addHere}${selAll}${menu}</span><h2>${title}<span class="sum">${sum}</span>${why}</h2></header>${body}</section>`;
  }
  const cap = s => s.charAt(0).toUpperCase() + s.slice(1);
  const areaOptionsAll = () => `<option value="none">Sin área</option>` + S.areas.map(a => `<option value="${esc(a.id)}">${esc(a.name)}</option>`).join("");
  function renderList(){
    const list = $("#list");
    if (S.loadError){
      list.innerHTML = `<div class="alert bad" role="alert"><b>${S.loadError.areasFailed ? "No pudimos cargar las áreas de este proyecto." : "No pudimos cargar las líneas de este proyecto."}</b>
        No se muestra el contenido porque podría estar incompleto, y no se permite modificar nada hasta recuperarlo. Tus datos no se han tocado.
        <br><button class="btn" data-act="retry">Reintentar</button></div>`;
    } else if (!S.lines.length){
      const selCount = getSelection().filter(i => isProductAvailable(i.productId)).length;
      list.innerHTML = ro()
        ? `<div class="empty-state"><h2>Este proyecto no tiene productos guardados</h2><p>Está archivado y es solo de consulta: no se pueden añadir productos.</p></div>`
        : `<div class="empty-state"><h2>Tu proyecto está vacío</h2><p>Añade productos desde el catálogo o desde tu selección. No hace falta configurar nada más: podrás ordenarlos después, si quieres.</p>
          <div class="acts">${selCount ? `<button class="btn btn-primary" data-act="from-selection">Añadir desde mi selección (${selCount})</button>` : ""}<a class="btn ${selCount ? "" : "btn-primary"}" href="catalogo.html">Explorar el catálogo</a></div></div>`;
    } else if (hasAreas()){
      list.innerHTML = S.areas.map((a, i) => boardHtml(a, i)).join("") + boardHtml(null)
        || `<div class="empty"><b>Ningún producto coincide con los filtros.</b><br><button class="textbtn" data-act="clear-all">Limpiar filtros</button></div>`;
    } else {
      list.innerHTML = S.lines.some(visible) ? boardHtml(undefined)
        : `<div class="empty"><b>Ningún producto coincide con los filtros.</b><br><button class="textbtn" data-act="clear-all">Limpiar filtros</button></div>`;
    }
    const compat = $("#compat-slot");
    if (compat) compat.innerHTML = !S.loadError && S.lines.some(l => l.configuration) ? `<p class="card-meta line-compat-note">${esc(MobauLineConfig.COMPAT_NOTE)}</p>` : "";
    $("#project-view").classList.toggle("selecting", S.selecting);
    placeFicha();
    /* Selección múltiple: un modo explícito; al salir no quedan líneas seleccionadas sin verse. */
    const bulk = $("#bulk"), n = S.selected.size, on = S.selecting && !ro();
    bulk.hidden = !on;
    bulk.innerHTML = on ? `<span class="grow">${n ? `<b>${n} seleccionada${n > 1 ? "s" : ""}</b>` : "Toca los productos que quieras"}</span>
      ${hasAreas() ? `<select id="bulk-area" aria-label="Área de destino">${areaOptionsAll()}</select><button class="btn" data-act="bulk-move" ${n ? "" : "disabled"}>Mover</button><button class="btn" data-act="bulk-copy" ${n ? "" : "disabled"}>Copiar</button>` : ""}
      <button class="btn" data-act="bulk-remove" ${n ? "" : "disabled"}>Quitar del proyecto</button>${n ? `<button class="btn" data-act="bulk-clear">Deseleccionar</button>` : ""}<button class="btn btn-light" data-act="select-mode">Terminar</button>` : "";
  }
  /* El índice y la franja marcan el área que se está leyendo. */
  let io = null;
  function observe(){
    if (io) io.disconnect();
    if (!hasAreas() || !("IntersectionObserver" in window)) return;
    io = new IntersectionObserver(entries => entries.forEach(en => {
      if (!en.isIntersecting || S.current === en.target.dataset.board) return;
      S.current = en.target.dataset.board; markCurrent(true);
    }), { rootMargin: "-20% 0px -70% 0px" });
    document.querySelectorAll(".board[data-area]").forEach(b => io.observe(b));
  }
  function markCurrent(slide){
    document.querySelectorAll(".index button[data-board], #strip button[data-board]").forEach(b => b.setAttribute("aria-current", b.dataset.board === S.current));
    const strip = $("#strip"), on = strip.querySelector('button[aria-current="true"]');
    if (slide && on && strip.scrollWidth > strip.clientWidth) strip.scrollTo({ left: strip.scrollLeft + on.getBoundingClientRect().left - strip.getBoundingClientRect().left - 16, behavior: reduced() ? "auto" : "smooth" });
  }
  function render(){
    $("#project-view").style.setProperty("--head-h", headH() + "px");
    renderHeader(); renderToolbar(); renderList(); renderStrip(); renderLedger(); observe(); markCurrent(false);
    if (S.noteEdit && S.noteEdit.focus){ const t = $(`#ne-${CSS.escape(S.noteEdit.id)}`); if (t){ t.focus({ preventScroll: true }); t.setSelectionRange(t.value.length, t.value.length); } S.noteEdit.focus = false; }
    if (S.renaming){ const r = $("#ren"); if (r && !r.dataset.done){ r.focus(); r.select(); r.dataset.done = 1; } }
  }
  let rzTimer = null, lastW = innerWidth;
  addEventListener("resize", () => {
    fitLedger();
    if (innerWidth === lastW) return;
    lastW = innerWidth; clearTimeout(rzTimer);
    rzTimer = setTimeout(() => { if (S.project && S.open) keepPlace(() => placeFicha()); }, 80);
  });

  /* ---------- operaciones ---------- */
  const toast = msg => showToast(msg);
  const targetOf = v => (v === "none" || v === "null" || !v ? null : v);
  /* Ejecuta una operación del servidor con la pantalla bloqueada; al terminar (bien o mal) vuelve a leer lo guardado. */
  async function run(fn){
    if (S.busy) return;
    S.busy = true; render();
    try { return await fn(); }
    finally { S.busy = false; await touchAndLoad(); }
  }
  async function touchAndLoad(touch){
    if (touch){
      const { data } = await MobauProjects.touchProject(S.project.id);
      if (data) S.project = Object.assign({}, S.project, data);
    }
    await load();
  }
  const dirtyNote = () => { const e = S.noteEdit; if (!e) return false; const l = lineById(e.id); return !!l && e.draft.trim() !== (l.note || ""); };
  function leaveNote(){ if (dirtyNote() && !confirm("Tienes una nota editada sin guardar. ¿Descartar los cambios?")) return false; S.noteEdit = null; return true; }
  window.addEventListener("beforeunload", e => { if (dirtyNote()){ e.preventDefault(); e.returnValue = ""; } });

  /* Cantidad: mismas reglas de siempre (mayor que 0; entera con «ud.»). */
  async function saveQty(l, raw){
    const unit = unitOf(l), rounded = r2(Number(String(raw).replace(",", ".")));
    if (!Number.isFinite(rounded) || rounded <= 0){ toast("La cantidad debe ser mayor que 0."); render(); return; }
    if (unit === "ud." && !Number.isInteger(rounded)){ toast("Para unidades (ud.) la cantidad debe ser un número entero."); render(); return; }
    if (rounded === r2(l.qty)){ render(); return; }
    await run(async () => {
      const { error } = await MobauProjects.updateProductQuantity(l.id, rounded);
      if (error){ toast(MobauAreas.explain(error)); return; }
      await MobauProjects.touchProject(S.project.id);
      toast("Cantidad actualizada.");
    });
    const input = document.querySelector(`.dp-qty-input[data-id="${CSS.escape(l.id)}"]`);
    if (input) input.focus();
  }
  async function saveNote(l){
    const draft = S.noteEdit.draft;
    await run(async () => {
      const { data, error } = await MobauProjects.updateLineNote(l.id, draft);
      if (error || !data){
        const hint = error && error.hint;
        S.noteEdit.status = hint === "line_note_archived" ? "Este proyecto está archivado: la nota ya no se puede modificar."
          : hint === "line_note_too_long" ? `La nota admite como máximo ${NOTE_MAX} caracteres.` : MobauAreas.explain(error) || "No pudimos guardar la nota. Inténtalo de nuevo.";
        return;
      }
      S.noteEdit = null;
      await MobauProjects.touchProject(S.project.id);
      toast(data.notes ? "Nota guardada." : "Nota eliminada.");
    });
  }
  async function removeLines(ids, message){
    await run(async () => {
      const { error } = await MobauProjects.removeProductsFromProject(ids);
      if (error){ toast(MobauAreas.explain(error)); return; }
      ids.forEach(id => S.selected.delete(id));
      await MobauProjects.touchProject(S.project.id);
      toast(message);
    });
  }

  /* Mover o copiar. El servidor decide los conflictos al ejecutar: si el destino ya tiene una línea equivalente
     pide una resolución para cada una (nada se funde en silencio); sin ella no cambia nada. */
  async function transfer(ids, target, kind, resolutions = {}, depth = 0){
    if (S.busy) return;
    S.busy = true;
    let outcome = null;
    try {
      const { data, error } = await MobauAreas.transferLines(ids, target, kind, resolutions);
      if (!error){
        outcome = { data };
      } else {
        const conflicts = MobauAreas.conflictsOf(error);
        if (conflicts && conflicts.length && depth < 4){
          S.busy = false;
          const resolved = await resolveTransferConflicts(conflicts, target, kind);
          if (!resolved){ await load(); return; }       // se canceló: no se cambió nada
          return await transfer(ids, target, kind, Object.assign({}, resolutions, resolved), depth + 1);
        }
        toast(MobauAreas.explain(error));
      }
    } finally { S.busy = false; }
    if (outcome){
      await MobauProjects.touchProject(S.project.id);
      ids.forEach(id => S.selected.delete(id));
      const d = outcome.data || {}, parts = [];
      if (d.moved) parts.push(`${d.moved} movida${d.moved > 1 ? "s" : ""}`);
      if (d.copied) parts.push(`${d.copied} copiada${d.copied > 1 ? "s" : ""}`);
      if (d.summed) parts.push(`${d.summed} sumada${d.summed > 1 ? "s" : ""} a una línea existente`);
      if (d.skipped) parts.push(`${d.skipped} sin cambios`);
      toast(`«${areaName(target)}»: ${parts.join(" · ") || "sin cambios"}.`);
    }
    await load();
  }
  /* Pregunta, línea a línea, qué hacer con cada conflicto: devuelve { [lineId]: resolución } o null si se cancela. */
  async function resolveTransferConflicts(conflicts, target, kind){
    const out = {};
    for (const c of conflicts){
      const l = lineById(c.line_id), twin = lineById(c.twin_id);
      if (!l || !twin) continue;
      const choice = await conflictModal(l, twin, target, kind);
      if (choice === "cancel") return null;
      out[l.id] = choice === "skip" ? { action: "skip" } : { action: "sum", note: choice };
    }
    return out;
  }

  /* ---------- ventanas ---------- */
  let modalResolve = null;
  function modal(title, body, footer, wide){
    $("#modal-root").innerHTML = `<div class="veil" data-act="veil"><div class="modal" role="dialog" aria-modal="true" aria-label="${esc(title)}" style="${wide ? "" : "width:min(600px,100%)"}"><header><h2>${esc(title)}</h2><span style="flex:1"></span><button class="iconbtn" data-act="close" aria-label="Cerrar">✕</button></header><div class="body">${body}</div>${footer ? `<footer>${footer}</footer>` : ""}</div></div>`;
    const first = $("#modal-root input, #modal-root select, #modal-root textarea, #modal-root .btn-primary");
    if (first && first.tagName === "INPUT" && first.type !== "radio") setTimeout(() => first.focus(), 30);
  }
  function closeModal(){
    $("#modal-root").innerHTML = "";
    if (modalResolve){ const r = modalResolve; modalResolve = null; r("cancel"); }
  }
  /* Conflicto al mover o copiar: promete "skip" | "existing" | "incoming" | "both" | "cancel" (con nota "incoming-only" cuando solo una tiene nota). */
  function conflictModal(l, twin, target, kind){
    return new Promise(resolve => {
      const p = prod(l.productId), differ = !!(l.note && twin.note && l.note.trim() !== twin.note.trim());
      const unit = unitOf(l), sum = r2(twin.qty + l.qty), verb = kind === "move" ? "movida" : "copiada";
      modal("Ya existe en esa área", `<p style="margin:0 0 8px;font-size:14px"><b>${esc(p ? p.nombre : l.productId)}</b>${finishText(l) ? ` · ${esc(finishText(l))}` : ""}${cfgSummary(l) ? ` · ${esc(cfgSummary(l))}` : ""}<br>Ya está en «${esc(areaName(target))}» con <b>${twin.qty} ${esc(unitOf(twin))}</b> — ${kind === "move" ? "moverla" : "copiarla"} añadiría ${l.qty} ${esc(unit)} más.</p>
        ${differ ? `<div class="cmp"><div><small>Nota de la línea existente</small>${esc(twin.note)}</div><div><small>Nota de la línea ${verb}</small>${esc(l.note)}</div></div>
          <div class="field47"><label>Las notas son distintas. Elige qué nota queda:</label>
            <label style="display:flex;gap:8px;align-items:center;color:var(--ink)"><input type="radio" name="nt" value="existing"> Conservar la nota existente</label>
            <label style="display:flex;gap:8px;align-items:center;color:var(--ink)"><input type="radio" name="nt" value="incoming"> Usar la otra nota</label>
            <label style="display:flex;gap:8px;align-items:center;color:var(--ink)"><input type="radio" name="nt" value="both"> Conservar las dos, una detrás de otra</label></div>`
          : `<p style="margin:0 0 6px;font-size:13.5px;color:var(--ink-soft)">${l.note && !twin.note ? `Se conservará la nota de la línea ${verb}.` : twin.note ? "Se conserva la nota existente." : "Ninguna de las dos tiene nota."}</p>`}`,
        `<button class="btn btn-outline" data-act="cf-skip">No hacer nada con esta línea</button><button class="btn btn-primary" data-act="cf-sum" ${differ ? "disabled" : ""}>Sumar cantidades (${twin.qty} + ${l.qty} = ${sum})</button>`);
      const root = $("#modal-root");
      const sumBtn = root.querySelector('[data-act="cf-sum"]');
      root.querySelectorAll('input[name="nt"]').forEach(r => r.addEventListener("change", () => { sumBtn.disabled = false; }));
      modalResolve = resolve;
      root.addEventListener("click", function h(e){
        const t = e.target.closest("[data-act]"); if (!t) return;
        if (t.dataset.act === "cf-skip"){ root.removeEventListener("click", h); modalResolve = null; closeModal(); resolve("skip"); }
        else if (t.dataset.act === "cf-sum"){
          const sel = root.querySelector('input[name="nt"]:checked');
          root.removeEventListener("click", h); modalResolve = null; closeModal(); resolve(differ ? sel.value : "incoming");
        } else if (t.dataset.act === "close" || (t.dataset.act === "veil" && e.target === t)){ root.removeEventListener("click", h); }
      });
    });
  }
  function organizeModal(){
    modal("Organizar por áreas", `<p style="margin:0 0 12px;font-size:14px">Crea la primera área, por ejemplo una habitación o una zona de obra. <b>No se reparte nada automáticamente</b>: tus productos quedan en «Sin área» hasta que quieras moverlos, y puedes seguir añadiendo productos sin asignarlos.</p>
      <div class="field47"><label for="first-area">Nombre de la primera área</label><input id="first-area" type="text" maxlength="60" placeholder="Ej. Sala, Cocina, Habitación 1" style="width:100%"></div>`,
      `<button class="btn btn-outline" data-act="close">Cancelar</button><button class="btn btn-primary" data-act="create-first">Crear área</button>`);
  }
  function areasModal(){
    modal("Gestionar áreas", `<p style="margin:0 0 10px;font-size:14px">Crea, renombra y ordena las áreas. Al eliminar un área sus líneas pasan a «Sin área»; nunca se elimina ningún producto. Si eliminas todas, el proyecto vuelve a ser una lista sencilla.</p>
      <div class="arealist">${S.areas.map((a, i) => `<div class="it"><input type="text" value="${esc(a.name)}" maxlength="60" data-act="area-name" data-id="${esc(a.id)}" aria-label="Nombre del área"><span style="font-size:12.5px;color:var(--ink-faint);min-width:64px">${S.lines.filter(l => l.areaId === a.id).length} líneas</span>
        <button class="iconbtn" data-act="up" data-id="${esc(a.id)}" data-keep="1" ${i === 0 ? "disabled" : ""} aria-label="Subir">↑</button><button class="iconbtn" data-act="down" data-id="${esc(a.id)}" data-keep="1" ${i === S.areas.length - 1 ? "disabled" : ""} aria-label="Bajar">↓</button>
        <button class="iconbtn" data-act="del-area" data-id="${esc(a.id)}" data-keep="1" aria-label="Eliminar" style="color:var(--danger)">🗑</button></div>`).join("")}
        <div class="it"><input type="text" id="new-area" placeholder="Nombre de la nueva área" maxlength="60"><button class="btn btn-primary" data-act="add-area" style="padding:8px 16px">Crear área</button></div></div>
        <p style="font-size:12.5px;color:var(--ink-faint);margin:10px 0 0">«Sin área» reúne lo que no está asignado, va al final y no se puede renombrar.</p>`, `<button class="btn btn-outline" data-act="close">Listo</button>`);
  }
  function areaErrorText(error){
    if (error && error.code === "23505") return "Ya existe un área con ese nombre.";
    if (error && error.code === "23514") return "El nombre del área debe tener entre 1 y 60 caracteres.";
    return MobauAreas.explain(error);
  }
  async function createArea(name, afterOk){
    const v = String(name || "").trim();
    if (!v){ toast("Escribe un nombre para el área."); return; }
    if (S.areas.some(a => a.name.toLowerCase() === v.toLowerCase())){ toast("Ya existe un área con ese nombre."); return; }
    if (S.busy) return;
    S.busy = true;
    const { error } = await MobauAreas.create(S.project.id, v, S.areas);
    S.busy = false;
    if (error){ toast(areaErrorText(error)); return; }
    await MobauProjects.touchProject(S.project.id);
    await load();
    afterOk();
  }
  async function renameArea(id, name){
    const a = S.areas.find(x => x.id === id), v = String(name || "").trim();
    if (!a || !v || v === a.name) return;
    if (S.areas.some(o => o.id !== id && o.name.toLowerCase() === v.toLowerCase())){ toast("Ya existe un área con ese nombre."); return; }
    const { error } = await MobauAreas.rename(id, v);
    if (error) toast(areaErrorText(error));
    await load();
  }
  async function moveArea(id, dir){
    const i = S.areas.findIndex(a => a.id === id), j = dir === "up" ? i - 1 : i + 1;
    if (!S.areas[i] || !S.areas[j]) return;
    const { error } = await MobauAreas.swapOrder(S.areas[i], S.areas[j]);
    if (error) toast(areaErrorText(error));
    await load();
  }

  /* Eliminar un área: sus líneas pasan a «Sin área». Sin conflictos, una confirmación breve. Si alguna línea ya tiene su
     equivalente en «Sin área», se resuelve ANTES (sumar o mover a otra área); cancelar no cambia nada. Los conflictos los
     vuelve a comprobar el servidor al ejecutar. */
  let pendingDel = null;
  function deleteAreaAsk(id, keep, serverConflicts){
    const a = S.areas.find(x => x.id === id); if (!a) return;
    const mine = S.lines.filter(l => l.areaId === id);
    const twinOf = (l, area) => S.lines.find(o => o.id !== l.id && (o.areaId || null) === area && keyOf(o) === keyOf(l));
    let conflicts = mine.map(l => ({ l, twin: twinOf(l, null) })).filter(x => x.twin);
    if (serverConflicts) conflicts = serverConflicts.map(c => ({ l: lineById(c.line_id), twin: lineById(c.twin_id) })).filter(x => x.l && x.twin);
    const others = S.areas.filter(x => x.id !== id), last = S.areas.length === 1;
    pendingDel = { id, keep, conflicts, others };
    if (!conflicts.length){
      modal("Eliminar área", `<p style="margin:0 0 8px;font-size:14px">¿Eliminar el área <b>«${esc(a.name)}»</b>?</p>
        <p style="margin:0;font-size:13.5px;color:var(--ink-soft)">${mine.length ? `Sus ${mine.length} ${mine.length === 1 ? "línea pasará" : "líneas pasarán"} a «Sin área». ` : ""}No se elimina ningún producto.${last ? " Era la última área: el proyecto volverá a ser una lista sencilla." : ""}</p>`,
        `<button class="btn btn-outline" data-act="close">Cancelar</button><button class="btn btn-primary" data-act="da-apply">Eliminar área</button>`);
      return;
    }
    modal("Conflictos al eliminar el área", `<p style="margin:0 0 10px;font-size:14px">Al pasar las líneas de <b>«${esc(a.name)}»</b> a «Sin área», ${conflicts.length === 1 ? "una ya existe" : conflicts.length + " ya existen"} allí. Resuélvelo antes de continuar; si cancelas, no cambia nada.</p>
      ${conflicts.map((c, i) => {
        const p = prod(c.l.productId), differ = !!(c.l.note && c.twin.note && c.l.note.trim() !== c.twin.note.trim());
        const free = others.filter(o => !twinOf(c.l, o.id));
        return `<div class="cflt" data-i="${i}"><p style="margin:0 0 6px;font-size:13.5px"><b>${esc(p ? p.nombre : c.l.productId)}</b>${finishText(c.l) ? ` · ${esc(finishText(c.l))}` : ""}${cfgSummary(c.l) ? ` · ${esc(cfgSummary(c.l))}` : ""}<br>En «${esc(a.name)}»: ${c.l.qty} ${esc(unitOf(c.l))} · En «Sin área»: ${c.twin.qty} ${esc(unitOf(c.twin))}</p>
          ${differ ? `<div class="cmp"><div><small>Nota en «Sin área»</small>${esc(c.twin.note)}</div><div><small>Nota en «${esc(a.name)}»</small>${esc(c.l.note)}</div></div>` : ""}
          <label class="rd"><input type="radio" name="r${i}" value="sum"> Sumar cantidades (${c.twin.qty} + ${c.l.qty} = ${r2(c.twin.qty + c.l.qty)})</label>
          ${differ ? `<div class="rd-sub">Notas distintas, ¿cuál queda?
            <label class="rd"><input type="radio" name="n${i}" value="existing"> La de «Sin área»</label><label class="rd"><input type="radio" name="n${i}" value="incoming"> La de «${esc(a.name)}»</label><label class="rd"><input type="radio" name="n${i}" value="both"> Las dos, una detrás de otra</label></div>` : ""}
          ${free.length ? `<label class="rd"><input type="radio" name="r${i}" value="move"> Mover esta línea a otra área: <select name="m${i}">${free.map(o => `<option value="${esc(o.id)}">${esc(o.name)}</option>`).join("")}</select></label>` : ""}</div>`;
      }).join("")}`,
      `<button class="btn btn-outline" data-act="close">Cancelar sin cambios</button><button class="btn btn-primary" data-act="da-apply" disabled>Eliminar el área y aplicar</button>`, true);
    const root = $("#modal-root"), btn = root.querySelector('[data-act="da-apply"]');
    const ready = () => conflicts.every((c, i) => {
      const rv = root.querySelector(`input[name="r${i}"]:checked`);
      if (!rv) return false;
      const differ = !!(c.l.note && c.twin.note && c.l.note.trim() !== c.twin.note.trim());
      return rv.value === "move" || !differ || !!root.querySelector(`input[name="n${i}"]:checked`);
    });
    root.addEventListener("change", () => { btn.disabled = !ready(); });
  }
  async function deleteAreaApply(){
    const d = pendingDel; if (!d || S.busy) return;
    const root = $("#modal-root"), resolutions = {};
    d.conflicts.forEach((c, i) => {
      const rv = root.querySelector(`input[name="r${i}"]:checked`);
      if (!rv) return;
      if (rv.value === "move") resolutions[c.l.id] = { action: "move", area_id: root.querySelector(`select[name="m${i}"]`).value };
      else resolutions[c.l.id] = { action: "sum", note: (root.querySelector(`input[name="n${i}"]:checked`) || {}).value || "existing" };
    });
    S.busy = true;
    const { data, error } = await MobauAreas.deleteArea(d.id, resolutions);
    S.busy = false;
    pendingDel = null;
    if (error){
      closeModal();
      const conflicts = MobauAreas.conflictsOf(error);
      await load();
      if (conflicts && conflicts.length){ deleteAreaAsk(d.id, d.keep, conflicts); return; }   // cambió mientras tanto: de nuevo, con lo que ve el servidor
      toast(MobauAreas.explain(error));
      return;
    }
    await MobauProjects.touchProject(S.project.id);
    S.filters.areas.delete(d.id); S.collapsed.delete(d.id); S.pop = null;
    closeModal();
    await load();
    toast(S.areas.length ? "Área eliminada; sus líneas están en «Sin área»." : "Sin áreas: el proyecto vuelve a ser una lista sencilla.");
    if (d.keep && S.areas.length) areasModal();
  }

  function archiveAsk(){
    const n = S.lines.length, canBack = planAllowsMultipleActive(S.plan);
    modal("Archivar proyecto", `<p style="margin:0 0 8px;font-size:14px">Vas a archivar <b>«${esc(S.project.name)}»</b>.</p>
      <p style="margin:0 0 8px;font-size:14px;color:var(--ink-soft)">Se conserva${n ? ` con sus ${plural(n, "línea", "líneas")}` : ""}, solo para consulta. <b>No se elimina.</b> Puedes recuperarlo o eliminarlo desde Archivados.</p>
      <p style="margin:0;font-size:13px;color:var(--ink-faint)">${canBack ? "Recuperarlo requiere cupo de proyectos activos en tu plan." : "Tu plan actual no permite recuperar proyectos archivados; sí podrás consultarlo o eliminarlo."}</p>`,
      `<button class="btn btn-outline" data-act="close">Cancelar</button><button class="btn btn-primary" data-act="archive-do">Archivar proyecto</button>`);
  }
  async function archiveDo(){
    if (S.busy) return;
    S.busy = true;
    const { data, error } = await MobauProjects.setStatus(S.project.id, "archived");
    S.busy = false;
    closeModal();
    if (error){ toast(error.message); return; }
    S.project = data; S.noteEdit = null; S.selected.clear(); S.pop = null;
    toast("Proyecto archivado. Lo encontrarás en Archivados.");
    await refreshAccess();
    await load();
  }
  async function reactivate(){
    if (S.busy) return;
    S.busy = true;
    const { data, error } = await MobauProjects.setStatus(S.project.id, "active");
    S.busy = false;
    if (error){ toast(error.message); return; }
    S.project = data;
    await refreshAccess();
    await load();
  }
  /* Estado derivado de un proyecto archivado: ¿tiene solicitud?, ¿se puede reactivar con el plan y el cupo actuales? */
  async function refreshAccess(){
    S.isRequested = false; S.canReactivate = false; S.reactivateWhy = "";
    if (S.project.status !== "archived") return;
    const rfqs = await MobauProjects.listMyRfqs(S.userId);
    S.isRequested = rfqs.some(r => r.project_id === S.project.id);
    if (planAllowsMultipleActive(S.plan)){
      const active = await MobauProjects.countActive();
      S.canReactivate = active < S.plan.max_active_projects;
      if (!S.canReactivate) S.reactivateWhy = "Sin cupo para reactivar";
    } else {
      S.reactivateWhy = "Los proyectos archivados no se pueden reactivar en tu plan actual.";
    }
  }

  /* Desde mi selección: mismas reglas de siempre (la selección solo se limpia si todo se transfirió bien). */
  function selectionModal(preArea){
    const items = getSelection().filter(i => isProductAvailable(i.productId));
    if (!items.length){ toast("Tu selección está vacía."); return; }
    modal("Añadir desde mi selección", `<p style="margin:0 0 10px;font-size:14px">Se añadirán ${items.length} ${items.length === 1 ? "producto" : "productos"} al proyecto.</p>
      ${hasAreas() ? `<div class="optf"><label for="sel-area">Asignar a un área (opcional):</label><select id="sel-area"><option value="none">Sin asignar</option>${S.areas.map(a => `<option value="${esc(a.id)}" ${a.id === preArea ? "selected" : ""}>${esc(a.name)}</option>`).join("")}</select></div>` : ""}
      <table class="sum"><thead><tr><th>Producto</th><th>Acabado</th><th style="text-align:right">Cantidad</th></tr></thead><tbody>${items.map(s => { const p = prod(s.productId); return `<tr><td>${esc(p ? p.nombre : s.productId)}${s.configuration ? `<br><span style="color:var(--ink-faint)">${esc(MobauLineConfig.rawChoices(s.configuration) || "Configurado")}</span>` : ""}</td><td>${esc(p && s.finish ? finishLabel(p, s.finish) : "—")}</td><td class="n" style="text-align:right">${s.quantity} ${esc(s.unit)}</td></tr>`; }).join("")}</tbody></table>
      <p style="font-size:12.5px;color:var(--ink-faint);margin:10px 0 0">Si el proyecto ya tiene el mismo producto, acabado y configuración en esa área, se suman las cantidades.</p>`,
      `<button class="btn btn-outline" data-act="close">Cancelar</button><button class="btn btn-primary" data-act="do-selection">Añadir al proyecto</button>`);
  }
  async function selectionDo(){
    if (S.busy) return;
    const all = getSelection(), items = all.filter(i => isProductAvailable(i.productId));
    const target = hasAreas() ? targetOf(($("#sel-area") || {}).value) : null;
    S.busy = true;
    const { failedCount, totalCount } = await MobauProjects.transferSelectionToProject(S.project.id, items, "sum", target);
    S.busy = false;
    closeModal();
    if (failedCount > 0){
      toast(`Se añadieron ${totalCount - failedCount} de ${totalCount} productos. Tu selección no se modificó: vuelve a intentarlo.`);
    } else {
      clearSelection();
      if (typeof updateSelectionBadge === "function") updateSelectionBadge();
      toast(`${plural(totalCount, "producto añadido", "productos añadidos")}${target ? ` en «${areaName(target)}»` : ""}.`);
    }
    await load();
  }

  async function saveInfo(){
    const name = $("#edit-name").value.trim();
    if (!name){ S.infoError = "Escribe un nombre para el proyecto."; render(); return; }
    if (S.busy) return;
    S.busy = true; S.infoError = "";
    const { data, error } = await MobauProjects.updateProjectInfo(S.project.id, {
      name, project_type: $("#edit-type").value, location: $("#edit-location").value.trim(),
      client_name: $("#edit-client").value.trim(), description: $("#edit-description").value.trim()
    });
    S.busy = false;
    if (error){ S.infoError = error.message; render(); return; }
    S.project = data; S.infoEdit = false;
    toast("Información del proyecto guardada.");
    render();
  }

  /* ---------- eventos ---------- */
  document.addEventListener("click", e => {
    if (!S.project) return;
    const t = e.target.closest("[data-act]");
    if (!e.target.closest(".menu-wrap") && S.pop){ S.pop = null; if (!t){ render(); return; } }
    if (!t) return;
    const act = t.dataset.act, id = t.dataset.id;
    if (act === "veil"){ if (e.target === t) closeModal(); return; }
    if (act === "cf-sum" || act === "cf-skip") return;     // los resuelve conflictModal
    switch (act){
      case "close": closeModal(); break;
      case "open": openLine(id); break;
      case "close-ficha": closeFicha(); break;
      case "pick": S.selected.has(id) ? S.selected.delete(id) : S.selected.add(id); render(); { const b = tileEl(id); if (b) b.querySelector(".tile-btn").focus({ preventScroll: true }); } break;
      case "select-mode": S.selecting = !S.selecting; S.selected.clear(); S.open = null; S.noteEdit = null; S.pop = null; render(); break;
      case "goto": { if (S.pop){ S.pop = null; renderDock(); } const b = document.getElementById("board-" + t.dataset.board); if (b) b.scrollIntoView({ behavior: reduced() ? "auto" : "smooth" }); break; }
      case "to-ledger": $("#ledger").scrollIntoView({ behavior: reduced() ? "auto" : "smooth" }); break;
      case "pop": S.pop = S.pop === t.dataset.key ? null : t.dataset.key; render(); break;
      case "info": S.infoOpen = !S.infoOpen; if (!S.infoOpen) { S.infoEdit = false; S.infoError = ""; } render(); break;
      case "info-edit": S.infoEdit = true; S.infoError = ""; render(); break;
      case "info-cancel": S.infoEdit = false; S.infoError = ""; render(); break;
      case "info-save": e.preventDefault(); saveInfo(); break;
      case "toggle": { const k = t.dataset.key; S.collapsed.has(k) ? S.collapsed.delete(k) : S.collapsed.add(k); render(); break; }
      case "collapse-all": S.areas.forEach(a => S.collapsed.add(a.id)); S.collapsed.add("none"); S.pop = null; render(); break;
      case "expand-all": S.collapsed.clear(); S.pop = null; render(); break;
      case "sel": t.checked ? S.selected.add(id) : S.selected.delete(id); render(); break;
      case "sel-area": { const k = t.dataset.key; S.lines.filter(l => (k === "all" || (l.areaId || "none") === k) && visible(l)).forEach(l => (t.checked ? S.selected.add(l.id) : S.selected.delete(l.id))); render(); break; }
      case "bulk-clear": S.selected.clear(); render(); break;
      case "bulk-remove": { const n = S.selected.size; if (confirm(n === 1 ? "¿Quitar este producto del proyecto?" : `¿Quitar estos ${n} productos del proyecto?`)) removeLines([...S.selected], n === 1 ? "Producto quitado del proyecto." : "Productos quitados del proyecto."); break; }
      case "bulk-move": transfer([...S.selected], targetOf($("#bulk-area").value), "move"); break;
      case "bulk-copy": transfer([...S.selected], targetOf($("#bulk-area").value), "copy"); break;
      case "note": S.pop = null; if (S.noteEdit && S.noteEdit.id === id){ render(); break; } if (!leaveNote()) break; S.open = id; S.noteEdit = { id, draft: lineById(id).note || "", focus: true, status: "" }; keepPlace(render); break;
      case "note-save": saveNote(lineById(id)); break;
      case "note-cancel": if (dirtyNote() && !confirm("Tienes una nota editada sin guardar. ¿Descartar los cambios?")) break; S.noteEdit = null; render(); break;
      case "dec": { const l = lineById(id); saveQty(l, Math.max(unitOf(l) === "ud." ? 1 : 0.01, l.qty - 1)); break; }
      case "inc": { const l = lineById(id); saveQty(l, l.qty + 1); break; }
      case "move1": S.pop = null; keepPlace(render); transfer([id], targetOf(t.dataset.area), "move"); break;
      case "copy1": S.pop = null; keepPlace(render); transfer([id], targetOf(t.dataset.area), "copy"); break;
      case "remove": S.pop = null; if (confirm("¿Quitar este producto del proyecto?")) removeLines([id], "Producto quitado del proyecto."); else render(); break;
      case "fa": { const v = t.dataset.v; if (t.dataset.off || !t.checked) S.filters.areas.delete(v); else S.filters.areas.add(v); render(); break; }
      case "fc": { const v = t.dataset.v; if (t.dataset.off || !t.checked) S.filters.cats.delete(v); else S.filters.cats.add(v); render(); break; }
      case "fa-clear": S.filters.areas.clear(); S.pop = null; render(); break;
      case "fc-clear": S.filters.cats.clear(); S.pop = null; render(); break;
      case "q-clear": S.filters.q = ""; render(); break;
      case "clear-all": S.filters = { q: "", areas: new Set(), cats: new Set() }; render(); break;
      case "ren": S.renaming = id; S.pop = null; render(); break;
      case "up": case "down": S.pop = null; moveArea(id, act).then(() => { if (t.dataset.keep) areasModal(); }); break;
      case "del-area": S.pop = null; render(); deleteAreaAsk(id, t.dataset.keep); break;
      case "da-apply": deleteAreaApply(); break;
      case "archive-ask": S.pop = null; render(); archiveAsk(); break;
      case "archive-do": archiveDo(); break;
      case "reactivate": reactivate(); break;
      case "retry": load(); break;
      case "areas": S.pop = null; render(); areasModal(); break;
      case "organize": S.pop = null; render(); organizeModal(); break;
      case "create-first": createArea($("#first-area").value, () => { closeModal(); toast("Área creada. Tus productos siguen en «Sin área» hasta que los muevas."); }); break;
      case "add-area": createArea($("#new-area").value, () => areasModal()); break;
      case "from-selection": S.pop = null; render(); selectionModal(t.dataset.area || null); break;
      case "do-selection": selectionDo(); break;
      case "rfq": if (!t.disabled) window.location.href = `proyectos-cotizacion.html?id=${encodeURIComponent(S.project.id)}`; break;
    }
  });
  document.addEventListener("change", e => {
    if (!S.project) return;
    const t = e.target, act = t.dataset && t.dataset.act;
    if (act === "qty"){ const l = lineById(t.dataset.id); if (l) saveQty(l, t.value); }
    else if (act === "area-name"){ const a = S.areas.find(x => x.id === t.dataset.id); renameArea(t.dataset.id, t.value).then(() => { if (a) areasModal(); }); }
  });
  let qTimer = null;
  document.addEventListener("input", e => {
    if (!S.project) return;
    const t = e.target;
    if (t.id === "q"){ S.filters.q = t.value; clearTimeout(qTimer); qTimer = setTimeout(render, 120); }
    else if (t.matches && t.matches(".noted textarea")){
      S.noteEdit.draft = t.value; S.noteEdit.status = "";
      const l = lineById(t.dataset.id), btn = document.querySelector(`[data-act="note-save"][data-id="${CSS.escape(t.dataset.id)}"]`), dirty = t.value.trim() !== (l.note || "");
      if (btn) btn.disabled = !dirty;
      const cnt = t.closest(".noted").querySelector(".cnt"); if (cnt) cnt.textContent = `${t.value.length}/${NOTE_MAX}`;
    }
  });
  document.addEventListener("submit", e => { if (e.target.id === "info-form"){ e.preventDefault(); saveInfo(); } });
  document.addEventListener("keydown", e => {
    if (!S.project) return;
    const t = e.target;
    if (t.id === "ren"){
      if (e.key === "Enter"){ const id = t.dataset.id, v = t.value; S.renaming = null; renameArea(id, v); }
      else if (e.key === "Escape"){ S.renaming = null; render(); }
    } else if (t.id === "first-area" && e.key === "Enter"){ const b = document.querySelector('[data-act="create-first"]'); if (b) b.click(); }
    else if (t.id === "new-area" && e.key === "Enter"){ const b = document.querySelector('[data-act="add-area"]'); if (b) b.click(); }
    else if (e.key === "Escape"){ if ($("#modal-root").innerHTML) closeModal(); else if (S.pop){ S.pop = null; render(); } else if (S.open) closeFicha(); }
  });
  document.addEventListener("blur", e => {
    if (S.project && e.target.id === "ren" && S.renaming){ const id = e.target.dataset.id, v = e.target.value; S.renaming = null; renameArea(id, v); }
  }, true);

  /* ---------- arranque ---------- */
  async function init({ project, plan, session, onPlanGate, onLoaded }){
    S.project = project; S.plan = plan; S.session = session; S.userId = session.user.id;
    hooks.onPlanGate = onPlanGate; hooks.onLoaded = onLoaded;
    await refreshAccess();
    await load();
  }
  return { init, state: S, calc, aggregate };
})();
