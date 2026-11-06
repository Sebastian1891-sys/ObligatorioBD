DROP DATABASE IF EXISTS torneo_ucu;
CREATE DATABASE torneo_ucu CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE torneo_ucu;

CREATE TABLE login (
    correo      VARCHAR(120) NOT NULL,
    contrasena  VARCHAR(100) NOT NULL,
    rol         VARCHAR(20) NOT NULL,
    CHECK (rol IN ('administrador','planillero')),
    PRIMARY KEY (correo),
    CHECK (correo LIKE '%_@_%._%'),
    CHECK (CHAR_LENGTH(contrasena) >= 50)
);

CREATE TABLE facultad (
    id_facultad INT NOT NULL AUTO_INCREMENT,
    nombre      VARCHAR(100) NOT NULL,
    PRIMARY KEY (id_facultad),
    UNIQUE (nombre),
    CHECK (CHAR_LENGTH(TRIM(nombre)) >= 2)
);

CREATE TABLE jugador (
    ci               VARCHAR(8)   NOT NULL,
    nombre           VARCHAR(60)  NOT NULL,
    apellido         VARCHAR(60)  NOT NULL,
    email            VARCHAR(120) NOT NULL,
    fecha_nacimiento DATE         NOT NULL,
    id_facultad      INT          NOT NULL,
    tipo             VARCHAR(20) NOT NULL,
    CHECK (tipo IN ('grado','posgrado','docente','funcionario')),
    PRIMARY KEY (ci),
    UNIQUE (email),
    FOREIGN KEY (id_facultad) REFERENCES facultad(id_facultad),
    CHECK (CHAR_LENGTH(ci) IN (7, 8)),
    CHECK (CHAR_LENGTH(TRIM(nombre)) >= 2 AND CHAR_LENGTH(TRIM(apellido)) >= 2),
    CHECK (email LIKE '%_@_%._%'),
    CHECK (fecha_nacimiento >= '1930-01-01')
);

CREATE TABLE torneo (
    id_torneo    INT NOT NULL AUTO_INCREMENT,
    nombre       VARCHAR(100) NOT NULL,
    anio         INT NOT NULL,
    semestre     INT  NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin    DATE NOT NULL,
    estado       VARCHAR(20) NOT NULL DEFAULT 'inscripcion',
    CHECK (estado IN ('inscripcion','en curso','finalizado')),
    PRIMARY KEY (id_torneo),
    UNIQUE (anio, semestre),
    CHECK (anio BETWEEN 2000 AND 2100),
    CHECK (semestre IN (1, 2)),
    CHECK (fecha_fin >= fecha_inicio),
    CHECK (YEAR(fecha_inicio) = anio)
);

CREATE TABLE equipo (
    id_equipo   INT NOT NULL AUTO_INCREMENT,
    nombre      VARCHAR(60) NOT NULL,
    id_torneo   INT NOT NULL,
    id_facultad INT NOT NULL,
    ci_capitan  VARCHAR(8) NULL,
    PRIMARY KEY (id_equipo),
    UNIQUE (id_torneo, nombre),
    UNIQUE (id_equipo, id_torneo),
    FOREIGN KEY (id_torneo)   REFERENCES torneo(id_torneo),
    FOREIGN KEY (id_facultad) REFERENCES facultad(id_facultad),
    FOREIGN KEY (ci_capitan)  REFERENCES jugador(ci),
    CHECK (CHAR_LENGTH(TRIM(nombre)) >= 2)
);

CREATE TABLE equipo_jugador_torneo (
    id_equipo       INT        NOT NULL,
    ci_jugador      VARCHAR(8) NOT NULL,
    id_torneo       INT        NOT NULL,
    numero_camiseta INT    NOT NULL,
    PRIMARY KEY (id_equipo, ci_jugador),

    UNIQUE (ci_jugador, id_torneo),
    UNIQUE (id_equipo, numero_camiseta),

    FOREIGN KEY (id_equipo, id_torneo) REFERENCES equipo(id_equipo, id_torneo) ON DELETE CASCADE,
    FOREIGN KEY (ci_jugador) REFERENCES jugador(ci),
    CHECK (numero_camiseta BETWEEN 1 AND 99)
);

CREATE TABLE complejo (
    id_complejo  INT NOT NULL AUTO_INCREMENT,
    nombre       VARCHAR(100) NOT NULL,
    direccion    VARCHAR(150) NOT NULL,
    departamento VARCHAR(30)  NOT NULL,
    PRIMARY KEY (id_complejo),
    UNIQUE (nombre),
    CHECK (departamento IN (
        'Artigas','Canelones','Cerro Largo','Colonia','Durazno','Flores','Florida',
        'Lavalleja','Maldonado','Montevideo','Paysandú','Río Negro','Rivera','Rocha',
        'Salto','San José','Soriano','Tacuarembó','Treinta y Tres'))
);

CREATE TABLE cancha (
    nombre_cancha VARCHAR(50) NOT NULL,
    id_complejo   INT NOT NULL,
    superficie    VARCHAR(20) NOT NULL,
    CHECK (superficie IN ('sintetico','parquet')),
    techada       BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (id_complejo, nombre_cancha),
    FOREIGN KEY (id_complejo) REFERENCES complejo(id_complejo) ON DELETE CASCADE
);

CREATE TABLE turno (
    id_turno    INT NOT NULL,
    hora_inicio TIME NOT NULL,
    hora_fin    TIME NOT NULL,
    PRIMARY KEY (id_turno),
    UNIQUE (hora_inicio),
    CHECK (hora_inicio >= '18:00:00' AND hora_fin <= '23:00:00'),
    CHECK (hora_fin = ADDTIME(hora_inicio, '01:00:00'))
);

CREATE TABLE partido (
    id_partido          INT NOT NULL AUTO_INCREMENT,
    id_torneo           INT NOT NULL,
    numero_fecha        INT NOT NULL,
    id_equipo_local     INT NOT NULL,
    id_equipo_visitante INT NOT NULL,
    dia                 DATE NOT NULL,
    id_turno            INT NOT NULL,
    nombre_cancha       VARCHAR(50) NOT NULL,
    id_complejo         INT NOT NULL,
    estado              VARCHAR(20) NOT NULL DEFAULT 'programado',
    CHECK (estado IN ('programado','jugado','postergado','cancelado')),
    jugado_en           DATETIME NULL,

    PRIMARY KEY (id_partido),

    FOREIGN KEY (id_torneo) REFERENCES torneo(id_torneo),

    FOREIGN KEY (id_equipo_local, id_torneo)     REFERENCES equipo(id_equipo, id_torneo),
    FOREIGN KEY (id_equipo_visitante, id_torneo) REFERENCES equipo(id_equipo, id_torneo),
    FOREIGN KEY (id_turno) REFERENCES turno(id_turno),
    FOREIGN KEY (id_complejo, nombre_cancha) REFERENCES cancha(id_complejo, nombre_cancha),
    CHECK (id_equipo_local <> id_equipo_visitante),
    CHECK (numero_fecha BETWEEN 1 AND 50)
);

CREATE TABLE planilla_partido (
    id_partido INT NOT NULL,
    ci_jugador VARCHAR(8) NOT NULL,
    id_equipo  INT NOT NULL,
    PRIMARY KEY (id_partido, ci_jugador),
    FOREIGN KEY (id_partido) REFERENCES partido(id_partido),

    FOREIGN KEY (id_equipo, ci_jugador) REFERENCES equipo_jugador_torneo(id_equipo, ci_jugador)
);

CREATE TABLE gol (
    id_gol     INT NOT NULL AUTO_INCREMENT,
    id_partido INT NOT NULL,
    ci_jugador VARCHAR(8) NOT NULL,
    minuto     INT NOT NULL,
    autogol    BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (id_gol),

    FOREIGN KEY (id_partido, ci_jugador) REFERENCES planilla_partido(id_partido, ci_jugador),
    CHECK (minuto BETWEEN 0 AND 60)
);

CREATE TABLE tarjeta (
    id_tarjeta INT NOT NULL AUTO_INCREMENT,
    id_partido INT NOT NULL,
    ci_jugador VARCHAR(8) NOT NULL,
    minuto     INT NOT NULL,
    color      VARCHAR(20) NOT NULL,
    CHECK (color IN ('amarilla','roja')),
    PRIMARY KEY (id_tarjeta),
    FOREIGN KEY (id_partido, ci_jugador) REFERENCES planilla_partido(id_partido, ci_jugador),
    CHECK (minuto BETWEEN 0 AND 60)
);

CREATE TABLE sancion_jugador (
    id_sancion          INT NOT NULL AUTO_INCREMENT,
    ci_jugador          VARCHAR(8) NOT NULL,
    id_torneo           INT NOT NULL,
    motivo              VARCHAR(24) NOT NULL,
    CHECK (motivo IN ('roja','acumulacion de amarillas','disciplinaria')),
    numero_fecha_inicio INT NOT NULL,
    cantidad_fechas     INT NOT NULL DEFAULT 1,
    id_tarjeta          INT NULL,
    observacion         VARCHAR(255) NULL,
    creada_en           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_sancion),
    FOREIGN KEY (ci_jugador) REFERENCES jugador(ci),
    FOREIGN KEY (id_torneo)  REFERENCES torneo(id_torneo),
    FOREIGN KEY (id_tarjeta) REFERENCES tarjeta(id_tarjeta),
    CHECK (numero_fecha_inicio BETWEEN 1 AND 50),
    CHECK (cantidad_fechas BETWEEN 1 AND 20),
    CHECK (
        (motivo = 'disciplinaria' AND id_tarjeta IS NULL) OR
        (motivo <> 'disciplinaria' AND id_tarjeta IS NOT NULL AND cantidad_fechas = 1))
);
