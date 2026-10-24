/**
 * Borra todo lo que creo la prueba de carga: sus senales por el prefijo de la
 * clave, y al final los incidentes, los estados, los equipos y el edificio.
 * Vacia la papelera en cada lote para devolver el almacenamiento.
 */
public with sharing class CargaSinteticaLimpiezaBatch implements Database.Batchable<SObject>, Database.Stateful {
  public Integer borradas = 0;

  public static Id lanzar() {
    return Database.executeBatch(new CargaSinteticaLimpiezaBatch(), 2000);
  }

  public Database.QueryLocator start(Database.BatchableContext contexto) {
    String prefijo = CargaSinteticaBatch.prefijoClave() + '%';
    return Database.getQueryLocator(
      [SELECT Id FROM Senal__c WHERE Clave__c LIKE :prefijo]
    );
  }

  public void execute(
    Database.BatchableContext contexto,
    List<Senal__c> senales
  ) {
    delete senales;
    Database.emptyRecycleBin(senales);
    borradas += senales.size();
  }

  /**
   * Lo que queda ligado al edificio: senales que no siguen el prefijo, como un
   * rastro, los incidentes y el catalogo. Activo y estado son detalle del
   * edificio, asi que caen con el.
   */
  public void finish(Database.BatchableContext contexto) {
    List<Senal__c> sueltas = [
      SELECT Id
      FROM Senal__c
      WHERE
        Activo__r.Edificio__r.Codigo_Externo__c = :CargaSinteticaBatch.EDIFICIO
      LIMIT 9000
    ];
    List<Case> incidentes = [
      SELECT Id
      FROM Case
      WHERE
        Activo__r.Edificio__r.Codigo_Externo__c = :CargaSinteticaBatch.EDIFICIO
      LIMIT 500
    ];
    List<Edificio__c> edificio = [
      SELECT Id
      FROM Edificio__c
      WHERE Codigo_Externo__c = :CargaSinteticaBatch.EDIFICIO
    ];
    List<SObject> todo = new List<SObject>();
    todo.addAll(sueltas);
    todo.addAll(incidentes);
    todo.addAll(edificio);
    if (!todo.isEmpty()) {
      delete sueltas;
      delete incidentes;
      delete edificio;
      Database.emptyRecycleBin(todo);
    }
    borradas += sueltas.size();
  }
}
