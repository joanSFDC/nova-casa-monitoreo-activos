// Corre la limpieza de la bitacora una vez, ahora. Su avance se ve en Configuracion,
// Trabajos de Apex (Apex Jobs), o con scripts/ver-limpieza.sh.
Id trabajo = Database.executeBatch(new BitacoraRetencionBatch(), BitacoraRetencionBatch.TAMANO_LOTE);
System.debug('LIMPIEZA lanzada ' + trabajo);
