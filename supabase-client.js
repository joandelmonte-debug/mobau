/* ============================================================
   MOBAU — Cliente de Supabase (Bloque 0)
   ============================================================
   Este es el único archivo que necesita tus claves de Supabase.
   Ve a tu proyecto en supabase.com → Settings → API y pega:

   1) "Project URL"        →  SUPABASE_URL
   2) "anon" / "public" key →  SUPABASE_ANON_KEY

   Nunca pegues aquí la "service_role key" — esa nunca debe
   estar en ningún archivo que se le sirva al navegador.

   Este archivo depende de que la librería de Supabase ya se
   haya cargado antes, vía la etiqueta:
   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
   ============================================================ */

const SUPABASE_URL = "https://skcoxtdppdcietgojdal.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_NCxP_LqiNJCKv3yrpi33fg_osKCmQIL"; // clave publicable ("anon" / "public")

/* Clave que usa @supabase/supabase-js v2 por defecto para guardar la
   sesión en localStorage (persistSession:true, sin storageKey propio
   aquí abajo) — se calcula a partir de SUPABASE_URL para no repetirla
   a mano. Sirve solo para una comprobación síncrona (MobauAuth.
   hasStoredSession(), más abajo): si el formato de esta clave cambiara
   en una versión futura de la librería, el peor caso es tratar a un
   usuario autenticado como anónimo para la selección temporal (se
   perdería al cerrar la pestaña) — nunca pérdida de datos de su cuenta
   real, que sigue viviendo en Supabase. */
const SUPABASE_SESSION_STORAGE_KEY = `sb-${new URL(SUPABASE_URL).hostname.split(".")[0]}-auth-token`;

const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,     // guarda la sesión en localStorage del navegador
    autoRefreshToken: true,   // renueva el token antes de que caduque
    detectSessionInUrl: true  // lee el token que llega en la URL del enlace mágico
  }
});

/* Lista blanca de destinos permitidos tras el enlace mágico — nunca se
   acepta una ruta fuera de este array, ver sendMagicLink() más abajo. */
const MAGIC_LINK_NEXT_PAGES = ["index.html", "perfil-distribuidor.html", "acceso.html", "verificar-correo.html"];

/* ---------- acceso profesional: motivos y retorno seguro (Punto 35A) ----------
   acceso.html es la puerta de entrada y también la página donde aterriza el
   enlace mágico. Desde ahí se decide adónde volver, SIEMPRE a partir de
   valores de esta lista blanca: nunca se redirige a un valor recibido tal
   cual (URL, localStorage), solo a una ruta reconstruida desde partes ya
   validadas. Todas las rutas son relativas, así que funcionan igual en la
   raíz del dominio y bajo un subdirectorio (/mobau/), con o sin .html en la
   URL (Cloudflare Pages las sirve sin extensión). */
const PRODUCT_ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

const MobauAccess = {
  INTENT_KEY: "mobau_access_intent",
  INTENT_TTL_MS: 2 * 60 * 60 * 1000, // 2 horas

  /* Motivo -> ruta a la que se vuelve tras iniciar sesión. "moodboard"
     queda definido pero inactivo (active: false) hasta 35B: se trata
     igual que un motivo desconocido. */
  MOTIVOS: new Map([
    ["guardar",    { route: "seleccion.html", active: true }],
    ["proyecto",   { route: "proyectos-cotizacion.html?mode=save", active: true }],
    ["cotizacion", { route: "proyectos-cotizacion.html?mode=send", active: true }],
    ["moodboard",  { route: "seleccion.html", active: false }]
  ]),

  /* Páginas a las que se puede volver con "next", y los únicos parámetros
     que conserva cada una (con su formato). Cualquier otro parámetro se
     descarta; uno conocido con formato inválido invalida el "next" entero. */
  NEXT_PAGES: new Map([
    ["index", {}],
    ["catalogo", {}],
    ["distribuidores", {}],
    ["seleccion", {}],
    ["cuenta", {}],
    ["inscripcion-profesional", {}],
    ["producto", { id: PRODUCT_ID_PATTERN }],
    ["proyectos", { status: /^(active|archived|requested)$/ }],
    ["proyectos-detalle", { id: UUID_PATTERN }],
    ["proyectos-resumen", { id: UUID_PATTERN }],
    ["proyectos-cotizacion", { mode: /^(save|send)$/, id: UUID_PATTERN }]
  ]),

  /* Planes profesionales que se pueden elegir al crear la cuenta. Solo
     sirven para NAVEGAR (qué pasos ve el usuario): nunca conceden permisos
     ni activan nada — el plan real lo asigna Mobau en la base de datos.
     requiresActivation: el plan necesita el paso de activación manual. */
  PLANES: new Map([
    ["gratis",     { requiresActivation: false }],
    ["individual", { requiresActivation: true }],
    ["estudio",    { requiresActivation: true }]
  ]),

  /* Modos de acceso.html: "login" (cuentas existentes) y "crear" (alta
     profesional, sin email). Cualquier otro valor -> null. */
  normalizeModo(value) {
    return value === "login" || value === "crear" ? value : null;
  },

  /* Devuelve el motivo si es uno de los activos, o null. */
  normalizeMotivo(value) {
    if (typeof value !== "string") return null;
    const motivo = this.MOTIVOS.get(value);
    return motivo && motivo.active ? value : null;
  },

  /* Devuelve el plan si es uno de la lista, o null. */
  normalizePlan(value) {
    return typeof value === "string" && this.PLANES.has(value) ? value : null;
  },

  /* true si el plan (ya validado o no) necesita el paso de activación. */
  planRequiresActivation(value) {
    const plan = this.normalizePlan(value);
    return !!plan && this.PLANES.get(plan).requiresActivation;
  },

  /* Reconstruye "pagina.html?param=valor" desde una página de la lista
     blanca y sus parámetros ya validados, o null si algo no encaja. */
  buildLocalPage(page, params) {
    const rules = this.NEXT_PAGES.get(page);
    if (!rules) return null;
    const out = new URLSearchParams();
    for (const key of Object.keys(rules)) {
      const value = params.get(key);
      if (value === null) continue;
      if (value.length > 64 || !rules[key].test(value)) return null;
      out.set(key, value);
    }
    const query = out.toString();
    return `${page}.html${query ? `?${query}` : ""}`;
  },

  /* Valida un "next" recibido. Solo acepta "pagina" o "pagina.html",
     opcionalmente con "?query": cualquier "/", ":", "\", "." extra o "#"
     (URL absoluta, "//", "javascript:", "../", fragmentos) lo rechaza. */
  sanitizeNext(raw) {
    if (typeof raw !== "string" || raw.length > 300) return null;
    const match = /^([a-z0-9-]+)(?:\.html)?(?:\?([^#]*))?$/.exec(raw);
    if (!match) return null;
    return this.buildLocalPage(match[1], new URLSearchParams(match[2] || ""));
  },

  /* La página actual como "next" (para requireSession), o null si no está
     en la lista blanca. "/" o ".../" es index; se acepta con o sin .html. */
  currentPageAsNext() {
    const last = window.location.pathname.split("/").pop() || "index";
    const page = last.replace(/\.html$/, "");
    if (!/^[a-z0-9-]+$/.test(page)) return null;
    return this.buildLocalPage(page, new URLSearchParams(window.location.search));
  },

  /* URL relativa de acceso.html para volver después a la página actual. */
  accessUrlForCurrentPage() {
    const next = this.currentPageAsNext();
    return next ? `acceso.html?next=${encodeURIComponent(next)}` : "acceso.html";
  },

  /* Guarda la intención (motivo + next + plan) al enviar el enlace: el
     enlace suele abrirse en otra pestaña, así que tiene que vivir en
     localStorage. Solo se guardan valores ya validados; si no hay nada
     que guardar, se borra cualquier intención anterior. */
  saveIntent({ motivo, next, plan }) {
    const safeMotivo = this.normalizeMotivo(motivo);
    const safeNext = this.sanitizeNext(next);
    const safePlan = this.normalizePlan(plan);
    try {
      if (!safeMotivo && !safeNext && !safePlan) {
        localStorage.removeItem(this.INTENT_KEY);
        return;
      }
      localStorage.setItem(this.INTENT_KEY, JSON.stringify({ motivo: safeMotivo, next: safeNext, plan: safePlan, createdAt: Date.now() }));
    } catch (e) {
      /* sin localStorage: se vuelve con el destino por defecto */
    }
  },

  /* Lee y valida la intención guardada, sin borrarla. Caducada, con fecha
     futura o manipulada -> null (y se borra). */
  peekIntent() {
    let raw = null;
    try {
      raw = localStorage.getItem(this.INTENT_KEY);
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
    if (!(age >= 0 && age <= this.INTENT_TTL_MS)) {
      this.clearIntent();
      return null;
    }
    const motivo = this.normalizeMotivo(data.motivo);
    const next = this.sanitizeNext(data.next);
    const plan = this.normalizePlan(data.plan);
    return motivo || next || plan ? { motivo, next, plan } : null;
  },

  /* Lee y BORRA la intención (un solo uso): se llama solo al llegar al
     destino final. Durante el alta (perfil, activación) se usa peekIntent(). */
  consumeIntent() {
    const intent = this.peekIntent();
    this.clearIntent();
    return intent;
  },

  clearIntent() {
    try {
      localStorage.removeItem(this.INTENT_KEY);
    } catch (e) {
      /* nada que borrar */
    }
  },

  /* Quita el plan de la intención (conservando motivo y next): la página de
     activación se muestra una sola vez por alta. */
  clearIntentPlan() {
    const intent = this.peekIntent();
    if (!intent || !intent.plan) return;
    if (!intent.motivo && !intent.next) {
      this.clearIntent();
      return;
    }
    try {
      const data = JSON.parse(localStorage.getItem(this.INTENT_KEY));
      data.plan = null;
      localStorage.setItem(this.INTENT_KEY, JSON.stringify(data));
    } catch (e) {
      this.clearIntent();
    }
  },

  /* Paso pendiente del alta profesional, o null si no queda ninguno:
     1) distribuidor -> perfil-distribuidor.html (nunca pasa por el alta profesional)
     2) sin perfil profesional -> inscripcion-profesional.html?paso=perfil
     3) plan que requiere activación -> activar-plan.html?plan=...
     "plan" solo decide qué pantalla se ve; nunca da permisos. */
  resolveOnboardingStep({ isSupplier, hasProfessionalProfile, plan }) {
    if (isSupplier) return { url: "perfil-distribuidor.html" };
    const safePlan = this.normalizePlan(plan);
    if (!hasProfessionalProfile) {
      return { url: `inscripcion-profesional.html?paso=perfil${safePlan ? `&plan=${safePlan}` : ""}` };
    }
    if (this.planRequiresActivation(safePlan)) return { url: `activar-plan.html?plan=${safePlan}` };
    return null;
  },

  /* Destino final (una vez completado el alta, si hacía falta), por prioridad:
     1) distribuidor -> perfil-distribuidor.html
     2) intención con motivo -> ruta del motivo (selección vacía -> seleccion.html con aviso)
     3) next válido (de la intención o de la URL)
     4) hay selección -> seleccion.html
     5) index.html */
  resolveDestination({ isSupplier, intent, urlNext, selectionCount }) {
    if (isSupplier) return { url: "perfil-distribuidor.html" };
    const motivo = intent ? this.normalizeMotivo(intent.motivo) : null;
    if (motivo) {
      if (!selectionCount) return { url: "seleccion.html", emptySelection: true };
      return { url: this.MOTIVOS.get(motivo).route };
    }
    const next = (intent && this.sanitizeNext(intent.next)) || this.sanitizeNext(urlNext);
    if (next) return { url: next };
    if (selectionCount > 0) return { url: "seleccion.html" };
    return { url: "index.html" };
  },

  /* Plan elegido al crear la cuenta, para navegar: primero la intención de
     este navegador; si no hay, el metadato requested_plan de la cuenta, y
     solo mientras aún no tenga perfil profesional (es decir, durante el
     alta). Nunca se usa para autorizar nada. */
  planForNavigation({ intent, session, hasProfessionalProfile }) {
    const fromIntent = intent ? this.normalizePlan(intent.plan) : null;
    if (fromIntent) return fromIntent;
    if (hasProfessionalProfile) return null;
    const metadata = session && session.user && session.user.user_metadata;
    return this.normalizePlan(metadata && metadata.requested_plan);
  },

  /* Rol y existencia de perfil profesional de la cuenta. Si la consulta del
     perfil falla, se trata como "sin perfil": la página de perfil vuelve a
     comprobarlo y continúa sola si el perfil ya existe. */
  async accountFacts(session) {
    const userId = session.user.id;
    const { data: account, error: roleError } = await supabaseClient
      .from("profiles").select("role").eq("id", userId).maybeSingle();
    const isSupplier = !roleError && !!account && account.role === "supplier";
    if (isSupplier) return { isSupplier: true, hasProfessionalProfile: false };
    const { data: profile, error: profileError } = await supabaseClient
      .from("professional_profiles").select("user_id").eq("user_id", userId).maybeSingle();
    return { isSupplier: false, hasProfessionalProfile: !profileError && !!profile };
  },

  /* Destino final, sin pasos de alta pendientes: une la selección anónima a
     la de la cuenta, CONSUME la intención y aplica resolveDestination(). */
  finalDestination({ isSupplier = false, urlNext = null, fallbackIntent = null } = {}) {
    if (typeof migrateAnonymousSelectionToAccount === "function") migrateAnonymousSelectionToAccount();
    const selectionCount = typeof getSelectionCount === "function" ? getSelectionCount() : 0;
    const intent = this.consumeIntent() || fallbackIntent;
    return this.resolveDestination({ isSupplier, intent, urlNext, selectionCount });
  },

  /* Única regla de "¿y ahora adónde?" tras iniciar sesión o completar un paso
     del alta: primero el paso pendiente (sin consumir la intención), si no,
     el destino final. explicitPlan: plan ya validado que llega en la URL del
     paso (sirve aunque la intención no exista en este navegador). */
  async resolveNext(session, { urlNext = null, fallbackIntent = null, explicitPlan = null } = {}) {
    const facts = await this.accountFacts(session);
    /* Un distribuidor nunca usa una intención profesional: se descarta para
       que no la herede otra cuenta que inicie sesión en este navegador. */
    if (facts.isSupplier) {
      this.clearIntent();
      return { url: "perfil-distribuidor.html" };
    }
    const intent = this.peekIntent() || fallbackIntent;
    const plan = this.normalizePlan(explicitPlan)
      || this.planForNavigation({ intent, session, hasProfessionalProfile: facts.hasProfessionalProfile });
    const step = this.resolveOnboardingStep({ isSupplier: facts.isSupplier, hasProfessionalProfile: facts.hasProfessionalProfile, plan });
    if (step) return step;
    return this.finalDestination({ isSupplier: facts.isSupplier, urlNext, fallbackIntent });
  }
};

/* ---------- helpers de autenticación, reutilizables en cualquier página ---------- */
const MobauAuth = {
  client: supabaseClient,

  /* Devuelve la sesión activa, o null si no hay ninguna. */
  async getSession() {
    const { data, error } = await supabaseClient.auth.getSession();
    if (error) {
      console.error("Error obteniendo la sesión:", error);
      return null;
    }
    return data.session;
  },

  /* Comprobación síncrona (sin await) de si hay una sesión guardada en
     este navegador — para código que necesita decidir de inmediato
     (p.ej. qué storage usar para mobau_seleccion, en seleccion-data.js)
     sin poder esperar una consulta async a Supabase. No protege
     páginas ni sustituye a getSession()/requireSession(): es solo una
     señal rápida. */
  hasStoredSession() {
    try {
      return !!localStorage.getItem(SUPABASE_SESSION_STORAGE_KEY);
    } catch (e) {
      return false;
    }
  },

  /* Envía el enlace mágico al correo indicado.
     extraData es opcional (por ejemplo { name: "Ana Rosario" })
     y queda disponible luego como raw_user_meta_data en Supabase.

     nextPage es opcional y SOLO puede ser uno de MAGIC_LINK_NEXT_PAGES
     (lista blanca fija arriba) — cualquier otro valor, incluido uno
     manipulado o ausente, cae siempre a "index.html". Nunca se arma
     la URL de redirección a partir de un valor externo sin pasar por
     este filtro, así que un valor arbitrario no puede convertirse en
     una redirección fuera del sitio.

     redirectTo se resuelve relativo a la página actual (siempre una
     página de la raíz del sitio), así que sirve igual en la raíz del
     dominio (Live Server, Cloudflare Pages) que bajo un subdirectorio
     como /mobau/, sin depender del nombre del host.

     options.createUser (por defecto true) — con false, Supabase NUNCA
     crea una cuenta: un email sin cuenta recibe un error y no se envía
     nada (acceso.html, solo para cuentas existentes). Con el valor por
     defecto la petición es exactamente la de siempre: Supabase crea la
     cuenta si no existe (verificar-correo.html, registro.html). */
  async sendMagicLink(email, extraData, nextPage, { createUser = true } = {}) {
    const target = MAGIC_LINK_NEXT_PAGES.includes(nextPage) ? nextPage : "index.html";
    const redirectTo = new URL(target, window.location.href).href;
    const options = {
      emailRedirectTo: redirectTo,
      data: extraData || undefined
    };
    if (createUser === false) options.shouldCreateUser = false;
    return supabaseClient.auth.signInWithOtp({ email, options });
  },

  /* Cierra la sesión y regresa a acceso.html. */
  async signOut() {
    const { error } = await supabaseClient.auth.signOut();
    if (error) console.error("Error cerrando sesión:", error);
    window.location.href = "acceso.html";
  },

  /* Devuelve la sesión, o null — sin redirigir a ningún sitio.
     Si la URL trae el fragmento del enlace mágico (#access_token=...),
     espera a que Supabase termine de procesarlo — vía el evento
     onAuthStateChange — antes de decidir si hay sesión o no. Sin esto,
     podría revisarse la sesión una fracción de segundo antes de que
     el enlace mágico terminara de guardarla. La usan requireSession()
     y acceso.html (que no puede redirigir si no hay sesión). */
  async getSessionFromRedirect() {
    if (window.location.hash && window.location.hash.includes("access_token")) {
      await new Promise((resolve) => {
        const { data: sub } = supabaseClient.auth.onAuthStateChange((event) => {
          if (event === "SIGNED_IN" || event === "INITIAL_SESSION") {
            sub.subscription.unsubscribe();
            resolve();
          }
        });
        setTimeout(resolve, 3000); // salvavidas: no bloquear para siempre si algo falla
      });
    }
    return this.getSession();
  },

  /* Protege una página: si no hay sesión, redirige a acceso.html (con la
     página actual como "next", solo si está en la lista blanca de
     MobauAccess) y detiene la ejecución del resto del script de esa
     página. Si hay sesión, la devuelve para que la página la use. */
  async requireSession() {
    const session = await this.getSessionFromRedirect();
    if (!session) {
      window.location.href = MobauAccess.accessUrlForCurrentPage();
      return null;
    }
    return session;
  }
};

/* Migra o limpia la selección temporal (mobau_seleccion) cuando cambia
   la sesión real de Supabase — las funciones viven en seleccion-data.js
   (puede no estar cargado en alguna página futura; por eso se
   comprueba typeof antes de llamarlas). Nunca toca localStorage.clear()
   ni sessionStorage.clear(): cada función de seleccion-data.js solo
   lee/escribe la clave "mobau_seleccion", nunca ningún otro dato.
   - SIGNED_IN / INITIAL_SESSION: une la selección anónima (sessionStorage)
     a la de la cuenta (localStorage), sin duplicar productos.
   - SIGNED_OUT: la selección temporal del usuario, ya anónimo de
     nuevo, queda vacía. */
supabaseClient.auth.onAuthStateChange((event) => {
  if ((event === "SIGNED_IN" || event === "INITIAL_SESSION") && typeof migrateAnonymousSelectionToAccount === "function") {
    migrateAnonymousSelectionToAccount();
  }
  if (event === "SIGNED_OUT" && typeof clearAnonymousSelection === "function") {
    clearAnonymousSelection();
  }
});
