from fastapi import HTTPException

def error(mensaje: str):
    raise HTTPException(400, mensaje)

def estado_torneo(db, id_torneo: int) -> str:
    t = db.one_or_404("select estado from torneo where id_torneo = %s", (id_torneo,), "Torneo")
    return t["estado"]

def exigir_inscripcion(db, id_torneo: int, mensaje: str):
    if estado_torneo(db, id_torneo) != "inscripcion":
        error(mensaje)

def validar_cambio_estado_torneo(db, id_torneo: int, nuevo: str):

    actual = estado_torneo(db, id_torneo)
    if actual == nuevo:
        return
    permitidos = {"inscripcion": "en curso", "en curso": "finalizado"}
    if permitidos.get(actual) != nuevo:
        error("Transición de estado inválida: inscripción, en curso,  finalizado")

    if nuevo == "en curso":
        equipos = db.all("""select e.id_equipo, e.ci_capitan,
                                   (SELECT COUNT(*) FROM equipo_jugador_torneo j
                                     WHERE j.id_equipo = e.id_equipo) AS jugadores
                              FROM equipo e WHERE e.id_torneo = %s""", (id_torneo,))
        if len(equipos) < 2:
            error("Se necesitan al menos 2 equipos para iniciar el torneo")
        for e in equipos:
            if e["ci_capitan"] is None or e["jugadores"] < 5:
                error("Todos los equipos necesitan capitán y al menos 5 jugadores para iniciar el torneo")

def validar_alta_plantel(db, id_equipo: int, ci: str):
    equipo = db.one_or_404("SELECT id_torneo, id_facultad FROM equipo WHERE id_equipo = %s",
                           (id_equipo,), "Equipo")
    jugador = db.one_or_404("SELECT id_facultad, tipo FROM jugador WHERE ci = %s", (ci,), "Jugador")

    exigir_inscripcion(db, equipo["id_torneo"], "Los planteles solo pueden modificarse durante la inscripción")

    if jugador["id_facultad"] != equipo["id_facultad"]:
        error("El jugador debe pertenecer a la facultad que representa el equipo")

    plantel = db.all("""SELECT j.tipo FROM equipo_jugador_torneo ejt
                          JOIN jugador j ON j.ci = ejt.ci_jugador
                         WHERE ejt.id_equipo = %s""", (id_equipo,))
    if len(plantel) >= 10:
        error("El plantel ya tiene 10 jugadores (máximo permitido)")

    if jugador["tipo"] in ("docente", "funcionario"):
        docentes = 0
        for p in plantel:
            if p["tipo"] in ("docente", "funcionario"):
                docentes += 1
        if docentes >= 2:
            error("El plantel ya tiene 2 docentes/funcionarios (máximo permitido)")

def validar_cambio_plantel(db, id_equipo: int):
    equipo = db.one_or_404("SELECT id_torneo FROM equipo WHERE id_equipo = %s", (id_equipo,), "Equipo")
    exigir_inscripcion(db, equipo["id_torneo"], "Los planteles solo pueden modificarse durante la inscripción")

def validar_baja_plantel(db, id_equipo: int, ci: str):
    validar_cambio_plantel(db, id_equipo)
    if db.one("SELECT 1 FROM equipo WHERE id_equipo = %s AND ci_capitan = %s", (id_equipo, ci)):
        error("El jugador es el capitán: asigná otro capitán antes de quitarlo del plantel")

def validar_edicion_equipo(db, id_equipo: int, id_facultad: int, ci_capitan: str | None):
    actual = db.one_or_404("SELECT id_facultad FROM equipo WHERE id_equipo = %s", (id_equipo,), "Equipo")
    tiene_plantel = db.one("SELECT 1 FROM equipo_jugador_torneo WHERE id_equipo = %s LIMIT 1", (id_equipo,))
    if id_facultad != actual["id_facultad"] and tiene_plantel:
        error("No se puede cambiar la facultad de un equipo con plantel cargado")
    if ci_capitan and not db.one("SELECT 1 FROM equipo_jugador_torneo WHERE id_equipo = %s AND ci_jugador = %s",
                                 (id_equipo, ci_capitan)):
        error("El capitán debe ser un jugador del plantel del equipo")

def validar_partido(db, d, id_partido: int = 0):

    torneo = db.one_or_404("SELECT estado, fecha_inicio, fecha_fin FROM torneo WHERE id_torneo = %s",
                           (d.id_torneo,), "Torneo")
    if torneo["estado"] == "finalizado":
        error("El torneo está finalizado: no se pueden programar ni modificar partidos")
    if d.id_equipo_local == d.id_equipo_visitante:
        error("Un equipo no puede enfrentarse a sí mismo")
    if not (torneo["fecha_inicio"] <= d.dia.isoformat() <= torneo["fecha_fin"]):
        error("El día del partido está fuera del período del torneo")

    equipos = db.all("SELECT id_equipo FROM equipo WHERE id_torneo = %s AND id_equipo IN (%s, %s)",
                     (d.id_torneo, d.id_equipo_local, d.id_equipo_visitante))
    if len(equipos) != 2:
        error("Los dos equipos deben estar inscriptos en esta edición")

    if d.estado == "programado":
        for id_equipo in (d.id_equipo_local, d.id_equipo_visitante):
            n = db.one("SELECT COUNT(*) AS n FROM equipo_jugador_torneo WHERE id_equipo = %s", (id_equipo,))["n"]
            if n < 5:
                error("Ambos equipos deben tener al menos 5 jugadores en su plantel")

        ocupada = db.one("""SELECT 1 FROM partido
                             WHERE id_complejo = %s AND nombre_cancha = %s AND dia = %s AND id_turno = %s
                               AND estado IN ('programado', 'jugado') AND id_partido <> %s""",
                         (d.id_complejo, d.nombre_cancha, d.dia, d.id_turno, id_partido))
        if ocupada:
            error("La cancha ya tiene un partido asignado en ese día y turno")

    if d.estado != "cancelado":

        repetido = db.one("""SELECT 1 FROM partido
                              WHERE id_torneo = %s AND estado <> 'cancelado' AND id_partido <> %s
                                AND ((id_equipo_local = %s AND id_equipo_visitante = %s)
                                  OR (id_equipo_local = %s AND id_equipo_visitante = %s))""",
                          (d.id_torneo, id_partido, d.id_equipo_local, d.id_equipo_visitante,
                           d.id_equipo_visitante, d.id_equipo_local))
        if repetido:
            error("Esos equipos ya tienen un partido en esta edición (solo se puede repetir si el anterior fue cancelado)")

        misma_fecha = db.one("""SELECT 1 FROM partido
                                 WHERE id_torneo = %s AND numero_fecha = %s
                                   AND estado <> 'cancelado' AND id_partido <> %s
                                   AND (id_equipo_local IN (%s, %s) OR id_equipo_visitante IN (%s, %s))""",
                             (d.id_torneo, d.numero_fecha, id_partido,
                              d.id_equipo_local, d.id_equipo_visitante, d.id_equipo_local, d.id_equipo_visitante))
        if misma_fecha:
            error(f"Uno de los equipos ya tiene un partido en la fecha {d.numero_fecha}")

def validar_edicion_partido(db, id_partido: int, nuevo_estado: str):
    p = db.one_or_404("SELECT estado FROM partido WHERE id_partido = %s", (id_partido,), "Partido")
    if p["estado"] == "jugado":
        error("Un partido jugado no puede modificarse (solo su planilla, dentro de las 48 h)")
    if p["estado"] == "cancelado":
        error("Un partido cancelado no puede modificarse: programá uno nuevo")
    if nuevo_estado in ("postergado", "cancelado") and tiene_planilla(db, id_partido):
        error("El partido ya tiene planilla cargada: no puede postergarse ni cancelarse")

def validar_marcar_jugado(db, id_partido: int):
    p = db.one_or_404("SELECT estado, fin, NOW() >= fin AS ya_paso FROM v_partido WHERE id_partido = %s",
                      (id_partido,), "Partido")
    if p["estado"] != "programado":
        error("Solo un partido programado puede marcarse como jugado")
    if not p["ya_paso"]:
        error("Un partido solo puede marcarse como jugado cuando su día y turno ya pasaron")
    if not tiene_planilla(db, id_partido):
        error("Cargá la planilla antes de marcar el partido como jugado")

def tiene_planilla(db, id_partido: int) -> bool:
    return db.one("SELECT 1 FROM planilla_partido WHERE id_partido = %s LIMIT 1", (id_partido,)) is not None

def validar_ventana_planilla(db, id_partido: int) -> dict:

    p = db.one_or_404("""SELECT v.id_torneo, v.numero_fecha, v.estado, v.id_equipo_local, v.id_equipo_visitante,
                                t.estado AS estado_torneo,
                                NOW() < v.fin                      AS no_termino,
                                NOW() > v.fin + INTERVAL 48 HOUR   AS vencida
                           FROM v_partido v JOIN torneo t ON t.id_torneo = v.id_torneo
                          WHERE v.id_partido = %s""", (id_partido,), "Partido")
    if p["estado"] in ("postergado", "cancelado"):
        error("No se puede cargar la planilla de un partido postergado o cancelado")
    if p["estado_torneo"] != "en curso":
        error("Solo se cargan planillas de torneos en curso")
    if p["no_termino"]:
        error("El partido todavía no terminó: la planilla se carga una vez finalizado el turno")
    if p["vencida"]:
        error("Pasaron más de 48 horas desde el partido: el resultado ya no puede corregirse")
    return p

def jugador_suspendido(db, ci: str, id_torneo: int, numero_fecha: int) -> bool:

    s = db.one("""SELECT 1 FROM sancion_jugador
                   WHERE ci_jugador = %s AND id_torneo = %s
                     AND %s BETWEEN numero_fecha_inicio AND numero_fecha_inicio + cantidad_fechas - 1""",
               (ci, id_torneo, numero_fecha))
    return s is not None

def validar_alta_planilla(db, id_partido: int, ci: str, id_equipo: int):
    p = validar_ventana_planilla(db, id_partido)
    if id_equipo not in (p["id_equipo_local"], p["id_equipo_visitante"]):
        error("El jugador debe pertenecer a uno de los dos equipos del partido")

    if jugador_suspendido(db, ci, p["id_torneo"], p["numero_fecha"]):
        error("El jugador está suspendido para esta fecha y no puede figurar en la planilla")

def validar_baja_planilla(db, id_partido: int, ci: str):
    validar_ventana_planilla(db, id_partido)
    if db.one("SELECT 1 FROM gol WHERE id_partido = %s AND ci_jugador = %s LIMIT 1", (id_partido, ci)) or \
       db.one("SELECT 1 FROM tarjeta WHERE id_partido = %s AND ci_jugador = %s LIMIT 1", (id_partido, ci)):
        error("El jugador tiene goles o tarjetas en el partido: borralos antes de quitarlo de la planilla")

def exigir_en_planilla(db, id_partido: int, ci: str):
    if not db.one("SELECT 1 FROM planilla_partido WHERE id_partido = %s AND ci_jugador = %s", (id_partido, ci)):
        error("Solo pueden convertir goles o recibir tarjetas los jugadores que figuran en la planilla")

def validar_tarjeta(db, id_partido: int, ci: str, color: str, id_tarjeta: int = 0):

    validar_ventana_planilla(db, id_partido)
    exigir_en_planilla(db, id_partido, ci)
    otras = db.all("""SELECT color FROM tarjeta
                       WHERE id_partido = %s AND ci_jugador = %s AND id_tarjeta <> %s""",
                   (id_partido, ci, id_tarjeta))
    rojas = 0
    amarillas = 0
    for t in otras:
        if t["color"] == "roja":
            rojas += 1
        else:
            amarillas += 1
    if rojas > 0:
        error("El jugador ya fue expulsado en este partido")
    if color == "amarilla" and amarillas >= 2:
        error("Un jugador no puede recibir más de 2 amarillas en un partido")

def recalcular_sanciones(db, ci: str, id_torneo: int):
    db.execute("""DELETE FROM sancion_jugador
                   WHERE ci_jugador = %s AND id_torneo = %s AND motivo <> 'disciplinaria'""",
               (ci, id_torneo))

    tarjetas = db.all("""SELECT t.id_tarjeta, t.color, p.numero_fecha
                           FROM tarjeta t JOIN partido p ON p.id_partido = t.id_partido
                          WHERE t.ci_jugador = %s AND p.id_torneo = %s
                          ORDER BY p.numero_fecha, p.dia, t.minuto, t.id_tarjeta""",
                      (ci, id_torneo))

    insertar = """INSERT INTO sancion_jugador
                    (ci_jugador, id_torneo, motivo, numero_fecha_inicio, cantidad_fechas, id_tarjeta)
                  VALUES (%s, %s, %s, %s, 1, %s)"""
    amarillas = 0
    for t in tarjetas:
        if t["color"] == "roja":
            db.execute(insertar, (ci, id_torneo, "roja", t["numero_fecha"] + 1, t["id_tarjeta"]))
        else:
            amarillas += 1
            if amarillas % 3 == 0:
                db.execute(insertar, (ci, id_torneo, "acumulacion de amarillas",
                                      t["numero_fecha"] + 1, t["id_tarjeta"]))
