"""
Sistema de gestión del Torneo Interfacultades de Fútbol 5 – UCU
Backend: FastAPI + PyMySQL (SQL a mano, sin ORM). Sirve también el frontend.
"""
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from .routers import auth, maestros, partidos, reportes, sanciones, torneos

app = FastAPI(title="Torneo Interfacultades de Fútbol 5 – UCU", version="1.0")

for r in (auth, maestros, torneos, partidos, sanciones, reportes):
    app.include_router(r.router)


@app.exception_handler(RequestValidationError)
async def validacion(_: Request, exc: RequestValidationError):
    """Devuelve los errores de validación de Pydantic en un formato simple para el frontend."""
    errores = []
    for e in exc.errors():
        campo = ".".join(str(x) for x in e["loc"] if x != "body")
        msg = e["msg"].removeprefix("Value error, ")
        errores.append(f"{campo}: {msg}" if campo else msg)
    return JSONResponse(status_code=422, content={"detail": "; ".join(errores)})


@app.get("/api/health")
def health():
    return {"ok": True}


# ---- frontend estático (SPA) ----
FRONT = Path(__file__).resolve().parent.parent.parent / "frontend"
if not FRONT.exists():                                   # dentro del contenedor
    FRONT = Path("/app/frontend")
if FRONT.exists():
    app.mount("/static", StaticFiles(directory=FRONT), name="static")

    @app.get("/", include_in_schema=False)
    def index():
        return FileResponse(FRONT / "index.html")
