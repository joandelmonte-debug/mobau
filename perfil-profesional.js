/* ============================================================
   MOBAU — Perfil profesional: validación compartida y borrador de alta
   ============================================================
   Depende de supabase-client.js (supabaseClient, MobauAccess), que debe
   cargarse antes.

   Una sola definición de qué es un perfil profesional válido, usada por:
   - crear-cuenta.html (paso de perfil del alta, ANTES de pedir el email),
   - verificar-correo.html (crea el perfil al volver del enlace mágico),
   - inscripcion-profesional.html (Mi perfil y respaldo ?paso=perfil).

   Borrador de alta (Punto 35A-1b): el perfil se rellena antes de que exista
   la cuenta, y la RLS de professional_profiles solo deja insertar la fila
   propia (user_id = auth.uid()). Por eso los datos esperan en este
   dispositivo (localStorage, porque el enlace suele abrirse en otra
   pestaña) hasta que el enlace mágico crea la sesión. El borrador:
   - solo guarda el plan y los campos del perfil YA validados — nunca el
     email ni ningún otro dato;
   - caduca a las 2 horas y se vuelve a validar entero en cada lectura
     (manipulado, incompleto o caducado -> se borra);
   - se borra al crear el perfil, al entrar como distribuidor, al detectar
     otra cuenta y con la acción visible "Descartar estos datos".
   ============================================================ */

const MobauPerfil = {
  DRAFT_KEY: "mobau_signup_draft",
  DRAFT_TTL_MS: 2 * 60 * 60 * 1000, // 2 horas, igual que la intención de acceso

  /* Tipos profesionales (columna professional_type). */
  TYPES: new Map([
    ["arquitecto", "Arquitecto/a"],
    ["interiorista", "Interiorista"],
    ["disenador", "Diseñador/a"],
    ["estudio", "Estudio"],
    ["particular", "Propietario / particular"],
    ["otro", "Otro"]
  ]),

  /* Ayuda breve que se muestra bajo el selector con ciertos tipos. */
  TYPE_HINTS: new Map([
    ["particular", "Para personas que desean organizar referencias y consultar información de producto para su propio proyecto."]
  ]),

  /* Longitud máxima de cada campo de texto: evita guardar (o insertar)
     valores desproporcionados. */
  MAX_LENGTHS: {
    professional_name: 120,
    city: 80,
    studio_name: 120,
    phone: 40,
    website: 200,
    instagram: 80
  },

  typeLabel(value) {
    return this.TYPES.get(value) || null;
  },

  /* Muestra bajo el selector la ayuda del tipo elegido (si la tiene) y la
     enlaza con aria-describedby; la oculta con cualquier otro tipo. */
  bindTypeHint(select, hintEl) {
    const update = () => {
      const hint = this.TYPE_HINTS.get(select.value) || "";
      hintEl.textContent = hint;
      hintEl.hidden = !hint;
      if (hint) select.setAttribute("aria-describedby", hintEl.id);
      else select.removeAttribute("aria-describedby");
    };
    select.addEventListener("change", update);
    update();
    return update;
  },

  /* Misma regla que la solicitud de cotización (proyectos-cotizacion.html):
     dígitos, "+", espacios, paréntesis, guiones y puntos, con al menos 7
     dígitos — el perfil completado en el alta sirve después para cotizar. */
  isValidContactPhone(raw) {
    if (typeof raw !== "string" || !/^[0-9+()\-.\s]+$/.test(raw)) return false;
    return raw.replace(/\D/g, "").length >= 7;
  },

  /* Valida y normaliza un perfil. Devuelve { ok: true, record } con la fila
     lista para professional_profiles (sin user_id), o { ok: false, error }
     con un texto fijo para mostrar. requirePhone: teléfono obligatorio
     (alta profesional). */
  validate(input, { requirePhone = false } = {}) {
    const text = (value) => (typeof value === "string" ? value.trim() : "");
    const record = {
      professional_name: text(input && input.professional_name),
      professional_type: text(input && input.professional_type),
      city: text(input && input.city),
      studio_name: text(input && input.studio_name) || null,
      phone: text(input && input.phone) || null,
      website: text(input && input.website) || null,
      instagram: text(input && input.instagram) || null
    };
    if (!record.professional_name || !record.professional_type || !record.city) {
      return { ok: false, error: "Completa nombre, tipo de perfil y ciudad para continuar." };
    }
    if (!this.TYPES.has(record.professional_type)) {
      return { ok: false, error: "Selecciona un tipo de perfil de la lista." };
    }
    for (const key of Object.keys(this.MAX_LENGTHS)) {
      if (record[key] && record[key].length > this.MAX_LENGTHS[key]) {
        return { ok: false, error: "Alguno de los datos es demasiado largo. Revísalo e intenta de nuevo." };
      }
    }
    if (requirePhone && !this.isValidContactPhone(record.phone || "")) {
      return { ok: false, error: "Indica un teléfono de contacto válido (al menos 7 dígitos)." };
    }
    return { ok: true, record };
  },

  /* ---------- borrador de alta ---------- */

  /* Guarda plan + perfil solo si ambos son válidos. Devuelve true si quedó
     guardado. Campos del alta: nombre, tipo, ciudad, estudio y teléfono. */
  saveDraft({ plan, profile }) {
    const safePlan = MobauAccess.normalizePlan(plan);
    const result = this.validate(profile, { requirePhone: true });
    if (!safePlan || !result.ok) return false;
    const { professional_name, professional_type, city, studio_name, phone } = result.record;
    try {
      localStorage.setItem(this.DRAFT_KEY, JSON.stringify({
        plan: safePlan,
        profile: { professional_name, professional_type, city, studio_name, phone },
        createdAt: Date.now()
      }));
      return true;
    } catch (e) {
      return false; // sin localStorage no se puede continuar con el alta
    }
  },

  /* Lee y vuelve a validar el borrador, sin borrarlo. Caducado, con fecha
     futura, manipulado o incompleto -> null (y se borra). */
  readDraft() {
    let raw = null;
    try {
      raw = localStorage.getItem(this.DRAFT_KEY);
    } catch (e) {
      return null;
    }
    if (!raw) return null;
    let data = null;
    try {
      data = JSON.parse(raw);
    } catch (e) {
      data = null;
    }
    const age = data && typeof data.createdAt === "number" ? Date.now() - data.createdAt : -1;
    const plan = data ? MobauAccess.normalizePlan(data.plan) : null;
    const result = data && data.profile && typeof data.profile === "object"
      ? this.validate(data.profile, { requirePhone: true })
      : { ok: false };
    if (!(age >= 0 && age <= this.DRAFT_TTL_MS) || !plan || !result.ok) {
      this.clearDraft();
      return null;
    }
    const { professional_name, professional_type, city, studio_name, phone } = result.record;
    return { plan, profile: { professional_name, professional_type, city, studio_name, phone }, createdAt: data.createdAt };
  },

  clearDraft() {
    try {
      localStorage.removeItem(this.DRAFT_KEY);
    } catch (e) {
      /* nada que borrar */
    }
  },

  /* El borrador pertenece a la cuenta que acaba de entrar solo si el nombre
     que se envió con el enlace (metadato "name", que la cuenta recibe al
     crearse) coincide. Cualquier otra cuenta —una ya existente con otro
     nombre, otra persona en este navegador— no hereda los datos. */
  draftMatchesAccount(draft, session) {
    const metadata = (session && session.user && session.user.user_metadata) || {};
    return typeof metadata.name === "string" && metadata.name.trim() === draft.profile.professional_name;
  },

  /* Cierra el alta al volver del enlace mágico. Nunca sobrescribe un perfil
     existente ni duplica filas. Resultado (status):
     - "supplier": cuenta de distribuidor; borrador e intención descartados.
     - "existing": la cuenta ya tenía perfil; se conserva y se descarta el borrador.
     - "created":  perfil creado con el borrador; borrador borrado.
     - "missing":  no hay borrador válido en este dispositivo (otro navegador,
                   caducado) o era de otra cuenta (descartado).
     - "error":    fallo al consultar o crear; el borrador se conserva para reintentar.
     plan: el plan del borrador, si lo había (solo para navegar). */
  async completeSignup(session) {
    const userId = session.user.id;
    const { data: account, error: roleError } = await supabaseClient
      .from("profiles").select("role").eq("id", userId).maybeSingle();
    if (roleError) return { status: "error" };
    if (account && account.role === "supplier") {
      this.clearDraft();
      MobauAccess.clearIntent();
      return { status: "supplier" };
    }

    const existing = await this.fetchProfileExists(userId);
    if (existing === null) return { status: "error" };
    const draft = this.readDraft();
    const plan = draft ? draft.plan : null;
    if (existing) {
      this.clearDraft();
      return { status: "existing", plan };
    }
    if (!draft) return { status: "missing", plan: null };
    if (!this.draftMatchesAccount(draft, session)) {
      this.clearDraft();
      return { status: "missing", plan: null, otherAccount: true };
    }

    const { error } = await supabaseClient
      .from("professional_profiles")
      .insert({ ...draft.profile, user_id: userId });
    if (error) {
      /* Si otra pestaña lo creó a la vez (user_id es único), ya existe. */
      if (await this.fetchProfileExists(userId)) {
        this.clearDraft();
        return { status: "created", plan };
      }
      return { status: "error", plan };
    }
    this.clearDraft();
    return { status: "created", plan };
  },

  /* true / false según exista el perfil, o null si la consulta falla. */
  async fetchProfileExists(userId) {
    const { data, error } = await supabaseClient
      .from("professional_profiles").select("user_id").eq("user_id", userId).maybeSingle();
    if (error) return null;
    return !!data;
  }
};
