/* ============================================================
   MOBAU — Estado de sesión en el header (nav)
   ------------------------------------------------------------
   Llena #nav-session-slot según haya o no sesión activa.
   No decide nada por su cuenta: solo consulta MobauAuth.getSession()
   (definida en supabase-client.js, que debe cargarse antes que este
   archivo) y muestra el resultado. No guarda ni cachea el estado —
   cada carga de página vuelve a preguntar la sesión real.
   ============================================================ */

(async () => {
  const slot = document.getElementById("nav-session-slot");
  if (!slot) return;

  const session = await MobauAuth.getSession();

  slot.outerHTML = session
    ? `<span class="nav-cta"><a href="proyectos.html">Mis proyectos</a><a href="cuenta.html">Mi cuenta</a></span>`
    : `<a href="login.html">Iniciar sesión</a>`;
})();
