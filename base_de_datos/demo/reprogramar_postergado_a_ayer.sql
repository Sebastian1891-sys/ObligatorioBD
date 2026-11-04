-- =====================================================================
--  Para la defensa: deja un partido "recién jugado" para poder mostrar la
--  carga de planilla en vivo (la planilla solo se habilita entre el fin del
--  turno y las 48 h siguientes).
--
--  Toma el partido postergado de la fecha 4 (Humanistas Unidos vs
--  Inconsciente Colectivo) y lo reprograma para AYER de 21 a 22 h.
--  Lo mismo se puede hacer desde la app: Partidos → Editar → día = ayer,
--  estado = programado.
-- =====================================================================
USE torneo_ucu;
UPDATE partido
   SET dia = CURDATE() - INTERVAL 1 DAY, id_turno = 4, estado = 'programado'
 WHERE id_partido = 12 AND estado = 'postergado';
SELECT id_partido, numero_fecha, dia, id_turno, estado FROM partido WHERE id_partido = 12;
