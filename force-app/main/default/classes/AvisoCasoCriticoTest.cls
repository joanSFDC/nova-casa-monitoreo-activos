/**
 * El flujo Avisar_Caso_Critico y los textos del correo. Apex no puede afirmar
 * que una alerta salio: se comprueba que el incidente queda guardado por cada
 * camino (nace en rojo, escala, sin ciudad) y que las formulas que lee el
 * correo dicen lo que muestra la maqueta.
 */
@isTest
private class AvisoCasoCriticoTest {
  @TestSetup
  static void preparar() {
    TestDataFactory.sembrarCatalogoMinimo();
  }

  @isTest
  static void shouldGuardarElIncidente_WhenNaceEnRojo() {
    Case incidente = incidente(bomba(), IncidentesServicio.PRIORIDAD_ALTA);
    incidente.Severidad_Apertura__c = IngestaConstantes.SEV_CRITICO;

    Test.startTest();
    insert incidente;
    Test.stopTest();

    Case guardado = leer(incidente.Id);
    Assert.areEqual(IncidentesServicio.PRIORIDAD_ALTA, guardado.Priority);
    Assert.areEqual('Nació en rojo', guardado.Como_Llego_A_Rojo__c);
    Assert.areEqual('Bogota', guardado.Ciudad__c, 'La ciudad decide la alerta');
    Assert.areEqual('Bomba de presion de agua', guardado.Equipo_Nombre__c);
  }

  @isTest
  static void shouldGuardarElIncidente_WhenEscalaDesdeAdvertencia() {
    Case incidente = incidente(bomba(), IncidentesServicio.PRIORIDAD_BAJA);
    incidente.Severidad_Apertura__c = 'Advertencia';
    insert incidente;

    Test.startTest();
    incidente.Priority = IncidentesServicio.PRIORIDAD_ALTA;
    update incidente;
    Test.stopTest();

    Case guardado = leer(incidente.Id);
    Assert.areEqual(IncidentesServicio.PRIORIDAD_ALTA, guardado.Priority);
    Assert.areEqual('Escaló desde advertencia', guardado.Como_Llego_A_Rojo__c);
  }

  @isTest
  static void shouldGuardarElIncidente_WhenNoTieneCiudad() {
    Case incidente = new Case(
      Subject = 'Sin equipo',
      Priority = IncidentesServicio.PRIORIDAD_ALTA
    );

    Test.startTest();
    insert incidente;
    Test.stopTest();

    Case guardado = leer(incidente.Id);
    Assert.isNull(guardado.Ciudad__c, 'Sin ciudad no hay alerta de operadores');
    Assert.areEqual(IncidentesServicio.PRIORIDAD_ALTA, guardado.Priority);
  }

  @isTest
  static void shouldDecirLaHoraEnBogota_WhenSeGuarda() {
    Case incidente = incidente(bomba(), IncidentesServicio.PRIORIDAD_ALTA);
    insert incidente;

    Case guardado = leer(incidente.Id);
    Datetime bogota = guardado.LastModifiedDate.addHours(-5);
    Integer hora = bogota.hourGmt();
    String esperada =
      bogota.formatGmt('dd/MM/yyyy') +
      ', ' +
      (Math.mod(hora, 12) == 0 ? 12 : Math.mod(hora, 12)) +
      ':' +
      bogota.formatGmt('mm') +
      (hora < 12 ? ' a. m.' : ' p. m.');
    Assert.areEqual(esperada, guardado.Hora_Cambio_Texto__c);
  }

  @isTest
  static void shouldDecirElCorte_WhenEsUnaCamara() {
    Activo__c camara = [
      SELECT Id
      FROM Activo__c
      WHERE Codigo_Externo__c = :TestDataFactory.AST_CAM
    ];
    Case incidente = incidente(camara, IncidentesServicio.PRIORIDAD_ALTA);
    incidente.Tipo_Medicion__c = LecturaFormato.CONECTIVIDAD;
    incidente.Ultima_Lectura__c = LecturaFormato.corte('LOST', 62 * 60);
    insert incidente;

    Case guardado = leer(incidente.Id);
    Assert.areEqual('Qué pasó', guardado.Que_Paso_Titulo__c);
    Assert.isTrue(
      guardado.Que_Paso__c.startsWith('Sin comunicación desde hace '),
      'Una cámara dice su corte, no un valor: ' + guardado.Que_Paso__c
    );
  }

  @isTest
  static void shouldDecirLaCola_WhenEstaEnCoordinacion() {
    Case incidente = incidente(bomba(), IncidentesServicio.PRIORIDAD_ALTA);
    incidente.Ultima_Lectura__c = '1,20 bar';
    incidente.OwnerId = IncidentesServicio.colaCoordinacion();
    insert incidente;

    Case guardado = leer(incidente.Id);
    Assert.areEqual(
      'Está en la cola de Coordinación, sin responsable.',
      guardado.Responsable_Texto__c
    );
    Assert.areEqual(
      'La lectura que lo puso en rojo',
      guardado.Que_Paso_Titulo__c
    );
    Assert.areEqual('1,20 bar', guardado.Que_Paso__c);
  }

  private static Activo__c bomba() {
    return [
      SELECT Id
      FROM Activo__c
      WHERE Codigo_Externo__c = :TestDataFactory.AST_PUMP
    ];
  }

  private static Case incidente(Activo__c activo, String prioridad) {
    return new Case(
      Subject = 'Lectura fuera de rango de prueba',
      Activo__c = activo.Id,
      Tipo_Medicion__c = 'WATER_PRESSURE',
      Priority = prioridad
    );
  }

  private static Case leer(Id casoId) {
    return [
      SELECT
        Priority,
        Ciudad__c,
        LastModifiedDate,
        Como_Llego_A_Rojo__c,
        Equipo_Nombre__c,
        Hora_Cambio_Texto__c,
        Que_Paso_Titulo__c,
        Que_Paso__c,
        Responsable_Texto__c
      FROM Case
      WHERE Id = :casoId
    ];
  }
}
