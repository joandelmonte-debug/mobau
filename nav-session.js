/* ============================================================
   MOBAU — Estado de sesión en el header (nav)
   ------------------------------------------------------------
   Llena #nav-session-slot según haya o no sesión activa. Sin sesión,
   un enlace simple a login.html (sin cambios). Con sesión, un menú
   desplegable (Punto 14): cabecera con nombre/email + Mi perfil,
   Mis proyectos, Solicitudes, Cerrar sesión.

   Ajuste de estabilidad visual: el menú se monta en cuanto se conoce
   la sesión (una sola espera: MobauAuth.getSession(), igual que antes
   de Punto 14) usando session.user.email. El nombre real
   (professional_profiles.professional_name) se pide aparte, en
   segundo plano, y solo actualiza el texto de la cabecera cuando
   llega — nunca vuelve a montar el menú ni retrasa que aparezca y se
   pueda usar. Antes, esa segunda consulta se esperaba ANTES de
   insertar nada: con sesión lenta o típica, el hueco en el header
   duraba el doble (dos round-trips en vez de uno), y en cada
   navegación de página completa (Inicio/Catálogo/Distribuidores/...)
   se veía como si el menú "desapareciera y volviera a aparecer".

   No guarda ni cachea nada — cada carga de página vuelve a preguntar.
   ============================================================ */

(async () => {
  const slot = document.getElementById("nav-session-slot");
  if (!slot) return;

  /* Protección idempotente: si este script se ejecutara más de una vez
     sobre el mismo documento (no debería, cada página lo carga una
     sola vez), nunca vuelve a montar el menú ni duplica listeners. */
  if (slot.dataset.navSessionMounted) return;
  slot.dataset.navSessionMounted = "1";

  const session = await MobauAuth.getSession();

  if (!session){
    slot.outerHTML = `<a href="login.html">Iniciar sesión</a>`;
    return;
  }

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
        <a href="inscripcion-profesional.html" role="menuitem">Mi perfil</a>
        <a href="proyectos.html?status=active" role="menuitem">Mis proyectos</a>
        <a href="proyectos.html?status=requested" role="menuitem">Solicitudes</a>
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
})();
