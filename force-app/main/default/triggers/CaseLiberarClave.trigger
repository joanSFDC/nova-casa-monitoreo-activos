trigger CaseLiberarClave on Case(before update) {
  Set<String> cerrados = new Set<String>();
  for (CaseStatus estado : [
    SELECT MasterLabel, ApiName
    FROM CaseStatus
    WHERE IsClosed = TRUE
  ]) {
    if (String.isNotBlank(estado.MasterLabel)) {
      cerrados.add(estado.MasterLabel);
    }
    if (String.isNotBlank(estado.ApiName)) {
      cerrados.add(estado.ApiName);
    }
  }
  for (Case incidente : Trigger.new) {
    Case anterior = Trigger.oldMap.get(incidente.Id);
    if (
      cerrados.contains(incidente.Status) &&
      anterior != null &&
      !cerrados.contains(anterior.Status)
    ) {
      incidente.Clave_Abierta__c = null;
    }
  }
}
