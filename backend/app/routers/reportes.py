"""
Reportes para el área de deportes.

Cada reporte es una función que recibe la edición del torneo (id_torneo) y
devuelve una lista de filas. Las consultas usan SQL de lo visto en el curso
(JOIN, LEFT JOIN, GROUP BY, HAVING, subconsultas y vistas); lo que es más
cómodo de hacer con un for (numerar posiciones, totales, porcentajes) se
calcula en Python.
"""
from fastapi import APIRouter, Depends, HTTPException

from ..security import db_admin

router = APIRouter(prefix="/api/reportes", tags=["reportes"])

# Goles de partidos jugados, con el equipo del goleador según la planilla
GOLES_VALIDOS = """FROM gol g
                   JOIN partido p ON p.id_partido = g.id_partido AND p.estado = 'jugado'
                   JOIN planilla_partido pl ON pl.id_partido = g.id_partido AND pl.ci_jugador = g.ci_jugador"""


def porcentaje(parte, total):
    return round(100 * parte / total, 1) if total else 0


# 1 --------------------------------------------------------------------
def posiciones(db, t):
    filas = db.all("""SELECT equipo, facultad, pj, pg, pe, pp, gf, gc, dg, pts
                        FROM v_tabla_posiciones
                       WHERE id_torneo = %s
                       ORDER BY pts DESC, dg DESC, gf DESC, equipo""", (t,))
    resultado = []
    for i, f in enumerate(filas, start=1):            # la posición es el número de fila
        resultado.append({"pos": i, **f})
    return resultado


# 2 --------------------------------------------------------------------
def goleadores(db, t):
    return db.all(f"""SELECT j.ci, CONCAT(j.nombre, ' ', j.apellido) AS jugador, e.nombre AS equipo,
                             COUNT(*) AS goles,
                             COUNT(DISTINCT g.id_partido) AS partidos_con_gol
                        {GOLES_VALIDOS}
                        JOIN jugador j ON j.ci = g.ci_jugador
                        JOIN equipo e  ON e.id_equipo = pl.id_equipo
                       WHERE p.id_torneo = %s AND g.autogol = FALSE
                       GROUP BY j.ci, j.nombre, j.apellido, e.nombre
                       ORDER BY goles DESC, j.apellido, j.nombre
                       LIMIT 10""", (t,))


# 3 --------------------------------------------------------------------
def fair_play(db, t):
    # LEFT JOIN para que también aparezcan los equipos sin tarjetas
    return db.all("""SELECT e.nombre AS equipo,
                            SUM(CASE WHEN t.color = 'amarilla' THEN 1 ELSE 0 END) AS amarillas,
                            SUM(CASE WHEN t.color = 'roja' THEN 1 ELSE 0 END)     AS rojas,
                            SUM(CASE WHEN t.color = 'amarilla' THEN 1
                                     WHEN t.color = 'roja' THEN 3 ELSE 0 END)     AS puntaje
                       FROM equipo e
                       LEFT JOIN planilla_partido pl ON pl.id_equipo = e.id_equipo
                       LEFT JOIN partido p ON p.id_partido = pl.id_partido AND p.estado = 'jugado'
                       LEFT JOIN tarjeta t ON t.id_partido = p.id_partido AND t.ci_jugador = pl.ci_jugador
                      WHERE e.id_torneo = %s
                      GROUP BY e.id_equipo, e.nombre
                      ORDER BY puntaje, rojas, e.nombre""", (t,))


# 4 --------------------------------------------------------------------
def promedio_goles(db, t):
    por_fecha = db.all("""SELECT numero_fecha,
                                 COUNT(*) AS partidos_jugados,
                                 SUM(goles_local + goles_visitante) AS goles,
                                 ROUND(AVG(goles_local + goles_visitante), 2) AS promedio
                            FROM v_resultado
                           WHERE id_torneo = %s AND estado = 'jugado'
                           GROUP BY numero_fecha
                           ORDER BY numero_fecha""", (t,))
    resultado = []
    total_partidos = 0
    total_goles = 0
    for f in por_fecha:
        resultado.append({"fecha": f"Fecha {f['numero_fecha']}", "partidos_jugados": f["partidos_jugados"],
                          "goles": f["goles"], "promedio": f["promedio"]})
        total_partidos += f["partidos_jugados"]
        total_goles += f["goles"]
    if total_partidos:
        resultado.append({"fecha": "Total edición", "partidos_jugados": total_partidos, "goles": total_goles,
                          "promedio": round(total_goles / total_partidos, 2)})
    return resultado


# 5 --------------------------------------------------------------------
def canchas_turnos(db, t):
    filas = db.all("""SELECT c.nombre AS complejo, p.nombre_cancha, tu.hora_inicio, tu.hora_fin,
                             COUNT(*) AS partidos,
                             SUM(CASE WHEN p.estado = 'jugado' THEN 1 ELSE 0 END) AS jugados
                        FROM partido p
                        JOIN complejo c ON c.id_complejo = p.id_complejo
                        JOIN turno tu   ON tu.id_turno = p.id_turno
                       WHERE p.id_torneo = %s AND p.estado IN ('programado', 'jugado')
                       GROUP BY c.nombre, p.nombre_cancha, tu.hora_inicio, tu.hora_fin""", (t,))
    # totales por cancha y por turno, sumando las filas de cada grupo
    total_cancha = {}
    total_turno = {}
    for f in filas:
        f["cancha"] = f"{f['complejo']} – {f['nombre_cancha']}"
        f["turno"] = f"{f['hora_inicio']}–{f['hora_fin']}"
        total_cancha[f["cancha"]] = total_cancha.get(f["cancha"], 0) + f["partidos"]
        total_turno[f["turno"]] = total_turno.get(f["turno"], 0) + f["partidos"]

    resultado = []
    for f in filas:
        resultado.append({"cancha": f["cancha"], "turno": f["turno"], "partidos": f["partidos"],
                          "jugados": f["jugados"], "total_cancha": total_cancha[f["cancha"]],
                          "total_turno": total_turno[f["turno"]]})
    resultado.sort(key=lambda r: (-r["total_cancha"], -r["partidos"], r["cancha"], r["turno"]))
    return resultado


# 6 --------------------------------------------------------------------
def jugadores_facultad_tipo(db, t):
    return db.all("""SELECT f.nombre AS facultad,
                            SUM(CASE WHEN j.tipo = 'grado' THEN 1 ELSE 0 END)       AS grado,
                            SUM(CASE WHEN j.tipo = 'posgrado' THEN 1 ELSE 0 END)    AS posgrado,
                            SUM(CASE WHEN j.tipo = 'docente' THEN 1 ELSE 0 END)     AS docente,
                            SUM(CASE WHEN j.tipo = 'funcionario' THEN 1 ELSE 0 END) AS funcionario,
                            COUNT(*) AS total
                       FROM equipo_jugador_torneo ejt
                       JOIN jugador j  ON j.ci = ejt.ci_jugador
                       JOIN facultad f ON f.id_facultad = j.id_facultad
                      WHERE ejt.id_torneo = %s
                      GROUP BY f.id_facultad, f.nombre
                      ORDER BY total DESC, facultad""", (t,))


# 7 --------------------------------------------------------------------
def nunca_jugaron(db, t):
    return db.all("""SELECT j.ci, CONCAT(j.nombre, ' ', j.apellido) AS jugador, j.tipo, e.nombre AS equipo,
                            ejt.numero_camiseta AS camiseta
                       FROM equipo_jugador_torneo ejt
                       JOIN jugador j ON j.ci = ejt.ci_jugador
                       JOIN equipo e  ON e.id_equipo = ejt.id_equipo
                      WHERE ejt.id_torneo = %s
                        AND j.ci NOT IN (SELECT pl.ci_jugador
                                           FROM planilla_partido pl
                                           JOIN partido p ON p.id_partido = pl.id_partido
                                          WHERE p.id_torneo = ejt.id_torneo)
                      ORDER BY e.nombre, j.apellido""", (t,))


# 8 --------------------------------------------------------------------
def sanciones_equipo(db, t):
    return db.all("""SELECT e.nombre AS equipo,
                            SUM(CASE WHEN s.motivo = 'roja' THEN 1 ELSE 0 END) AS roja,
                            SUM(CASE WHEN s.motivo = 'acumulacion de amarillas' THEN 1 ELSE 0 END) AS acumulacion_amarillas,
                            SUM(CASE WHEN s.motivo = 'disciplinaria' THEN 1 ELSE 0 END) AS disciplinaria,
                            COUNT(s.id_sancion) AS total,
                            COALESCE(SUM(s.cantidad_fechas), 0) AS fechas_de_suspension
                       FROM equipo e
                       LEFT JOIN equipo_jugador_torneo ejt ON ejt.id_equipo = e.id_equipo
                       LEFT JOIN sancion_jugador s ON s.ci_jugador = ejt.ci_jugador AND s.id_torneo = e.id_torneo
                      WHERE e.id_torneo = %s
                      GROUP BY e.id_equipo, e.nombre
                      ORDER BY total DESC, e.nombre""", (t,))


# 9 --------------------------------------------------------------------
def estado_partidos(db, t):
    filas = db.all("""SELECT estado, COUNT(*) AS partidos
                        FROM partido WHERE id_torneo = %s
                       GROUP BY estado""", (t,))
    total = 0
    for f in filas:
        total += f["partidos"]
    orden = ["jugado", "postergado", "cancelado", "programado"]
    filas.sort(key=lambda f: orden.index(f["estado"]))
    for f in filas:
        f["porcentaje"] = porcentaje(f["partidos"], total)
    return filas


# ---------- 3 consultas adicionales propuestas por el grupo ----------
# 10: a quién le conviene cuidarse en la próxima fecha
def riesgo_suspension(db, t):
    # con 2, 5, 8... amarillas, la próxima lo suspende
    return db.all("""SELECT j.ci, CONCAT(j.nombre, ' ', j.apellido) AS jugador, e.nombre AS equipo,
                            COUNT(*) AS amarillas_acumuladas
                       FROM tarjeta t
                       JOIN partido p ON p.id_partido = t.id_partido
                       JOIN jugador j ON j.ci = t.ci_jugador
                       JOIN equipo_jugador_torneo ejt ON ejt.ci_jugador = j.ci AND ejt.id_torneo = p.id_torneo
                       JOIN equipo e  ON e.id_equipo = ejt.id_equipo
                      WHERE p.id_torneo = %s AND t.color = 'amarilla'
                      GROUP BY j.ci, j.nombre, j.apellido, e.nombre
                     HAVING COUNT(*) %% 3 = 2
                      ORDER BY e.nombre, jugador""", (t,))


# 11: en qué momento del partido se convierten los goles
def goles_por_tramo(db, t):
    minutos = db.all(f"SELECT g.minuto {GOLES_VALIDOS} WHERE p.id_torneo = %s", (t,))
    por_tramo = {}
    for m in minutos:
        tramo = min(m["minuto"], 59) // 10            # 0-9 -> 0, 10-19 -> 1, ... (el 60 va al último)
        por_tramo[tramo] = por_tramo.get(tramo, 0) + 1
    total = len(minutos)
    resultado = []
    for tramo in sorted(por_tramo):
        desde = tramo * 10
        resultado.append({"tramo": f"{desde:02d}–{desde + 9} min", "goles": por_tramo[tramo],
                          "porcentaje": porcentaje(por_tramo[tramo], total)})
    return resultado


# 12: rendimiento de cada equipo jugando de local y de visitante
def local_visitante(db, t):
    partidos = db.all("""SELECT id_equipo_local, id_equipo_visitante, goles_local, goles_visitante
                           FROM v_resultado WHERE id_torneo = %s AND estado = 'jugado'""", (t,))
    equipos = db.all("SELECT id_equipo, nombre FROM equipo WHERE id_torneo = %s", (t,))

    def puntos(propios, ajenos):
        if propios > ajenos:
            return 3
        if propios == ajenos:
            return 1
        return 0

    resultado = []
    for e in equipos:
        fila = {"equipo": e["nombre"], "pj_local": 0, "pts_local": 0, "pj_visitante": 0, "pts_visitante": 0}
        for p in partidos:
            if p["id_equipo_local"] == e["id_equipo"]:
                fila["pj_local"] += 1
                fila["pts_local"] += puntos(p["goles_local"], p["goles_visitante"])
            elif p["id_equipo_visitante"] == e["id_equipo"]:
                fila["pj_visitante"] += 1
                fila["pts_visitante"] += puntos(p["goles_visitante"], p["goles_local"])
        if fila["pj_local"] + fila["pj_visitante"] > 0:     # solo equipos que jugaron
            resultado.append(fila)
    resultado.sort(key=lambda f: (-(f["pts_local"] + f["pts_visitante"]), f["equipo"]))
    return resultado


REPORTES = {
    "posiciones": ("Tabla de posiciones", posiciones),
    "goleadores": ("Tabla de goleadores (top 10)", goleadores),
    "fair_play": ("Fair play por equipo (1 pt amarilla, 3 pts roja; gana el menor)", fair_play),
    "promedio_goles": ("Promedio de goles por partido (por fecha y total)", promedio_goles),
    "canchas_turnos": ("Canchas y turnos más utilizados", canchas_turnos),
    "jugadores_facultad_tipo": ("Jugadores inscriptos por facultad y tipo", jugadores_facultad_tipo),
    "nunca_jugaron": ("Jugadores inscriptos que nunca figuraron en una planilla", nunca_jugaron),
    "sanciones_equipo": ("Cantidad de sanciones por equipo y motivo", sanciones_equipo),
    "estado_partidos": ("Partidos jugados vs. postergados / cancelados", estado_partidos),
    "riesgo_suspension": ("[Extra] Jugadores a una amarilla de ser suspendidos", riesgo_suspension),
    "goles_por_tramo": ("[Extra] Distribución de goles por tramo de 10 minutos", goles_por_tramo),
    "local_visitante": ("[Extra] Rendimiento como local y como visitante", local_visitante),
}


@router.get("")
def listar():
    return [{"clave": k, "titulo": v[0]} for k, v in REPORTES.items()]


@router.get("/{clave}")
def reporte(clave: str, id_torneo: int, db=Depends(db_admin)):
    if clave not in REPORTES:
        raise HTTPException(404, "Reporte inexistente")
    titulo, funcion = REPORTES[clave]
    return {"titulo": titulo, "filas": funcion(db, id_torneo)}
