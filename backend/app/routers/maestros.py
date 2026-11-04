"""ABM de facultades, jugadores, complejos, canchas y consulta de turnos."""
from fastapi import APIRouter, Depends, HTTPException

from ..schemas import CanchaIn, ComplejoIn, DEPARTAMENTOS, FacultadIn, JugadorIn
from ..security import db_admin, db_usuario

router = APIRouter(prefix="/api", tags=["maestros"])


# ---------------------------------------------------------------- facultades
@router.get("/facultades")
def facultades(db=Depends(db_usuario)):
    return db.all("""SELECT f.id_facultad, f.nombre, COUNT(j.ci) AS jugadores
                       FROM facultad f LEFT JOIN jugador j ON j.id_facultad = f.id_facultad
                      GROUP BY f.id_facultad, f.nombre ORDER BY f.nombre""")


@router.post("/facultades", status_code=201)
def crear_facultad(data: FacultadIn, db=Depends(db_admin)):
    db.execute("INSERT INTO facultad (nombre) VALUES (%s)", (data.nombre,))
    return {"id_facultad": db.lastrowid, "nombre": data.nombre}


@router.put("/facultades/{id_facultad}")
def editar_facultad(id_facultad: int, data: FacultadIn, db=Depends(db_admin)):
    db.one_or_404("SELECT 1 FROM facultad WHERE id_facultad = %s", (id_facultad,), "Facultad")
    db.execute("UPDATE facultad SET nombre = %s WHERE id_facultad = %s", (data.nombre, id_facultad))
    return {"id_facultad": id_facultad, "nombre": data.nombre}


@router.delete("/facultades/{id_facultad}", status_code=204)
def borrar_facultad(id_facultad: int, db=Depends(db_admin)):
    if db.execute("DELETE FROM facultad WHERE id_facultad = %s", (id_facultad,)) == 0:
        raise HTTPException(404, "Facultad no encontrada")


# ---------------------------------------------------------------- turnos
@router.get("/turnos")
def turnos(db=Depends(db_usuario)):
    return db.all("SELECT id_turno, hora_inicio, hora_fin FROM turno ORDER BY hora_inicio")


@router.get("/departamentos")
def departamentos():
    return list(DEPARTAMENTOS)


# ---------------------------------------------------------------- jugadores
JUGADOR_SQL = """SELECT j.ci, j.nombre, j.apellido, j.email, j.fecha_nacimiento, j.id_facultad,
                        f.nombre AS facultad, j.tipo
                   FROM jugador j JOIN facultad f ON f.id_facultad = j.id_facultad"""


@router.get("/jugadores")
def jugadores(id_facultad: int | None = None, q: str | None = None, db=Depends(db_usuario)):
    sql, params = JUGADOR_SQL + " WHERE 1=1", []
    if id_facultad:
        sql += " AND j.id_facultad = %s"
        params.append(id_facultad)
    if q:
        sql += " AND (j.ci LIKE %s OR j.nombre LIKE %s OR j.apellido LIKE %s)"
        params += [f"%{q}%"] * 3
    return db.all(sql + " ORDER BY j.apellido, j.nombre", params)


@router.get("/jugadores/{ci}")
def jugador(ci: str, db=Depends(db_usuario)):
    j = db.one_or_404(JUGADOR_SQL + " WHERE j.ci = %s", (ci,), "Jugador")
    j["equipos"] = db.all("""SELECT e.id_equipo, e.nombre, t.nombre AS torneo, ejt.numero_camiseta
                               FROM equipo_jugador_torneo ejt JOIN equipo e ON e.id_equipo = ejt.id_equipo
                               JOIN torneo t ON t.id_torneo = ejt.id_torneo
                              WHERE ejt.ci_jugador = %s ORDER BY t.anio DESC, t.semestre DESC""", (ci,))
    return j


@router.post("/jugadores", status_code=201)
def crear_jugador(data: JugadorIn, db=Depends(db_admin)):
    db.execute("""INSERT INTO jugador (ci, nombre, apellido, email, fecha_nacimiento, id_facultad, tipo)
                  VALUES (%s, %s, %s, %s, %s, %s, %s)""",
               (data.ci, data.nombre, data.apellido, data.email.lower(), data.fecha_nacimiento,
                data.id_facultad, data.tipo))
    return db.one(JUGADOR_SQL + " WHERE j.ci = %s", (data.ci,))


@router.put("/jugadores/{ci}")
def editar_jugador(ci: str, data: JugadorIn, db=Depends(db_admin)):
    actual = db.one_or_404("SELECT id_facultad, tipo FROM jugador WHERE ci = %s", (ci,), "Jugador")
    if data.ci != ci:
        raise HTTPException(400, "La cédula no se modifica: dar de baja y alta de nuevo")
    # si integra un plantel, cambiar facultad o tipo podría romper las reglas del plantel
    if (data.id_facultad != actual["id_facultad"] or data.tipo != actual["tipo"]) and db.one(
            "SELECT 1 FROM equipo_jugador_torneo WHERE ci_jugador = %s", (ci,)):
        raise HTTPException(400, "El jugador integra un plantel: no se puede cambiar su facultad ni su tipo")
    db.execute("""UPDATE jugador SET nombre=%s, apellido=%s, email=%s, fecha_nacimiento=%s,
                  id_facultad=%s, tipo=%s WHERE ci=%s""",
               (data.nombre, data.apellido, data.email.lower(), data.fecha_nacimiento,
                data.id_facultad, data.tipo, ci))
    return db.one(JUGADOR_SQL + " WHERE j.ci = %s", (ci,))


@router.delete("/jugadores/{ci}", status_code=204)
def borrar_jugador(ci: str, db=Depends(db_admin)):
    if db.execute("DELETE FROM jugador WHERE ci = %s", (ci,)) == 0:
        raise HTTPException(404, "Jugador no encontrado")


# ---------------------------------------------------------------- complejos y canchas
@router.get("/complejos")
def complejos(db=Depends(db_usuario)):
    cs = db.all("SELECT id_complejo, nombre, direccion, departamento FROM complejo ORDER BY nombre")
    canchas = db.all("SELECT id_complejo, nombre_cancha, superficie, techada FROM cancha ORDER BY nombre_cancha")
    for c in cs:
        c["canchas"] = [{**k, "techada": bool(k["techada"])} for k in canchas if k["id_complejo"] == c["id_complejo"]]
    return cs


@router.post("/complejos", status_code=201)
def crear_complejo(data: ComplejoIn, db=Depends(db_admin)):
    db.execute("INSERT INTO complejo (nombre, direccion, departamento) VALUES (%s, %s, %s)",
               (data.nombre, data.direccion, data.departamento))
    return {"id_complejo": db.lastrowid, **data.model_dump()}


@router.put("/complejos/{id_complejo}")
def editar_complejo(id_complejo: int, data: ComplejoIn, db=Depends(db_admin)):
    db.one_or_404("SELECT 1 FROM complejo WHERE id_complejo = %s", (id_complejo,), "Complejo")
    db.execute("UPDATE complejo SET nombre=%s, direccion=%s, departamento=%s WHERE id_complejo=%s",
               (data.nombre, data.direccion, data.departamento, id_complejo))
    return {"id_complejo": id_complejo, **data.model_dump()}


@router.delete("/complejos/{id_complejo}", status_code=204)
def borrar_complejo(id_complejo: int, db=Depends(db_admin)):
    if db.one("SELECT 1 FROM partido WHERE id_complejo = %s LIMIT 1", (id_complejo,)):
        raise HTTPException(409, "El complejo tiene partidos asignados: no se puede eliminar")
    if db.execute("DELETE FROM complejo WHERE id_complejo = %s", (id_complejo,)) == 0:
        raise HTTPException(404, "Complejo no encontrado")


@router.post("/complejos/{id_complejo}/canchas", status_code=201)
def crear_cancha(id_complejo: int, data: CanchaIn, db=Depends(db_admin)):
    db.one_or_404("SELECT 1 FROM complejo WHERE id_complejo = %s", (id_complejo,), "Complejo")
    db.execute("INSERT INTO cancha (nombre_cancha, id_complejo, superficie, techada) VALUES (%s, %s, %s, %s)",
               (data.nombre_cancha, id_complejo, data.superficie, data.techada))
    return {"id_complejo": id_complejo, **data.model_dump()}


@router.put("/complejos/{id_complejo}/canchas/{nombre}")
def editar_cancha(id_complejo: int, nombre: str, data: CanchaIn, db=Depends(db_admin)):
    db.one_or_404("SELECT 1 FROM cancha WHERE id_complejo = %s AND nombre_cancha = %s",
                  (id_complejo, nombre), "Cancha")
    if data.nombre_cancha != nombre and db.one(
            "SELECT 1 FROM partido WHERE id_complejo = %s AND nombre_cancha = %s LIMIT 1", (id_complejo, nombre)):
        raise HTTPException(409, "La cancha tiene partidos: no se puede renombrar")
    db.execute("""UPDATE cancha SET nombre_cancha=%s, superficie=%s, techada=%s
                  WHERE id_complejo=%s AND nombre_cancha=%s""",
               (data.nombre_cancha, data.superficie, data.techada, id_complejo, nombre))
    return {"id_complejo": id_complejo, **data.model_dump()}


@router.delete("/complejos/{id_complejo}/canchas/{nombre}", status_code=204)
def borrar_cancha(id_complejo: int, nombre: str, db=Depends(db_admin)):
    if db.execute("DELETE FROM cancha WHERE id_complejo = %s AND nombre_cancha = %s", (id_complejo, nombre)) == 0:
        raise HTTPException(404, "Cancha no encontrada")
