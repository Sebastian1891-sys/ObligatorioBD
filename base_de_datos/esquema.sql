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
