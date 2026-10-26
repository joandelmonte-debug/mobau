/* ============================================================
   MOBAU — Componentes y accesorios en propuestas (punto 46, bloque 4)
   ------------------------------------------------------------
   Compartido por el formulario de propuesta del distribuidor
   (distribuidor-propuestas.html), por Mis productos y por la consola de
   moderación. Mobau organiza lo que el distribuidor declara; no certifica
   compatibilidad técnica.

   Dos partes, sin dependencias entre sí:
   1) LÓGICA PURA (sin DOM): modelo del editor ⇄ manifiesto
      (product_proposals.proposed_components), ⇄ estructura actual del producto
      (product_component_groups / product_component_options), comparación,
      validación y resumen. Es el espejo de lo que valida el servidor
      (46-03, trigger 36); el servidor decide, aquí solo se adelantan los
      mensajes.
   2) EDITOR (DOM): render(container, state, ctx, hooks). Todo el texto del
      usuario se pinta con textContent / value, nunca con innerHTML.

   Manifiesto (46-03):
     null                    → sin cambios de componentes;
     {"catalog_role": …}     → solo cambia el uso en el catálogo;
     {"groups": [...]}       → lista COMPLETA de grupos (lo que falte se retira);
     ambas claves a la vez.
   Claves estables: «code» del grupo y de la opción. Una opción de componente
   apunta a {"product_id"} (artículo propio) o {"proposal_id"} (alta propia de un
   componente nuevo, aún sin aprobar).
   ============================================================ */
const MobauComponentes = (() => {
  const ROLES = [
    ["principal", "Producto principal"],
    ["componente", "Solo componente o accesorio"],
    ["ambos", "Principal y también componente"]
  ];
  const ROLE_LABELS = Object.fromEntries(ROLES);
  const REQUIREMENTS = [["necesario", "Necesario (hay que elegir)"], ["opcional", "Opcional"]];
  const CHOICES = [["una", "Elegir una opción"], ["varias", "Se pueden elegir varias"]];
  const KINDS = [["componente", "Componente o accesorio"], ["ajuste", "Ajuste del propio artículo"]];
  const SUPPLIES = [["incluido", "Incluido con el artículo"], ["aparte", "Se solicita aparte"]];
  const MODES = [["fija", "Cantidad fija por unidad"], ["a_calcular", "A calcular por el distribuidor"]];
  const LIMITS = { groups: 30, options: 40, attributes: 8, label: 80, code: 40, attrLabel: 60, attrValue: 120, qtyMax: 9999999.999 };

  /* ---------- utilidades ---------- */
  const text = (v) => (typeof v === "string" ? v.trim().replace(/\s+/g, " ") : "");
  const lower = (v) => text(v).toLowerCase();

  function slug(value, fallback){
    const base = text(value).normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase()
      .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, LIMITS.code).replace(/-+$/g, "");
    return base || fallback;
  }

  /* Clave estable y única (sin distinguir mayúsculas) dentro de un conjunto. */
  function uniqueCode(base, used){
    const taken = new Set(used.map(lower));
    let code = base;
    let n = 2;
    while (taken.has(code.toLowerCase())){
      const suffix = `-${n++}`;
      code = base.slice(0, LIMITS.code - suffix.length) + suffix;
    }
    return code;
  }

  let seq = 0;
  const newKey = () => ++seq;

  const emptyOption = () => ({ _k: newKey(), code: "", kind: "componente", component: null, finish_code: "", setting_label: "", supply: "incluido", quantity: "1", quantity_mode: "fija", attributes: [] });
  const emptyGroup = () => ({ _k: newKey(), code: "", label: "", requirement: "opcional", choice: "una", dependsOn: null, options: [] });
  const emptyModel = () => ({ role: "principal", groups: [] });

  /* ---------- estructura actual del producto → modelo ---------- */
  /* rows: { groups: [product_component_groups activos], options: [product_component_options activas] }.
     Las condiciones llegan por id de opción; aquí pasan a {group, option} por claves. */
  function fromStructure(rows, role){
    const groups = (rows && rows.groups || []).filter(g => g.status === undefined || g.status === "activo")
      .slice().sort((a, b) => (a.sort_order - b.sort_order) || String(a.code).localeCompare(String(b.code)));
    const options = (rows && rows.options || []).filter(o => o.status === undefined || o.status === "activo");
    const optById = new Map(options.map(o => [o.id, o]));
    const groupById = new Map(groups.map(g => [g.id, g]));
    return {
      role: role || "principal",
      groups: groups.map(g => {
        const dep = g.depends_on_option_id ? optById.get(g.depends_on_option_id) : null;
        const depGroup = dep ? groupById.get(dep.group_id) : null;
        return {
          _k: newKey(), code: g.code, label: g.label, requirement: g.requirement, choice: g.choice,
          dependsOn: dep && depGroup ? { group: depGroup.code, option: dep.code } : null,
          options: options.filter(o => o.group_id === g.id)
            .sort((a, b) => (a.sort_order - b.sort_order) || String(a.code).localeCompare(String(b.code)))
            .map(o => ({
              _k: newKey(), code: o.code, kind: o.kind,
              component: o.component_product_id ? { product_id: o.component_product_id } : null,
              finish_code: o.component_finish_code || "", setting_label: o.setting_label || "",
              supply: o.supply || (o.kind === "componente" ? "incluido" : ""),
              quantity: o.quantity === null || o.quantity === undefined ? "" : String(Number(o.quantity)),
              quantity_mode: o.quantity_mode || (o.kind === "componente" ? "fija" : ""),
              attributes: Array.isArray(o.attributes) ? o.attributes.map(a => ({ label: a.label || "", value: a.value || "" })) : []
            }))
        };
      })
    };
  }

  /* ---------- manifiesto ⇄ modelo ---------- */
  function fromManifest(manifest, fallbackRole){
    const m = manifest && typeof manifest === "object" ? manifest : {};
    return {
      role: m.catalog_role || fallbackRole || "principal",
      groups: (Array.isArray(m.groups) ? m.groups : []).map(g => ({
        _k: newKey(), code: g.code || "", label: g.label || "", requirement: g.requirement || "opcional", choice: g.choice || "una",
        dependsOn: g.depends_on && typeof g.depends_on === "object" ? { group: g.depends_on.group, option: g.depends_on.option } : null,
        options: (Array.isArray(g.options) ? g.options : []).map(o => ({
          _k: newKey(), code: o.code || "", kind: o.kind || "componente",
          component: o.component && typeof o.component === "object" ? { ...o.component } : null,
          finish_code: o.finish_code || "", setting_label: o.setting_label || "",
          supply: o.supply || "", quantity: o.quantity === undefined || o.quantity === null ? "" : String(o.quantity),
          quantity_mode: o.quantity_mode || "", attributes: Array.isArray(o.attributes) ? o.attributes.map(a => ({ label: a.label || "", value: a.value || "" })) : []
        }))
      }))
    };
  }

  /* Claves estables: se asignan una sola vez, cuando el elemento ya tiene nombre (al guardar o al
     usarlo como condición), y no cambian aunque después se edite el nombre. */
  function ensureGroupCode(model, g){
    if (!g.code) g.code = uniqueCode(slug(g.label, "grupo"), model.groups.map(x => x.code).filter(Boolean));
    return g.code;
  }
  function ensureOptionCode(g, o){
    if (!o.code){
      const base = o.kind === "ajuste" ? slug(o.setting_label, "ajuste") : slug(optionName(o), "opcion");
      o.code = uniqueCode(base, g.options.map(x => x.code).filter(Boolean));
    }
    return o.code;
  }

  /* Asigna las claves que falten y devuelve el manifiesto.
     includeRole: añade catalog_role (alta de producto o cambio de uso). */
  function toManifest(model, { includeRole = false } = {}){
    model.groups.forEach(g => {
      ensureGroupCode(model, g);
      g.options.forEach(o => ensureOptionCode(g, o));
    });
    const out = {};
    if (includeRole) out.catalog_role = model.role;
    out.groups = model.groups.map(g => {
      const group = { code: g.code, label: text(g.label), requirement: g.requirement, choice: g.choice };
      if (g.dependsOn && g.dependsOn.group && g.dependsOn.option) group.depends_on = { group: g.dependsOn.group, option: g.dependsOn.option };
      group.options = g.options.map(o => {
        const opt = { code: o.code, kind: o.kind };
        if (o.kind === "componente"){
          if (o.component) opt.component = { ...o.component };
          if (o.finish_code) opt.finish_code = o.finish_code;
          if (o.supply) opt.supply = o.supply;
          if (o.quantity_mode) opt.quantity_mode = o.quantity_mode;
          if (o.quantity_mode === "fija" && text(o.quantity) !== "") opt.quantity = Number(text(o.quantity).replace(",", "."));
        } else {
          opt.setting_label = text(o.setting_label);
        }
        const attrs = o.attributes.map(a => ({ label: text(a.label), value: text(a.value) })).filter(a => a.label || a.value);
        if (attrs.length) opt.attributes = attrs;
        return opt;
      });
      return group;
    });
    return out;
  }

  /* Forma canónica para comparar (orden de grupos y opciones por clave, sin importar el orden de edición). */
  function canonical(manifest){
    const m = manifest || {};
    const sortBy = (arr, key) => arr.slice().sort((a, b) => String(a[key]).toLowerCase().localeCompare(String(b[key]).toLowerCase()));
    const num = (v) => (v === undefined || v === null ? null : Number(v));
    return JSON.stringify({
      groups: sortBy(m.groups || [], "code").map(g => ({
        code: g.code, label: g.label, requirement: g.requirement, choice: g.choice,
        depends_on: g.depends_on ? { group: g.depends_on.group, option: g.depends_on.option } : null,
        options: sortBy(g.options || [], "code").map(o => ({
          code: o.code, kind: o.kind,
          component: o.component ? (o.component.product_id ? { product_id: o.component.product_id } : { proposal_id: o.component.proposal_id }) : null,
          finish_code: o.finish_code || null, setting_label: o.setting_label || null, supply: o.supply || null,
          quantity: num(o.quantity), quantity_mode: o.quantity_mode || null,
          attributes: (o.attributes || []).map(a => ({ label: a.label, value: a.value }))
        }))
      }))
    });
  }

  /* Lo que se guarda en proposed_components. null = sin cambios de componentes.
     baseline: { role, manifest } del producto actual (cambio) o null (producto nuevo). */
  function buildProposed(model, baseline, ctx){
    if (ctx) nameCtx = ctx;
    const manifest = toManifest(model);
    if (!baseline){
      const isDefault = model.role === "principal" && manifest.groups.length === 0;
      if (isDefault) return null;
      const out = { catalog_role: model.role };
      if (manifest.groups.length) out.groups = manifest.groups;
      return out;
    }
    const roleChanged = model.role !== baseline.role;
    const groupsChanged = canonical(manifest) !== canonical(baseline.manifest);
    if (!roleChanged && !groupsChanged) return null;
    const out = {};
    if (roleChanged) out.catalog_role = model.role;
    if (groupsChanged) out.groups = manifest.groups;
    return out;
  }

  /* ---------- nombres para mostrar ---------- */
  function componentRef(option, ctx){
    const c = option.component;
    if (!c) return null;
    if (c.product_id){ const p = (ctx.products || []).find(x => x.id === c.product_id); return p ? p.name : c.product_id; }
    if (c.proposal_id){ const p = (ctx.proposals || []).find(x => x.id === c.proposal_id); return p ? `${p.name || "Componente nuevo"} (nuevo, pendiente de aprobación)` : "Componente nuevo"; }
    return null;
  }
  let nameCtx = { products: [], proposals: [] };
  function optionName(option){
    if (option.kind === "ajuste") return option.setting_label;
    /* Nombre llano, sin la nota «(nuevo, pendiente de aprobación)»: de él sale la clave de la opción. */
    const c = option.component;
    if (c && c.proposal_id){
      const p = (nameCtx.proposals || []).find(x => x.id === c.proposal_id);
      return (p && p.name) || "componente";
    }
    return componentRef(option, nameCtx) || "";
  }

  /* ---------- identidad de una opción y diferencias ---------- */
  /* Misma clave = mismo artículo (46-03): cambiar el artículo o el tipo de una opción que ya existe exige una
     opción NUEVA (clave nueva); la antigua se retira al no figurar en la lista. */
  const identityOf = (o) => `${o.kind}:${o.component ? (o.component.product_id || o.component.proposal_id || "") : ""}`;
  function baselineIdentity(baseline, groupCode, optionCode){
    const g = baseline && (baseline.groups || []).find(x => x.code === groupCode);
    const o = g && (g.options || []).find(x => x.code === optionCode);
    return o ? `${o.kind}:${o.component ? (o.component.product_id || o.component.proposal_id || "") : ""}` : null;
  }

  /* Texto de una opción. names: { product(id) → nombre, proposal(id) → { name, status } }. */
  function describeOption(o, names){
    const n = names || {};
    const parts = [];
    if (o.kind === "ajuste"){
      parts.push(`Ajuste «${text(o.setting_label)}»`);
    } else {
      const c = o.component || {};
      if (c.product_id){
        parts.push(`Componente «${(n.product && n.product(c.product_id)) || c.product_id}»`);
      } else if (c.proposal_id){
        const pr = n.proposal && n.proposal(c.proposal_id);
        parts.push(`Componente nuevo «${(pr && pr.name) || "sin nombre"}»${pr && pr.status ? ` (propuesta ${pr.status === "approved" ? "aprobada" : "sin aprobar"})` : ""}`);
      } else {
        parts.push("Componente sin artículo");
      }
      if (o.finish_code) parts.push(`acabado ${o.finish_code}`);
      parts.push(o.supply === "aparte" ? "se solicita aparte" : "incluido");
      parts.push(o.quantity_mode === "a_calcular" ? "cantidad a calcular" : `${o.quantity === undefined || o.quantity === null ? "?" : o.quantity} por unidad`);
    }
    if (Array.isArray(o.attributes) && o.attributes.length) parts.push(o.attributes.map(a => `${a.label}: ${a.value}`).join("; "));
    return parts.join(" · ");
  }

  /* Nombre legible de una opción para condiciones: el ajuste o el artículo, con su suministro si es un componente
     (dos opciones del mismo artículo se distinguen por él), nunca la clave técnica salvo que no haya otra cosa. */
  function plainOptionLabel(o, names){
    if (!o) return null;
    if (o.kind === "ajuste") return text(o.setting_label) || null;
    const c = o.component || {};
    const n = names || {};
    let name = null;
    if (c.product_id) name = (n.product && n.product(c.product_id)) || null;
    else if (c.proposal_id){ const pr = n.proposal && n.proposal(c.proposal_id); name = (pr && pr.name) || null; }
    return name ? `${name} (${o.supply === "aparte" ? "se solicita aparte" : "incluido"})` : null;
  }
  function describeGroupRules(g, groups, names){
    const bits = [g.requirement === "necesario" ? "necesario" : "opcional", g.choice === "varias" ? "varias opciones" : "una opción"];
    if (g.depends_on){
      const dg = (groups || []).find(x => x.code === g.depends_on.group);
      const dopt = dg && (dg.options || []).find(x => x.code === g.depends_on.option);
      bits.push(`solo si se elige «${dg ? text(dg.label) : g.depends_on.group}» → «${(dopt && plainOptionLabel(dopt, names)) || (dopt ? (dopt.setting_label || dopt.code) : g.depends_on.option)}»`);
    }
    return bits.join(", ");
  }

  /* Compara dos manifiestos por clave de grupo. status: nuevo | cambia | igual | retirado. */
  function diff(baseManifest, proposedManifest){
    const base = new Map(((baseManifest && baseManifest.groups) || []).map(g => [g.code, g]));
    const proposed = (proposedManifest && proposedManifest.groups) || [];
    const one = (g) => canonical({ groups: [g] });
    const out = proposed.map(g => {
      const b = base.get(g.code);
      return { code: g.code, label: g.label, status: !b ? "nuevo" : (one(b) === one(g) ? "igual" : "cambia"), group: g, before: b || null };
    });
    const kept = new Set(proposed.map(g => g.code));
    base.forEach((g, code) => { if (!kept.has(code)) out.push({ code, label: g.label, status: "retirado", group: null, before: g }); });
    return out;
  }

  /* ---------- validación (espejo del servidor) ---------- */
  function validate(model, ctx, { submit = false } = {}){
    nameCtx = ctx || nameCtx;
    const groups = model.groups;
    if (groups.length > LIMITS.groups) return `Máximo ${LIMITS.groups} grupos de componentes.`;
    const gcodes = new Set();
    for (const g of groups){
      const label = text(g.label);
      if (label.length < 1 || label.length > LIMITS.label) return "Revisa el nombre (1–80 caracteres) de cada grupo de componentes.";
      if (g.code){ if (gcodes.has(g.code.toLowerCase())) return "Hay dos grupos de componentes con la misma clave."; gcodes.add(g.code.toLowerCase()); }
      if (!["necesario", "opcional"].includes(g.requirement) || !["una", "varias"].includes(g.choice)) return `El grupo «${label}» no es válido.`;
      if (g.options.length > LIMITS.options) return `El grupo «${label}» tiene demasiadas opciones (máximo ${LIMITS.options}).`;
      if (submit && g.requirement === "necesario" && g.options.length === 0) return `El grupo necesario «${label}» no tiene opciones.`;
      const ocodes = new Set();
      for (const o of g.options){
        if (o.code){ if (ocodes.has(o.code.toLowerCase())) return `El grupo «${label}» tiene dos opciones con la misma clave.`; ocodes.add(o.code.toLowerCase()); }
        if (o.kind === "componente"){
          if (!o.component) return `Indica el artículo de cada opción de componente del grupo «${label}».`;
          if (o.component.product_id && ctx && ctx.selfProductId && o.component.product_id === ctx.selfProductId) return `Un producto no puede ser componente de sí mismo (grupo «${label}»).`;
          if (!["incluido", "aparte"].includes(o.supply)) return `Indica si cada componente del grupo «${label}» va incluido o se solicita aparte.`;
          if (!["fija", "a_calcular"].includes(o.quantity_mode)) return `Indica la cantidad (fija o a calcular) de cada componente del grupo «${label}».`;
          if (o.quantity_mode === "fija"){
            const raw = text(o.quantity).replace(",", ".");
            const n = Number(raw);
            if (raw === "" || !Number.isFinite(n) || n <= 0 || n > LIMITS.qtyMax || Math.round(n * 1000) / 1000 !== n){
              return "La cantidad por unidad de cada componente debe ser mayor que 0 (hasta 3 decimales).";
            }
          }
        } else if (o.kind === "ajuste"){
          const s = text(o.setting_label);
          if (s.length < 1 || s.length > LIMITS.label) return `Indica el nombre (1–80 caracteres) de cada ajuste del grupo «${label}».`;
        } else {
          return `Alguna opción del grupo «${label}» no es válida.`;
        }
        if (o.attributes.length > LIMITS.attributes) return `Las características de una opción no son válidas (máximo ${LIMITS.attributes}).`;
        for (const a of o.attributes){
          const l = text(a.label), v = text(a.value);
          if (!l && !v) continue;
          if (!l || !v || l.length > LIMITS.attrLabel || v.length > LIMITS.attrValue) return "Cada característica necesita un nombre (hasta 60 caracteres) y un valor (hasta 120).";
        }
      }
    }
    /* Condiciones: una opción de OTRO grupo del mismo manifiesto; sin círculos. */
    const byCode = new Map(groups.filter(g => g.code).map(g => [g.code, g]));
    for (const g of groups){
      if (!g.dependsOn) continue;
      const target = byCode.get(g.dependsOn.group);
      if (!target || target === g || !target.options.some(o => o.code === g.dependsOn.option)){
        return `La condición del grupo «${text(g.label)}» no es válida: elige una opción de otro grupo.`;
      }
      let cur = g, steps = 0;
      while (cur && cur.dependsOn && steps++ <= groups.length){
        cur = byCode.get(cur.dependsOn.group);
        if (cur === g) return "Las condiciones de los grupos forman un círculo.";
      }
    }
    return null;
  }

  /* ---------- resumen en texto (Mis productos, moderación) ---------- */
  function summary(manifest, role){
    const lines = [];
    if (manifest && manifest.catalog_role) lines.push(`Uso en el catálogo: ${ROLE_LABELS[manifest.catalog_role] || manifest.catalog_role}`);
    else if (role) lines.push(`Uso en el catálogo: ${ROLE_LABELS[role] || role}`);
    const groups = manifest && Array.isArray(manifest.groups) ? manifest.groups : null;
    if (groups){
      if (!groups.length) lines.push("Grupos de componentes: se retiran todos");
      groups.forEach(g => {
        const n = (g.options || []).length;
        lines.push(`${text(g.label)} (${g.requirement === "necesario" ? "necesario" : "opcional"}, ${g.choice === "varias" ? "varias" : "una"}): ${n} ${n === 1 ? "opción" : "opciones"}${g.depends_on ? ", con condición" : ""}`);
      });
    }
    return lines;
  }

  /* Lee la estructura actual de un producto (grupos y opciones) con el cliente de Supabase de la página.
     La política de lectura decide qué ve cada cuenta (el distribuidor lee la suya; Mobau con aal2, todo). */
  async function loadStructure(client, productId){
    const { data: groups, error: groupsError } = await client.from("product_component_groups")
      .select("id, product_id, code, label, requirement, choice, depends_on_option_id, status, sort_order").eq("product_id", productId);
    if (groupsError) throw groupsError;
    let options = [];
    if (groups.length){
      const { data, error } = await client.from("product_component_options")
        .select("id, group_id, code, kind, component_product_id, component_finish_code, setting_label, supply, quantity, quantity_mode, attributes, status, sort_order")
        .in("group_id", groups.map(g => g.id));
      if (error) throw error;
      options = data;
    }
    return { groups, options };
  }

  /* ============================================================
     EDITOR (DOM)
     ============================================================ */
  const STYLE_ID = "mobau-componentes-estilos";
  function ensureStyles(){
    if (typeof document === "undefined" || document.getElementById(STYLE_ID)) return;
    const css = `
      .pc-root{ display:grid; gap:14px; }
      .pc-help{ margin:0; font-size:13.5px; color: var(--ink-soft); }
      .pc-group{ border:1px solid var(--line); border-radius: var(--radius); background:#fff; padding:14px; display:grid; gap:12px; }
      .pc-group-head{ display:grid; grid-template-columns: 1fr auto; gap:10px; align-items:end; }
      .pc-grid{ display:grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap:10px; }
      .pc-field{ display:grid; gap:4px; font-size:12.5px; color: var(--ink-soft); }
      .pc-field input, .pc-field select{ width:100%; font-size:14px; }
      .pc-option{ border:1px solid var(--line); border-radius: var(--radius); background: var(--surface); padding:12px; display:grid; gap:10px; }
      .pc-option-head{ display:flex; justify-content:space-between; gap:10px; align-items:center; font-size:13px; font-weight:600; color: var(--ink); }
      .pc-attrs{ display:grid; gap:6px; }
      .pc-attr{ display:grid; grid-template-columns: 1fr 1.4fr auto; gap:8px; align-items:center; }
      .pc-actions{ display:flex; flex-wrap:wrap; gap:8px; }
      .pc-empty{ margin:0; font-size:13.5px; color: var(--ink-soft); }
      .pc-note{ margin:0; font-size:12.5px; color: var(--ink-soft); }
      .pc-danger{ color: var(--danger); }
      @media (max-width: 640px){ .pc-group-head{ grid-template-columns: 1fr; } .pc-attr{ grid-template-columns: 1fr; } }
    `;
    const style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = css;
    document.head.appendChild(style);
  }

  const el = (tag, cls, content) => {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (content !== undefined && content !== null) node.textContent = content;
    return node;
  };
  function button(label, handler, cls){
    const b = el("button", `btn btn-outline btn-sm${cls ? " " + cls : ""}`, label);
    b.type = "button";
    b.addEventListener("click", handler);
    return b;
  }
  function field(label, control){
    const wrap = el("label", "pc-field");
    wrap.append(el("span", "", label), control);
    return wrap;
  }
  function select(options, value, onChange){
    const s = el("select");
    options.forEach(([v, l]) => { const o = el("option", "", l); o.value = v; s.append(o); });
    s.value = value;
    s.addEventListener("change", () => onChange(s.value));
    return s;
  }
  function input(value, onInput, attrs){
    const i = el("input");
    i.type = "text";
    i.value = value;
    Object.entries(attrs || {}).forEach(([k, v]) => i.setAttribute(k, v));
    i.addEventListener("input", () => onInput(i.value));
    return i;
  }

  /* ctx: { products:[{id,name,catalog_role}], finishesByProduct: Map|obj, proposals:[{id,name}], selfProductId }
     hooks: { onChange(), onCreateComponent(group, option) } */
  function render(container, model, ctx, hooks){
    ensureStyles();
    nameCtx = ctx || nameCtx;
    const h = hooks || {};
    const changed = () => { if (h.onChange) h.onChange(); };
    const redraw = () => { render(container, model, ctx, hooks); changed(); };
    /* Cambiar el artículo o el tipo de una opción que ya existía la convierte en una opción nueva. */
    const rekey = (g, o, apply) => {
      const before = o.code ? baselineIdentity(ctx && ctx.baseline, g.code, o.code) : null;
      const oldCode = o.code;
      apply();
      if (before !== null && identityOf(o) !== before){
        model.groups.forEach(og => { if (og.dependsOn && og.dependsOn.group === g.code && og.dependsOn.option === oldCode) og.dependsOn = null; });
        o.code = "";
      }
    };
    const finishesOf = (productId) => {
      const f = ctx && ctx.finishesByProduct;
      const list = f instanceof Map ? f.get(productId) : (f ? f[productId] : null);
      return Array.isArray(list) ? list : [];
    };
    const componentChoices = [["", "Elige un artículo…"]]
      .concat((ctx.products || []).filter(p => (p.catalog_role === "componente" || p.catalog_role === "ambos") && p.id !== ctx.selfProductId)
        .map(p => [`p:${p.id}`, p.name]))
      .concat((ctx.proposals || []).map(p => [`n:${p.id}`, `${p.name || "Componente nuevo"} (nuevo, pendiente de aprobación)`]));

    container.replaceChildren();
    const root = el("div", "pc-root");

    if (!model.groups.length){
      root.append(el("p", "pc-empty", "Este producto no tiene grupos de componentes. Añade un grupo para ofrecer accesorios, piezas o ajustes que el cliente pueda elegir."));
    }

    model.groups.forEach((g, gi) => {
      const gbox = el("div", "pc-group");
      gbox.setAttribute("role", "group");
      gbox.setAttribute("aria-label", text(g.label) || `Grupo ${gi + 1}`);

      const head = el("div", "pc-group-head");
      head.append(
        field("Nombre del grupo (lo que verá el cliente)", input(g.label, (v) => { g.label = v; changed(); }, { maxlength: String(LIMITS.label), placeholder: "Ej. Fuente de luz, Lente, Acabado del soporte" })),
        button("Quitar grupo", () => {
          model.groups.forEach(o => { if (o.dependsOn && o.dependsOn.group === g.code) o.dependsOn = null; });
          model.groups.splice(gi, 1);
          redraw();
        }, "pc-danger")
      );
      gbox.append(head);

      const rules = el("div", "pc-grid");
      rules.append(
        field("¿Hay que elegir?", select(REQUIREMENTS, g.requirement, (v) => { g.requirement = v; changed(); })),
        field("Cuántas opciones", select(CHOICES, g.choice, (v) => { g.choice = v; changed(); }))
      );
      /* Condición: solo opciones con nombre de otros grupos con nombre; la clave de destino se fija al elegirla. */
      const condChoices = [["", "Siempre se muestra"]];
      model.groups.forEach(og => {
        if (og === g || !text(og.label)) return;
        og.options.forEach(oo => { const n = optionName(oo); if (n) condChoices.push([`${og._k}|${oo._k}`, `Solo si se elige «${text(og.label)}» → «${n}»`]); });
      });
      let condValue = "";
      if (g.dependsOn){
        const og = model.groups.find(x => x.code === g.dependsOn.group);
        const oo = og && og.options.find(x => x.code === g.dependsOn.option);
        condValue = og && oo ? `${og._k}|${oo._k}` : "__roto__";
        if (condValue === "__roto__") condChoices.push([condValue, "Condición que ya no existe (elige otra)"]);
        else if (!condChoices.some(([v]) => v === condValue)) condChoices.push([condValue, `Solo si se elige «${og.code}» → «${oo.code}»`]);
      }
      rules.append(field("Condición para mostrarlo", select(condChoices, condValue, (v) => {
        if (!v || v === "__roto__"){ g.dependsOn = null; changed(); return; }
        const [gk, ok] = v.split("|");
        const og = model.groups.find(x => String(x._k) === gk);
        const oo = og && og.options.find(x => String(x._k) === ok);
        if (!og || !oo){ g.dependsOn = null; changed(); return; }
        ensureGroupCode(model, og);
        ensureOptionCode(og, oo);
        g.dependsOn = { group: og.code, option: oo.code };
        changed();
      })));
      gbox.append(rules);

      if (!g.options.length) gbox.append(el("p", "pc-empty", "Todavía no hay opciones en este grupo."));

      g.options.forEach((o, oi) => {
        const obox = el("div", "pc-option");
        const ohead = el("div", "pc-option-head");
        ohead.append(el("span", "", `Opción ${oi + 1}`), button("Quitar opción", () => {
          model.groups.forEach(og => { if (og.dependsOn && og.dependsOn.group === g.code && og.dependsOn.option === o.code) og.dependsOn = null; });
          g.options.splice(oi, 1);
          redraw();
        }, "pc-danger"));
        obox.append(ohead);

        const row = el("div", "pc-grid");
        row.append(field("Tipo de opción", select(KINDS, o.kind, (v) => {
          rekey(g, o, () => { o.kind = v; });
          if (v === "componente"){ o.supply = o.supply || "incluido"; o.quantity_mode = o.quantity_mode || "fija"; o.quantity = o.quantity || "1"; }
          redraw();
        })));
        if (o.kind === "componente"){
          const current = o.component ? (o.component.product_id ? `p:${o.component.product_id}` : `n:${o.component.proposal_id}`) : "";
          const choices = componentChoices.slice();
          if (current && !choices.some(([v]) => v === current)) choices.push([current, componentRef(o, ctx) || "Artículo que ya no está disponible (elige otro)"]);
          row.append(field("Artículo (de tu empresa)", select(choices, current, (v) => {
            rekey(g, o, () => {
              o.finish_code = "";
              if (!v) o.component = null;
              else if (v.startsWith("p:")) o.component = { product_id: v.slice(2) };
              else o.component = { proposal_id: v.slice(2) };
            });
            redraw();
          })));
          const fins = o.component && o.component.product_id ? finishesOf(o.component.product_id) : [];
          if (fins.length){
            row.append(field("Acabado (opcional)", select([["", "Cualquiera / no se especifica"]].concat(fins.map(f => [f.code, f.name || f.code])), o.finish_code, (v) => { o.finish_code = v; changed(); })));
          }
          row.append(
            field("Suministro", select(SUPPLIES, o.supply, (v) => { o.supply = v; changed(); })),
            field("Cantidad", select(MODES, o.quantity_mode, (v) => { o.quantity_mode = v; redraw(); }))
          );
          if (o.quantity_mode === "fija"){
            row.append(field("Cantidad por unidad del artículo", input(o.quantity, (v) => { o.quantity = v; changed(); }, { inputmode: "decimal", placeholder: "1" })));
          }
        } else {
          row.append(field("Nombre del ajuste", input(o.setting_label, (v) => { o.setting_label = v; changed(); }, { maxlength: String(LIMITS.label), placeholder: "Ej. Luz cálida, Altura 75 cm" })));
        }
        obox.append(row);

        const attrs = el("div", "pc-attrs");
        o.attributes.forEach((a, ai) => {
          const arow = el("div", "pc-attr");
          arow.append(
            input(a.label, (v) => { a.label = v; changed(); }, { maxlength: String(LIMITS.attrLabel), placeholder: "Característica (Ej. Potencia)", "aria-label": "Nombre de la característica" }),
            input(a.value, (v) => { a.value = v; changed(); }, { maxlength: String(LIMITS.attrValue), placeholder: "Valor (Ej. 12 W)", "aria-label": "Valor de la característica" }),
            button("Quitar", () => { o.attributes.splice(ai, 1); redraw(); }, "pc-danger")
          );
          attrs.append(arow);
        });
        if (o.attributes.length < LIMITS.attributes){
          attrs.append(button("Añadir característica", () => { o.attributes.push({ label: "", value: "" }); redraw(); }));
        }
        obox.append(attrs);
        gbox.append(obox);
      });

      const actions = el("div", "pc-actions");
      if (g.options.length < LIMITS.options){
        actions.append(button("Añadir opción", () => { g.options.push(emptyOption()); redraw(); }));
        if (h.onCreateComponent){
          actions.append(button("Crear componente nuevo…", () => h.onCreateComponent(g)));
        }
      }
      gbox.append(actions);
      root.append(gbox);
    });

    if (model.groups.length < LIMITS.groups){
      root.append(button("Añadir grupo de componentes", () => { model.groups.push(emptyGroup()); redraw(); }));
    }
    root.append(el("p", "pc-note", "Mobau organiza lo que declaras aquí; no certifica la compatibilidad técnica entre piezas. Un grupo «necesario» debe tener al menos una opción antes de enviar."));
    container.append(root);
  }

  return {
    ROLES, ROLE_LABELS, LIMITS,
    slug, uniqueCode, emptyModel, emptyGroup, emptyOption,
    fromStructure, fromManifest, toManifest, canonical, buildProposed,
    validate, summary, render, diff, describeOption, describeGroupRules, loadStructure,
    setContext(ctx){ nameCtx = ctx || nameCtx; }
  };
})();
