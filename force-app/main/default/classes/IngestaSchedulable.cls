/**
 * Arranca la cadena de ingesta cada minuto. No hace callouts: solo encola el primer eslabon.
 */
public with sharing class IngestaSchedulable implements Schedulable {
    public static final String NOMBRE_JOB = 'Nova Casa Ingesta';
    public static final String CRON_HORA = '0 0 * * * ?';

    public void execute(SchedulableContext sc) {
        System.enqueueJob(new IngestaQueueable(0));
    }

    /**
     * Sesenta trabajos, uno por minuto. Apex programado no admite un solo cron cada minuto.
     */
    public static List<String> programarCadaMinuto() {
        abortar();
        List<String> ids = new List<String>();
        for (Integer minuto = 0; minuto < 60; minuto++) {
            String etiqueta = String.valueOf(minuto);
            if (etiqueta.length() == 1) {
                etiqueta = '0' + etiqueta;
            }
            ids.add(
                System.schedule(
                    NOMBRE_JOB + ' ' + etiqueta,
                    '0 ' + minuto + ' * * * ?',
                    new IngestaSchedulable()
                )
            );
        }
        return ids;
    }

    public static String programarCadaHora() {
        abortar();
        return System.schedule(NOMBRE_JOB + ' 00', CRON_HORA, new IngestaSchedulable());
    }

    public static void abortar() {
        String prefijo = NOMBRE_JOB + '%';
        for (CronTrigger trabajo : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :prefijo
        ]) {
            System.abortJob(trabajo.Id);
        }
    }
}
