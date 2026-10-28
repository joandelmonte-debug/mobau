/* ============================================================
   MOBAU — Importes de un proyecto (Punto 47)
   ------------------------------------------------------------
   Cálculo puro (sin DOM, sin red) del importe conocido de cada línea y de un conjunto de líneas, y de su cobertura.
   Una sola moneda: USD (los precios publicados son USD; no hay conversiones). El importe es PRELIMINAR: suma de
   los importes conocidos, nunca una cotización.

   Por línea (line.quantity = cantidad de la línea):
   - Producto principal: precio publicado × cantidad. Sin precio publicado -> la línea queda incompleta.
   - Componentes (solo en líneas configuradas, según el estado de la configuración): los «incluido» no suman; los
     «aparte» suman precio × cantidad por unidad (item.factor) × cantidad de la línea cuando la cantidad por unidad
     está determinada; «cantidad a calcular» o sin precio dejan la línea incompleta, sin inventar una multiplicación.
     item.factor ya incluye los componentes de nivel superior (anidados).
   - Configuración pendiente: la línea queda fuera del importe calculable (no se suma ni su principal).
   - Configuración que no se pudo comprobar (state null): solo cuenta el principal y la línea queda incompleta.
   - Sin acceso a precios: nada se calcula ni se muestra (estado "oculto").
   - Producto no disponible (archivado o ausente del catálogo): no suma; se cuenta aparte (nodisp).

   Estados de línea: "completa" | "parcial" (hay importe conocido y algo pendiente) | "sin" (nada conocido) |
   "pendiente" (configuración pendiente) | "nodisp" | "oculto".
   Entradas:
     priceOf(productId) -> { kind: "published", amount } | { kind: otro } (como getPriceInfo de script.js)
     pricesVisible -> false si priceAccessInfo() bloquea los precios.
   ============================================================ */
const MobauImportes = {
  round2(n) { return Math.round(n * 100) / 100; },

  /* line: { product_id, quantity, configuration }; state: entrada de project_line_states o null;
     ctx: { priceOf, pricesVisible, isAvailable } */
  line(line, state, ctx) {
    const result = { status: "completa", known: 0, issues: [] };
    if (!ctx.pricesVisible) { result.status = "oculto"; return result; }
    if (ctx.isAvailable && !ctx.isAvailable(line.product_id)) {
      result.status = "nodisp";
      result.issues.push("Producto no disponible actualmente");
      return result;
    }
    const quantity = Number(line.quantity);
    const qty = Number.isFinite(quantity) && quantity > 0 ? quantity : null;
    const known = state && (state.status === "completa" || state.status === "pendiente" || state.status === "no_requiere");
    if (state && state.status === "pendiente") {
      result.status = "pendiente";
      result.issues = Array.isArray(state.reasons) ? state.reasons.map(r => r.message).filter(Boolean) : [];
      return result;
    }
    const main = ctx.priceOf(line.product_id);
    if (main && main.kind === "published" && qty !== null) result.known += main.amount * qty;
    else result.issues.push(main && main.kind === "quote-required" ? "Producto principal bajo cotización"
      : qty === null ? "Falta la cantidad" : "Producto principal sin precio");

    if (line.configuration) {
      if (!known || state.status === "no_requiere") {
        result.issues.push("No se pudo comprobar la configuración con el catálogo actual");
      } else {
        (state.items || []).filter(i => i.kind === "componente" && i.supply !== "incluido").forEach(item => {
          const name = item.product_name || item.product_id;
          const factor = typeof item.factor === "number" && item.factor > 0 ? item.factor : null;
          if (factor === null || qty === null) { result.issues.push(`Cantidad por determinar: ${name}`); return; }
          const price = ctx.priceOf(item.product_id);
          if (price && price.kind === "published") result.known += price.amount * Math.round(factor * 1000) / 1000 * qty;
          else result.issues.push(`Sin precio: ${name}`);
        });
      }
    }
    result.known = this.round2(result.known);
    result.status = !result.issues.length ? "completa" : result.known > 0 ? "parcial" : "sin";
    return result;
  },

  /* results: salida de line() de cada línea. */
  aggregate(results) {
    const total = { n: results.length, known: 0, completa: 0, parcial: 0, sin: 0, pendiente: 0, nodisp: 0, oculto: 0 };
    results.forEach(r => {
      total[r.status] = (total[r.status] || 0) + 1;
      if (r.status !== "oculto" && r.status !== "pendiente" && r.status !== "nodisp") total.known += r.known;
    });
    total.known = this.round2(total.known);
    total.pend = total.parcial + total.sin + total.pendiente;
    return total;
  }
};

if (typeof module !== "undefined" && module.exports) module.exports = MobauImportes;
