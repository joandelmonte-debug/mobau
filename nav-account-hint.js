/* ============================================================
   MOBAU — Pista de diseño de la cabecera (Punto 38-A, ampliada en el Punto 50)
   ------------------------------------------------------------
   Se carga de forma síncrona en el <head> de todas las páginas con cabecera,
   ANTES de que se pinte. Escribe <html data-nav="…"> con la composición de
   cabecera que se espera, para que cabecera.css reserve en la primera pintura
   el sitio de lo que va a llegar (Mi cuenta, Mis proyectos, Mi selección,
   Resumen y Mis productos, Moderación) y nada se desplace cuando se confirme
   la sesión:
     anon      sin sesión guardada: «Iniciar sesión» se pinta ya
     pro | gratis | supplier | mobau
               última composición confirmada para ESTA misma cuenta
     pending   hay una sesión guardada pero no se sabe aún el tipo de cuenta
               (primera visita, pista caducada o sesión que vuelve por un
               enlace): solo se reserva «Mi cuenta»

   La pista ("mobau_nav_hint" = {u: id de usuario, k: tipo, n: contador de «Mi selección»}) es SOLO de diseño:
   no guarda tokens, datos de perfil ni permisos; reserva un hueco invisible y
   sin foco, nunca muestra un enlace restringido y no decide ningún acceso. El
   tipo real lo confirman nav-session.js (sesión, rol y plan) y las políticas
   RLS. Se descarta si no hay sesión guardada o si pertenece a otro usuario.
   Un error al leer o escribir el almacenamiento nunca rompe la cabecera.

   Distribuidor: además marca data-account="supplier" y oculta desde la primera
   pintura lo que no usa (opciones de proyectos del pie, botones de añadir a la
   selección o al proyecto activo).
   ============================================================ */
(function () {
  var HINT_KEY = "mobau_nav_hint";
  var LEGACY_KEY = "mobau_account_kind";
  /* Misma clave que SUPABASE_SESSION_STORAGE_KEY (supabase-client.js), que
     aquí aún no está cargado. */
  var SESSION_KEY = "sb-skcoxtdppdcietgojdal-auth-token";
  var UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
  var KINDS = { pro: 1, gratis: 1, supplier: 1, mobau: 1 };
  var root = document.documentElement;
  var nav = "anon";
  var kind = null;

  try {
    var raw = localStorage.getItem(SESSION_KEY);
    if (!raw) {
      /* Sin sesión guardada solo es definitivo si la página no está recogiendo
         una (enlace mágico, código de retorno): ahí aún puede crearse. */
      if (/[#?&](access_token|refresh_token|token_hash|code)=/.test(window.location.hash + window.location.search)) nav = "pending";
      else {
        localStorage.removeItem(HINT_KEY);
        localStorage.removeItem(LEGACY_KEY);
      }
    } else {
      nav = "pending";
      var uid = null;
      try {
        var stored = JSON.parse(raw);
        uid = stored && stored.user && typeof stored.user.id === "string" && UUID.test(stored.user.id) ? stored.user.id : null;
      } catch (e) { /* sesión ilegible: se trata como desconocida */ }
      var hint = null;
      try { hint = JSON.parse(localStorage.getItem(HINT_KEY)); } catch (e) { /* pista ilegible: se ignora */ }
      if (hint && uid && hint.u === uid && typeof hint.k === "string" && KINDS[hint.k] === 1) {
        nav = hint.k;
        kind = hint.k;
        /* Contador de «Mi selección» que tenía esta cuenta: solo para reservar la anchura de su círculo. */
        if (hint.k === "pro" && typeof hint.n === "number" && hint.n >= 1 && hint.n <= 999 && hint.n % 1 === 0) {
          root.style.setProperty("--nav-n", "\"" + hint.n + "\"");
        }
      } else if (hint) {
        /* De otra cuenta o inválida: se descarta. */
        localStorage.removeItem(HINT_KEY);
      }
    }
  } catch (e) {
    /* Sin almacenamiento no puede haber sesión persistida: cabecera pública. */
    nav = "anon";
  }

  root.setAttribute("data-nav", nav);
  if (kind !== "supplier") return;

  root.setAttribute("data-account", "supplier");

  /* Las reglas solo actúan mientras <html> tenga data-account="supplier":
     si el rol confirmado no es de distribuidor, nav-session.js quita el
     atributo y todo vuelve a verse como siempre. */
  var s = "html[data-account=\"supplier\"] ";
  var style = document.createElement("style");
  style.id = "mobau-account-hint";
  style.textContent = [
    s + "[data-architect-only]",
    s + ".site-footer li:has(> a[href=\"distribuidores.html\"])",
    s + ".site-footer li:has(> a[href=\"proyectos.html\"])",
    s + ".btn-add-selection",
    s + ".btn-add-to-project",
    s + ".product-selection-actions"
  ].join(",\n") + "{ display:none !important; }";
  document.head.appendChild(style);
})();
