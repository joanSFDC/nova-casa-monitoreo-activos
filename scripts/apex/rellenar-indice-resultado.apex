// Corre una vez el relleno de Resultado_Indice__c en las senales anteriores al campo.
Id trabajo = Database.executeBatch(new SenalIndiceRellenoBatch(), SenalIndiceRellenoBatch.TAMANO_LOTE);
System.debug('RELLENO lanzado ' + trabajo);
