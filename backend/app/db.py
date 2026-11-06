"""
Acceso a datos SIN ORM: PyMySQL + SQL parametrizado.

- Cada conexión se abre con el usuario de BD del rol que corresponde
  (auth / administrador / planillero).
- Todas las consultas usan parámetros (%s): nunca se concatena input del
  usuario en el SQL, lo que evita inyección SQL.
- Los errores de MySQL se traducen a respuestas HTTP con mensajes legibles.
"""
import datetime as dt
from contextlib import contextmanager
from decimal import Decimal

import pymysql
from fastapi import HTTPException

from . import config

# Mensajes para los CHECK del esquema
CHECK_MSG = {
    "chk_jugador_ci": "La cédula debe tener 7 u 8 dígitos, sin puntos ni guion",
    "chk_turno_1h": "Cada turno dura exactamente una hora",
    "chk_jugador_email": "El email del jugador no es válido",
    "chk_jugador_nombre": "Nombre y apellido deben tener al menos 2 caracteres",
    "chk_jugador_nac": "Fecha de nacimiento inválida",
    "chk_torneo_semestre": "El semestre debe ser 1 o 2",
    "chk_torneo_fechas": "La fecha de fin debe ser posterior a la de inicio",
    "chk_torneo_anio_ini": "La fecha de inicio debe caer en el año del torneo",
    "chk_torneo_anio": "Año fuera de rango",
    "chk_ejt_camiseta": "El número de camiseta debe estar entre 1 y 99",
    "chk_complejo_depto": "Departamento inválido",
    "chk_partido_rivales": "Un equipo no puede enfrentarse a sí mismo",
    "chk_partido_fecha": "Número de fecha inválido",
    "chk_gol_minuto": "El minuto debe estar entre 0 y 60",
    "chk_tarjeta_minuto": "El minuto debe estar entre 0 y 60",
    "chk_sancion_cant": "La sanción debe ser de 1 a 20 fechas",
    "chk_sancion_fecha": "Número de fecha inválido",
    "chk_sancion_auto": "Las sanciones manuales solo pueden ser disciplinarias",
    "chk_login_correo": "Correo inválido",
}

# Mensajes para claves únicas
UNIQUE_MSG = {
    "PRIMARY": "Ya existe un registro con esa clave",
    "uq_jugador_email": "Ya hay un jugador con ese email",
    "uq_facultad_nombre": "Ya existe una facultad con ese nombre",
    "uq_torneo_edicion": "Ya existe una edición para ese año y semestre",
    "uq_equipo_nombre_torneo": "Ya hay un equipo con ese nombre en esta edición",
    "uq_jugador_un_equipo_por_torneo": "El jugador ya integra otro equipo en esta edición",
    "uq_camiseta_por_equipo": "Ese número de camiseta ya está usado en el equipo",
    "uq_complejo_nombre": "Ya existe un complejo con ese nombre",
    "uq_turno_inicio": "Ya existe un turno con esa hora",
}


def _connect(rol: str):
    user, password = config.DB_USERS[rol]
    return pymysql.connect(
        host=config.DB_HOST, port=config.DB_PORT, user=user, password=password,
        database=config.DB_NAME, charset="utf8mb4", autocommit=False,
        cursorclass=pymysql.cursors.DictCursor,
        init_command=f"SET time_zone = '{config.DB_TIME_ZONE}'",
    )


def _buscar_mensaje(texto_error: str, mensajes: dict, por_defecto: str) -> str:
    """MySQL incluye el nombre de la restricción en el texto del error
    (por ejemplo "Duplicate entry ... for key 'equipo.uq_equipo_nombre_torneo'").
    Se busca cuál de nuestras restricciones aparece y se devuelve su mensaje."""
    for nombre, mensaje in mensajes.items():
        if f"'{nombre}'" in texto_error or f".{nombre}'" in texto_error:
            return mensaje
    return por_defecto


def traducir_error(e: pymysql.MySQLError) -> HTTPException:
    """Convierte un error de MySQL en una respuesta HTTP con un mensaje entendible."""
    code = e.args[0] if e.args else 0
    msg = str(e.args[1]) if len(e.args) > 1 else str(e)
    if code == 1062:                                   # se violó un UNIQUE o la PRIMARY KEY
        return HTTPException(409, _buscar_mensaje(msg, UNIQUE_MSG, "Registro duplicado"))
    if code == 3819:                                   # se violó un CHECK
        return HTTPException(400, _buscar_mensaje(msg, CHECK_MSG, "Dato inválido"))
    if code in (1451, 1217):                           # FK: hay filas que dependen de esta
        return HTTPException(409, "No se puede eliminar o modificar: tiene registros asociados")
    if code == 1452:                                   # FK: el dato referenciado no existe
        return HTTPException(400, "Referencia inválida: alguno de los datos relacionados no existe")
    if code in (1142, 1143, 1370):                     # GRANT: el usuario de BD del rol no tiene permiso
        return HTTPException(403, "Tu rol no tiene permiso para esta operación (rechazado por la base de datos)")
    if code in (1048, 1364):
        return HTTPException(400, "Falta un dato obligatorio")
    if code in (1265, 1366, 1292, 1406):
        return HTTPException(400, "Formato de dato inválido")
    if code in (2003, 2013, 1045):
        return HTTPException(503, "No hay conexión con la base de datos")
    return HTTPException(500, f"Error de base de datos ({code})")


def _limpiar(v):
    """Pasa los tipos de MySQL a valores que se pueden mandar como JSON."""
    if isinstance(v, dt.timedelta):                    # columnas TIME
        s = int(v.total_seconds())
        return f"{s // 3600:02d}:{s % 3600 // 60:02d}"
    if isinstance(v, Decimal):                         # SUM/AVG de MySQL devuelven DECIMAL
        return int(v) if v == v.to_integral_value() else float(v)
    if isinstance(v, dt.datetime):
        return v.isoformat(sep=" ", timespec="minutes")
    if isinstance(v, dt.date):
        return v.isoformat()
    return v


class Cursor:
    """Cursor de PyMySQL con cuatro atajos para no repetir código en los endpoints.
    En todos, `params` son los valores que reemplazan a los %s del SQL."""

    def __init__(self, cur):
        self._cur = cur

    def execute(self, sql, params=None) -> int:
        """INSERT / UPDATE / DELETE. Devuelve cuántas filas se afectaron."""
        return self._cur.execute(sql, params)

    def all(self, sql, params=None) -> list[dict]:
        """SELECT que devuelve todas las filas, cada una como diccionario {columna: valor}."""
        self._cur.execute(sql, params)
        return [{k: _limpiar(v) for k, v in r.items()} for r in self._cur.fetchall()]

    def one(self, sql, params=None) -> dict | None:
        """SELECT que devuelve la primera fila, o None si no hay ninguna."""
        rows = self.all(sql, params)
        return rows[0] if rows else None

    def one_or_404(self, sql, params=None, que="Registro") -> dict:
        """Como one(), pero si no hay fila responde 404 '<que> no encontrado'."""
        r = self.one(sql, params)
        if r is None:
            raise HTTPException(404, f"{que} no encontrado")
        return r

    @property
    def lastrowid(self):
        """id AUTO_INCREMENT generado por el último INSERT."""
        return self._cur.lastrowid


@contextmanager
def transaccion(rol: str):
    """Un request = una transacción.
    Abre la conexión con el usuario de BD del rol, deja usar el cursor, y al
    terminar hace COMMIT. Si algo falla (una regla, un error de MySQL), hace
    ROLLBACK y no queda nada guardado a medias."""
    try:
        conn = _connect(rol)
    except pymysql.MySQLError as e:
        raise traducir_error(e)
    try:
        with conn.cursor() as cur:
            yield Cursor(cur)
        conn.commit()
    except pymysql.MySQLError as e:
        conn.rollback()
        raise traducir_error(e)
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
