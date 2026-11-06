USE torneo_ucu;
UPDATE partido
   SET dia = CURDATE() - INTERVAL 1 DAY, id_turno = 4, estado = 'programado'
 WHERE id_partido = 12 AND estado = 'postergado';
SELECT id_partido, numero_fecha, dia, id_turno, estado FROM partido WHERE id_partido = 12;
