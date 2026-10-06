/**
 * El escenario y la semilla solo viajan al abrir sesion. Si alguien los
 * cambia, el cursor de la sesion vieja ya no sirve: vaciarlo hace que el ciclo
 * siguiente abra otra con lo pedido. Un guardado que trae cursor nuevo es la
 * ingesta escribiendo la sesion que acaba de abrir, y ese cursor se respeta.
 */
trigger ControlNuevaSesion on Control_de_Ingesta__c(before update) {
  for (Control_de_Ingesta__c control : Trigger.new) {
    Control_de_Ingesta__c anterior = Trigger.oldMap.get(control.Id);
    Boolean otraSesion =
      control.Escenario__c != anterior.Escenario__c ||
      control.Semilla__c != anterior.Semilla__c;
    Boolean mismoCursor = control.Cursor__c == null
      ? anterior.Cursor__c == null
      : control.Cursor__c.equals(anterior.Cursor__c);
    if (otraSesion && mismoCursor) {
      control.Cursor__c = null;
    }
  }
}
