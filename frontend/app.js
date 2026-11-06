const $ = (s, el = document) => el.querySelector(s);
const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

const state = {
  token: sessionStorage.getItem("token"),
  user: JSON.parse(sessionStorage.getItem("user") || "null"),
  torneos: [],
  torneo: Number(sessionStorage.getItem("torneo")) || null,
  vista: null,
};
const esAdmin = () => state.user?.rol === "administrador";
const torneoActual = () => state.torneos.find((t) => t.id_torneo === state.torneo);

async function api(path, { method = "GET", body } = {}) {
  const res = await fetch(path, {
    method,
    headers: { "Content-Type": "application/json", ...(state.token ? { Authorization: `Bearer ${state.token}` } : {}) },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  if (res.status === 401 && path !== "/api/auth/login") { logout(); throw new Error("Sesión expirada"); }
  if (res.status === 204) return null;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.detail || `Error ${res.status}`);
  return data;
}

function toast(msg, err = false) {
  const t = $("#toast");
  t.textContent = msg;
  t.className = "toast show" + (err ? " err" : "");
  clearTimeout(toast._t);
  toast._t = setTimeout(() => (t.className = "toast"), err ? 5000 : 2500);
}
async function intentar(fn, okMsg) {
  try { const r = await fn(); if (okMsg) toast(okMsg); return r; }
  catch (e) { toast(e.message, true); throw e; }
}

function ciValida(ci) {
  ci = String(ci).replace(/[.\-\s]/g, "");
  if (!/^\d{7,8}$/.test(ci)) return false;
  const base = ci.slice(0, -1).padStart(7, "0");
  const s = [...base].reduce((acc, d, i) => acc + Number(d) * [2, 9, 8, 7, 6, 3, 4][i], 0);
  return (10 - (s % 10)) % 10 === Number(ci.at(-1));
}
const VALIDADORES = {
  ci: (v) => (ciValida(v) ? "" : "Cédula inválida (7 u 8 dígitos y dígito verificador correcto)"),
  edad: (v) => {
    const n = new Date(v), h = new Date();
    let e = h.getFullYear() - n.getFullYear();
    if (h < new Date(h.getFullYear(), n.getMonth(), n.getDate())) e--;
    return e >= 16 && e <= 90 ? "" : "El jugador debe tener entre 16 y 90 años";
  },
};

function formModal(titulo, campos, valores = {}, okText = "Guardar", error = "") {
  return new Promise((resolve) => {
    const dlg = $("#modal"), body = $("#modal-body"), form = $("#modal-form");
    $("#modal-title").textContent = titulo;
    $("#modal-ok").textContent = okText;
    $("#modal-error").textContent = error;
    form.classList.remove("validado");
    body.innerHTML = campos.map((c) => {
      const v = valores[c.name] ?? c.value ?? "";
      const attrs = [c.required !== false ? "required" : "", c.min != null ? `min="${c.min}"` : "", c.max != null ? `max="${c.max}"` : "",
        c.pattern ? `pattern="${c.pattern}"` : "", c.maxlength ? `maxlength="${c.maxlength}"` : "", c.readonly ? "readonly" : "",
        c.placeholder ? `placeholder="${esc(c.placeholder)}"` : 'placeholder=" "'].join(" ");
      if (c.type === "select")
        return `<label>${esc(c.label)}<select name="${c.name}" ${attrs}>${c.vacio ? `<option value="">${esc(c.vacio)}</option>` : ""}${c.options
          .map(([val, lab]) => `<option value="${esc(val)}" ${String(val) === String(v) ? "selected" : ""}>${esc(lab)}</option>`).join("")}</select></label>`;
      if (c.type === "checkbox")
        return `<label class="inline"><input type="checkbox" name="${c.name}" ${v ? "checked" : ""}> ${esc(c.label)}</label>`;
      if (c.type === "textarea")
        return `<label>${esc(c.label)}<textarea name="${c.name}" rows="3" ${c.maxlength ? `maxlength="${c.maxlength}"` : ""}>${esc(v)}</textarea></label>`;
      return `<label>${esc(c.label)}<input name="${c.name}" type="${c.type || "text"}" value="${esc(v)}" ${attrs}>${c.hint ? `<small class="muted">${esc(c.hint)}</small>` : ""}</label>`;
    }).join("");

    const cerrar = (val) => { dlg.close(); form.onsubmit = null; $("#modal-cancel").onclick = null; resolve(val); };
    $("#modal-cancel").onclick = () => cerrar(null);
    dlg.oncancel = (e) => { e.preventDefault(); cerrar(null); };
    form.onsubmit = (ev) => {
      ev.preventDefault();
      const datos = {};
      for (const c of campos) {
        const el = form.elements[c.name];
        el.setCustomValidity("");
        let v = c.type === "checkbox" ? el.checked : el.value.trim();
        if (c.validar && v !== "") el.setCustomValidity(VALIDADORES[c.validar](v));
        if (c.type === "number" && v !== "") v = Number(v);
        if (v === "" && c.required === false) v = null;
        datos[c.name] = v;
      }
      if (!form.checkValidity()) {
        form.classList.add("validado");
        const inv = [...form.elements].find((e) => !e.checkValidity());
        $("#modal-error").textContent = `${inv.closest("label")?.firstChild?.textContent?.trim() || "Campo"}: ${inv.validationMessage}`;
        inv.focus();
        return;
      }
      cerrar(datos);
    };
    dlg.showModal();
  });
}
const confirmar = (msg) => formModal(msg, [], {}, "Confirmar").then((r) => r !== null);

async function guardarConModal(titulo, campos, valores, accion) {
  let v = valores, error = "";
  while (true) {
    const datos = await formModal(titulo, campos, v, "Guardar", error);
    if (!datos) return null;

    try { const r = await accion(datos); toast("Guardado"); return r; }
    catch (e) { v = datos; error = e.message; }
  }
}

function tabla(cols, filas, acciones) {
  if (!filas.length) return `<div class="table-wrap"><div class="empty">Sin datos</div></div>`;
  return `<div class="table-wrap"><table><thead><tr>${cols.map((c) => `<th class="${c.num ? "num" : ""}">${esc(c.t)}</th>`).join("")}${acciones ? "<th></th>" : ""}</tr></thead><tbody>${filas
    .map((f, i) => `<tr>${cols.map((c) => `<td class="${c.num ? "num" : ""}${c.wrap ? " wrap" : ""}">${c.html ? c.html(f) : esc(f[c.k])}</td>`).join("")}${acciones ? `<td class="acc">${acciones(f, i)}</td>` : ""}</tr>`).join("")}</tbody></table></div>`;
}

const ETIQUETAS = { inscripcion: "inscripción", sintetico: "sintético", "acumulacion de amarillas": "acumulación de amarillas" };
const mostrar = (v) => ETIQUETAS[v] ?? v;
const badge = (txt) => `<span class="badge b-${esc(String(txt).split(" ")[0])}">${esc(mostrar(txt))}</span>`;
const fmtDia = (d) => (d ? new Date(d + "T12:00").toLocaleDateString("es-UY", { weekday: "short", day: "2-digit", month: "2-digit" }) : "");

function bindAcciones(root, handlers) {
  root.onclick = (ev) => {
    const b = ev.target.closest("[data-act]");
    if (b && handlers[b.dataset.act]) handlers[b.dataset.act](b.dataset, b);
  };
}

const VISTAS = {
  partidos: { t: "Partidos", roles: ["administrador", "planillero"], render: vistaPartidos },
  equipos: { t: "Equipos y planteles", render: vistaEquipos },
  jugadores: { t: "Jugadores", render: vistaJugadores },
  sanciones: { t: "Sanciones", render: vistaSanciones },
  reportes: { t: "Reportes", render: vistaReportes },
  torneos: { t: "Ediciones", render: vistaTorneos },
  complejos: { t: "Complejos y canchas", render: vistaComplejos },
  facultades: { t: "Facultades", render: vistaFacultades },
  usuarios: { t: "Usuarios", render: vistaUsuarios },
};

function irA(nombre) {
  state.vista = nombre;
  document.querySelectorAll("#nav button").forEach((b) => b.classList.toggle("active", b.dataset.v === nombre));
  const v = $("#view");
  v.onclick = null;
  v.innerHTML = `<p class="muted">Cargando…</p>`;
  VISTAS[nombre].render(v).catch((e) => (v.innerHTML = `<p class="error">${esc(e.message)}</p>`));
}

async function vistaPartidos(v, filtroFecha = "") {
  if (!state.torneo) { v.innerHTML = `<p class="muted">No hay ediciones creadas.</p>`; return; }
  const ps = await api(`/api/partidos?id_torneo=${state.torneo}`);
  const fechas = [...new Set(ps.map((p) => p.numero_fecha))].sort((a, b) => a - b);
  const vis = filtroFecha ? ps.filter((p) => p.numero_fecha === Number(filtroFecha)) : ps;
  v.innerHTML = `
    <h2>Partidos · ${esc(torneoActual()?.nombre)}</h2>
    <div class="toolbar">
      <label>Fecha <select id="f-fecha"><option value="">Todas</option>${fechas.map((f) => `<option ${String(f) === String(filtroFecha) ? "selected" : ""}>${f}</option>`).join("")}</select></label>
      <span class="grow"></span>
      ${esAdmin() ? `<button class="btn primary" data-act="nuevo">+ Programar partido</button>` : ""}
    </div>
    ${tabla([
      { t: "Fecha", k: "numero_fecha", num: true },
      { t: "Día", html: (p) => fmtDia(p.dia) },
      { t: "Turno", html: (p) => `<span class="mono">${p.hora_inicio}</span>` },
      { t: "Cancha", wrap: true, html: (p) => `${esc(p.complejo)} · ${esc(p.nombre_cancha)}` },
      { t: "Local", k: "equipo_local" },
      { t: "", html: (p) => (p.estado === "jugado" || p.en_planilla ? `<span class="score">${p.goles_local}–${p.goles_visitante}</span>` : "vs") },
      { t: "Visitante", k: "equipo_visitante" },
      { t: "Estado", html: (p) => badge(p.estado) },
    ], vis, (p) => `
      ${p.estado === "programado" || p.estado === "jugado" ? `<button class="btn sm" data-act="planilla" data-id="${p.id_partido}">Planilla</button>` : ""}
      ${esAdmin() && ["programado", "postergado"].includes(p.estado) ? `<button class="btn sm" data-act="editar" data-id="${p.id_partido}">Editar</button>` : ""}
      ${esAdmin() && p.estado !== "jugado" && !p.en_planilla ? `<button class="btn sm danger" data-act="borrar" data-id="${p.id_partido}">Eliminar</button>` : ""}`)}`;
  $("#f-fecha").onchange = (e) => vistaPartidos(v, e.target.value);
  const porId = (id) => ps.find((p) => p.id_partido === Number(id));
  bindAcciones(v, {
    nuevo: () => formPartido(null, Math.max(0, ...fechas) || 1).then((r) => r && vistaPartidos(v, filtroFecha)),
    editar: (d) => formPartido(porId(d.id)).then((r) => r && vistaPartidos(v, filtroFecha)),
    planilla: (d) => vistaPlanilla(v, Number(d.id)),
    borrar: async (d) => {
      if (await confirmar("¿Eliminar el partido?")) { await intentar(() => api(`/api/partidos/${d.id}`, { method: "DELETE" }), "Partido eliminado"); vistaPartidos(v, filtroFecha); }
    },
  });
}

async function formPartido(p, fechaSugerida) {
  const [equipos, turnos, complejos] = await Promise.all([
    api(`/api/equipos?id_torneo=${state.torneo}`), api("/api/turnos"), api("/api/complejos")]);
  const t = torneoActual();
  const canchas = complejos.flatMap((c) => c.canchas.map((k) => [`${c.id_complejo}|${k.nombre_cancha}`,
    `${c.nombre} · ${k.nombre_cancha} (${mostrar(k.superficie)}${k.techada ? ", techada" : ""})`]));
  const eq = equipos.map((e) => [e.id_equipo, `${e.nombre} (${e.jugadores} jug.)`]);
  const campos = [
    { name: "numero_fecha", label: "Número de fecha", type: "number", min: 1, max: 50 },
    { name: "id_equipo_local", label: "Equipo local", type: "select", options: eq, vacio: "Elegí…" },
    { name: "id_equipo_visitante", label: "Equipo visitante", type: "select", options: eq, vacio: "Elegí…" },
    { name: "dia", label: "Día", type: "date", min: t.fecha_inicio, max: t.fecha_fin },
    { name: "id_turno", label: "Turno", type: "select", options: turnos.map((x) => [x.id_turno, `${x.hora_inicio} a ${x.hora_fin}`]) },
    { name: "cancha", label: "Cancha", type: "select", options: canchas, vacio: "Elegí…" },
    { name: "estado", label: "Estado", type: "select", options: [["programado", "programado"], ["postergado", "postergado"], ["cancelado", "cancelado"]] },
  ];
  const val = p ? { ...p, cancha: `${p.id_complejo}|${p.nombre_cancha}` } : { numero_fecha: fechaSugerida, estado: "programado" };
  return guardarConModal(p ? "Editar partido" : "Programar partido", campos, val, (d) => {
    if (d.id_equipo_local === d.id_equipo_visitante) throw new Error("Un equipo no puede enfrentarse a sí mismo");
    const [id_complejo, nombre_cancha] = d.cancha.split("|");
    const body = { ...d, id_torneo: state.torneo, id_equipo_local: +d.id_equipo_local, id_equipo_visitante: +d.id_equipo_visitante,
      id_turno: +d.id_turno, id_complejo: +id_complejo, nombre_cancha };
    delete body.cancha;
    return p ? api(`/api/partidos/${p.id_partido}`, { method: "PUT", body }) : api("/api/partidos", { method: "POST", body });
  });
}

async function vistaPlanilla(v, id) {
  const d = await api(`/api/partidos/${id}/planilla`);
  const p = d.partido;
  const enPlanilla = d.equipos.flatMap((e) => e.plantel.filter((j) => j.en_planilla).map((j) => ({ ...j, eq: e.nombre })));
  const editable = p.editable_planilla && p.estado !== "cancelado" && p.estado !== "postergado";
  const nombreEq = (idEq) => d.equipos.find((e) => e.id_equipo === idEq)?.nombre;
  const opcJug = enPlanilla.map((j) => `<option value="${j.ci}">${esc(j.eq)} · #${j.numero_camiseta} ${esc(j.nombre)} ${esc(j.apellido)}</option>`).join("");

  let aviso = "";
  if (!p.ya_paso) aviso = `<div class="aviso warn">El partido todavía no se jugó (termina ${esc(p.fin)}). La planilla se habilita al finalizar el turno.</div>`;
  else if (!editable) aviso = `<div class="aviso warn">Pasaron más de 48 h desde el partido: la planilla y el resultado quedan cerrados.</div>`;
  else aviso = `<div class="aviso ok">Planilla abierta: se puede cargar o corregir hasta 48 h después del partido.${p.estado === "jugado" ? " El partido ya figura como jugado." : ""}</div>`;

  v.innerHTML = `
    <div class="toolbar"><button class="btn" data-act="volver">← Partidos</button><span class="grow"></span>
      ${p.estado === "programado" && editable ? `<button class="btn primary" data-act="jugado">Marcar como jugado</button>` : ""}</div>
    <div class="marcador"><div class="eq">${esc(p.equipo_local)}</div><div class="res">${p.goles_local} – ${p.goles_visitante}</div><div class="eq">${esc(p.equipo_visitante)}</div>
      <div class="muted" style="width:100%">Fecha ${p.numero_fecha} · ${fmtDia(p.dia)} ${p.hora_inicio} · ${esc(p.complejo)} – ${esc(p.nombre_cancha)} · ${badge(p.estado)}</div></div>
    ${aviso}
    <div class="grid2">
      ${d.equipos.map((e) => `<div class="card"><h3>${esc(e.nombre)} <span class="muted">(${e.lado})</span></h3>
        <div class="plantel-list">${e.plantel.map((j) => `
          <label class="${j.suspendido ? "off" : ""}"><input type="checkbox" data-act="toggle" data-ci="${j.ci}" data-eq="${e.id_equipo}"
            ${j.en_planilla ? "checked" : ""} ${!editable || (j.suspendido && !j.en_planilla) ? "disabled" : ""}>
            <span class="camiseta">${j.numero_camiseta}</span> ${esc(j.nombre)} ${esc(j.apellido)} ${j.suspendido ? `<span class="badge b-susp">suspendido</span>` : ""}</label>`).join("")}
        </div></div>`).join("")}
    </div>
    <div class="grid2" style="margin-top:1rem">
      <div class="card"><h3>Goles</h3>
        ${editable && enPlanilla.length ? `<div class="evento-form"><label>Jugador<select id="g-ci">${opcJug}</select></label>
          <label>Minuto<input id="g-min" type="number" min="0" max="60" required></label>
          <label class="inline"><input id="g-ag" type="checkbox"> en contra</label>
          <button class="btn primary" data-act="gol">Agregar</button></div>` : ""}
        ${tabla([{ t: "Min", k: "minuto", num: true }, { t: "Jugador", html: (g) => `${esc(g.nombre)} ${esc(g.apellido)}${g.autogol ? " <span class='badge b-cancelado'>en contra</span>" : ""}` },
          { t: "Equipo", html: (g) => esc(nombreEq(g.id_equipo)) }], d.goles,
          (g) => (editable ? `<button class="btn sm danger" data-act="borrar-gol" data-id="${g.id_gol}">✕</button>` : ""))}
      </div>
      <div class="card"><h3>Tarjetas</h3>
        ${editable && enPlanilla.length ? `<div class="evento-form"><label>Jugador<select id="t-ci">${opcJug}</select></label>
          <label>Minuto<input id="t-min" type="number" min="0" max="60" required></label>
          <label>Color<select id="t-color"><option value="amarilla">Amarilla</option><option value="roja">Roja</option></select></label>
          <button class="btn primary" data-act="tarjeta">Agregar</button></div>` : ""}
        ${tabla([{ t: "Min", k: "minuto", num: true }, { t: "Jugador", html: (t) => `<span class="${t.color === "roja" ? "card-r" : "card-y"}"></span>${esc(t.nombre)} ${esc(t.apellido)}` },
          { t: "Equipo", html: (t) => esc(nombreEq(t.id_equipo)) }], d.tarjetas,
          (t) => (editable ? `<button class="btn sm danger" data-act="borrar-tarjeta" data-id="${t.id_tarjeta}">✕</button>` : ""))}
        <p class="muted" style="font-size:.85rem">Roja o 3 amarillas en la edición = 1 fecha de suspensión automática (fecha siguiente).</p>
      </div>
    </div>`;

  const recargar = () => vistaPlanilla(v, id);
  const minuto = (sel) => {
    const el = $(sel, v), n = Number(el.value);
    if (el.value === "" || !Number.isInteger(n) || n < 0 || n > 60) { toast("El minuto debe ser un entero entre 0 y 60", true); el.focus(); return null; }
    return n;
  };
  bindAcciones(v, {
    volver: () => irA("partidos"),
    toggle: async (ds, el) => {
      try {
        if (el.checked) await api(`/api/partidos/${id}/planilla`, { method: "POST", body: { ci_jugador: ds.ci, id_equipo: +ds.eq } });
        else await api(`/api/partidos/${id}/planilla/${ds.ci}`, { method: "DELETE" });
      } catch (e) { toast(e.message, true); }
      recargar();
    },
    gol: async () => {
      const m = minuto("#g-min"); if (m === null) return;
      await intentar(() => api(`/api/partidos/${id}/goles`, { method: "POST", body: { ci_jugador: $("#g-ci", v).value, minuto: m, autogol: $("#g-ag", v).checked } }), "Gol registrado").catch(() => {});
      recargar();
    },
    tarjeta: async () => {
      const m = minuto("#t-min"); if (m === null) return;
      await intentar(() => api(`/api/partidos/${id}/tarjetas`, { method: "POST", body: { ci_jugador: $("#t-ci", v).value, minuto: m, color: $("#t-color", v).value } }), "Tarjeta registrada").catch(() => {});
      recargar();
    },
    "borrar-gol": async (ds) => { await intentar(() => api(`/api/goles/${ds.id}`, { method: "DELETE" })).catch(() => {}); recargar(); },
    "borrar-tarjeta": async (ds) => { await intentar(() => api(`/api/tarjetas/${ds.id}`, { method: "DELETE" })).catch(() => {}); recargar(); },
    jugado: async () => {
      if (!(await confirmar(`¿Confirmar resultado ${p.goles_local}–${p.goles_visitante} y marcar como jugado?`))) return;
      await intentar(() => api(`/api/partidos/${id}/estado`, { method: "PATCH", body: { estado: "jugado" } }), "Partido marcado como jugado").catch(() => {});
      recargar();
    },
  });
}

async function vistaEquipos(v) {
  const [equipos, facultades] = await Promise.all([api(`/api/equipos?id_torneo=${state.torneo}`), api("/api/facultades")]);
  const t = torneoActual();
  const inscripcion = t.estado === "inscripcion";
  v.innerHTML = `<h2>Equipos · ${esc(t.nombre)}</h2>
    ${!inscripcion ? `<div class="aviso warn">La edición está "${esc(mostrar(t.estado))}": los planteles ya no pueden modificarse.</div>` : ""}
    <div class="toolbar"><span class="grow"></span>${inscripcion ? `<button class="btn primary" data-act="nuevo">+ Inscribir equipo</button>` : ""}</div>
    ${tabla([{ t: "Equipo", k: "nombre" }, { t: "Facultad", k: "facultad" }, { t: "Capitán", html: (e) => esc(e.capitan || "—") },
      { t: "Jugadores", html: (e) => `${e.jugadores}/10 ${e.jugadores < 5 ? `<span class="badge b-cancelado">mín. 5</span>` : ""}`, num: true }],
      equipos, (e) => `<button class="btn sm" data-act="plantel" data-id="${e.id_equipo}">Plantel</button>
        <button class="btn sm" data-act="editar" data-id="${e.id_equipo}">Editar</button>
        ${inscripcion ? `<button class="btn sm danger" data-act="borrar" data-id="${e.id_equipo}">Eliminar</button>` : ""}`)}`;
  const fac = facultades.map((f) => [f.id_facultad, f.nombre]);
  bindAcciones(v, {
    nuevo: async () => {
      const r = await guardarConModal("Inscribir equipo", [
        { name: "nombre", label: "Nombre", minlength: 2, maxlength: 60 },
        { name: "id_facultad", label: "Facultad que representa", type: "select", options: fac, vacio: "Elegí…" }], {},
        (d) => api("/api/equipos", { method: "POST", body: { ...d, id_facultad: +d.id_facultad, id_torneo: state.torneo } }));
      if (r) vistaPlantel(v, r.id_equipo);
    },
    editar: async (ds) => {
      const e = await api(`/api/equipos/${ds.id}`);
      const r = await guardarConModal("Editar equipo", [
        { name: "nombre", label: "Nombre", maxlength: 60 },
        { name: "id_facultad", label: "Facultad", type: "select", options: fac },
        { name: "ci_capitan", label: "Capitán (debe ser del plantel)", type: "select", required: false, vacio: "Sin capitán",
          options: e.plantel.map((j) => [j.ci, `#${j.numero_camiseta} ${j.nombre} ${j.apellido}`]) }], e,
        (d) => api(`/api/equipos/${ds.id}`, { method: "PUT", body: { ...d, id_facultad: +d.id_facultad } }));
      if (r) vistaEquipos(v);
    },
    plantel: (ds) => vistaPlantel(v, Number(ds.id)),
    borrar: async (ds) => {
      if (await confirmar("¿Eliminar el equipo y su plantel?")) { await intentar(() => api(`/api/equipos/${ds.id}`, { method: "DELETE" }), "Equipo eliminado").catch(() => {}); vistaEquipos(v); }
    },
  });
}

async function vistaPlantel(v, id) {
  const e = await api(`/api/equipos/${id}`);
  const editable = e.estado_torneo === "inscripcion";
  const disp = editable ? await api(`/api/equipos/${id}/disponibles`) : [];
  const docFun = e.plantel.filter((j) => ["docente", "funcionario"].includes(j.tipo)).length;
  v.innerHTML = `<div class="toolbar"><button class="btn" data-act="volver">← Equipos</button></div>
    <h2>${esc(e.nombre)} <span class="muted">· ${esc(e.facultad)}</span></h2>
    <p class="muted">${e.plantel.length}/10 jugadores (mínimo 5) · docentes/funcionarios: ${docFun}/2 · capitán: ${esc(e.capitan || "sin asignar")}</p>
    ${editable && e.plantel.length < 10 ? `<div class="card evento-form">
      <label>Jugador de ${esc(e.facultad)}<select id="p-ci">${disp.map((j) => `<option value="${j.ci}">${esc(j.apellido)}, ${esc(j.nombre)} · ${j.tipo}</option>`).join("")}</select></label>
      <label>Camiseta<input id="p-num" type="number" min="1" max="99"></label>
      <button class="btn primary" data-act="agregar" ${disp.length ? "" : "disabled"}>Agregar al plantel</button>
      ${disp.length ? "" : `<span class="muted">No quedan jugadores libres de esta facultad.</span>`}</div><br>` : ""}
    ${tabla([{ t: "#", k: "numero_camiseta", num: true }, { t: "Jugador", html: (j) => `${esc(j.nombre)} ${esc(j.apellido)} ${j.es_capitan ? badge("capitán") : ""}` },
      { t: "CI", html: (j) => `<span class="mono">${j.ci}</span>` }, { t: "Tipo", k: "tipo" }], e.plantel,
      editable ? (j) => `<button class="btn sm" data-act="cap" data-ci="${j.ci}" ${j.es_capitan ? "disabled" : ""}>Hacer capitán</button>
        <button class="btn sm" data-act="num" data-ci="${j.ci}" data-n="${j.numero_camiseta}">Camiseta</button>
        <button class="btn sm danger" data-act="quitar" data-ci="${j.ci}">Quitar</button>` : null)}`;
  const recargar = () => vistaPlantel(v, id);
  bindAcciones(v, {
    volver: () => irA("equipos"),
    agregar: async () => {
      const n = Number($("#p-num", v).value);
      if (!Number.isInteger(n) || n < 1 || n > 99) return toast("Número de camiseta entre 1 y 99", true);
      await intentar(() => api(`/api/equipos/${id}/plantel`, { method: "POST", body: { ci_jugador: $("#p-ci", v).value, numero_camiseta: n } }), "Jugador agregado").catch(() => {});
      recargar();
    },
    cap: async (ds) => {
      await intentar(() => api(`/api/equipos/${id}`, { method: "PUT", body: { nombre: e.nombre, id_facultad: e.id_facultad, ci_capitan: ds.ci } }), "Capitán asignado").catch(() => {});
      recargar();
    },
    num: async (ds) => {
      const r = await guardarConModal("Número de camiseta", [{ name: "numero_camiseta", label: "Número", type: "number", min: 1, max: 99 }],
        { numero_camiseta: ds.n }, (d) => api(`/api/equipos/${id}/plantel/${ds.ci}`, { method: "PUT", body: d }));
      if (r) recargar();
    },
    quitar: async (ds) => { await intentar(() => api(`/api/equipos/${id}/plantel/${ds.ci}`, { method: "DELETE" }), "Jugador quitado").catch(() => {}); recargar(); },
  });
}

async function vistaJugadores(v, filtro = {}) {
  const fac = await api("/api/facultades");
  const qs = new URLSearchParams(Object.entries(filtro).filter(([, x]) => x)).toString();
  const js = await api(`/api/jugadores${qs ? "?" + qs : ""}`);
  v.innerHTML = `<h2>Jugadores</h2>
    <div class="toolbar">
      <label>Facultad<select id="j-fac"><option value="">Todas</option>${fac.map((f) => `<option value="${f.id_facultad}" ${String(f.id_facultad) === String(filtro.id_facultad) ? "selected" : ""}>${esc(f.nombre)}</option>`).join("")}</select></label>
      <label>Buscar<input id="j-q" placeholder="nombre, apellido o CI" value="${esc(filtro.q || "")}"></label>
      <span class="grow"></span><button class="btn primary" data-act="nuevo">+ Nuevo jugador</button></div>
    ${tabla([{ t: "CI", html: (j) => `<span class="mono">${j.ci}</span>` }, { t: "Apellido", k: "apellido" }, { t: "Nombre", k: "nombre" },
      { t: "Facultad", k: "facultad" }, { t: "Tipo", k: "tipo" }, { t: "Email", k: "email" }, { t: "Nacimiento", k: "fecha_nacimiento" }], js,
      (j) => `<button class="btn sm" data-act="editar" data-ci="${j.ci}">Editar</button><button class="btn sm danger" data-act="borrar" data-ci="${j.ci}">Eliminar</button>`)}`;
  const recargar = () => vistaJugadores(v, { id_facultad: $("#j-fac", v).value, q: $("#j-q", v).value.trim() });
  $("#j-fac", v).onchange = recargar;
  $("#j-q", v).onkeydown = (e) => e.key === "Enter" && recargar();
  const campos = (edit) => [
    { name: "ci", label: "Cédula (sin puntos ni guion)", pattern: "\\d{7,8}", validar: "ci", readonly: edit, placeholder: "41234567" },
    { name: "nombre", label: "Nombre", maxlength: 60, pattern: ".{2,}" }, { name: "apellido", label: "Apellido", maxlength: 60, pattern: ".{2,}" },
    { name: "email", label: "Email", type: "email", maxlength: 120 },
    { name: "fecha_nacimiento", label: "Fecha de nacimiento", type: "date", validar: "edad" },
    { name: "id_facultad", label: "Facultad", type: "select", options: fac.map((f) => [f.id_facultad, f.nombre]), vacio: "Elegí…" },
    { name: "tipo", label: "Tipo", type: "select", options: ["grado", "posgrado", "docente", "funcionario"].map((x) => [x, x]) }];
  const porCi = (ci) => js.find((j) => j.ci === ci);
  bindAcciones(v, {
    nuevo: async () => (await guardarConModal("Nuevo jugador", campos(false), {}, (d) => api("/api/jugadores", { method: "POST", body: { ...d, id_facultad: +d.id_facultad } }))) && recargar(),
    editar: async (ds) => (await guardarConModal("Editar jugador", campos(true), porCi(ds.ci), (d) => api(`/api/jugadores/${ds.ci}`, { method: "PUT", body: { ...d, id_facultad: +d.id_facultad } }))) && recargar(),
    borrar: async (ds) => {
      if (await confirmar(`¿Eliminar a ${porCi(ds.ci).nombre} ${porCi(ds.ci).apellido}?`)) { await intentar(() => api(`/api/jugadores/${ds.ci}`, { method: "DELETE" }), "Jugador eliminado").catch(() => {}); recargar(); }
    },
  });
}

async function vistaSanciones(v) {
  const ss = await api(`/api/sanciones?id_torneo=${state.torneo}`);
  v.innerHTML = `<h2>Sanciones · ${esc(torneoActual().nombre)}</h2>
    <p class="muted">Las sanciones por roja y por 3 amarillas las genera automáticamente la base al registrar tarjetas. Acá se agregan las disciplinarias.</p>
    <div class="toolbar"><span class="grow"></span><button class="btn primary" data-act="nueva">+ Sanción disciplinaria</button></div>
    ${tabla([{ t: "Jugador", html: (s) => `${esc(s.nombre)} ${esc(s.apellido)}` }, { t: "Equipo", k: "equipo" }, { t: "Motivo", html: (s) => badge(s.motivo) },
      { t: "Fechas", html: (s) => (s.cantidad_fechas > 1 ? `${s.numero_fecha_inicio} a ${s.numero_fecha_fin}` : `${s.numero_fecha_inicio}`) },
      { t: "Cant.", k: "cantidad_fechas", num: true }, { t: "Observación", k: "observacion" }], ss,
      (s) => (s.motivo === "disciplinaria" ? `<button class="btn sm" data-act="editar" data-id="${s.id_sancion}">Editar</button><button class="btn sm danger" data-act="borrar" data-id="${s.id_sancion}">Eliminar</button>` : `<span class="muted">automática</span>`))}`;
  const campos = [{ name: "numero_fecha_inicio", label: "Desde la fecha", type: "number", min: 1, max: 50 },
    { name: "cantidad_fechas", label: "Cantidad de fechas", type: "number", min: 1, max: 20 },
    { name: "observacion", label: "Observación", type: "textarea", required: false, maxlength: 255 }];
  bindAcciones(v, {
    nueva: async () => {
      const equipos = await api(`/api/equipos?id_torneo=${state.torneo}`);
      const planteles = await Promise.all(equipos.map((e) => api(`/api/equipos/${e.id_equipo}`)));
      const opts = planteles.flatMap((e) => e.plantel.map((j) => [j.ci, `${e.nombre} · ${j.apellido}, ${j.nombre}`]));
      const r = await guardarConModal("Sanción disciplinaria", [{ name: "ci_jugador", label: "Jugador", type: "select", options: opts, vacio: "Elegí…" }, ...campos],
        { cantidad_fechas: 1 }, (d) => api("/api/sanciones", { method: "POST", body: { ...d, id_torneo: state.torneo } }));
      if (r) vistaSanciones(v);
    },
    editar: async (ds) => {
      const s = ss.find((x) => x.id_sancion === Number(ds.id));
      if (await guardarConModal("Editar sanción", campos, s, (d) => api(`/api/sanciones/${ds.id}`, { method: "PUT", body: d }))) vistaSanciones(v);
    },
    borrar: async (ds) => {
      if (await confirmar("¿Eliminar la sanción?")) { await intentar(() => api(`/api/sanciones/${ds.id}`, { method: "DELETE" }), "Sanción eliminada").catch(() => {}); vistaSanciones(v); }
    },
  });
}

async function vistaReportes(v, clave = "posiciones") {
  const lista = await api("/api/reportes");
  const r = await api(`/api/reportes/${clave}?id_torneo=${state.torneo}`);
  const cols = r.filas.length ? Object.keys(r.filas[0]).map((k) => ({ t: k.replaceAll("_", " "), k, num: typeof r.filas[0][k] === "number" })) : [];
  v.innerHTML = `<h2>Reportes · ${esc(torneoActual().nombre)}</h2>
    <div class="toolbar"><label class="grow">Reporte<select id="r-sel">${lista.map((x) => `<option value="${x.clave}" ${x.clave === clave ? "selected" : ""}>${esc(x.titulo)}</option>`).join("")}</select></label></div>
    <h3>${esc(r.titulo)}</h3>${tabla(cols, r.filas)}`;
  $("#r-sel", v).onchange = (e) => vistaReportes(v, e.target.value);
}

async function vistaTorneos(v) {
  const ts = await api("/api/torneos");
  v.innerHTML = `<h2>Ediciones del torneo</h2>
    <div class="toolbar"><span class="grow"></span><button class="btn primary" data-act="nuevo">+ Nueva edición</button></div>
    ${tabla([{ t: "Nombre", k: "nombre" }, { t: "Año", k: "anio", num: true }, { t: "Sem.", k: "semestre", num: true }, { t: "Inicio", k: "fecha_inicio" },
      { t: "Fin", k: "fecha_fin" }, { t: "Estado", html: (t) => badge(t.estado) }, { t: "Equipos", k: "equipos", num: true }, { t: "Partidos", k: "partidos", num: true }], ts,
      (t) => `${t.estado !== "finalizado" ? `<button class="btn sm" data-act="avanzar" data-id="${t.id_torneo}">${t.estado === "inscripcion" ? "Iniciar" : "Finalizar"}</button>` : ""}
        <button class="btn sm" data-act="editar" data-id="${t.id_torneo}">Editar</button>
        ${t.estado === "inscripcion" ? `<button class="btn sm danger" data-act="borrar" data-id="${t.id_torneo}">Eliminar</button>` : ""}`)}`;
  const anio = new Date().getFullYear();
  const campos = [{ name: "nombre", label: "Nombre", maxlength: 100, pattern: ".{3,}" },
    { name: "anio", label: "Año", type: "number", min: 2000, max: 2100 },
    { name: "semestre", label: "Semestre", type: "select", options: [[1, "1er semestre"], [2, "2º semestre"]] },
    { name: "fecha_inicio", label: "Inicio", type: "date" }, { name: "fecha_fin", label: "Fin", type: "date" }];
  const porId = (id) => ts.find((t) => t.id_torneo === Number(id));
  const guardar = (url, method) => (d) => {
    if (d.fecha_fin < d.fecha_inicio) throw new Error("La fecha de fin debe ser posterior a la de inicio");
    return api(url, { method, body: { ...d, semestre: +d.semestre } });
  };
  bindAcciones(v, {
    nuevo: async () => { if (await guardarConModal("Nueva edición", campos, { anio: anio + 1, semestre: 1 }, guardar("/api/torneos", "POST"))) { await cargarTorneos(); vistaTorneos(v); } },
    editar: async (ds) => { if (await guardarConModal("Editar edición", campos, porId(ds.id), guardar(`/api/torneos/${ds.id}`, "PUT"))) { await cargarTorneos(); vistaTorneos(v); } },
    avanzar: async (ds) => {
      const t = porId(ds.id), nuevo = t.estado === "inscripcion" ? "en curso" : "finalizado";
      if (!(await confirmar(`¿Pasar "${t.nombre}" a ${nuevo}? No se puede volver atrás.`))) return;
      await intentar(() => api(`/api/torneos/${ds.id}/estado`, { method: "PATCH", body: { estado: nuevo } }), "Estado actualizado").catch(() => {});
      await cargarTorneos(); vistaTorneos(v);
    },
    borrar: async (ds) => {
      if (await confirmar("¿Eliminar la edición?")) { await intentar(() => api(`/api/torneos/${ds.id}`, { method: "DELETE" }), "Edición eliminada").catch(() => {}); await cargarTorneos(); vistaTorneos(v); }
    },
  });
}

async function vistaComplejos(v) {
  const [cs, deptos] = await Promise.all([api("/api/complejos"), api("/api/departamentos")]);
  v.innerHTML = `<h2>Complejos deportivos y canchas</h2>
    <div class="toolbar"><span class="grow"></span><button class="btn primary" data-act="nuevo">+ Nuevo complejo</button></div>
    <div class="grid2">${cs.map((c) => `<div class="card">
      <div class="toolbar"><div class="grow"><h3 style="margin:0">${esc(c.nombre)}</h3><span class="muted">${esc(c.direccion)} · ${esc(c.departamento)}</span></div>
        <button class="btn sm" data-act="editar" data-id="${c.id_complejo}">Editar</button><button class="btn sm danger" data-act="borrar" data-id="${c.id_complejo}">Eliminar</button></div>
      ${tabla([{ t: "Cancha", k: "nombre_cancha" }, { t: "Superficie", html: (k) => esc(mostrar(k.superficie)) }, { t: "Techada", html: (k) => (k.techada ? "Sí" : "No") }], c.canchas,
        (k) => `<button class="btn sm" data-act="ed-cancha" data-id="${c.id_complejo}" data-n="${esc(k.nombre_cancha)}">Editar</button><button class="btn sm danger" data-act="bo-cancha" data-id="${c.id_complejo}" data-n="${esc(k.nombre_cancha)}">✕</button>`)}
      <br><button class="btn sm" data-act="nueva-cancha" data-id="${c.id_complejo}">+ Cancha</button></div>`).join("")}</div>`;
  const cc = [{ name: "nombre", label: "Nombre", maxlength: 100 }, { name: "direccion", label: "Dirección", maxlength: 150, pattern: ".{3,}" },
    { name: "departamento", label: "Departamento", type: "select", options: deptos.map((d) => [d, d]), value: "Montevideo" }];
  const ck = [{ name: "nombre_cancha", label: "Nombre de la cancha", maxlength: 50 },
    { name: "superficie", label: "Superficie", type: "select", options: [["sintetico", "sintético"], ["parquet", "parquet"]] },
    { name: "techada", label: "Techada", type: "checkbox" }];
  const porId = (id) => cs.find((c) => c.id_complejo === Number(id));
  const rec = (r) => r && vistaComplejos(v);
  bindAcciones(v, {
    nuevo: async () => rec(await guardarConModal("Nuevo complejo", cc, {}, (d) => api("/api/complejos", { method: "POST", body: d }))),
    editar: async (ds) => rec(await guardarConModal("Editar complejo", cc, porId(ds.id), (d) => api(`/api/complejos/${ds.id}`, { method: "PUT", body: d }))),
    borrar: async (ds) => { if (await confirmar("¿Eliminar el complejo y sus canchas?")) { await intentar(() => api(`/api/complejos/${ds.id}`, { method: "DELETE" }), "Complejo eliminado").catch(() => {}); vistaComplejos(v); } },
    "nueva-cancha": async (ds) => rec(await guardarConModal("Nueva cancha", ck, {}, (d) => api(`/api/complejos/${ds.id}/canchas`, { method: "POST", body: d }))),
    "ed-cancha": async (ds) => rec(await guardarConModal("Editar cancha", ck, porId(ds.id).canchas.find((k) => k.nombre_cancha === ds.n),
      (d) => api(`/api/complejos/${ds.id}/canchas/${encodeURIComponent(ds.n)}`, { method: "PUT", body: d }))),
    "bo-cancha": async (ds) => { if (await confirmar(`¿Eliminar la cancha ${ds.n}?`)) { await intentar(() => api(`/api/complejos/${ds.id}/canchas/${encodeURIComponent(ds.n)}`, { method: "DELETE" }), "Cancha eliminada").catch(() => {}); vistaComplejos(v); } },
  });
}

async function vistaFacultades(v) {
  const fs = await api("/api/facultades");
  v.innerHTML = `<h2>Facultades</h2><div class="toolbar"><span class="grow"></span><button class="btn primary" data-act="nueva">+ Nueva facultad</button></div>
    ${tabla([{ t: "Nombre", k: "nombre" }, { t: "Jugadores", k: "jugadores", num: true }], fs,
      (f) => `<button class="btn sm" data-act="editar" data-id="${f.id_facultad}">Editar</button><button class="btn sm danger" data-act="borrar" data-id="${f.id_facultad}">Eliminar</button>`)}`;
  const c = [{ name: "nombre", label: "Nombre", maxlength: 100, pattern: ".{2,}" }];
  bindAcciones(v, {
    nueva: async () => (await guardarConModal("Nueva facultad", c, {}, (d) => api("/api/facultades", { method: "POST", body: d }))) && vistaFacultades(v),
    editar: async (ds) => (await guardarConModal("Editar facultad", c, fs.find((f) => f.id_facultad === +ds.id), (d) => api(`/api/facultades/${ds.id}`, { method: "PUT", body: d }))) && vistaFacultades(v),
    borrar: async (ds) => { if (await confirmar("¿Eliminar la facultad?")) { await intentar(() => api(`/api/facultades/${ds.id}`, { method: "DELETE" }), "Facultad eliminada").catch(() => {}); vistaFacultades(v); } },
  });
}

async function vistaUsuarios(v) {
  const us = await api("/api/usuarios");
  v.innerHTML = `<h2>Usuarios de la aplicación</h2><div class="toolbar"><span class="grow"></span><button class="btn primary" data-act="nuevo">+ Nuevo usuario</button></div>
    ${tabla([{ t: "Correo", k: "correo" }, { t: "Rol", html: (u) => badge(u.rol) }], us,
      (u) => (u.correo === state.user.correo ? `<span class="muted">vos</span>` : `<button class="btn sm danger" data-act="borrar" data-c="${esc(u.correo)}">Eliminar</button>`))}`;
  bindAcciones(v, {
    nuevo: async () => (await guardarConModal("Nuevo usuario", [{ name: "correo", label: "Correo", type: "email" },
      { name: "contrasena", label: "Contraseña (mín. 6)", type: "password", pattern: ".{6,}" },
      { name: "rol", label: "Rol", type: "select", options: [["planillero", "planillero"], ["administrador", "administrador"]] }], {},
      (d) => api("/api/usuarios", { method: "POST", body: d }))) && vistaUsuarios(v),
    borrar: async (ds) => { if (await confirmar(`¿Eliminar ${ds.c}?`)) { await intentar(() => api(`/api/usuarios/${encodeURIComponent(ds.c)}`, { method: "DELETE" }), "Usuario eliminado").catch(() => {}); vistaUsuarios(v); } },
  });
}

async function cargarTorneos() {
  state.torneos = await api("/api/torneos");
  if (!state.torneos.some((t) => t.id_torneo === state.torneo)) {
    state.torneo = (state.torneos.find((t) => t.estado === "en curso") || state.torneos[0])?.id_torneo ?? null;
  }
  const sel = $("#torneo-actual");
  sel.innerHTML = state.torneos.map((t) => `<option value="${t.id_torneo}" ${t.id_torneo === state.torneo ? "selected" : ""}>${esc(t.nombre)} · ${esc(mostrar(t.estado))}</option>`).join("");
}

async function iniciarApp() {
  $("#login").classList.add("hidden");
  $("#app").classList.remove("hidden");
  $("#user-info").textContent = `${state.user.correo} · ${state.user.rol}`;
  const vistas = Object.entries(VISTAS).filter(([, x]) => esAdmin() || (x.roles || []).includes(state.user.rol));
  $("#nav").innerHTML = vistas.map(([k, x]) => `<button data-v="${k}">${x.t}</button>`).join("");
  $("#nav").onclick = (e) => e.target.dataset.v && irA(e.target.dataset.v);
  await cargarTorneos();
  $("#torneo-actual").onchange = (e) => {
    state.torneo = Number(e.target.value);
    sessionStorage.setItem("torneo", state.torneo);
    irA(state.vista);
  };
  irA("partidos");
}

function logout() {
  sessionStorage.clear();
  state.token = state.user = null;
  $("#app").classList.add("hidden");
  $("#login").classList.remove("hidden");
}

$("#login-form").onsubmit = async (ev) => {
  ev.preventDefault();
  const f = ev.target;
  $("#login-error").textContent = "";
  if (!f.checkValidity()) { $("#login-error").textContent = "Ingresá un correo válido y la contraseña"; return; }
  try {
    const r = await api("/api/auth/login", { method: "POST", body: { correo: f.correo.value.trim(), contrasena: f.contrasena.value } });
    state.token = r.token;
    state.user = { correo: r.correo, rol: r.rol };
    sessionStorage.setItem("token", r.token);
    sessionStorage.setItem("user", JSON.stringify(state.user));
    iniciarApp();
  } catch (e) { $("#login-error").textContent = e.message; }
};
$("#logout").onclick = logout;

if (state.token && state.user) iniciarApp().catch(logout); else logout();
