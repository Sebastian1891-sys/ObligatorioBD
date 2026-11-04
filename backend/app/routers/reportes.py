"""
Reportes para el área de deportes. Cada reporte es una consulta SQL escrita a
mano (sin ORM); todos reciben el id de la edición del torneo.
"""
from fastapi import APIRouter, Depends, HTTPException

from ..security import db_admin

router = APIRouter(prefix="/api/reportes", tags=["reportes"])

# Expresiones reutilizadas
GOLES_VALIDOS = """FROM gol g
                   JOIN partido p ON p.id_partido = g.id_partido AND p.estado = 'jugado'
                   JOIN planilla_partido pl ON pl.id_partido = g.id_partido AND pl.ci_jugador = g.ci_jugador"""

REPORTES = {
    # 1 ----------------------------------------------------------------
    "posiciones": ("Tabla de posiciones", """
        SELECT ROW_NUMBER() OVER (ORDER BY pts DESC, dg DESC, gf DESC, equipo) AS pos,
               equipo, facultad, pj, pg, pe, pp, gf, gc, dg, pts
          FROM v_tabla_posiciones WHERE id_torneo = %(t)s
         ORDER BY pts DESC, dg DESC, gf DESC, equipo"""),

    # 2 ----------------------------------------------------------------
    "goleadores": ("Tabla de goleadores (top 10)", f"""
        SELECT j.ci, CONCAT(j.nombre, ' ', j.apellido) AS jugador, e.nombre AS equipo,
               COUNT(*) AS goles,
               COUNT(DISTINCT g.id_partido) AS partidos_con_gol
          {GOLES_VALIDOS}
          JOIN jugador j ON j.ci = g.ci_jugador
          JOIN equipo e  ON e.id_equipo = pl.id_equipo
         WHERE p.id_torneo = %(t)s AND NOT g.autogol
         GROUP BY j.ci, j.nombre, j.apellido, e.nombre
         ORDER BY goles DESC, j.apellido, j.nombre
         LIMIT 10"""),

    # 3 ----------------------------------------------------------------
    "fair_play": ("Fair play por equipo (1 pt amarilla, 3 pts roja; gana el menor)", """
        SELECT e.nombre AS equipo,
               COALESCE(SUM(t.color = 'amarilla'), 0) AS amarillas,
               COALESCE(SUM(t.color = 'roja'), 0)     AS rojas,
               COALESCE(SUM(CASE t.color WHEN 'amarilla' THEN 1 WHEN 'roja' THEN 3 ELSE 0 END), 0) AS puntaje
          FROM equipo e
          LEFT JOIN planilla_partido pl ON pl.id_equipo = e.id_equipo
          LEFT JOIN partido p ON p.id_partido = pl.id_partido AND p.estado = 'jugado'
          LEFT JOIN tarjeta t ON t.id_partido = p.id_partido AND t.ci_jugador = pl.ci_jugador
         WHERE e.id_torneo = %(t)s
         GROUP BY e.id_equipo, e.nombre
         ORDER BY puntaje, rojas, e.nombre"""),

    # 4 ----------------------------------------------------------------
    "promedio_goles": ("Promedio de goles por partido (por fecha y total)", """
        SELECT CASE WHEN GROUPING(numero_fecha) = 1 THEN 'Total edición'
                    ELSE CONCAT('Fecha ', numero_fecha) END AS fecha,
               COUNT(*) AS partidos_jugados,
               SUM(goles_local + goles_visitante) AS goles,
               ROUND(AVG(goles_local + goles_visitante), 2) AS promedio
          FROM v_resultado
         WHERE id_torneo = %(t)s AND estado = 'jugado'
         GROUP BY numero_fecha WITH ROLLUP"""),

    # 5 ----------------------------------------------------------------
    "canchas_turnos": ("Canchas y turnos más utilizados", """
        SELECT CONCAT(c.nombre, ' – ', p.nombre_cancha) AS cancha,
               CONCAT(DATE_FORMAT(t.hora_inicio, '%%H:%%i'), '–', DATE_FORMAT(t.hora_fin, '%%H:%%i')) AS turno,
               COUNT(*) AS partidos,
               SUM(p.estado = 'jugado') AS jugados,
               SUM(COUNT(*)) OVER (PARTITION BY p.id_complejo, p.nombre_cancha) AS total_cancha,
               SUM(COUNT(*)) OVER (PARTITION BY p.id_turno) AS total_turno
          FROM partido p
          JOIN complejo c ON c.id_complejo = p.id_complejo
          JOIN turno t    ON t.id_turno = p.id_turno
         WHERE p.id_torneo = %(t)s AND p.estado IN ('programado', 'jugado')
         GROUP BY p.id_complejo, c.nombre, p.nombre_cancha, p.id_turno, t.hora_inicio, t.hora_fin
         ORDER BY total_cancha DESC, partidos DESC, cancha"""),

    # 6 ----------------------------------------------------------------
    "jugadores_facultad_tipo": ("Jugadores inscriptos por facultad y tipo", """
        SELECT f.nombre AS facultad,
               SUM(j.tipo = 'grado')       AS grado,
               SUM(j.tipo = 'posgrado')    AS posgrado,
               SUM(j.tipo = 'docente')     AS docente,
               SUM(j.tipo = 'funcionario') AS funcionario,
               COUNT(*) AS total
          FROM equipo_jugador_torneo ejt
          JOIN jugador j  ON j.ci = ejt.ci_jugador
          JOIN facultad f ON f.id_facultad = j.id_facultad
         WHERE ejt.id_torneo = %(t)s
         GROUP BY f.id_facultad, f.nombre
         ORDER BY total DESC, facultad"""),

    # 7 ----------------------------------------------------------------
    "nunca_jugaron": ("Jugadores inscriptos que nunca figuraron en una planilla", """
        SELECT j.ci, CONCAT(j.nombre, ' ', j.apellido) AS jugador, j.tipo, e.nombre AS equipo,
               ejt.numero_camiseta AS camiseta
          FROM equipo_jugador_torneo ejt
          JOIN jugador j ON j.ci = ejt.ci_jugador
          JOIN equipo e  ON e.id_equipo = ejt.id_equipo
         WHERE ejt.id_torneo = %(t)s
           AND NOT EXISTS (SELECT 1 FROM planilla_partido pl JOIN partido p ON p.id_partido = pl.id_partido
                            WHERE pl.ci_jugador = j.ci AND p.id_torneo = ejt.id_torneo)
         ORDER BY e.nombre, j.apellido"""),

    # 8 ----------------------------------------------------------------
    "sanciones_equipo": ("Cantidad de sanciones por equipo y motivo", """
        SELECT e.nombre AS equipo,
               COALESCE(SUM(s.motivo = 'roja'), 0) AS roja,
               COALESCE(SUM(s.motivo = 'acumulacion de amarillas'), 0) AS acumulacion_amarillas,
               COALESCE(SUM(s.motivo = 'disciplinaria'), 0) AS disciplinaria,
               COUNT(s.id_sancion) AS total,
               COALESCE(SUM(s.cantidad_fechas), 0) AS fechas_de_suspension
          FROM equipo e
          LEFT JOIN equipo_jugador_torneo ejt ON ejt.id_equipo = e.id_equipo
          LEFT JOIN sancion_jugador s ON s.ci_jugador = ejt.ci_jugador AND s.id_torneo = e.id_torneo
         WHERE e.id_torneo = %(t)s
         GROUP BY e.id_equipo, e.nombre
         ORDER BY total DESC, e.nombre"""),

    # 9 ----------------------------------------------------------------
    "estado_partidos": ("Partidos jugados vs. postergados / cancelados", """
        SELECT estado, COUNT(*) AS partidos,
               ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS porcentaje
          FROM partido WHERE id_torneo = %(t)s
         GROUP BY estado
         ORDER BY FIELD(estado, 'jugado', 'postergado', 'cancelado', 'programado')"""),

    # ---------- 3 consultas adicionales propuestas por el grupo ----------
    # 10: a quién le conviene cuidarse en la próxima fecha
    "riesgo_suspension": ("[Extra] Jugadores a una amarilla de ser suspendidos", """
        SELECT j.ci, CONCAT(j.nombre, ' ', j.apellido) AS jugador, e.nombre AS equipo,
               COUNT(*) AS amarillas_acumuladas
          FROM tarjeta t
          JOIN partido p ON p.id_partido = t.id_partido
          JOIN jugador j ON j.ci = t.ci_jugador
          JOIN equipo_jugador_torneo ejt ON ejt.ci_jugador = j.ci AND ejt.id_torneo = p.id_torneo
          JOIN equipo e  ON e.id_equipo = ejt.id_equipo
         WHERE p.id_torneo = %(t)s AND t.color = 'amarilla'
         GROUP BY j.ci, j.nombre, j.apellido, e.nombre
        HAVING COUNT(*) %% 3 = 2
         ORDER BY e.nombre, jugador"""),

    # 11: en qué momento del partido se convierten los goles
    "goles_por_tramo": ("[Extra] Distribución de goles por tramo de 10 minutos", f"""
        SELECT CONCAT(LPAD(x.tramo * 10, 2, '0'), '–', x.tramo * 10 + 9, ' min') AS tramo,
               COUNT(*) AS goles,
               ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS porcentaje
          FROM (SELECT FLOOR(LEAST(g.minuto, 59) / 10) AS tramo
                  {GOLES_VALIDOS}
                 WHERE p.id_torneo = %(t)s) x
         GROUP BY x.tramo
         ORDER BY x.tramo"""),

    # 12: rendimiento de cada equipo jugando de local y de visitante
    "local_visitante": ("[Extra] Rendimiento como local y como visitante", """
        SELECT e.nombre AS equipo,
               SUM(r.id_equipo_local = e.id_equipo) AS pj_local,
               SUM(CASE WHEN r.id_equipo_local = e.id_equipo THEN
                       CASE WHEN r.goles_local > r.goles_visitante THEN 3 WHEN r.goles_local = r.goles_visitante THEN 1 ELSE 0 END
                   ELSE 0 END) AS pts_local,
               SUM(r.id_equipo_visitante = e.id_equipo) AS pj_visitante,
               SUM(CASE WHEN r.id_equipo_visitante = e.id_equipo THEN
                       CASE WHEN r.goles_visitante > r.goles_local THEN 3 WHEN r.goles_local = r.goles_visitante THEN 1 ELSE 0 END
                   ELSE 0 END) AS pts_visitante
          FROM equipo e
          JOIN v_resultado r ON r.estado = 'jugado' AND e.id_equipo IN (r.id_equipo_local, r.id_equipo_visitante)
         WHERE e.id_torneo = %(t)s
         GROUP BY e.id_equipo, e.nombre
         ORDER BY pts_local + pts_visitante DESC, e.nombre"""),
}


@router.get("")
def listar():
    return [{"clave": k, "titulo": v[0]} for k, v in REPORTES.items()]


@router.get("/{clave}")
def reporte(clave: str, id_torneo: int, db=Depends(db_admin)):
    if clave not in REPORTES:
        raise HTTPException(404, "Reporte inexistente")
    titulo, sql = REPORTES[clave]
    return {"titulo": titulo, "filas": db.all(sql, {"t": id_torneo})}
