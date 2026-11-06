import datetime as dt
from contextlib import contextmanager
from decimal import Decimal

import pymysql
from fastapi import HTTPException

from . import config


def _connect(rol: str):
    user, password = config.DB_USERS[rol]
    return pymysql.connect(
        host=config.DB_HOST, port=config.DB_PORT, user=user, password=password,
        database=config.DB_NAME, charset="utf8mb4", autocommit=False,
        cursorclass=pymysql.cursors.DictCursor,
        init_command=f"SET time_zone = '{config.DB_TIME_ZONE}'",
    )

def traducir_error(e: pymysql.MySQLError) -> HTTPException:
    code = e.args[0] if e.args else 0
    if code == 1062:
        return HTTPException(409, "Ya existe un registro con esos datos")
    if code == 3819:
        return HTTPException(400, "Dato inválido: no cumple las restricciones de la base")
    if code in (1451, 1217):
        return HTTPException(409, "No se puede eliminar o modificar: tiene registros asociados")
    if code == 1452:
        return HTTPException(400, "Referencia inválida: alguno de los datos relacionados no existe")
    if code in (1142, 1143, 1370):
        return HTTPException(403, "Tu rol no tiene permiso para esta operación (rechazado por la base de datos)")
    if code in (1048, 1364):
        return HTTPException(400, "Falta un dato obligatorio")
    if code in (1265, 1366, 1292, 1406):
        return HTTPException(400, "Formato de dato inválido")
    if code in (2003, 2013, 1045):
        return HTTPException(503, "No hay conexión con la base de datos")
    return HTTPException(500, f"Error de base de datos ({code})")

def _limpiar(v):

    if isinstance(v, dt.timedelta):
        s = int(v.total_seconds())
        return f"{s // 3600:02d}:{s % 3600 // 60:02d}"
    if isinstance(v, Decimal):
        return int(v) if v == v.to_integral_value() else float(v)
    if isinstance(v, dt.datetime):
        return v.isoformat(sep=" ", timespec="minutes")
    if isinstance(v, dt.date):
        return v.isoformat()
    return v

class Cursor:

    def __init__(self, cur):
        self._cur = cur

    def execute(self, sql, params=None) -> int:

        return self._cur.execute(sql, params)

    def all(self, sql, params=None) -> list[dict]:

        self._cur.execute(sql, params)
        filas = []
        for fila in self._cur.fetchall():
            limpia = {}
            for columna, valor in fila.items():
                limpia[columna] = _limpiar(valor)
            filas.append(limpia)
        return filas

    def one(self, sql, params=None) -> dict | None:

        rows = self.all(sql, params)
        return rows[0] if rows else None

    def one_or_404(self, sql, params=None, que="Registro") -> dict:

        r = self.one(sql, params)
        if r is None:
            raise HTTPException(404, f"{que} no encontrado")
        return r

    @property
    def lastrowid(self):

        return self._cur.lastrowid

@contextmanager
def transaccion(rol: str):
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
