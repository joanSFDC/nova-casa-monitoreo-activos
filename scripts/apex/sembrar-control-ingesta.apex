// Crea o actualiza el registro unico de Control_de_Ingesta__c.
// No abre sesion ni guarda el token.

List<Control_de_Ingesta__c> existentes = [
    SELECT Id, Name, Cursor__c, Fallos_Consecutivos__c, Paginas_Procesadas__c
    FROM Control_de_Ingesta__c
    WHERE Activo__c = true
    LIMIT 1
];
Control_de_Ingesta__c control = existentes.isEmpty()
    ? new Control_de_Ingesta__c()
    : existentes[0];
control.Name = 'Control principal';
control.Activo__c = true;
control.Escenario__c = 'MIXED';
control.Semilla__c = 20260922;
control.Tamano_Tanda__c = 50;
control.Fallos_Consecutivos__c = 0;
if (control.Paginas_Procesadas__c == null) {
    control.Paginas_Procesadas__c = 0;
}
upsert control;
System.debug('CONTROL id=' + control.Id + ' cursor=' + control.Cursor__c);
