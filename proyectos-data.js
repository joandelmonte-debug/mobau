/* ============================================================
   MOBAU — Datos de Proyectos (Bloque A)
   ------------------------------------------------------------
   Funciones para listar, crear, abrir y archivar proyectos.
   Depende de que supabase-client.js ya se haya cargado antes
   (usa la variable global `supabaseClient` definida ahí).
   ============================================================ */

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

  /* Guarda un producto real del catálogo dentro de un proyecto.
     Si ya estaba guardado, nunca duplica la fila:
     - mode "replace" (por defecto): reemplaza quantity/unit con el valor recibido.
     - mode "sum": newQuantity = existingQuantity + quantity, y actualiza unit. */
  async saveProductToProject(projectId, productId, quantity, unit, mode = "replace") {
    const { data: existing } = await supabaseClient
      .from("project_products")
      .select("id, quantity, unit")
      .eq("project_id", projectId)
      .eq("product_id", productId)
      .maybeSingle();

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
    /* id, product_id, quantity, unit son los únicos campos que lee
       cualquier página (proyectos.html, proyectos-detalle.html,
       cuenta.html, proyectos-cotizacion.html) del resultado de esta
       función — order_position y created_at solo se usan para
       ordenar, no hace falta traerlos de vuelta. */
    const { data, error } = await supabaseClient
      .from("project_products")
      .select("id, product_id, quantity, unit")
      .eq("project_id", projectId)
      .order("order_position", { ascending: true })
      .order("created_at", { ascending: true });
    if (error) {
      console.error("Error listando productos del proyecto:", error);
      return [];
    }
    return data;
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
      .select("id, project_id, product_id, quantity, unit")
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

  /* Asocia cada producto de la selección local al proyecto, con su
     quantity y unit. Reutiliza saveProductToProject (ya evita
     duplicados) — solo cuenta cuántos fallaron, sin detenerse en el
     primero, para poder informar un resultado parcial con precisión.
     Al ser una transferencia múltiple, touchProject() se llama una
     sola vez al final (nunca dentro del bucle), y solo si al menos un
     producto se guardó de verdad. */
  async transferSelectionToProject(projectId, selectionItems, mode = "replace") {
    let failedCount = 0;
    for (const item of selectionItems) {
      const { error } = await this.saveProductToProject(projectId, item.productId, item.quantity, item.unit, mode);
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
        status: "submitted",
        consent_to_share_contact: true
      })
      .select()
      .single();
    return { data, error };
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
