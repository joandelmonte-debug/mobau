/* Mesa B (solo pruebas locales). Igual que sw-paginas-47.js: sirve las páginas reales del repositorio bajo
   supabase/tests/mesa-b/pagina/, cambiando solo la etiqueta de supabase-js por el cliente simulado de CC1 y añadiendo,
   tras supabase-client.js, mock-areas-mesa-b.js (casos del ensayo 47 más los de la mesa). Fuera de un origen local
   no intercepta nada. */
const LOCAL = ["localhost", "127.0.0.1", "[::1]"].includes(self.location.hostname);
const ROOT = new URL("../../../", self.location).href;
const BASE = new URL("pagina/", self.location).href;
const CDN = '<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>';
const CLIENT = '<script src="supabase-client.js"></script>';

self.addEventListener("install", () => { if (LOCAL) self.skipWaiting(); else self.registration.unregister(); });
self.addEventListener("activate", event => event.waitUntil(self.clients.claim()));
self.addEventListener("fetch", event => {
  const url = new URL(event.request.url);
  if (!LOCAL || !url.href.startsWith(BASE)) return;
  const file = url.pathname.slice(new URL(BASE).pathname.length);
  event.respondWith((async () => {
    const res = await fetch(ROOT + file, { cache: "no-store" });
    if (!file.endsWith(".html") || !res.ok) return res;
    const html = await res.text();
    if (html.split(CDN).length !== 2 || html.split(CLIENT).length !== 2){
      return new Response(`Mesa B: ${file} no tiene las etiquetas esperadas`, { status: 500 });
    }
    /* ?solo43: solo el cliente simulado de la prueba 43 (sus datos), para recorrer a mano el caso 114. */
    const solo43 = url.searchParams.has("solo43");
    const out = html.replace(CDN, '<script src="supabase/tests/43/interfaz/mock-supabase-cc1.js"></script>')
      .replace(CLIENT, solo43 ? CLIENT : CLIENT + '\n<script src="supabase/tests/mesa-b/mock-areas-mesa-b.js"></script>');
    return new Response(out, { headers: { "Content-Type": "text/html; charset=utf-8" } });
  })());
});
