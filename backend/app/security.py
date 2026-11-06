import base64
import hashlib
import hmac
import json
import time

import bcrypt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from . import config
from .db import transaccion

def hash_password(p: str) -> str:
    return bcrypt.hashpw(p.encode(), bcrypt.gensalt(rounds=10)).decode()

def check_password(p: str, h: str) -> bool:
    try:
        return bcrypt.checkpw(p.encode(), h.encode())
    except ValueError:
        return False

def _b64(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

def _unb64(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))

def crear_token(correo: str, rol: str) -> str:
    payload = _b64(json.dumps({"sub": correo, "rol": rol,
                               "exp": int(time.time()) + config.TOKEN_HORAS * 3600}).encode())
    firma = _b64(hmac.new(config.SECRET_KEY.encode(), payload.encode(), hashlib.sha256).digest())
    return f"{payload}.{firma}"

def leer_token(token: str) -> dict:
    try:
        payload, firma = token.split(".")
        esperada = _b64(hmac.new(config.SECRET_KEY.encode(), payload.encode(), hashlib.sha256).digest())
        if not hmac.compare_digest(firma, esperada):
            raise ValueError
        datos = json.loads(_unb64(payload))
        if datos["exp"] < time.time():
            raise HTTPException(401, "La sesión expiró, volvé a iniciar sesión")
        return datos
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(401, "Token inválido")

bearer = HTTPBearer(auto_error=False)

def usuario_actual(cred: HTTPAuthorizationCredentials | None = Depends(bearer)) -> dict:
    if cred is None:
        raise HTTPException(401, "Iniciá sesión")
    datos = leer_token(cred.credentials)
    with transaccion("auth") as db:
        u = db.one("SELECT correo, rol FROM login WHERE correo = %s", (datos["sub"],))
    if not u or u["rol"] != datos["rol"]:
        raise HTTPException(401, "Usuario inexistente o rol modificado")
    return u

def solo_admin(u: dict = Depends(usuario_actual)) -> dict:
    if u["rol"] != "administrador":
        raise HTTPException(403, "Solo un administrador puede hacer esto")
    return u

def db_usuario(u: dict = Depends(usuario_actual)):
    with transaccion(u["rol"]) as db:
        yield db

def db_admin(u: dict = Depends(solo_admin)):
    with transaccion("administrador") as db:
        yield db
