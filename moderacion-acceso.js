/* ============================================================
   MOBAU — Consola de moderación: puerta de acceso (Punto 39)
   ------------------------------------------------------------
   La comparten moderacion.html y moderacion-propuesta.html. Orden:
   1) sesión (sin sesión → acceso.html con la página como "next");
   2) tipo de cuenta: profesional o distribuidor → «solo para el equipo de
      Mobau», sin ninguna otra consulta;
   3) mobau_admin_session() en el servidor → { admin, aal2 };
   4) admin sin aal2 → segundo factor. La consola SOLO usa
      auth.mfa.listFactors(), auth.mfa.challenge() y auth.mfa.verify()
      sobre un factor TOTP ya verificado. El primer factor se configura
      fuera del sitio, con un procedimiento aparte: aquí no se crean ni se
      eliminan factores;
   5) tras verificar, se vuelve a preguntar al servidor y solo con
      { admin: true, aal2: true } se llama a la página (lecturas y
      decisiones).
   Nada de esto autoriza por sí mismo: la protección real son las RLS
   (is_mobau_admin(): admin activo y aal2) y las comprobaciones de
   moderate_product_proposal(). El código de 6 dígitos nunca se guarda ni
   se escribe en la consola del navegador.

   Además, utilidades comunes de las dos páginas: textos, pintado seguro
   (siempre textContent; enlaces solo http/https en pestaña nueva, nunca
   imágenes) y el mapa de errores de moderate_product_proposal().
   ============================================================ */

const MobauModeracion = (() => {
  const CODE_PATTERN = /^\d{6}$/;

  /* Menú móvil, como initNavToggle() de script.js: la consola no carga
     script.js (ni el catálogo ni la selección). */
  const navToggle = document.querySelector(".nav-toggle");
  if (navToggle) navToggle.addEventListener("click", () => document.body.classList.toggle("nav-open"));

  const STATUS = {
    submitted:         { label: "En revisión",         kind: "wait" },
    changes_requested: { label: "Cambios solicitados", kind: "alert" },
    approved:          { label: "Aprobada",            kind: "ok" },
    rejected:          { label: "Rechazada",           kind: "alert" },
    withdrawn:         { label: "Retirada",            kind: "neutral" }
  };
  const FIELD_LABELS = {
    name: "Nombre", brand: "Marca", availability: "Disponibilidad", category_id: "Categoría", subcategory: "Subcategoría",
    use_context: "Uso", space: "Espacio", lead_time: "Plazo de entrega", description: "Descripción", measurements: "Medidas",
    materials: "Materiales", finishes: "Acabados", image_url: "Imagen", technical_sheet_url: "Ficha técnica",
    cad_bim_3d_url: "CAD / BIM / 3D", price: "Precio"
  };
  const URL_FIELDS = ["image_url", "technical_sheet_url", "cad_bim_3d_url"];
  const AVAILABILITY = { "en-stock": "En stock", "bajo-pedido": "Bajo pedido", "por-confirmar": "Por confirmar" };
  const PRICE_STATUS = {
    published: "Precio publicado", quote_required: "Bajo cotización",
    pending_confirmation: "Por confirmar", unavailable: "No disponible"
  };

  /* ---------- pintado seguro ---------- */
  function el(tag, className, text){
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  }

  function chip(label, kind){
    return el("span", `pd-chip pd-chip--${kind}`, label);
  }

  /* Enlace externo solo si la URL es http(s) válida; si no, el valor como
     texto. Nunca <img>: la consola no carga imágenes de terceros. */
  function safeLink(value, text){
    const raw = typeof value === "string" ? value.trim() : "";
    let url = null;
    try {
      url = /^https?:\/\//i.test(raw) ? new URL(raw) : null;
    } catch (e) {
      url = null;
    }
    if (!url || (url.protocol !== "http:" && url.protocol !== "https:")) return el("span", "", raw || "vacío");
    const a = el("a", "pd-link", text || url.href);
    a.href = url.href;
    a.target = "_blank";
    a.rel = "noopener noreferrer";
    return a;
  }

  function formatDate(value){
    if (!value) return "";
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? "" : d.toLocaleDateString("es-DO", { day: "numeric", month: "long", year: "numeric" });
  }

  function formatMoney(amount){
    if (amount === null || amount === undefined || amount === "") return "";
    const n = Number(amount);
    return Number.isFinite(n) ? `US$ ${n.toLocaleString("es-DO", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}` : "";
  }

  function priceText(price){
    if (!price || !price.price_status) return "Sin precio";
    const label = PRICE_STATUS[price.price_status] || price.price_status;
    const amount = formatMoney(price.price_amount);
    return amount ? `${label} · ${amount}` : label;
  }

  function fieldLabel(key){
    return FIELD_LABELS[key] || key;
  }

  /* ---------- errores de moderate_product_proposal() ----------
     Devuelve { action, message }: "mfa" (volver a verificar), "denied"
     (sin acceso), "login", "block" (acciones desactivadas), "notfound",
     "reload" (mensaje y volver a cargar) o "show" (solo mensaje). */
  function decisionError(error){
    const code = error && error.code;
    const hint = error && error.hint;
    const message = (error && error.message) || "";
    if (code === "42501"){
      if (hint === "aal2_required") return { action: "mfa", message: "Tu verificación en dos pasos ha caducado. Vuelve a verificar para continuar." };
      if (hint === "not_admin") return { action: "denied", message: "Tu cuenta ya no tiene acceso de moderación." };
      if (hint === "self_moderation_forbidden") return { action: "block", message: message || "No puedes moderar propuestas de tu propia empresa." };
      if (hint === "not_authenticated") return { action: "login", message: "" };
      return { action: "show", message: "No tienes permiso para esta acción." };
    }
    if (code === "22023") return { action: "show", message: message || "Revisa la decisión y el mensaje." };
    if (code === "P0002") return { action: "notfound", message: "No encontramos la propuesta." };
    if (code === "55000") return { action: "reload", message: message || "La propuesta no se puede decidir en su estado actual." };
    return { action: "network", message: "No pudimos enviar la decisión. Vuelve a cargar la propuesta antes de reintentar." };
  }

  /* ---------- puerta ----------
     options.onReady({ session }): la página puede leer y decidir.
     options.onLock(): la página debe vaciar lo que haya pintado (se pierde
     el acceso o el segundo factor). Devuelve { relock, deny }. */
  function start({ onReady, onLock }){
    const gate = document.getElementById("mod-gate");
    const app = document.getElementById("mod-app");
    let session = null;

    function hideApp(){
      if (!app.hidden && typeof onLock === "function") onLock();
      app.hidden = true;
    }

    function showGate(...children){
      hideApp();
      gate.replaceChildren(...children);
      gate.hidden = false;
    }

    function focusFirst(node){
      if (!node) return;
      node.setAttribute("tabindex", "-1");
      node.focus({ preventScroll: false });
    }

    function showLoading(){
      showGate(el("p", "card-meta", "Comprobando tu acceso…"));
    }

    function showError(text, retry){
      const title = el("p", "pd-empty-title", text);
      const button = el("button", "btn btn-primary", "Reintentar");
      button.type = "button";
      button.addEventListener("click", retry);
      const box = el("div", "pd-empty");
      box.setAttribute("role", "alert");
      box.append(title, button);
      showGate(box);
    }

    function deny(text){
      const box = el("div", "pd-empty");
      box.append(
        el("p", "pd-empty-title", text || "Esta página es solo para el equipo de Mobau."),
        el("p", "pd-empty-text", "Si crees que deberías tener acceso, contacta con el equipo de Mobau.")
      );
      const back = el("a", "btn btn-outline", "Ir al inicio");
      back.href = "index.html";
      box.append(back);
      showGate(box);
      focusFirst(box.firstChild);
    }

    function showPending(){
      const box = el("div", "pd-empty");
      box.append(
        el("p", "pd-empty-title", "Verificación en dos pasos"),
        el("p", "pd-empty-text", "La verificación en dos pasos todavía no está configurada para esta cuenta. Contacta con el equipo de Mobau.")
      );
      box.setAttribute("role", "status");
      showGate(box);
      focusFirst(box.firstChild);
    }

    function showCodeForm(factorId, note){
      const form = el("form", "mod-mfa");
      form.noValidate = true;
      const title = el("h2", "mod-mfa-title", "Verificación en dos pasos");
      const text = el("p", "pd-empty-text", note
        ? `${note} Escribe el código de 6 dígitos de tu app de autenticación.`
        : "Escribe el código de 6 dígitos de tu app de autenticación.");
      const field = el("div", "field");
      const label = el("label", "", "Código");
      label.htmlFor = "mod-mfa-code";
      const input = el("input", "mod-mfa-code");
      input.id = "mod-mfa-code";
      input.name = "one-time-code";
      input.inputMode = "numeric";
      input.autocomplete = "one-time-code";
      input.maxLength = 6;
      input.setAttribute("pattern", "[0-9]{6}");
      input.setAttribute("aria-describedby", "mod-mfa-msg");
      field.append(label, input);
      const button = el("button", "btn btn-primary", "Verificar");
      button.type = "submit";
      const msg = el("p", "mod-mfa-msg");
      msg.id = "mod-mfa-msg";
      msg.setAttribute("role", "status");
      msg.setAttribute("aria-live", "polite");
      form.append(title, text, field, button, msg);

      let busy = false;
      form.addEventListener("submit", async (e) => {
        e.preventDefault();
        if (busy) return;
        const code = input.value.trim();
        input.value = "";
        if (!CODE_PATTERN.test(code)){
          msg.textContent = "Escribe los 6 dígitos del código.";
          input.focus();
          return;
        }
        busy = true;
        button.disabled = true;
        msg.textContent = "Verificando…";
        let verified = false;
        try {
          const { data: challenge, error: challengeError } = await supabaseClient.auth.mfa.challenge({ factorId });
          if (!challengeError && challenge && challenge.id){
            const { error: verifyError } = await supabaseClient.auth.mfa.verify({ factorId, challengeId: challenge.id, code });
            verified = !verifyError;
          }
        } catch (err) {
          verified = false;
        }
        if (!verified){
          busy = false;
          button.disabled = false;
          msg.textContent = "El código no es válido o ha caducado. Inténtalo de nuevo.";
          input.focus();
          return;
        }
        /* El desbloqueo lo decide el servidor, nunca el cliente. */
        let state = null;
        try {
          state = await MobauAccess.adminSession({ fresh: true });
        } catch (err) {
          state = null;
        }
        if (!state || !state.admin || !state.aal2){
          showError("No pudimos completar la verificación.", run);
          return;
        }
        unlock();
      });

      const box = el("div", "pd-card mod-mfa-card");
      box.append(form);
      showGate(box);
      input.focus();
    }

    async function mfaStep(note){
      showLoading();
      let factors = null;
      try {
        const { data, error } = await supabaseClient.auth.mfa.listFactors();
        if (!error && data) factors = (data.all || []).filter(f => f.factor_type === "totp" && f.status === "verified");
      } catch (err) {
        factors = null;
      }
      if (!factors){
        showError("No pudimos comprobar tu acceso.", () => mfaStep(note));
        return;
      }
      if (!factors.length){
        showPending();
        return;
      }
      showCodeForm(factors[0].id, note);
    }

    function unlock(){
      gate.hidden = true;
      gate.replaceChildren();
      app.hidden = false;
      onReady({ session });
    }

    /* Se perdió el segundo factor (o el acceso) durante el uso: vuelve a
       preguntar al servidor y, según la respuesta, pide el código, deniega
       o sigue (devuelve true si la página puede continuar). note: texto
       opcional para la pantalla del código. */
    async function relock(note){
      let state = null;
      try {
        state = await MobauAccess.adminSession({ fresh: true });
      } catch (err) {
        state = null;
      }
      if (state && state.admin && state.aal2) return true;
      if (!state){
        showError("No pudimos comprobar tu acceso.", run);
        return false;
      }
      if (!state.admin){
        deny("Tu cuenta ya no tiene acceso de moderación.");
        return false;
      }
      await mfaStep(note);
      return false;
    }

    async function run(){
      showLoading();
      session = await MobauAuth.requireSession();
      if (!session) return; // ya redirigió a acceso.html

      const kind = await MobauAccess.accountKind();
      if (kind === "supplier" || kind === "client"){
        deny();
        return;
      }
      /* Misma consulta que la cabecera (una por página). */
      let state = null;
      try {
        state = await MobauAccess.adminSession();
      } catch (err) {
        state = null;
      }
      if (!state){
        showError("No pudimos comprobar tu acceso.", run);
        return;
      }
      if (!state.admin){
        deny();
        return;
      }
      if (state.aal2){
        unlock();
        return;
      }
      await mfaStep();
    }

    run();
    return { relock, deny: (text) => deny(text) };
  }

  return {
    STATUS, FIELD_LABELS, URL_FIELDS, AVAILABILITY, PRICE_STATUS,
    el, chip, safeLink, formatDate, formatMoney, priceText, fieldLabel, decisionError, start
  };
})();
