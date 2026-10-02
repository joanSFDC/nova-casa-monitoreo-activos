// Una vez, al pasar Case a privado: los casos anteriores a CaseCiudad no
// tienen ciudad y ningun operador los veria. Guardarlos basta para que el
// disparador la escriba desde el edificio del activo.
List<Case> casos = [SELECT Id FROM Case WHERE Activo__c != null AND Ciudad__c = null];
update casos;
System.debug('Casos con ciudad: ' + casos.size());
