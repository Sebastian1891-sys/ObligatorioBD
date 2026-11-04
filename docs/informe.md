# Informe – Sistema de Gestión del Torneo Interfacultades de Fútbol 5

**Base de Datos 1 – Universidad Católica del Uruguay – Segundo semestre 2026**
**Integrantes:** _[completar]_
**Repositorio:** https://github.com/Sebastian1891-sys/ObligatorioBD

---

## 1. Resumen

Se diseñó e implementó un sistema para que la organización del Torneo Interfacultades de Fútbol 5
gestione ediciones, equipos, planteles, fixture, planillas de juego, sanciones y reportes, reemplazando
las planillas de cálculo y los grupos de mensajería.

| Capa | Tecnología | Decisión |
|---|---|---|
| Base de datos | MySQL 8.0 | Motor exigido. Se aprovechan `CHECK`, columnas generadas, funciones de ventana y triggers. |
| Backend | Python 3.12, FastAPI, PyMySQL | Sin ORM (exigido): todo el SQL está escrito a mano y parametrizado. |
| Frontend | HTML, CSS y JavaScript sin frameworks | No requiere compilación; lo sirve el propio backend. |
| Infraestructura | Docker Compose (`db` + `app`) | Un solo comando levanta todo con los datos de prueba. |

---

## 2. Modelo de datos

Se respetaron todas las tablas y atributos pedidos en la letra. A continuación, las decisiones tomadas
sobre claves y las mejoras agregadas.

### 2.1 Claves y restricciones relevantes

- **`equipo_jugador_torneo`**: PK `(id_equipo, ci_jugador)` y además `UNIQUE (ci_jugador, id_torneo)`.
  Esa clave única implementa de forma **declarativa** la regla *"un jugador no puede integrar más de un
  equipo en una misma edición"*. El `id_torneo` (redundante con el del equipo) queda atado al equipo por
  una **FK compuesta** `(id_equipo, id_torneo) → equipo(id_equipo, id_torneo)`, así nunca puede quedar
  inconsistente.
- **`partido`**: las FK de local y visitante son compuestas `(id_equipo_local, id_torneo)` y
  `(id_equipo_visitante, id_torneo)` contra `equipo(id_equipo, id_torneo)`. Con eso la base garantiza
  que **ambos equipos pertenecen a la misma edición del partido** sin necesidad de código.
- **`planilla_partido`**: FK `(id_equipo, ci_jugador) → equipo_jugador_torneo`. Solo puede figurar en
  la planilla alguien que está en el plantel del equipo indicado.
- **`gol` y `tarjeta`**: FK `(id_partido, ci_jugador) → planilla_partido`. *"Solo pueden convertir goles
  o recibir tarjetas los jugadores que figuren en la planilla"* queda resuelto por integridad referencial.
- **`cancha`**: PK compuesta `(id_complejo, nombre_cancha)`, como en la letra.
- **`turno`**: `CHECK` de que empieza en punto, dura una hora y está entre 18:00 y 23:00.

### 2.2 Columnas generadas para reglas de unicidad "condicionales"

Dos reglas dicen "no puede haber dos … **salvo** que uno esté cancelado/postergado". Un `UNIQUE` común
no sirve porque bloquearía también los partidos cancelados. Se resolvió con **columnas generadas** que
valen `1` cuando el partido cuenta y `NULL` cuando no (MySQL permite varios `NULL` en un índice único):

```sql
ocupa_cancha TINYINT GENERATED ALWAYS AS (IF(estado IN ('programado','jugado'), 1, NULL)) STORED,
par_activo   TINYINT GENERATED ALWAYS AS (IF(estado <> 'cancelado', 1, NULL)) STORED,
equipo_menor INT     GENERATED ALWAYS AS (LEAST(id_equipo_local, id_equipo_visitante)) STORED,
equipo_mayor INT     GENERATED ALWAYS AS (GREATEST(id_equipo_local, id_equipo_visitante)) STORED,

UNIQUE KEY uq_cancha_dia_turno (id_complejo, nombre_cancha, dia, id_turno, ocupa_cancha),
UNIQUE KEY uq_enfrentamiento   (id_torneo, equipo_menor, equipo_mayor, par_activo)
```

`LEAST/GREATEST` hacen que A-vs-B y B-vs-A sean el mismo enfrentamiento.

### 2.3 Atributos y tablas agregadas (mejoras al modelo)

| Dónde | Agregado | Para qué |
|---|---|---|
| `login.contrasena` | Se guarda un **hash bcrypt**, nunca la contraseña | Seguridad; `CHECK` de largo mínimo del hash. |
| `torneo` | `UNIQUE (anio, semestre)` | Una edición por semestre. |
| `equipo.ci_capitan` | Admite `NULL` | El equipo se crea antes de tener plantel; el capitán se asigna después (un trigger exige que sea del plantel). |
| `equipo_jugador_torneo` | `UNIQUE (id_equipo, numero_camiseta)` | No se repiten números en un equipo. |
| `partido.jugado_en` | `DATETIME` | Momento en que se marcó como jugado (trazabilidad). |
| `sancion_jugador.id_tarjeta` | FK a la tarjeta que originó la sanción | Trazabilidad y regeneración de sanciones automáticas. |
| `sancion_jugador.observacion`, `creada_en` | Texto y fecha | Motivo de las disciplinarias y auditoría. |
| `sancion_jugador` | `CHECK` | Las disciplinarias no tienen tarjeta; las automáticas sí y duran 1 fecha. |
| Vistas | `v_partido`, `v_resultado`, `v_resultado_equipo`, `v_tabla_posiciones` | El **resultado no se almacena**: se calcula siempre a partir de los goles (como pide la letra), evitando que el marcador quede desincronizado de los goles. |

---

## 3. Dónde se valida cada regla

La letra pide validación en todas las capas. El criterio fue: **la base es la autoridad final** (cualquier
cliente que se conecte, incluso por consola, tiene que respetar las reglas); el backend valida formato y
devuelve mensajes claros; el frontend evita errores obvios antes de enviar.

| Regla | Base de datos | Backend | Frontend |
|---|---|---|---|
| Plantel de 5 a 10 jugadores | Trigger `trg_plantel_bi` (máx. 10); `sp_validar_partido` (mín. 5 al programar); `trg_torneo_bu` (mín. 5 para iniciar) | — | Contador `x/10` y aviso "mín. 5" |
| Máx. 2 docentes/funcionarios | Trigger `trg_plantel_bi` | — | Contador en el plantel |
| Jugadores de la facultad del equipo | Trigger `trg_plantel_bi` | Endpoint `disponibles` solo ofrece los de esa facultad | Selector filtrado |
| Un equipo por jugador y edición | `UNIQUE (ci_jugador, id_torneo)` | Traducción del error a mensaje | Selector filtrado |
| Planteles solo en inscripción | Triggers `trg_plantel_bi/bu/bd`, `trg_equipo_bi/bd` | — | Botones ocultos fuera de inscripción |
| Capitán es del plantel | Trigger `trg_equipo_bu` | — | Selector con el plantel |
| Ambos equipos de la misma edición | FK compuestas | — | Solo se listan equipos de la edición |
| Un equipo no se enfrenta a sí mismo | `CHECK chk_partido_rivales` + trigger | Validador Pydantic | Validación antes de enviar |
| No repetir rival (salvo cancelado) | `UNIQUE uq_enfrentamiento` + trigger con mensaje | — | — |
| Un partido por equipo y fecha | Trigger (`sp_validar_partido`) | — | — |
| Una cancha por día y turno | `UNIQUE uq_cancha_dia_turno` + trigger con mensaje | — | — |
| Marcar jugado solo si el turno pasó | Trigger (`sp_validar_partido`) | Exige planilla cargada | Botón solo si corresponde |
| Partido jugado no se elimina ni modifica | Trigger `trg_partido_bd/bu` | Chequeo previo | Botones ocultos |
| Planilla: jugadores del plantel y no suspendidos | FK a plantel + trigger `trg_planilla_bi` (`fn_jugador_suspendido`) | — | Suspendidos deshabilitados y marcados |
| Goles y tarjetas solo de quien está en planilla | FK a `planilla_partido` | Chequeo previo con mensaje | Selector solo con jugadores de la planilla |
| Corrección solo dentro de 48 h | `sp_validar_ventana_planilla` en todos los triggers de planilla, gol y tarjeta | — | Planilla en modo lectura fuera de la ventana |
| Sanción automática (roja / 3 amarillas) | Triggers de `tarjeta` + `sp_regenerar_sanciones_auto` | Las automáticas no se editan por API | Marcadas como "automática" |
| Estados del torneo solo avanzan | Trigger `trg_torneo_bu` | Enum Pydantic | Botón "Iniciar"/"Finalizar" |
| Formatos (CI, email, minutos, fechas) | `CHECK` (regex de CI y email, rangos) | Pydantic: dígito verificador de CI, edad 16–90, `EmailStr`, rangos | `required`, `pattern`, `min/max`, validador de CI en JS |

Todas las violaciones de reglas en triggers se informan con `SIGNAL SQLSTATE '45000'` y un mensaje en
español; el backend (`db.traducir_error`) devuelve ese mensaje tal cual con código 400, y traduce
también los errores de `UNIQUE`, `CHECK` y FK a mensajes legibles.

### 3.1 Sanciones automáticas

En lugar de insertar una sanción cada vez que llega una tarjeta (lo que deja inconsistencias si después
se corrige o borra una tarjeta dentro de las 48 h), el procedimiento `sp_regenerar_sanciones_auto`
**recalcula** todas las sanciones automáticas del jugador en la edición a partir de sus tarjetas:

- cada roja → 1 fecha, en la fecha siguiente;
- cada 3 amarillas acumuladas en la edición (la 3ª, 6ª, 9ª…) → 1 fecha, en la fecha siguiente.

Se ejecuta en `AFTER INSERT` / `AFTER UPDATE` de `tarjeta` y en `BEFORE DELETE` (excluyendo la tarjeta
que se borra). Así, por ejemplo, si el planillero carga una roja por error y la borra, la sanción
desaparece sola. Las disciplinarias no se tocan.

### 3.2 La ventana de 48 horas y los datos de prueba

La planilla (y sus goles y tarjetas) solo se acepta entre el fin del turno y las 48 h siguientes. Eso
haría imposible cargar datos históricos de prueba, así que `fn_carga_inicial()` habilita una excepción
**solo** si quien ejecuta es `root` **y** activó la variable de sesión `@carga_datos = 1` (lo hace
`datos.sql`). Los usuarios de la aplicación no son root, así que no pueden usarla aunque seteen la
variable.

---

## 4. Seguridad

### 4.1 Usuarios de base de datos con permisos diferenciados

La aplicación **nunca** se conecta como root. En cada request el backend abre la conexión con el usuario
de MySQL que corresponde al rol del usuario logueado:

| Usuario MySQL | Permisos |
|---|---|
| `torneo_auth` | Solo `SELECT` sobre `login` (autenticación). |
| `torneo_admin` | `SELECT, INSERT, UPDATE, DELETE, EXECUTE` sobre el esquema. No puede crear/borrar tablas ni usuarios. |
| `torneo_planillero` | `SELECT` sobre lo necesario para ver partidos y planteles; `INSERT/DELETE` en `planilla_partido`; `INSERT/UPDATE/DELETE` en `gol` y `tarjeta`; **`UPDATE (estado)` a nivel de columna** en `partido`; **sin acceso** a `login`. |

Esto es defensa en profundidad: aunque hubiera un error en el backend, un planillero no podría, por
ejemplo, borrar un equipo o cambiar el día de un partido — lo rechaza MySQL
(`ERROR 1142/1143 … command denied`), y el backend lo traduce a un 403. Los triggers corren con los
permisos de su *definer*, por eso el planillero puede generar sanciones automáticas sin tener permiso de
escritura sobre `sancion_jugador`.

### 4.2 Aplicación

- Contraseñas con **bcrypt** (salt + costo 10).
- Sesión con un **token firmado con HMAC-SHA256** y vencimiento (12 h), implementado con la librería
  estándar. En cada request se verifica que el usuario siga existiendo y con el mismo rol.
- **Todas** las consultas usan parámetros (`%s`) de PyMySQL: ningún dato del usuario se concatena en el
  SQL, lo que previene inyección SQL. Los únicos fragmentos armados dinámicamente son nombres de columna
  fijos definidos en el código.
- El frontend escapa todo lo que muestra (`esc()`), evitando XSS.

---

## 5. Backend sin ORM

`app/db.py` es una capa mínima sobre PyMySQL: abre la conexión con el usuario del rol, entrega un cursor
con helpers (`all`, `one`, `one_or_404`), hace `commit` al terminar el request o `rollback` si algo
falló, y traduce los errores de MySQL. Cada endpoint escribe su SQL explícitamente. Pydantic se usa
**solo para validar la entrada**, no para mapear tablas.

Organización:

| Archivo | Contenido |
|---|---|
| `routers/auth.py` | login, usuario actual, ABM de usuarios de la app |
| `routers/maestros.py` | ABM de facultades, jugadores, complejos y canchas; turnos |
| `routers/torneos.py` | ABM de ediciones (y avance de estado), equipos y planteles |
| `routers/partidos.py` | ABM de partidos, planilla, goles y tarjetas |
| `routers/sanciones.py` | ABM de sanciones disciplinarias, listado de todas |
| `routers/reportes.py` | los 12 reportes (SQL a mano) |

---

## 6. Reportes

| # | Reporte | Técnica SQL destacada |
|---|---|---|
| 1 | Tabla de posiciones | Vista `v_tabla_posiciones` sobre `v_resultado_equipo` (`UNION ALL` local/visitante); orden por puntos, DG y GF con `ROW_NUMBER()` |
| 2 | Goleadores (top 10) | Excluye autogoles; solo partidos jugados |
| 3 | Fair play por equipo | `LEFT JOIN` para incluir equipos sin tarjetas; puntaje 1/3 |
| 4 | Promedio de goles por fecha y total | `GROUP BY … WITH ROLLUP` + `GROUPING()` para la fila total |
| 5 | Canchas y turnos más utilizados | Agregación por cancha × turno con totales por ventana (`SUM(COUNT(*)) OVER (PARTITION BY …)`) |
| 6 | Jugadores por facultad y tipo | Pivot con `SUM(tipo = '…')` |
| 7 | Inscriptos que nunca figuraron en planilla | `NOT EXISTS` |
| 8 | Sanciones por equipo y motivo | Pivot + total de fechas de suspensión |
| 9 | % jugados vs. postergados/cancelados | Porcentaje con `SUM(COUNT(*)) OVER ()` |

**Consultas propuestas por el grupo:**

| # | Reporte | Por qué es útil |
|---|---|---|
| 10 | Jugadores a una amarilla de ser suspendidos (`HAVING COUNT(*) % 3 = 2`) | Los capitanes y la organización saben quién está "al límite" antes de la próxima fecha. |
| 11 | Distribución de goles por tramo de 10 minutos | Muestra en qué momento del partido se definen los resultados (dato deportivo para el área). |
| 12 | Rendimiento como local y como visitante | Puntos de cada equipo según la condición; ayuda a evaluar si la asignación local/visitante es equitativa. |

---

## 7. Datos de prueba

`base_de_datos/datos.sql` se genera con `base_de_datos/tools/generar_datos.py`, que **simula el torneo fecha por fecha**
aplicando las mismas reglas que la base (suspensiones por roja, por acumulación y disciplinarias) para
que todas las inserciones pasen los triggers. Es determinístico (semilla fija). Incluye 6 equipos,
4 fechas disputadas (más de las 3 pedidas), un partido postergado, uno cancelado, un autogol, una roja,
una acumulación de amarillas, una sanción disciplinaria y una segunda edición en inscripción. Las cédulas
tienen dígito verificador válido.

---

## 8. Pruebas realizadas

Además de usar la aplicación, se verificó cada regla contra la base y la API:

- Agregar jugador a un plantel con el torneo en curso → rechazado.
- Tercer docente/funcionario en un plantel → rechazado. Undécimo jugador → rechazado.
- Jugador de otra facultad → rechazado.
- Programar un enfrentamiento repetido → rechazado; repetirlo cuando el anterior fue cancelado → aceptado.
- Equipo contra sí mismo; cancha ocupada; marcar jugado un partido futuro → rechazados.
- Eliminar un partido jugado → rechazado.
- Agregar a la planilla un jugador suspendido → rechazado.
- Gol de un jugador que no está en planilla; minuto 75 → rechazados.
- Roja → genera sanción para la fecha siguiente; borrar esa roja → la sanción desaparece.
- Corregir un partido de hace más de 48 h → rechazado.
- Planillero intentando borrar un equipo o cambiar el día de un partido directamente en MySQL →
  `command denied`; intentando leer `login` → `command denied`.
- Iniciar una edición con equipos incompletos; volver un torneo a inscripción → rechazados.
- Cédula con dígito verificador incorrecto → rechazada en frontend y backend.

---

## 9. Limitaciones y mejoras futuras

- **Generación automática del fixture** (algoritmo round-robin) en vez de cargar partido por partido.
- **Auditoría**: tabla de log de cambios de planilla con usuario y fecha (hoy queda `jugado_en` y la
  fecha de creación de sanciones).
- Si se borra una tarjeta que generó una sanción ya cumplida, la sanción se recalcula igual; podría
  agregarse un estado "cumplida" para congelarla.
- Paginación en los listados si el volumen de jugadores crece mucho.
- Tokens revocables (lista de sesiones) y cambio de contraseña desde la app.

---

## 10. Bitácora

_Completar con las fechas y responsables reales del grupo._

| Fecha | Integrante(s) | Trabajo realizado |
|---|---|---|
| 09/10/2026 | | Entrega de la letra. Lectura y relevamiento de reglas. |
| | | Diseño del modelo: claves compuestas, columnas generadas, decisiones sobre sanciones. |
| | | Script DDL (`esquema.sql`) y triggers/vistas (`logica.sql`). |
| 30/10/2026 | | Entrega de avance. |
| | | Usuarios de BD por rol (`usuarios.sql`) y generador de datos de prueba. |
| | | Backend FastAPI: ABMs, planilla, sanciones y reportes. |
| | | Frontend y pruebas de reglas de negocio. |
| | | Docker Compose, instructivo e informe. |
| 06/11/2026 | | Entrega final. |

---

## 11. Bibliografía

- Elmasri, R. y Navathe, S. B. *Fundamentals of Database Systems*, 7.ª ed. Pearson, 2016.
- Silberschatz, A., Korth, H. F. y Sudarshan, S. *Database System Concepts*, 7.ª ed. McGraw-Hill, 2019.
- Codd, E. F. "A Relational Model of Data for Large Shared Data Banks". *Communications of the ACM*,
  13(6), 1970.
- Oracle. *MySQL 8.0 Reference Manual* — CREATE TRIGGER, SIGNAL, CHECK Constraints, Generated Columns,
  Window Functions, GRANT (privilegios a nivel de columna). https://dev.mysql.com/doc/refman/8.0/en/
- FastAPI. *Documentación oficial*. https://fastapi.tiangolo.com/
- PyMySQL. *Documentación oficial*. https://pymysql.readthedocs.io/
- Pydantic. *Documentación oficial (v2)*. https://docs.pydantic.dev/
- Docker. *Docker Compose file reference*. https://docs.docker.com/compose/
- Docker Hub. *mysql – Official Image* (inicialización con `/docker-entrypoint-initdb.d`).
  https://hub.docker.com/_/mysql
- OWASP. *SQL Injection Prevention Cheat Sheet*. https://cheatsheetseries.owasp.org/
- Material del curso Base de Datos 1, UCU, 2026.
