/**
 * Relleno de una vez de Resultado_Indice__c en las senales que ya existian antes
 * del campo. Solo las que buscan las vistas de investigacion: pendientes,
 * rechazadas, fallidas y en conflicto. Las aplicadas y atrasadas no las busca
 * ninguna vista y la limpieza las borra a los 7 dias.
 *
 * without sharing: proceso de sistema sobre toda la bitacora.
 */
public without sharing class SenalIndiceRellenoBatch implements Database.Batchable<SObject> {
  public static final Integer TAMANO_LOTE = 2000;

  public Database.QueryLocator start(Database.BatchableContext contexto) {
    Set<String> buscados = new Set<String>{
      IngestaConstantes.RESULTADO_PENDIENTE,
      IngestaConstantes.RESULTADO_RECHAZADO,
      IngestaConstantes.RESULTADO_FALLIDO,
      IngestaConstantes.RESULTADO_CONFLICTO
    };
    return Database.getQueryLocator(
      [
        SELECT Id, Resultado__c
        FROM Senal__c
        WHERE Resultado__c IN :buscados AND Resultado_Indice__c = NULL
      ]
    );
  }

  public void execute(Database.BatchableContext contexto, List<Senal__c> lote) {
    List<Senal__c> cambios = new List<Senal__c>();
    for (Senal__c senal : lote) {
      cambios.add(
        new Senal__c(Id = senal.Id, Resultado_Indice__c = senal.Resultado__c)
      );
    }
    Database.update(cambios, false, AccessLevel.SYSTEM_MODE);
  }

  public void finish(Database.BatchableContext contexto) {
    System.debug(LoggingLevel.INFO, 'Indice de resultado rellenado');
  }
}
