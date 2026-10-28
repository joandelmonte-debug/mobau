/* ============================================================
   MOBAU — Datos de Proyectos (Bloque A)
   ------------------------------------------------------------
   Funciones para listar, crear, abrir y archivar proyectos.
   Depende de que supabase-client.js ya se haya cargado antes
   (usa la variable global `supabaseClient` definida ahí).
   ============================================================ */

/* ============================================================
   Punto 47 — áreas de un proyecto (opcionales)
   ------------------------------------------------------------
   Un proyecto sin áreas es una lista normal; las áreas aparecen cuando la persona las crea. El estado de las
   áreas se comprueba UNA vez por página y distingue tres casos que nunca se confunden:
   - "ready":   la tabla project_areas existe y se pudo consultar.
   - "missing": la tabla todavía no existe (migración 47-01 sin aplicar): el proyecto se trabaja como hasta ahora.
   - "error":   la tabla no se pudo comprobar (red, permisos, carga). NO se cachea, NO se trata como «sin áreas» y las
                operaciones que podrían escribir en el área equivocada se rechazan con un mensaje claro.
   Todas las escrituras de líneas llevan la cabecera x-mobau-areas (supabase-client.js): una pestaña antigua no la
   lleva y el servidor la rechaza cuando el proyecto ya tiene áreas. ============================================================ */
const MobauAreas = {
  _ready: false,

  /* Devuelve { state: "ready" | "missing" | "error", error }. */
  async probe() {
    if (this._ready) return { state: "ready", error: null };
    const { error } = await supabaseClient.from("project_areas").select("id").limit(1);
    if (!error) { this._ready = true; return { state: "ready", error: null }; }
    if (error.code === "PGRST205" || error.code === "42P01") return { state: "missing", error: null };
    console.error("Error comprobando las áreas:", error);
    return { state: "error", error };
  },

  /* Las áreas de un proyecto, en su orden: { state, areas, error }. areas es null si no se pudieron leer. */
  async list(projectId) {
    const probe = await this.probe();
    if (probe.state === "missing") return { state: "missing", areas: [], error: null };
    if (probe.state === "error") return { state: "error", areas: null, error: probe.error };
    const { data, error } = await supabaseClient
      .from("project_areas")
      .select("id, project_id, name, sort_order, created_at")
      .eq("project_id", projectId)
      .order("sort_order", { ascending: true })
      .order("created_at", { ascending: true })
      .order("id", { ascending: true });
    if (error) {
      console.error("Error leyendo las áreas del proyecto:", error);
      return { state: "error", areas: null, error };
    }
    return { state: "ready", areas: data || [], error: null };
  },

  async create(projectId, name, existing) {
    const next = (existing || []).reduce((max, a) => Math.max(max, a.sort_order || 0), 0) + 1;
    const { data, error } = await supabaseClient
      .from("project_areas")
      .insert({ project_id: projectId, name: String(name || "").trim(), sort_order: next })
      .select("id, project_id, name, sort_order, created_at")
      .single();
    return { data, error };
  },

  async rename(areaId, name) {
    const { data, error } = await supabaseClient
      .from("project_areas")
      .update({ name: String(name || "").trim() })
      .eq("id", areaId)
      .select("id, name")
      .single();
    return { data, error };
  },

  /* Intercambia el orden de dos áreas (subir/bajar). */
  async swapOrder(a, b) {
    const first = await supabaseClient.from("project_areas").update({ sort_order: b.sort_order }).eq("id", a.id);
    if (first.error) return { error: first.error };
    const second = await supabaseClient.from("project_areas").update({ sort_order: a.sort_order }).eq("id", b.id);
    return { error: second.error };
  },

  /* Mueve o copia líneas a un área (null = «Sin área») en una sola operación atómica del servidor. resolutions:
     { [lineId]: { action: "sum" | "skip", note?: "existing" | "incoming" | "both" } }. Si en el destino ya hay una línea
     equivalente sin resolución, el servidor rechaza todo sin cambiar nada (hint transfer_conflict, detail con las líneas). */
  async transferLines(lineIds, areaId, kind, resolutions) {
    const { data, error } = await supabaseClient.rpc("project_lines_transfer", {
      p_line_ids: lineIds, p_area_id: areaId || null, p_kind: kind, p_resolutions: resolutions || {}
    });
    return { data, error };
  },

  /* Elimina un área: sus líneas pasan a «Sin área» (atómico). resolutions por línea en conflicto:
     { action: "sum", note? } o { action: "move", area_id }. */
  async deleteArea(areaId, resolutions) {
    const { data, error } = await supabaseClient.rpc("project_area_delete", {
      p_area_id: areaId, p_resolutions: resolutions || {}
    });
    return { data, error };
  },

  /* Resumen y cotización: etiqueta «Área: X» y orden por área (áreas en su orden, «Sin área» al final). labels(rows, areas)
     devuelve { rows (ordenadas), label(row) } y no hace nada si no hay áreas. areas puede ser null (no se pudieron leer). */
  presentation(rows, areas) {
    const list = areas || [];
    const byId = new Map(list.map((a, i) => [a.id, { name: a.name, index: i }]));
    const any = list.length > 0 || rows.some(r => r.area_name);
    /* Filas de la copia de una RFQ: traen su propio nombre y orden de área; las vivas, el de las áreas actuales. */
    const rank = row => (row.area_name ? (Number.isFinite(row.area_sort_order) ? row.area_sort_order : 1e6 - 1)
      : byId.has(row.area_id) ? byId.get(row.area_id).index : 1e6);
    const label = row => (!any ? "" : "Área: " + (row.area_name || (byId.get(row.area_id) || {}).name || "Sin área"));
    const ordered = !any ? rows : rows.map((r, i) => ({ r, i })).sort((a, b) => rank(a.r) - rank(b.r) || a.i - b.i).map(x => x.r);
    return { rows: ordered, label };
  },

  /* Los conflictos que devuelve el servidor (detail JSON) -> [{ line_id, twin_id }]. */
  conflictsOf(error) {
    if (!error || (error.hint !== "transfer_conflict" && error.hint !== "area_conflict")) return null;
    try { const list = JSON.parse(error.details || error.detail || "[]"); return Array.isArray(list) ? list : []; }
    catch (e) { return []; }
  },

  /* Texto para la persona cuando una operación sobre líneas o áreas falla. */
  explain(error) {
    if (!error) return "";
    if (error.hint === "client_outdated") return "Esta página está desactualizada: recárgala para seguir trabajando en este proyecto.";
    if (error.hint === "project_not_active") return "El proyecto ya no admite cambios (está archivado).";
    if (error.hint === "area_invalid") return "El área ya no existe. Recarga la página.";
    if (error.hint === "line_invalid") return "Alguna de las líneas ya no existe. Recarga la página.";
    return error.message || "No pudimos completar la operación.";
  }
};

const MobauProjects = {

  /* Lista los proyectos del usuario actual.
     status: "active" | "archived" | undefined (todos) */
  async list(status) {
    /* Columnas exactas que consumen proyectos.html, cuenta.html y
       proyectos-cotizacion.html desde el resultado de list() — ninguna
       de las tres lee owner_user_id ni created_at de aquí (created_at
       solo se usa vía get(), que sigue con select("*") sin tocar). */
    let query = supabaseClient
      .from("projects")
      .select("id, name, client_name, project_type, location, description, status, updated_at")
      .order("updated_at", { ascending: false });
    if (status) query = query.eq("status", status);

    const { data, error } = await query;
    if (error) {
      console.error("Error listando proyectos:", error);
      return [];
    }
    return data;
  },

  /* Trae un proyecto por id. */
  async get(id) {
    const { data, error } = await supabaseClient
      .from("projects")
      .select("*")
      .eq("id", id)
      .single();
    if (error) {
      console.error("Error obteniendo el proyecto:", error);
      return null;
    }
    return data;
  },

  /* Crea un proyecto nuevo, siempre en estado "active".
     Devuelve { data, error } sin lanzar excepción, para que la
     página decida cómo mostrar un posible error de límite de plan. */
  async create(fields, userId) {
    const { data, error } = await supabaseClient
      .from("projects")
      .insert({
        owner_user_id: userId,
        name: fields.name,
        client_name: fields.client_name || null,
        project_type: fields.project_type || null,
        location: fields.location || null,
        description: fields.description || null,
        status: "active"
      })
      .select()
      .single();
    return { data, error };
  },

  /* Cambia el estado de un proyecto ("active" <-> "archived"). */
  async setStatus(id, status) {
    const { data, error } = await supabaseClient
      .from("projects")
      .update({ status })
      .eq("id", id)
      .select()
      .single();
    return { data, error };
  },

  /* Elimina definitivamente un proyecto archivado. RLS exige que
     pertenezca al usuario actual y que status = 'archived' — esta
     llamada no puede afectar proyectos activos ni de otro usuario,
     sin importar qué id se le pase. project_products y moodboards
     se eliminan solos por ON DELETE CASCADE. */
  async deleteProject(id) {
    const { error } = await supabaseClient
      .from("projects")
      .delete()
      .eq("id", id);
    return { error };
  },

  /* Cuenta cuántos proyectos activos tiene el usuario ahora mismo. */
  async countActive() {
    const { count, error } = await supabaseClient
      .from("projects")
      .select("id", { count: "exact", head: true })
      .eq("status", "active");
    if (error) {
      console.error("Error contando proyectos activos:", error);
      return 0;
    }
    return count || 0;
  },

  /* Devuelve el plan del usuario actual con sus límites
     (id, name, max_users, max_active_projects, trial_days). */
  async myPlan(userId) {
    const { data: profile, error: profileError } = await supabaseClient
      .from("profiles")
      .select("plan")
      .eq("id", userId)
      .single();
    if (profileError || !profile) {
      console.error("Error obteniendo el perfil:", profileError);
      return null;
    }

    /* Únicos campos de "plans" que lee algún archivo del sitio (grep
       confirmado): name y max_active_projects. */
    const { data: plan, error: planError } = await supabaseClient
      .from("plans")
      .select("name, max_active_projects")
      .eq("id", profile.plan)
      .single();
    if (planError || !plan) {
      console.error("Error obteniendo el plan:", planError);
      return null;
    }
    return plan;
  },

  /* ---------- Bloque B: productos guardados dentro de un proyecto ---------- */

  /* Guarda un producto real del catálogo dentro de un proyecto, con su
     acabado (punto 44; finish null = sin acabado) y su configuración
     (46-04; null = sin configuración): una línea por producto, acabado y
     configuración. Si esa línea ya estaba guardada, nunca la duplica:
     - mode "replace" (por defecto): reemplaza quantity/unit con el valor recibido.
     - mode "sum": newQuantity = existingQuantity + quantity, y actualiza unit. */
  async saveProductToProject(projectId, productId, quantity, unit, mode = "replace", finish = null, configuration = null, areaId = null) {
    /* Punto 47: la línea es única por producto, acabado, configuración Y área. Sin indicar área se trabaja siempre
       sobre «Sin área», nunca sobre la de otra. Si las áreas no se pudieron comprobar no se escribe nada: podría
       acabar en el área equivocada. Sin la migración (estado "missing") todo sigue como antes. */
    const areaProbe = await MobauAreas.probe();
    if (areaProbe.state === "error") {
      return { data: null, error: { message: "No pudimos comprobar las áreas del proyecto. Revisa tu conexión e inténtalo de nuevo; no se ha cambiado nada." }, alreadyExists: false };
    }
    const areasOn = areaProbe.state === "ready";
    const targetArea = areasOn && areaId ? areaId : null;
    const finishCode = (typeof finish === "string" && finish.trim()) ? finish.trim() : null;
    /* Puede haber varias líneas del mismo producto y acabado con
       configuraciones distintas: se elige la de la misma configuración
       (forma normal, seleccion-data.js), nunca la primera que aparezca. */
    const configKey = selectionConfigurationKey(configuration);
    let lookup = supabaseClient
      .from("project_products")
      .select("id, quantity, unit, configuration")
      .eq("project_id", projectId)
      .eq("product_id", productId);
    lookup = finishCode ? lookup.eq("finish_code", finishCode) : lookup.is("finish_code", null);
    if (areasOn) lookup = targetArea ? lookup.eq("area_id", targetArea) : lookup.is("area_id", null);
    const { data: candidates, error: lookupError } = await lookup;
    if (lookupError) {
      return { data: null, error: lookupError, alreadyExists: false };
    }
    const existing = (candidates || []).find(row => selectionConfigurationKey(row.configuration) === configKey) || null;

    if (existing) {
      const updateRow = {};
      if (mode === "sum") {
        const base = (typeof existing.quantity === "number" && Number.isFinite(existing.quantity)) ? existing.quantity : 0;
        const add = (typeof quantity === "number" && Number.isFinite(quantity)) ? quantity : 0;
        updateRow.quantity = Math.round((base + add) * 100) / 100;
        if (typeof unit === "string" && unit) updateRow.unit = unit;
      } else {
        if (typeof quantity === "number" && Number.isFinite(quantity)) updateRow.quantity = quantity;
        if (typeof unit === "string" && unit) updateRow.unit = unit;
      }

      if (Object.keys(updateRow).length === 0) {
        return { data: existing, error: null, alreadyExists: true };
      }

      const { data, error } = await supabaseClient
        .from("project_products")
        .update(updateRow)
        .eq("id", existing.id)
        .select()
        .single();

      return { data: data || existing, error, alreadyExists: true };
    }

    const insertRow = { project_id: projectId, product_id: productId };
    if (finishCode) insertRow.finish_code = finishCode;
    if (configKey) insertRow.configuration = normalizeSelectionConfiguration(configuration);
    if (targetArea) insertRow.area_id = targetArea;
    if (typeof quantity === "number" && Number.isFinite(quantity)) insertRow.quantity = quantity;
    if (typeof unit === "string" && unit) insertRow.unit = unit;

    const { data, error } = await supabaseClient
      .from("project_products")
      .insert(insertRow)
      .select()
      .single();

    return { data, error, alreadyExists: false };
  },

  /* Quita un producto guardado del proyecto (por el id de la fila
     de project_products, no por el id del producto). */
  async removeProductFromProject(projectProductId) {
    const { error } = await supabaseClient
      .from("project_products")
      .delete()
      .eq("id", projectProductId);
    return { error };
  },

  /* Quita varias líneas a la vez (selección múltiple), por id de línea. */
  async removeProductsFromProject(projectProductIds) {
    const { error } = await supabaseClient
      .from("project_products")
      .delete()
      .in("id", projectProductIds);
    return { error };
  },

  /* Actualiza la quantity de una fila ya guardada, por su propio id de
     fila (igual que removeProductFromProject) — nunca toca unit ni
     product_id, así que no puede duplicar ni reasignar la fila a otro
     producto. */
  async updateProductQuantity(projectProductId, quantity) {
    const { data, error } = await supabaseClient
      .from("project_products")
      .update({ quantity })
      .eq("id", projectProductId)
      .select()
      .single();
    return { data, error };
  },

  /* Lista las filas de project_products de un proyecto.
     Los datos del producto (nombre, marca, distribuidor, etc.) se
     completan del lado del cliente con el PRODUCTS de script.js —
     esta consulta solo trae qué productos están guardados y con
     qué id de fila, para poder quitarlos. */
  async listProductsInProject(projectId) {
    const { rows, error } = await this.loadProjectLines(projectId);
    if (error) {
      console.error("Error listando productos del proyecto:", error);
      return [];
    }
    return rows;
  },

  /* Lo mismo con el error a la vista (nunca un [] que parezca «proyecto vacío») y con area_id cuando el proyecto
     puede tener áreas: { rows, areas: { state, areas, error }, error }. Si no se pudo comprobar si existen las
     áreas, tampoco se devuelven filas: sin eso no se sabe a qué área pertenece cada una. */
  async loadProjectLines(projectId) {
    const areas = await MobauAreas.list(projectId);
    if (areas.state === "error") return { rows: [], areas, error: areas.error };
    const columns = "id, product_id, finish_code, configuration, quantity, unit, notes" + (areas.state === "ready" ? ", area_id" : "");
    const { data, error } = await supabaseClient
      .from("project_products")
      .select(columns)
      .eq("project_id", projectId)
      .order("order_position", { ascending: true })
      .order("created_at", { ascending: true });
    if (error) return { rows: [], areas, error };
    return { rows: data || [], areas, error: null };
  },

  /* Punto 46-04: lo solicitado en una RFQ del proyecto (la indicada o, sin
     rfqId, la más reciente con copia), desde su copia generada en el
     servidor (rfqs.lines_snapshot), con la misma forma de fila que
     listProductsInProject() (+ requested: la línea copiada). Cada RFQ
     conserva su propia copia. Las RFQ anteriores a 46-04 no tienen copia:
     se devuelven las líneas actuales del proyecto, como hasta ahora (no se
     inventa una copia). */
  async listRequestedLines(projectId, rfqId = null) {
    const view = await this.getRequestedView(projectId, rfqId);
    /* Si la copia no se pudo leer se devuelven las líneas actuales, como hasta ahora (el error ya quedó en consola). */
    return view.rows || this.listProductsInProject(projectId);
  },

  /* Punto 47: lo mismo con las áreas de esa copia (rfqs.lines_snapshot v2: id, nombre y orden de las áreas usadas) y
     el error a la vista. { rows, areas, fromCopy, error }: rows es null si no se pudo leer. Sin copia (RFQ anterior a
     46-04, o proyecto sin RFQ) se devuelven las líneas y áreas actuales, con fromCopy false. */
  async getRequestedView(projectId, rfqId = null) {
    let query = supabaseClient
      .from("rfqs")
      .select("lines_snapshot")
      .eq("project_id", projectId);
    if (rfqId) query = query.eq("id", rfqId);
    const { data, error } = await query
      .not("lines_snapshot", "is", null)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error) {
      console.error("Error leyendo la copia de la solicitud:", error);
      return { rows: null, areas: [], fromCopy: false, error };
    }
    const snapshot = data && data.lines_snapshot;
    if (!snapshot || !Array.isArray(snapshot.distributors)) {
      const current = await this.loadProjectLines(projectId);
      if (current.error) return { rows: null, areas: [], fromCopy: false, error: current.error, areaState: current.areas.state };
      return { rows: current.rows, areas: current.areas.areas || [], fromCopy: false, error: null, areaState: current.areas.state };
    }
    const rows = snapshot.distributors.flatMap(group => (group.lines || []).map(line => ({
      id: line.line_id,
      product_id: line.product_id,
      finish_code: line.finish_code || null,
      configuration: line.configuration || null,
      quantity: line.quantity,
      unit: line.unit,
      notes: line.notes || null,
      area_id: line.area_id || null,
      area_name: line.area_name || null,
      area_sort_order: line.area_sort_order === undefined ? null : line.area_sort_order,
      requested: line
    })));
    const areas = Array.isArray(snapshot.areas) ? snapshot.areas.map(a => ({ id: a.id, name: a.name, sort_order: a.sort_order })) : [];
    return { rows, areas, fromCopy: true, error: null, areaState: areas.length ? "ready" : "missing" };
  },

  /* Punto 46: nota técnica de una línea del proyecto (texto libre opcional del profesional; vacío = sin nota).
     Solo toca notes de esa fila: nunca quantity, unit, producto ni configuración. */
  async updateLineNote(projectProductId, note) {
    const value = typeof note === "string" && note.trim() ? note.trim() : null;
    const { data, error } = await supabaseClient
      .from("project_products")
      .update({ notes: value })
      .eq("id", projectProductId)
      .select("id, notes")
      .single();
    return { data, error };
  },

  /* Punto 46 · bloque 4: solicitudes enviadas de un proyecto (la RLS solo deja ver las propias), de la más
     reciente a la más antigua, con su copia de líneas (null en las anteriores a 46-04). null = no se pudo leer. */
  async listRfqsOfProject(projectId) {
    const { data, error } = await supabaseClient
      .from("rfqs")
      .select("id, created_at, status, requester_name, project_location, budget_range, project_stage, message, lines_snapshot")
      .eq("project_id", projectId)
      .order("created_at", { ascending: false });
    if (error) {
      console.error("Error leyendo las solicitudes del proyecto:", error);
      return null;
    }
    return data || [];
  },

  /* Punto 46 · bloque 4: estado actual de cada línea del proyecto
     (project_line_states, con la RLS de project_products): Map por id de
     línea, o null si no se pudo comprobar. Informativo: el servidor lo
     vuelve a comprobar al enviar la solicitud. */
  async listLineStates(projectId) {
    return informativeConfigurationQuery(async () => {
      const { data, error } = await runCatalogQuery(supabaseClient.rpc("project_line_states", { p_project_id: projectId }));
      if (error || !Array.isArray(data)) return null;
      return new Map(data.map(state => [state.line_id, state]));
    }, null);
  },

  /* Lo mismo para las líneas configuradas de la selección que todavía no
     están en un proyecto (line_configuration_resolve): Map por producto +
     configuración; sin entrada = no se pudo comprobar. */
  async resolveSelectionConfigurations(items) {
    const states = new Map();
    await Promise.all(items.filter(item => item.configuration).map(async item => {
      const key = item.productId + "\u0000" + selectionConfigurationKey(item.configuration);
      const state = await informativeConfigurationQuery(async () => {
        const { data, error } = await runCatalogQuery(supabaseClient.rpc("line_configuration_resolve", { p_product_id: item.productId, p_configuration: item.configuration }));
        return error || !data ? null : data;
      }, null);
      if (state) states.set(key, state);
    }));
    return states;
  },

  /* Trae los productos guardados de VARIOS proyectos en una sola
     consulta (evita pedir uno por proyecto — el N+1 de "Mis
     proyectos") y los agrupa por project_id en memoria. Devuelve un
     Map<project_id, row[]>; un proyecto sin productos guardados
     simplemente no aparece como clave, así que hay que leerlo con
     `.get(id) || []`. Mismos campos que listProductsInProject() más
     project_id, imprescindible aquí para poder agrupar. Sin proyectos
     no se hace ninguna consulta. */
  async listProductsInProjects(projectIds) {
    if (!projectIds.length) return new Map();
    const { data, error } = await supabaseClient
      .from("project_products")
      .select("id, project_id, product_id, finish_code, configuration, quantity, unit")
      .in("project_id", projectIds);
    if (error) {
      console.error("Error listando productos de varios proyectos:", error);
      return new Map();
    }
    const grouped = new Map();
    data.forEach(row => {
      if (!grouped.has(row.project_id)) grouped.set(row.project_id, []);
      grouped.get(row.project_id).push(row);
    });
    return grouped;
  },

  /* Reutiliza el proyecto activo del usuario si ya existe, o crea uno
     nuevo con ese nombre — nunca ambas cosas. Punto único compartido
     por "Guardar proyecto" y "Enviar solicitud" para no duplicar
     proyectos entre los dos caminos. */
  /* Reutiliza el proyecto activo del usuario si ya existe, o crea uno
     nuevo con estos campos — nunca ambas cosas. Punto único compartido
     por "Guardar proyecto" y "Enviar solicitud" para no duplicar
     proyectos entre los dos caminos. Si se reutiliza uno existente,
     también actualiza sus datos con lo que el usuario acaba de escribir
     — solo los campos con valor real, nunca sobrescribe con vacío. */
  async getOrCreateActiveProject(fields, userId) {
    const activeProjects = await this.list("active");
    if (activeProjects.length) {
      const existing = activeProjects[0];
      const { data: updated, error } = await this.updateProjectDetails(existing.id, fields);
      return { data: updated || existing, error, created: false };
    }
    const { data, error } = await this.create(fields, userId);
    return { data, error, created: true };
  },

  /* Actualiza nombre y detalles de un proyecto ya existente, desde el
     formulario de edición de proyectos-detalle.html. A diferencia de
     updateProjectDetails() (pensada para no pisar datos al reutilizar
     un proyecto activo), esta función guarda exactamente lo que el
     usuario escribió, incluyendo vaciar un campo opcional si lo borra.
     El nombre se valida antes de llamar aquí (nunca vacío). Nunca toca
     project_products — no crea ni transfiere nada. */
  async updateProjectInfo(id, fields) {
    const { data, error } = await supabaseClient
      .from("projects")
      .update({
        name: fields.name,
        project_type: fields.project_type || null,
        location: fields.location || null,
        client_name: fields.client_name || null,
        description: fields.description || null,
        updated_at: new Date().toISOString() // se adopta la opción: editar datos generales también cuenta como "Actualizado"
      })
      .eq("id", id)
      .select()
      .single();
    return { data, error };
  },

  /* Actualiza solo los campos de detalle de un proyecto que traigan un
     valor real — un campo vacío en el formulario nunca borra un dato
     que ya existiera guardado. */
  async updateProjectDetails(id, fields) {
    const updates = {};
    if (fields.client_name) updates.client_name = fields.client_name;
    if (fields.project_type) updates.project_type = fields.project_type;
    if (fields.location) updates.location = fields.location;
    if (fields.description) updates.description = fields.description;
    if (Object.keys(updates).length === 0) {
      return { data: null, error: null };
    }
    const { data, error } = await supabaseClient
      .from("projects")
      .update(updates)
      .eq("id", id)
      .select()
      .single();
    return { data, error };
  },

  /* Asocia cada línea de la selección local (producto + acabado) al
     proyecto, con su quantity y unit. Reutiliza saveProductToProject (ya evita
     duplicados) — solo cuenta cuántos fallaron, sin detenerse en el
     primero, para poder informar un resultado parcial con precisión.
     Al ser una transferencia múltiple, touchProject() se llama una
     sola vez al final (nunca dentro del bucle), y solo si al menos un
     producto se guardó de verdad. */
  async transferSelectionToProject(projectId, selectionItems, mode = "replace", areaId = null) {
    let failedCount = 0;
    for (const item of selectionItems) {
      const { error } = await this.saveProductToProject(projectId, item.productId, item.quantity, item.unit, mode, item.finish || null, item.configuration || null, areaId);
      if (error) failedCount++;
    }
    if (selectionItems.length - failedCount > 0) {
      await this.touchProject(projectId);
    }
    return { failedCount, totalCount: selectionItems.length };
  },

  /* Marca projects.updated_at como "ahora" — el punto único que se
     llama después de que una operación real sobre project_products
     (añadir, quitar, cambiar quantity/unit) haya terminado con éxito.
     Nunca se llama si la operación falló. Solución de aplicación: lo
     ideal sería un trigger en project_products usando NOW() del propio
     Postgres, pero este repositorio no tiene sistema de migraciones
     SQL disponible — mientras no lo tenga, este es el punto central
     que evita perder o duplicar la actualización de la fecha. */
  async touchProject(projectId) {
    const { data, error } = await supabaseClient
      .from("projects")
      .update({ updated_at: new Date().toISOString() })
      .eq("id", projectId)
      .select()
      .single();
    if (error) {
      console.error("Error actualizando la fecha del proyecto:", error);
    }
    return { data, error };
  },

  /* Inserta una solicitud real en rfqs. status se fija en "submitted"
     directamente porque esa tabla no tiene política de UPDATE — una
     vez insertada, no se puede corregir después desde la web.
     No toca rfq_distributors (sin política de usuario, a propósito). */
  async createRfq(fields) {
    const { data, error } = await supabaseClient
      .from("rfqs")
      .insert({
        project_id: fields.project_id,
        requester_user_id: fields.requester_user_id,
        requester_name: fields.requester_name,
        requester_email: fields.requester_email,
        requester_company: fields.requester_company || null,
        project_location: fields.project_location || null,
        estimated_purchase_date: fields.estimated_purchase_date || null,
        message: fields.message || null,
        budget_range: fields.budget_range || null,
        project_stage: fields.project_stage || null,
        status: "submitted",
        consent_to_share_contact: true
      })
      .select()
      .single();
    return { data, error };
  },

  /* Marca como no incluidas en la solicitud las LÍNEAS indicadas (p. ej. de productos archivados), por su id de línea:
     el mismo producto en otra área, acabado o configuración no se toca (Punto 47). */
  async excludeFromRfq(projectId, lineIds) {
    const { error } = await supabaseClient
      .from("project_products")
      .update({ selected_for_rfq: false })
      .eq("project_id", projectId)
      .in("id", lineIds);
    return { error };
  },

  /* Lista las RFQs del usuario autenticado, más recientes primero.
     Filtra explícitamente por requester_user_id además de la RLS ya
     confirmada en Supabase (rfqs_select: requester_user_id = auth.uid()),
     mismo criterio que ya usa el resto del código con otras tablas
     protegidas por RLS — nunca puede devolver solicitudes de otro
     usuario. Solo trae las columnas que "Mi cuenta" necesita; el
     nombre del proyecto no vive en rfqs (solo project_id), se resuelve
     aparte con MobauProjects.list(). */
  async listMyRfqs(userId) {
    const { data, error } = await supabaseClient
      .from("rfqs")
      .select("id, project_id, requester_company, status, created_at")
      .eq("requester_user_id", userId)
      .order("created_at", { ascending: false });
    if (error) {
      console.error("Error listando tus solicitudes:", error);
      return [];
    }
    return data;
  },

  /* Única fuente de verdad para "¿tiene el usuario un proyecto activo
     ahora mismo?" — reutilizada por el catálogo, la ficha de producto
     y el indicador del CTA. No usa requireSession(): un visitante sin
     sesión simplemente no tiene proyecto activo, sin redirigir a nadie. */
  async getActiveProjectStatus() {
    const session = await MobauAuth.getSession();
    if (!session) return { hasActiveProject: false, project: null };
    const activeProjects = await this.list("active");
    if (!activeProjects.length) return { hasActiveProject: false, project: null };
    return { hasActiveProject: true, project: activeProjects[0] };
  }
};

/* Etiquetas de tipo de proyecto, en español, para mostrar en la interfaz. */
const PROJECT_TYPE_LABELS = {
  residencial: "Residencial",
  comercial: "Comercial",
  hospitalidad: "Hospitalidad",
  oficina: "Oficina",
  otro: "Otro"
};

/* Punto 46 · bloque 4: consulta informativa de configuraciones con el mismo
   límite que el catálogo (runCatalogQuery y CATALOG_CONFIG.timeoutMs, de
   script.js) y un plazo de respaldo por si la cancelación no la termina.
   Nunca falla: ante error, rechazo o límite devuelve fallback; una respuesta
   posterior se ignora. */
async function informativeConfigurationQuery(run, fallback){
  const query = Promise.resolve().then(run).catch(() => fallback);
  let timer;
  const limit = new Promise(done => { timer = setTimeout(() => done(fallback), CATALOG_CONFIG.timeoutMs); });
  const result = await Promise.race([query, limit]);
  clearTimeout(timer);
  return result;
}

/* Punto 46 · bloque 4: textos de la configuración de una línea, para el
   proyecto, el resumen y la cotización. Devuelven texto plano: quien lo
   incorpora al HTML lo escapa. Dos orígenes que nunca se mezclan:
   - current(): estado ACTUAL según el catálogo (project_line_states o
     line_configuration_resolve). Informativo; sin estado, o con un estado
     desconocido, «no se pudo comprobar», nunca «completa». Cantidades por
     unidad de la línea.
   - sent(): lo ENVIADO en una RFQ, tal como lo guardó el servidor en su
     copia (rfqs.lines_snapshot); no se recalcula. Cantidades totales.
   Resultado: { lines, status, reasons, needsQuote }; status es
   "no_requiere" | "completa" | "pendiente" | "sin_comprobar". */
const MobauLineConfig = {
  /* Nota secundaria del bloque (una vez por lista, no por línea): lo registrado son elecciones, no una validación. */
  COMPAT_NOTE: "Mobau no valida la compatibilidad técnica entre piezas.",
  compatNote(afterEl, show){
    if (!afterEl || !afterEl.parentNode) return;
    const id = `compat-note-${afterEl.id || "bloque"}`;
    let el = document.getElementById(id);
    if (!show){ if (el) el.remove(); return; }
    if (!el){
      el = document.createElement("p");
      el.id = id;
      el.className = "card-meta line-compat-note";
      el.style.margin = "8px 0 0";
      el.textContent = this.COMPAT_NOTE;
      afterEl.after(el);
    }
  },
  rawChoices(configuration){
    const choices = configuration && Array.isArray(configuration.choices) ? configuration.choices : null;
    if (!choices || !choices.every(c => c && typeof c.group === "string" && Array.isArray(c.options))) return null;
    return choices.map(c => `${c.group}: ${c.options.join(", ")}`).join(" · ");
  },

  current(configuration, state){
    const known = !!state && (state.status === "completa" || state.status === "pendiente" || state.status === "no_requiere");
    const reasons = known && Array.isArray(state.reasons) ? state.reasons.map(r => r.message) : [];
    if (!configuration){
      if (known && state.status === "pendiente") return { lines: [`Revisar: ${reasons.join(" ")}`], status: "pendiente", reasons, needsQuote: false };
      return { lines: [], status: known ? state.status : "sin_comprobar", reasons: [], needsQuote: false };
    }
    const raw = this.rawChoices(configuration);
    if (raw === null){
      return { lines: ["Revisar: la configuración guardada no tiene el formato esperado. Se conserva tal cual."], status: "sin_comprobar", reasons: [], needsQuote: true };
    }
    if (!known || state.status === "no_requiere"){
      return { lines: [`Configuración: ${raw}`, "No pudimos comprobar la configuración con el catálogo actual. Se conserva lo guardado."],
               status: "sin_comprobar", reasons: [], needsQuote: true };
    }
    const lines = [];
    if (state.summary) lines.push(`Configuración: ${state.summary}`);
    const components = (state.items || []).filter(i => i.kind === "componente");
    if (components.length){
      lines.push(components.map(i => `${i.product_name || i.product_id}: ${i.supply === "incluido" ? "incluido" : "aparte"}`
        + (i.quantity_mode === "a_calcular" ? " · cantidad a calcular" : ` · ${i.quantity} por unidad`)).join(" · "));
    }
    if (state.status === "pendiente"){
      lines.push(`Elegido: ${raw}`, `Revisar: ${reasons.join(" ")}`);
    } else {
      if (state.review === "revisar") lines.push("Revisar: el catálogo cambió esta configuración desde que se guardó.");
      lines.push("Elecciones registradas según el catálogo actual; se vuelven a comprobar al enviar la solicitud.");
    }
    (state.notices || []).forEach(n => lines.push(n.message));
    const needsQuote = state.status === "pendiente" || components.some(i => i.supply === "aparte" || i.quantity_mode === "a_calcular");
    return { lines, status: state.status, reasons, needsQuote };
  },

  sent(requested){
    if (!requested || !requested.configuration){
      return { lines: [], status: (requested && requested.config_status) || "sin_comprobar", reasons: [], needsQuote: false };
    }
    const raw = this.rawChoices(requested.configuration);
    const lines = [`Configuración enviada: ${requested.config_summary || raw || "sin resumen"}`];
    const components = (requested.items || []).filter(i => i.kind === "componente");
    if (components.length){
      lines.push(components.map(i => `${i.product_name || i.product_id}: ${i.supply === "incluido" ? "incluido" : "aparte"}`
        + (i.quantity_status === "calculada" ? ` · ${i.total_quantity} ${i.unit} en total` : " · cantidad a calcular")).join(" · "));
    }
    const reasons = Array.isArray(requested.config_reasons) ? requested.config_reasons.map(r => r.message) : [];
    if (requested.config_status === "pendiente") lines.push(`Enviada con elecciones por revisar: ${reasons.join(" ")}`);
    (requested.config_notices || []).forEach(n => lines.push(n.message));
    return { lines, status: requested.config_status || "sin_comprobar", reasons,
             needsQuote: components.some(i => i.supply === "aparte" || i.quantity_status !== "calculada") };
  }
};

/* true si el plan permite más de un proyecto activo a la vez (Estudio).
   Se basa en plans.max_active_projects — NO en project.studio_id, porque
   hoy ningún proyecto tiene studio_id asignado todavía (el Bloque E no
   existe), así que studio_id nunca reflejaría el plan real del usuario. */
function planAllowsMultipleActive(plan){
  return !!plan && plan.max_active_projects > 1;
}

/* Fecha relativa simple, en español, sin librerías externas. */
function relativeDate(isoString) {
  const then = new Date(isoString).getTime();
  const now = Date.now();
  const diffMin = Math.floor((now - then) / 60000);
  if (diffMin < 1) return "justo ahora";
  if (diffMin < 60) return `hace ${diffMin} ${diffMin === 1 ? "minuto" : "minutos"}`;
  const diffH = Math.floor(diffMin / 60);
  if (diffH < 24) return `hace ${diffH} ${diffH === 1 ? "hora" : "horas"}`;
  const diffD = Math.floor(diffH / 24);
  if (diffD < 30) return `hace ${diffD} ${diffD === 1 ? "día" : "días"}`;
  return new Date(isoString).toLocaleDateString("es-DO", { year: "numeric", month: "long", day: "numeric" });
}

/* ============================================================
   Bloque B — flujo de "Añadir al proyecto" desde el catálogo
   ------------------------------------------------------------
   @deprecated Sin llamadas activas en ninguna página: catalogo.html y
   producto.html añaden siempre a mobau_seleccion (addToSelection) y
   nunca escriben directo en project_products — ver bindAddButtons()
   en script.js y el handler de "add-project-btn" en producto.html.
   Se conserva sin borrar (no se pidió eliminarla) por si alguien
   reactiva ese flujo de escritura directa. Si se reactiva:
   - revisar que la página que la llame siga asignando isLoggedIn /
     myActiveProjects tras comprobar sesión (script.js ya no lo hace
     para este flujo);
   - quantity/unit ya se calculan aquí abajo con getProductUnit(),
     igual que en cualquier otro punto real de guardado — no debería
     hacer falta tocar nada más.
   Se usan diálogos nativos del navegador (confirm / prompt) a
   propósito, para no necesitar CSS nuevo. */
async function mobauSaveToProject(productId) {
  if (!myActiveProjects.length) {
    window.location.href = `proyectos-nuevo.html?producto_pendiente=${encodeURIComponent(productId)}`;
    return { success: false, redirected: true };
  }

  let targetProject;
  if (myActiveProjects.length === 1) {
    targetProject = myActiveProjects[0];
    const ok = confirm(`¿Guardar este producto en tu proyecto "${targetProject.name}"?`);
    if (!ok) return { success: false, cancelled: true };
  } else {
    const list = myActiveProjects.map((p, i) => `${i + 1}. ${p.name}`).join("\n");
    const answer = prompt(`¿En cuál proyecto quieres guardarlo?\n${list}\n\nEscribe el número:`);
    const idx = parseInt(answer, 10) - 1;
    if (Number.isNaN(idx) || !myActiveProjects[idx]) return { success: false, cancelled: true };
    targetProject = myActiveProjects[idx];
  }

  /* quantity/unit nunca deben faltar — mismo cálculo que usan
     catalogo.html/producto.html al añadir a mobau_seleccion, para que
     una fila insertada desde aquí no quede inconsistente con el resto. */
  const product = (typeof PRODUCTS !== "undefined") ? PRODUCTS.find(p => p.id === productId) : null;
  const unit = (typeof getProductUnit === "function") ? getProductUnit(product) : "ud.";
  const initialQuantity = unit === "ud." ? 1 : 0;

  const { error, alreadyExists } = await MobauProjects.saveProductToProject(targetProject.id, productId, initialQuantity, unit);
  if (error) {
    alert(error.message);
    return { success: false, error };
  }
  await MobauProjects.touchProject(targetProject.id);
  showToast(alreadyExists ? "Este producto ya estaba en el proyecto." : `Añadido a "${targetProject.name}".`);
  return { success: true, alreadyExists: !!alreadyExists };
}
