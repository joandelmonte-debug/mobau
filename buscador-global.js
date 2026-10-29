/* ============================================================
   MOBAU — Buscador global de la cabecera (Punto 49)
   ------------------------------------------------------------
   Va después de script.js, que tiene el motor (MobauBusqueda) y la carga del catálogo (loadCatalog). No cambia la
   sesión, el rol ni los permisos: «Mi cuenta / Iniciar sesión» y «Mi selección» siguen siendo de nav-session.js.
   - Patrón combobox de WAI-ARIA: ↓/↑ recorren las sugerencias, Intro abre la marcada (o, sin marca, envía el
     formulario a catalogo.html?q=…), Esc cierra sin borrar, Tab y un clic fuera cierran. Borrar: el botón ✕.
   - El catálogo se pide al enfocar o abrir la búsqueda con loadCatalog(), que reutiliza la carga en curso o ya
     hecha (script.js la empieza al abrir la página); nunca al pasar el puntero.
   - En móvil, ⌕ abre la búsqueda a pantalla completa.
   - En Productos (catalogo.html), el campo es el buscador de la página: al escribir se filtra la rejilla (evento
     «mobau:consulta»), sin sugerencias; en la hoja móvil hay sugerencias e Intro aplica la consulta a la rejilla.
   Sin JavaScript, el formulario solo navega a catalogo.html?q=…; los resultados necesitan JavaScript.
   ============================================================ */
(() => {
  const form = document.querySelector(".site-header .gsearch");
  if (!form || typeof MobauBusqueda === "undefined") return;
  const input = form.querySelector("input[name=q]");
  const clear = form.querySelector(".gsearch-clear");
  const panel = form.querySelector(".gsearch-panel");
  const live = form.querySelector(".gsearch-live");
  const openBtn = document.querySelector(".site-header .gsearch-open");
  const closeBtn = form.querySelector(".gsearch-close");
  const EN_PRODUCTOS = !!document.getElementById("product-grid") && /catalogo\.html$/.test(location.pathname);
  const hojaAbierta = () => document.body.classList.contains("gsearch-sheet");
  const local = () => EN_PRODUCTOS && !hojaAbierta();
  const avisarProductos = texto => document.dispatchEvent(new CustomEvent("mobau:consulta", { detail: texto }));

  /* ---------- carga del catálogo ---------- */
  let estado = "idle"; // idle | cargando | listo | error
  function asegurarCatalogo(){
    if (estado === "listo" || estado === "cargando") return;
    estado = "cargando";
    loadCatalog().then(() => { estado = "listo"; pintar(); }, () => { estado = "error"; pintar(); });
  }

  /* ---------- panel ---------- */
  let opciones = [], activa = -1, temporizador = null;
  const abierto = () => !panel.hidden;
  function abrir(){ panel.hidden = false; input.setAttribute("aria-expanded", "true"); }
  function cerrar(){ panel.hidden = true; input.setAttribute("aria-expanded", "false"); marcar(-1); }
  function marcar(i){
    activa = i;
    opciones.forEach((li, k) => li.setAttribute("aria-selected", k === i ? "true" : "false"));
    if (i >= 0){ input.setAttribute("aria-activedescendant", opciones[i].id); opciones[i].scrollIntoView({ block: "nearest" }); }
    else input.removeAttribute("aria-activedescendant");
  }
  const anunciar = t => { if (live) live.textContent = t; };

  function miniatura(p){
    if (p.imagen) return `<span class="gs-thumb"><img src="${escapeHtml(p.imagen)}" alt="" loading="lazy"></span>`;
    return `<span class="gs-thumb">${productFallbackMarkup(p, 22)}</span>`;
  }
  function filaArticulo(r, i){
    const p = r.p, marca = LABELS.marca[p.marca] || "";
    const meta = [marca ? escapeHtml(marca) : "", p.referencia ? `Ref. ${escapeHtml(p.referencia)}` : ""].filter(Boolean).join(" · ");
    const tipo = r.componente ? `<span class="gs-kind">Componente</span>` : "";
    return `<li class="gs-opt" role="option" id="gs-o${i}" data-href="${escapeHtml(`producto.html?id=${encodeURIComponent(p.id)}`)}" aria-selected="false">
      ${miniatura(p)}<span><span class="gs-name">${escapeHtml(p.nombre)}</span><span class="gs-meta">${meta}${tipo}</span></span></li>`;
  }
  function filaAtajo(a, i){
    const soloComp = !a.productos;
    const n = soloComp ? a.componentes : a.productos;
    const unidad = soloComp ? (n === 1 ? "componente" : "componentes") : (n === 1 ? "producto" : "productos");
    const href = `catalogo.html?${a.param}=${encodeURIComponent(a.clave)}${soloComp ? "&vista=componentes" : ""}`;
    return `<li class="gs-short" role="option" id="gs-o${i}" data-href="${escapeHtml(href)}" aria-selected="false" aria-label="${escapeHtml(`${a.tipo} ${a.etiqueta}: ver ${n} ${unidad}`)}">
      <span class="k">${escapeHtml(a.tipo)}</span><span class="v">${escapeHtml(a.etiqueta)}</span><span class="n">${n} ${unidad}</span></li>`;
  }
  const caja = (titulo, sub, boton) => `<div class="gs-state"><b>${escapeHtml(titulo)}</b><span>${escapeHtml(sub)}</span>${boton || ""}</div>`;

  function pintar(){
    const consulta = input.value;
    clear.hidden = !consulta;
    if (local()) return;
    if (normalizeSearchText(consulta).length < 2){ cerrar(); panel.innerHTML = ""; opciones = []; anunciar(""); return; }
    if (estado !== "listo"){
      if (estado === "error"){
        panel.innerHTML = caja("No pudimos cargar el catálogo", "Comprueba la conexión e inténtalo de nuevo.", `<button type="button" class="gs-btn" data-retry>Reintentar</button>`);
        anunciar("No pudimos cargar el catálogo.");
      } else {
        panel.innerHTML = `<div class="gs-loading" role="status">Cargando productos…</div>`;
      }
      opciones = []; abrir(); return;
    }
    injectIconSprite();
    const { resultados, aproximada } = MobauBusqueda.buscar(consulta);
    const atajos = MobauBusqueda.atajos(consulta);
    if (!resultados.length && !atajos.length){
      panel.innerHTML = caja(`Sin resultados para «${consulta.trim()}»`, "Prueba con otra palabra, la marca o la referencia.", `<a class="gs-btn" href="catalogo.html">Ver todos los productos</a>`);
      opciones = []; abrir(); anunciar("Sin resultados."); return;
    }
    const sug = MobauBusqueda.sugerencias(resultados);
    let i = 0, html = "";
    if (aproximada) html += `<p class="gs-note">Resultados similares a: ${escapeHtml(aproximada)}</p>`;
    html += `<ul class="gsearch-list" id="gsearch-list" role="listbox" aria-label="Sugerencias">`;
    atajos.forEach(a => { html += filaAtajo(a, i++); });
    if (atajos.length && sug.length) html += `<li class="gs-sep" role="presentation"></li>`;
    sug.forEach(r => { html += filaArticulo(r, i++); });
    if (resultados.length) html += `<li class="gs-all" role="option" id="gs-o${i++}" data-href="${escapeHtml(`catalogo.html?q=${encodeURIComponent(consulta.trim())}`)}" aria-selected="false">Ver todos los resultados (${resultados.length})</li>`;
    html += `</ul>`;
    panel.innerHTML = html;
    opciones = [...panel.querySelectorAll("[role=option]")];
    activa = -1; abrir();
    anunciar(`${sug.length} ${sug.length === 1 ? "sugerencia" : "sugerencias"}${atajos.length ? ` y ${atajos.length} ${atajos.length === 1 ? "atajo" : "atajos"}` : ""}. ${resultados.length} ${resultados.length === 1 ? "resultado" : "resultados"} en total.`);
  }
  function ir(href){
    /* En Productos, «Ver todos» aplica la consulta a la rejilla sin recargar. */
    if (EN_PRODUCTOS && /^catalogo\.html\?q=/.test(href)){ avisarProductos(input.value); cerrarHoja(); return; }
    window.location.href = href;
  }

  /* ---------- eventos ---------- */
  input.addEventListener("focus", () => { asegurarCatalogo(); if (normalizeSearchText(input.value).length >= 2) pintar(); });
  input.addEventListener("input", () => {
    clear.hidden = !input.value;
    asegurarCatalogo(); // por si el texto llega sin un foco previo (pegar, autocompletar)
    clearTimeout(temporizador);
    if (local()){ temporizador = setTimeout(() => avisarProductos(input.value), 200); return; }
    temporizador = setTimeout(pintar, 150);
  });
  input.addEventListener("keydown", e => {
    if (e.key === "ArrowDown" || e.key === "ArrowUp"){
      if (local()) return;
      if (!abierto()){ pintar(); if (!abierto()) return; }
      if (!opciones.length) return;
      e.preventDefault();
      const n = opciones.length;
      marcar(e.key === "ArrowDown" ? (activa + 1) % n : (activa <= 0 ? n - 1 : activa - 1));
    } else if (e.key === "Enter"){
      if (abierto() && activa >= 0){ e.preventDefault(); ir(opciones[activa].dataset.href); }
    } else if (e.key === "Escape"){
      /* Esc nunca borra (el campo de búsqueda nativo lo haría): solo cierra. */
      e.preventDefault();
      if (hojaAbierta()) cerrarHoja();
      else if (abierto()) cerrar();
    } else if (e.key === "Tab"){ cerrar(); }
  });
  form.addEventListener("submit", e => {
    if (EN_PRODUCTOS){
      e.preventDefault();
      clearTimeout(temporizador);
      avisarProductos(input.value);
      if (hojaAbierta()) cerrarHoja();
      return;
    }
    if (!input.value.trim()) e.preventDefault();
    /* Si no, navegación normal a catalogo.html?q=…; los resultados los pinta esa página. */
  });
  panel.addEventListener("mousedown", e => { if (e.target.closest("[role=option], .gs-btn")) e.preventDefault(); });
  panel.addEventListener("click", e => {
    if (e.target.closest("[data-retry]")){ estado = "idle"; asegurarCatalogo(); pintar(); input.focus(); return; }
    const op = e.target.closest("[role=option]");
    if (op) ir(op.dataset.href);
  });
  panel.addEventListener("mousemove", e => { const op = e.target.closest("[role=option]"); if (op && opciones.indexOf(op) !== activa) marcar(opciones.indexOf(op)); });
  clear.addEventListener("click", () => {
    input.value = ""; clear.hidden = true; cerrar(); input.focus();
    if (EN_PRODUCTOS){ clearTimeout(temporizador); avisarProductos(""); }
  });
  document.addEventListener("click", e => { if (abierto() && !form.contains(e.target) && !hojaAbierta()) cerrar(); });

  /* ---------- hoja de búsqueda (móvil) ---------- */
  function abrirHoja(){
    document.body.classList.add("gsearch-sheet");
    asegurarCatalogo();
    input.focus();
    if (normalizeSearchText(input.value).length >= 2) pintar();
  }
  function cerrarHoja(){
    if (!hojaAbierta()){ cerrar(); return; }
    document.body.classList.remove("gsearch-sheet");
    cerrar();
    if (openBtn) openBtn.focus();
  }
  if (openBtn) openBtn.addEventListener("click", abrirHoja);
  if (closeBtn) closeBtn.addEventListener("click", cerrarHoja);
  document.addEventListener("keydown", e => { if (e.key === "Escape" && hojaAbierta() && e.target !== input) cerrarHoja(); });

  /* En Productos, la consulta de la URL llega al campo; Productos la mantiene sincronizada con fijar(). */
  window.MobauBuscadorGlobal = {
    valor: () => input.value,
    fijar(texto){ input.value = texto || ""; clear.hidden = !input.value; }
  };
  if (EN_PRODUCTOS){
    const q = new URLSearchParams(location.search).get("q");
    if (q) window.MobauBuscadorGlobal.fijar(q);
  }
  clear.hidden = !input.value;
})();
