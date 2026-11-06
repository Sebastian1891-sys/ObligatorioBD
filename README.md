# Torneo Interfacultades de Fútbol 5 · UCU

Sistema de gestión del Torneo Interfacultades de Fútbol 5 (Base de Datos 1 – UCU, 2º semestre 2026).

- **Base de datos:** MySQL 8 — validación de campos e integridad con `PRIMARY KEY`, `FOREIGN KEY`, `UNIQUE`, `NOT NULL` y `CHECK`; dos vistas para consultar partidos y resultados. La tabla de posiciones se calcula en Python.
- **Backend:** Python 3.12 + FastAPI + PyMySQL, **SQL escrito a mano, sin ORM**. Las reglas del torneo están en `backend/app/reglas.py`.
- **Frontend:** HTML + CSS + JavaScript sin frameworks, servido por el mismo backend.
- **Seguridad en la BD:** un usuario de MySQL por rol (`torneo_admin`, `torneo_planillero`, `torneo_auth`) con permisos diferenciados.
- **Docker Compose** con los servicios `db` y `app`.

```
.
├── script_completo.sql          ← los 4 scripts de base_de_datos/ concatenados (para correr de una)
├── base_de_datos/
│   ├── esquema.sql              tablas, claves primarias y foráneas, UNIQUE y CHECK
│   ├── logica.sql               vistas (partidos y resultados)
│   ├── usuarios.sql             usuarios de BD con permisos por rol
│   ├── datos.sql                datos maestros y de prueba (generado)
│   ├── tools/generar_datos.py   genera datos.sql simulando el torneo
│   └── demo/                    script para la defensa
├── backend/                     API FastAPI (app/, reglas en app/reglas.py) + Dockerfile
├── frontend/                    SPA (index.html, app.js, styles.css)
├── docs/                        informe del trabajo (INFORME.pdf / informe.docx)
└── docker-compose.yml
```

---

## Instructivo para correr la aplicación

### Opción A — Docker (recomendada)

Requisitos: Docker Desktop (o Docker Engine + plugin compose).

```bash
git clone https://github.com/Sebastian1891-sys/ObligatorioBD.git
cd ObligatorioBD
docker compose up --build
```

La primera vez MySQL ejecuta los scripts de `base_de_datos/` (tarda ~30 s). Cuando aparezca
`Uvicorn running on http://0.0.0.0:8000`, abrir **http://localhost:8000**.

| Usuario | Contraseña | Rol |
|---|---|---|
| `admin@ucu.edu.uy` | `admin123` | administrador |
| `planillero@ucu.edu.uy` | `planillero123` | planillero |

Comandos útiles:

```bash
docker compose down            # detener
docker compose down -v         # detener y BORRAR la base (vuelve a cargar los datos de prueba al levantar)
docker compose logs -f app     # ver logs del backend
docker exec -it torneo_ucu_mysql mysql -uroot -proot_torneo_2026 torneo_ucu   # consola MySQL
```

La base queda expuesta en el puerto **3307** del host (para conectarse con Workbench/DBeaver:
`127.0.0.1:3307`, usuario `root`, contraseña `root_torneo_2026`).

### Opción B — Local, sin Docker

Requisitos: MySQL 8.0+ y Python 3.10+.

1. **Crear la base** (como root, en este orden — o directamente `script_completo.sql`):

   ```bash
   mysql -uroot -p < script_completo.sql
   ```
   o
   ```bash
   mysql -uroot -p < base_de_datos/esquema.sql
   mysql -uroot -p < base_de_datos/logica.sql
   mysql -uroot -p < base_de_datos/usuarios.sql
   mysql -uroot -p < base_de_datos/datos.sql
   ```
   > Ejecutarlos como **root**: `usuarios.sql` crea los usuarios de base de datos de la aplicación.

2. **Backend:**

   ```bash
   cd backend
   python -m venv .venv
   source .venv/bin/activate          # Windows: .venv\Scripts\activate
   pip install -r requirements.txt
   cp ../.env.example ../.env         # opcional: los valores por defecto ya sirven en local
   uvicorn app.main:app --reload --port 8000
   ```
   Si MySQL no está en `127.0.0.1:3306`, exportar `DB_HOST` / `DB_PORT` antes de levantar uvicorn.

3. Abrir **http://localhost:8000**. La documentación interactiva de la API está en
   **http://localhost:8000/docs**.

### Regenerar los datos de prueba (opcional)

```bash
pip install bcrypt
python base_de_datos/tools/generar_datos.py      # reescribe base_de_datos/datos.sql (con semilla fija; los hashes de contraseñas varían)
cd base_de_datos && cat esquema.sql logica.sql usuarios.sql datos.sql > ../script_completo.sql
```

---

## Datos de prueba incluidos

- **Edición 2026 – 2º semestre (en curso):** 6 equipos (uno por facultad), 8 jugadores por plantel,
  fixture completo a una rueda (5 fechas, 15 partidos).
  - Fechas 1 a 4 disputadas (11 partidos con planilla, goles, autogol y tarjetas).
  - 1 partido **postergado** (fecha 4), 1 **cancelado** (fecha 5), 2 **programados** (fecha 5).
  - Sanciones: una por **roja**, una por **acumulación de 3 amarillas** (calculadas por Python al cargar
    las tarjetas) y una **disciplinaria** de 2 fechas.
  - En cada plantel hay un jugador que nunca jugó (para el reporte correspondiente).
- **Edición 2027 – 1er semestre (inscripción):** 2 equipos, uno con plantel incompleto, para probar el
  ABM de planteles (que solo se permite en esta etapa).

### Para la defensa: cargar una planilla en vivo

La planilla solo se puede cargar **después** de que terminó el turno y **dentro de las 48 h**. Como los
partidos de prueba son de septiembre/octubre, para mostrar la carga en vivo:

- desde la app: **Partidos → partido postergado de la fecha 4 → Editar → día = ayer, estado = programado**, o
- `mysql -uroot -p < base_de_datos/demo/reprogramar_postergado_a_ayer.sql`

Después, con el planillero: **Partidos → Planilla**, marcar jugadores, agregar goles/tarjetas y
**Marcar como jugado**.

---

## Funcionalidades

| Requerimiento | Dónde |
|---|---|
| ABM jugadores | Jugadores (validación de cédula con dígito verificador) |
| ABM equipos y planteles | Equipos y planteles → Plantel |
| ABM complejos y canchas | Complejos y canchas |
| ABM partidos con todas las restricciones | Partidos → Programar / Editar |
| Planillas, goles y tarjetas | Partidos → Planilla (administrador y planillero) |
| ABM sanciones | Sanciones (las automáticas las calcula Python) |
| 9 reportes + 3 propios | Reportes |
| Extra | ABM de ediciones (con avance de estado), facultades y usuarios |

## API

Todos los endpoints están bajo `/api` y se documentan solos en `/docs` (Swagger). Autenticación con
`POST /api/auth/login` → token, que se envía como `Authorization: Bearer <token>`.
