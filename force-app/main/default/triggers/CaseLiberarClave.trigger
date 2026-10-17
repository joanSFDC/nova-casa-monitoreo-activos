/**
 * Al cerrar un caso vacia Clave_Abierta__c para que el mismo problema pueda
 * abrir otro. Solo consulta CaseStatus si algun caso cambio de estado: el
 * usuario de integracion, con licencia solo de API, no puede leer ese objeto,
 * y el procesamiento actualiza casos sin cambiarles el estado.
 */
trigger CaseLiberarClave on Case(before update) {
  List<Case> cambiaronDeEstado = new List<Case>();
  for (Case incidente : Trigger.new) {
    Case anterior = Trigger.oldMap.get(incidente.Id);
    if (anterior != null && incidente.Status != anterior.Status) {
      cambiaronDeEstado.add(incidente);
    }
  }
  if (cambiaronDeEstado.isEmpty()) {
    return;
  }
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
  for (Case incidente : cambiaronDeEstado) {
    Case anterior = Trigger.oldMap.get(incidente.Id);
    if (
      cerrados.contains(incidente.Status) && !cerrados.contains(anterior.Status)
    ) {
      incidente.Clave_Abierta__c = null;
    }
  }
}
