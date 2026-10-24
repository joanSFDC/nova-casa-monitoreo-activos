/**
 * El vigia de la ingesta: cada 10 minutos revisa si la ingesta sigue trayendo
 * datos. Son trabajos propios, aparte de los 60 de la ingesta, para que un corte
 * de esa cadena no se lleve tambien la alarma. No cubre que se caiga toda la
 * plataforma asincrona de Salesforce, que avisa por su cuenta.
 */
public with sharing class VigiaIngestaSchedulable implements Schedulable {
  public static final String NOMBRE_JOB = 'Nova Casa Vigia de ingesta';
  // Desfasado de la ingesta, que arranca en el minuto cero de cada trabajo.
  private static final List<Integer> MINUTOS = new List<Integer>{
    5,
    15,
    25,
    35,
    45,
    55
  };

  public void execute(SchedulableContext sc) {
    AvisoIngestaServicio.revisar(Datetime.now());
  }

  public static List<String> programar() {
    abortar();
    List<String> ids = new List<String>();
    for (Integer minuto : MINUTOS) {
      ids.add(
        System.schedule(
          NOMBRE_JOB + ' :' + String.valueOf(minuto).leftPad(2, '0'),
          '0 ' + minuto + ' * * * ?',
          new VigiaIngestaSchedulable()
        )
      );
    }
    return ids;
  }

  public static void abortar() {
    String prefijo = NOMBRE_JOB + '%';
    for (CronTrigger trabajo : [
      SELECT Id
      FROM CronTrigger
      WHERE CronJobDetail.Name LIKE :prefijo
      WITH SYSTEM_MODE
    ]) {
      System.abortJob(trabajo.Id);
    }
  }
}
