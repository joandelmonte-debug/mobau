/* ============================================================
   MOBAU — Estado de sesión en el header (nav)
   ------------------------------------------------------------
   Llena #nav-session-slot según haya o no sesión activa. Sin sesión,
   un enlace simple a login.html (sin cambios). Con sesión, un menú
   desplegable (Punto 14): cabecera con nombre/email + Mi perfil,
   Mis proyectos, Mi proyecto activo (Punto 27), Solicitudes, Cerrar
   sesión.

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
        <a href="proyectos.html?status=active" id="account-menu-active-project" role="menuitem">Mi proyecto activo</a>
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

  /* Punto 27 — "Mi proyecto activo".

     BUG REAL DE SINCRONIZACIÓN (corregido aquí): la versión anterior
     dejaba el href en el fallback hasta que MobauProjects.list("active")
     resolvía, en una línea de tiempo TOTALMENTE separada de la del
     usuario. Con sesión ya restaurada (el caso normal: recargar la
     página, volver de otra pestaña, abrir el menú después de un rato)
     MobauAuth.getSession() resuelve casi al instante, el menú queda
     usable de inmediato, y el primer clic real solía llegar ANTES de
     que la consulta a product_prices/projects terminara — la
     navegación ocurre con el href que hubiera EN ESE INSTANTE en el
     DOM (el fallback), sin importar que la promesa fuera a resolver
     bien 100–300ms después. El "segundo clic" solo parecía arreglarlo
     porque, para entonces, ya había pasado de sobra una navegación de
     página completa — tiempo real suficiente para que la consulta ya
     hubiera terminado en segundo plano.

     CORRECCIÓN: una sola promesa compartida (resolveActiveProjectHref,
     memoizada en activeProjectHrefPromise) entre quien actualiza el
     href al resolver y el propio clic del enlace. Si el clic llega
     antes de resolver, se intercepta ESE clic (preventDefault) y se
     espera la MISMA promesa ya en curso — nunca una consulta nueva,
     nunca un setTimeout fijo, nunca exige un segundo clic. */
  let activeProjectHrefPromise = null;
  let activeProjectHrefResolved = false;

  function resolveActiveProjectHref(){
    if (activeProjectHrefPromise) return activeProjectHrefPromise;
    const fallback = "proyectos.html?status=active";
    activeProjectHrefPromise = (async () => {
      /* 1) DOM listo: en TODAS las páginas <script src="nav-session.js">
         va antes que <script src="proyectos-data.js"> — sin esperar
         esto, `typeof MobauProjects` puede evaluarse antes de que ese
         script exista todavía (confirmado con sesión real ya en
         caché: el guard corría antes de que el parser llegara al
         siguiente <script>). */
      if (document.readyState === "loading"){
        await new Promise(resolve => document.addEventListener("DOMContentLoaded", resolve, { once: true }));
      }
      /* 2) Páginas sin proyectos-data.js (index.html, distribuidores.html,
         inscripción profesional, proyecto.html, rfq.html…): no existe
         arquitectura para resolver el proyecto real ahí. Límite
         conocido y documentado, no un bug — el fallback es el
         resultado correcto en esas páginas, siempre. */
      if (typeof MobauProjects === "undefined") return fallback;
      /* 3) Reutiliza MobauAuth.getSession() — nunca una consulta nueva
         de sesión. Si ya no hay sesión (cerró sesión entre que se
         montó el menú y el clic — caso extremo pero real), nunca se
         resuelve ni se navega a un destino privado: fallback. */
      const currentSession = await MobauAuth.getSession();
      if (!currentSession) return fallback;
      /* 4) Una sola consulta real, sin importar cuántas veces se llame
         esta función (al montar el menú Y desde el clic): la promesa
         ya en curso se reutiliza siempre, MobauProjects.list("active")
         se ejecuta como máximo una vez por carga de página. Cero o
         más de uno (no debería pasar con la regla de un solo proyecto
         activo por plan; si pasa, no se elige ninguno al azar ni se
         corrige el dato) → fallback. Error de red → fallback (list()
         ya lo registra y devuelve [] por su cuenta). */
      try {
        const activeProjects = await MobauProjects.list("active");
        return activeProjects.length === 1
          ? `proyectos-detalle.html?id=${activeProjects[0].id}`
          : fallback;
      } catch {
        return fallback;
      }
    })();
    return activeProjectHrefPromise;
  }

  const activeProjectLink = document.getElementById("account-menu-active-project");
  if (activeProjectLink){
    /* aria-busy en vez de cualquier CSS nuevo: anuncia el estado de
       carga a lectores de pantalla sin ocupar espacio ni cambiar la
       altura del header — se retira apenas resuelve, junto con el
       href real. */
    activeProjectLink.setAttribute("aria-busy", "true");

    /* Orden deliberado: el listener de clic prematuro se instala ANTES
       de iniciar resolveActiveProjectHref() (más abajo) — así la
       protección ya existe desde el instante en que se crea el
       enlace, sin depender de que ningún clic no pueda colarse en el
       hueco síncrono entre ambas líneas.
       Primer clic antes de resolver: preventDefault() es temporal — se
       usa SOLO mientras activeProjectHrefResolved sigue en false, y
       deja de aplicarse en cuanto la promesa (ya en curso, la misma de
       abajo) resuelve; a partir de ahí el enlace navega solo con su
       href ya real, sin este listener de por medio. Solo se intercepta
       el clic simple de botón principal — clic central, Ctrl/Cmd+clic
       o Mayús+clic para abrir en pestaña nueva siguen su camino nativo
       normal con el href que haya en ese instante, igual que cualquier
       enlace real: eso no se puede ni se debe interceptar, y es
       exactamente lo que mantiene el elemento como un <a> real para
       teclado, lectores de pantalla y "copiar enlace". */
    activeProjectLink.addEventListener("click", (e) => {
      if (activeProjectHrefResolved) return;
      if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
      e.preventDefault();
      resolveActiveProjectHref().then(href => {
        activeProjectLink.href = href;
        window.location.href = href;
      });
    });

    resolveActiveProjectHref().then(href => {
      activeProjectLink.href = href;
      activeProjectLink.removeAttribute("aria-busy");
      activeProjectHrefResolved = true;
    });
  }
})();
