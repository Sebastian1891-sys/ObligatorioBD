"""ABM de partidos y registro de planillas, goles y tarjetas."""
from fastapi import APIRouter, Depends, HTTPException

from ..schemas import GolIn, GolUpdate, PartidoEstado, PartidoIn, PlanillaIn, TarjetaIn, TarjetaUpdate
from ..security import db_admin, db_usuario, usuario_actual

router = APIRouter(prefix="/api", tags=["partidos"])

PARTIDO_SQL = """SELECT v.*, r.goles_local, r.goles_visitante,
                        (NOW() >= v.fin) AS ya_paso,
                        (NOW() BETWEEN v.fin AND v.fin + INTERVAL 48 HOUR) AS editable_planilla,
                        (SELECT COUNT(*) FROM planilla_partido pl WHERE pl.id_partido = v.id_partido) AS en_planilla
                   FROM v_partido v JOIN v_resultado r ON r.id_partido = v.id_partido"""


def _partido(db, id_partido):
    p = db.one_or_404(PARTIDO_SQL + " WHERE v.id_partido = %s", (id_partido,), "Partido")
    p["ya_paso"], p["editable_planilla"] = bool(p["ya_paso"]), bool(p["editable_planilla"])
    return p


@router.get("/partidos")
def partidos(id_torneo: int | None = None, numero_fecha: int | None = None, estado: str | None = None,
             db=Depends(db_usuario)):
    sql, params = PARTIDO_SQL + " WHERE 1=1", []
    for col, val in (("v.id_torneo", id_torneo), ("v.numero_fecha", numero_fecha), ("v.estado", estado)):
        if val is not None:
            sql += f" AND {col} = %s"          # col es fijo (no viene del usuario)
            params.append(val)
    rows = db.all(sql + " ORDER BY v.numero_fecha, v.dia, v.hora_inicio, v.complejo", params)
    for r in rows:
        r["ya_paso"], r["editable_planilla"] = bool(r["ya_paso"]), bool(r["editable_planilla"])
    return rows


@router.get("/partidos/{id_partido}")
def partido(id_partido: int, db=Depends(db_usuario)):
    return _partido(db, id_partido)


@router.post("/partidos", status_code=201)
def crear_partido(data: PartidoIn, db=Depends(db_admin)):
    db.execute("""INSERT INTO partido (id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante,
                                       dia, id_turno, nombre_cancha, id_complejo, estado)
                  VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)""",
               (data.id_torneo, data.numero_fecha, data.id_equipo_local, data.id_equipo_visitante,
                data.dia, data.id_turno, data.nombre_cancha, data.id_complejo, data.estado))
    return _partido(db, db.lastrowid)


@router.put("/partidos/{id_partido}")
def editar_partido(id_partido: int, data: PartidoIn, db=Depends(db_admin)):
    db.one_or_404("SELECT 1 FROM partido WHERE id_partido = %s", (id_partido,), "Partido")
    db.execute("""UPDATE partido SET id_torneo=%s, numero_fecha=%s, id_equipo_local=%s, id_equipo_visitante=%s,
                         dia=%s, id_turno=%s, nombre_cancha=%s, id_complejo=%s, estado=%s
                   WHERE id_partido=%s""",
               (data.id_torneo, data.numero_fecha, data.id_equipo_local, data.id_equipo_visitante,
                data.dia, data.id_turno, data.nombre_cancha, data.id_complejo, data.estado, id_partido))
    return _partido(db, id_partido)


@router.patch("/partidos/{id_partido}/estado")
def cambiar_estado(id_partido: int, data: PartidoEstado, db=Depends(db_usuario), u=Depends(usuario_actual)):
    if u["rol"] == "planillero" and data.estado != "jugado":
        raise HTTPException(403, "El planillero solo puede marcar el partido como jugado")
    p = db.one_or_404("SELECT estado FROM partido WHERE id_partido = %s", (id_partido,), "Partido")
    if data.estado == "jugado" and not db.one(
            "SELECT 1 FROM planilla_partido WHERE id_partido = %s LIMIT 1", (id_partido,)):
        raise HTTPException(400, "Cargá la planilla antes de marcar el partido como jugado")
    if p["estado"] != data.estado:
        db.execute("UPDATE partido SET estado = %s WHERE id_partido = %s", (data.estado, id_partido))
    return _partido(db, id_partido)


@router.delete("/partidos/{id_partido}", status_code=204)
def borrar_partido(id_partido: int, db=Depends(db_admin)):
    db.one_or_404("SELECT 1 FROM partido WHERE id_partido = %s", (id_partido,), "Partido")
    if db.one("SELECT 1 FROM planilla_partido WHERE id_partido = %s LIMIT 1", (id_partido,)):
        raise HTTPException(409, "El partido tiene planilla cargada: no se puede eliminar")
    db.execute("DELETE FROM partido WHERE id_partido = %s", (id_partido,))


# ---------------------------------------------------------------- planilla
@router.get("/partidos/{id_partido}/planilla")
def ver_planilla(id_partido: int, db=Depends(db_usuario)):
    p = _partido(db, id_partido)
    equipos = []
    for lado, id_eq, nombre in (("local", p["id_equipo_local"], p["equipo_local"]),
                                ("visitante", p["id_equipo_visitante"], p["equipo_visitante"])):
        plantel = db.all("""SELECT j.ci, j.nombre, j.apellido, ejt.numero_camiseta,
                                   fn_jugador_suspendido(j.ci, %s, %s) AS suspendido,
                                   EXISTS (SELECT 1 FROM planilla_partido pl
                                            WHERE pl.id_partido = %s AND pl.ci_jugador = j.ci) AS en_planilla
                              FROM equipo_jugador_torneo ejt JOIN jugador j ON j.ci = ejt.ci_jugador
                             WHERE ejt.id_equipo = %s ORDER BY ejt.numero_camiseta""",
                         (p["id_torneo"], p["numero_fecha"], id_partido, id_eq))
        for j in plantel:
            j["suspendido"], j["en_planilla"] = bool(j["suspendido"]), bool(j["en_planilla"])
        equipos.append({"lado": lado, "id_equipo": id_eq, "nombre": nombre, "plantel": plantel})
    goles = db.all("""SELECT g.id_gol, g.ci_jugador, j.nombre, j.apellido, pl.id_equipo, g.minuto, g.autogol
                        FROM gol g JOIN jugador j ON j.ci = g.ci_jugador
                        JOIN planilla_partido pl ON pl.id_partido = g.id_partido AND pl.ci_jugador = g.ci_jugador
                       WHERE g.id_partido = %s ORDER BY g.minuto, g.id_gol""", (id_partido,))
    tarjetas = db.all("""SELECT t.id_tarjeta, t.ci_jugador, j.nombre, j.apellido, pl.id_equipo, t.minuto, t.color
                           FROM tarjeta t JOIN jugador j ON j.ci = t.ci_jugador
                           JOIN planilla_partido pl ON pl.id_partido = t.id_partido AND pl.ci_jugador = t.ci_jugador
                          WHERE t.id_partido = %s ORDER BY t.minuto, t.id_tarjeta""", (id_partido,))
    for g in goles:
        g["autogol"] = bool(g["autogol"])
    return {"partido": p, "equipos": equipos, "goles": goles, "tarjetas": tarjetas}


@router.post("/partidos/{id_partido}/planilla", status_code=201)
def agregar_a_planilla(id_partido: int, data: PlanillaIn, db=Depends(db_usuario)):
    db.one_or_404("SELECT 1 FROM partido WHERE id_partido = %s", (id_partido,), "Partido")
    db.execute("INSERT INTO planilla_partido (id_partido, ci_jugador, id_equipo) VALUES (%s, %s, %s)",
               (id_partido, data.ci_jugador, data.id_equipo))
    return {"ok": True}


@router.delete("/partidos/{id_partido}/planilla/{ci}", status_code=204)
def quitar_de_planilla(id_partido: int, ci: str, db=Depends(db_usuario)):
    if db.execute("DELETE FROM planilla_partido WHERE id_partido = %s AND ci_jugador = %s", (id_partido, ci)) == 0:
        raise HTTPException(404, "El jugador no está en la planilla")


# ---------------------------------------------------------------- goles
def _en_planilla(db, id_partido, ci):
    db.one_or_404("SELECT 1 FROM partido WHERE id_partido = %s", (id_partido,), "Partido")
    if not db.one("SELECT 1 FROM planilla_partido WHERE id_partido = %s AND ci_jugador = %s", (id_partido, ci)):
        raise HTTPException(400, "Solo pueden convertir goles o recibir tarjetas los jugadores que figuran en la planilla")


@router.post("/partidos/{id_partido}/goles", status_code=201)
def agregar_gol(id_partido: int, data: GolIn, db=Depends(db_usuario)):
    _en_planilla(db, id_partido, data.ci_jugador)
    db.execute("INSERT INTO gol (id_partido, ci_jugador, minuto, autogol) VALUES (%s, %s, %s, %s)",
               (id_partido, data.ci_jugador, data.minuto, data.autogol))
    return {"id_gol": db.lastrowid}


@router.put("/goles/{id_gol}")
def editar_gol(id_gol: int, data: GolUpdate, db=Depends(db_usuario)):
    db.one_or_404("SELECT 1 FROM gol WHERE id_gol = %s", (id_gol,), "Gol")
    db.execute("UPDATE gol SET minuto = %s, autogol = %s WHERE id_gol = %s", (data.minuto, data.autogol, id_gol))
    return {"ok": True}


@router.delete("/goles/{id_gol}", status_code=204)
def borrar_gol(id_gol: int, db=Depends(db_usuario)):
    if db.execute("DELETE FROM gol WHERE id_gol = %s", (id_gol,)) == 0:
        raise HTTPException(404, "Gol no encontrado")


# ---------------------------------------------------------------- tarjetas
@router.post("/partidos/{id_partido}/tarjetas", status_code=201)
def agregar_tarjeta(id_partido: int, data: TarjetaIn, db=Depends(db_usuario)):
    _en_planilla(db, id_partido, data.ci_jugador)
    db.execute("INSERT INTO tarjeta (id_partido, ci_jugador, minuto, color) VALUES (%s, %s, %s, %s)",
               (id_partido, data.ci_jugador, data.minuto, data.color))
    return {"id_tarjeta": db.lastrowid}


@router.put("/tarjetas/{id_tarjeta}")
def editar_tarjeta(id_tarjeta: int, data: TarjetaUpdate, db=Depends(db_usuario)):
    db.one_or_404("SELECT 1 FROM tarjeta WHERE id_tarjeta = %s", (id_tarjeta,), "Tarjeta")
    db.execute("UPDATE tarjeta SET minuto = %s, color = %s WHERE id_tarjeta = %s", (data.minuto, data.color, id_tarjeta))
    return {"ok": True}


@router.delete("/tarjetas/{id_tarjeta}", status_code=204)
def borrar_tarjeta(id_tarjeta: int, db=Depends(db_usuario)):
    if db.execute("DELETE FROM tarjeta WHERE id_tarjeta = %s", (id_tarjeta,)) == 0:
        raise HTTPException(404, "Tarjeta no encontrada")
