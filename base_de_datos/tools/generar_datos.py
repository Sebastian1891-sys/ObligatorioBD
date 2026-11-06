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

    d = f"{base7:07d}"
    pesos = [2, 9, 8, 7, 6, 3, 4]
    s = 0
    for i in range(7):
        s += int(d[i]) * pesos[i]
    return str((10 - s % 10) % 10)

def ins(table, cols, rows):
    if not rows:
        return ""
    filas_sql = []
    for fila in rows:
        valores = []
        for valor in fila:
            valores.append(q(valor))
        filas_sql.append("(" + ", ".join(valores) + ")")
    vals = ",\n  ".join(filas_sql)
    return f"INSERT INTO {table} ({', '.join(cols)}) VALUES\n  {vals};\n"

sql = []

sql.append("USE torneo_ucu;\n\n")

usuarios = [
    ("admin@ucu.edu.uy", "admin123", "administrador"),
    ("planillero@ucu.edu.uy", "planillero123", "planillero"),
    ("planillero2@ucu.edu.uy", "planillero123", "planillero"),
]
sql.append("\n")
sql.append("\n")
filas = []
for correo, contrasena, rol in usuarios:
    protegida = bcrypt.hashpw(contrasena.encode(), bcrypt.gensalt(rounds=10)).decode()
    filas.append((correo, protegida, rol))
sql.append(ins("login", ["correo", "contrasena", "rol"], filas))

facultades = ["Ingeniería y Tecnologías", "Ciencias Empresariales", "Derecho",
              "Ciencias de la Salud", "Ciencias Humanas", "Psicología", "Odontología"]
filas = []
for i, nombre in enumerate(facultades):
    filas.append((i + 1, nombre))
sql.append(ins("facultad", ["id_facultad", "nombre"], filas))

filas = []
for i in range(5):
    filas.append((i + 1, f"{18 + i}:00:00", f"{19 + i}:00:00"))
sql.append(ins("turno", ["id_turno", "hora_inicio", "hora_fin"], filas))

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
sql.append("\n" + ins("complejo", ["id_complejo", "nombre", "direccion", "departamento"], complejos))
sql.append(ins("cancha", ["nombre_cancha", "id_complejo", "superficie", "techada"], canchas))

nombres = ["Mateo", "Santiago", "Joaquín", "Bruno", "Facundo", "Nicolás", "Agustín", "Martín",
           "Federico", "Gonzalo", "Diego", "Lucas", "Tomás", "Rodrigo", "Ignacio", "Pablo",
           "Valentina", "Sofía", "Camila", "Lucía", "Florencia", "Micaela", "Juan", "Sebastián",
           "Emiliano", "Maximiliano", "Germán", "Andrés", "Marcos", "Felipe"]
apellidos = ["Rodríguez", "González", "Fernández", "Pérez", "Silva", "Martínez", "Sosa", "López",
             "Díaz", "Suárez", "Pereira", "Cabrera", "Núñez", "Olivera", "Méndez", "Acosta",
             "Ferreira", "Castro", "Romero", "Álvarez", "Benítez", "Viera", "Techera", "Correa"]

jugadores = []
por_facultad = {}
ci_base = 3_512_300
used_emails = set()
for fid in range(1, len(facultades) + 1):
    n_jug = 10 if fid <= 6 else 4

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
        if tipo in ("docente", "funcionario"):
            anio = R.randint(1972, 1990)
        elif tipo == "posgrado":
            anio = R.randint(1994, 2001)
        else:
            anio = R.randint(2002, 2007)
        nac = f"{anio}-{R.randint(1, 12):02d}-{R.randint(1, 28):02d}"
        jugadores.append((ci, nom, ape, email, nac, fid, tipo))
        lst.append(ci)
    por_facultad[fid] = lst
sql.append("\n" + ins("jugador", ["ci", "nombre", "apellido", "email", "fecha_nacimiento", "id_facultad", "tipo"], jugadores))

sql.append("\n\n")
sql.append(ins("torneo", ["id_torneo", "nombre", "anio", "semestre", "fecha_inicio", "fecha_fin", "estado"], [
    (1, "Torneo Interfacultades 2026 – 2º semestre", 2026, 2, "2026-09-07", "2026-11-30", "inscripcion"),
    (2, "Torneo Interfacultades 2027 – 1er semestre", 2027, 1, "2027-03-15", "2027-07-09", "inscripcion"),
]))

nombres_equipo = {1: "Los Compiladores", 2: "Balance Cero", 3: "Fallo Unánime",
                  4: "Bisturí FC", 5: "Humanistas Unidos", 6: "Inconsciente Colectivo"}
equipos = []
for fid in range(1, 7):
    equipos.append((fid, nombres_equipo[fid], 1, fid))
sql.append("\n" + ins("equipo", ["id_equipo", "nombre", "id_torneo", "id_facultad"], equipos))

planteles = {}
filas = []
for fid in range(1, 7):
    cis = por_facultad[fid][:8]
    planteles[fid] = cis
    camisetas = R.sample(range(1, 24), len(cis))
    for ci, nro in zip(cis, camisetas):
        filas.append((fid, ci, 1, nro))
sql.append(ins("equipo_jugador_torneo", ["id_equipo", "ci_jugador", "id_torneo", "numero_camiseta"], filas))

sql.append("\n\n")
for fid in range(1, 7):
    sql.append(f"UPDATE equipo SET ci_capitan = {q(planteles[fid][0])} WHERE id_equipo = {fid};\n")

sql.append("\n" + ins("equipo", ["id_equipo", "nombre", "id_torneo", "id_facultad"],
             [(7, "Los Compiladores 2.0", 2, 1), (8, "Sonrisa Perfecta", 2, 7)]))
filas = []
for i, ci in enumerate(por_facultad[1][:6]):
    filas.append((7, ci, 2, i + 1))
for i, ci in enumerate(por_facultad[7][:3]):
    filas.append((8, ci, 2, i + 10))
sql.append(ins("equipo_jugador_torneo", ["id_equipo", "ci_jugador", "id_torneo", "numero_camiseta"], filas))
sql.append(f"UPDATE equipo SET ci_capitan = {q(por_facultad[1][1])} WHERE id_equipo = 7;\n")

sql.append("\nUPDATE torneo SET estado = 'en curso' WHERE id_torneo = 1;\n")

fixture = {
    1: [(1, 6), (2, 5), (3, 4)],
    2: [(5, 1), (6, 4), (2, 3)],
    3: [(1, 4), (3, 5), (6, 2)],
    4: [(3, 1), (4, 2), (5, 6)],
    5: [(1, 2), (6, 3), (4, 5)],
}
dias = {1: "2026-09-14", 2: "2026-09-21", 3: "2026-09-28", 4: "2026-10-05", 5: "2026-11-16"}
slots = [(1, "Cancha 1", 1), (1, "Cancha 2", 2), (2, "Central", 3)]

partidos = []
pid = 0
for f in range(1, 6):
    for i, (loc, vis) in enumerate(fixture[f]):
        pid += 1
        comp, cancha, turno = slots[(i + f) % 3]
        if f == 4 and i == 2:
            comp, cancha, turno = 3, "Cancha A", 4
        partidos.append(dict(id=pid, fecha=f, loc=loc, vis=vis, dia=dias[f], turno=turno,
                             comp=comp, cancha=cancha))

sanciones = []
id_tarjeta = 0
amarillas_acum = {}

def minuto_evento(evento):
    return evento[2]

def suspendido(ci, fecha):
    for jugador, inicio, cantidad in sanciones:
        if jugador == ci and inicio <= fecha <= inicio + cantidad - 1:
            return True
    return False

guion_rojas = {(2, planteles[2][2])}
guion_amarillas = {(1, planteles[4][1]), (2, planteles[4][1]), (3, planteles[4][1]),
                   (1, planteles[1][3]), (3, planteles[1][3])}
disciplinaria = (planteles[6][4], 4, 2, "Agresión verbal al árbitro en la fecha 3")

sql.append("\n\n")
for f in range(1, 6):
    sql.append(f"\n\n")
    if f == 4:
        sql.append("\n")
        sql.append(ins("sancion_jugador", ["ci_jugador", "id_torneo", "motivo", "numero_fecha_inicio", "cantidad_fechas", "observacion"],
              [(disciplinaria[0], 1, "disciplinaria", disciplinaria[1], disciplinaria[2], disciplinaria[3])]))
        sanciones.append((disciplinaria[0], disciplinaria[1], disciplinaria[2]))
    for p in partidos:
        if p["fecha"] != f:
            continue
        sql.append(ins("partido", ["id_partido", "id_torneo", "numero_fecha", "id_equipo_local", "id_equipo_visitante",
                          "dia", "id_turno", "nombre_cancha", "id_complejo", "estado"],
              [(p["id"], 1, f, p["loc"], p["vis"], p["dia"], p["turno"], p["cancha"], p["comp"], "programado")]))
        if f == 5:
            if p["loc"] == 4:
                sql.append(f"UPDATE partido SET estado = 'cancelado' WHERE id_partido = {p['id']};  \n")
            continue
        if f == 4 and p["loc"] == 5:
            sql.append(f"UPDATE partido SET estado = 'postergado' WHERE id_partido = {p['id']};  \n")
            continue

        plan = []
        for eq in (p["loc"], p["vis"]):
            habil = []
            for ci in planteles[eq][:7]:
                if not suspendido(ci, f):
                    habil.append(ci)
            for ci in habil[:6]:
                plan.append((eq, ci))
        filas = []
        for eq, ci in plan:
            filas.append((p["id"], ci, eq))
        sql.append(ins("planilla_partido", ["id_partido", "ci_jugador", "id_equipo"], filas))

        goles = []
        for eq in (p["loc"], p["vis"]):
            cis = []
            for equipo, ci in plan:
                if equipo == eq:
                    cis.append(ci)
            for _ in range(R.choice([0, 1, 1, 2, 2, 3, 4])):
                goles.append((p["id"], R.choice(cis), R.randint(1, 50), False))
        if p["id"] == 5:
            visitantes = []
            for equipo, ci in plan:
                if equipo == p["vis"]:
                    visitantes.append(ci)
            goles.append((p["id"], visitantes[3], 33, True))
        goles.sort(key=minuto_evento)
        sql.append(ins("gol", ["id_partido", "ci_jugador", "minuto", "autogol"], goles))

        tarjetas = []
        en_planilla = []
        for equipo, ci in plan:
            en_planilla.append(ci)
        for (ff, ci) in guion_amarillas:
            if ff == f and ci in en_planilla:
                tarjetas.append((p["id"], ci, R.randint(5, 45), "amarilla"))
        for (ff, ci) in guion_rojas:
            if ff == f and ci in en_planilla:
                tarjetas.append((p["id"], ci, R.randint(30, 48), "roja"))

        for _ in range(R.randint(0, 2)):
            ci = R.choice(en_planilla)
            tiene_tarjeta = False
            for tarjeta in tarjetas:
                if tarjeta[1] == ci:
                    tiene_tarjeta = True
            if amarillas_acum.get(ci, 0) == 0 and not tiene_tarjeta:
                tarjetas.append((p["id"], ci, R.randint(5, 50), "amarilla"))
        tarjetas.sort(key=minuto_evento)
        filas_t = []
        nuevas_sanciones = []
        for _, ci, minuto, color in tarjetas:
            id_tarjeta += 1
            filas_t.append((id_tarjeta, p["id"], ci, minuto, color))

            if color == "roja":
                nuevas_sanciones.append((ci, 1, "roja", f + 1, 1, id_tarjeta))
                sanciones.append((ci, f + 1, 1))
            else:
                amarillas_acum[ci] = amarillas_acum.get(ci, 0) + 1
                if amarillas_acum[ci] % 3 == 0:
                    nuevas_sanciones.append((ci, 1, "acumulacion de amarillas", f + 1, 1, id_tarjeta))
                    sanciones.append((ci, f + 1, 1))
        sql.append(ins("tarjeta", ["id_tarjeta", "id_partido", "ci_jugador", "minuto", "color"], filas_t))
        if nuevas_sanciones:
            sql.append("\n")
            sql.append(ins("sancion_jugador", ["ci_jugador", "id_torneo", "motivo", "numero_fecha_inicio", "cantidad_fechas", "id_tarjeta"],
                  nuevas_sanciones))

        sql.append(f"UPDATE partido SET estado = 'jugado', jugado_en = NOW() WHERE id_partido = {p['id']};\n")

OUT.write_text("".join(sql), encoding="utf-8")
print("escrito", OUT)
