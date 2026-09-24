/**
 * Un eslabon de la cadena de ingesta. Pide una pagina, la procesa y decide si continuar.
 *
 * without sharing: proceso de sistema. El Schedulable solo encola; este eslabon hace el trabajo.
 */
public without sharing class IngestaQueueable implements Queueable, Database.AllowsCallouts {
    private Integer indicePagina;

    public IngestaQueueable() {
        this(0);
    }

    public IngestaQueueable(Integer indicePagina) {
        this.indicePagina = indicePagina == null ? 0 : indicePagina;
    }

    public void execute(QueueableContext context) {
        try {
            IngestaServicio.ResultadoCiclo resultado = IngestaServicio.ejecutar(this.indicePagina);
            if (resultado != null && resultado.encadenar == true && !Test.isRunningTest()) {
                System.enqueueJob(new IngestaQueueable(resultado.indiceSiguiente));
            }
        } catch (Exception e) {
            registrarFallo(e);
        }
    }

    private void registrarFallo(Exception e) {
        List<Control_de_Ingesta__c> filas = [
            SELECT Id, Fallos_Consecutivos__c, Ultimo_Error__c
            FROM Control_de_Ingesta__c
            WHERE Activo__c = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (filas.isEmpty()) {
            return;
        }
        Control_de_Ingesta__c control = filas[0];
        control.Fallos_Consecutivos__c =
            (control.Fallos_Consecutivos__c == null ? 0 : control.Fallos_Consecutivos__c) + 1;
        control.Ultimo_Error__c = e.getMessage() == null ? 'Error de ingesta' : e.getMessage().left(255);
        Database.update(control, AccessLevel.SYSTEM_MODE);
    }
}
