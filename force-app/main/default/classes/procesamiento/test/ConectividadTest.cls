/**
 * US-206: severidad por valor y por silencio, resumen del activo, RESTORED sin cerrar.
 */
@isTest
private class ConectividadTest {
  private static final String CLAVE_CAMARA =
    TestDataFactory.AST_CAM + '|CAMERA_CONNECTIVITY';
  private static final String CLAVE_PRESION =
    TestDataFactory.AST_PUMP + '|WATER_PRESSURE';

  @TestSetup
  static void setup() {
    TestDataFactory.sembrarCatalogoMinimo();
  }

  @isTest
  static void shouldNoAbrirCaso_WhenMedicionNormal() {
    Activo__c bomba = bomba();
    Map<String, Object> mensaje = TestDataFactory.mensajePresion();
    insert TestDataFactory.senalPendiente(mensaje, bomba.Id, bomba.Edificio__c);

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(mensaje) }
    );
    Test.stopTest();

    Estado_Actual__c estado = [
      SELECT Severidad__c, Severidad_Nivel__c
      FROM Estado_Actual__c
      WHERE Clave__c = :CLAVE_PRESION
    ];
    Assert.areEqual(IngestaConstantes.SEV_NORMAL, estado.Severidad__c);
    Assert.areEqual(0, estado.Severidad_Nivel__c);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Case],
      'Normal no abre intervencion'
    );
  }

  @isTest
  static void shouldResumirCritico_WhenActivoTieneNormalYCritico() {
    Activo__c bomba = bomba();
    insert new List<Estado_Actual__c>{
      new Estado_Actual__c(
        Activo__c = bomba.Id,
        Clave__c = bomba.Codigo_Externo__c + '|WATER_PRESSURE',
        Tipo_Medicion__c = 'WATER_PRESSURE',
        Severidad__c = IngestaConstantes.SEV_NORMAL,
        Severidad_Nivel__c = 0
      ),
      new Estado_Actual__c(
        Activo__c = bomba.Id,
        Clave__c = bomba.Codigo_Externo__c + '|ENERGY_CONSUMPTION',
        Tipo_Medicion__c = 'ENERGY_CONSUMPTION',
        Severidad__c = IngestaConstantes.SEV_CRITICO,
        Severidad_Nivel__c = 2
      )
    };

    Activo__c leido = [
      SELECT Severidad_Nivel__c, Severidad__c
      FROM Activo__c
      WHERE Id = :bomba.Id
    ];
    Assert.areEqual(2, leido.Severidad_Nivel__c, 'La peor gana');
    Assert.areEqual('Crítico', leido.Severidad__c);
  }

  @isTest
  static void shouldDejarNormalYVaciarEpisodio_WhenHealthy() {
    Activo__c camara = camara();
    Map<String, Object> mensaje = TestDataFactory.mensajeCamara(
      'msg_hb',
      'HEALTHY',
      60,
      'EPI-BOG-hb'
    );
    insert TestDataFactory.senalPendiente(
      mensaje,
      camara.Id,
      camara.Edificio__c
    );

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(mensaje) }
    );
    Test.stopTest();

    Estado_Actual__c estado = estadoCamara();
    Assert.areEqual(IngestaConstantes.SEV_NORMAL, estado.Severidad__c);
    Assert.areEqual('HEALTHY', estado.Estado_Comunicacion__c);
    Assert.areEqual(0, estado.Sin_Comunicacion_Num__c);
    Assert.areEqual(null, estado.Valor__c, 'Conectividad no es una lectura');
    Assert.areEqual(null, estado.Episodio_Id__c, 'El latido vacia el episodio');
    Assert.areEqual(0, [SELECT COUNT() FROM Case]);
  }

  @isTest
  static void shouldMarcarSilencioSinCaso_WhenLostDeNoventaSegundos() {
    Activo__c camara = camara();
    Map<String, Object> mensaje = TestDataFactory.mensajeCamara(
      'msg_lost90',
      'LOST',
      90,
      'EPI-BOG-out-0'
    );
    insert TestDataFactory.senalPendiente(
      mensaje,
      camara.Id,
      camara.Edificio__c
    );

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(mensaje) }
    );
    Test.stopTest();

    Estado_Actual__c estado = estadoCamara();
    Assert.areEqual(IngestaConstantes.SEV_NORMAL, estado.Severidad__c);
    Assert.areEqual('LOST', estado.Estado_Comunicacion__c);
    Assert.areEqual(1, estado.Sin_Comunicacion_Num__c);
    Assert.areEqual(90, estado.Gap_Segundos__c);
    Assert.areEqual(null, estado.Valor__c);
    Assert.areEqual(0, [SELECT COUNT() FROM Case], '90 s no despierta');
  }

  @isTest
  static void shouldEscalarMismoCaso_WhenLostDeQuinceYDeUnaHora() {
    Activo__c camara = camara();
    Map<String, Object> advertencia = TestDataFactory.mensajeCamara(
      'msg_lost15',
      'LOST',
      15 * 60,
      'EPI-BOG-out-0'
    );
    advertencia.put('occurredAt', '2026-09-22T22:00:00.000Z');
    Map<String, Object> critico = TestDataFactory.mensajeCamara(
      'msg_lost60',
      'LOST',
      60 * 60,
      'EPI-BOG-out-0'
    );
    critico.put('occurredAt', '2026-09-22T22:45:00.000Z');
    insert new List<Senal__c>{
      TestDataFactory.senalPendiente(
        advertencia,
        camara.Id,
        camara.Edificio__c
      ),
      TestDataFactory.senalPendiente(critico, camara.Id, camara.Edificio__c)
    };

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(advertencia) }
    );
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(critico) }
    );
    Test.stopTest();

    Assert.areEqual(1, [SELECT COUNT() FROM Case], 'Mismo episodio, un caso');
    Case incidente = [
      SELECT
        Priority,
        Clave_Abierta__c,
        IsClosed,
        Lectura_Apertura__c,
        Severidad_Apertura__c,
        Ultima_Lectura__c,
        Severidad_Ultima_Lectura__c,
        Condicion_Equipo__c
      FROM Case
    ];
    Assert.areEqual('CONN|EPI-BOG-out-0', incidente.Clave_Abierta__c);
    Assert.areEqual(IncidentesServicio.PRIORIDAD_ALTA, incidente.Priority);
    Assert.areEqual(false, incidente.IsClosed);
    Assert.areEqual(IngestaConstantes.SEV_CRITICO, estadoCamara().Severidad__c);
    Assert.areEqual(
      'Sin comunicaci\u00f3n \u00b7 15 min',
      incidente.Lectura_Apertura__c,
      'Lo abrio el corte de quince minutos'
    );
    Assert.areEqual(
      IngestaConstantes.SEV_ADVERTENCIA,
      incidente.Severidad_Apertura__c
    );
    Assert.areEqual(
      'Sin comunicaci\u00f3n \u00b7 1 h',
      incidente.Ultima_Lectura__c,
      'Lo escalo el de una hora'
    );
    Assert.areEqual(
      IngestaConstantes.SEV_CRITICO,
      incidente.Severidad_Ultima_Lectura__c
    );
    Assert.areEqual(
      IncidentesServicio.CONDICION_EN_FALLA,
      incidente.Condicion_Equipo__c
    );
  }

  @isTest
  static void shouldNoCerrarYConservarEpisodio_WhenRestored() {
    Activo__c camara = camara();
    Map<String, Object> perdido = TestDataFactory.mensajeCamara(
      'msg_lost15',
      'LOST',
      15 * 60,
      'EPI-BOG-out-0'
    );
    perdido.put('occurredAt', '2026-09-22T22:00:00.000Z');
    Map<String, Object> recuperado = TestDataFactory.mensajeCamara(
      'msg_restored',
      'RESTORED',
      15 * 60,
      'EPI-BOG-out-0'
    );
    recuperado.put('occurredAt', '2026-09-22T22:16:00.000Z');
    insert new List<Senal__c>{
      TestDataFactory.senalPendiente(perdido, camara.Id, camara.Edificio__c),
      TestDataFactory.senalPendiente(recuperado, camara.Id, camara.Edificio__c)
    };

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(perdido) }
    );
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(recuperado) }
    );
    Test.stopTest();

    Estado_Actual__c estado = estadoCamara();
    Assert.areEqual('RESTORED', estado.Estado_Comunicacion__c);
    Assert.areEqual(IngestaConstantes.SEV_NORMAL, estado.Severidad__c);
    Assert.areEqual(0, estado.Sin_Comunicacion_Num__c);
    Assert.areEqual('EPI-BOG-out-0', estado.Episodio_Id__c);
    Assert.areEqual(null, estado.Valor__c);

    Case incidente = [
      SELECT
        IsClosed,
        Description,
        Priority,
        Condicion_Equipo__c,
        Normalizado_En__c,
        Ultima_Lectura__c,
        Severidad_Ultima_Lectura__c,
        Ultima_Senal__c
      FROM Case
    ];
    Assert.areEqual(false, incidente.IsClosed, 'Cerrar es humano');
    Assert.areEqual(IncidentesServicio.PRIORIDAD_BAJA, incidente.Priority);
    Assert.areEqual(
      IncidentesServicio.CONDICION_NORMALIZADO,
      incidente.Condicion_Equipo__c,
      'La comunicacion volvio: el caso queda normalizado'
    );
    Assert.areEqual(
      Datetime.newInstanceGmt(2026, 9, 22, 22, 16, 0),
      incidente.Normalizado_En__c,
      'Con la fecha de origen de la recuperacion'
    );
    Assert.areEqual(
      'Comunicaci\u00f3n recuperada',
      incidente.Ultima_Lectura__c
    );
    Assert.areEqual(
      IngestaConstantes.SEV_NORMAL,
      incidente.Severidad_Ultima_Lectura__c
    );
    Assert.isTrue(
      incidente.Ultima_Senal__c.endsWith('msg_restored'),
      'Y nombra la senal que lo normalizo'
    );
    Assert.isTrue(
      incidente.Description != null &&
      incidente.Description.contains('Recuperado'),
      'Deja evidencia de recuperacion'
    );
    Assert.isTrue(
      incidente.Description.contains(' se\u00f1al '),
      'La linea nombra la senal con tilde'
    );
  }

  @isTest
  static void shouldDosCasos_WhenDosEpisodios() {
    Activo__c camara = camara();
    Map<String, Object> primero = TestDataFactory.mensajeCamara(
      'msg_out0',
      'LOST',
      15 * 60,
      'EPI-BOG-out-0'
    );
    primero.put('occurredAt', '2026-09-22T22:00:00.000Z');
    Map<String, Object> segundo = TestDataFactory.mensajeCamara(
      'msg_out2',
      'LOST',
      15 * 60,
      'EPI-BOG-out-2'
    );
    segundo.put('occurredAt', '2026-09-22T23:00:00.000Z');
    insert new List<Senal__c>{
      TestDataFactory.senalPendiente(primero, camara.Id, camara.Edificio__c),
      TestDataFactory.senalPendiente(segundo, camara.Id, camara.Edificio__c)
    };

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(primero) }
    );
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(segundo) }
    );
    Test.stopTest();

    Assert.areEqual(2, [SELECT COUNT() FROM Case], 'Dos cortes, dos casos');
    Set<String> claves = new Set<String>();
    for (Case incidente : [SELECT Clave_Abierta__c, IsClosed FROM Case]) {
      claves.add(incidente.Clave_Abierta__c);
      Assert.areEqual(false, incidente.IsClosed);
    }
    Assert.isTrue(claves.contains('CONN|EPI-BOG-out-0'));
    Assert.isTrue(claves.contains('CONN|EPI-BOG-out-2'));
  }

  @isTest
  static void shouldVaciarEpisodio_WhenHealthyDespuesDeLost() {
    Activo__c camara = camara();
    Map<String, Object> perdido = TestDataFactory.mensajeCamara(
      'msg_lost15',
      'LOST',
      15 * 60,
      'EPI-BOG-out-0'
    );
    perdido.put('occurredAt', '2026-09-22T22:00:00.000Z');
    Map<String, Object> latido = TestDataFactory.mensajeCamara(
      'msg_hb2',
      'HEALTHY',
      45,
      'EPI-BOG-hb'
    );
    latido.put('occurredAt', '2026-09-22T22:20:00.000Z');
    insert new List<Senal__c>{
      TestDataFactory.senalPendiente(perdido, camara.Id, camara.Edificio__c),
      TestDataFactory.senalPendiente(latido, camara.Id, camara.Edificio__c)
    };

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(perdido) }
    );
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(latido) }
    );
    Test.stopTest();

    Estado_Actual__c estado = estadoCamara();
    Assert.areEqual('HEALTHY', estado.Estado_Comunicacion__c);
    Assert.areEqual(null, estado.Episodio_Id__c);
    Assert.areEqual(1, [SELECT COUNT() FROM Case], 'El caso del corte sigue');
    Assert.areEqual(false, [SELECT IsClosed FROM Case].IsClosed);
  }

  @isTest
  static void shouldNormalizarSusCortes_WhenCamaraVuelveConOtroEpisodio() {
    Activo__c camara = camara();
    Map<String, Object> primero = TestDataFactory.mensajeCamara(
      'msg_out0',
      'LOST',
      15 * 60,
      'EPI-BOG-out-0'
    );
    primero.put('occurredAt', '2026-09-22T22:00:00.000Z');
    Map<String, Object> segundo = TestDataFactory.mensajeCamara(
      'msg_out2',
      'LOST',
      15 * 60,
      'EPI-BOG-out-2'
    );
    segundo.put('occurredAt', '2026-09-22T23:00:00.000Z');
    Map<String, Object> latido = TestDataFactory.mensajeCamara(
      'msg_hb3',
      'HEALTHY',
      40,
      'EPI-BOG-hb'
    );
    latido.put('occurredAt', '2026-09-22T23:30:00.000Z');
    insert new List<Senal__c>{
      TestDataFactory.senalPendiente(primero, camara.Id, camara.Edificio__c),
      TestDataFactory.senalPendiente(segundo, camara.Id, camara.Edificio__c),
      TestDataFactory.senalPendiente(latido, camara.Id, camara.Edificio__c)
    };

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(primero) }
    );
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(segundo) }
    );
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(latido) }
    );
    Test.stopTest();

    List<Case> cortes = [
      SELECT IsClosed, Condicion_Equipo__c, Ultima_Lectura__c, Normalizado_En__c
      FROM Case
    ];
    Assert.areEqual(2, cortes.size(), 'El latido no abre otro caso');
    for (Case corte : cortes) {
      Assert.isFalse(corte.IsClosed, 'Cerrar sigue siendo humano');
      Assert.areEqual(
        IncidentesServicio.CONDICION_NORMALIZADO,
        corte.Condicion_Equipo__c,
        'La camara volvio, aunque el episodio sea otro'
      );
      Assert.areEqual('En l\u00ednea', corte.Ultima_Lectura__c);
      Assert.areEqual(
        Datetime.newInstanceGmt(2026, 9, 22, 23, 30, 0),
        corte.Normalizado_En__c
      );
    }
  }

  private static Activo__c bomba() {
    return [
      SELECT Id, Edificio__c, Codigo_Externo__c
      FROM Activo__c
      WHERE Codigo_Externo__c = :TestDataFactory.AST_PUMP
    ];
  }

  private static Activo__c camara() {
    return [
      SELECT Id, Edificio__c, Codigo_Externo__c
      FROM Activo__c
      WHERE Codigo_Externo__c = :TestDataFactory.AST_CAM
    ];
  }

  private static Estado_Actual__c estadoCamara() {
    return [
      SELECT
        Severidad__c,
        Severidad_Nivel__c,
        Estado_Comunicacion__c,
        Sin_Comunicacion_Num__c,
        Gap_Segundos__c,
        Valor__c,
        Episodio_Id__c
      FROM Estado_Actual__c
      WHERE Clave__c = :CLAVE_CAMARA
    ];
  }
}
