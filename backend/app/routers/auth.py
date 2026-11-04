from fastapi import APIRouter, Depends, HTTPException

from ..db import transaccion
from ..schemas import Login, UsuarioIn
from ..security import check_password, crear_token, db_admin, hash_password, usuario_actual

router = APIRouter(prefix="/api", tags=["auth"])


@router.post("/auth/login")
def login(data: Login):
    with transaccion("auth") as db:
        u = db.one("SELECT correo, contrasena, rol FROM login WHERE correo = %s", (data.correo.lower(),))
    if not u or not check_password(data.contrasena, u["contrasena"]):
        raise HTTPException(401, "Correo o contraseña incorrectos")
    return {"token": crear_token(u["correo"], u["rol"]), "correo": u["correo"], "rol": u["rol"]}


@router.get("/auth/me")
def me(u: dict = Depends(usuario_actual)):
    return u


# --- gestión de usuarios de la aplicación (solo administradores) ---
@router.get("/usuarios")
def listar_usuarios(db=Depends(db_admin)):
    return db.all("SELECT correo, rol FROM login ORDER BY rol, correo")


@router.post("/usuarios", status_code=201)
def crear_usuario(data: UsuarioIn, db=Depends(db_admin)):
    db.execute("INSERT INTO login (correo, contrasena, rol) VALUES (%s, %s, %s)",
               (data.correo.lower(), hash_password(data.contrasena), data.rol))
    return {"correo": data.correo.lower(), "rol": data.rol}


@router.delete("/usuarios/{correo}", status_code=204)
def borrar_usuario(correo: str, db=Depends(db_admin), u: dict = Depends(usuario_actual)):
    if correo.lower() == u["correo"]:
        raise HTTPException(400, "No podés borrar tu propio usuario")
    if db.execute("DELETE FROM login WHERE correo = %s", (correo.lower(),)) == 0:
        raise HTTPException(404, "Usuario no encontrado")
