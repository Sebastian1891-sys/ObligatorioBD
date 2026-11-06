from fastapi import APIRouter, Depends, HTTPException

from ..security import db_admin

router = APIRouter(prefix="/api/reportes", tags=["reportes"])

GOLES_VALIDOS = """FROM gol g
                   JOIN partido p ON p.id_partido = g.id_partido AND p.estado = 'jugado'
                   JOIN planilla_partido pl ON pl.id_partido = g.id_partido AND pl.ci_jugador = g.ci_jugador"""

def porcentaje(parte, total):
    if total == 0:
        return 0
    return round(100 * parte / total, 1)

def orden_posicion(fila):
    return (-fila["pts"], -fila["dg"], -fila["gf"], fila["equipo"])

def posiciones(db, t):
    equipos = db.all("""SELECT e.id_equipo, e.nombre AS equipo, f.nombre AS facultad
                          FROM equipo e JOIN facultad f ON f.id_facultad = e.id_facultad
                         WHERE e.id_torneo = %s""", (t,))
    partidos = db.all("""SELECT id_equipo_local, id_equipo_visitante, goles_local, goles_visitante
                           FROM v_resultado WHERE id_torneo = %s AND estado = 'jugado'""", (t,))
    resultado = []
    for equipo in equipos:
        fila = {"pos": 0, "equipo": equipo["equipo"], "facultad": equipo["facultad"],
                "pj": 0, "pg": 0, "pe": 0, "pp": 0, "gf": 0, "gc": 0, "dg": 0, "pts": 0}
        for partido in partidos:
            if partido["id_equipo_local"] == equipo["id_equipo"]:
                favor = partido["goles_local"]
                contra = partido["goles_visitante"]
            elif partido["id_equipo_visitante"] == equipo["id_equipo"]:
                favor = partido["goles_visitante"]
                contra = partido["goles_local"]
            else:
                continue
            fila["pj"] += 1
            fila["gf"] += favor
            fila["gc"] += contra
            if favor > contra:
                fila["pg"] += 1
                fila["pts"] += 3
            elif favor == contra:
                fila["pe"] += 1
                fila["pts"] += 1
            else:
                fila["pp"] += 1
        fila["dg"] = fila["gf"] - fila["gc"]
        resultado.append(fila)
    resultado.sort(key=orden_posicion)
    posicion = 1
    for fila in resultado:
        fila["pos"] = posicion
        posicion += 1
    return resultado

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

def orden_fair_play(fila):
    return (fila["puntaje"], fila["rojas"], fila["equipo"])

def fair_play(db, t):
    equipos = db.all("SELECT id_equipo, nombre FROM equipo WHERE id_torneo = %s", (t,))
    tarjetas = db.all("""SELECT pl.id_equipo, ta.color, COUNT(*) AS cantidad
                           FROM tarjeta ta
                           JOIN partido p ON p.id_partido = ta.id_partido
                           JOIN planilla_partido pl ON pl.id_partido = ta.id_partido
                                                   AND pl.ci_jugador = ta.ci_jugador
                          WHERE p.id_torneo = %s AND p.estado = 'jugado'
                          GROUP BY pl.id_equipo, ta.color""", (t,))
    resultado = []
    for equipo in equipos:
        fila = {"equipo": equipo["nombre"], "amarillas": 0, "rojas": 0, "puntaje": 0}
        for tarjeta in tarjetas:
            if tarjeta["id_equipo"] == equipo["id_equipo"]:
                if tarjeta["color"] == "amarilla":
                    fila["amarillas"] = tarjeta["cantidad"]
                else:
                    fila["rojas"] = tarjeta["cantidad"]
        fila["puntaje"] = fila["amarillas"] + 3 * fila["rojas"]
        resultado.append(fila)
    resultado.sort(key=orden_fair_play)
    return resultado

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

def orden_cancha(fila):
    return (-fila["total_cancha"], -fila["partidos"], fila["cancha"], fila["turno"])

def canchas_turnos(db, t):
    filas = db.all("""SELECT c.nombre AS complejo, p.nombre_cancha, tu.hora_inicio, tu.hora_fin,
                             p.estado, COUNT(*) AS partidos
                        FROM partido p
                        JOIN complejo c ON c.id_complejo = p.id_complejo
                        JOIN turno tu   ON tu.id_turno = p.id_turno
                       WHERE p.id_torneo = %s AND p.estado IN ('programado', 'jugado')
                       GROUP BY c.nombre, p.nombre_cancha, tu.hora_inicio, tu.hora_fin, p.estado""", (t,))

    agrupadas = {}
    for fila in filas:
        clave = (fila["complejo"], fila["nombre_cancha"], fila["hora_inicio"], fila["hora_fin"])
        if clave not in agrupadas:
            agrupadas[clave] = fila.copy()
            agrupadas[clave]["partidos"] = 0
            agrupadas[clave]["jugados"] = 0
        agrupadas[clave]["partidos"] += fila["partidos"]
        if fila["estado"] == "jugado":
            agrupadas[clave]["jugados"] += fila["partidos"]
    filas = list(agrupadas.values())

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
    resultado.sort(key=orden_cancha)
    return resultado

def orden_total(fila):
    return -fila["total"]

def jugadores_facultad_tipo(db, t):
    filas = db.all("""SELECT f.id_facultad, f.nombre AS facultad, j.tipo, COUNT(*) AS cantidad
                        FROM equipo_jugador_torneo ejt
                        JOIN jugador j ON j.ci = ejt.ci_jugador
                        JOIN facultad f ON f.id_facultad = j.id_facultad
                       WHERE ejt.id_torneo = %s
                       GROUP BY f.id_facultad, f.nombre, j.tipo
                       ORDER BY f.nombre""", (t,))
    facultades = {}
    for fila in filas:
        id_facultad = fila["id_facultad"]
        if id_facultad not in facultades:
            facultades[id_facultad] = {"facultad": fila["facultad"], "grado": 0, "posgrado": 0,
                                      "docente": 0, "funcionario": 0, "total": 0}
        facultades[id_facultad][fila["tipo"]] = fila["cantidad"]
        facultades[id_facultad]["total"] += fila["cantidad"]
    resultado = list(facultades.values())
    resultado.sort(key=orden_total)
    return resultado

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

def sanciones_equipo(db, t):
    equipos = db.all("SELECT id_equipo, nombre FROM equipo WHERE id_torneo = %s ORDER BY nombre", (t,))
    sanciones = db.all("""SELECT ejt.id_equipo, s.motivo, COUNT(*) AS cantidad,
                                 SUM(s.cantidad_fechas) AS fechas
                            FROM sancion_jugador s
                            JOIN equipo_jugador_torneo ejt ON ejt.ci_jugador = s.ci_jugador
                                                         AND ejt.id_torneo = s.id_torneo
                           WHERE s.id_torneo = %s
                           GROUP BY ejt.id_equipo, s.motivo""", (t,))
    resultado = []
    for equipo in equipos:
        fila = {"equipo": equipo["nombre"], "roja": 0, "acumulacion_amarillas": 0,
                "disciplinaria": 0, "total": 0, "fechas_de_suspension": 0}
        for sancion in sanciones:
            if sancion["id_equipo"] == equipo["id_equipo"]:
                motivo = sancion["motivo"]
                if motivo == "acumulacion de amarillas":
                    motivo = "acumulacion_amarillas"
                fila[motivo] = sancion["cantidad"]
                fila["total"] += sancion["cantidad"]
                fila["fechas_de_suspension"] += sancion["fechas"]
        resultado.append(fila)
    resultado.sort(key=orden_total)
    return resultado

def estado_partidos(db, t):
    filas = db.all("""SELECT estado, COUNT(*) AS partidos
                        FROM partido WHERE id_torneo = %s
                       GROUP BY estado""", (t,))
    total = 0
    for f in filas:
        total += f["partidos"]
    orden = ["jugado", "postergado", "cancelado", "programado"]
    ordenadas = []
    for estado in orden:
        for fila in filas:
            if fila["estado"] == estado:
                ordenadas.append(fila)
    filas = ordenadas
    for f in filas:
        f["porcentaje"] = porcentaje(f["partidos"], total)
    return filas

def riesgo_suspension(db, t):

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

def goles_por_tramo(db, t):
    minutos = db.all(f"SELECT g.minuto {GOLES_VALIDOS} WHERE p.id_torneo = %s", (t,))
    por_tramo = {}
    for m in minutos:
        tramo = min(m["minuto"], 59) // 10
        por_tramo[tramo] = por_tramo.get(tramo, 0) + 1
    total = len(minutos)
    resultado = []
    for tramo in sorted(por_tramo):
        desde = tramo * 10
        resultado.append({"tramo": f"{desde:02d}–{desde + 9} min", "goles": por_tramo[tramo],
                          "porcentaje": porcentaje(por_tramo[tramo], total)})
    return resultado

def orden_rendimiento(fila):
    puntos = fila["pts_local"] + fila["pts_visitante"]
    return (-puntos, fila["equipo"])

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
        if fila["pj_local"] + fila["pj_visitante"] > 0:
            resultado.append(fila)
    resultado.sort(key=orden_rendimiento)
    return resultado

REPORTES = {
    "posiciones": "Tabla de posiciones",
    "goleadores": "Tabla de goleadores (top 10)",
    "fair_play": "Fair play por equipo (1 pt amarilla, 3 pts roja; gana el menor)",
    "promedio_goles": "Promedio de goles por partido (por fecha y total)",
    "canchas_turnos": "Canchas y turnos más utilizados",
    "jugadores_facultad_tipo": "Jugadores inscriptos por facultad y tipo",
    "nunca_jugaron": "Jugadores inscriptos que nunca figuraron en una planilla",
    "sanciones_equipo": "Cantidad de sanciones por equipo y motivo",
    "estado_partidos": "Partidos jugados vs. postergados / cancelados",
    "riesgo_suspension": "[Extra] Jugadores a una amarilla de ser suspendidos",
    "goles_por_tramo": "[Extra] Distribución de goles por tramo de 10 minutos",
    "local_visitante": "[Extra] Rendimiento como local y como visitante",
}

@router.get("")
def listar():
    resultado = []
    for clave, datos in REPORTES.items():
        resultado.append({"clave": clave, "titulo": datos})
    return resultado

@router.get("/{clave}")
def reporte(clave: str, id_torneo: int, db=Depends(db_admin)):
    if clave not in REPORTES:
        raise HTTPException(404, "Reporte inexistente")
    if clave == "posiciones":
        filas = posiciones(db, id_torneo)
    elif clave == "goleadores":
        filas = goleadores(db, id_torneo)
    elif clave == "fair_play":
        filas = fair_play(db, id_torneo)
    elif clave == "promedio_goles":
        filas = promedio_goles(db, id_torneo)
    elif clave == "canchas_turnos":
        filas = canchas_turnos(db, id_torneo)
    elif clave == "jugadores_facultad_tipo":
        filas = jugadores_facultad_tipo(db, id_torneo)
    elif clave == "nunca_jugaron":
        filas = nunca_jugaron(db, id_torneo)
    elif clave == "sanciones_equipo":
        filas = sanciones_equipo(db, id_torneo)
    elif clave == "estado_partidos":
        filas = estado_partidos(db, id_torneo)
    elif clave == "riesgo_suspension":
        filas = riesgo_suspension(db, id_torneo)
    elif clave == "goles_por_tramo":
        filas = goles_por_tramo(db, id_torneo)
    elif clave == "local_visitante":
        filas = local_visitante(db, id_torneo)
    return {"titulo": REPORTES[clave], "filas": filas}
