/**
 * El relleno copia el resultado al indice en las senales que buscan las vistas
 * (insertadas aqui sin indice, como las anteriores al campo), y un cambio a mano
 * del resultado lo corrige el flujo.
 */
@isTest
private class SenalIndiceRellenoBatchTest {
  @isTest
  static void shouldCopiarElResultado_WhenLaSenalNoTieneIndice() {
    List<Senal__c> senales = new List<Senal__c>{
      senal('rechazada', IngestaConstantes.RESULTADO_RECHAZADO),
      senal('conflicto', IngestaConstantes.RESULTADO_CONFLICTO),
      senal('aplicada', IngestaConstantes.RESULTADO_APLICADO)
    };
    insert senales;

    Test.startTest();
    Database.executeBatch(new SenalIndiceRellenoBatch(), 2000);
    Test.stopTest();

    Map<String, String> indice = new Map<String, String>();
    for (Senal__c s : [
      SELECT Message_Id__c, Resultado_Indice__c
      FROM Senal__c
    ]) {
      indice.put(s.Message_Id__c, s.Resultado_Indice__c);
    }
    Assert.areEqual(
      IngestaConstantes.RESULTADO_RECHAZADO,
      indice.get('rechazada')
    );
    Assert.areEqual(
      IngestaConstantes.RESULTADO_CONFLICTO,
      indice.get('conflicto')
    );
  }

  @isTest
  static void shouldCorregirElIndice_WhenSeCambiaElResultadoAMano() {
    Senal__c senal = senal('corregida', IngestaConstantes.RESULTADO_RECHAZADO);
    insert senal;

    senal.Resultado__c = IngestaConstantes.RESULTADO_APLICADO;
    update senal;

    Assert.areEqual(
      IngestaConstantes.RESULTADO_APLICADO,
      [SELECT Resultado_Indice__c FROM Senal__c WHERE Id = :senal.Id]
      .Resultado_Indice__c,
      'El flujo mantiene el indice igual al resultado'
    );
  }

  @isTest
  static void shouldCopiarAlAplicar_WhenLoPoneLaIngesta() {
    Senal__c senal = new Senal__c(Clave__c = 'prueba|aplicar');
    IngestaConstantes.aplicar(
      senal,
      IngestaConstantes.RESULTADO_FALLIDO,
      IngestaConstantes.MOTIVO_SISTEMA
    );
    Assert.areEqual(
      IngestaConstantes.RESULTADO_FALLIDO,
      senal.Resultado_Indice__c
    );
  }

  private static Senal__c senal(String id, String resultado) {
    return new Senal__c(
      Clave__c = 'prueba|' + id,
      Message_Id__c = id,
      Tipo_Mensaje__c = IngestaConstantes.TIPO_MEDICION,
      Resultado__c = resultado
    );
  }
}
