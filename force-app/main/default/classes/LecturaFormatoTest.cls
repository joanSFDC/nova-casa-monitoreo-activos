/**
 * Como se dice una lectura: decimales, unidad, comunicacion y antiguedad.
 */
@isTest
private class LecturaFormatoTest {
  @isTest
  static void shouldCalcularAntiguedadDesdeOrigen() {
    Datetime ahora = Datetime.newInstanceGmt(2026, 10, 1, 12, 0, 0);
    Assert.areEqual(
      'hace un momento',
      LecturaFormato.antiguedad(ahora.addSeconds(-20), ahora)
    );
    Assert.areEqual(
      'hace 15 min',
      LecturaFormato.antiguedad(ahora.addMinutes(-15), ahora)
    );
    Assert.areEqual(
      'hace 3 h',
      LecturaFormato.antiguedad(ahora.addHours(-3), ahora)
    );
    Assert.areEqual(
      'hace 2 d',
      LecturaFormato.antiguedad(ahora.addDays(-2), ahora)
    );
    Assert.areEqual(
      'hace un momento',
      LecturaFormato.antiguedad(ahora.addHours(2), ahora),
      'Una lectura con el reloj del simulador por delante no se pinta en el futuro'
    );
    Assert.areEqual('Sin fecha', LecturaFormato.antiguedad(null, ahora));
  }

  @isTest
  static void shouldConservarCerosFinales_WhenUmbralPideDecimales() {
    String separador = Decimal.valueOf('1.5').format().substring(1, 2);
    Assert.areEqual(
      '0' + separador + '80',
      LecturaFormato.conDecimales(0.8, 2)
    );
    Assert.areEqual('18' + separador + '0', LecturaFormato.conDecimales(18, 1));
    Assert.areEqual('247', LecturaFormato.conDecimales(247, 0));
  }

  @isTest
  static void shouldEscribirValorConUnidad_WhenMedicion() {
    String separador = Decimal.valueOf('1.5').format().substring(1, 2);
    Assert.areEqual(
      '0' + separador + '80 bar',
      LecturaFormato.lectura('WATER_PRESSURE', 0.8, 'BAR', 2, null, null)
    );
    Assert.areEqual(
      '32' + separador + '7 \u00b0C',
      LecturaFormato.valor(32.7, 'CELSIUS', 1)
    );
    Assert.areEqual(
      LecturaFormato.SIN_VALOR,
      LecturaFormato.valor(null, 'BAR', 2),
      'Sin valor no se inventa un cero'
    );
  }

  @isTest
  static void shouldNombrarElCorte_WhenCamara() {
    Assert.areEqual(
      'Sin comunicaci\u00f3n \u00b7 15 min',
      LecturaFormato.lectura(
        LecturaFormato.CONECTIVIDAD,
        null,
        null,
        null,
        'LOST',
        900
      )
    );
    Assert.areEqual(
      'Sin comunicaci\u00f3n \u00b7 45 s',
      LecturaFormato.corte('LOST', 45)
    );
    Assert.areEqual(
      'Comunicaci\u00f3n recuperada',
      LecturaFormato.corte('RESTORED', 120)
    );
    Assert.areEqual(
      'En l\u00ednea',
      LecturaFormato.corte('HEALTHY', 30),
      'Una camara sana tambien se nombra'
    );
    Assert.isNull(
      LecturaFormato.comunicacion('HEALTHY'),
      'Pero no es un aviso'
    );
    Assert.areEqual('Recuperada', LecturaFormato.comunicacion('RESTORED'));
  }

  @isTest
  static void shouldTraducirSeveridadYNivel() {
    Assert.areEqual('Cr\u00edtico', LecturaFormato.severidad(2));
    Assert.areEqual(
      IngestaConstantes.SEV_CRITICO,
      LecturaFormato.severidadApi(2)
    );
    Assert.areEqual(
      IngestaConstantes.SEV_ADVERTENCIA,
      LecturaFormato.severidadApi(1)
    );
    Assert.areEqual(
      IngestaConstantes.SEV_NORMAL,
      LecturaFormato.severidadApi(0)
    );
    Assert.areEqual(2, LecturaFormato.nivelDe(IngestaConstantes.SEV_CRITICO));
    Assert.areEqual(0, LecturaFormato.nivelDe(null));
    Assert.areEqual(
      'Bomba de presi\u00f3n',
      LecturaFormato.tipoActivo('WATER_PUMP')
    );
    Assert.areEqual(
      'Consumo de agua',
      LecturaFormato.medicion('WATER_CONSUMPTION')
    );
  }
}
