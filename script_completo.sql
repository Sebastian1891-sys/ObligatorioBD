-- =====================================================================
--  Torneo Interfacultades de Fútbol 5 – UCU
--  esquema.sql : creación de la base y de todas las tablas
--  MySQL 8.0+
-- =====================================================================

DROP DATABASE IF EXISTS torneo_ucu;
CREATE DATABASE torneo_ucu CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE torneo_ucu;

-- ---------------------------------------------------------------------
-- Usuarios del sistema
-- ---------------------------------------------------------------------
CREATE TABLE login (
    correo      VARCHAR(120) NOT NULL,
    contrasena  VARCHAR(100) NOT NULL COMMENT 'hash bcrypt, nunca texto plano',
    rol         ENUM('administrador','planillero') NOT NULL,
    PRIMARY KEY (correo),
    CONSTRAINT chk_login_correo CHECK (correo REGEXP '^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$'),
    CONSTRAINT chk_login_hash   CHECK (CHAR_LENGTH(contrasena) >= 50)
);

-- ---------------------------------------------------------------------
-- Datos maestros
-- ---------------------------------------------------------------------
CREATE TABLE facultad (
    id_facultad INT NOT NULL AUTO_INCREMENT,
    nombre      VARCHAR(100) NOT NULL,
    PRIMARY KEY (id_facultad),
    UNIQUE KEY uq_facultad_nombre (nombre),
    CONSTRAINT chk_facultad_nombre CHECK (CHAR_LENGTH(TRIM(nombre)) >= 2)
);

CREATE TABLE jugador (
    ci               VARCHAR(8)   NOT NULL COMMENT 'CI uruguaya sin puntos ni guion',
    nombre           VARCHAR(60)  NOT NULL,
    apellido         VARCHAR(60)  NOT NULL,
    email            VARCHAR(120) NOT NULL,
    fecha_nacimiento DATE         NOT NULL,
    id_facultad      INT          NOT NULL,
    tipo             ENUM('grado','posgrado','docente','funcionario') NOT NULL,
    PRIMARY KEY (ci),
    UNIQUE KEY uq_jugador_email (email),
    CONSTRAINT fk_jugador_facultad FOREIGN KEY (id_facultad) REFERENCES facultad(id_facultad),
    CONSTRAINT chk_jugador_ci     CHECK (ci REGEXP '^[0-9]{7,8}$'),
    CONSTRAINT chk_jugador_nombre CHECK (CHAR_LENGTH(TRIM(nombre)) >= 2 AND CHAR_LENGTH(TRIM(apellido)) >= 2),
    CONSTRAINT chk_jugador_email  CHECK (email REGEXP '^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$'),
    CONSTRAINT chk_jugador_nac    CHECK (fecha_nacimiento >= '1930-01-01')
);

CREATE TABLE torneo (
    id_torneo    INT NOT NULL AUTO_INCREMENT,
    nombre       VARCHAR(100) NOT NULL,
    anio         SMALLINT NOT NULL,
    semestre     TINYINT  NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin    DATE NOT NULL,
    estado       ENUM('inscripcion','en curso','finalizado') NOT NULL DEFAULT 'inscripcion',
    PRIMARY KEY (id_torneo),
    UNIQUE KEY uq_torneo_edicion (anio, semestre) COMMENT 'una edición por semestre',
    CONSTRAINT chk_torneo_anio     CHECK (anio BETWEEN 2000 AND 2100),
    CONSTRAINT chk_torneo_semestre CHECK (semestre IN (1, 2)),
    CONSTRAINT chk_torneo_fechas   CHECK (fecha_fin >= fecha_inicio),
    CONSTRAINT chk_torneo_anio_ini CHECK (YEAR(fecha_inicio) = anio)
);

CREATE TABLE equipo (
    id_equipo   INT NOT NULL AUTO_INCREMENT,
    nombre      VARCHAR(60) NOT NULL,
    id_torneo   INT NOT NULL,
    id_facultad INT NOT NULL,
    ci_capitan  VARCHAR(8) NULL COMMENT 'NULL hasta que el plantel tenga jugadores',
    PRIMARY KEY (id_equipo),
    UNIQUE KEY uq_equipo_nombre_torneo (id_torneo, nombre),
    UNIQUE KEY uq_equipo_torneo (id_equipo, id_torneo) COMMENT 'destino de FKs compuestas',
    CONSTRAINT fk_equipo_torneo   FOREIGN KEY (id_torneo)   REFERENCES torneo(id_torneo),
    CONSTRAINT fk_equipo_facultad FOREIGN KEY (id_facultad) REFERENCES facultad(id_facultad),
    CONSTRAINT fk_equipo_capitan  FOREIGN KEY (ci_capitan)  REFERENCES jugador(ci),
    CONSTRAINT chk_equipo_nombre  CHECK (CHAR_LENGTH(TRIM(nombre)) >= 2)
);

CREATE TABLE equipo_jugador_torneo (
    id_equipo       INT        NOT NULL,
    ci_jugador      VARCHAR(8) NOT NULL,
    id_torneo       INT        NOT NULL,
    numero_camiseta TINYINT    NOT NULL,
    PRIMARY KEY (id_equipo, ci_jugador),
    -- un jugador no puede integrar más de un equipo en la misma edición
    UNIQUE KEY uq_jugador_un_equipo_por_torneo (ci_jugador, id_torneo),
    UNIQUE KEY uq_camiseta_por_equipo (id_equipo, numero_camiseta),
    -- el id_torneo redundante queda atado al del equipo
    CONSTRAINT fk_ejt_equipo  FOREIGN KEY (id_equipo, id_torneo) REFERENCES equipo(id_equipo, id_torneo) ON DELETE CASCADE,
    CONSTRAINT fk_ejt_jugador FOREIGN KEY (ci_jugador) REFERENCES jugador(ci),
    CONSTRAINT chk_ejt_camiseta CHECK (numero_camiseta BETWEEN 1 AND 99)
);

-- ---------------------------------------------------------------------
-- Infraestructura
-- ---------------------------------------------------------------------
CREATE TABLE complejo (
    id_complejo  INT NOT NULL AUTO_INCREMENT,
    nombre       VARCHAR(100) NOT NULL,
    direccion    VARCHAR(150) NOT NULL,
    departamento VARCHAR(30)  NOT NULL,
    PRIMARY KEY (id_complejo),
    UNIQUE KEY uq_complejo_nombre (nombre),
    CONSTRAINT chk_complejo_depto CHECK (departamento IN (
        'Artigas','Canelones','Cerro Largo','Colonia','Durazno','Flores','Florida',
        'Lavalleja','Maldonado','Montevideo','Paysandú','Río Negro','Rivera','Rocha',
        'Salto','San José','Soriano','Tacuarembó','Treinta y Tres'))
);

CREATE TABLE cancha (
    nombre_cancha VARCHAR(50) NOT NULL,
    id_complejo   INT NOT NULL,
    superficie    ENUM('sintetico','parquet') NOT NULL,
    techada       BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (id_complejo, nombre_cancha),
    CONSTRAINT fk_cancha_complejo FOREIGN KEY (id_complejo) REFERENCES complejo(id_complejo) ON DELETE CASCADE
);

CREATE TABLE turno (
    id_turno    TINYINT NOT NULL,
    hora_inicio TIME NOT NULL,
    hora_fin    TIME NOT NULL,
    PRIMARY KEY (id_turno),
    UNIQUE KEY uq_turno_inicio (hora_inicio),
    CONSTRAINT chk_turno_rango  CHECK (hora_inicio >= '18:00:00' AND hora_fin <= '23:00:00'),
    CONSTRAINT chk_turno_1h     CHECK (TIMEDIFF(hora_fin, hora_inicio) = '01:00:00'),
    CONSTRAINT chk_turno_enpunto CHECK (MINUTE(hora_inicio) = 0 AND SECOND(hora_inicio) = 0)
);

-- ---------------------------------------------------------------------
-- Partidos
-- ---------------------------------------------------------------------
CREATE TABLE partido (
    id_partido          INT NOT NULL AUTO_INCREMENT,
    id_torneo           INT NOT NULL,
    numero_fecha        TINYINT NOT NULL,
    id_equipo_local     INT NOT NULL,
    id_equipo_visitante INT NOT NULL,
    dia                 DATE NOT NULL,
    id_turno            TINYINT NOT NULL,
    nombre_cancha       VARCHAR(50) NOT NULL,
    id_complejo         INT NOT NULL,
    estado              ENUM('programado','jugado','postergado','cancelado') NOT NULL DEFAULT 'programado',
    jugado_en           DATETIME NULL COMMENT 'momento en que se marcó como jugado',

    -- columnas generadas para que índices UNIQUE ignoren partidos que no ocupan lugar
    ocupa_cancha  TINYINT GENERATED ALWAYS AS (IF(estado IN ('programado','jugado'), 1, NULL)) STORED,
    par_activo    TINYINT GENERATED ALWAYS AS (IF(estado <> 'cancelado', 1, NULL)) STORED,
    equipo_menor  INT GENERATED ALWAYS AS (LEAST(id_equipo_local, id_equipo_visitante)) STORED,
    equipo_mayor  INT GENERATED ALWAYS AS (GREATEST(id_equipo_local, id_equipo_visitante)) STORED,

    PRIMARY KEY (id_partido),
    UNIQUE KEY uq_partido_torneo (id_partido, id_torneo),
    -- una cancha no puede tener dos partidos en el mismo día y turno
    UNIQUE KEY uq_cancha_dia_turno (id_complejo, nombre_cancha, dia, id_turno, ocupa_cancha),
    -- un par de equipos se enfrenta una sola vez por edición (salvo partidos cancelados)
    UNIQUE KEY uq_enfrentamiento (id_torneo, equipo_menor, equipo_mayor, par_activo),
    KEY ix_partido_fecha (id_torneo, numero_fecha),

    CONSTRAINT fk_partido_torneo    FOREIGN KEY (id_torneo) REFERENCES torneo(id_torneo),
    -- ambos equipos deben pertenecer a la misma edición del partido
    CONSTRAINT fk_partido_local     FOREIGN KEY (id_equipo_local, id_torneo)     REFERENCES equipo(id_equipo, id_torneo),
    CONSTRAINT fk_partido_visitante FOREIGN KEY (id_equipo_visitante, id_torneo) REFERENCES equipo(id_equipo, id_torneo),
    CONSTRAINT fk_partido_turno     FOREIGN KEY (id_turno) REFERENCES turno(id_turno),
    CONSTRAINT fk_partido_cancha    FOREIGN KEY (id_complejo, nombre_cancha) REFERENCES cancha(id_complejo, nombre_cancha),
    CONSTRAINT chk_partido_rivales  CHECK (id_equipo_local <> id_equipo_visitante),
    CONSTRAINT chk_partido_fecha    CHECK (numero_fecha BETWEEN 1 AND 50)
);

CREATE TABLE planilla_partido (
    id_partido INT NOT NULL,
    ci_jugador VARCHAR(8) NOT NULL,
    id_equipo  INT NOT NULL,
    PRIMARY KEY (id_partido, ci_jugador),
    CONSTRAINT fk_planilla_partido FOREIGN KEY (id_partido) REFERENCES partido(id_partido),
    -- solo jugadores del plantel del equipo indicado
    CONSTRAINT fk_planilla_plantel FOREIGN KEY (id_equipo, ci_jugador) REFERENCES equipo_jugador_torneo(id_equipo, ci_jugador)
);

CREATE TABLE gol (
    id_gol     INT NOT NULL AUTO_INCREMENT,
    id_partido INT NOT NULL,
    ci_jugador VARCHAR(8) NOT NULL,
    minuto     TINYINT NOT NULL,
    autogol    BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (id_gol),
    -- solo puede convertir quien figura en la planilla
    CONSTRAINT fk_gol_planilla FOREIGN KEY (id_partido, ci_jugador) REFERENCES planilla_partido(id_partido, ci_jugador),
    CONSTRAINT chk_gol_minuto  CHECK (minuto BETWEEN 0 AND 60)
);

CREATE TABLE tarjeta (
    id_tarjeta INT NOT NULL AUTO_INCREMENT,
    id_partido INT NOT NULL,
    ci_jugador VARCHAR(8) NOT NULL,
    minuto     TINYINT NOT NULL,
    color      ENUM('amarilla','roja') NOT NULL,
    PRIMARY KEY (id_tarjeta),
    CONSTRAINT fk_tarjeta_planilla FOREIGN KEY (id_partido, ci_jugador) REFERENCES planilla_partido(id_partido, ci_jugador),
    CONSTRAINT chk_tarjeta_minuto  CHECK (minuto BETWEEN 0 AND 60)
);

CREATE TABLE sancion_jugador (
    id_sancion          INT NOT NULL AUTO_INCREMENT,
    ci_jugador          VARCHAR(8) NOT NULL,
    id_torneo           INT NOT NULL,
    motivo              ENUM('roja','acumulacion de amarillas','disciplinaria') NOT NULL,
    numero_fecha_inicio TINYINT NOT NULL,
    cantidad_fechas     TINYINT NOT NULL DEFAULT 1,
    id_tarjeta          INT NULL COMMENT 'tarjeta que originó la sanción automática',
    observacion         VARCHAR(255) NULL,
    creada_en           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_sancion),
    KEY ix_sancion_jugador_torneo (ci_jugador, id_torneo),
    CONSTRAINT fk_sancion_jugador FOREIGN KEY (ci_jugador) REFERENCES jugador(ci),
    CONSTRAINT fk_sancion_torneo  FOREIGN KEY (id_torneo)  REFERENCES torneo(id_torneo),
    CONSTRAINT fk_sancion_tarjeta FOREIGN KEY (id_tarjeta) REFERENCES tarjeta(id_tarjeta),
    CONSTRAINT chk_sancion_fecha  CHECK (numero_fecha_inicio BETWEEN 1 AND 50),
    CONSTRAINT chk_sancion_cant   CHECK (cantidad_fechas BETWEEN 1 AND 20),
    CONSTRAINT chk_sancion_auto   CHECK (
        (motivo = 'disciplinaria' AND id_tarjeta IS NULL) OR
        (motivo <> 'disciplinaria' AND id_tarjeta IS NOT NULL AND cantidad_fechas = 1))
);
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
-- =====================================================================
--  datos.sql : datos maestros y datos de prueba
--  GENERADO por base_de_datos/tools/generar_datos.py (no editar a mano)
--  Torneo 2026-S2 en curso: 6 equipos, fechas 1 a 4 disputadas,
--  un partido postergado, fecha 5 programada (uno cancelado),
--  más una edición 2027-S1 en inscripción.
-- =====================================================================
USE torneo_ucu;
SET @carga_datos = 1;  -- habilita cargar planillas históricas (solo root)

-- usuarios de la aplicación (contraseñas hasheadas con bcrypt)
-- admin@ucu.edu.uy / admin123   ·   planillero@ucu.edu.uy / planillero123
INSERT INTO login (correo, contrasena, rol) VALUES
  ('admin@ucu.edu.uy', '$2b$10$7DnOjoPtsR0voiX94jm3x.kGNGoJa5a/yI97vMpiQu1lXkc0NoEY6', 'administrador'),
  ('planillero@ucu.edu.uy', '$2b$10$eiIMGiKcdBNHAOrP0.efD.JS21VFZ65WTWGsAEoO5o6KEonwSylwK', 'planillero'),
  ('planillero2@ucu.edu.uy', '$2b$10$nivaecKfwU9uqqfkZAFjuOHMDUJptdtAA5FDTmoNaoPGooVjQoK2m', 'planillero');

INSERT INTO facultad (id_facultad, nombre) VALUES
  (1, 'Ingeniería y Tecnologías'),
  (2, 'Ciencias Empresariales'),
  (3, 'Derecho'),
  (4, 'Ciencias de la Salud'),
  (5, 'Ciencias Humanas'),
  (6, 'Psicología'),
  (7, 'Odontología');

INSERT INTO turno (id_turno, hora_inicio, hora_fin) VALUES
  (1, '18:00:00', '19:00:00'),
  (2, '19:00:00', '20:00:00'),
  (3, '20:00:00', '21:00:00'),
  (4, '21:00:00', '22:00:00'),
  (5, '22:00:00', '23:00:00');

INSERT INTO complejo (id_complejo, nombre, direccion, departamento) VALUES
  (1, 'Complejo Fútbol 5 Buceo', 'Av. Rivera 3450', 'Montevideo'),
  (2, 'Arena Malvín', 'Av. Italia 4820', 'Montevideo'),
  (3, 'Gol Center Ciudad de la Costa', 'Av. Giannattasio km 21', 'Canelones');
INSERT INTO cancha (nombre_cancha, id_complejo, superficie, techada) VALUES
  ('Cancha 1', 1, 'sintetico', FALSE),
  ('Cancha 2', 1, 'sintetico', TRUE),
  ('Central', 2, 'parquet', TRUE),
  ('Anexo', 2, 'sintetico', FALSE),
  ('Cancha A', 3, 'sintetico', FALSE);

INSERT INTO jugador (ci, nombre, apellido, email, fecha_nacimiento, id_facultad, tipo) VALUES
  ('35294131', 'Diego', 'Ferreira', 'diego.ferreira@correo.ucu.edu.uy', '2006-11-28', 1, 'grado'),
  ('35443653', 'Marcos', 'López', 'marcos.lopez@correo.ucu.edu.uy', '2006-10-18', 1, 'grado'),
  ('36009959', 'Maximiliano', 'Romero', 'maximiliano.romero@correo.ucu.edu.uy', '2006-12-25', 1, 'grado'),
  ('36668381', 'Emiliano', 'Romero', 'emiliano.romero@correo.ucu.edu.uy', '2005-04-01', 1, 'grado'),
  ('37488425', 'Joaquín', 'Pérez', 'joaquin.perez@correo.ucu.edu.uy', '2004-02-15', 1, 'grado'),
  ('37518476', 'Germán', 'Viera', 'german.viera@correo.ucu.edu.uy', '2005-11-11', 1, 'grado'),
  ('37809019', 'Tomás', 'Díaz', 'tomas.diaz@correo.ucu.edu.uy', '1999-06-26', 1, 'posgrado'),
  ('38317297', 'Sebastián', 'Ferreira', 'sebastian.ferreira@ucu.edu.uy', '1974-12-11', 1, 'docente'),
  ('38449810', 'Sofía', 'Castro', 'sofia.castro@ucu.edu.uy', '1981-05-15', 1, 'funcionario'),
  ('38649472', 'Marcos', 'Benítez', 'marcos.benitez@correo.ucu.edu.uy', '2007-12-19', 1, 'grado'),
  ('39069483', 'Mateo', 'Techera', 'mateo.techera@correo.ucu.edu.uy', '2004-06-15', 2, 'grado'),
  ('39637886', 'Joaquín', 'Núñez', 'joaquin.nunez@correo.ucu.edu.uy', '2006-09-16', 2, 'grado'),
  ('39805510', 'Rodrigo', 'Ferreira', 'rodrigo.ferreira@correo.ucu.edu.uy', '2006-08-13', 2, 'grado'),
  ('40508189', 'Federico', 'Olivera', 'federico.olivera@correo.ucu.edu.uy', '2006-08-17', 2, 'grado'),
  ('41202118', 'Maximiliano', 'Rodríguez', 'maximiliano.rodriguez@correo.ucu.edu.uy', '2006-04-25', 2, 'grado'),
  ('41386198', 'Germán', 'González', 'german.gonzalez@correo.ucu.edu.uy', '2007-09-22', 2, 'grado'),
  ('41535632', 'Juan', 'Álvarez', 'juan.alvarez@correo.ucu.edu.uy', '2000-08-05', 2, 'posgrado'),
  ('42182547', 'Marcos', 'López', 'marcos.lopez@ucu.edu.uy', '1975-11-23', 2, 'docente'),
  ('42796275', 'Micaela', 'Acosta', 'micaela.acosta@ucu.edu.uy', '1989-05-18', 2, 'funcionario'),
  ('43338284', 'Micaela', 'Suárez', 'micaela.suarez@correo.ucu.edu.uy', '2006-11-17', 2, 'grado'),
  ('44268583', 'Pablo', 'Núñez', 'pablo.nunez@correo.ucu.edu.uy', '2005-04-10', 3, 'grado'),
  ('44636211', 'Mateo', 'González', 'mateo.gonzalez@correo.ucu.edu.uy', '2003-11-20', 3, 'grado'),
  ('45251812', 'Maximiliano', 'Ferreira', 'maximiliano.ferreira@correo.ucu.edu.uy', '2005-06-07', 3, 'grado'),
  ('45607740', 'Juan', 'Acosta', 'juan.acosta@correo.ucu.edu.uy', '2005-09-25', 3, 'grado'),
  ('46274372', 'Maximiliano', 'Olivera', 'maximiliano.olivera@correo.ucu.edu.uy', '2006-11-02', 3, 'grado'),
  ('46669565', 'Diego', 'Méndez', 'diego.mendez@correo.ucu.edu.uy', '1995-08-23', 3, 'posgrado'),
  ('47623714', 'Maximiliano', 'Ferreira', 'maximiliano.ferreira2@correo.ucu.edu.uy', '1998-08-06', 3, 'posgrado'),
  ('48196780', 'Germán', 'Correa', 'german.correa@ucu.edu.uy', '1987-02-21', 3, 'docente'),
  ('48561046', 'Marcos', 'Acosta', 'marcos.acosta@correo.ucu.edu.uy', '2004-02-07', 3, 'grado'),
  ('49115153', 'Facundo', 'Méndez', 'facundo.mendez@ucu.edu.uy', '1972-02-01', 3, 'docente'),
  ('49721588', 'Camila', 'Castro', 'camila.castro@correo.ucu.edu.uy', '2002-10-26', 4, 'grado'),
  ('49997145', 'Martín', 'Pérez', 'martin.perez@correo.ucu.edu.uy', '2006-01-25', 4, 'grado'),
  ('50728381', 'Federico', 'Viera', 'federico.viera@correo.ucu.edu.uy', '2007-06-05', 4, 'grado'),
  ('50750106', 'Diego', 'Viera', 'diego.viera@correo.ucu.edu.uy', '2006-10-25', 4, 'grado'),
  ('51409958', 'Juan', 'Correa', 'juan.correa@correo.ucu.edu.uy', '2003-09-08', 4, 'grado'),
  ('52044890', 'Camila', 'Silva', 'camila.silva@correo.ucu.edu.uy', '2006-12-17', 4, 'grado'),
  ('52440892', 'Joaquín', 'Olivera', 'joaquin.olivera@correo.ucu.edu.uy', '1996-03-26', 4, 'posgrado'),
  ('53224015', 'Gonzalo', 'Ferreira', 'gonzalo.ferreira@ucu.edu.uy', '1985-07-26', 4, 'docente'),
  ('53433698', 'Valentina', 'Sosa', 'valentina.sosa@ucu.edu.uy', '1984-01-04', 4, 'funcionario'),
  ('53959018', 'Marcos', 'Fernández', 'marcos.fernandez@correo.ucu.edu.uy', '2002-06-21', 4, 'grado'),
  ('54437225', 'Felipe', 'Rodríguez', 'felipe.rodriguez@correo.ucu.edu.uy', '2002-09-16', 5, 'grado'),
  ('54881826', 'Micaela', 'Suárez', 'micaela.suarez2@correo.ucu.edu.uy', '2005-06-04', 5, 'grado'),
  ('55548996', 'Ignacio', 'Romero', 'ignacio.romero@correo.ucu.edu.uy', '2006-03-05', 5, 'grado'),
  ('56338962', 'Valentina', 'Sosa', 'valentina.sosa@correo.ucu.edu.uy', '2005-10-11', 5, 'grado'),
  ('56955344', 'Lucía', 'López', 'lucia.lopez@correo.ucu.edu.uy', '2007-12-03', 5, 'grado'),
  ('57687766', 'Tomás', 'González', 'tomas.gonzalez@correo.ucu.edu.uy', '2003-11-06', 5, 'grado'),
  ('57762057', 'Florencia', 'Castro', 'florencia.castro@correo.ucu.edu.uy', '1994-08-28', 5, 'posgrado'),
  ('58617023', 'Agustín', 'Acosta', 'agustin.acosta@ucu.edu.uy', '1972-03-21', 5, 'docente'),
  ('59326613', 'Agustín', 'Ferreira', 'agustin.ferreira@ucu.edu.uy', '1976-03-22', 5, 'funcionario'),
  ('59585417', 'Tomás', 'Díaz', 'tomas.diaz2@correo.ucu.edu.uy', '2005-09-14', 5, 'grado'),
  ('59703500', 'Tomás', 'Suárez', 'tomas.suarez@correo.ucu.edu.uy', '2003-06-06', 6, 'grado'),
  ('60063804', 'Ignacio', 'Acosta', 'ignacio.acosta@correo.ucu.edu.uy', '2005-05-15', 6, 'grado'),
  ('60310740', 'Diego', 'Ferreira', 'diego.ferreira2@correo.ucu.edu.uy', '2005-08-04', 6, 'grado'),
  ('61016818', 'Maximiliano', 'Ferreira', 'maximiliano.ferreira23@correo.ucu.edu.uy', '2004-02-28', 6, 'grado'),
  ('61312733', 'Martín', 'Rodríguez', 'martin.rodriguez@correo.ucu.edu.uy', '2002-08-21', 6, 'grado'),
  ('61760841', 'Rodrigo', 'Castro', 'rodrigo.castro@correo.ucu.edu.uy', '2007-03-01', 6, 'grado'),
  ('62237142', 'Andrés', 'Martínez', 'andres.martinez@correo.ucu.edu.uy', '1999-09-22', 6, 'posgrado'),
  ('63002300', 'Maximiliano', 'Castro', 'maximiliano.castro@ucu.edu.uy', '1978-02-20', 6, 'docente'),
  ('63955797', 'Federico', 'Castro', 'federico.castro@ucu.edu.uy', '1990-12-07', 6, 'funcionario'),
  ('64717687', 'Gonzalo', 'Romero', 'gonzalo.romero@correo.ucu.edu.uy', '2004-11-18', 6, 'grado'),
  ('64906509', 'Bruno', 'Díaz', 'bruno.diaz@correo.ucu.edu.uy', '2002-07-06', 7, 'grado'),
  ('65060487', 'Micaela', 'González', 'micaela.gonzalez@correo.ucu.edu.uy', '2004-12-26', 7, 'grado'),
  ('65318612', 'Florencia', 'Benítez', 'florencia.benitez@correo.ucu.edu.uy', '2002-09-11', 7, 'grado'),
  ('65696391', 'Camila', 'Fernández', 'camila.fernandez@correo.ucu.edu.uy', '2004-06-06', 7, 'grado');

-- las ediciones se crean en inscripción y luego avanzan de estado (como en la app)
INSERT INTO torneo (id_torneo, nombre, anio, semestre, fecha_inicio, fecha_fin, estado) VALUES
  (1, 'Torneo Interfacultades 2026 – 2º semestre', 2026, 2, '2026-09-07', '2026-11-30', 'inscripcion'),
  (2, 'Torneo Interfacultades 2027 – 1er semestre', 2027, 1, '2027-03-15', '2027-07-09', 'inscripcion');

INSERT INTO equipo (id_equipo, nombre, id_torneo, id_facultad) VALUES
  (1, 'Los Compiladores', 1, 1),
  (2, 'Balance Cero', 1, 2),
  (3, 'Fallo Unánime', 1, 3),
  (4, 'Bisturí FC', 1, 4),
  (5, 'Humanistas Unidos', 1, 5),
  (6, 'Inconsciente Colectivo', 1, 6);
INSERT INTO equipo_jugador_torneo (id_equipo, ci_jugador, id_torneo, numero_camiseta) VALUES
  (1, '35294131', 1, 9),
  (1, '35443653', 1, 23),
  (1, '36009959', 1, 3),
  (1, '36668381', 1, 1),
  (1, '37488425', 1, 14),
  (1, '37518476', 1, 22),
  (1, '37809019', 1, 19),
  (1, '38317297', 1, 20),
  (2, '39069483', 1, 2),
  (2, '39637886', 1, 4),
  (2, '39805510', 1, 8),
  (2, '40508189', 1, 1),
  (2, '41202118', 1, 10),
  (2, '41386198', 1, 22),
  (2, '41535632', 1, 18),
  (2, '42182547', 1, 12),
  (3, '44268583', 1, 11),
  (3, '44636211', 1, 15),
  (3, '45251812', 1, 20),
  (3, '45607740', 1, 21),
  (3, '46274372', 1, 2),
  (3, '46669565', 1, 13),
  (3, '47623714', 1, 23),
  (3, '48196780', 1, 7),
  (4, '49721588', 1, 20),
  (4, '49997145', 1, 15),
  (4, '50728381', 1, 14),
  (4, '50750106', 1, 4),
  (4, '51409958', 1, 12),
  (4, '52044890', 1, 17),
  (4, '52440892', 1, 9),
  (4, '53224015', 1, 13),
  (5, '54437225', 1, 10),
  (5, '54881826', 1, 12),
  (5, '55548996', 1, 2),
  (5, '56338962', 1, 14),
  (5, '56955344', 1, 1),
  (5, '57687766', 1, 23),
  (5, '57762057', 1, 11),
  (5, '58617023', 1, 18),
  (6, '59703500', 1, 4),
  (6, '60063804', 1, 10),
  (6, '60310740', 1, 14),
  (6, '61016818', 1, 11),
  (6, '61312733', 1, 19),
  (6, '61760841', 1, 1),
  (6, '62237142', 1, 20),
  (6, '63002300', 1, 7);

-- capitanes (deben ser del plantel)
UPDATE equipo SET ci_capitan = '35294131' WHERE id_equipo = 1;
UPDATE equipo SET ci_capitan = '39069483' WHERE id_equipo = 2;
UPDATE equipo SET ci_capitan = '44268583' WHERE id_equipo = 3;
UPDATE equipo SET ci_capitan = '49721588' WHERE id_equipo = 4;
UPDATE equipo SET ci_capitan = '54437225' WHERE id_equipo = 5;
UPDATE equipo SET ci_capitan = '59703500' WHERE id_equipo = 6;

INSERT INTO equipo (id_equipo, nombre, id_torneo, id_facultad) VALUES
  (7, 'Los Compiladores 2.0', 2, 1),
  (8, 'Sonrisa Perfecta', 2, 7);
INSERT INTO equipo_jugador_torneo (id_equipo, ci_jugador, id_torneo, numero_camiseta) VALUES
  (7, '35294131', 2, 1),
  (7, '35443653', 2, 2),
  (7, '36009959', 2, 3),
  (7, '36668381', 2, 4),
  (7, '37488425', 2, 5),
  (7, '37518476', 2, 6),
  (8, '64906509', 2, 10),
  (8, '65060487', 2, 11),
  (8, '65318612', 2, 12);
UPDATE equipo SET ci_capitan = '35443653' WHERE id_equipo = 7;

UPDATE torneo SET estado = 'en curso' WHERE id_torneo = 1;

-- ===================== FIXTURE Y PARTIDOS =====================

-- ---------- Fecha 1 ----------
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (1, 1, 1, 1, 6, '2026-09-14', 2, 'Cancha 2', 1, 'programado');
INSERT INTO planilla_partido (id_partido, ci_jugador, id_equipo) VALUES
  (1, '35294131', 1),
  (1, '35443653', 1),
  (1, '36009959', 1),
  (1, '36668381', 1),
  (1, '37488425', 1),
  (1, '37518476', 1),
  (1, '59703500', 6),
  (1, '60063804', 6),
  (1, '60310740', 6),
  (1, '61016818', 6),
  (1, '61312733', 6),
  (1, '61760841', 6);
INSERT INTO gol (id_partido, ci_jugador, minuto, autogol) VALUES
  (1, '59703500', 8, FALSE),
  (1, '59703500', 9, FALSE),
  (1, '35294131', 11, FALSE),
  (1, '35294131', 47, FALSE);
INSERT INTO tarjeta (id_partido, ci_jugador, minuto, color) VALUES
  (1, '36668381', 38, 'amarilla'),
  (1, '61016818', 46, 'amarilla');
UPDATE partido SET estado = 'jugado' WHERE id_partido = 1;
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (2, 1, 1, 2, 5, '2026-09-14', 3, 'Central', 2, 'programado');
INSERT INTO planilla_partido (id_partido, ci_jugador, id_equipo) VALUES
  (2, '39069483', 2),
  (2, '39637886', 2),
  (2, '39805510', 2),
  (2, '40508189', 2),
  (2, '41202118', 2),
  (2, '41386198', 2),
  (2, '54437225', 5),
  (2, '54881826', 5),
  (2, '55548996', 5),
  (2, '56338962', 5),
  (2, '56955344', 5),
  (2, '57687766', 5);
INSERT INTO gol (id_partido, ci_jugador, minuto, autogol) VALUES
  (2, '39805510', 2, FALSE),
  (2, '39637886', 23, FALSE),
  (2, '56338962', 25, FALSE),
  (2, '40508189', 38, FALSE),
  (2, '54881826', 50, FALSE);
INSERT INTO tarjeta (id_partido, ci_jugador, minuto, color) VALUES
  (2, '56955344', 19, 'amarilla');
UPDATE partido SET estado = 'jugado' WHERE id_partido = 2;
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (3, 1, 1, 3, 4, '2026-09-14', 1, 'Cancha 1', 1, 'programado');
INSERT INTO planilla_partido (id_partido, ci_jugador, id_equipo) VALUES
  (3, '44268583', 3),
  (3, '44636211', 3),
  (3, '45251812', 3),
  (3, '45607740', 3),
  (3, '46274372', 3),
  (3, '46669565', 3),
  (3, '49721588', 4),
  (3, '49997145', 4),
  (3, '50728381', 4),
  (3, '50750106', 4),
  (3, '51409958', 4),
  (3, '52044890', 4);
INSERT INTO gol (id_partido, ci_jugador, minuto, autogol) VALUES
  (3, '46274372', 2, FALSE),
  (3, '44636211', 12, FALSE),
  (3, '49997145', 15, FALSE),
  (3, '50750106', 17, FALSE),
  (3, '46274372', 44, FALSE),
  (3, '46669565', 46, FALSE);
INSERT INTO tarjeta (id_partido, ci_jugador, minuto, color) VALUES
  (3, '49997145', 6, 'amarilla');
UPDATE partido SET estado = 'jugado' WHERE id_partido = 3;

-- ---------- Fecha 2 ----------
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (4, 1, 2, 5, 1, '2026-09-21', 3, 'Central', 2, 'programado');
INSERT INTO planilla_partido (id_partido, ci_jugador, id_equipo) VALUES
  (4, '54437225', 5),
  (4, '54881826', 5),
  (4, '55548996', 5),
  (4, '56338962', 5),
  (4, '56955344', 5),
  (4, '57687766', 5),
  (4, '35294131', 1),
  (4, '35443653', 1),
  (4, '36009959', 1),
  (4, '36668381', 1),
  (4, '37488425', 1),
  (4, '37518476', 1);
INSERT INTO gol (id_partido, ci_jugador, minuto, autogol) VALUES
  (4, '36009959', 21, FALSE),
  (4, '56955344', 31, FALSE),
  (4, '35443653', 41, FALSE);
INSERT INTO tarjeta (id_partido, ci_jugador, minuto, color) VALUES
  (4, '36009959', 7, 'amarilla'),
  (4, '54881826', 16, 'amarilla');
UPDATE partido SET estado = 'jugado' WHERE id_partido = 4;
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (5, 1, 2, 6, 4, '2026-09-21', 1, 'Cancha 1', 1, 'programado');
INSERT INTO planilla_partido (id_partido, ci_jugador, id_equipo) VALUES
  (5, '59703500', 6),
  (5, '60063804', 6),
  (5, '60310740', 6),
  (5, '61016818', 6),
  (5, '61312733', 6),
  (5, '61760841', 6),
  (5, '49721588', 4),
  (5, '49997145', 4),
  (5, '50728381', 4),
  (5, '50750106', 4),
  (5, '51409958', 4),
  (5, '52044890', 4);
INSERT INTO gol (id_partido, ci_jugador, minuto, autogol) VALUES
  (5, '52044890', 1, FALSE),
  (5, '50728381', 4, FALSE),
  (5, '52044890', 16, FALSE),
  (5, '61312733', 17, FALSE),
  (5, '50750106', 33, TRUE),
  (5, '60310740', 41, FALSE),
  (5, '61312733', 49, FALSE);
INSERT INTO tarjeta (id_partido, ci_jugador, minuto, color) VALUES
  (5, '49997145', 35, 'amarilla');
UPDATE partido SET estado = 'jugado' WHERE id_partido = 5;
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (6, 1, 2, 2, 3, '2026-09-21', 2, 'Cancha 2', 1, 'programado');
INSERT INTO planilla_partido (id_partido, ci_jugador, id_equipo) VALUES
  (6, '39069483', 2),
  (6, '39637886', 2),
  (6, '39805510', 2),
  (6, '40508189', 2),
  (6, '41202118', 2),
  (6, '41386198', 2),
  (6, '44268583', 3),
  (6, '44636211', 3),
  (6, '45251812', 3),
  (6, '45607740', 3),
  (6, '46274372', 3),
  (6, '46669565', 3);
INSERT INTO gol (id_partido, ci_jugador, minuto, autogol) VALUES
  (6, '45251812', 15, FALSE),
  (6, '46274372', 18, FALSE),
  (6, '41386198', 33, FALSE),
  (6, '45607740', 46, FALSE),
  (6, '44636211', 48, FALSE);
INSERT INTO tarjeta (id_partido, ci_jugador, minuto, color) VALUES
  (6, '39805510', 40, 'roja');
UPDATE partido SET estado = 'jugado' WHERE id_partido = 6;

-- ---------- Fecha 3 ----------
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (7, 1, 3, 1, 4, '2026-09-28', 1, 'Cancha 1', 1, 'programado');
INSERT INTO planilla_partido (id_partido, ci_jugador, id_equipo) VALUES
  (7, '35294131', 1),
  (7, '35443653', 1),
  (7, '36009959', 1),
  (7, '36668381', 1),
  (7, '37488425', 1),
  (7, '37518476', 1),
  (7, '49721588', 4),
  (7, '49997145', 4),
  (7, '50728381', 4),
  (7, '50750106', 4),
  (7, '51409958', 4),
  (7, '52044890', 4);
INSERT INTO gol (id_partido, ci_jugador, minuto, autogol) VALUES
  (7, '51409958', 20, FALSE),
  (7, '36009959', 30, FALSE),
  (7, '50750106', 36, FALSE),
  (7, '50750106', 44, FALSE);
INSERT INTO tarjeta (id_partido, ci_jugador, minuto, color) VALUES
  (7, '49721588', 14, 'amarilla'),
  (7, '36668381', 15, 'amarilla'),
  (7, '49997145', 17, 'amarilla');
UPDATE partido SET estado = 'jugado' WHERE id_partido = 7;
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (8, 1, 3, 3, 5, '2026-09-28', 2, 'Cancha 2', 1, 'programado');
INSERT INTO planilla_partido (id_partido, ci_jugador, id_equipo) VALUES
  (8, '44268583', 3),
  (8, '44636211', 3),
  (8, '45251812', 3),
  (8, '45607740', 3),
  (8, '46274372', 3),
  (8, '46669565', 3),
  (8, '54437225', 5),
  (8, '54881826', 5),
  (8, '55548996', 5),
  (8, '56338962', 5),
  (8, '56955344', 5),
  (8, '57687766', 5);
INSERT INTO gol (id_partido, ci_jugador, minuto, autogol) VALUES
  (8, '56955344', 45, FALSE);
INSERT INTO tarjeta (id_partido, ci_jugador, minuto, color) VALUES
  (8, '44268583', 45, 'amarilla');
UPDATE partido SET estado = 'jugado' WHERE id_partido = 8;
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (9, 1, 3, 6, 2, '2026-09-28', 3, 'Central', 2, 'programado');
INSERT INTO planilla_partido (id_partido, ci_jugador, id_equipo) VALUES
  (9, '59703500', 6),
  (9, '60063804', 6),
  (9, '60310740', 6),
  (9, '61016818', 6),
  (9, '61312733', 6),
  (9, '61760841', 6),
  (9, '39069483', 2),
  (9, '39637886', 2),
  (9, '40508189', 2),
  (9, '41202118', 2),
  (9, '41386198', 2),
  (9, '41535632', 2);
INSERT INTO gol (id_partido, ci_jugador, minuto, autogol) VALUES
  (9, '59703500', 20, FALSE),
  (9, '41386198', 47, FALSE);
INSERT INTO tarjeta (id_partido, ci_jugador, minuto, color) VALUES
  (9, '60310740', 50, 'amarilla');
UPDATE partido SET estado = 'jugado' WHERE id_partido = 9;

-- ---------- Fecha 4 ----------
-- sanción disciplinaria resuelta por la organización antes de la fecha 4
INSERT INTO sancion_jugador (ci_jugador, id_torneo, motivo, numero_fecha_inicio, cantidad_fechas, observacion) VALUES
  ('61312733', 1, 'disciplinaria', 4, 2, 'Agresión verbal al árbitro en la fecha 3');
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (10, 1, 4, 3, 1, '2026-10-05', 2, 'Cancha 2', 1, 'programado');
INSERT INTO planilla_partido (id_partido, ci_jugador, id_equipo) VALUES
  (10, '44268583', 3),
  (10, '44636211', 3),
  (10, '45251812', 3),
  (10, '45607740', 3),
  (10, '46274372', 3),
  (10, '46669565', 3),
  (10, '35294131', 1),
  (10, '35443653', 1),
  (10, '36009959', 1),
  (10, '36668381', 1),
  (10, '37488425', 1),
  (10, '37518476', 1);
INSERT INTO gol (id_partido, ci_jugador, minuto, autogol) VALUES
  (10, '44268583', 2, FALSE),
  (10, '37488425', 3, FALSE),
  (10, '46274372', 14, FALSE),
  (10, '46669565', 38, FALSE);
INSERT INTO tarjeta (id_partido, ci_jugador, minuto, color) VALUES
  (10, '35294131', 39, 'amarilla');
UPDATE partido SET estado = 'jugado' WHERE id_partido = 10;
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (11, 1, 4, 4, 2, '2026-10-05', 3, 'Central', 2, 'programado');
INSERT INTO planilla_partido (id_partido, ci_jugador, id_equipo) VALUES
  (11, '49721588', 4),
  (11, '50728381', 4),
  (11, '50750106', 4),
  (11, '51409958', 4),
  (11, '52044890', 4),
  (11, '52440892', 4),
  (11, '39069483', 2),
  (11, '39637886', 2),
  (11, '39805510', 2),
  (11, '40508189', 2),
  (11, '41202118', 2),
  (11, '41386198', 2);
INSERT INTO gol (id_partido, ci_jugador, minuto, autogol) VALUES
  (11, '50728381', 33, FALSE),
  (11, '52440892', 43, FALSE);
UPDATE partido SET estado = 'jugado' WHERE id_partido = 11;
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (12, 1, 4, 5, 6, '2026-10-05', 4, 'Cancha A', 3, 'programado');
UPDATE partido SET estado = 'postergado' WHERE id_partido = 12;  -- lluvia, cancha sin techo

-- ---------- Fecha 5 ----------
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (13, 1, 5, 1, 2, '2026-11-16', 3, 'Central', 2, 'programado');
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (14, 1, 5, 6, 3, '2026-11-16', 1, 'Cancha 1', 1, 'programado');
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (15, 1, 5, 4, 5, '2026-11-16', 2, 'Cancha 2', 1, 'programado');
UPDATE partido SET estado = 'cancelado' WHERE id_partido = 15;  -- cancelado por la organización

SET @carga_datos = NULL;
