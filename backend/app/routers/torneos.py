"""ABM de torneos (ediciones), equipos y planteles."""
from fastapi import APIRouter, Depends, HTTPException

from .. import reglas
from ..schemas import CamisetaIn, EquipoIn, EquipoUpdate, PlantelIn, TorneoEstado, TorneoIn
from ..security import db_admin, db_usuario

router = APIRouter(prefix="/api", tags=["torneos"])


# ---------------------------------------------------------------- torneos
TORNEO_SQL = """SELECT t.id_torneo, t.nombre, t.anio, t.semestre, t.fecha_inicio, t.fecha_fin, t.estado,
                       (SELECT COUNT(*) FROM equipo e WHERE e.id_torneo = t.id_torneo) AS equipos,
                       (SELECT COUNT(*) FROM partido p WHERE p.id_torneo = t.id_torneo) AS partidos
                  FROM torneo t"""


@router.get("/torneos")
def torneos(db=Depends(db_usuario)):
    return db.all(TORNEO_SQL + " ORDER BY t.anio DESC, t.semestre DESC")


@router.get("/torneos/{id_torneo}")
def torneo(id_torneo: int, db=Depends(db_usuario)):
    return db.one_or_404(TORNEO_SQL + " WHERE t.id_torneo = %s", (id_torneo,), "Torneo")


@router.post("/torneos", status_code=201)
def crear_torneo(data: TorneoIn, db=Depends(db_admin)):
    db.execute("""INSERT INTO torneo (nombre, anio, semestre, fecha_inicio, fecha_fin, estado)
                  VALUES (%s, %s, %s, %s, %s, 'inscripcion')""",
               (data.nombre, data.anio, data.semestre, data.fecha_inicio, data.fecha_fin))
    return db.one(TORNEO_SQL + " WHERE t.id_torneo = %s", (db.lastrowid,))


@router.put("/torneos/{id_torneo}")
def editar_torneo(id_torneo: int, data: TorneoIn, db=Depends(db_admin)):
    db.one_or_404("SELECT 1 FROM torneo WHERE id_torneo = %s", (id_torneo,), "Torneo")
    fuera = db.one("""SELECT 1 FROM partido WHERE id_torneo = %s AND dia NOT BETWEEN %s AND %s LIMIT 1""",
                   (id_torneo, data.fecha_inicio, data.fecha_fin))
    if fuera:
        raise HTTPException(400, "Hay partidos fuera del nuevo período del torneo")
    db.execute("""UPDATE torneo SET nombre=%s, anio=%s, semestre=%s, fecha_inicio=%s, fecha_fin=%s
                  WHERE id_torneo=%s""",
               (data.nombre, data.anio, data.semestre, data.fecha_inicio, data.fecha_fin, id_torneo))
    return db.one(TORNEO_SQL + " WHERE t.id_torneo = %s", (id_torneo,))


@router.patch("/torneos/{id_torneo}/estado")
def cambiar_estado_torneo(id_torneo: int, data: TorneoEstado, db=Depends(db_admin)):
    reglas.validar_cambio_estado_torneo(db, id_torneo, data.estado)
    db.execute("UPDATE torneo SET estado = %s WHERE id_torneo = %s", (data.estado, id_torneo))
    return db.one(TORNEO_SQL + " WHERE t.id_torneo = %s", (id_torneo,))


@router.delete("/torneos/{id_torneo}", status_code=204)
def borrar_torneo(id_torneo: int, db=Depends(db_admin)):
    t = db.one_or_404("SELECT estado FROM torneo WHERE id_torneo = %s", (id_torneo,), "Torneo")
    if t["estado"] != "inscripcion":
        raise HTTPException(409, "Solo se puede eliminar una edición que está en inscripción")
    if db.one("SELECT 1 FROM equipo WHERE id_torneo = %s LIMIT 1", (id_torneo,)):
        raise HTTPException(409, "La edición tiene equipos inscriptos: eliminalos primero")
    db.execute("DELETE FROM torneo WHERE id_torneo = %s", (id_torneo,))


# ---------------------------------------------------------------- equipos
EQUIPO_SQL = """SELECT e.id_equipo, e.nombre, e.id_torneo, t.nombre AS torneo, t.estado AS estado_torneo,
                       e.id_facultad, f.nombre AS facultad, e.ci_capitan,
                       CONCAT(c.nombre, ' ', c.apellido) AS capitan,
                       (SELECT COUNT(*) FROM equipo_jugador_torneo x WHERE x.id_equipo = e.id_equipo) AS jugadores
                  FROM equipo e
                  JOIN torneo t   ON t.id_torneo = e.id_torneo
                  JOIN facultad f ON f.id_facultad = e.id_facultad
                  LEFT JOIN jugador c ON c.ci = e.ci_capitan"""


def _equipo_con_plantel(db, id_equipo):
    e = db.one_or_404(EQUIPO_SQL + " WHERE e.id_equipo = %s", (id_equipo,), "Equipo")
    e["plantel"] = db.all("""SELECT j.ci, j.nombre, j.apellido, j.tipo, ejt.numero_camiseta,
                                    (j.ci = %s) AS es_capitan
                               FROM equipo_jugador_torneo ejt JOIN jugador j ON j.ci = ejt.ci_jugador
                              WHERE ejt.id_equipo = %s ORDER BY ejt.numero_camiseta""",
                          (e["ci_capitan"], id_equipo))
    return e


@router.get("/equipos")
def equipos(id_torneo: int | None = None, db=Depends(db_usuario)):
    if id_torneo:
        return db.all(EQUIPO_SQL + " WHERE e.id_torneo = %s ORDER BY e.nombre", (id_torneo,))
    return db.all(EQUIPO_SQL + " ORDER BY t.anio DESC, t.semestre DESC, e.nombre")


@router.get("/equipos/{id_equipo}")
def equipo(id_equipo: int, db=Depends(db_usuario)):
    return _equipo_con_plantel(db, id_equipo)


@router.post("/equipos", status_code=201)
def crear_equipo(data: EquipoIn, db=Depends(db_admin)):
    reglas.exigir_inscripcion(db, data.id_torneo, "Solo se pueden inscribir equipos mientras el torneo está en inscripción")
    db.execute("INSERT INTO equipo (nombre, id_torneo, id_facultad) VALUES (%s, %s, %s)",
               (data.nombre, data.id_torneo, data.id_facultad))
    return _equipo_con_plantel(db, db.lastrowid)


@router.put("/equipos/{id_equipo}")
def editar_equipo(id_equipo: int, data: EquipoUpdate, db=Depends(db_admin)):
    reglas.validar_edicion_equipo(db, id_equipo, data.id_facultad, data.ci_capitan)
    db.execute("UPDATE equipo SET nombre=%s, id_facultad=%s, ci_capitan=%s WHERE id_equipo=%s",
               (data.nombre, data.id_facultad, data.ci_capitan or None, id_equipo))
    return _equipo_con_plantel(db, id_equipo)


@router.delete("/equipos/{id_equipo}", status_code=204)
def borrar_equipo(id_equipo: int, db=Depends(db_admin)):
    e = db.one_or_404("SELECT id_torneo FROM equipo WHERE id_equipo = %s", (id_equipo,), "Equipo")
    reglas.exigir_inscripcion(db, e["id_torneo"], "Solo se pueden dar de baja equipos durante la inscripción")
    if db.one("""SELECT 1 FROM partido WHERE id_equipo_local = %s OR id_equipo_visitante = %s LIMIT 1""",
              (id_equipo, id_equipo)):
        raise HTTPException(409, "El equipo tiene partidos programados: eliminalos primero")
    db.execute("UPDATE equipo SET ci_capitan = NULL WHERE id_equipo = %s", (id_equipo,))
    db.execute("DELETE FROM equipo WHERE id_equipo = %s", (id_equipo,))


# ---------------------------------------------------------------- plantel
@router.get("/equipos/{id_equipo}/disponibles")
def jugadores_disponibles(id_equipo: int, db=Depends(db_usuario)):
    """Jugadores de la facultad del equipo que todavía no integran ningún equipo de la edición."""
    e = db.one_or_404("SELECT id_torneo, id_facultad FROM equipo WHERE id_equipo = %s", (id_equipo,), "Equipo")
    return db.all("""SELECT j.ci, j.nombre, j.apellido, j.tipo FROM jugador j
                      WHERE j.id_facultad = %s
                        AND NOT EXISTS (SELECT 1 FROM equipo_jugador_torneo x
                                         WHERE x.ci_jugador = j.ci AND x.id_torneo = %s)
                      ORDER BY j.apellido, j.nombre""", (e["id_facultad"], e["id_torneo"]))


@router.post("/equipos/{id_equipo}/plantel", status_code=201)
def agregar_al_plantel(id_equipo: int, data: PlantelIn, db=Depends(db_admin)):
    reglas.validar_alta_plantel(db, id_equipo, data.ci_jugador)
    e = db.one("SELECT id_torneo FROM equipo WHERE id_equipo = %s", (id_equipo,))
    db.execute("""INSERT INTO equipo_jugador_torneo (id_equipo, ci_jugador, id_torneo, numero_camiseta)
                  VALUES (%s, %s, %s, %s)""", (id_equipo, data.ci_jugador, e["id_torneo"], data.numero_camiseta))
    return _equipo_con_plantel(db, id_equipo)


@router.put("/equipos/{id_equipo}/plantel/{ci}")
def cambiar_camiseta(id_equipo: int, ci: str, data: CamisetaIn, db=Depends(db_admin)):
    reglas.validar_cambio_plantel(db, id_equipo)
    if db.execute("UPDATE equipo_jugador_torneo SET numero_camiseta = %s WHERE id_equipo = %s AND ci_jugador = %s",
                  (data.numero_camiseta, id_equipo, ci)) == 0 and not db.one(
            "SELECT 1 FROM equipo_jugador_torneo WHERE id_equipo = %s AND ci_jugador = %s", (id_equipo, ci)):
        raise HTTPException(404, "El jugador no está en el plantel")
    return _equipo_con_plantel(db, id_equipo)


@router.delete("/equipos/{id_equipo}/plantel/{ci}")
def quitar_del_plantel(id_equipo: int, ci: str, db=Depends(db_admin)):
    reglas.validar_baja_plantel(db, id_equipo, ci)
    if db.execute("DELETE FROM equipo_jugador_torneo WHERE id_equipo = %s AND ci_jugador = %s", (id_equipo, ci)) == 0:
        raise HTTPException(404, "El jugador no está en el plantel")
    return _equipo_con_plantel(db, id_equipo)
