DROP DATABASE IF EXISTS torneo_ucu;
CREATE DATABASE torneo_ucu CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE torneo_ucu;

CREATE TABLE login (
    correo      VARCHAR(120) NOT NULL,
    contrasena  VARCHAR(100) NOT NULL,
    rol         ENUM('administrador','planillero') NOT NULL,
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
    tipo             ENUM('grado','posgrado','docente','funcionario') NOT NULL,
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
    anio         SMALLINT NOT NULL,
    semestre     TINYINT  NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin    DATE NOT NULL,
    estado       ENUM('inscripcion','en curso','finalizado') NOT NULL DEFAULT 'inscripcion',
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
    numero_camiseta TINYINT    NOT NULL,
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
    superficie    ENUM('sintetico','parquet') NOT NULL,
    techada       BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (id_complejo, nombre_cancha),
    FOREIGN KEY (id_complejo) REFERENCES complejo(id_complejo) ON DELETE CASCADE
);

CREATE TABLE turno (
    id_turno    TINYINT NOT NULL,
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
    numero_fecha        TINYINT NOT NULL,
    id_equipo_local     INT NOT NULL,
    id_equipo_visitante INT NOT NULL,
    dia                 DATE NOT NULL,
    id_turno            TINYINT NOT NULL,
    nombre_cancha       VARCHAR(50) NOT NULL,
    id_complejo         INT NOT NULL,
    estado              ENUM('programado','jugado','postergado','cancelado') NOT NULL DEFAULT 'programado',
    jugado_en           DATETIME NULL,

    PRIMARY KEY (id_partido),
    KEY ix_partido_fecha (id_torneo, numero_fecha),

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
    minuto     TINYINT NOT NULL,
    autogol    BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (id_gol),
    FOREIGN KEY (id_partido, ci_jugador) REFERENCES planilla_partido(id_partido, ci_jugador),
    CHECK (minuto BETWEEN 0 AND 60)
);

CREATE TABLE tarjeta (
    id_tarjeta INT NOT NULL AUTO_INCREMENT,
    id_partido INT NOT NULL,
    ci_jugador VARCHAR(8) NOT NULL,
    minuto     TINYINT NOT NULL,
    color      ENUM('amarilla','roja') NOT NULL,
    PRIMARY KEY (id_tarjeta),
    FOREIGN KEY (id_partido, ci_jugador) REFERENCES planilla_partido(id_partido, ci_jugador),
    CHECK (minuto BETWEEN 0 AND 60)
);

CREATE TABLE sancion_jugador (
    id_sancion          INT NOT NULL AUTO_INCREMENT,
    ci_jugador          VARCHAR(8) NOT NULL,
    id_torneo           INT NOT NULL,
    motivo              ENUM('roja','acumulacion de amarillas','disciplinaria') NOT NULL,
    numero_fecha_inicio TINYINT NOT NULL,
    cantidad_fechas     TINYINT NOT NULL DEFAULT 1,
    id_tarjeta          INT NULL,
    observacion         VARCHAR(255) NULL,
    creada_en           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_sancion),
    KEY ix_sancion_jugador_torneo (ci_jugador, id_torneo),
    FOREIGN KEY (ci_jugador) REFERENCES jugador(ci),
    FOREIGN KEY (id_torneo)  REFERENCES torneo(id_torneo),
    FOREIGN KEY (id_tarjeta) REFERENCES tarjeta(id_tarjeta),
    CHECK (numero_fecha_inicio BETWEEN 1 AND 50),
    CHECK (cantidad_fechas BETWEEN 1 AND 20),
    CHECK (
        (motivo = 'disciplinaria' AND id_tarjeta IS NULL) OR
        (motivo <> 'disciplinaria' AND id_tarjeta IS NOT NULL AND cantidad_fechas = 1))
);

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
       COALESCE(SUM(CASE WHEN (pl.id_equipo = p.id_equipo_local     AND NOT g.autogol)
                           OR (pl.id_equipo = p.id_equipo_visitante AND g.autogol) THEN 1 ELSE 0 END), 0) AS goles_local,
       COALESCE(SUM(CASE WHEN (pl.id_equipo = p.id_equipo_visitante AND NOT g.autogol)
                           OR (pl.id_equipo = p.id_equipo_local     AND g.autogol) THEN 1 ELSE 0 END), 0) AS goles_visitante
  FROM partido p
  LEFT JOIN gol g               ON g.id_partido = p.id_partido
  LEFT JOIN planilla_partido pl ON pl.id_partido = g.id_partido AND pl.ci_jugador = g.ci_jugador
 GROUP BY p.id_partido, p.id_torneo, p.numero_fecha, p.estado, p.id_equipo_local, p.id_equipo_visitante;

CREATE VIEW v_resultado_equipo AS
SELECT id_torneo, id_partido, numero_fecha, id_equipo_local AS id_equipo,
       goles_local AS gf, goles_visitante AS gc
  FROM v_resultado WHERE estado = 'jugado'
UNION ALL
SELECT id_torneo, id_partido, numero_fecha, id_equipo_visitante,
       goles_visitante, goles_local
  FROM v_resultado WHERE estado = 'jugado';

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

USE torneo_ucu;

INSERT INTO login (correo, contrasena, rol) VALUES
  ('admin@ucu.edu.uy', '$2b$10$JeVp4ylUrzQYAa3SXC7fnOkfvU84JmP5KgbOWWjjpJ5xDj9PTQ9.6', 'administrador'),
  ('planillero@ucu.edu.uy', '$2b$10$9wnvF3UJsEbSjVNNQVp3Xut2.A6RulFuR1BQyoc83chnUJcG9ZiQa', 'planillero'),
  ('planillero2@ucu.edu.uy', '$2b$10$MlUu0tpwnzhLtHaVGqL1e.10rRrLvdkF1bRgPpD2IkUXNzUWps1qa', 'planillero');

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
INSERT INTO tarjeta (id_tarjeta, id_partido, ci_jugador, minuto, color) VALUES
  (1, 1, '36668381', 38, 'amarilla'),
  (2, 1, '61016818', 46, 'amarilla');
UPDATE partido SET estado = 'jugado', jugado_en = NOW() WHERE id_partido = 1;
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
INSERT INTO tarjeta (id_tarjeta, id_partido, ci_jugador, minuto, color) VALUES
  (3, 2, '56955344', 19, 'amarilla');
UPDATE partido SET estado = 'jugado', jugado_en = NOW() WHERE id_partido = 2;
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
INSERT INTO tarjeta (id_tarjeta, id_partido, ci_jugador, minuto, color) VALUES
  (4, 3, '49997145', 6, 'amarilla');
UPDATE partido SET estado = 'jugado', jugado_en = NOW() WHERE id_partido = 3;

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
INSERT INTO tarjeta (id_tarjeta, id_partido, ci_jugador, minuto, color) VALUES
  (5, 4, '36009959', 7, 'amarilla'),
  (6, 4, '54881826', 16, 'amarilla');
UPDATE partido SET estado = 'jugado', jugado_en = NOW() WHERE id_partido = 4;
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
INSERT INTO tarjeta (id_tarjeta, id_partido, ci_jugador, minuto, color) VALUES
  (7, 5, '49997145', 35, 'amarilla');
UPDATE partido SET estado = 'jugado', jugado_en = NOW() WHERE id_partido = 5;
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
INSERT INTO tarjeta (id_tarjeta, id_partido, ci_jugador, minuto, color) VALUES
  (8, 6, '39805510', 40, 'roja');
INSERT INTO sancion_jugador (ci_jugador, id_torneo, motivo, numero_fecha_inicio, cantidad_fechas, id_tarjeta) VALUES
  ('39805510', 1, 'roja', 3, 1, 8);
UPDATE partido SET estado = 'jugado', jugado_en = NOW() WHERE id_partido = 6;

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
INSERT INTO tarjeta (id_tarjeta, id_partido, ci_jugador, minuto, color) VALUES
  (9, 7, '49721588', 14, 'amarilla'),
  (10, 7, '49997145', 15, 'amarilla'),
  (11, 7, '36668381', 17, 'amarilla');

INSERT INTO sancion_jugador (ci_jugador, id_torneo, motivo, numero_fecha_inicio, cantidad_fechas, id_tarjeta) VALUES
  ('49997145', 1, 'acumulacion de amarillas', 4, 1, 10);
UPDATE partido SET estado = 'jugado', jugado_en = NOW() WHERE id_partido = 7;
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
INSERT INTO tarjeta (id_tarjeta, id_partido, ci_jugador, minuto, color) VALUES
  (12, 8, '44268583', 45, 'amarilla');
UPDATE partido SET estado = 'jugado', jugado_en = NOW() WHERE id_partido = 8;
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
INSERT INTO tarjeta (id_tarjeta, id_partido, ci_jugador, minuto, color) VALUES
  (13, 9, '60310740', 50, 'amarilla');
UPDATE partido SET estado = 'jugado', jugado_en = NOW() WHERE id_partido = 9;

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
INSERT INTO tarjeta (id_tarjeta, id_partido, ci_jugador, minuto, color) VALUES
  (14, 10, '35294131', 39, 'amarilla');
UPDATE partido SET estado = 'jugado', jugado_en = NOW() WHERE id_partido = 10;
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
UPDATE partido SET estado = 'jugado', jugado_en = NOW() WHERE id_partido = 11;
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (12, 1, 4, 5, 6, '2026-10-05', 4, 'Cancha A', 3, 'programado');
UPDATE partido SET estado = 'postergado' WHERE id_partido = 12;

INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (13, 1, 5, 1, 2, '2026-11-16', 3, 'Central', 2, 'programado');
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (14, 1, 5, 6, 3, '2026-11-16', 1, 'Cancha 1', 1, 'programado');
INSERT INTO partido (id_partido, id_torneo, numero_fecha, id_equipo_local, id_equipo_visitante, dia, id_turno, nombre_cancha, id_complejo, estado) VALUES
  (15, 1, 5, 4, 5, '2026-11-16', 2, 'Cancha 2', 1, 'programado');
UPDATE partido SET estado = 'cancelado' WHERE id_partido = 15;
