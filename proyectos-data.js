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
    let query = supabaseClient
      .from("projects")
      .select("*")
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

    const { data: plan, error: planError } = await supabaseClient
      .from("plans")
      .select("*")
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
     Si ya estaba guardado, no lo duplica — devuelve alreadyExists: true. */
  async saveProductToProject(projectId, productId) {
    const { data: existing } = await supabaseClient
      .from("project_products")
      .select("id")
      .eq("project_id", projectId)
      .eq("product_id", productId)
      .maybeSingle();

    if (existing) {
      return { data: existing, error: null, alreadyExists: true };
    }

    const { data, error } = await supabaseClient
      .from("project_products")
      .insert({ project_id: projectId, product_id: productId })
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

  /* Lista las filas de project_products de un proyecto.
     Los datos del producto (nombre, marca, distribuidor, etc.) se
     completan del lado del cliente con el PRODUCTS de script.js —
     esta consulta solo trae qué productos están guardados y con
     qué id de fila, para poder quitarlos. */
  async listProductsInProject(projectId) {
    const { data, error } = await supabaseClient
      .from("project_products")
      .select("*")
      .eq("project_id", projectId)
      .order("order_position", { ascending: true })
      .order("created_at", { ascending: true });
    if (error) {
      console.error("Error listando productos del proyecto:", error);
      return [];
    }
    return data;
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
   Usa las variables globales isLoggedIn / myActiveProjects,
   definidas en script.js y asignadas por cada página después
   de comprobar la sesión. Se usan diálogos nativos del navegador
   (confirm / prompt) a propósito, para no necesitar CSS nuevo. */
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

  const { error, alreadyExists } = await MobauProjects.saveProductToProject(targetProject.id, productId);
  if (error) {
    alert(error.message);
    return { success: false, error };
  }
  showToast(alreadyExists ? "Este producto ya estaba en el proyecto." : `Añadido a "${targetProject.name}".`);
  return { success: true, alreadyExists: !!alreadyExists };
}
