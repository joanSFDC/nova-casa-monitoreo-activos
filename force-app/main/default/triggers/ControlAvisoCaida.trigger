/**
 * Marca la caida de la ingesta cuando se corta por fallos y la vuelta con la
 * siguiente consulta exitosa. El aviso lo manda el flujo Avisar_Ingesta_Caida.
 */
trigger ControlAvisoCaida on Control_de_Ingesta__c(before update) {
  AvisoIngestaServicio.alGuardar(Trigger.new, Trigger.oldMap, Datetime.now());
}
