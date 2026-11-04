-- =====================================================================
--  usuarios.sql : usuarios de base de datos con permisos diferenciados
--
--  La aplicación NUNCA se conecta como root. Usa tres cuentas:
--    torneo_auth       -> solo lee la tabla login (para autenticar)
--    torneo_admin      -> gestiona toda la información del torneo
--    torneo_planillero -> lee lo necesario y solo escribe planillas,
--                         goles, tarjetas y el estado del partido
--  Cada request del backend usa la cuenta que corresponde al rol del
--  usuario logueado, así que aunque hubiera un bug en el backend, un
--  planillero no podría, por ejemplo, borrar un equipo.
--
--  Las contraseñas son de desarrollo: cambiarlas en producción (y en .env).
-- =====================================================================
USE torneo_ucu;

DROP USER IF EXISTS 'torneo_auth'@'%', 'torneo_admin'@'%', 'torneo_planillero'@'%';

CREATE USER 'torneo_auth'@'%'       IDENTIFIED BY 'Auth_Torneo_2026!';
CREATE USER 'torneo_admin'@'%'      IDENTIFIED BY 'Admin_Torneo_2026!';
CREATE USER 'torneo_planillero'@'%' IDENTIFIED BY 'Planillero_Torneo_2026!';

-- autenticación
GRANT SELECT ON torneo_ucu.login TO 'torneo_auth'@'%';

-- administrador: CRUD sobre todo el esquema (no puede crear/borrar tablas ni usuarios de BD)
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE, SHOW VIEW ON torneo_ucu.* TO 'torneo_admin'@'%';

-- planillero: lectura de lo necesario para ver partidos y planteles
GRANT SELECT ON torneo_ucu.facultad              TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.jugador               TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.torneo                TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.equipo                TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.equipo_jugador_torneo TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.complejo              TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.cancha                TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.turno                 TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.sancion_jugador       TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.v_partido             TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.v_resultado           TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.v_resultado_equipo    TO 'torneo_planillero'@'%';
GRANT SELECT ON torneo_ucu.v_tabla_posiciones    TO 'torneo_planillero'@'%';
GRANT EXECUTE ON FUNCTION torneo_ucu.fn_jugador_suspendido TO 'torneo_planillero'@'%';

-- partido: puede leerlo y cambiar ÚNICAMENTE la columna estado (marcar jugado)
GRANT SELECT ON torneo_ucu.partido TO 'torneo_planillero'@'%';
GRANT UPDATE (estado) ON torneo_ucu.partido TO 'torneo_planillero'@'%';

-- lo que sí registra
GRANT SELECT, INSERT, DELETE         ON torneo_ucu.planilla_partido TO 'torneo_planillero'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON torneo_ucu.gol              TO 'torneo_planillero'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON torneo_ucu.tarjeta          TO 'torneo_planillero'@'%';

FLUSH PRIVILEGES;
