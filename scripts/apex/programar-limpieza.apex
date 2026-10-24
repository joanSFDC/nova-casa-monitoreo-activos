// Programa la limpieza de la bitacora cada noche a las 2 a. m. (hora de quien la programa).
// Para quitarla: BitacoraRetencionSchedulable.abortar();
String id = BitacoraRetencionSchedulable.programar();
System.debug('LIMPIEZA programada ' + id);
