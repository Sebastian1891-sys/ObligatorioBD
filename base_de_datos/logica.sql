USE torneo_ucu;

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

CREATE VIEW v_resultado AS
SELECT p.id_partido, p.id_torneo, p.numero_fecha, p.estado,
       p.id_equipo_local, p.id_equipo_visitante,
       (SELECT COUNT(*) FROM gol g
         JOIN planilla_partido pl ON pl.id_partido = g.id_partido AND pl.ci_jugador = g.ci_jugador
        WHERE g.id_partido = p.id_partido
          AND ((pl.id_equipo = p.id_equipo_local AND g.autogol = FALSE)
            OR (pl.id_equipo = p.id_equipo_visitante AND g.autogol = TRUE))) AS goles_local,
       (SELECT COUNT(*) FROM gol g
         JOIN planilla_partido pl ON pl.id_partido = g.id_partido AND pl.ci_jugador = g.ci_jugador
        WHERE g.id_partido = p.id_partido
          AND ((pl.id_equipo = p.id_equipo_visitante AND g.autogol = FALSE)
            OR (pl.id_equipo = p.id_equipo_local AND g.autogol = TRUE))) AS goles_visitante
  FROM partido p;
