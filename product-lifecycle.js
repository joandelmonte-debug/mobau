/* ============================================================
   MOBAU — Ciclo de vida de productos (punto 41, D2)
   ------------------------------------------------------------
   Único punto de la interfaz que llama a las nueve funciones de ciclo de
   vida (41-03 y 41-05) y que crea, envía o retira propuestas «republish»
   (41-04).
   Lo usan distribuidor-productos.html, moderacion.html,
   moderacion-propuesta.html y moderacion-producto.html.

   Interruptor: con MobauAccess.LIFECYCLE_UI_ENABLED apagado, ninguna
   función de este archivo hace peticiones (call() falla antes de la red) y
   las páginas no pintan nada nuevo. El interruptor del servidor y los
   permisos (41-06) siguen siendo la protección real: aunque la interfaz
   esté encendida, el servidor decide qué acciones existen
   (allowed_actions) y rechaza el resto.

   Textos: BORRADOR para revisión (no aprobados).
   ============================================================ */

const MobauLifecycle = (() => {
  /* Las nueve funciones nuevas: solo se llaman desde call(). */
  const FUNCTIONS = Object.freeze([
    "my_products_lifecycle", "my_product_lifecycle_events",
    "distributor_retire_product", "distributor_trash_product", "distributor_restore_product",
    "mobau_product_lifecycle", "mobau_purge_product", "mobau_product_references", "mobau_product_lifecycle_view"
  ]);
  const REASON_MAX = 500;
  const CATALOG_CACHE_KEYS = ["mobau_catalog_v2", "mobau_distributors_v2", "mobau_categories_v2"]; // las de script.js (D1)

  function enabled(){
    return typeof MobauAccess !== "undefined" && MobauAccess.LIFECYCLE_UI_ENABLED === true;
  }

  /* ---------- textos (borrador) ---------- */
  const STATES = {
    published:         { label: "Publicado",            kind: "ok" },
    retired:           { label: "Retirado",             kind: "alert" },
    legacy_retired:    { label: "Retirado (heredado)",  kind: "neutral" },
    trashed:           { label: "En papelera",          kind: "alert" },
    draft:             { label: "Borrador",             kind: "neutral" },
    in_review:         { label: "En revisión",          kind: "wait" },
    changes_requested: { label: "Cambios solicitados",  kind: "alert" }
  };
  const ACTIONS = {
    retire:            "Retirar del catálogo",
    trash:             "Mover a la papelera",
    restore:           "Restaurar",
    request_republish: "Solicitar republicación",
    purge:             "Eliminar definitivamente"
  };
  const CONFIRM = {
    retire:  "El producto dejará de verse en el catálogo y en su ficha de inmediato. Para volver a publicarlo hará falta que Mobau apruebe una solicitud de republicación.",
    trash:   "El producto pasará a la papelera. Podrás restaurarlo durante 30 días; después Mobau podrá eliminarlo definitivamente.",
    restore: "El producto volverá al estado que tenía antes de la papelera (retirado o borrador). No se publicará.",
    request_republish: "Mobau revisará la solicitud. El producto seguirá retirado hasta que la apruebe.",
    mobau_trash:   "El producto pasará a la papelera. Durante 30 días solo se podrá eliminar definitivamente de forma anticipada.",
    mobau_restore: "El producto volverá al estado que tenía antes de la papelera. No se publicará.",
    purge:   "Eliminar definitivamente borra el producto, su precio, sus propuestas y el historial de esas propuestas; solo queda un registro de auditoría con recuentos, sin el contenido. No se puede deshacer. El servidor lo impide si el producto está en alguna línea de proyecto (activo o archivado, también las incluidas en solicitudes de cotización), si otra tabla lo referencia, si hay referencias que no se pueden comprobar o si tiene una propuesta abierta."
  };
  const BLOCKS = {
    open_proposal:            "Tiene una propuesta abierta: no se puede retirar ni mover a la papelera hasta que se cierre.",
    legacy_pending_review:    "Retirado antes del ciclo de vida: pendiente de revisión individual por Mobau. Sin acciones.",
    in_review:                "El producto está en revisión: sin acciones de ciclo de vida.",
    purge_not_due:            "El plazo de la papelera no ha terminado: solo cabe la eliminación definitiva anticipada, con motivo.",
    purge_blocked_references: "Está en proyectos o solicitudes de cotización: la eliminación definitiva está bloqueada.",
    purge_unknown_reference:  "Hay referencias que no se pueden comprobar: la eliminación definitiva está bloqueada."
  };
  const TEXT = {
    unavailable:        "La gestión del ciclo de vida todavía no está disponible.",
    serverDisabled:     "El servidor todavía no tiene activada la gestión del ciclo de vida. No hay acciones disponibles.",
    noPermission:       "Esta función no está disponible para tu sesión. Puede que todavía no esté habilitada o que no tengas permiso.",
    notVerified:        "Tu empresa no está verificada: no puedes gestionar el ciclo de vida de tus productos.",
    selfCompany:        "No puedes gestionar productos ni propuestas de tu propia empresa.",
    network:            "No pudimos comprobar el estado de ciclo de vida. Comprueba tu conexión e inténtalo de nuevo.",
    versionConflict:    "El producto cambió desde que lo abriste. Hemos vuelto a cargarlo: revisa su estado antes de repetir la acción.",
    notFound:           "No encontramos el producto.",
    reasonRequired:     `Escribe el motivo (entre 1 y ${REASON_MAX} caracteres).`,
    reasonTooLong:      `El motivo supera los ${REASON_MAX} caracteres.`,
    confirmMismatch:    "Escribe exactamente el identificador del producto para confirmar la eliminación definitiva.",
    notChecked:         "Estado sin comprobar",
    generic:            "No pudimos completar la acción."
  };
  const EVENTS = {
    retire: "Retirado", trash: "Movido a la papelera", restore: "Restaurado",
    republish: "Republicado", purge: "Eliminado definitivamente"
  };
  const ACTORS = { distributor: "Empresa", mobau: "Mobau" };
  const DONE = {
    retire:  "Producto retirado del catálogo.",
    trash:   "Producto movido a la papelera.",
    restore: "Producto restaurado.",
    request_republish: "Solicitud de republicación enviada a Mobau.",
    purge:   "Producto eliminado definitivamente."
  };
  /* Mensajes por código de error (hint) de las funciones de 41-03/04/05. */
  const HINTS = {
    feature_disabled:          TEXT.serverDisabled,
    not_authenticated:         "Tu sesión ha caducado. Vuelve a iniciar sesión.",
    not_verified_distributor:  TEXT.notVerified,
    not_admin:                 "Tu cuenta no tiene acceso de moderación.",
    aal2_required:             "Tu verificación en dos pasos ha caducado. Vuelve a verificar para continuar.",
    self_moderation_forbidden: TEXT.selfCompany,
    product_not_found:         TEXT.notFound,
    version_conflict:          TEXT.versionConflict,
    missing_version:           "Falta la versión del producto: vuelve a cargar la página.",
    invalid_parameter:         "Los datos de la acción no son válidos. Vuelve a cargar la página.",
    invalid_action:            "Acción no válida. Vuelve a cargar la página.",
    invalid_reason:            TEXT.reasonRequired,
    invalid_state:             "El producto no está en un estado que permita esta acción. Vuelve a cargarlo.",
    open_proposal:             BLOCKS.open_proposal,
    legacy_pending_review:     BLOCKS.legacy_pending_review,
    in_review:                 BLOCKS.in_review,
    restore_window_expired:    "El plazo para restaurar terminó. Contacta con Mobau.",
    republish_requires_retired: "Solo se puede solicitar republicar un producto retirado.",
    confirm_mismatch:          TEXT.confirmMismatch,
    purge_not_due:             BLOCKS.purge_not_due,
    purge_blocked_references:  BLOCKS.purge_blocked_references,
    purge_unknown_reference:   BLOCKS.purge_unknown_reference
  };

  /* ---------- errores ----------
     Separa: interfaz apagada, servidor apagado (feature_disabled), sin
     permiso (por ejemplo, sin EXECUTE: 42501 sin código propio, o función no
     expuesta), sesión o MFA, conflicto de versión, no encontrado, bloqueos y
     red. Ninguno se interpreta como lista vacía ni deja acciones operativas. */
  function classify(error){
    if (!error) return { kind: "network", message: TEXT.network };
    if (error.kind === "ui_disabled") return { kind: "ui_disabled", message: TEXT.unavailable };
    const code = error.code || "";
    const hint = error.hint || "";
    if (hint === "feature_disabled") return { kind: "server_disabled", message: HINTS.feature_disabled };
    if (code === "42501"){
      if (hint === "aal2_required") return { kind: "mfa", message: HINTS.aal2_required };
      if (hint === "not_admin") return { kind: "denied", message: HINTS.not_admin };
      if (hint === "not_authenticated") return { kind: "login", message: HINTS.not_authenticated };
      if (hint === "not_verified_distributor") return { kind: "no_permission", message: HINTS.not_verified_distributor };
      if (hint === "self_moderation_forbidden") return { kind: "blocked", message: HINTS.self_moderation_forbidden };
      if (hint === "product_not_found") return { kind: "not_found", message: TEXT.notFound };
      return { kind: "no_permission", message: TEXT.noPermission };
    }
    if (code === "PGRST202" || code === "42883") return { kind: "no_permission", message: TEXT.noPermission };
    if (code === "40001") return { kind: "version_conflict", message: HINTS.version_conflict };
    if (code === "P0002") return { kind: "not_found", message: TEXT.notFound };
    if (code === "22023" || code === "55000") return { kind: "blocked", message: HINTS[hint] || error.message || TEXT.generic };
    if (code === "23505") return { kind: "blocked", message: BLOCKS.open_proposal };
    if (!code || code === "20" || /abort|fetch|network/i.test(error.message || "")) return { kind: "network", message: TEXT.network };
    return { kind: "blocked", message: HINTS[hint] || TEXT.generic };
  }

  /* ---------- llamadas ---------- */
  function uiDisabled(){
    const e = new Error("lifecycle_ui_disabled");
    e.kind = "ui_disabled";
    return e;
  }

  /* Única vía a las nueve funciones. Con el interruptor apagado no hay red. */
  async function call(fn, args){
    if (!enabled()) throw uiDisabled();
    if (!FUNCTIONS.includes(fn)) throw new Error(`Función de ciclo de vida desconocida: ${fn}`);
    let res;
    try {
      res = await supabaseClient.rpc(fn, args || {});
    } catch (err) {
      throw { code: "", message: (err && err.message) || "network" };
    }
    if (res.error) throw res.error;
    return res.data;
  }

  /* Motivo como lo cuenta el servidor (char_length tras btrim). */
  function reasonLength(text){ return [...String(text || "").trim()].length; }
  function reasonError(text, required){
    const n = reasonLength(text);
    if (required && n === 0) return TEXT.reasonRequired;
    if (n > REASON_MAX) return TEXT.reasonTooLong;
    return null;
  }

  /* Distribuidor (41-03) */
  const myProducts = () => call("my_products_lifecycle", {});
  const myEvents = (productId) => call("my_product_lifecycle_events", { p_product_id: productId });
  const retire = (productId, reason, updatedAt) =>
    call("distributor_retire_product", { p_product_id: productId, p_reason: reason, p_expected_updated_at: updatedAt });
  const trash = (productId, updatedAt) =>
    call("distributor_trash_product", { p_product_id: productId, p_expected_updated_at: updatedAt });
  const restore = (productId, updatedAt) =>
    call("distributor_restore_product", { p_product_id: productId, p_expected_updated_at: updatedAt });

  /* Republicación (41-04): propuesta sin cambios; se crea como borrador y se
     envía, igual que el resto de propuestas. Si falla el envío, queda un
     borrador que se puede enviar o retirar desde Mis productos. */
  async function requestRepublish(productId){
    if (!enabled()) throw uiDisabled();
    const { data, error } = await supabaseClient.from("product_proposals")
      .insert({ proposal_kind: "republish", product_id: productId }).select("id, status, version").single();
    if (error) throw error;
    return submitRepublish(data.id);
  }
  async function submitRepublish(proposalId){
    if (!enabled()) throw uiDisabled();
    const { data, error } = await supabaseClient.from("product_proposals")
      .update({ status: "submitted" }).eq("id", proposalId).select("id, status, version").single();
    if (error) throw error;
    return data;
  }
  /* Retirar una solicitud abierta: el mismo cambio de estado (→ withdrawn)
     que el resto de propuestas (38-C); el servidor decide si se permite. */
  async function withdrawRepublish(proposalId){
    if (!enabled()) throw uiDisabled();
    const { data, error } = await supabaseClient.from("product_proposals")
      .update({ status: "withdrawn" }).eq("id", proposalId).select("id, status").single();
    if (error) throw error;
    return data;
  }

  /* Mobau (41-05) */
  const view = (productId) => call("mobau_product_lifecycle_view", { p_product_id: productId });
  const references = (productId) => call("mobau_product_references", { p_product_id: productId });
  const act = (productId, action, reason, updatedAt) =>
    call("mobau_product_lifecycle", { p_product_id: productId, p_action: action, p_reason: reason || null, p_expected_updated_at: updatedAt });
  /* El id de confirmación se envía tal cual se escribió: el servidor lo
     compara exactamente con el del producto. */
  const purge = (productId, confirmId, reason, early, updatedAt) =>
    call("mobau_purge_product", { p_product_id: productId, p_confirm_id: confirmId, p_reason: reason, p_early: !!early, p_expected_updated_at: updatedAt });

  /* ---------- utilidades ---------- */
  /* Tras una acción correcta: la caché del catálogo de esta pestaña ya no vale. */
  function invalidateCatalog(){
    if (typeof invalidateCatalogCache === "function"){ invalidateCatalogCache(); return; }
    CATALOG_CACHE_KEYS.forEach(key => { try { sessionStorage.removeItem(key); } catch (e) {} });
  }

  /* Ejecuta fn sobre cada elemento con como mucho `limit` a la vez. Nunca
     lanza: devuelve [{ item, ok, value | error }] en el orden de entrada. */
  async function runLimited(items, limit, fn){
    const results = new Array(items.length);
    let next = 0;
    async function worker(){
      while (next < items.length){
        const i = next++;
        try { results[i] = { item: items[i], ok: true, value: await fn(items[i]) }; }
        catch (error) { results[i] = { item: items[i], ok: false, error }; }
      }
    }
    await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
    return results;
  }

  function formatDate(value){
    if (!value) return "";
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? "" : d.toLocaleDateString("es-DO", { day: "numeric", month: "long", year: "numeric" });
  }

  function stateInfo(state){ return STATES[state] || { label: state || TEXT.notChecked, kind: "neutral" }; }

  return {
    FUNCTIONS, REASON_MAX, STATES, ACTIONS, CONFIRM, BLOCKS, TEXT, DONE, HINTS, EVENTS, ACTORS,
    enabled, classify, reasonError, reasonLength, stateInfo, formatDate,
    myProducts, myEvents, retire, trash, restore, requestRepublish, submitRepublish, withdrawRepublish,
    view, references, act, purge, invalidateCatalog, runLimited
  };
})();
