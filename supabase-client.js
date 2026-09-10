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

/* Fijamos un único origen para desarrollo local. localhost y 127.0.0.1 son,
   para el navegador, dos sitios distintos con almacenamiento de sesión
   separado — por eso hay que entrar SIEMPRE por esta misma URL, tanto al
   pedir el enlace mágico como al abrirlo. Si más adelante despliegas a un
   dominio real, este valor es lo único que hay que actualizar aquí. */
const SITE_URL = "http://127.0.0.1:5500";

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

  /* Envía el enlace mágico al correo indicado.
     extraData es opcional (por ejemplo { name: "Ana Rosario" })
     y queda disponible luego como raw_user_meta_data en Supabase. */
  async sendMagicLink(email, extraData) {
    const redirectTo = SITE_URL + "/cuenta.html";
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
