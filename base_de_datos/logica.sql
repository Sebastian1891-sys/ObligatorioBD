-- =====================================================================
--  logica.sql : vistas usadas por la aplicación y los reportes
--
--  El resultado de un partido NO se guarda en ninguna columna: se calcula
--  siempre a partir de los goles cargados (como pide la letra). Estas
--  vistas hacen ese cálculo para no repetirlo en cada consulta.
-- =====================================================================
USE torneo_ucu;

-- Partido con nombres y horario legibles
CREATE VIEW v_partido AS
SELECT p.id_partido, p.id_torneo, p.numero_fecha, p.dia, p.id_turno,
       t.hora_inicio, t.hora_fin, TIMESTAMP(p.dia, t.hora_fin) AS fin,
       p.id_complejo, c.nombre AS complejo, p.nombre_cancha, p.estado, p.jugado_en,
       p.id_equipo_local, el.nombre AS equipo_local,
       p.id_equipo_visitante, ev.nombre AS equipo_visitante
  FROM partido p
  JOIN turno t     ON t.id_turno = p.id_turno
  JOIN complejo c  ON c.id_complejo = p.id_complejo
  JOIN equipo el   ON el.id_equipo = p.id_equipo_local
  JOIN equipo ev   ON ev.id_equipo = p.id_equipo_visitante;

-- Resultado calculado a partir de los goles (el autogol suma al rival)
CREATE VIEW v_resultado AS
SELECT p.id_partido, p.id_torneo, p.numero_fecha, p.estado,
       p.id_equipo_local, p.id_equipo_visitante,
       COALESCE(SUM(CASE WHEN (pl.id_equipo = p.id_equipo_local     AND NOT g.autogol)
                           OR (pl.id_equipo = p.id_equipo_visitante AND g.autogol) THEN 1 ELSE 0 END), 0) AS goles_local,
       COALESCE(SUM(CASE WHEN (pl.id_equipo = p.id_equipo_visitante AND NOT g.autogol)
                           OR (pl.id_equipo = p.id_equipo_local     AND g.autogol) THEN 1 ELSE 0 END), 0) AS goles_visitante
  FROM partido p
  LEFT JOIN gol g               ON g.id_partido = p.id_partido
  LEFT JOIN planilla_partido pl ON pl.id_partido = g.id_partido AND pl.ci_jugador = g.ci_jugador
 GROUP BY p.id_partido, p.id_torneo, p.numero_fecha, p.estado, p.id_equipo_local, p.id_equipo_visitante;

-- Una fila por equipo y partido jugado
CREATE VIEW v_resultado_equipo AS
SELECT id_torneo, id_partido, numero_fecha, id_equipo_local AS id_equipo,
       goles_local AS gf, goles_visitante AS gc
  FROM v_resultado WHERE estado = 'jugado'
UNION ALL
SELECT id_torneo, id_partido, numero_fecha, id_equipo_visitante,
       goles_visitante, goles_local
  FROM v_resultado WHERE estado = 'jugado';

-- Tabla de posiciones (incluye equipos que todavía no jugaron)
CREATE VIEW v_tabla_posiciones AS
SELECT e.id_torneo, e.id_equipo, e.nombre AS equipo, f.nombre AS facultad,
       COUNT(r.id_partido)                         AS pj,
       SUM(CASE WHEN r.gf > r.gc THEN 1 ELSE 0 END)  AS pg,
       SUM(CASE WHEN r.gf = r.gc THEN 1 ELSE 0 END)  AS pe,
       SUM(CASE WHEN r.gf < r.gc THEN 1 ELSE 0 END)  AS pp,
       COALESCE(SUM(r.gf), 0)                      AS gf,
       COALESCE(SUM(r.gc), 0)                      AS gc,
       COALESCE(SUM(r.gf), 0) - COALESCE(SUM(r.gc), 0) AS dg,
       COALESCE(SUM(CASE WHEN r.gf > r.gc THEN 3 WHEN r.gf = r.gc THEN 1 ELSE 0 END), 0) AS pts
  FROM equipo e
  JOIN facultad f ON f.id_facultad = e.id_facultad
  LEFT JOIN v_resultado_equipo r ON r.id_equipo = e.id_equipo
 GROUP BY e.id_torneo, e.id_equipo, e.nombre, f.nombre;
