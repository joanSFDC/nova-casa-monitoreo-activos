/**
 * La caida de la ingesta se marca una vez: al cortarse por fallos o tras 10
 * minutos sin consultas exitosas, y se cierra con la siguiente consulta. El
 * vigia se programa en seis trabajos propios.
 */
@isTest
private class AvisoIngestaServicioTest {
  @isTest
  static void shouldMarcarCaida_WhenSeCortaPorFallos() {
    Control_de_Ingesta__c control = TestDataFactory.crearControl(false);
    control.Fallos_Consecutivos__c = IngestaConstantes.FALLOS_PARA_CORTAR;
    insert control;

    Test.startTest();
    control.Fallos_Consecutivos__c = IngestaConstantes.FALLOS_PARA_CORTAR + 1;
    control.Ultimo_Error__c = '503 Servicio no disponible';
    update control;
    Test.stopTest();

    Control_de_Ingesta__c leido = leer(control.Id);
    Assert.isNotNull(leido.Caida_Desde__c, 'El corte marca la caida');
    Assert.isTrue(
      leido.Motivo_Caida__c.contains('4 fallos seguidos') &&
      leido.Motivo_Caida__c.contains('503'),
      'Dice por que: ' + leido.Motivo_Caida__c
    );
  }

  @isTest
  static void shouldNoRepetirMarca_WhenSigueFallando() {
    Control_de_Ingesta__c control = TestDataFactory.crearControl(false);
    control.Fallos_Consecutivos__c = IngestaConstantes.FALLOS_PARA_CORTAR + 1;
    Datetime marca = Datetime.now().addMinutes(-20);
    control.Caida_Desde__c = marca;
    insert control;

    control.Fallos_Consecutivos__c = IngestaConstantes.FALLOS_PARA_CORTAR + 2;
    update control;

    Assert.areEqual(
      marca,
      leer(control.Id).Caida_Desde__c,
      'Una marca por caida'
    );
  }

  @isTest
  static void shouldMarcarCaida_WhenDiezMinutosSinConsultas() {
    Datetime ahora = Datetime.now();
    Control_de_Ingesta__c control = TestDataFactory.crearControl(false);
    control.Ultima_Consulta_Exitosa__c = ahora.addMinutes(-15);
    insert control;

    Test.startTest();
    Boolean marco = AvisoIngestaServicio.revisar(ahora);
    Test.stopTest();

    Assert.isTrue(marco, 'Quince minutos sin consultas es una caida');
    Control_de_Ingesta__c leido = leer(control.Id);
    Assert.isNotNull(leido.Caida_Desde__c);
    Assert.areEqual(
      'Sin consultas exitosas desde hace 15 min.',
      leido.Motivo_Caida__c
    );
  }

  @isTest
  static void shouldNoMarcar_WhenConsultaRecienteInactivaOYaAvisada() {
    Datetime ahora = Datetime.now();
    Control_de_Ingesta__c control = TestDataFactory.crearControl(false);
    control.Ultima_Consulta_Exitosa__c = ahora.addMinutes(-5);
    insert control;
    Assert.isFalse(
      AvisoIngestaServicio.revisar(ahora),
      'Cinco minutos no es caida'
    );

    control.Ultima_Consulta_Exitosa__c = ahora.addMinutes(-30);
    control.Caida_Desde__c = ahora.addMinutes(-20);
    update control;
    Assert.isFalse(AvisoIngestaServicio.revisar(ahora), 'Ya se aviso');

    control.Caida_Desde__c = null;
    control.Activo__c = false;
    update control;
    Assert.isFalse(
      AvisoIngestaServicio.revisar(ahora),
      'Una ingesta apagada a proposito no es una caida'
    );
  }

  @isTest
  static void shouldCerrarLaCaida_WhenVuelveUnaConsultaExitosa() {
    Datetime ahora = Datetime.now();
    Control_de_Ingesta__c control = TestDataFactory.crearControl(false);
    control.Ultima_Consulta_Exitosa__c = ahora.addMinutes(-30);
    control.Caida_Desde__c = ahora.addMinutes(-20);
    control.Motivo_Caida__c = 'Sin consultas exitosas desde hace 10 min.';
    insert control;

    Test.startTest();
    control.Ultima_Consulta_Exitosa__c = ahora;
    control.Fallos_Consecutivos__c = 0;
    update control;
    Test.stopTest();

    Control_de_Ingesta__c leido = leer(control.Id);
    Assert.isNull(leido.Caida_Desde__c, 'La consulta exitosa cierra la caida');
    Assert.areEqual(30, leido.Minutos_Ultima_Caida__c, 'Cuanto estuvo caida');
  }

  @isTest
  static void shouldProgramarSeisVigias_WhenSeProgramaYSeQuita() {
    Test.startTest();
    List<String> ids = VigiaIngestaSchedulable.programar();
    Test.stopTest();

    String prefijo = VigiaIngestaSchedulable.NOMBRE_JOB + '%';
    Assert.areEqual(6, ids.size(), 'Seis trabajos, uno cada 10 minutos');
    Assert.areEqual(
      6,
      [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE :prefijo]
    );
    VigiaIngestaSchedulable.abortar();
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE :prefijo]
    );
  }

  @isTest
  static void shouldMarcarCaida_WhenCorreElVigia() {
    Control_de_Ingesta__c control = TestDataFactory.crearControl(false);
    control.Ultima_Consulta_Exitosa__c = Datetime.now().addHours(-1);
    insert control;

    Test.startTest();
    new VigiaIngestaSchedulable().execute(null);
    Test.stopTest();

    Assert.isNotNull(
      leer(control.Id).Caida_Desde__c,
      'El vigia marca la caida'
    );
  }

  private static Control_de_Ingesta__c leer(Id controlId) {
    return [
      SELECT Caida_Desde__c, Motivo_Caida__c, Minutos_Ultima_Caida__c
      FROM Control_de_Ingesta__c
      WHERE Id = :controlId
    ];
  }
}
