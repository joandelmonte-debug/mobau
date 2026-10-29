/* Ensayo 49 (solo pruebas locales; no se publica). Catálogo simulado de las pruebas, construido en el navegador al
   primer uso a partir de los literales de script.js (STATIC_PRODUCTS, LABELS, DISTRIBUTORS, CATEGORIES), así que debe
   llamarse después de cargar script.js. Una sola fuente para el simulador (mock-catalogo-49.js) y para pruebas-49.html.
   - p1…p20: los 20 productos de muestra, como filas de catalog_products.
   - Los 15 artículos del catálogo público con su foto real (los de la mesa B), con subcategoría y función asignadas
     a mano para las pruebas: los dos drivers y el módulo LED de Hoff Light son componentes.
   - Los 11 artículos sintéticos de la mesa B (los usan los proyectos simulados) y el archivado, solo para proyecto.
   - 5 componentes sintéticos más, para los ejemplos (uno «ambos»). Ningún dato sale de Supabase. */
window.MOBAU_DATOS_49 = (() => {
  let cache = null;
  return () => {
    if (cache) return cache;
    const STATIC = STATIC_PRODUCTS, CATS = CATEGORIES, DIST = DISTRIBUTORS;
    const day = n => new Date(Date.UTC(2026, 6, 1) + n * 86400000).toISOString();
    const base = { use_context: "residencial", space: "sala", availability: "en-stock", measurements: null, materials: null, finishes: null,
      lead_time: null, technical_sheet_url: null, cad_bim_3d_url: null, status: "active", cover_path: null, cover_card_path: null,
      environment: null, light_source: null, electrical_connection: null, color_temperature: null, catalog_role: "principal", finish_options: [] };
    const fin = (code, name, def) => ({ code, name, reference_code: null, is_default: !!def });
    const rows = [];
    const add = (r, n) => rows.push(Object.assign({}, base, { created_at: day(n), updated_at: day(n), catalog_entered_at: day(n) }, r));
    
    /* 1) Muestras p1…p20 (en Producción, al final del «Orden del catálogo»). */
    STATIC.forEach((p, i) => add({
      id: p.id, name: p.nombre, brand: LABELS.marca[p.marca] || p.marca, distributor_id: p.distribuidor, category_id: p.categoria,
      subcategory: p.subcategoria, use_context: p.uso, space: p.espacio, availability: p.disponibilidad, description: p.descripcion,
      measurements: p.medidas, materials: p.materiales, finishes: p.acabados, lead_time: p.leadtime, icon: p.icon,
      reference_code: null, image_url: null
    }, i));
    
    /* 2) Catálogo público con foto (portada 4:5 servida en local desde supabase/tests/mesa-b/fotos/). */
    const FOTO = id => `${location.origin}/supabase/tests/mesa-b/fotos/${id}.jpg`;
    const fotos = [
      ["spectro-02651803", "Sweden Mesa Portátil", "Hoff Light", "2.9003.1318", "Decorativa", "principal", "Lámpara portátil de mesa con batería recargable y regulación táctil.", [fin("fe58c844e258b", "Blanco", 1), fin("f30abf718a862", "Negro")]],
      ["spectro-16e21399", "Duro Petra Plafón", "Vibia", "4881", "De superficie", "principal", "Plafón de superficie con difusor de vidrio opal.", [fin("93", "Blanco", 1), fin("18", "Grafito"), fin("58", "Crema")]],
      ["spectro-19caf9e2", "DRIVER DALI & PUSH EU 125-500mA 5,5- 22W 100-240V", "Hoff Light", "4.3069.6102", "Arquitectónica", "componente", "Driver regulable DALI y pulsador para módulos LED de 125 a 500 mA.", []],
      ["spectro-2cc63dca", "MALTA 8-12 GEN 3 CTT SWITCH | MODULO LED", "Hoff Light", "1.1122.0218", "Empotrada", "componente", "Módulo LED con temperatura de color seleccionable para downlights Malta.", []],
      ["spectro-2e12589a", "Mayfair Colgante", "Vibia", "5520", "Decorativa", "principal", "Lámpara colgante con pantalla bicolor de tejido.", [fin("07", "Grafito y verde", 1), fin("08", "Grafito y naranja")]],
      ["spectro-3470d67d", "Mayfair Mesa", "Vibia", "5500", "Decorativa", "principal", "Lámpara de mesa con pantalla bicolor de tejido.", [fin("08", "Grafito y naranja", 1), fin("07", "Grafito y verde")]],
      ["spectro-402d4c08", "BOGOTA SURFACE DOWNLIGHT - GU10", "Hoff Light", "1.2020.1190", "De superficie", "principal", "Downlight de superficie para lámpara GU10.", [fin("fe7732f235dcd", "Blanco", 1), fin("f26d58f633b2f", "Negro")]],
      ["spectro-5add2cfd", "Alba Portátil", "Vibia", "3780", "Decorativa", "principal", "Lámpara portátil recargable con pantalla cónica.", [fin("38", "Terra Dark", 1), fin("56", "Green D1"), fin("24", "Beige M1")]],
      ["spectro-8ae12824", "Musa Pared", "Vibia", "7415", "Decorativa", "principal", "Aplique de pared con luz indirecta.", [fin("03", "Blanco", 1), fin("24", "Beige D1"), fin("36", "Soft Pink")]],
      ["spectro-8f6c2029", "Driver ON-OFF 150- 500mA 6,3-21W 240V", "Hoff Light", "4.1069.1101", "Arquitectónica", "componente", "Driver de corriente constante, encendido y apagado.", []],
      ["spectro-b029fd1b", "Musa Mesa", "Vibia", "7400", "Decorativa", "principal", "Lámpara de mesa con luz indirecta.", [fin("93", "Blanco", 1), fin("36", "Soft Pink"), fin("24", "Beige M1")]],
      ["spectro-b6ffb730", "Athens 9 Redondo", "Hoff Light", "2.3511.1312", "Empotrada", "principal", "Downlight empotrable redondo orientable.", [fin("00", "Antracita", 1)]],
      ["spectro-cb1cc62f", "Dama Pie", "Vibia", "3230", "Decorativa", "principal", "Lámpara de pie con pantalla textil.", [fin("11", "Black", 1), fin("25", "Beige D1")]],
      ["spectro-d3016bf1", "Dama Sobremesa", "Vibia", "3225", "Decorativa", "principal", "Lámpara de sobremesa con pantalla textil.", [fin("25", "Beige D1", 1), fin("11", "Black")]],
      ["spectro-e9436bca", "COPENHAGUE PARED", "Hoff Light", "1.3011.1111", "De superficie", "principal", "Aplique de pared de superficie.", [fin("f9eceb2c452ce", "Blanco", 1)]]
    ];
    fotos.forEach(([id, name, brand, ref, sub, role, desc, fins], i) => add({
      id, name, brand, distributor_id: "spectro", category_id: "iluminacion", subcategory: sub, description: desc, reference_code: ref,
      icon: "lampFloor", image_url: FOTO(id), catalog_role: role, finish_options: fins
    }, 60 + i));
    
    /* 3) Sintéticos de la mesa B (los usan los proyectos simulados). «viejo» solo existe para las páginas de proyecto. */
    const mesa = [
      ["silla-tolu", "Silla Tolú", "mobiliario", "ST-100", "Tolú", "chair", "principal", [fin("roble", "Roble", 1), fin("nogal", "Nogal")]],
      ["mesa-aro", "Mesa Aro", "mobiliario", "MA-200", "Tolú", "table", "principal", [fin("blanco", "Blanco", 1)]],
      ["sofa-bruma", "Sofá Bruma", "mobiliario", "SB-300", "Bruma", "sofa", "principal", [fin("lino", "Lino", 1), fin("gris", "Gris")]],
      ["lamp-orbe", "Lámpara Orbe", "iluminacion", "LO-10", "Spectro", "lampFloor", "principal", [fin("negro", "Negro", 1)]],
      ["lamp-riel", "Riel Lineal", "iluminacion", "RL-20", "Spectro", "lampFloor", "principal", [fin("blanco", "Blanco", 1)]],
      ["comp-led", "Módulo LED", "iluminacion", "ML-01", "Spectro", "lampFloor", "componente", []],
      ["comp-driver", "Driver 24 V", "iluminacion", "DR-24", "Spectro", "lampFloor", "componente", []],
      ["rev-porc", "Porcelánico Arena", "revestimientos", "PA-60", "Arena", "tile", "principal", [fin("mate", "Mate", 1)]],
      ["rev-madera", "Madera Natural", "revestimientos", "MN-12", "Arena", "tile", "principal", []],
      ["bano-grifo", "Grifo Cascada", "bano", "GC-5", "Agua", "bath", "principal", [fin("cromo", "Cromo", 1)]],
      ["cot-pieza", "Pieza bajo cotización", "mobiliario", "BC-1", "Tolú", "chair", "principal", []]
    ];
    mesa.forEach(([id, name, cat, ref, brand, icon, role, fins], i) => add({
      id, name, brand, distributor_id: cat === "iluminacion" ? "spectro" : "altritempi", category_id: cat, subcategory: CATS[cat].subcategorias[0],
      description: "Artículo simulado de la maqueta.", reference_code: ref, icon, image_url: null, catalog_role: role, finish_options: fins
    }, 40 + i));
    add({ id: "viejo", name: "Producto archivado", brand: "Tolú", distributor_id: "altritempi", category_id: "mobiliario", subcategory: "Residencial",
      description: "Artículo simulado de la maqueta.", reference_code: "VJ-0", icon: "chair", image_url: null, status: "archived", soloProyecto: true }, 39);
    
    /* 4) Componentes sintéticos para los ejemplos (sin foto: icono de la categoría). */
    [
      ["c49-pantalla-dama", "Pantalla Dama", "Vibia", "3230-P", "Decorativa", "componente", "Pantalla textil de recambio para Dama Pie y Dama Sobremesa.", [fin("11", "Black", 1), fin("25", "Beige D1")]],
      ["c49-kit-mayfair", "Kit de suspensión Mayfair", "Vibia", "5520-KS", "Decorativa", "componente", "Cable y florón de techo para Mayfair Colgante.", []],
      ["c49-aro-bogota", "Aro embellecedor Bogota", "Hoff Light", "1.2020.9001", "De superficie", "componente", "Aro decorativo para downlight Bogota.", [fin("b", "Blanco", 1), fin("n", "Negro")]],
      ["c49-gu10", "Lámpara LED GU10 6 W", "Hoff Light", "9.0610.0006", "Empotrada", "componente", "Lámpara de recambio GU10 para downlights.", []],
      ["c49-cable", "Cable textil trenzado 3 m", "Hoff Light", "9.0300.0003", "Decorativa", "ambos", "Cable textil para lámparas colgantes, también a la venta por separado.", [fin("n", "Negro", 1), fin("t", "Terracota")]]
    ].forEach(([id, name, brand, ref, sub, role, desc, fins], i) => add({
      id, name, brand, distributor_id: "spectro", category_id: "iluminacion", subcategory: sub, description: desc, reference_code: ref,
      icon: "lampCeiling", image_url: null, catalog_role: role, finish_options: fins
    }, 80 + i));
    
    /* Para las pruebas del Punto 49: los materiales no se buscan (D5) y un rol desconocido nunca aparece. */
    rows.find(r => r.id === "c49-pantalla-dama").materials = "Policarbonato opal";
    add({ id: "c49-raro", name: "Pieza con rol desconocido", brand: "Hoff Light", distributor_id: "spectro", category_id: "iluminacion",
      subcategory: "Decorativa", description: "Artículo con un valor de función no válido.", reference_code: "0.0000.0001", icon: "lampCeiling",
      image_url: null, catalog_role: "raro", finish_options: [] }, 90);
    const categories = Object.entries(CATS).map(([id, c]) => ({ id, name: c.nombre, subcategories: c.subcategorias }));
    const distributors = Object.entries(DIST).map(([id, d]) => ({ id, name: d.nombre, location: d.ubicacion, description: d.descripcion,
      categories: d.categorias, contact_email: null, contact_phone: null, website: null, created_at: day(0) }));
    const prices = {};
    rows.forEach((r, i) => { if (i % 6 !== 4) prices[r.id] = [46.5, 1120, 38, 412, 520, 29.5, 540, 398, 465, 58, 845, 610, 31, 69, 22.4][i % 15]; });
    
    
    cache = { rows, categories, distributors, prices };
    return cache;
  };
})();
