# Mobau — Instrucciones permanentes

Mobau es una plataforma de diseño multicategoría para arquitectos e interioristas.

## Forma de trabajo
- Trabajar una sola tarea por vez.
- Antes de editar, entregar un diagnóstico breve y esperar confirmación.
- No reauditar todo el proyecto si ya existe un diagnóstico.
- No inventar tablas, columnas, funciones ni políticas RLS.
- No modificar Supabase, RLS, autenticación, catálogo o estilos generales sin autorización explícita.
- No reescribir archivos completos si no es necesario.
- Entregar resúmenes de máximo 5 líneas.

## Modelo de datos y flujo
- Mantener `quantity` y `unit` en selección, proyecto y cotización.
- `mobau_seleccion` es la selección temporal.
- Un proyecto con `status active` es el proyecto activo.
- Guardar proyecto crea o actualiza un proyecto `active`.
- Enviar solicitud crea un RFQ `submitted` y después marca el proyecto `archived`.
- La selección solo se limpia después de completar correctamente una operación.
- `project_products` usa `quantity numeric(10,2)` y `unit`.
- Revestimientos usan m²; el resto de categorías actuales usa ud., salvo excepciones futuras explícitas.
- Los productos nuevos deben añadirse primero a `mobau_seleccion`.
- Mi selección permite revisar cantidades antes de transferir productos al proyecto activo.
- Al transferir al proyecto activo debe hacerse insert si el producto no existe y update de quantity/unit si ya existe.
- No duplicar `project_products`.
