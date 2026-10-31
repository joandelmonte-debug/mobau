/* ============================================================
   MOBAU — Estado de sesión en el header (nav)
   ------------------------------------------------------------
   Completa la cabecera según haya o no sesión activa, sin reconstruirla
   (Punto 50). El HTML de cada página ya trae todos los accesos posibles
   (data-nav-for) y nav-account-hint.js, en el <head>, marca
   <html data-nav="…"> con la composición esperada: lo que no corresponde
   no ocupa sitio y lo que sí corresponde ocupa su sitio exacto, invisible y
   sin foco, hasta que este script confirma la sesión, el rol y el plan
   (atributo data-on). Así nada aparece, desaparece ni se desplaza al
   resolverse la sesión. La pista es solo de diseño: este script la corrige
   (data-nav) y la guarda para la siguiente página ("mobau_nav_hint" = tipo de
   cuenta confirmado para ESTE usuario); nunca concede permisos.

   - Sin sesión: «Iniciar sesión» (ya pintado) y nada más.
   - Con sesión (Punto 14): el hueco reservado se sustituye por el menú de
     cuenta (misma caja y mismo ancho): nombre/email, Mi perfil, Mi moodboard
     y Cerrar sesión. «Mis proyectos» es un enlace directo de la cabecera
     (solo con herramientas profesionales, Punto 43), no un elemento del menú.
     El nombre real (professional_profiles.professional_name) llega aparte,
     en segundo plano, y solo cambia el texto.
   - Cuenta de distribuidor (Punto 38-A): Resumen · Mis productos · Productos;
     el logo lleva al panel y el menú queda en «Perfil de empresa» y
     «Cerrar sesión». Desaparecen «Mi selección», Distribuidores, Contacto y
     los enlaces de proyectos (también los del pie).
   - Cuenta de Mobau (Punto 39, profiles.role = 'admin'): sin selección,
     proyectos ni perfil profesional; cabecera Moderación · Productos y menú
     Moderación · Cerrar sesión. «Moderación» solo se revela si el servidor
     confirma un admin activo (mobau_admin_session().admin, una sola llamada
     y solo para este tipo de cuenta); la consola vuelve a comprobarlo y
     exige además el segundo factor.
   ============================================================ */

(async () => {
  /* Punto 50: composición de la cabecera. navState() decide el valor de
     <html data-nav> con lo ya confirmado (rol y acceso); devuelve null mientras
     no se pueda decidir, y entonces se queda la pista del <head>. Se aplica
     sobre los elementos que ya existen (data-nav-for): solo cambia atributos. */
  const root = document.documentElement;
  const HINT_KEY = "mobau_nav_hint";
  const navState = (access) => {
    const kind = MobauAccess.confirmedKind;
    if (kind === "supplier" || kind === "mobau") return kind;
    if (access === "pro" || access === "gratis" || access === "anon" || access === "unknown") return access;
    return null;
  };
  /* Pista de diseño para la siguiente página: solo tipo de cuenta, usuario y el
     contador visible de «Mi selección»; nunca tokens, perfil ni permisos. */
  const storeHint = (nav) => {
    try {
      /* Sin sesión o con una lectura fallida: no se reserva nada para la siguiente página. */
      if (nav === "anon" || nav === "unknown"){ localStorage.removeItem(HINT_KEY); return; }
      if (!["pro", "gratis", "supplier", "mobau"].includes(nav)) return;
      const u = MobauAuth.storedUserId();
      if (!u) return;
      const hint = { u, k: nav };
      const link = document.getElementById("selection-count-link");
      const n = nav === "pro" && link && !link.hidden ? parseInt((link.querySelector(".sel-n") || {}).textContent.replace(/\D/g, ""), 10) : 0;
      if (n > 0) hint.n = n;
      localStorage.setItem(HINT_KEY, JSON.stringify(hint));
    } catch (e) { /* sin almacenamiento: solo se pierde la pista */ }
  };
  const syncNav = (access) => {
    const nav = navState(access);
    if (!nav) return;
    if (root.getAttribute("data-nav") !== nav) root.setAttribute("data-nav", nav);
    document.querySelectorAll(".site-header [data-pro-nav]").forEach(el => { el.toggleAttribute("data-on", nav === "pro"); el.inert = nav !== "pro"; });
    document.querySelectorAll(".site-header [data-supplier-nav]").forEach(el => { el.toggleAttribute("data-on", nav === "supplier"); el.inert = nav !== "supplier"; });
    storeHint(nav);
  };
  MobauAccess.access().then(syncNav);
  document.addEventListener("mobau:access", (e) => syncNav(e.detail.access));

  /* Punto 43: «Mi selección» solo con herramientas profesionales (plan
     Individual o Estudio, MobauAccess.access() = "pro"). El enlace llega
     oculto en el HTML de cada cabecera (atributo hidden, CC1): así no se ve
     en la primera pintura, mientras se descargan los scripts. Este es el
     único punto que lo muestra, y solo cuando se confirma el acceso; vuelve
     a ocultarse si el acceso baja después (respuesta del servidor). */
  const selectionLink = document.getElementById("selection-count-link");
  if (selectionLink){
    selectionLink.hidden = true;
    const showSelectionLink = (access) => {
      if (!selectionLink.isConnected) return;
      selectionLink.hidden = access !== "pro";
      selectionLink.inert = access !== "pro";
      if (access === "pro" && typeof updateSelectionBadge === "function") updateSelectionBadge();
    };
    MobauAccess.access().then(showSelectionLink);
    document.addEventListener("mobau:access", (e) => showSelectionLink(e.detail.access));
    /* El contador lo escribe updateSelectionBadge() (script.js, sin cambios): aquí solo se
       observa para que la pista de la siguiente página reserve el ancho de su círculo. */
    new MutationObserver(() => { if (root.getAttribute("data-nav") === "pro") storeHint("pro"); })
      .observe(selectionLink, { childList: true, subtree: true });
  }

  /* Punto 43 (CC1): Gratis no tiene proyectos, presupuestos ni solicitudes.
     «Mis proyectos» del pie llega oculto en el HTML de cada página (como «Mi
     selección») y solo se muestra con herramientas profesionales
     confirmadas: sin sesión, Gratis o acceso sin comprobar, nunca aparece.
     Distribuidor y Mobau lo pierden más abajo. */
  const showFooterProjectLinks = (access) => {
    document.querySelectorAll('.site-footer a[href="proyectos.html"]').forEach(a => {
      (a.closest("li") || a).hidden = access !== "pro";
    });
  };
  MobauAccess.access().then(showFooterProjectLinks);
  document.addEventListener("mobau:access", (e) => showFooterProjectLinks(e.detail.access));

  const slot = document.getElementById("nav-session-slot");
  if (!slot) return;

  /* Protección idempotente: si este script se ejecutara más de una vez
     sobre el mismo documento (no debería, cada página lo carga una
     sola vez), nunca vuelve a montar el menú ni duplica listeners. */
  if (slot.dataset.navSessionMounted) return;
  slot.dataset.navSessionMounted = "1";

  /* Tipo de cuenta confirmado (una sola consulta por página, compartida con
     script.js y las redirecciones): se pide ya, en paralelo con la sesión.
     Sin sesión resuelve "anon" y borra la pista estética. */
  const accountKindPromise = MobauAccess.accountKind();

  const session = await MobauAuth.getSession();

  if (!session){
    /* «Iniciar sesión» ya está pintado (#nav-login): solo se retira el hueco reservado. */
    root.setAttribute("data-nav", "anon");
    storeHint("anon");
    slot.remove();
    return;
  }
  /* Había sesión aunque la pista dijera lo contrario (p. ej. iniciada en otra pestaña): se reserva «Mi cuenta». */
  if (root.getAttribute("data-nav") === "anon") root.setAttribute("data-nav", "pending");

  const email = session.user.email || "";
  const escapeHtml = (str) => (str || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

  slot.outerHTML = `
    <div class="account-menu" id="account-menu">
      <button type="button" class="account-menu-trigger" id="account-menu-trigger" aria-haspopup="true" aria-expanded="false" aria-controls="account-menu-panel">
        Mi cuenta
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="6 9 12 15 18 9"></polyline></svg>
      </button>
      <div class="account-menu-panel" id="account-menu-panel" role="menu" aria-label="Menú de cuenta">
        <div class="account-menu-header">
          <div class="account-menu-name" id="account-menu-name">Tu cuenta</div>
          <div class="account-menu-email">${escapeHtml(email)}</div>
        </div>
        <a href="inscripcion-profesional.html" id="account-menu-profile" role="menuitem">Mi perfil</a>
        <a href="moodboard.html" id="account-menu-moodboard" data-architect-only hidden role="menuitem">Mi moodboard</a>
        <button type="button" class="account-menu-item" id="account-menu-logout" role="menuitem">Cerrar sesión</button>
      </div>
    </div>`;

  const menu = document.getElementById("account-menu");
  const trigger = document.getElementById("account-menu-trigger");
  const panel = document.getElementById("account-menu-panel");

  /* Abrir/cerrar por clase, nunca por display:none/hidden: el panel ya
     es position:absolute (fuera del flujo) dentro de .account-menu
     (position:relative), así que nunca desplaza ni el header ni el
     resto del contenido — solo cambia su propia opacidad/visibilidad. */
  function openMenu(){
    panel.classList.add("is-open");
    trigger.setAttribute("aria-expanded", "true");
  }
  function closeMenu({ focusTrigger } = {}){
    panel.classList.remove("is-open");
    trigger.setAttribute("aria-expanded", "false");
    if (focusTrigger) trigger.focus();
  }

  trigger.addEventListener("click", () => {
    if (panel.classList.contains("is-open")) closeMenu(); else openMenu();
  });

  /* Clic fuera del menú lo cierra — se compara contra "menu" (trigger +
     panel juntos), así un clic en cualquiera de los dos no cuenta como
     "fuera". */
  document.addEventListener("click", (e) => {
    if (panel.classList.contains("is-open") && !menu.contains(e.target)) closeMenu();
  });

  /* Escape cierra y devuelve el foco al botón, sin importar qué
     elemento del panel tuviera el foco en ese momento. */
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && panel.classList.contains("is-open")) closeMenu({ focusTrigger: true });
  });

  /* Punto 50: el menú de cuenta profesional queda en Mi perfil, Mi moodboard y
     Cerrar sesión; «Mis proyectos» es el enlace directo de la cabecera. «Mi
     moodboard» (por ahora una pantalla informativa) aparece para las cuentas
     profesionales, con plan o Gratis; nunca para distribuidor ni Mobau, que lo
     pierden más abajo (data-architect-only). */
  const applyAccessToMenu = (access) => {
    const moodboardLink = document.getElementById("account-menu-moodboard");
    if (moodboardLink) moodboardLink.hidden = !(access === "pro" || access === "gratis");
  };
  MobauAccess.access().then(applyAccessToMenu);
  document.addEventListener("mobau:access", (e) => applyAccessToMenu(e.detail.access));

  /* Cerrar sesión: MobauAuth.signOut() es la única lógica de logout de
     toda la app (supabase-client.js) — aquí solo se cierra el menú
     (cambio de estado, no se vuelve a montar nada) antes de llamarla;
     signOut() ya redirige a login.html. */
  document.getElementById("account-menu-logout").addEventListener("click", () => {
    closeMenu();
    MobauAuth.signOut();
  });

  /* Navegar con un enlace del menú solo cambia el estado del panel
     (misma closeMenu() de siempre) — la navegación real la hace el
     propio <a>, esto no vuelve a montar #nav-session-slot ni el resto
     del header. */
  panel.querySelectorAll("a[role='menuitem']").forEach(link => {
    link.addEventListener("click", () => closeMenu());
  });

  /* Nombre real, en segundo plano: misma tabla que ya usa
     cuenta.html/inscripcion-profesional.html, no crea ninguna fuente
     de datos nueva. Nunca bloquea ni retrasa que el menú aparezca o se
     pueda abrir — si tarda, falla o no hay perfil todavía, el menú ya
     está montado y usable con el email; esto solo reemplaza el texto
     del nombre si llega. */
  supabaseClient
    .from("professional_profiles")
    .select("professional_name")
    .eq("user_id", session.user.id)
    .maybeSingle()
    .then(({ data }) => {
      if (data && data.professional_name){
        const nameEl = document.getElementById("account-menu-name");
        if (nameEl) nameEl.textContent = data.professional_name;
      }
    })
    .catch(() => {});

  /* Cuentas de distribuidor (profiles.role = 'supplier'): en segundo plano,
     como el nombre — el menú ya es usable. Hasta que llega el rol se ve la
     cabecera de siempre, salvo en las páginas con nav-account-hint.js y
     pista guardada, donde lo de cliente ya está oculto por CSS. Si la
     consulta falla ("unknown"), la cabecera queda como la de siempre. */
  accountKindPromise.then(kind => {
    syncNav(null);
    if (kind === "mobau"){
      applyMobauAccount();
      return;
    }
    if (kind !== "supplier") return;
    applySupplierHeader();

    const profileLink = document.getElementById("account-menu-profile");
    if (profileLink){
      profileLink.href = "perfil-distribuidor.html";
      profileLink.textContent = "Perfil de empresa";
    }
    panel.querySelectorAll("[data-architect-only]").forEach(el => el.remove());

    /* Nombre comercial (fila propia de distributor_profiles), si ya existe. */
    supabaseClient
      .from("distributor_profiles")
      .select("nombre_comercial")
      .eq("user_id", session.user.id)
      .maybeSingle()
      .then(({ data }) => {
        if (data && data.nombre_comercial){
          const nameEl = document.getElementById("account-menu-name");
          if (nameEl) nameEl.textContent = data.nombre_comercial;
        }
      })
      .catch(() => {});
  });

  /* Cuenta de Mobau: quita lo de profesional y, solo con admin activo,
     revela «Moderación» (ya reservada en la cabecera) y la añade al menú.
     No reconstruye la cabecera: <html data-nav="mobau"> oculta lo de cliente. */
  function applyMobauAccount(){
    const profileLink = document.getElementById("account-menu-profile");
    if (profileLink) profileLink.remove();
    panel.querySelectorAll("[data-architect-only]").forEach(el => el.remove());

    const selectionLink = document.getElementById("selection-count-link");
    if (selectionLink) selectionLink.remove();
    document.querySelectorAll('.site-footer a[href="distribuidores.html"], .site-footer a[href="proyectos.html"]').forEach(a => {
      (a.closest("li") || a).remove();
    });

    MobauAccess.adminSession().then(state => {
      if (!state.admin) return;
      const home = MobauAccess.MOBAU_HOME;
      document.querySelectorAll(".site-header .brand").forEach(a => { a.href = home; });
      const nameEl = document.getElementById("account-menu-name");
      if (nameEl) nameEl.textContent = "Equipo Mobau";

      document.querySelectorAll(".site-header [data-mobau-nav]").forEach(a => { a.setAttribute("data-on", ""); a.inert = false; });
      if (!panel.querySelector("[data-mobau-nav]")){
        const item = document.createElement("a");
        item.href = home;
        item.textContent = "Moderación";
        item.setAttribute("role", "menuitem");
        item.setAttribute("data-mobau-nav", "");
        item.addEventListener("click", () => closeMenu());
        panel.insertBefore(item, document.getElementById("account-menu-logout"));
      }
    }).catch(() => {});
  }

  /* Cabecera y pie de distribuidor: los enlaces propios (Resumen, Mis productos) ya están en
     cada cabecera y se revelan con syncNav(); aquí solo el logo, la selección y el pie. */
  function applySupplierHeader(){
    const home = MobauAccess.SUPPLIER_HOME;
    document.querySelectorAll(".site-header .brand").forEach(a => { a.href = home; });

    const selectionLink = document.getElementById("selection-count-link");
    if (selectionLink) selectionLink.remove();

    document.querySelectorAll('.site-footer a[href="distribuidores.html"], .site-footer a[href="proyectos.html"]').forEach(a => {
      (a.closest("li") || a).remove();
    });
  }
})();
