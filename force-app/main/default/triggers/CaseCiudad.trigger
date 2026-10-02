/**
 * Case es privado y se comparte por Ciudad__c. La ciudad sale siempre del
 * edificio del activo, nunca de lo que traiga el registro: si no, cualquiera
 * que cree un caso elegiria que grupo lo ve. Las reglas de comparticion no
 * aceptan formulas, por eso es un campo escrito aqui.
 */
trigger CaseCiudad on Case(before insert, before update) {
  Set<Id> activoIds = new Set<Id>();
  for (Case incidente : Trigger.new) {
    if (incidente.Activo__c != null) {
      activoIds.add(incidente.Activo__c);
    }
  }
  Map<Id, Activo__c> activos = new Map<Id, Activo__c>();
  if (!activoIds.isEmpty()) {
    activos = new Map<Id, Activo__c>(
      [
        SELECT Id, Edificio__r.Ciudad__c
        FROM Activo__c
        WHERE Id IN :activoIds
        WITH SYSTEM_MODE
      ]
    );
  }
  for (Case incidente : Trigger.new) {
    Activo__c activo = activos.get(incidente.Activo__c);
    incidente.Ciudad__c = activo == null ? null : activo.Edificio__r.Ciudad__c;
  }
}
