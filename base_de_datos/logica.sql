-- =====================================================================
--  logica.sql : reglas de negocio en la base (funciones, procedimientos,
--  triggers) y vistas usadas por los reportes.
--
--  Todas las violaciones de reglas se informan con SIGNAL SQLSTATE '45000'
--  y un mensaje legible, que el backend devuelve tal cual al usuario.
-- =====================================================================
USE torneo_ucu;

DELIMITER $$

-- ---------------------------------------------------------------------
-- Funciones auxiliares
-- ---------------------------------------------------------------------

-- Permite cargar datos históricos (partidos de hace semanas) sin chocar con
-- la ventana de 48 h. Solo vale si quien ejecuta es root y además setea la
-- variable de sesión @carga_datos = 1 (lo hace datos.sql). Los usuarios
-- de la aplicación nunca pueden activarlo.
CREATE FUNCTION fn_carga_inicial() RETURNS BOOLEAN
NOT DETERMINISTIC NO SQL
BEGIN
    RETURN COALESCE(@carga_datos, 0) = 1 AND SUBSTRING_INDEX(USER(), '@', 1) = 'root';
END$$

-- Momento en que termina el turno del partido (día + hora_fin)
CREATE FUNCTION fn_fin_partido(p_id_partido INT) RETURNS DATETIME
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_fin DATETIME;
    SELECT TIMESTAMP(p.dia, t.hora_fin) INTO v_fin
      FROM partido p JOIN turno t ON t.id_turno = p.id_turno
     WHERE p.id_partido = p_id_partido;
    RETURN v_fin;
END$$

-- ¿Está el jugador suspendido para esa fecha de esa edición?
CREATE FUNCTION fn_jugador_suspendido(p_ci VARCHAR(8), p_id_torneo INT, p_numero_fecha INT)
RETURNS BOOLEAN NOT DETERMINISTIC READS SQL DATA
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM sancion_jugador s
         WHERE s.ci_jugador = p_ci AND s.id_torneo = p_id_torneo
           AND p_numero_fecha BETWEEN s.numero_fecha_inicio
                                  AND s.numero_fecha_inicio + s.cantidad_fechas - 1);
END$$

-- ---------------------------------------------------------------------
-- Procedimientos de validación reutilizados por varios triggers
-- ---------------------------------------------------------------------

-- La planilla (y sus goles/tarjetas) solo se carga o corrige cuando el turno
-- ya terminó y dentro de las 48 h siguientes. Partido no postergado/cancelado.
CREATE PROCEDURE sp_validar_ventana_planilla(IN p_id_partido INT)
BEGIN
    DECLARE v_estado VARCHAR(20);
    DECLARE v_estado_torneo VARCHAR(20);
    DECLARE v_fin DATETIME;

    SELECT p.estado, tr.estado INTO v_estado, v_estado_torneo
      FROM partido p JOIN torneo tr ON tr.id_torneo = p.id_torneo
     WHERE p.id_partido = p_id_partido;
    SET v_fin = fn_fin_partido(p_id_partido);

    IF v_estado IN ('postergado', 'cancelado') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede cargar la planilla de un partido postergado o cancelado';
    END IF;
    IF NOT fn_carga_inicial() THEN
        IF v_estado_torneo <> 'en curso' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se cargan planillas de torneos en curso';
        END IF;
        IF NOW() < v_fin THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El partido todavía no terminó: la planilla se carga una vez finalizado el turno';
        END IF;
        IF NOW() > v_fin + INTERVAL 48 HOUR THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pasaron más de 48 horas desde el partido: el resultado ya no puede corregirse';
        END IF;
    END IF;
END$$

-- Reglas al programar o modificar un partido
CREATE PROCEDURE sp_validar_partido(
    IN p_id_partido INT, IN p_id_torneo INT, IN p_numero_fecha INT,
    IN p_local INT, IN p_visitante INT, IN p_dia DATE, IN p_id_turno INT,
    IN p_id_complejo INT, IN p_cancha VARCHAR(50), IN p_estado VARCHAR(20))
BEGIN
    DECLARE v_estado_torneo VARCHAR(20);
    DECLARE v_ini DATE;
    DECLARE v_fin DATE;
    DECLARE v_hora_fin TIME;
    DECLARE v_msg VARCHAR(255);

    SELECT estado, fecha_inicio, fecha_fin INTO v_estado_torneo, v_ini, v_fin
      FROM torneo WHERE id_torneo = p_id_torneo;

    IF v_estado_torneo = 'finalizado' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El torneo está finalizado: no se pueden programar ni modificar partidos';
    END IF;
    IF p_local = p_visitante THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Un equipo no puede enfrentarse a sí mismo';
    END IF;
    IF p_dia NOT BETWEEN v_ini AND v_fin THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El día del partido está fuera del período del torneo';
    END IF;

    IF p_estado IN ('programado', 'jugado') THEN
        IF (SELECT COUNT(*) FROM equipo_jugador_torneo WHERE id_equipo = p_local) < 5
           OR (SELECT COUNT(*) FROM equipo_jugador_torneo WHERE id_equipo = p_visitante) < 5 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ambos equipos deben tener al menos 5 jugadores en su plantel';
        END IF;

        IF EXISTS (SELECT 1 FROM partido
                    WHERE id_complejo = p_id_complejo AND nombre_cancha = p_cancha
                      AND dia = p_dia AND id_turno = p_id_turno
                      AND estado IN ('programado','jugado') AND id_partido <> p_id_partido) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cancha ya tiene un partido asignado en ese día y turno';
        END IF;
    END IF;

    IF p_estado <> 'cancelado' THEN
        IF EXISTS (SELECT 1 FROM partido
                    WHERE id_torneo = p_id_torneo AND estado <> 'cancelado' AND id_partido <> p_id_partido
                      AND LEAST(id_equipo_local, id_equipo_visitante) = LEAST(p_local, p_visitante)
                      AND GREATEST(id_equipo_local, id_equipo_visitante) = GREATEST(p_local, p_visitante)) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Esos equipos ya tienen un partido en esta edición (solo se puede repetir si el anterior fue cancelado)';
        END IF;

        IF EXISTS (SELECT 1 FROM partido
                    WHERE id_torneo = p_id_torneo AND numero_fecha = p_numero_fecha
                      AND estado <> 'cancelado' AND id_partido <> p_id_partido
                      AND (id_equipo_local IN (p_local, p_visitante) OR id_equipo_visitante IN (p_local, p_visitante))) THEN
            SET v_msg = CONCAT('Uno de los equipos ya tiene un partido en la fecha ', p_numero_fecha);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;
    END IF;

    IF p_estado = 'jugado' THEN
        SELECT hora_fin INTO v_hora_fin FROM turno WHERE id_turno = p_id_turno;
        IF NOW() < TIMESTAMP(p_dia, v_hora_fin) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Un partido solo puede marcarse como jugado cuando su día y turno ya pasaron';
        END IF;
    END IF;
END$$

-- Regenera las sanciones automáticas (roja / acumulación de amarillas) de un
-- jugador en una edición a partir de sus tarjetas. Se llama desde los triggers
-- de tarjeta, así insertar, corregir o borrar una tarjeta deja todo coherente.
--   * roja                 -> 1 fecha, se cumple en la fecha siguiente
--   * cada 3 amarillas     -> 1 fecha, en la fecha siguiente a la 3ª (6ª, 9ª...)
-- p_excluir: id de tarjeta a ignorar (la que se está borrando), 0 si ninguna.
CREATE PROCEDURE sp_regenerar_sanciones_auto(IN p_ci VARCHAR(8), IN p_id_torneo INT, IN p_excluir INT)
BEGIN
    DELETE FROM sancion_jugador
     WHERE ci_jugador = p_ci AND id_torneo = p_id_torneo AND motivo <> 'disciplinaria';

    INSERT INTO sancion_jugador (ci_jugador, id_torneo, motivo, numero_fecha_inicio, cantidad_fechas, id_tarjeta)
    SELECT t.ci_jugador, p.id_torneo, 'roja', p.numero_fecha + 1, 1, t.id_tarjeta
      FROM tarjeta t JOIN partido p ON p.id_partido = t.id_partido
     WHERE t.ci_jugador = p_ci AND p.id_torneo = p_id_torneo
       AND t.color = 'roja' AND t.id_tarjeta <> p_excluir;

    INSERT INTO sancion_jugador (ci_jugador, id_torneo, motivo, numero_fecha_inicio, cantidad_fechas, id_tarjeta)
    SELECT x.ci_jugador, x.id_torneo, 'acumulacion de amarillas', x.numero_fecha + 1, 1, x.id_tarjeta
      FROM (SELECT t.ci_jugador, p.id_torneo, p.numero_fecha, t.id_tarjeta,
                   ROW_NUMBER() OVER (ORDER BY p.numero_fecha, p.dia, t.minuto, t.id_tarjeta) AS n
              FROM tarjeta t JOIN partido p ON p.id_partido = t.id_partido
             WHERE t.ci_jugador = p_ci AND p.id_torneo = p_id_torneo
               AND t.color = 'amarilla' AND t.id_tarjeta <> p_excluir) x
     WHERE x.n % 3 = 0;
END$$

-- ---------------------------------------------------------------------
-- TORNEO: el estado solo avanza  inscripción -> en curso -> finalizado
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_torneo_bu BEFORE UPDATE ON torneo FOR EACH ROW
BEGIN
    IF NEW.estado <> OLD.estado AND NOT (
         (OLD.estado = 'inscripcion' AND NEW.estado = 'en curso') OR
         (OLD.estado = 'en curso'    AND NEW.estado = 'finalizado')) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transición de estado inválida: inscripción → en curso → finalizado';
    END IF;
    IF OLD.estado = 'inscripcion' AND NEW.estado = 'en curso'
       AND (SELECT COUNT(*) FROM equipo WHERE id_torneo = NEW.id_torneo) < 2 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Se necesitan al menos 2 equipos para iniciar el torneo';
    END IF;
    IF OLD.estado = 'inscripcion' AND NEW.estado = 'en curso' AND EXISTS (
        SELECT 1 FROM equipo e
         WHERE e.id_torneo = NEW.id_torneo
           AND (e.ci_capitan IS NULL
                OR (SELECT COUNT(*) FROM equipo_jugador_torneo j WHERE j.id_equipo = e.id_equipo) < 5)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Todos los equipos necesitan capitán y al menos 5 jugadores para iniciar el torneo';
    END IF;
END$$

-- ---------------------------------------------------------------------
-- EQUIPO
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_equipo_bi BEFORE INSERT ON equipo FOR EACH ROW
BEGIN
    IF (SELECT estado FROM torneo WHERE id_torneo = NEW.id_torneo) <> 'inscripcion' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se pueden inscribir equipos mientras el torneo está en inscripción';
    END IF;
    IF NEW.ci_capitan IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El capitán se asigna después de cargar el plantel';
    END IF;
END$$

CREATE TRIGGER trg_equipo_bu BEFORE UPDATE ON equipo FOR EACH ROW
BEGIN
    IF NEW.id_torneo <> OLD.id_torneo THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Un equipo no puede cambiarse de edición';
    END IF;
    IF NEW.id_facultad <> OLD.id_facultad
       AND EXISTS (SELECT 1 FROM equipo_jugador_torneo WHERE id_equipo = OLD.id_equipo) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede cambiar la facultad de un equipo con plantel cargado';
    END IF;
    IF NEW.ci_capitan IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM equipo_jugador_torneo WHERE id_equipo = NEW.id_equipo AND ci_jugador = NEW.ci_capitan) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El capitán debe ser un jugador del plantel del equipo';
    END IF;
END$$

CREATE TRIGGER trg_equipo_bd BEFORE DELETE ON equipo FOR EACH ROW
BEGIN
    IF (SELECT estado FROM torneo WHERE id_torneo = OLD.id_torneo) <> 'inscripcion' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se pueden dar de baja equipos durante la inscripción';
    END IF;
END$$

-- ---------------------------------------------------------------------
-- PLANTEL (equipo_jugador_torneo)
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_plantel_bi BEFORE INSERT ON equipo_jugador_torneo FOR EACH ROW
BEGIN
    DECLARE v_fac_equipo INT;
    DECLARE v_fac_jugador INT;
    DECLARE v_tipo VARCHAR(20);

    IF (SELECT estado FROM torneo WHERE id_torneo = NEW.id_torneo) <> 'inscripcion' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Los planteles solo pueden modificarse durante la inscripción';
    END IF;

    SELECT id_facultad INTO v_fac_equipo FROM equipo WHERE id_equipo = NEW.id_equipo;
    SELECT id_facultad, tipo INTO v_fac_jugador, v_tipo FROM jugador WHERE ci = NEW.ci_jugador;

    IF v_fac_equipo <> v_fac_jugador THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El jugador debe pertenecer a la facultad que representa el equipo';
    END IF;
    IF (SELECT COUNT(*) FROM equipo_jugador_torneo WHERE id_equipo = NEW.id_equipo) >= 10 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El plantel ya tiene 10 jugadores (máximo permitido)';
    END IF;
    IF v_tipo IN ('docente', 'funcionario') AND (
        SELECT COUNT(*) FROM equipo_jugador_torneo ejt JOIN jugador j ON j.ci = ejt.ci_jugador
         WHERE ejt.id_equipo = NEW.id_equipo AND j.tipo IN ('docente', 'funcionario')) >= 2 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El plantel ya tiene 2 docentes/funcionarios (máximo permitido)';
    END IF;
END$$

CREATE TRIGGER trg_plantel_bu BEFORE UPDATE ON equipo_jugador_torneo FOR EACH ROW
BEGIN
    IF (SELECT estado FROM torneo WHERE id_torneo = OLD.id_torneo) <> 'inscripcion' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Los planteles solo pueden modificarse durante la inscripción';
    END IF;
    IF NEW.id_equipo <> OLD.id_equipo OR NEW.ci_jugador <> OLD.ci_jugador OR NEW.id_torneo <> OLD.id_torneo THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se puede modificar el número de camiseta; para cambiar de jugador, dar de baja y alta';
    END IF;
END$$

CREATE TRIGGER trg_plantel_bd BEFORE DELETE ON equipo_jugador_torneo FOR EACH ROW
BEGIN
    IF (SELECT estado FROM torneo WHERE id_torneo = OLD.id_torneo) <> 'inscripcion' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Los planteles solo pueden modificarse durante la inscripción';
    END IF;
    IF EXISTS (SELECT 1 FROM equipo WHERE id_equipo = OLD.id_equipo AND ci_capitan = OLD.ci_jugador) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El jugador es el capitán: asigná otro capitán antes de quitarlo del plantel';
    END IF;
END$$

-- ---------------------------------------------------------------------
-- PARTIDO
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_partido_bi BEFORE INSERT ON partido FOR EACH ROW
BEGIN
    CALL sp_validar_partido(0, NEW.id_torneo, NEW.numero_fecha, NEW.id_equipo_local, NEW.id_equipo_visitante,
                            NEW.dia, NEW.id_turno, NEW.id_complejo, NEW.nombre_cancha, NEW.estado);
    IF NEW.estado = 'jugado' THEN
        SET NEW.jugado_en = NOW();
    END IF;
END$$

CREATE TRIGGER trg_partido_bu BEFORE UPDATE ON partido FOR EACH ROW
BEGIN
    IF OLD.estado = 'jugado' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Un partido jugado no puede modificarse (solo su planilla, dentro de las 48 h)';
    END IF;
    IF OLD.estado = 'cancelado' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Un partido cancelado no puede modificarse: programá uno nuevo';
    END IF;
    IF NEW.id_torneo <> OLD.id_torneo THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Un partido no puede cambiar de edición';
    END IF;
    IF NEW.estado IN ('postergado', 'cancelado')
       AND EXISTS (SELECT 1 FROM planilla_partido WHERE id_partido = OLD.id_partido) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El partido ya tiene planilla cargada: no puede postergarse ni cancelarse';
    END IF;
    CALL sp_validar_partido(OLD.id_partido, NEW.id_torneo, NEW.numero_fecha, NEW.id_equipo_local, NEW.id_equipo_visitante,
                            NEW.dia, NEW.id_turno, NEW.id_complejo, NEW.nombre_cancha, NEW.estado);
    IF NEW.estado = 'jugado' THEN
        SET NEW.jugado_en = NOW();
    END IF;
END$$

CREATE TRIGGER trg_partido_bd BEFORE DELETE ON partido FOR EACH ROW
BEGIN
    IF OLD.estado = 'jugado' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Un partido jugado no puede eliminarse';
    END IF;
END$$

-- ---------------------------------------------------------------------
-- PLANILLA
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_planilla_bi BEFORE INSERT ON planilla_partido FOR EACH ROW
BEGIN
    DECLARE v_local INT;
    DECLARE v_visit INT;
    DECLARE v_torneo INT;
    DECLARE v_fecha INT;

    CALL sp_validar_ventana_planilla(NEW.id_partido);

    SELECT id_equipo_local, id_equipo_visitante, id_torneo, numero_fecha
      INTO v_local, v_visit, v_torneo, v_fecha
      FROM partido WHERE id_partido = NEW.id_partido;

    IF NEW.id_equipo NOT IN (v_local, v_visit) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El jugador debe pertenecer a uno de los dos equipos del partido';
    END IF;
    IF fn_jugador_suspendido(NEW.ci_jugador, v_torneo, v_fecha) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El jugador está suspendido para esta fecha y no puede figurar en la planilla';
    END IF;
END$$

CREATE TRIGGER trg_planilla_bu BEFORE UPDATE ON planilla_partido FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La planilla no se edita: quitá al jugador y volvé a agregarlo';
END$$

CREATE TRIGGER trg_planilla_bd BEFORE DELETE ON planilla_partido FOR EACH ROW
BEGIN
    CALL sp_validar_ventana_planilla(OLD.id_partido);
    IF EXISTS (SELECT 1 FROM gol WHERE id_partido = OLD.id_partido AND ci_jugador = OLD.ci_jugador)
       OR EXISTS (SELECT 1 FROM tarjeta WHERE id_partido = OLD.id_partido AND ci_jugador = OLD.ci_jugador) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El jugador tiene goles o tarjetas en el partido: borralos antes de quitarlo de la planilla';
    END IF;
END$$

-- ---------------------------------------------------------------------
-- GOL
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_gol_bi BEFORE INSERT ON gol FOR EACH ROW
BEGIN
    CALL sp_validar_ventana_planilla(NEW.id_partido);
END$$

CREATE TRIGGER trg_gol_bu BEFORE UPDATE ON gol FOR EACH ROW
BEGIN
    IF NEW.id_partido <> OLD.id_partido THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Un gol no puede moverse a otro partido';
    END IF;
    CALL sp_validar_ventana_planilla(OLD.id_partido);
END$$

CREATE TRIGGER trg_gol_bd BEFORE DELETE ON gol FOR EACH ROW
BEGIN
    CALL sp_validar_ventana_planilla(OLD.id_partido);
END$$

-- ---------------------------------------------------------------------
-- TARJETA  (además dispara la regeneración de sanciones automáticas)
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_tarjeta_bi BEFORE INSERT ON tarjeta FOR EACH ROW
BEGIN
    CALL sp_validar_ventana_planilla(NEW.id_partido);
    IF EXISTS (SELECT 1 FROM tarjeta WHERE id_partido = NEW.id_partido AND ci_jugador = NEW.ci_jugador AND color = 'roja') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El jugador ya fue expulsado en este partido';
    END IF;
    IF NEW.color = 'amarilla' AND (SELECT COUNT(*) FROM tarjeta
         WHERE id_partido = NEW.id_partido AND ci_jugador = NEW.ci_jugador AND color = 'amarilla') >= 2 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Un jugador no puede recibir más de 2 amarillas en un partido';
    END IF;
END$$

CREATE TRIGGER trg_tarjeta_ai AFTER INSERT ON tarjeta FOR EACH ROW
BEGIN
    CALL sp_regenerar_sanciones_auto(NEW.ci_jugador, (SELECT id_torneo FROM partido WHERE id_partido = NEW.id_partido), 0);
END$$

CREATE TRIGGER trg_tarjeta_bu BEFORE UPDATE ON tarjeta FOR EACH ROW
BEGIN
    IF NEW.id_partido <> OLD.id_partido OR NEW.ci_jugador <> OLD.ci_jugador THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se puede corregir el minuto o el color de la tarjeta';
    END IF;
    CALL sp_validar_ventana_planilla(OLD.id_partido);
END$$

CREATE TRIGGER trg_tarjeta_au AFTER UPDATE ON tarjeta FOR EACH ROW
BEGIN
    CALL sp_regenerar_sanciones_auto(NEW.ci_jugador, (SELECT id_torneo FROM partido WHERE id_partido = NEW.id_partido), 0);
END$$

CREATE TRIGGER trg_tarjeta_bd BEFORE DELETE ON tarjeta FOR EACH ROW
BEGIN
    CALL sp_validar_ventana_planilla(OLD.id_partido);
    -- se regenera excluyendo la tarjeta que se borra (así no queda ninguna sanción apuntándole)
    CALL sp_regenerar_sanciones_auto(OLD.ci_jugador, (SELECT id_torneo FROM partido WHERE id_partido = OLD.id_partido), OLD.id_tarjeta);
END$$

-- ---------------------------------------------------------------------
-- SANCIONES: las automáticas solo las crea la base
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_sancion_bu BEFORE UPDATE ON sancion_jugador FOR EACH ROW
BEGIN
    IF OLD.motivo <> 'disciplinaria' OR NEW.motivo <> 'disciplinaria' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Las sanciones automáticas no se editan: se corrigen modificando las tarjetas';
    END IF;
END$$

DELIMITER ;

-- =====================================================================
-- VISTAS
-- =====================================================================

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
       COALESCE(SUM(r.gf > r.gc), 0)               AS pg,
       COALESCE(SUM(r.gf = r.gc), 0)               AS pe,
       COALESCE(SUM(r.gf < r.gc), 0)               AS pp,
       COALESCE(SUM(r.gf), 0)                      AS gf,
       COALESCE(SUM(r.gc), 0)                      AS gc,
       COALESCE(SUM(r.gf), 0) - COALESCE(SUM(r.gc), 0) AS dg,
       COALESCE(SUM(CASE WHEN r.gf > r.gc THEN 3 WHEN r.gf = r.gc THEN 1 ELSE 0 END), 0) AS pts
  FROM equipo e
  JOIN facultad f ON f.id_facultad = e.id_facultad
  LEFT JOIN v_resultado_equipo r ON r.id_equipo = e.id_equipo
 GROUP BY e.id_torneo, e.id_equipo, e.nombre, f.nombre;
