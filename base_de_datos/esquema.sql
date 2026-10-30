

CREATE DATABASE IF NOT EXISTS torneo_ucu;


USE torneo_ucu;

CREATE TABLE facultad (
    id_facultad INT PRIMARY KEY AUTO_INCREMENT,
    nombre VARCHAR(100) NOT NULL
);

INSERT INTO facultad (nombre)
VALUES
('Ingenieria'),
('Derecho'),
('Ciencias Empresariales');

SELECT * FROM facultad;

CREATE TABLE jugador (
    ci VARCHAR(20) PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    apellido VARCHAR(100) NOT NULL,
    email VARCHAR(150),
    fecha_nacimiento DATE,
    id_facultad INT NOT NULL,
    tipo ENUM('grado', 'posgrado', 'docente', 'funcionario') NOT NULL,

    FOREIGN KEY (id_facultad)
        REFERENCES facultad(id_facultad)
);

CREATE TABLE torneo (
    id_torneo INT PRIMARY KEY AUTO_INCREMENT,
    nombre VARCHAR(100) NOT NULL,
    anio INT NOT NULL,
    semestre INT NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    estado ENUM('inscripcion', 'en curso', 'finalizado') NOT NULL
);

CREATE TABLE equipo (
    id_equipo INT PRIMARY KEY AUTO_INCREMENT,
    nombre VARCHAR(100) NOT NULL,
    id_torneo INT NOT NULL,
    id_facultad INT NOT NULL,
    ci_capitan VARCHAR(20),

    FOREIGN KEY (id_torneo)
        REFERENCES torneo(id_torneo),

    FOREIGN KEY (id_facultad)
        REFERENCES facultad(id_facultad),

    FOREIGN KEY (ci_capitan)
        REFERENCES jugador(ci)
);

CREATE TABLE equipo_jugador_torneo (
    id_equipo INT NOT NULL,
    ci_jugador VARCHAR(20) NOT NULL,
    id_torneo INT NOT NULL,
    numero_camiseta INT NOT NULL,

    PRIMARY KEY (id_equipo, ci_jugador, id_torneo),

    FOREIGN KEY (id_equipo)
        REFERENCES equipo(id_equipo),

    FOREIGN KEY (ci_jugador)
        REFERENCES jugador(ci),

    FOREIGN KEY (id_torneo)
        REFERENCES torneo(id_torneo),

    UNIQUE (ci_jugador, id_torneo),
    UNIQUE (id_equipo, numero_camiseta)
);



CREATE TABLE complejo (
    id_complejo INT PRIMARY KEY AUTO_INCREMENT,
    nombre VARCHAR(100) NOT NULL,
    direccion VARCHAR(150) NOT NULL,
    departamento VARCHAR(100) NOT NULL
);

CREATE TABLE cancha (
    nombre_cancha VARCHAR(100) NOT NULL,
    id_complejo INT NOT NULL,
    superficie ENUM('sintetico', 'parquet') NOT NULL,
    techada BOOLEAN NOT NULL,

    PRIMARY KEY (nombre_cancha, id_complejo),

    FOREIGN KEY (id_complejo)
        REFERENCES complejo(id_complejo)
);

CREATE TABLE turno (
    id_turno INT PRIMARY KEY AUTO_INCREMENT,
    hora_inicio TIME NOT NULL,
    hora_fin TIME NOT NULL
);


CREATE TABLE partido (
    id_partido INT PRIMARY KEY AUTO_INCREMENT,
    id_torneo INT NOT NULL,
    numero_fecha INT NOT NULL,
    id_equipo_local INT NOT NULL,
    id_equipo_visitante INT NOT NULL,
    dia DATE NOT NULL,
    id_turno INT NOT NULL,
    nombre_cancha VARCHAR(100) NOT NULL,
    id_complejo INT NOT NULL,
    estado ENUM('programado', 'jugado', 'postergado', 'cancelado') NOT NULL,

    FOREIGN KEY (id_torneo)
        REFERENCES torneo(id_torneo),

    FOREIGN KEY (id_equipo_local)
        REFERENCES equipo(id_equipo),

    FOREIGN KEY (id_equipo_visitante)
        REFERENCES equipo(id_equipo),

    FOREIGN KEY (id_turno)
        REFERENCES turno(id_turno),

    FOREIGN KEY (nombre_cancha, id_complejo)
        REFERENCES cancha(nombre_cancha, id_complejo),

    CHECK (id_equipo_local <> id_equipo_visitante)
);


CREATE TABLE planilla_partido (
    id_partido INT NOT NULL,
    ci_jugador VARCHAR(20) NOT NULL,
    id_equipo INT NOT NULL,

    PRIMARY KEY (id_partido, ci_jugador),

    FOREIGN KEY (id_partido)
        REFERENCES partido(id_partido),

    FOREIGN KEY (ci_jugador)
        REFERENCES jugador(ci),

    FOREIGN KEY (id_equipo)
        REFERENCES equipo(id_equipo)
);

CREATE TABLE gol (
    id_gol INT PRIMARY KEY AUTO_INCREMENT,
    id_partido INT NOT NULL,
    ci_jugador VARCHAR(20) NOT NULL,
    minuto INT NOT NULL,
    autogol BOOLEAN NOT NULL DEFAULT FALSE,

    FOREIGN KEY (id_partido, ci_jugador)
        REFERENCES planilla_partido(id_partido, ci_jugador),

    CHECK (minuto >= 0)
);

CREATE TABLE tarjeta (
    id_tarjeta INT PRIMARY KEY AUTO_INCREMENT,
    id_partido INT NOT NULL,
    ci_jugador VARCHAR(20) NOT NULL,
    minuto INT NOT NULL,
    color ENUM('amarilla', 'roja') NOT NULL,

    FOREIGN KEY (id_partido, ci_jugador)
        REFERENCES planilla_partido(id_partido, ci_jugador),

    CHECK (minuto >= 0)
);


CREATE TABLE sancion_jugador (
    id_sancion INT PRIMARY KEY AUTO_INCREMENT,
    ci_jugador VARCHAR(20) NOT NULL,
    id_torneo INT NOT NULL,
    motivo ENUM('roja', 'acumulacion de amarillas', 'disciplinaria') NOT NULL,
    numero_fecha_inicio INT NOT NULL,
    cantidad_fechas INT NOT NULL,

    FOREIGN KEY (ci_jugador)
        REFERENCES jugador(ci),

    FOREIGN KEY (id_torneo)
        REFERENCES torneo(id_torneo),

    CHECK (numero_fecha_inicio > 0),
    CHECK (cantidad_fechas > 0)
);

CREATE TABLE login (
    correo VARCHAR(150) PRIMARY KEY,
    contrasena VARCHAR(255) NOT NULL,
    rol ENUM('administrador', 'planillero') NOT NULL
);

