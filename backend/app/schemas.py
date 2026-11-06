import datetime as dt
from typing import Literal

from pydantic import BaseModel, EmailStr, Field, field_validator, model_validator

Nombre = Field(min_length=2, max_length=60)

DEPARTAMENTOS = ("Artigas", "Canelones", "Cerro Largo", "Colonia", "Durazno", "Flores", "Florida",
                 "Lavalleja", "Maldonado", "Montevideo", "Paysandú", "Río Negro", "Rivera", "Rocha",
                 "Salto", "San José", "Soriano", "Tacuarembó", "Treinta y Tres")


def ci_valida(ci: str) -> bool:
    """Cédula uruguaya: 7 u 8 dígitos, el último es verificador (pesos 2987634)."""
    if not ci.isdigit() or len(ci) not in (7, 8):
        return False
    base, dv = ci[:-1].zfill(7), int(ci[-1])
    s = sum(int(d) * w for d, w in zip(base, (2, 9, 8, 7, 6, 3, 4)))
    return (10 - s % 10) % 10 == dv


def _strip(v):
    return v.strip() if isinstance(v, str) else v


class Login(BaseModel):
    correo: EmailStr
    contrasena: str = Field(min_length=1, max_length=100)


class UsuarioIn(BaseModel):
    correo: EmailStr
    contrasena: str = Field(min_length=6, max_length=100)
    rol: Literal["administrador", "planillero"]


class FacultadIn(BaseModel):
    nombre: str = Field(min_length=2, max_length=100)
    _s = field_validator("nombre", mode="before")(_strip)


class JugadorIn(BaseModel):
    ci: str
    nombre: str = Nombre
    apellido: str = Nombre
    email: EmailStr
    fecha_nacimiento: dt.date
    id_facultad: int = Field(gt=0)
    tipo: Literal["grado", "posgrado", "docente", "funcionario"]

    _s = field_validator("ci", "nombre", "apellido", mode="before")(_strip)

    @field_validator("ci")
    @classmethod
    def _ci(cls, v):
        v = v.replace(".", "").replace("-", "")
        if not ci_valida(v):
            raise ValueError("cédula inválida (revisá el dígito verificador)")
        return v

    @field_validator("fecha_nacimiento")
    @classmethod
    def _nac(cls, v):
        hoy = dt.date.today()
        edad = hoy.year - v.year - ((hoy.month, hoy.day) < (v.month, v.day))
        if not 16 <= edad <= 90:
            raise ValueError("el jugador debe tener entre 16 y 90 años")
        return v


class TorneoIn(BaseModel):
    nombre: str = Field(min_length=3, max_length=100)
    anio: int = Field(ge=2000, le=2100)
    semestre: Literal[1, 2]
    fecha_inicio: dt.date
    fecha_fin: dt.date

    @model_validator(mode="after")
    def _fechas(self):
        if self.fecha_fin < self.fecha_inicio:
            raise ValueError("la fecha de fin debe ser posterior a la de inicio")
        if self.fecha_inicio.year != self.anio:
            raise ValueError("la fecha de inicio debe caer en el año del torneo")
        return self


class TorneoEstado(BaseModel):
    estado: Literal["inscripcion", "en curso", "finalizado"]


class EquipoIn(BaseModel):
    nombre: str = Nombre
    id_torneo: int = Field(gt=0)
    id_facultad: int = Field(gt=0)
    _s = field_validator("nombre", mode="before")(_strip)


class EquipoUpdate(BaseModel):
    nombre: str = Nombre
    id_facultad: int = Field(gt=0)
    ci_capitan: str | None = None
    _s = field_validator("nombre", mode="before")(_strip)


class PlantelIn(BaseModel):
    ci_jugador: str = Field(pattern=r"^\d{7,8}$")
    numero_camiseta: int = Field(ge=1, le=99)


class CamisetaIn(BaseModel):
    numero_camiseta: int = Field(ge=1, le=99)


class ComplejoIn(BaseModel):
    nombre: str = Field(min_length=2, max_length=100)
    direccion: str = Field(min_length=3, max_length=150)
    departamento: str
    _s = field_validator("nombre", "direccion", mode="before")(_strip)

    @field_validator("departamento")
    @classmethod
    def _depto(cls, v):
        if v not in DEPARTAMENTOS:
            raise ValueError("departamento inválido")
        return v


class CanchaIn(BaseModel):
    nombre_cancha: str = Field(min_length=1, max_length=50)
    superficie: Literal["sintetico", "parquet"]
    techada: bool
    _s = field_validator("nombre_cancha", mode="before")(_strip)


class PartidoIn(BaseModel):
    id_torneo: int = Field(gt=0)
    numero_fecha: int = Field(ge=1, le=50)
    id_equipo_local: int = Field(gt=0)
    id_equipo_visitante: int = Field(gt=0)
    dia: dt.date
    id_turno: int = Field(ge=1)
    id_complejo: int = Field(gt=0)
    nombre_cancha: str = Field(min_length=1, max_length=50)
    estado: Literal["programado", "postergado", "cancelado"] = "programado"

    @model_validator(mode="after")
    def _rivales(self):
        if self.id_equipo_local == self.id_equipo_visitante:
            raise ValueError("un equipo no puede enfrentarse a sí mismo")
        return self


class PartidoEstado(BaseModel):
    estado: Literal["programado", "jugado", "postergado", "cancelado"]


class PlanillaIn(BaseModel):
    ci_jugador: str = Field(pattern=r"^\d{7,8}$")
    id_equipo: int = Field(gt=0)


class GolIn(BaseModel):
    ci_jugador: str = Field(pattern=r"^\d{7,8}$")
    minuto: int = Field(ge=0, le=60)
    autogol: bool = False


class GolUpdate(BaseModel):
    minuto: int = Field(ge=0, le=60)
    autogol: bool = False


class TarjetaIn(BaseModel):
    ci_jugador: str = Field(pattern=r"^\d{7,8}$")
    minuto: int = Field(ge=0, le=60)
    color: Literal["amarilla", "roja"]


class TarjetaUpdate(BaseModel):
    minuto: int = Field(ge=0, le=60)
    color: Literal["amarilla", "roja"]


class SancionIn(BaseModel):
    ci_jugador: str = Field(pattern=r"^\d{7,8}$")
    id_torneo: int = Field(gt=0)
    numero_fecha_inicio: int = Field(ge=1, le=50)
    cantidad_fechas: int = Field(ge=1, le=20)
    observacion: str | None = Field(default=None, max_length=255)


class SancionUpdate(BaseModel):
    numero_fecha_inicio: int = Field(ge=1, le=50)
    cantidad_fechas: int = Field(ge=1, le=20)
    observacion: str | None = Field(default=None, max_length=255)
