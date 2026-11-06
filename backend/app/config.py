import os

DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_PORT = int(os.getenv("DB_PORT", "3306"))
DB_NAME = os.getenv("DB_NAME", "torneo_ucu")

DB_USERS = {
    "auth": (os.getenv("DB_AUTH_USER", "torneo_auth"), os.getenv("DB_AUTH_PASSWORD", "Auth_Torneo_2026!")),
    "administrador": (os.getenv("DB_ADMIN_USER", "torneo_admin"), os.getenv("DB_ADMIN_PASSWORD", "Admin_Torneo_2026!")),
    "planillero": (os.getenv("DB_PLANILLERO_USER", "torneo_planillero"),
                   os.getenv("DB_PLANILLERO_PASSWORD", "Planillero_Torneo_2026!")),
}

DB_TIME_ZONE = os.getenv("DB_TIME_ZONE", "-03:00")

SECRET_KEY = os.getenv("SECRET_KEY", "cambiar-esta-clave-en-produccion")
TOKEN_HORAS = int(os.getenv("TOKEN_HORAS", "12"))
