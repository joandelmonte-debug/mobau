/* ============================================================
   MOBAU — Pista estética de cuenta de distribuidor (Punto 38-A)
   ------------------------------------------------------------
   Se carga de forma síncrona en el <head> de las páginas que un
   distribuidor usa con normalidad (catálogo, ficha de producto, perfil
   de distribuidor), ANTES de que se pinte la cabecera. Si este
   navegador ya confirmó una cuenta de distribuidor
   (localStorage "mobau_account_kind" = "supplier", ver MobauAccountHint
   en supabase-client.js), oculta desde la primera pintura lo que un
   distribuidor no usa: "Mi selección", la navegación profesional, las
   opciones de proyectos/solicitudes del menú de cuenta y los botones de
   añadir a la selección o al proyecto activo. Sin sesión guardada no hace
   nada (y borra la pista): la interfaz pública no cambia.

   Es SOLO estética: no concede permisos, no sustituye a la sesión y no
   decide ningún acceso. El rol real lo confirma nav-session.js (vía
   MobauAccess.accountKind()), que corrige la cabecera si la pista no
   coincide; la protección de los datos son las políticas RLS.
   ============================================================ */
(function () {
  var kind = null, hasSession = false;
  try {
    kind = localStorage.getItem("mobau_account_kind");
    /* Misma clave que SUPABASE_SESSION_STORAGE_KEY (supabase-client.js),
       que aquí aún no está cargado. Sin sesión guardada, la interfaz
       pública no cambia nunca: la pista se borra y no se aplica. */
    hasSession = !!localStorage.getItem("sb-skcoxtdppdcietgojdal-auth-token");
    if (kind && !hasSession) localStorage.removeItem("mobau_account_kind");
  } catch (e) { return; }
  if (kind !== "supplier" || !hasSession) return;

  document.documentElement.setAttribute("data-account", "supplier");

  /* Las reglas solo actúan mientras <html> tenga data-account="supplier":
     si el rol confirmado no es de distribuidor, nav-session.js quita el
     atributo y todo vuelve a verse como siempre. */
  var s = "html[data-account=\"supplier\"] ";
  var style = document.createElement("style");
  style.id = "mobau-account-hint";
  style.textContent = [
    s + "#selection-count-link",
    s + ".nav-links > a:not([data-supplier-nav]):not([href=\"catalogo.html\"])",
    s + "[data-architect-only]",
    s + ".site-footer li:has(> a[href=\"distribuidores.html\"])",
    s + ".site-footer li:has(> a[href=\"proyectos.html\"])",
    s + ".btn-add-selection",
    s + ".btn-add-to-project",
    s + ".product-selection-actions"
  ].join(",\n") + "{ display:none !important; }";
  document.head.appendChild(style);
})();
