/* Punto 47 · prototipo local de «Proyecto sencillo por defecto, organización por áreas opcional». Solo mocks (mock-datos-47.js);
   sin red ni Supabase. Es una maqueta para ver y usar el diseño: la lógica de importes, áreas y conflictos imita lo que haría la
   implementación real, pero NO es el motor definitivo.
   Criterio: un proyecto SIN áreas es una lista normal de productos; las áreas aparecen solo cuando la persona pulsa
   «Organizar por áreas» y desaparecen al borrar la última. */
(() => {
  const M = window.MOCK47;
  const $ = (s, r = document) => r.querySelector(s);
  const esc = s => String(s == null ? "" : s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const prod = id => M.CATALOG.find(p => p.id === id);
  const NOTE_MAX = 1000;
  const ICON = {
    search: '<svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="6.5"/><path d="M16 16l5 5"/></svg>',
    note: '<svg viewBox="0 0 24 24"><path d="M5 4h11l3 3v13H5z"/><path d="M8 10h8M8 14h8M8 18h5"/></svg>',
    more: '<svg viewBox="0 0 24 24"><circle cx="5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="19" cy="12" r="1.3"/></svg>',
    chev: '<svg viewBox="0 0 24 24"><path d="M6 9l6 6 6-6"/></svg>'
  };

  /* ---------- estado ---------- */
  const S = {};
  function load(key){
    const sc = M.caso(key);
    Object.assign(S, {
      caso: key, project: sc.project, areas: sc.areas, lines: sc.lines, nextId: 1000,
      collapsed: new Set(), selected: new Set(), filters: { q: "", areas: new Set(), cats: new Set() },
      openCfg: new Set(), noteEdit: null, pop: null, renaming: null, infoOpen: false, detailOpen: false, deleted: false, tipOpen: false,
      arch: [{ id: "x1", name: "Oficina Sur", lines: 12, areas: 3, requested: false, note: "archivado el 14 oct" },
             { id: "x2", name: "Hotel Este", lines: 34, areas: 5, requested: true, note: "archivado el 2 oct" },
             { id: "x3", name: "Casa de playa (sin productos)", lines: 0, areas: 0, requested: false, note: "archivado el 20 sep" }]
    });
    if (S.view === undefined) S.view = "project";
    if (S.pricesOn === undefined){ S.pricesOn = true; S.pstatus = "active"; S.plan = "estudio"; S.currency = "USD"; }
  }
  load("c");
  const hasAreas = () => S.areas.length > 0;
  const ro = () => S.pstatus !== "active";          // archivado o con solicitud enviada: solo consulta
  const areaName = id => (id ? (S.areas.find(a => a.id === id) || {}).name : "Sin área");
  const cfgOf = l => (l.configId ? M.CONFIGS[l.configId] : null);
  const keyOf = l => `${l.productId}|${l.finish}|${l.configId || ""}`;
  const finOf = l => { const p = prod(l.productId); return p.finishes.find(f => f.code === l.finish) || p.finishes[0]; };
  /* Una sola moneda de visualización por proyecto (S.currency); nunca se mezclan ni se convierten: cada precio trae su importe en cada moneda. */
  const fmt = a => (S.currency === "DOP" ? "RD$ " : "US$ ") + Number(a).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const amt = pr => (pr && pr.amounts ? pr.amounts[S.currency] : undefined);
  const curOrder = c => (c === "USD" ? 0 : 1);
  const money = known => Object.keys(known).sort((a, b) => curOrder(a) - curOrder(b) || a.localeCompare(b)).map(c => fmt(known[c], c));

  /* ---------- importes (maqueta del cálculo; el motor definitivo no existe todavía) ----------
     Precio del principal × cantidad; componentes aparte con cantidad fija y precio × cantidad por unidad × cantidad de la línea
     (en anidados, también la de los componentes de arriba); los incluidos no suman; «a calcular» o sin precio dejan la línea
     incompleta (sin inventar una multiplicación); una configuración pendiente queda fuera del importe calculable; monedas separadas. */
  function calc(line){
    const p = prod(line.productId), cfg = cfgOf(line);
    const r = { known: {}, issues: [], pendingCfg: false, status: "completa" };
    if (!S.pricesOn){ r.status = "oculto"; return r; }
    if (cfg && cfg.status === "pendiente"){ r.pendingCfg = true; r.status = "pendiente"; r.issues = (cfg.reasons || []).slice(); return r; }
    const add = (cur, v) => { r.known[cur] = (r.known[cur] || 0) + v; };
    if (amt(p.price) !== undefined) add(S.currency, amt(p.price) * line.qty);
    else r.issues.push(p.price.status === "quote_required" ? "Producto principal bajo cotización" : "Producto principal sin precio");
    function walk(items, factor){
      items.forEach(it => {
        if (it.supply === "incluido") return;
        const fija = factor !== null && it.mode === "fija" && it.qty > 0;
        if (!fija){ r.issues.push(`Cantidad por determinar: ${it.name}`); if (it.nested) walk(it.nested, null); return; }
        const q = Math.round(it.qty * factor * 1000) / 1000;
        if (amt(it.price) === undefined) r.issues.push(`Sin precio: ${it.name}`); else add(S.currency, amt(it.price) * q * line.qty);
        if (it.nested) walk(it.nested, q);
      });
    }
    if (cfg) walk(cfg.items, 1);
    r.status = !r.issues.length ? "completa" : Object.keys(r.known).length ? "parcial" : "sin";
    return r;
  }
  function aggregate(lines){
    const t = { n: lines.length, known: {}, completa: 0, parcial: 0, sin: 0, pendiente: 0 };
    lines.forEach(l => {
      const c = calc(l);
      if (c.status === "oculto") return;
      t[c.status]++;
      if (!c.pendingCfg) Object.keys(c.known).forEach(k => { t.known[k] = (t.known[k] || 0) + c.known[k]; });
    });
    t.pend = t.parcial + t.sin + t.pendiente;
    return t;
  }

  /* ---------- filtros ---------- */
  const filtering = () => !!(S.filters.q.trim() || S.filters.areas.size || S.filters.cats.size);
  function visible(l){
    const f = S.filters, p = prod(l.productId);
    if (f.areas.size && !f.areas.has(l.areaId || "none")) return false;
    if (f.cats.size && !f.cats.has(p.cat)) return false;
    const q = f.q.trim().toLowerCase();
    if (q){
      const hay = [p.name, p.ref, p.brand, finOf(l).name, l.note, hasAreas() ? areaName(l.areaId) : "", (cfgOf(l) || {}).summary].join(" ").toLowerCase();
      if (!q.split(/\s+/).every(w => hay.includes(w))) return false;
    }
    return true;
  }

  /* ---------- piezas de interfaz ---------- */
  function thumb(l){
    const p = prod(l.productId), f = finOf(l);
    const hex = f.color.replace("#", ""), lum = (parseInt(hex.slice(0, 2), 16) * 299 + parseInt(hex.slice(2, 4), 16) * 587 + parseInt(hex.slice(4, 6), 16) * 114) / 1000;
    return `<div class="th${lum > 150 ? " light" : ""}" style="background:${f.color}" role="img" aria-label="${esc(p.name)} · ${esc(f.name)}"><svg viewBox="0 0 24 24">${M.GLYPHS[p.cat]}</svg></div>`;
  }
  function amountHtml(l){
    const c = calc(l);
    if (c.status === "oculto") return `<span class="none" title="Los precios se consultan con un plan Individual o Estudio">—</span>`;
    if (c.status === "pendiente") return `<span class="none" title="${esc(c.issues.join(" · "))}">Sin importe</span><small class="warn" title="${esc(c.issues.join(" · "))}">Configuración pendiente</small>`;
    const m = money(c.known);
    if (c.status === "completa") return `<strong>${esc(m.join(" + "))}</strong><small>ITBIS incluido</small>`;
    if (c.status === "parcial") return `<strong>${esc(m.join(" + "))}</strong><small class="warn" title="${esc(c.issues.join(" · "))}">+ ${c.issues.length} pendiente${c.issues.length > 1 ? "s" : ""}</small>`;
    const p = prod(l.productId);
    return `<span class="none">${p.price.status === "quote_required" ? "Precio bajo cotización" : "Sin precio"}</span><small class="warn" title="${esc(c.issues.join(" · "))}">Se confirmará en la cotización</small>`;
  }
  function cfgLine(l){
    const cfg = cfgOf(l);
    if (!cfg) return "";
    const open = S.openCfg.has(l.id);
    const toggle = `<button class="link" data-act="cfg" data-id="${l.id}" aria-expanded="${open}">${open ? "Ocultar" : "Detalles"}</button>`;
    if (cfg.status === "pendiente") return `<div class="r-cfg"><span class="pbadge warn">Pendiente</span><span class="sum" title="${esc(cfg.summary)}">${esc(cfg.reasons.join(" "))}</span>${toggle}</div>`;
    const c = calc(l);
    const flag = c.status === "parcial" || c.status === "sin" ? `<span class="pbadge cot">Parte por cotizar</span>` : "";
    return `<div class="r-cfg"><span class="pbadge ok">Configurado</span><span class="sum" title="${esc(cfg.summary)}">· ${esc(cfg.summary)}</span>${flag}${toggle}</div>`;
  }
  function cfgPanel(l){
    const cfg = cfgOf(l), c = calc(l);
    const rows = (items, factor, depth) => items.map(it => {
      const fija = factor !== null && it.mode === "fija" && it.qty > 0;
      const tot = fija ? Math.round(it.qty * factor * 1000) / 1000 : null;
      const priceTxt = it.supply === "incluido" ? "No suma" : !S.pricesOn ? "—" : amt(it.price) === undefined ? "Sin precio" : (tot ? fmt(amt(it.price) * tot * l.qty) : `${fmt(amt(it.price))} c/u`);
      return `<tr class="${depth ? "nest" : ""}"><td>${esc(it.name)}<br><span style="color:var(--ink-faint)">Ref. ${esc(it.ref)}</span></td>
        <td class="n">${!fija ? "Cantidad por determinar" : `${tot} por unidad`}</td>
        <td>${it.supply === "incluido" ? "Incluido" : "Se suministra aparte"}</td><td class="n">${esc(priceTxt)}</td></tr>`
        + (it.nested ? rows(it.nested, fija ? it.qty * factor : null, depth + 1) : "");
    }).join("");
    return `<div class="panel"><div class="cfgd"><table><thead><tr><th>Componente</th><th class="n">Cantidad</th><th>Suministro</th><th class="n">Importe</th></tr></thead><tbody>${rows(cfg.items, 1, 0)}</tbody></table>
      ${c.issues.length ? `<p class="issue">${c.pendingCfg ? "Fuera del importe calculable: " : ""}${c.issues.map(esc).join(" · ")}</p>` : ""}
      ${(cfg.notices || []).map(n => `<p>${esc(n)}</p>`).join("")}
      <p>Los importes de componentes aparte se calculan con la cantidad de la línea; los incluidos no se suman. Es información para decidir, no una cotización final.</p></div></div>`;
  }
  function noteLine(l){
    if (S.noteEdit && S.noteEdit.id === l.id) return "";
    if (ro()) return l.note ? `<div class="r-note">${ICON.note}<span class="pv" title="${esc(l.note)}" style="color:var(--ink-soft);font-style:italic;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;min-width:0">${esc(l.note)}</span></div>` : "";
    return l.note
      ? `<div class="r-note">${ICON.note}<button class="link pv" data-act="note" data-id="${l.id}" title="${esc(l.note)}" style="text-decoration:none;color:var(--ink-soft)">${esc(l.note)}</button></div>`
      : `<div class="r-note"><button class="link" data-act="note" data-id="${l.id}">Añadir nota</button></div>`;
  }
  function notePanel(l){
    if (!(S.noteEdit && S.noteEdit.id === l.id)) return "";
    const d = S.noteEdit.draft, dirty = d.trim() !== (l.note || "");
    return `<div class="panel"><div class="noted"><label for="ne-${l.id}" style="font-size:12.5px;color:var(--ink-soft)">Nota técnica (opcional)</label>
      <textarea id="ne-${l.id}" maxlength="${NOTE_MAX}" data-id="${l.id}" placeholder="Ej. medidas especiales, referencia de obra, condiciones de montaje…">${esc(d)}</textarea>
      <div class="bar"><button class="btn btn-primary" data-act="note-save" data-id="${l.id}" ${dirty ? "" : "disabled"}>Guardar</button><button class="btn btn-outline" data-act="note-cancel" data-id="${l.id}">Cancelar</button>
      ${dirty ? `<span style="font-size:12.5px;color:var(--warn)">Cambios sin guardar</span>` : ""}<span class="cnt">${d.length}/${NOTE_MAX}</span></div></div></div>`;
  }
  const targetList = l => [{ id: null, name: "Sin área" }].concat(S.areas).filter(a => a.id !== (l.areaId || null));
  function rowHtml(l){
    const p = prod(l.productId), f = finOf(l), isU = l.unit === "ud.";
    const popKey = "row:" + l.id;
    const targets = hasAreas() ? targetList(l) : [];
    return `<div class="row${S.selected.has(l.id) ? " sel" : ""}" data-id="${l.id}">
      <input class="chk" type="checkbox" data-act="sel" data-id="${l.id}" ${S.selected.has(l.id) ? "checked" : ""} ${ro() ? 'style="visibility:hidden" tabindex="-1"' : ""} aria-label="Seleccionar ${esc(p.name)}">
      ${thumb(l)}
      <div class="r-main">
        <div class="r-name" title="${esc(p.name)}">${esc(p.name)}</div>
        <div class="r-meta">Ref. ${esc(p.ref)} · ${esc(f.name)} · ${esc(p.brand)}</div>
        ${cfgLine(l)}${noteLine(l)}
      </div>
      <div class="r-tail">
        <div class="r-qty"><button data-act="dec" data-id="${l.id}" aria-label="Reducir cantidad" ${ro() ? "disabled" : ""}>−</button><input type="number" data-act="qty" data-id="${l.id}" value="${isU ? Math.round(l.qty) : Math.round(l.qty * 100) / 100}" min="${isU ? 1 : 0.01}" step="${isU ? 1 : 0.01}" inputmode="decimal" aria-label="Cantidad" ${ro() ? "disabled" : ""}><button data-act="inc" data-id="${l.id}" aria-label="Aumentar cantidad" ${ro() ? "disabled" : ""}>+</button><span class="u">${esc(l.unit)}</span></div>
        <div class="r-amt">${amountHtml(l)}</div>
        <div class="r-act">
          <a class="ficha" href="#" onclick="return false" title="Abre la ficha del producto (en la versión real)">Ficha</a>
          <span class="menu-wrap"><button class="iconbtn" data-act="pop" data-key="${popKey}" aria-label="Más acciones" aria-expanded="${S.pop === popKey}">${ICON.more}</button>
            ${S.pop === popKey ? (ro() ? `<div class="pop right"><button data-act="toast" data-msg="Abre la ficha del producto (en la versión real).">Ver ficha</button></div>` : `<div class="pop right">${targets.length ? `<div class="h">Mover a</div>${targets.map(a => `<button data-act="move1" data-id="${l.id}" data-area="${a.id || "none"}">${esc(a.name)}</button>`).join("")}<hr><div class="h">Copiar a</div>${targets.map(a => `<button data-act="copy1" data-id="${l.id}" data-area="${a.id || "none"}">${esc(a.name)}</button>`).join("")}<hr>` : ""}<button data-act="toast" data-msg="Abre la ficha del producto (en la versión real).">Ver ficha</button><button data-act="note" data-id="${l.id}">${l.note ? "Editar nota" : "Añadir nota"}</button><button data-act="remove" data-id="${l.id}" style="color:var(--danger)">Quitar del proyecto</button></div>`) : ""}</span>
        </div>
      </div>
      ${S.openCfg.has(l.id) && cfgOf(l) ? cfgPanel(l) : ""}${notePanel(l)}
    </div>`;
  }

  /* ---------- bloques ---------- */
  const ARCH_ICON = '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4" width="18" height="4" rx="1"/><path d="M5 8v11h14V8"/><path d="M10 12.5h4"/></svg>';
  function renderHeader(){
    const pr = S.project, cats = Object.keys(M.CATEGORIES), empty = !S.lines.length;
    const chip = S.pstatus === "active" ? ["sent", "Activo"] : S.pstatus === "requested" ? ["quoted", "Solicitud enviada"] : ["closed", "Archivado"];
    $("#bc").textContent = pr.name;
    $("#banner").innerHTML = ro() ? `<div class="alert info" style="margin:10px 0 0">Este proyecto está archivado y se conserva para consulta.${S.pstatus === "requested" ? " Tiene una solicitud enviada: su copia y su historial se conservan." : ""} <button class="link" data-act="go-archived">Ver Archivados</button></div>` : "";
    $("#ph").innerHTML = `<div class="ph-main">
        <div class="ph-title"><h1>${esc(pr.name)}</h1><span class="status-chip ${chip[0]}">${chip[1]}</span></div>
        <div class="ph-links"><button class="link" data-act="info" aria-expanded="${S.infoOpen}">Información del proyecto</button></div>
        ${empty ? "" : `<p class="ph-meta">${esc(pr.client)} · ${esc(pr.location)} · ${esc(pr.type)} · <b>${S.lines.length} ${S.lines.length === 1 ? "línea" : "líneas"}</b>${hasAreas() ? ` · ${S.areas.length} ${S.areas.length === 1 ? "área" : "áreas"}` : ""}</p>`}
        ${S.infoOpen ? `<dl class="ph-info"><div><dt>Cliente</dt><dd>${esc(pr.client)}</dd></div><div><dt>Ubicación</dt><dd>${esc(pr.location)}</dd></div><div><dt>Tipo</dt><dd>${esc(pr.type)}</dd></div><div><dt>Actualizado</dt><dd>${esc(pr.updated)}</dd></div>${ro() ? "" : `<div><dt>Datos</dt><dd><button class="link" data-act="toast" data-msg="En la versión real abre la edición de los datos del proyecto.">Editar datos</button></dd></div>`}</dl>` : ""}
      </div>
      <div class="ph-actions">
        <span class="addwrap"><span class="menu-wrap"><button class="btn ${empty && !ro() ? "btn-primary" : "btn-outline"}" data-act="pop" data-key="add" ${ro() ? "disabled" : ""}>Añadir productos ▾</button>
          ${S.pop === "add" && !ro() ? `<div class="pop"><button data-act="from-selection">Desde mi selección <span class="count">${M.SELECTION.length}</span></button><hr><div class="h">Catálogo por categoría</div>${cats.map(c => `<button data-act="toast" data-msg="Prototipo: aquí se abre el catálogo de ${esc(M.CATEGORIES[c])} para añadir al proyecto.">${esc(M.CATEGORIES[c])}</button>`).join("")}<hr><button data-act="toast" data-msg="Prototipo: abre el catálogo completo.">Buscar en todo el catálogo</button></div>` : ""}</span>
          </span>
        <button class="btn btn-outline" data-act="summary" ${empty ? "disabled" : ""}>Ver resumen preliminar</button>
        <button class="btn ${empty || ro() ? "btn-outline" : "btn-primary"}" data-act="rfq" ${empty || ro() ? "disabled" : ""} ${ro() ? 'title="El proyecto ya no admite cambios"' : ""}>Solicitar cotización</button>
        ${S.pstatus === "active" ? `<span class="tipwrap archwrap${S.tipOpen ? " show" : ""}${S.hoverOn ? " hv" : ""}"><button class="btn btn-outline iconarch" data-act="archive-ask" aria-label="Archivar proyecto" aria-describedby="tip-arch">${ARCH_ICON}</button><span id="tip-arch" role="tooltip" class="tip"><b>Archivar proyecto</b>Puedes recuperarlo o eliminarlo desde Archivados.</span></span>` : ""}
      </div>`;
  }
  /* Cuadro económico independiente bajo la cabecera: importe conocido, barra de cobertura con su leyenda y aviso de importe preliminar.
     Una sola moneda de visualización (S.currency); con el filtro activo aparece al lado el del resultado filtrado. */
  function covCard(title, t, cls, sub){
    const m = money(t.known);
    const tot = t.completa + t.parcial + t.sin + t.pendiente || 1;
    const w = k => (t[k] / tot * 100).toFixed(1) + "%";
    return `<div class="tcard ${cls}"><h3>${esc(title)}${sub ? ` · ${esc(sub)}` : ""}</h3>
      <div class="money"><span class="lbl">Importe conocido</span>${m.length ? `<strong>${esc(m[0])}<small>${S.currency === "DOP" ? "pesos dominicanos" : "dólares"} · ITBIS incl.</small></strong>` : `<strong style="font-size:15px;color:var(--ink-soft)">Sin importes conocidos todavía</strong>`}</div>
      <div class="cov" role="img" aria-label="Cobertura de importes"><i class="c1" style="width:${w("completa")}"></i><i class="c2" style="width:${w("parcial")}"></i><i class="c3" style="width:${w("sin")}"></i><i class="c4" style="width:${w("pendiente")}"></i></div>
      <div class="covtxt"><span class="c1">${t.completa} con importe completo</span><span class="c2">${t.parcial} parciales</span><span class="c3">${t.sin} sin precio</span><span class="c4">${t.pendiente} con configuración pendiente</span></div>
      <p class="tnote">Importe preliminar: suma parcial de los importes conocidos. No es una cotización final.</p></div>`;
  }
  function renderTotals(){
    const box = $("#totals");
    if (!S.lines.length){ box.innerHTML = ""; return; }
    if (!S.pricesOn){ box.innerHTML = `<div class="slim"><span class="muted">Importes disponibles con un plan Individual o Estudio.</span><a class="link" href="#" onclick="return false" title="En la versión real abre «Planes»">Ver planes</a></div>`; return; }
    const vis = S.lines.filter(visible);
    box.innerHTML = `<div class="detail">${covCard("Proyecto completo", aggregate(S.lines), "", `${S.lines.length} ${S.lines.length === 1 ? "línea" : "líneas"}`)}${filtering() ? covCard("Resultado filtrado", aggregate(vis), "filtered", `${vis.length} de ${S.lines.length} líneas`) : ""}</div>`;
  }
  function popFilter(kind){
    if (kind === "org"){
      if (!hasAreas()) return `<div class="pop right" style="min-width:270px"><p style="margin:6px 10px 8px;font-size:13px;color:var(--ink-soft)">Agrupa tus productos por habitación o zona. Es opcional: puedes trabajar siempre como lista normal.</p><button data-act="organize">Crear la primera área…</button></div>`;
      const unassigned = S.lines.filter(l => !l.areaId).length;
      const items = S.areas.concat(unassigned ? [{ id: "none", name: "Sin área" }] : []);
      return `<div class="pop right" style="min-width:260px"><div class="h">Filtrar por áreas</div>${items.map(a => `<label><input type="checkbox" data-act="fa" data-v="${a.id}" ${S.filters.areas.has(a.id) ? "checked" : ""}> ${esc(a.name)}<span class="count">${S.lines.filter(l => (l.areaId || "none") === a.id).length}</span></label>`).join("")}${S.filters.areas.size ? `<button data-act="fa-clear">Quitar filtro de áreas</button>` : ""}<hr><button data-act="areas">Gestionar áreas…</button><button data-act="collapse-all">Plegar todas</button><button data-act="expand-all">Desplegar todas</button></div>`;
    }
    const present = Object.keys(M.CATEGORIES).filter(c => S.lines.some(l => prod(l.productId).cat === c));
    return `<div class="pop">${present.map(c => `<label><input type="checkbox" data-act="fc" data-v="${c}" ${S.filters.cats.has(c) ? "checked" : ""}> ${esc(M.CATEGORIES[c])}<span class="count">${S.lines.filter(l => prod(l.productId).cat === c).length}</span></label>`).join("")}<hr><button data-act="fc-clear">Quitar filtro</button></div>`;
  }
  function renderToolbar(){
    const tb = $("#toolbar"), chipsBox = $("#chips");
    if (!S.lines.length){ tb.innerHTML = ""; chipsBox.innerHTML = ""; return; }
    const f = S.filters;
    const keepQ = document.activeElement && document.activeElement.id === "q";
    tb.innerHTML = `<div class="search">${ICON.search}<input id="q" type="search" value="${esc(f.q)}" placeholder="Buscar en el proyecto" aria-label="Buscar en el proyecto"></div>
      <span class="menu-wrap"><button class="tb${f.cats.size ? " on" : ""}" data-act="pop" data-key="catF" aria-haspopup="menu" aria-expanded="${S.pop === "catF"}">Categoría${f.cats.size ? ` <span class="n">${f.cats.size}</span>` : ""} ▾</button>${S.pop === "catF" ? popFilter("catF") : ""}</span>
      ${ro() ? "" : `<span class="menu-wrap"><button class="tb${f.areas.size ? " on" : ""}" data-act="pop" data-key="org" aria-haspopup="menu" aria-expanded="${S.pop === "org"}">Organizar por áreas${f.areas.size ? ` <span class="n">${f.areas.size}</span>` : ""} ▾</button>${S.pop === "org" ? popFilter("org") : ""}</span>`}`;
    if (keepQ){ const q = $("#q"); q.focus(); q.setSelectionRange(q.value.length, q.value.length); }
    const chips = [];
    f.areas.forEach(a => chips.push(`<span class="chip47">Área: ${esc(areaName(a === "none" ? null : a))}<button data-act="fa" data-v="${a}" data-off="1" aria-label="Quitar">×</button></span>`));
    f.cats.forEach(c => chips.push(`<span class="chip47">Categoría: ${esc(M.CATEGORIES[c])}<button data-act="fc" data-v="${c}" data-off="1" aria-label="Quitar">×</button></span>`));
    if (f.q.trim()) chips.push(`<span class="chip47">Búsqueda: «${esc(f.q.trim())}»<button data-act="q-clear" aria-label="Quitar">×</button></span>`);
    chipsBox.innerHTML = chips.length ? chips.join("") + `<button class="link" data-act="clear-all">Limpiar filtros</button>` : "";
  }
  function areaSection(a, idx){
    const all = S.lines.filter(l => (l.areaId || null) === (a ? a.id : null));
    const vis = all.filter(visible);
    if (filtering() && !vis.length) return "";
    if (!a && !all.length) return "";
    const key = a ? a.id : "none", col = S.collapsed.has(key), t = aggregate(all);
    const m = money(t.known);
    const allSel = vis.length && vis.every(l => S.selected.has(l.id));
    const title = S.renaming === key && a ? `<input class="ren" id="ren" value="${esc(a.name)}" maxlength="60" data-id="${a.id}" aria-label="Nombre del área">` : `<h2>${esc(a ? a.name : "Sin área")}</h2>`;
    const popKey = "area:" + key;
    const menu = a && !ro() ? `<span class="menu-wrap"><button class="iconbtn" data-act="pop" data-key="${popKey}" aria-label="Acciones del área">${ICON.more}</button>${S.pop === popKey ? `<div class="pop right"><button data-act="ren" data-id="${a.id}">Renombrar</button><button data-act="up" data-id="${a.id}" ${idx === 0 ? "disabled" : ""}>Subir</button><button data-act="down" data-id="${a.id}" ${idx === S.areas.length - 1 ? "disabled" : ""}>Bajar</button><hr><button data-act="del-area" data-id="${a.id}" style="color:var(--danger)">Eliminar área…</button></div>` : ""}</span>` : "";
    const sub = S.pricesOn ? `${m.length ? `<b>${esc(m.join(" + "))}</b> conocido` : ""}${t.pend ? `${m.length ? " · " : ""}<span style="color:var(--warn)">${t.pend} pendiente${t.pend > 1 ? "s" : ""}</span>` : ""}` : "";
    return `<section class="area${col ? " collapsed" : ""}" data-area="${key}">
      <div class="area-h"><button class="tg" data-act="toggle" data-key="${key}" aria-expanded="${!col}" aria-label="${col ? "Desplegar" : "Plegar"} ${esc(a ? a.name : "Sin área")}">${ICON.chev}</button>
        <input class="chk" type="checkbox" data-act="sel-area" data-key="${key}" ${allSel ? "checked" : ""} ${vis.length ? "" : "disabled"} aria-label="Seleccionar las líneas visibles del área" style="width:17px;height:17px;accent-color:var(--accent)">
        ${title}<span class="cnt">${filtering() ? `${vis.length} de ${all.length}` : all.length} ${all.length === 1 ? "línea" : "líneas"}</span>
        <span class="sub">${sub}</span>${menu}</div>
      <div class="rows">${vis.length ? vis.map(rowHtml).join("") : `<div class="empty" style="border:0">Sin líneas en esta área. Mueve o copia productos aquí desde su menú ⋯ o con la selección múltiple.</div>`}</div></section>`;
  }
  function areaOptionsAll(){ return `<option value="none">Sin área</option>` + S.areas.map(a => `<option value="${a.id}">${esc(a.name)}</option>`).join(""); }
  function renderList(){
    const list = $("#list");
    if (!S.lines.length){
      list.innerHTML = `<div class="empty-state"><h2>Tu proyecto está vacío</h2><p>Añade productos desde el catálogo o desde tu selección. No hace falta configurar nada más: podrás ordenarlos después, si quieres.</p>
        <div class="acts"><button class="btn btn-primary" data-act="from-selection">Añadir desde mi selección (${M.SELECTION.length})</button><button class="btn btn-outline" data-act="toast" data-msg="Prototipo: abre el catálogo.">Explorar el catálogo</button></div></div>`;
    } else if (hasAreas()){
      list.innerHTML = S.areas.map((a, i) => areaSection(a, i)).join("") + areaSection(null)
        || `<div class="empty"><b>Ningún producto coincide con los filtros.</b><br><button class="link" data-act="clear-all">Limpiar filtros</button></div>`;
    } else {
      const vis = S.lines.filter(visible);
      list.innerHTML = vis.length ? `<section class="area flat"><div class="rows">${vis.map(rowHtml).join("")}</div></section>`
        : `<div class="empty"><b>Ningún producto coincide con los filtros.</b><br><button class="link" data-act="clear-all">Limpiar filtros</button></div>`;
    }
    const bulk = $("#bulk"), n = S.selected.size;
    bulk.hidden = !n || ro();
    if (n && !ro()) bulk.innerHTML = `<b>${n} seleccionada${n > 1 ? "s" : ""}</b>${hasAreas() ? `<select id="bulk-area" aria-label="Área de destino">${areaOptionsAll()}</select><button class="btn btn-primary" data-act="bulk-move">Mover</button><button class="btn btn-outline" data-act="bulk-copy">Copiar</button>` : ""}<button class="btn btn-outline" data-act="bulk-remove">Quitar del proyecto</button><button class="btn btn-outline" data-act="bulk-clear">Cancelar</button>`;
  }
  function renderDeleted(){
    $("#ph").innerHTML = ""; $("#banner").innerHTML = ""; $("#totals").innerHTML = ""; $("#toolbar").innerHTML = ""; $("#chips").innerHTML = ""; $("#bulk").hidden = true;
    $("#list").innerHTML = `<div class="empty-state"><h2>Proyecto eliminado</h2><p>«${esc(S.project.name)}» se eliminó, con sus líneas, notas y áreas. Los productos siguen en el catálogo y tus otros proyectos no cambian.</p><div class="acts"><button class="btn btn-primary" data-act="toast" data-msg="Prototipo: vuelve a Mis proyectos.">Volver a mis proyectos</button><button class="btn btn-outline" data-act="reset-case">Deshacer en la demostración</button></div></div>`;
  }
  function render(){
    if (S.view === "archived"){ renderArchived(); return; }
    if (S.deleted){ renderDeleted(); return; }
    renderHeader(); renderTotals(); renderToolbar(); renderList();
    if (S.noteEdit && S.noteEdit.focus){ const t = $(`#ne-${S.noteEdit.id}`); if (t){ t.focus(); t.setSelectionRange(t.value.length, t.value.length); } S.noteEdit.focus = false; }
    if (S.renaming){ const r = $("#ren"); if (r && !r.dataset.done){ r.focus(); r.select(); r.dataset.done = 1; } }
  }

  /* ---------- operaciones ---------- */
  function toast(msg){ const t = document.createElement("div"); t.className = "toast"; t.textContent = msg; $("#toast-root").replaceChildren(t); clearTimeout(toast.t); toast.t = setTimeout(() => t.remove(), 4200); }
  const lineById = id => S.lines.find(l => l.id === id);
  const targetOf = v => (v === "none" || v === "null" || !v ? null : v);
  /* Misma identidad (producto + acabado + configuración) en la MISMA área: la unicidad real tendrá que incluir el área. */
  function sameIdentity(l, areaId, exceptId){ return S.lines.find(o => o.id !== exceptId && (o.areaId || null) === areaId && keyOf(o) === keyOf(l)); }
  const r2 = n => Math.round(n * 100) / 100;

  /* Mover o copiar. Sin conflicto se hace directamente. Si el destino ya tiene una línea equivalente NO se fusiona en silencio:
     se pregunta línea a línea y, si las notas difieren, la persona decide qué nota queda (nunca se elige ni se sobrescribe sola). */
  function transfer(ids, target, kind){
    const res = { moved: 0, copied: 0, summed: 0, skipped: 0 }, queue = [];
    ids.forEach(id => {
      const l = lineById(id); if (!l) return;
      if (kind === "move" && (l.areaId || null) === target) return;
      const twin = sameIdentity(l, target, l.id);
      if (twin){ queue.push({ id: l.id, twin: twin.id }); return; }
      if (kind === "move"){ l.areaId = target; res.moved++; }
      else { S.lines.push(Object.assign({}, l, { id: "l" + (++S.nextId), areaId: target })); res.copied++; }
    });
    const finish = () => {
      closeModal(); render();
      const parts = [];
      if (res.moved) parts.push(`${res.moved} movida${res.moved > 1 ? "s" : ""}`);
      if (res.copied) parts.push(`${res.copied} copiada${res.copied > 1 ? "s" : ""}`);
      if (res.summed) parts.push(`${res.summed} sumada${res.summed > 1 ? "s" : ""} a una línea existente`);
      if (res.skipped) parts.push(`${res.skipped} sin cambios`);
      toast(`«${areaName(target)}»: ${parts.join(" · ") || "sin cambios"}.`);
    };
    const next = () => {
      const item = queue.shift();
      if (!item){ finish(); return; }
      const l = lineById(item.id), twin = lineById(item.twin);
      if (!l || !twin){ next(); return; }
      conflictModal(l, twin, target, kind, choice => {
        if (!choice){ res.skipped++; next(); return; }
        twin.qty = r2(twin.qty + l.qty);
        if (choice === "incoming") twin.note = l.note;
        else if (choice === "both") twin.note = [twin.note, l.note].filter(Boolean).join("\n\n");
        else if (choice === "incoming-only" && !twin.note) twin.note = l.note;
        if (kind === "move"){ S.lines = S.lines.filter(x => x.id !== l.id); S.selected.delete(l.id); }
        res.summed++; next();
      });
    };
    if (queue.length) next(); else finish();
  }
  function conflictModal(l, twin, target, kind, done){
    const p = prod(l.productId), differ = !!(l.note && twin.note && l.note.trim() !== twin.note.trim());
    const sum = r2(twin.qty + l.qty), verb = kind === "move" ? "movida" : "copiada";
    modal("Ya existe en esa área", `<p style="margin:0 0 8px;font-size:14px"><b>${esc(p.name)}</b> · ${esc(finOf(l).name)}${cfgOf(l) ? ` · ${esc(cfgOf(l).summary)}` : ""}<br>Ya está en «${esc(areaName(target))}» con <b>${twin.qty} ${esc(twin.unit)}</b> — ${kind === "move" ? "moverla" : "copiarla"} añadiría ${l.qty} ${esc(l.unit)} más.</p>
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
    root.addEventListener("click", function h(e){
      const t = e.target.closest("[data-act]"); if (!t) return;
      if (t.dataset.act === "cf-skip"){ root.removeEventListener("click", h); done(null); }
      else if (t.dataset.act === "cf-sum"){
        const sel = root.querySelector('input[name="nt"]:checked');
        root.removeEventListener("click", h); done(differ ? sel.value : "incoming-only");
      } else if (t.dataset.act === "close" || (t.dataset.act === "veil" && e.target === t)){ root.removeEventListener("click", h); done(null); }
    });
  }
  const dirtyNote = () => { const e = S.noteEdit; if (!e) return false; const l = lineById(e.id); return !!l && e.draft.trim() !== (l.note || ""); };
  function leaveNote(){ if (dirtyNote() && !confirm("Tienes una nota editada sin guardar. ¿Descartar los cambios?")) return false; S.noteEdit = null; return true; }
  window.addEventListener("beforeunload", e => { if (dirtyNote()){ e.preventDefault(); e.returnValue = ""; } });
  function setQty(l, v){
    let q = parseFloat(String(v).replace(",", "."));
    if (!Number.isFinite(q) || q <= 0) q = l.unit === "ud." ? 1 : 0.01;
    l.qty = l.unit === "ud." ? Math.round(q) : r2(q);
  }

  /* ---------- ventanas ---------- */
  function modal(title, body, footer){
    $("#modal-root").innerHTML = `<div class="veil" data-act="veil"><div class="modal" role="dialog" aria-modal="true" aria-label="${esc(title)}" style="${/Ya existe|Organizar|Añadir desde|Solicitar/.test(title) ? "width:min(600px,100%)" : ""}"><header><h2>${esc(title)}</h2><span style="flex:1"></span><button class="iconbtn" data-act="close" aria-label="Cerrar">✕</button></header><div class="body">${body}</div>${footer ? `<footer>${footer}</footer>` : ""}</div></div>`;
  }
  const closeModal = () => { $("#modal-root").innerHTML = ""; };
  function lineTable(ls){
    return `<table class="sum"><thead><tr><th>Producto</th><th>Acabado</th><th style="text-align:right">Cantidad</th><th style="text-align:right">Importe</th></tr></thead><tbody>${ls.map(l => {
      const p = prod(l.productId), c = calc(l), cfg = cfgOf(l);
      const amt = c.status === "oculto" ? "—" : c.status === "pendiente" ? "Configuración pendiente" : c.status === "sin" ? "Por cotizar" : money(c.known).join(" + ") + (c.status === "parcial" ? " + pendiente" : "");
      return `<tr><td>${esc(p.name)}<br><span style="color:var(--ink-faint)">Ref. ${esc(p.ref)}${cfg ? ` · ${esc(cfg.summary)}` : ""}</span>${l.note ? `<br><em style="color:var(--ink-soft)">Nota: ${esc(l.note.length > 90 ? l.note.slice(0, 90) + "…" : l.note)}</em>` : ""}</td><td>${esc(finOf(l).name)}</td><td class="n" style="text-align:right">${l.qty} ${esc(l.unit)}</td><td class="n" style="text-align:right">${esc(amt)}</td></tr>`;
    }).join("")}</tbody></table>`;
  }
  function summaryModal(){
    const all = aggregate(S.lines), m = money(all.known);
    let body;
    if (!hasAreas()) body = lineTable(S.lines);
    else body = S.areas.concat([null]).map(a => {
      const ls = S.lines.filter(l => (l.areaId || null) === (a ? a.id : null));
      if (!ls.length) return "";
      const t = aggregate(ls), mm = money(t.known);
      return `<div class="sumarea"><h3><span>${esc(a ? a.name : "Sin área")} <span style="font-weight:400;color:var(--ink-soft)">· ${ls.length} ${ls.length === 1 ? "línea" : "líneas"}</span></span><span>${S.pricesOn && mm.length ? esc(mm.join(" + ")) + " conocido" : ""}</span></h3>${lineTable(ls)}</div>`;
    }).join("");
    modal("Resumen preliminar", `<div class="alert info">${S.pricesOn ? `Importe conocido: <b>${esc(m.join(" + ") || "—")}</b>${all.pend ? ` · ${all.pend} ${all.pend === 1 ? "línea pendiente" : "líneas pendientes"}` : ""}. No es una cotización final.` : "Importes disponibles con un plan Individual o Estudio."}</div>${body}`, `<button class="btn btn-outline" data-act="close">Cerrar</button><button class="btn btn-outline" data-act="toast" data-msg="Prototipo: imprimiría el resumen.">Imprimir</button>`);
  }
  function rfqModal(){
    const all = aggregate(S.lines), pend = S.lines.filter(l => cfgOf(l) && cfgOf(l).status === "pendiente");
    const used = S.areas.filter(a => S.lines.some(l => l.areaId === a.id));
    modal("Solicitar cotización", `
      ${pend.length ? `<div class="alert bad"><b>${pend.length} línea${pend.length > 1 ? "s" : ""} con la configuración pendiente.</b> Complétalas o quítalas antes de enviar: ${pend.slice(0, 4).map(l => esc(prod(l.productId).name)).join(", ")}${pend.length > 4 ? "…" : ""}.</div>` : ""}
      <p style="font-size:14px;margin:0 0 8px">Se solicita el <b>proyecto completo</b>: ${S.lines.length} ${S.lines.length === 1 ? "línea" : "líneas"}${used.length ? ` en ${used.length} ${used.length === 1 ? "área" : "áreas"}${S.lines.some(l => !l.areaId) ? " y «Sin área»" : ""}` : ""}. ${filtering() ? "Los filtros de la pantalla no cambian lo que se solicita." : ""}</p>
      ${used.length ? `<p style="font-size:13.5px;color:var(--ink-soft);margin:0 0 8px">Las áreas viajan con la solicitud, con su nombre y su orden actuales.</p>` : ""}
      ${S.pricesOn ? `<p style="font-size:13px;color:var(--ink-soft)">Importe conocido en pantalla: ${esc(money(all.known).join(" + ") || "—")} (referencia parcial); el distribuidor responde con la cotización final.</p>` : ""}
      <div class="field47"><label for="rq-name">Tus datos de contacto</label><input id="rq-name" value="Ana Rosario · Estudio Demo" disabled></div>`,
      `<button class="btn btn-outline" data-act="close">Volver</button><button class="btn btn-primary" data-act="toast" data-msg="Prototipo: no se envía nada." ${pend.length ? "disabled" : ""}>Enviar solicitud</button>`);
  }
  function selectionModal(){
    modal("Añadir desde mi selección", `<p style="margin:0 0 10px;font-size:14px">Se añadirán ${M.SELECTION.length} productos al proyecto.</p>
      ${hasAreas() ? `<div class="optf"><label for="sel-area">Asignar a un área (opcional):</label><select id="sel-area"><option value="none">Sin asignar</option>${S.areas.map(a => `<option value="${a.id}">${esc(a.name)}</option>`).join("")}</select></div>` : ""}
      <table class="sum"><thead><tr><th>Producto</th><th>Acabado</th><th style="text-align:right">Cantidad</th></tr></thead><tbody>${M.SELECTION.map(s => { const p = prod(s.productId); const f = p.finishes.find(x => x.code === s.finish) || p.finishes[0]; return `<tr><td>${esc(p.name)}${s.configId ? `<br><span style="color:var(--ink-faint)">${esc(M.CONFIGS[s.configId].summary)}</span>` : ""}</td><td>${esc(f.name)}</td><td class="n" style="text-align:right">${s.qty} ${esc(s.unit)}</td></tr>`; }).join("")}</tbody></table>
      <p style="font-size:12.5px;color:var(--ink-faint);margin:10px 0 0">Si el proyecto ya tiene el mismo producto, acabado y configuración, se actualiza su cantidad.</p>`,
      `<button class="btn btn-outline" data-act="close">Cancelar</button><button class="btn btn-primary" data-act="do-selection">Añadir al proyecto</button>`);
  }
  function organizeModal(){
    modal("Organizar por áreas", `<p style="margin:0 0 12px;font-size:14px">Crea la primera área, por ejemplo una habitación o una zona de obra. <b>No se reparte nada automáticamente</b>: tus productos quedan en «Sin área» hasta que quieras moverlos, y puedes seguir añadiendo productos sin asignarlos.</p>
      <div class="field47"><label for="first-area">Nombre de la primera área</label><input id="first-area" type="text" maxlength="60" placeholder="Ej. Sala, Cocina, Habitación 1" style="width:100%"></div>`,
      `<button class="btn btn-outline" data-act="close">Cancelar</button><button class="btn btn-primary" data-act="create-first">Crear área</button>`);
    setTimeout(() => { const i = $("#first-area"); if (i) i.focus(); }, 30);
  }
  function areasModal(){
    modal("Gestionar áreas", `<p style="margin:0 0 10px;font-size:14px">Crea, renombra y ordena las áreas. Al eliminar un área sus líneas pasan a «Sin área»; nunca se elimina ningún producto. Si eliminas todas, el proyecto vuelve a ser una lista sencilla.</p>
      <div class="arealist">${S.areas.map((a, i) => `<div class="it"><input type="text" value="${esc(a.name)}" maxlength="60" data-act="area-name" data-id="${a.id}" aria-label="Nombre del área"><span style="font-size:12.5px;color:var(--ink-faint);min-width:64px">${S.lines.filter(l => l.areaId === a.id).length} líneas</span>
        <button class="iconbtn" data-act="up" data-id="${a.id}" data-keep="1" ${i === 0 ? "disabled" : ""} aria-label="Subir">↑</button><button class="iconbtn" data-act="down" data-id="${a.id}" data-keep="1" ${i === S.areas.length - 1 ? "disabled" : ""} aria-label="Bajar">↓</button>
        <button class="iconbtn" data-act="del-area" data-id="${a.id}" data-keep="1" aria-label="Eliminar" style="color:var(--danger)">🗑</button></div>`).join("")}
        <div class="it"><input type="text" id="new-area" placeholder="Nombre de la nueva área" maxlength="60"><button class="btn btn-primary" data-act="add-area" style="padding:8px 16px">Crear área</button></div></div>
        <p style="font-size:12.5px;color:var(--ink-faint);margin:10px 0 0">«Sin área» reúne lo que no está asignado, va al final y no se puede renombrar.</p>`, `<button class="btn btn-outline" data-act="close">Listo</button>`);
  }
  function archiveAsk(){
    const n = S.lines.length;
    modal("Archivar proyecto", `<p style="margin:0 0 8px;font-size:14px">Vas a archivar <b>«${esc(S.project.name)}»</b>.</p>
      <p style="margin:0 0 8px;font-size:14px;color:var(--ink-soft)">Se conserva${n ? ` con sus ${n} ${n === 1 ? "línea" : "líneas"}` : ""}, solo para consulta. <b>No se elimina.</b> Puedes recuperarlo o eliminarlo desde Archivados.</p>
      <p style="margin:0;font-size:13px;color:var(--ink-faint)">${S.plan === "estudio" ? "Recuperarlo requiere cupo de proyectos activos en tu plan." : "Tu plan actual no permite recuperar proyectos archivados."}</p>`,
      `<button class="btn btn-outline" data-act="close">Cancelar</button><button class="btn btn-primary" data-act="archive-do">Archivar proyecto</button>`);
  }
  /* Archivados (vista simulada mínima, solo para enseñar restaurar y eliminar). Eliminar solo existe aquí y nunca en proyectos con solicitudes. */
  const archList = () => {
    const base = S.arch.slice();
    if (S.pstatus !== "active") base.unshift({ id: "cur", name: S.project.name, lines: S.lines.length, areas: S.areas.length, requested: S.pstatus === "requested", note: "Este es el proyecto que estabas viendo" });
    return base;
  };
  function renderArchived(){
    $("#ph").innerHTML = ""; $("#banner").innerHTML = ""; $("#totals").innerHTML = ""; $("#toolbar").innerHTML = ""; $("#chips").innerHTML = ""; $("#bulk").hidden = true;
    $("#bc").textContent = "Archivados";
    const items = archList();
    $("#list").innerHTML = `<div class="archhead"><h1>Archivados</h1><button class="link" data-act="go-project">← Volver al proyecto</button></div>
      <p style="margin:0 0 12px;color:var(--ink-soft);font-size:14px">Los proyectos archivados se conservan para consulta. Desde aquí puedes restaurarlos o eliminarlos.</p>
      ${items.length ? items.map(it => `<div class="archcard"><div><b>${esc(it.name)}</b> <span class="status-chip ${it.requested ? "quoted" : "closed"}">${it.requested ? "Solicitud enviada" : "Archivado"}</span>
          <div class="sub">${it.lines} ${it.lines === 1 ? "línea" : "líneas"}${it.areas ? ` · ${it.areas} áreas` : ""}${it.note ? ` · ${esc(it.note)}` : ""}</div>
          ${it.requested ? `<div class="sub warn">No se puede eliminar: tiene solicitudes enviadas, que se conservan con su historial.</div>` : ""}
          ${S.plan === "individual" ? `<div class="sub">Tu plan actual no permite restaurar proyectos archivados.</div>` : ""}</div>
        <div class="acts"><button class="btn btn-outline btn-sm" data-act="arch-consult" data-id="${it.id}">Consultar</button>
          <button class="btn btn-outline btn-sm" data-act="arch-restore" data-id="${it.id}" ${S.plan === "individual" ? "disabled" : ""}>Restaurar</button>
          ${it.requested ? "" : `<button class="btn btn-outline btn-sm danger" data-act="arch-delete-ask" data-id="${it.id}">Eliminar</button>`}</div></div>`).join("") : `<div class="empty">No tienes proyectos archivados.</div>`}`;
  }
  function deleteAsk(it){
    const n = it.lines, k = it.areas;
    modal("Eliminar proyecto", `<p style="margin:0 0 8px;font-size:14px">¿Eliminar <b>«${esc(it.name)}»</b>?</p>
      <p style="margin:0 0 6px;font-size:14px">${n ? `Se eliminarán el proyecto y sus <b>${n} ${n === 1 ? "línea" : "líneas"}</b> (cantidades, notas y configuraciones)${k ? ` y sus ${k} ${k === 1 ? "área" : "áreas"}` : ""}.` : "Este proyecto no tiene productos: se eliminará el proyecto."}</p>
      <p style="margin:0 0 6px;font-size:13.5px;color:var(--ink-soft)">No se elimina ningún producto del catálogo ni se modifican otros proyectos.</p>
      <p style="margin:0;font-size:13.5px;color:var(--danger)"><b>Esta acción no se puede deshacer.</b></p>`,
      `<button class="btn btn-outline" data-act="close">Cancelar</button><button class="btn btn-primary" data-act="arch-delete-do" data-id="${it.id}" style="background:var(--danger);border-color:var(--danger)">Eliminar proyecto</button>`);
  }

  /* Eliminar un área: sus líneas pasan a «Sin área». Sin conflictos, una confirmación breve. Si alguna línea ya tiene su equivalente en
     «Sin área», se resuelve ANTES de completar (sumar o mover a otra área); cancelar no cambia nada; no se pierden notas ni configuraciones. */
  let pendingDel = null;
  function deleteAreaAsk(id, keep){
    const a = S.areas.find(x => x.id === id), mine = S.lines.filter(l => l.areaId === id);
    const conflicts = mine.map(l => ({ l, twin: sameIdentity(l, null, l.id) })).filter(x => x.twin);
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
        const free = others.filter(o => !sameIdentity(c.l, o.id, c.l.id));
        return `<div class="cflt" data-i="${i}"><p style="margin:0 0 6px;font-size:13.5px"><b>${esc(p.name)}</b> · ${esc(finOf(c.l).name)}${cfgOf(c.l) ? ` · ${esc(cfgOf(c.l).summary)}` : ""}<br>En «${esc(a.name)}»: ${c.l.qty} ${esc(c.l.unit)} · En «Sin área»: ${c.twin.qty} ${esc(c.twin.unit)}</p>
          ${differ ? `<div class="cmp"><div><small>Nota en «Sin área»</small>${esc(c.twin.note)}</div><div><small>Nota en «${esc(a.name)}»</small>${esc(c.l.note)}</div></div>` : ""}
          <label class="rd"><input type="radio" name="r${i}" value="sum"> Sumar cantidades (${c.twin.qty} + ${c.l.qty} = ${r2(c.twin.qty + c.l.qty)})</label>
          ${differ ? `<div class="rd-sub">Notas distintas, ¿cuál queda?
            <label class="rd"><input type="radio" name="n${i}" value="existing"> La de «Sin área»</label><label class="rd"><input type="radio" name="n${i}" value="incoming"> La de «${esc(a.name)}»</label><label class="rd"><input type="radio" name="n${i}" value="both"> Las dos, una detrás de otra</label></div>` : ""}
          ${free.length ? `<label class="rd"><input type="radio" name="r${i}" value="move"> Mover esta línea a otra área: <select name="m${i}">${free.map(o => `<option value="${o.id}">${esc(o.name)}</option>`).join("")}</select></label>` : ""}</div>`;
      }).join("")}`,
      `<button class="btn btn-outline" data-act="close">Cancelar sin cambios</button><button class="btn btn-primary" data-act="da-apply" disabled>Eliminar el área y aplicar</button>`);
    const root = $("#modal-root"), btn = root.querySelector('[data-act="da-apply"]');
    const ready = () => conflicts.every((c, i) => {
      const rv = root.querySelector(`input[name="r${i}"]:checked`);
      if (!rv) return false;
      const differ = !!(c.l.note && c.twin.note && c.l.note.trim() !== c.twin.note.trim());
      return rv.value === "move" || !differ || !!root.querySelector(`input[name="n${i}"]:checked`);
    });
    root.addEventListener("change", () => { btn.disabled = !ready(); });
  }
  function deleteAreaApply(){
    const d = pendingDel; if (!d) return;
    const root = $("#modal-root");
    d.conflicts.forEach((c, i) => {
      const rv = root.querySelector(`input[name="r${i}"]:checked`).value;
      if (rv === "move"){ c.l.areaId = root.querySelector(`select[name="m${i}"]`).value; return; }
      const nv = (root.querySelector(`input[name="n${i}"]:checked`) || {}).value;
      c.twin.qty = r2(c.twin.qty + c.l.qty);
      if (nv === "incoming") c.twin.note = c.l.note;
      else if (nv === "both") c.twin.note = [c.twin.note, c.l.note].filter(Boolean).join("\n\n");
      else if (!c.twin.note) c.twin.note = c.l.note;
      S.lines = S.lines.filter(x => x.id !== c.l.id);
    });
    S.lines.filter(l => l.areaId === d.id).forEach(l => { l.areaId = null; });
    S.areas = S.areas.filter(x => x.id !== d.id); S.filters.areas.delete(d.id); S.collapsed.delete(d.id); S.pop = null;
    const msg = S.areas.length ? "Área eliminada; sus líneas están en «Sin área»." : "Sin áreas: el proyecto vuelve a ser una lista sencilla.";
    if (!S.areas.length){ S.filters.areas.clear(); S.collapsed.clear(); }
    closeModal(); pendingDel = null; render(); toast(msg); if (d.keep && S.areas.length) areasModal();
  }

  /* ---------- eventos ---------- */
  document.addEventListener("click", e => {
    const t = e.target.closest("[data-act]");
    if (!e.target.closest(".menu-wrap") && S.pop){ S.pop = null; if (!t){ render(); return; } }
    if (!t) return;
    const act = t.dataset.act, id = t.dataset.id;
    if (act === "veil"){ if (e.target === t) closeModal(); return; }
    if (act === "cf-sum" || act === "cf-skip") return;     // los resuelve conflictModal
    switch (act){
      case "close": closeModal(); break;
      case "toast": toast(t.dataset.msg); S.pop = null; render(); break;
      case "pop": S.pop = S.pop === t.dataset.key ? null : t.dataset.key; render(); break;
      case "info": S.infoOpen = !S.infoOpen; render(); break;
      case "detail": S.detailOpen = !S.detailOpen; render(); break;
      case "toggle": { const k = t.dataset.key; S.collapsed.has(k) ? S.collapsed.delete(k) : S.collapsed.add(k); render(); break; }
      case "collapse-all": S.areas.forEach(a => S.collapsed.add(a.id)); S.collapsed.add("none"); S.pop = null; render(); break;
      case "expand-all": S.collapsed.clear(); S.pop = null; render(); break;
      case "sel": t.checked ? S.selected.add(id) : S.selected.delete(id); render(); break;
      case "sel-area": { const k = t.dataset.key; S.lines.filter(l => (l.areaId || "none") === k && visible(l)).forEach(l => (t.checked ? S.selected.add(l.id) : S.selected.delete(l.id))); render(); break; }
      case "bulk-clear": S.selected.clear(); render(); break;
      case "bulk-remove": if (confirm(`¿Quitar ${S.selected.size} líneas del proyecto? Los productos no se eliminan del catálogo.`)){ S.lines = S.lines.filter(l => !S.selected.has(l.id)); S.selected.clear(); toast("Líneas quitadas del proyecto."); } render(); break;
      case "bulk-move": { const ids = [...S.selected]; S.selected.clear(); transfer(ids, targetOf($("#bulk-area").value), "move"); break; }
      case "bulk-copy": { const ids = [...S.selected]; S.selected.clear(); transfer(ids, targetOf($("#bulk-area").value), "copy"); break; }
      case "cfg": S.openCfg.has(id) ? S.openCfg.delete(id) : S.openCfg.add(id); render(); break;
      case "note": S.pop = null; if (S.noteEdit && S.noteEdit.id === id){ render(); break; } if (!leaveNote()) break; S.noteEdit = { id, draft: lineById(id).note || "", focus: true }; render(); break;
      case "note-save": { const l = lineById(id); l.note = S.noteEdit.draft.trim().slice(0, NOTE_MAX); S.noteEdit = null; render(); toast(l.note ? "Nota guardada." : "Nota eliminada."); break; }
      case "note-cancel": if (dirtyNote() && !confirm("Tienes una nota editada sin guardar. ¿Descartar los cambios?")) break; S.noteEdit = null; render(); break;
      case "dec": { const l = lineById(id); setQty(l, l.qty - 1); render(); break; }
      case "inc": { const l = lineById(id); setQty(l, l.qty + 1); render(); break; }
      case "move1": S.pop = null; transfer([id], targetOf(t.dataset.area), "move"); break;
      case "copy1": S.pop = null; transfer([id], targetOf(t.dataset.area), "copy"); break;
      case "remove": if (confirm("¿Quitar esta línea del proyecto? El producto no se elimina del catálogo.")){ S.lines = S.lines.filter(l => l.id !== id); S.selected.delete(id); toast("Línea quitada del proyecto."); } S.pop = null; render(); break;
      case "fa": { const v = t.dataset.v; if (t.dataset.off || !t.checked) S.filters.areas.delete(v); else S.filters.areas.add(v); render(); break; }
      case "fc": { const v = t.dataset.v; if (t.dataset.off || !t.checked) S.filters.cats.delete(v); else S.filters.cats.add(v); render(); break; }
      case "fa-clear": S.filters.areas.clear(); S.pop = null; render(); break;
      case "fc-clear": S.filters.cats.clear(); S.pop = null; render(); break;
      case "q-clear": S.filters.q = ""; render(); break;
      case "clear-all": S.filters = { q: "", areas: new Set(), cats: new Set() }; render(); break;
      case "ren": S.renaming = id; S.pop = null; render(); break;
      case "up": case "down": { const i = S.areas.findIndex(a => a.id === id), j = act === "up" ? i - 1 : i + 1; if (S.areas[j]){ [S.areas[i], S.areas[j]] = [S.areas[j], S.areas[i]]; } S.pop = null; render(); if (t.dataset.keep) areasModal(); break; }
      case "del-area": S.pop = null; render(); deleteAreaAsk(id, t.dataset.keep); break;
      case "da-apply": deleteAreaApply(); break;
      case "archive-ask": S.pop = null; render(); archiveAsk(); break;
      case "archive-do": S.pstatus = "archived"; S.noteEdit = null; S.selected.clear(); closeModal(); render(); toast("Proyecto archivado. Lo encontrarás en Archivados."); break;
      case "go-archived": S.view = "archived"; pressed("#seg-v", "v", "archived"); render(); break;
      case "go-project": S.view = "project"; pressed("#seg-v", "v", "project"); render(); break;
      case "arch-consult": if (id === "cur"){ S.view = "project"; pressed("#seg-v", "v", "project"); render(); } else toast("Prototipo: abre ese proyecto archivado, en solo consulta."); break;
      case "arch-restore": { const it = archList().find(x => x.id === id); if (id === "cur"){ S.pstatus = "active"; toast(`«${it.name}» restaurado: vuelve a ser un proyecto de trabajo.`); } else { S.arch = S.arch.filter(x => x.id !== id); toast(`«${it.name}» restaurado: vuelve a Mis proyectos.`); } render(); break; }
      case "arch-delete-ask": deleteAsk(archList().find(x => x.id === id)); break;
      case "arch-delete-do": { const it = archList().find(x => x.id === id); closeModal(); if (id === "cur"){ S.deleted = true; S.view = "project"; pressed("#seg-v", "v", "project"); } else { S.arch = S.arch.filter(x => x.id !== id); } render(); toast(`«${it.name}» eliminado.`); break; }
      case "reset-case": load(S.caso); render(); break;
      case "noop": break;
      case "areas": S.pop = null; render(); areasModal(); break;
      case "organize": organizeModal(); break;
      case "create-first": { const v = $("#first-area").value.trim(); if (!v){ toast("Escribe un nombre para el área."); break; } S.areas.push({ id: "a" + (++S.nextId), name: v }); closeModal(); render(); toast(`Área «${v}» creada. Tus productos siguen en «Sin área» hasta que los muevas.`); break; }
      case "add-area": { const v = $("#new-area").value.trim(); if (!v){ toast("Escribe un nombre para el área."); break; } if (S.areas.some(a => a.name.toLowerCase() === v.toLowerCase())){ toast("Ya existe un área con ese nombre."); break; } S.areas.push({ id: "a" + (++S.nextId), name: v }); render(); areasModal(); break; }
      case "summary": summaryModal(); break;
      case "rfq": rfqModal(); break;
      case "from-selection": S.pop = null; render(); selectionModal(); break;
      case "do-selection": { const target = hasAreas() ? targetOf($("#sel-area").value) : null; let upd = 0, ins = 0;
        M.SELECTION.forEach(s => { const probe = { productId: s.productId, finish: s.finish, configId: s.configId }; const twin = sameIdentity(probe, target, null);
          if (twin){ twin.qty = s.qty; upd++; } else { S.lines.push({ id: "l" + (++S.nextId), productId: s.productId, finish: s.finish, qty: s.qty, unit: s.unit, areaId: target, note: "", configId: s.configId }); ins++; } });
        closeModal(); render(); toast(`${ins} producto${ins === 1 ? "" : "s"} añadido${ins === 1 ? "" : "s"}${upd ? `, ${upd} con cantidad actualizada` : ""}${hasAreas() && target ? ` en «${areaName(target)}»` : ""}.`); break; }
    }
  });
  document.addEventListener("change", e => {
    const t = e.target, act = t.dataset && t.dataset.act;
    if (act === "qty"){ setQty(lineById(t.dataset.id), t.value); render(); }
    else if (act === "area-name"){ const a = S.areas.find(x => x.id === t.dataset.id); const v = t.value.trim(); if (v && !S.areas.some(o => o.id !== a.id && o.name.toLowerCase() === v.toLowerCase())) a.name = v; else t.value = a.name; render(); }
  });
  let qTimer = null;
  document.addEventListener("input", e => {
    const t = e.target;
    if (t.id === "q"){ S.filters.q = t.value; clearTimeout(qTimer); qTimer = setTimeout(render, 120); }
    else if (t.matches && t.matches(".noted textarea")){
      S.noteEdit.draft = t.value;
      const l = lineById(t.dataset.id), btn = document.querySelector(`[data-act="note-save"][data-id="${t.dataset.id}"]`), dirty = t.value.trim() !== (l.note || "");
      if (btn) btn.disabled = !dirty;
      const cnt = t.closest(".noted").querySelector(".cnt"); if (cnt) cnt.textContent = `${t.value.length}/${NOTE_MAX}`;
    }
  });
  document.addEventListener("keydown", e => {
    const t = e.target;
    if (t.id === "ren"){
      if (e.key === "Enter"){ const a = S.areas.find(x => x.id === t.dataset.id), v = t.value.trim(); if (v && !S.areas.some(o => o.id !== a.id && o.name.toLowerCase() === v.toLowerCase())) a.name = v; S.renaming = null; render(); }
      else if (e.key === "Escape"){ S.renaming = null; render(); }
    } else if (t.id === "first-area" && e.key === "Enter"){ document.querySelector('[data-act="create-first"]').click(); }
    else if (e.key === "Escape"){ if ($("#modal-root").innerHTML) closeModal(); else if (S.pop){ S.pop = null; render(); } }
  });
  document.addEventListener("blur", e => {
    if (e.target.id === "ren" && S.renaming){
      const a = S.areas.find(x => x.id === e.target.dataset.id), v = e.target.value.trim();
      if (a && v && !S.areas.some(o => o.id !== a.id && o.name.toLowerCase() === v.toLowerCase())) a.name = v;
      S.renaming = null; render();
    }
  }, true);
  const pressed = (box, attr, val) => [...$(box).children].forEach(x => x.setAttribute("aria-pressed", String(x.dataset[attr] === val)));
  $("#seg-n").addEventListener("click", e => { const b = e.target.closest("button"); if (!b) return; if (!leaveNote()) return; load(b.dataset.c); pressed("#seg-n", "c", b.dataset.c); render(); });
  $("#seg-m").addEventListener("click", e => { const b = e.target.closest("button"); if (!b) return; S.currency = b.dataset.m; pressed("#seg-m", "m", b.dataset.m); render(); });
  $("#seg-e").addEventListener("click", e => { const b = e.target.closest("button"); if (!b) return; if (!leaveNote()) return; S.pstatus = b.dataset.e; S.deleted = false; S.pop = null; pressed("#seg-e", "e", b.dataset.e); render(); });
  $("#seg-v").addEventListener("click", e => { const b = e.target.closest("button"); if (!b) return; if (!leaveNote()) return; S.view = b.dataset.v; S.deleted = false; pressed("#seg-v", "v", b.dataset.v); render(); });
  $("#seg-l").addEventListener("click", e => { const b = e.target.closest("button"); if (!b) return; S.plan = b.dataset.l; pressed("#seg-l", "l", b.dataset.l); render(); });
  $("#seg-p").addEventListener("click", e => { const b = e.target.closest("button"); if (!b) return; S.pricesOn = b.dataset.p === "1"; pressed("#seg-p", "p", b.dataset.p); render(); });
  $("#reset").addEventListener("click", () => { if (!leaveNote()) return; load(S.caso); render(); });
  window.__P47 = { S, calc, aggregate, transfer };   // solo para inspeccionar el prototipo desde la consola

  /* Atajos de la dirección (para revisar y para las capturas):
     ?caso=a|b|c|d  ·  ?precios=0  ·  ?demo=detalles | nota | filtro | menu | resumen | solicitud | areas | seleccion | organizar | conflicto | desglose */
  const qp = new URLSearchParams(location.search);
  const caso = qp.get("caso") || (qp.get("n") === "100" ? "d" : "c");
  load(caso); pressed("#seg-n", "c", caso);
  if (qp.get("precios") === "0"){ S.pricesOn = false; pressed("#seg-p", "p", "0"); }
  const mon = (qp.get("moneda") || "").toUpperCase(); if (mon === "DOP"){ S.currency = "DOP"; pressed("#seg-m", "m", "DOP"); }
  const est = qp.get("estado"); if (est === "archivado" || est === "solicitud"){ S.pstatus = est === "archivado" ? "archived" : "requested"; pressed("#seg-e", "e", S.pstatus); }
  if (qp.get("plan") === "individual"){ S.plan = "individual"; pressed("#seg-l", "l", "individual"); }
  const demo = qp.get("demo");
  if (demo === "detalles"){ S.lines.filter(l => cfgOf(l)).slice(0, 3).forEach(l => S.openCfg.add(l.id)); }
  if (demo === "nota"){ const l = S.lines.find(x => x.note) || S.lines[0]; S.noteEdit = { id: l.id, draft: (l.note || "") + " Añadido en la edición, todavía sin guardar.", focus: false }; }
  if (demo === "filtro" && hasAreas()){ S.filters.areas.add(S.areas[0].id); S.filters.cats.add("iluminacion"); }
  if (demo === "filtro" && !hasAreas()){ S.filters.cats.add("mobiliario"); }
  if (demo === "menu"){ const l = S.lines[1] || S.lines[0]; S.pop = "row:" + l.id; }
  if (demo === "desglose"){ S.detailOpen = true; }
  render();
  if (demo === "resumen") summaryModal();
  if (demo === "solicitud") rfqModal();
  if (demo === "areas" && hasAreas()) areasModal();
  if (demo === "seleccion") selectionModal();
  if (demo === "organizar") organizeModal();
  if (qp.get("vista") === "archivados"){ S.view = "archived"; pressed("#seg-v", "v", "archived"); render(); }
  if (demo === "tooltip"){ S.tipOpen = true; render(); }
  if (demo === "hover"){ S.tipOpen = true; S.hoverOn = true; render(); }
  if (demo === "foco"){ S.tipOpen = true; render(); const b = $(".iconarch"); if (b) b.focus(); }
  if (demo === "organizar-menu"){ S.pop = "org"; render(); }
  if (demo === "archivar") archiveAsk();
  if (demo === "eliminar"){ S.view = "archived"; pressed("#seg-v", "v", "archived"); render(); deleteAsk(archList().find(x => x.id === "x1")); }
  if (demo === "conflicto-area" && hasAreas()){
    /* Prepara un conflicto real: una silla de «Cocina» y otra igual ya sin área, con notas distintas. */
    const cocina = S.areas[1], silla = S.lines.find(l => l.productId === "silla-tolu" && l.areaId === cocina.id);
    if (silla){ silla.note = "Pedir muestra del tapizado."; S.lines.push(Object.assign({}, silla, { id: "l" + (++S.nextId), areaId: null, qty: 2, note: "Medida del brazo: confirmar con el cliente." })); }
    render(); deleteAreaAsk(cocina.id);
  }
  if (demo === "conflicto" && hasAreas()){ const sillas = S.lines.filter(l => l.productId === "silla-tolu"); if (sillas.length > 1){ sillas[0].note = "Medida del brazo: confirmar con el cliente."; sillas[1].note = "Pedir muestra del tapizado."; transfer([sillas[0].id], sillas[1].areaId, "move"); } }
})();
