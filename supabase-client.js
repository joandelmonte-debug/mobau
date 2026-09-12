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

     redirectTo lleva a index.html (no a cuenta.html) y calcula la
     ruta base a mano para GitHub Pages, que publica el sitio dentro
     de /mobau/ — en local (o cualquier otro host) basePath queda
     vacío y el enlace resuelve igual en la raíz. */
  async sendMagicLink(email, extraData) {
    const basePath = window.location.hostname === "joandelmonte-debug.github.io"
      ? "/mobau"
      : "";
    const redirectTo = `${window.location.origin}${basePath}/index.html`;
    return supabaseClient.auth.signInWithOtp({
      email,
      options: {
        emailRedirectTo: redirectTo,
        data: extraData || undefined
      }
    });
  },

  /* Cierra la sesión y regresa a login.html. */
  async signOut() {
    const { error } = await supabaseClient.auth.signOut();
    if (error) console.error("Error cerrando sesión:", error);
    window.location.href = "login.html";
  },

  /* Protege una página: si no hay sesión, redirige a login.html
     y detiene la ejecución del resto del script de esa página.
     Si hay sesión, la devuelve para que la página la use.

     Si la URL trae el fragmento del enlace mágico (#access_token=...),
     esperamos a que Supabase termine de procesarlo — vía el evento
     onAuthStateChange — antes de decidir si hay sesión o no. Sin esto,
     podría revisarse la sesión una fracción de segundo antes de que
     el enlace mágico terminara de guardarla. */
  async requireSession() {
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

    const session = await this.getSession();
    if (!session) {
      window.location.href = "login.html";
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
