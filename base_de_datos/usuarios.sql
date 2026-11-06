USE torneo_ucu;

DROP USER IF EXISTS 'torneo_auth'@'%', 'torneo_admin'@'%', 'torneo_planillero'@'%';

CREATE USER 'torneo_auth'@'%'       IDENTIFIED BY 'Auth_Torneo_2026!';
CREATE USER 'torneo_admin'@'%'      IDENTIFIED BY 'Admin_Torneo_2026!';
CREATE USER 'torneo_planillero'@'%' IDENTIFIED BY 'Planillero_Torneo_2026!';

GRANT SELECT ON torneo_ucu.login TO 'torneo_auth'@'%';

GRANT SELECT, INSERT, UPDATE, DELETE ON torneo_ucu.* TO 'torneo_admin'@'%';

GRANT SELECT ON torneo_ucu.facultad              TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.jugador               TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.torneo                TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.equipo                TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.equipo_jugador_torneo TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.complejo              TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.cancha                TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.turno                 TO 'torneo_planillero'@'%';

GRANT SELECT, INSERT, DELETE ON torneo_ucu.sancion_jugador TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.v_partido             TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.v_resultado           TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.v_resultado_equipo    TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.v_tabla_posiciones    TO 'torneo_planillero'@'%';

GRANT SELECT ON torneo_ucu.partido TO 'torneo_planillero'@'%';
GRANT UPDATE (estado, jugado_en) ON torneo_ucu.partido TO 'torneo_planillero'@'%';

GRANT SELECT, INSERT, DELETE         ON torneo_ucu.planilla_partido TO 'torneo_planillero'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON torneo_ucu.gol              TO 'torneo_planillero'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON torneo_ucu.tarjeta          TO 'torneo_planillero'@'%';

FLUSH PRIVILEGES;
