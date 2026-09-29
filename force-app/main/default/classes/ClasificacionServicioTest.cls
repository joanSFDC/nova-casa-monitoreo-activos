/**
 * Fronteras cerradas de medicion y escalada de conectividad por minutos.
 */
@isTest
private class ClasificacionServicioTest {
  @TestSetup
  static void setup() {
    TestDataFactory.sembrarCatalogoMinimo();
  }

  @isTest
  static void shouldSerNormal_WhenPresionEnBanda() {
    Umbral__c umbral = umbralDe('WATER_PUMP|WATER_PRESSURE');
    Test.startTest();
    ClasificacionServicio.Dictamen d = ClasificacionServicio.clasificarMedicion(
      2.76,
      umbral
    );
    Test.stopTest();
    Assert.areEqual(
      IngestaConstantes.SEV_NORMAL,
      d.severidad,
      '2.76 BAR es normal'
    );
    Assert.areEqual(0, d.nivel, 'Nivel 0');
    Assert.isTrue(d.esValido(), 'Sin motivo');
  }

  @isTest
  static void shouldSerAdvertencia_WhenFronteraInclusiva() {
    Umbral__c umbral = umbralDe('WATER_PUMP|WATER_PRESSURE');
    Test.startTest();
    ClasificacionServicio.Dictamen d = ClasificacionServicio.clasificarMedicion(
      4.01,
      umbral
    );
    Test.stopTest();
    Assert.areEqual(
      IngestaConstantes.SEV_ADVERTENCIA,
      d.severidad,
      '4.01 es el minimo de advertencia alta'
    );
  }

  @isTest
  static void shouldSerCritico_WhenPorEncimaDelTecho() {
    Umbral__c umbral = umbralDe('TECHNICAL_ROOM|TEMPERATURE');
    Test.startTest();
    ClasificacionServicio.Dictamen d = ClasificacionServicio.clasificarMedicion(
      60.19,
      umbral
    );
    Test.stopTest();
    Assert.areEqual(
      IngestaConstantes.SEV_CRITICO,
      d.severidad,
      'Hueco del catalogo sigue siendo critico'
    );
  }

  @isTest
  static void shouldSerNormal_WhenTreintaGrados() {
    Umbral__c umbral = umbralDe('TECHNICAL_ROOM|TEMPERATURE');
    ClasificacionServicio.Dictamen d = ClasificacionServicio.clasificarMedicion(
      30,
      umbral
    );
    Assert.areEqual(
      IngestaConstantes.SEV_NORMAL,
      d.severidad,
      '30 C es el maximo de normal'
    );
    Assert.areEqual(0, d.nivel);
  }

  @isTest
  static void shouldSerAdvertencia_WhenTreintaYCinco() {
    Umbral__c umbral = umbralDe('TECHNICAL_ROOM|TEMPERATURE');
    ClasificacionServicio.Dictamen d = ClasificacionServicio.clasificarMedicion(
      35,
      umbral
    );
    Assert.areEqual(
      IngestaConstantes.SEV_ADVERTENCIA,
      d.severidad,
      '35 C no llega a critico 35.1'
    );
  }

  @isTest
  static void shouldSerCritico_WhenTreintaYCincoPuntoUno() {
    Umbral__c umbral = umbralDe('TECHNICAL_ROOM|TEMPERATURE');
    ClasificacionServicio.Dictamen d = ClasificacionServicio.clasificarMedicion(
      35.1,
      umbral
    );
    Assert.areEqual(
      IngestaConstantes.SEV_CRITICO,
      d.severidad,
      '35.1 C es el minimo de critico alto'
    );
  }

  @isTest
  static void shouldSerAdvertencia_WhenQuinceGrados() {
    Umbral__c umbral = umbralDe('TECHNICAL_ROOM|TEMPERATURE');
    ClasificacionServicio.Dictamen d = ClasificacionServicio.clasificarMedicion(
      15,
      umbral
    );
    Assert.areEqual(
      IngestaConstantes.SEV_ADVERTENCIA,
      d.severidad,
      '15 C es advertencia baja'
    );
  }

  @isTest
  static void shouldSerCritico_WhenCatorcePuntoNueve() {
    Umbral__c umbral = umbralDe('TECHNICAL_ROOM|TEMPERATURE');
    ClasificacionServicio.Dictamen d = ClasificacionServicio.clasificarMedicion(
      14.9,
      umbral
    );
    Assert.areEqual(
      IngestaConstantes.SEV_CRITICO,
      d.severidad,
      '14.9 C es critico bajo'
    );
  }

  @isTest
  static void shouldRechazarReintentable_WhenSinUmbral() {
    ClasificacionServicio.Dictamen d = ClasificacionServicio.clasificarMedicion(
      30,
      null
    );
    Assert.isNull(d.severidad, 'Sin umbral no se finge normal');
    Assert.areEqual(IngestaConstantes.MOTIVO_SIN_LIMITE, d.motivo);
    Assert.isTrue(IngestaConstantes.esReintentable(d.motivo));
  }

  @isTest
  static void shouldUsarSoloBandaAlta_WhenConsumo() {
    Umbral__c consumo = new Umbral__c(
      Advertencia_Alto__c = 401,
      Critico_Alto__c = 651
    );
    Assert.areEqual(
      IngestaConstantes.SEV_NORMAL,
      ClasificacionServicio.clasificarMedicion(0, consumo).severidad
    );
    Assert.areEqual(
      IngestaConstantes.SEV_ADVERTENCIA,
      ClasificacionServicio.clasificarMedicion(401, consumo).severidad
    );
    Assert.areEqual(
      IngestaConstantes.SEV_CRITICO,
      ClasificacionServicio.clasificarMedicion(651, consumo).severidad
    );
  }

  @isTest
  static void shouldSerNormal_WhenLostCorto() {
    Umbral__c umbral = umbralDe('SECURITY_CAMERA|CAMERA_CONNECTIVITY');
    Test.startTest();
    ClasificacionServicio.Dictamen d = ClasificacionServicio.clasificarConectividad(
      'LOST',
      180,
      umbral
    );
    Test.stopTest();
    Assert.areEqual(
      IngestaConstantes.SEV_NORMAL,
      d.severidad,
      'Tres minutos no despiertan'
    );
  }

  @isTest
  static void shouldSerAdvertencia_WhenLostDeQuinceMinutos() {
    Umbral__c umbral = umbralDe('SECURITY_CAMERA|CAMERA_CONNECTIVITY');
    Test.startTest();
    ClasificacionServicio.Dictamen d = ClasificacionServicio.clasificarConectividad(
      'LOST',
      15 * 60,
      umbral
    );
    Test.stopTest();
    Assert.areEqual(
      IngestaConstantes.SEV_ADVERTENCIA,
      d.severidad,
      'Exactamente 15 min ya es advertencia'
    );
  }

  private static Umbral__c umbralDe(String clave) {
    return [
      SELECT
        Clave__c,
        Critico_Bajo__c,
        Critico_Alto__c,
        Advertencia_Bajo__c,
        Advertencia_Alto__c,
        Minutos_Advertencia__c,
        Minutos_Critico__c,
        Unidad__c
      FROM Umbral__c
      WHERE Clave__c = :clave
    ];
  }
}
