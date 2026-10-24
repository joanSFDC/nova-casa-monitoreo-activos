/**
 * Lanza la limpieza de la bitacora cada noche a las 2 a. m., en la zona horaria
 * de quien la programa (Bogota).
 */
public with sharing class BitacoraRetencionSchedulable implements Schedulable {
  public static final String NOMBRE_JOB = 'Nova Casa Limpieza de bitacora';
  public static final String CRON_NOCHE = '0 0 2 * * ?';

  public void execute(SchedulableContext sc) {
    Database.executeBatch(
      new BitacoraRetencionBatch(),
      BitacoraRetencionBatch.TAMANO_LOTE
    );
  }

  public static String programar() {
    abortar();
    return System.schedule(
      NOMBRE_JOB,
      CRON_NOCHE,
      new BitacoraRetencionSchedulable()
    );
  }

  public static void abortar() {
    for (CronTrigger trabajo : [
      SELECT Id
      FROM CronTrigger
      WHERE CronJobDetail.Name = :NOMBRE_JOB
      WITH SYSTEM_MODE
    ]) {
      System.abortJob(trabajo.Id);
    }
  }
}
