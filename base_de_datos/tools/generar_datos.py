"""
Genera base_de_datos/datos.sql con datos de prueba coherentes.

Simula el torneo fecha por fecha respetando las mismas reglas que la base
(suspensiones por roja, por acumulación de 3 amarillas y disciplinarias), para
que todas las inserciones pasen los triggers. Es determinístico (semilla fija),
así que regenerarlo da siempre el mismo archivo.

    python base_de_datos/tools/generar_datos.py
"""
import random
from pathlib import Path

import bcrypt

R = random.Random(2026)
OUT = Path(__file__).resolve().parent.parent / "datos.sql"


def q(v):
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, (int, float)):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


def digito_verificador(base7):
    """Dígito verificador de la cédula uruguaya (pesos 2987634)."""
    d = f"{base7:07d}"
    s = sum(int(x) * w for x, w in zip(d, (2, 9, 8, 7, 6, 3, 4)))
    return str((10 - s % 10) % 10)


def ins(table, cols, rows):
    if not rows:
        return ""
    vals = ",\n  ".join("(" + ", ".join(q(v) for v in r) + ")" for r in rows)
    return f"INSERT INTO {table} ({', '.join(cols)}) VALUES\n  {vals};\n"


sql = []
w = sql.append

w("-- =====================================================================\n"
  "--  datos.sql : datos maestros y datos de prueba\n"
  "--  GENERADO por base_de_datos/tools/generar_datos.py (no editar a mano)\n"
  "--  Torneo 2026-S2 en curso: 6 equipos, fechas 1 a 4 disputadas,\n"
  "--  un partido postergado, fecha 5 programada (uno cancelado),\n"
  "--  más una edición 2027-S1 en inscripción.\n"
  "-- =====================================================================\n"
  "USE torneo_ucu;\n"
  "SET @carga_datos = 1;  -- habilita cargar planillas históricas (solo root)\n\n")

# ---------------------------------------------------------------- login
usuarios = [
    ("admin@ucu.edu.uy", "admin123", "administrador"),
    ("planillero@ucu.edu.uy", "planillero123", "planillero"),
    ("planillero2@ucu.edu.uy", "planillero123", "planillero"),
]
w("-- usuarios de la aplicación (contraseñas hasheadas con bcrypt)\n")
w("-- admin@ucu.edu.uy / admin123   ·   planillero@ucu.edu.uy / planillero123\n")
w(ins("login", ["correo", "contrasena", "rol"],
      [(c, bcrypt.hashpw(p.encode(), bcrypt.gensalt(rounds=10)).decode(), r) for c, p, r in usuarios]))

# ---------------------------------------------------------------- facultades
facultades = ["Ingeniería y Tecnologías", "Ciencias Empresariales", "Derecho",
              "Ciencias de la Salud", "Ciencias Humanas", "Psicología", "Odontología"]
w("\n" + ins("facultad", ["id_facultad", "nombre"], [(i + 1, n) for i, n in enumerate(facultades)]))

# ---------------------------------------------------------------- turnos
w("\n" + ins("turno", ["id_turno", "hora_inicio", "hora_fin"],
             [(i + 1, f"{18 + i}:00:00", f"{19 + i}:00:00") for i in range(5)]))

# ---------------------------------------------------------------- complejos / canchas
complejos = [
    (1, "Complejo Fútbol 5 Buceo", "Av. Rivera 3450", "Montevideo"),
    (2, "Arena Malvín", "Av. Italia 4820", "Montevideo"),
    (3, "Gol Center Ciudad de la Costa", "Av. Giannattasio km 21", "Canelones"),
]
canchas = [
    ("Cancha 1", 1, "sintetico", False), ("Cancha 2", 1, "sintetico", True),
    ("Central", 2, "parquet", True), ("Anexo", 2, "sintetico", False),
    ("Cancha A", 3, "sintetico", False),
]
w("\n" + ins("complejo", ["id_complejo", "nombre", "direccion", "departamento"], complejos))
w(ins("cancha", ["nombre_cancha", "id_complejo", "superficie", "techada"], canchas))

# ---------------------------------------------------------------- jugadores
nombres = ["Mateo", "Santiago", "Joaquín", "Bruno", "Facundo", "Nicolás", "Agustín", "Martín",
           "Federico", "Gonzalo", "Diego", "Lucas", "Tomás", "Rodrigo", "Ignacio", "Pablo",
           "Valentina", "Sofía", "Camila", "Lucía", "Florencia", "Micaela", "Juan", "Sebastián",
           "Emiliano", "Maximiliano", "Germán", "Andrés", "Marcos", "Felipe"]
apellidos = ["Rodríguez", "González", "Fernández", "Pérez", "Silva", "Martínez", "Sosa", "López",
             "Díaz", "Suárez", "Pereira", "Cabrera", "Núñez", "Olivera", "Méndez", "Acosta",
             "Ferreira", "Castro", "Romero", "Álvarez", "Benítez", "Viera", "Techera", "Correa"]

jugadores = []        # (ci, nombre, apellido, email, nac, fac, tipo)
por_facultad = {}
ci_base = 3_512_300
used_emails = set()
for fid in range(1, len(facultades) + 1):
    n_jug = 10 if fid <= 6 else 4
    # perfil de tipos por facultad: 2 docentes/funcionarios como máximo en el plantel
    tipos = ["grado"] * 6 + ["posgrado", "docente", "funcionario", "grado"]
    if fid == 3:
        tipos = ["grado"] * 5 + ["posgrado", "posgrado", "docente", "grado", "docente"]
    lst = []
    for k in range(n_jug):
        ci_base += R.randint(1500, 98000)
        ci = str(ci_base) + digito_verificador(ci_base)
        nom, ape = R.choice(nombres), R.choice(apellidos)
        tipo = tipos[k] if k < len(tipos) else "grado"
        base = f"{nom}.{ape}".lower()
        for a, b in (("á", "a"), ("é", "e"), ("í", "i"), ("ó", "o"), ("ú", "u"), ("ñ", "n")):
            base = base.replace(a, b)
        email, i = f"{base}@{'ucu.edu.uy' if tipo in ('docente', 'funcionario') else 'correo.ucu.edu.uy'}", 2
        while email in used_emails:
            email = email.replace("@", f"{i}@", 1); i += 1
        used_emails.add(email)
        anio = R.randint(1972, 1990) if tipo in ("docente", "funcionario") else (
            R.randint(1994, 2001) if tipo == "posgrado" else R.randint(2002, 2007))
        nac = f"{anio}-{R.randint(1, 12):02d}-{R.randint(1, 28):02d}"
        jugadores.append((ci, nom, ape, email, nac, fid, tipo))
        lst.append(ci)
    por_facultad[fid] = lst
w("\n" + ins("jugador", ["ci", "nombre", "apellido", "email", "fecha_nacimiento", "id_facultad", "tipo"], jugadores))

# ---------------------------------------------------------------- torneos
w("\n-- las ediciones se crean en inscripción y luego avanzan de estado (como en la app)\n")
w(ins("torneo", ["id_torneo", "nombre", "anio", "semestre", "fecha_inicio", "fecha_fin", "estado"], [
    (1, "Torneo Interfacultades 2026 – 2º semestre", 2026, 2, "2026-09-07", "2026-11-30", "inscripcion"),
    (2, "Torneo Interfacultades 2027 – 1er semestre", 2027, 1, "2027-03-15", "2027-07-09", "inscripcion"),
]))

nombres_equipo = {1: "Los Compiladores", 2: "Balance Cero", 3: "Fallo Unánime",
                  4: "Bisturí FC", 5: "Humanistas Unidos", 6: "Inconsciente Colectivo"}
equipos = [(fid, nombres_equipo[fid], 1, fid) for fid in range(1, 7)]
w("\n" + ins("equipo", ["id_equipo", "nombre", "id_torneo", "id_facultad"], equipos))

# planteles: 8 jugadores por equipo (el 8º nunca juega -> reporte de "nunca figuraron")
planteles = {}
filas = []
for fid in range(1, 7):
    cis = por_facultad[fid][:8]
    planteles[fid] = cis
    camisetas = R.sample(range(1, 24), len(cis))
    for ci, nro in zip(cis, camisetas):
        filas.append((fid, ci, 1, nro))
w(ins("equipo_jugador_torneo", ["id_equipo", "ci_jugador", "id_torneo", "numero_camiseta"], filas))

w("\n-- capitanes (deben ser del plantel)\n")
for fid in range(1, 7):
    w(f"UPDATE equipo SET ci_capitan = {q(planteles[fid][0])} WHERE id_equipo = {fid};\n")

# edición 2027-1 en inscripción: dos equipos, uno con plantel incompleto
w("\n" + ins("equipo", ["id_equipo", "nombre", "id_torneo", "id_facultad"],
             [(7, "Los Compiladores 2.0", 2, 1), (8, "Sonrisa Perfecta", 2, 7)]))
w(ins("equipo_jugador_torneo", ["id_equipo", "ci_jugador", "id_torneo", "numero_camiseta"],
      [(7, ci, 2, i + 1) for i, ci in enumerate(por_facultad[1][:6])] +
      [(8, ci, 2, i + 10) for i, ci in enumerate(por_facultad[7][:3])]))
w(f"UPDATE equipo SET ci_capitan = {q(por_facultad[1][1])} WHERE id_equipo = 7;\n")

w("\nUPDATE torneo SET estado = 'en curso' WHERE id_torneo = 1;\n")

# ---------------------------------------------------------------- fixture (round robin, 5 fechas)
fixture = {
    1: [(1, 6), (2, 5), (3, 4)],
    2: [(5, 1), (6, 4), (2, 3)],
    3: [(1, 4), (3, 5), (6, 2)],
    4: [(3, 1), (4, 2), (5, 6)],
    5: [(1, 2), (6, 3), (4, 5)],
}
dias = {1: "2026-09-14", 2: "2026-09-21", 3: "2026-09-28", 4: "2026-10-05", 5: "2026-11-16"}
slots = [(1, "Cancha 1", 1), (1, "Cancha 2", 2), (2, "Central", 3)]   # (complejo, cancha, turno)

partidos = []   # dicts
pid = 0
for f in range(1, 6):
    for i, (loc, vis) in enumerate(fixture[f]):
        pid += 1
        comp, cancha, turno = slots[(i + f) % 3]
        if f == 4 and i == 2:
            comp, cancha, turno = 3, "Cancha A", 4
        partidos.append(dict(id=pid, fecha=f, loc=loc, vis=vis, dia=dias[f], turno=turno,
                             comp=comp, cancha=cancha))

# ---------------------------------------------------------------- simulación
sanciones = []   # (ci, desde, cant)
amarillas_acum = {}


def suspendido(ci, fecha):
    return any(c_i == ci and d <= fecha <= d + c - 1 for c_i, d, c in sanciones)


# guion para que el ejemplo sea interesante: roja en fecha 2 y alguien llega a 3 amarillas
guion_rojas = {(2, planteles[2][2])}
guion_amarillas = {(1, planteles[4][1]), (2, planteles[4][1]), (3, planteles[4][1]),
                   (1, planteles[1][3]), (3, planteles[1][3])}
disciplinaria = (planteles[6][4], 4, 2, "Agresión verbal al árbitro en la fecha 3")

w("\n-- ===================== FIXTURE Y PARTIDOS =====================\n")
for f in range(1, 6):
    w(f"\n-- ---------- Fecha {f} ----------\n")
    if f == 4:
        w("-- sanción disciplinaria resuelta por la organización antes de la fecha 4\n")
        w(ins("sancion_jugador", ["ci_jugador", "id_torneo", "motivo", "numero_fecha_inicio", "cantidad_fechas", "observacion"],
              [(disciplinaria[0], 1, "disciplinaria", disciplinaria[1], disciplinaria[2], disciplinaria[3])]))
        sanciones.append((disciplinaria[0], disciplinaria[1], disciplinaria[2]))
    for p in [p for p in partidos if p["fecha"] == f]:
        w(ins("partido", ["id_partido", "id_torneo", "numero_fecha", "id_equipo_local", "id_equipo_visitante",
                          "dia", "id_turno", "nombre_cancha", "id_complejo", "estado"],
              [(p["id"], 1, f, p["loc"], p["vis"], p["dia"], p["turno"], p["cancha"], p["comp"], "programado")]))
        if f == 5:
            if p["loc"] == 4:
                w(f"UPDATE partido SET estado = 'cancelado' WHERE id_partido = {p['id']};  -- cancelado por la organización\n")
            continue
        if f == 4 and p["loc"] == 5:
            w(f"UPDATE partido SET estado = 'postergado' WHERE id_partido = {p['id']};  -- lluvia, cancha sin techo\n")
            continue

        # planilla: hasta 6 habilitados por equipo, el 8º del plantel nunca juega
        plan = []
        for eq in (p["loc"], p["vis"]):
            habil = [ci for ci in planteles[eq][:7] if not suspendido(ci, f)]
            plan += [(eq, ci) for ci in habil[:6]]
        w(ins("planilla_partido", ["id_partido", "ci_jugador", "id_equipo"], [(p["id"], ci, eq) for eq, ci in plan]))

        goles = []
        for eq in (p["loc"], p["vis"]):
            cis = [ci for e, ci in plan if e == eq]
            for _ in range(R.choice([0, 1, 1, 2, 2, 3, 4])):
                goles.append((p["id"], R.choice(cis), R.randint(1, 50), False))
        if p["id"] == 5:   # un autogol de ejemplo
            goles.append((p["id"], [ci for e, ci in plan if e == p["vis"]][3], 33, True))
        goles.sort(key=lambda g: g[2])
        w(ins("gol", ["id_partido", "ci_jugador", "minuto", "autogol"], goles))

        tarjetas = []
        en_planilla = {ci for _, ci in plan}
        for (ff, ci) in guion_amarillas:
            if ff == f and ci in en_planilla:
                tarjetas.append((p["id"], ci, R.randint(5, 45), "amarilla"))
        for (ff, ci) in guion_rojas:
            if ff == f and ci in en_planilla:
                tarjetas.append((p["id"], ci, R.randint(30, 48), "roja"))
        # alguna amarilla extra al azar (sin pasarse de 2 acumuladas para no romper el guion)
        for _ in range(R.randint(0, 2)):
            ci = R.choice([c for _, c in plan])
            if amarillas_acum.get(ci, 0) == 0 and all(t[1] != ci for t in tarjetas):
                tarjetas.append((p["id"], ci, R.randint(5, 50), "amarilla"))
        tarjetas.sort(key=lambda t: t[2])
        w(ins("tarjeta", ["id_partido", "ci_jugador", "minuto", "color"], tarjetas))
        for _, ci, _, color in tarjetas:
            if color == "roja":
                sanciones.append((ci, f + 1, 1))
            else:
                amarillas_acum[ci] = amarillas_acum.get(ci, 0) + 1
                if amarillas_acum[ci] % 3 == 0:
                    sanciones.append((ci, f + 1, 1))

        w(f"UPDATE partido SET estado = 'jugado' WHERE id_partido = {p['id']};\n")

w("\nSET @carga_datos = NULL;\n")
OUT.write_text("".join(sql), encoding="utf-8")
print("escrito", OUT)
