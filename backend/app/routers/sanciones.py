"""ABM de sanciones. Las automáticas (roja / 3 amarillas) las genera la base;
acá se gestionan las disciplinarias."""
from fastapi import APIRouter, Depends, HTTPException

from ..schemas import SancionIn, SancionUpdate
from ..security import db_admin, db_usuario

router = APIRouter(prefix="/api/sanciones", tags=["sanciones"])

SANCION_SQL = """SELECT s.id_sancion, s.ci_jugador, j.nombre, j.apellido, s.id_torneo, t.nombre AS torneo,
                        e.nombre AS equipo, s.motivo, s.numero_fecha_inicio, s.cantidad_fechas,
                        s.numero_fecha_inicio + s.cantidad_fechas - 1 AS numero_fecha_fin,
                        s.id_tarjeta, s.observacion, s.creada_en
                   FROM sancion_jugador s
                   JOIN jugador j ON j.ci = s.ci_jugador
                   JOIN torneo t  ON t.id_torneo = s.id_torneo
                   LEFT JOIN equipo_jugador_torneo ejt ON ejt.ci_jugador = s.ci_jugador AND ejt.id_torneo = s.id_torneo
                   LEFT JOIN equipo e ON e.id_equipo = ejt.id_equipo"""


@router.get("")
def sanciones(id_torneo: int | None = None, db=Depends(db_usuario)):
    if id_torneo:
        return db.all(SANCION_SQL + " WHERE s.id_torneo = %s ORDER BY s.numero_fecha_inicio, j.apellido", (id_torneo,))
    return db.all(SANCION_SQL + " ORDER BY s.id_torneo DESC, s.numero_fecha_inicio, j.apellido")


@router.post("", status_code=201)
def crear_sancion(data: SancionIn, db=Depends(db_admin)):
    if not db.one("SELECT 1 FROM equipo_jugador_torneo WHERE ci_jugador = %s AND id_torneo = %s",
                  (data.ci_jugador, data.id_torneo)):
        raise HTTPException(400, "El jugador no integra ningún plantel de esa edición")
    db.execute("""INSERT INTO sancion_jugador (ci_jugador, id_torneo, motivo, numero_fecha_inicio, cantidad_fechas, observacion)
                  VALUES (%s, %s, 'disciplinaria', %s, %s, %s)""",
               (data.ci_jugador, data.id_torneo, data.numero_fecha_inicio, data.cantidad_fechas, data.observacion))
    return db.one(SANCION_SQL + " WHERE s.id_sancion = %s", (db.lastrowid,))


def _disciplinaria(db, id_sancion):
    s = db.one_or_404("SELECT motivo FROM sancion_jugador WHERE id_sancion = %s", (id_sancion,), "Sanción")
    if s["motivo"] != "disciplinaria":
        raise HTTPException(400, "Las sanciones automáticas se corrigen modificando o borrando la tarjeta que las originó")


@router.put("/{id_sancion}")
def editar_sancion(id_sancion: int, data: SancionUpdate, db=Depends(db_admin)):
    _disciplinaria(db, id_sancion)
    db.execute("UPDATE sancion_jugador SET numero_fecha_inicio=%s, cantidad_fechas=%s, observacion=%s WHERE id_sancion=%s",
               (data.numero_fecha_inicio, data.cantidad_fechas, data.observacion, id_sancion))
    return db.one(SANCION_SQL + " WHERE s.id_sancion = %s", (id_sancion,))


@router.delete("/{id_sancion}", status_code=204)
def borrar_sancion(id_sancion: int, db=Depends(db_admin)):
    _disciplinaria(db, id_sancion)
    db.execute("DELETE FROM sancion_jugador WHERE id_sancion = %s", (id_sancion,))
