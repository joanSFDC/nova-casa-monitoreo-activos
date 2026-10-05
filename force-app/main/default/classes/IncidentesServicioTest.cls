/**
 * US-205: un incidente por problema, escalada, duplicado concurrente y reapertura.
 */
@isTest
private class IncidentesServicioTest {
  private static final String CLAVE_PRESION = 'AST-BOG-PUMP-001|WATER_PRESSURE';

  @TestSetup
  static void setup() {
    TestDataFactory.sembrarCatalogoMinimo();
  }

  @isTest
  static void shouldUnSoloCaso_WhenDiezCriticos() {
    Activo__c bomba = bomba();
    List<Senal__c> senales = new List<Senal__c>();
    List<Aviso_de_Senal__e> avisos = new List<Aviso_de_Senal__e>();
    for (Integer i = 1; i <= 10; i++) {
      String n = String.valueOf(i).leftPad(6, '0');
      Map<String, Object> mensaje = TestDataFactory.mensajePresion(
        'msg_c' + n,
        'dlv_c' + n,
        5.5,
        'BAR'
      );
      mensaje.put(
        'occurredAt',
        '2026-09-22T22:5' + String.valueOf(i - 1) + ':00.000Z'
      );
      senales.add(
        TestDataFactory.senalPendiente(mensaje, bomba.Id, bomba.Edificio__c)
      );
      avisos.add(TestDataFactory.avisoDe(mensaje));
    }
    insert senales;

    Test.startTest();
    ProcesamientoServicio.procesar(avisos);
    Test.stopTest();

    Assert.areEqual(1, [SELECT COUNT() FROM Case], 'Un caso bajo rafaga');
    Case incidente = [
      SELECT Priority, Clave_Abierta__c, Origen_Senal__c, Activo__c, OwnerId
      FROM Case
    ];
    Assert.areEqual(
      IncidentesServicio.PRIORIDAD_ALTA,
      incidente.Priority,
      'Critico abre en alta'
    );
    Assert.areEqual(
      IncidentesServicio.colaCoordinacion(),
      incidente.OwnerId,
      'Y entra en la cola del coordinador'
    );
    Assert.areEqual(CLAVE_PRESION, incidente.Clave_Abierta__c);
    Assert.areEqual(bomba.Id, incidente.Activo__c);
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM Senal__c
        WHERE
          Incidente__c = :incidente.Id
          AND Resultado__c = :IngestaConstantes.RESULTADO_APLICADO
      ],
      'Solo la vigente de la tanda liga al caso'
    );
    Assert.areEqual(
      9,
      [
        SELECT COUNT()
        FROM Senal__c
        WHERE Resultado__c = :IngestaConstantes.RESULTADO_ATRASADO
      ],
      'Las otras nueve de la misma clave quedan atrasadas'
    );
  }

  @isTest
  static void shouldEscalar_WhenAdvertenciaYLuegoCritico() {
    Activo__c bomba = bomba();
    Map<String, Object> advertencia = TestDataFactory.mensajePresion(
      'msg_adv',
      'dlv_adv',
      4.5,
      'BAR'
    );
    Map<String, Object> critico = TestDataFactory.mensajePresion(
      'msg_cri',
      'dlv_cri',
      5.5,
      'BAR'
    );
    critico.put('occurredAt', '2026-09-22T22:55:00.000Z');
    insert new List<Senal__c>{
      TestDataFactory.senalPendiente(advertencia, bomba.Id, bomba.Edificio__c),
      TestDataFactory.senalPendiente(critico, bomba.Id, bomba.Edificio__c)
    };

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(advertencia) }
    );
    Case despuesDeAdv = [
      SELECT Priority, OwnerId
      FROM Case
      WHERE Clave_Abierta__c = :CLAVE_PRESION
    ];
    Assert.areEqual(
      IncidentesServicio.PRIORIDAD_BAJA,
      despuesDeAdv.Priority,
      'Advertencia en baja'
    );
    Assert.areEqual(
      UserInfo.getUserId(),
      despuesDeAdv.OwnerId,
      'La advertencia no entra en ninguna cola'
    );
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(critico) }
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Case],
      'Sigue siendo el mismo caso'
    );
    Case incidente = [
      SELECT Priority, Clave_Abierta__c, OwnerId
      FROM Case
      WHERE Clave_Abierta__c = :CLAVE_PRESION
    ];
    Assert.areEqual(
      IncidentesServicio.PRIORIDAD_ALTA,
      incidente.Priority,
      'Sube a alta'
    );
    Assert.areEqual(
      IncidentesServicio.colaCoordinacion(),
      incidente.OwnerId,
      'Y pasa a la cola del coordinador'
    );
    Senal__c senalCritica = [
      SELECT Incidente__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_cri'
    ];
    Assert.areEqual(
      incidente.Id,
      senalCritica.Incidente__c,
      'La senal critica apunta al caso'
    );
  }

  @isTest
  static void shouldConservarPropietario_WhenUnaPersonaYaTomoElCaso() {
    Activo__c bomba = bomba();
    User operador;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      operador = TestDataFactory.usuarioConConjunto('Nova_Casa_Operador');
    }
    insert new Case(
      Subject = 'Tomado por el operador',
      Status = 'New',
      Origin = 'Web',
      Priority = IncidentesServicio.PRIORIDAD_BAJA,
      Clave_Abierta__c = CLAVE_PRESION,
      Activo__c = bomba.Id,
      Tipo_Medicion__c = 'WATER_PRESSURE',
      OwnerId = operador.Id
    );
    Map<String, Object> critico = TestDataFactory.mensajePresion(
      'msg_cri',
      'dlv_cri',
      5.5,
      'BAR'
    );
    insert TestDataFactory.senalPendiente(critico, bomba.Id, bomba.Edificio__c);

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(critico) }
    );
    Test.stopTest();

    Case incidente = [
      SELECT Priority, OwnerId
      FROM Case
      WHERE Clave_Abierta__c = :CLAVE_PRESION
    ];
    Assert.areEqual(
      IncidentesServicio.PRIORIDAD_ALTA,
      incidente.Priority,
      'Escala igual'
    );
    Assert.areEqual(
      operador.Id,
      incidente.OwnerId,
      'Quien ya lo tomo lo conserva'
    );
  }

  @isTest
  static void shouldNoEscalar_WhenCriticoQuedaAtrasadoEnLaTanda() {
    Activo__c bomba = bomba();
    Map<String, Object> critico = TestDataFactory.mensajePresion(
      'msg_cri',
      'dlv_cri',
      5.5,
      'BAR'
    );
    critico.put('occurredAt', '2026-09-22T22:50:00.000Z');
    Map<String, Object> advertencia = TestDataFactory.mensajePresion(
      'msg_adv',
      'dlv_adv',
      4.5,
      'BAR'
    );
    advertencia.put('occurredAt', '2026-09-22T22:55:00.000Z');
    insert new List<Senal__c>{
      TestDataFactory.senalPendiente(critico, bomba.Id, bomba.Edificio__c),
      TestDataFactory.senalPendiente(advertencia, bomba.Id, bomba.Edificio__c)
    };

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{
        TestDataFactory.avisoDe(critico),
        TestDataFactory.avisoDe(advertencia)
      }
    );
    Test.stopTest();

    Case incidente = [
      SELECT Priority, Origen_Senal__c
      FROM Case
      WHERE Clave_Abierta__c = :CLAVE_PRESION
    ];
    Assert.areEqual(
      IncidentesServicio.PRIORIDAD_BAJA,
      incidente.Priority,
      'La situacion vigente es una advertencia'
    );
    Assert.areEqual(
      'nova-casa-simulator|msg_adv',
      incidente.Origen_Senal__c,
      'El origen es la lectura aplicada'
    );
    Senal__c superada = [
      SELECT Resultado__c, Incidente__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_cri'
    ];
    Assert.areEqual(
      IngestaConstantes.RESULTADO_ATRASADO,
      superada.Resultado__c,
      'El critico perdio la tanda'
    );
    Assert.isNull(superada.Incidente__c, 'Una atrasada no se liga al caso');
  }

  @isTest
  static void shouldNoCrearSegundo_WhenReentregaDelBus() {
    Activo__c bomba = bomba();
    Map<String, Object> mensaje = TestDataFactory.mensajePresion(
      'msg_bus',
      'dlv_bus',
      5.5,
      'BAR'
    );
    insert TestDataFactory.senalPendiente(mensaje, bomba.Id, bomba.Edificio__c);
    Aviso_de_Senal__e aviso = TestDataFactory.avisoDe(mensaje);

    Test.startTest();
    ProcesamientoServicio.procesar(new List<Aviso_de_Senal__e>{ aviso });
    ProcesamientoServicio.procesar(new List<Aviso_de_Senal__e>{ aviso });
    Test.stopTest();

    Assert.areEqual(1, [SELECT COUNT() FROM Case], 'La reentrega no abre otro');
  }

  @isTest
  static void shouldNoAbrirCaso_WhenConflicto() {
    Activo__c bomba = bomba();
    Map<String, Object> mensaje = TestDataFactory.mensajePresion(
      'msg_conf',
      'dlv_conf',
      5.5,
      'BAR'
    );
    Senal__c senal = TestDataFactory.senalPendiente(
      mensaje,
      bomba.Id,
      bomba.Edificio__c
    );
    IngestaConstantes.aplicar(
      senal,
      IngestaConstantes.RESULTADO_CONFLICTO,
      IngestaConstantes.MOTIVO_VALOR
    );
    insert senal;

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(mensaje) }
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Case],
      'Un conflicto no abre incidente'
    );
  }

  @isTest
  static void shouldTratarDuplicadoComoExito_WhenCarrera() {
    Activo__c bomba = bomba();
    Map<String, Object> mensaje = TestDataFactory.mensajePresion(
      'msg_race',
      'dlv_race',
      5.5,
      'BAR'
    );
    Senal__c senal = TestDataFactory.senalPendiente(
      mensaje,
      bomba.Id,
      bomba.Edificio__c
    );
    senal.Resultado__c = IngestaConstantes.RESULTADO_APLICADO;
    insert senal;
    insert new Case(
      Subject = 'Ganador de la carrera',
      Status = 'New',
      Origin = 'Web',
      Priority = IncidentesServicio.PRIORIDAD_BAJA,
      Clave_Abierta__c = CLAVE_PRESION,
      Activo__c = bomba.Id,
      Tipo_Medicion__c = 'WATER_PRESSURE'
    );
    IncidentesServicio.Decision decision = new IncidentesServicio.Decision();
    decision.clave = CLAVE_PRESION;
    decision.activoId = bomba.Id;
    decision.tipoMedicion = 'WATER_PRESSURE';
    decision.claveSenal = senal.Clave__c;
    decision.clavesSenal = new Set<String>{ senal.Clave__c };
    decision.nivel = 2;
    decision.marcarRecuperado = false;

    Test.startTest();
    IncidentesServicio.escribir(
      new Map<String, IncidentesServicio.Decision>{ CLAVE_PRESION => decision },
      new Map<String, Case>(),
      new Map<String, Senal__c>{ senal.Clave__c => senal },
      Datetime.now()
    );
    Test.stopTest();

    Assert.areEqual(1, [SELECT COUNT() FROM Case], 'El duplicado no crea otro');
    Case ganador = [
      SELECT Priority, OwnerId
      FROM Case
      WHERE Clave_Abierta__c = :CLAVE_PRESION
    ];
    Assert.areEqual(
      IncidentesServicio.PRIORIDAD_ALTA,
      ganador.Priority,
      'Reintenta la escalada'
    );
    Assert.areEqual(
      IncidentesServicio.colaCoordinacion(),
      ganador.OwnerId,
      'La escalada reintentada tambien va a la cola'
    );
    Assert.areEqual(
      ganador.Id,
      senal.Incidente__c,
      'La senal perdedora queda ligada'
    );
  }

  @isTest
  static void shouldAbrirNuevo_WhenCierreLiberaClave() {
    Activo__c bomba = bomba();
    Map<String, Object> primero = TestDataFactory.mensajePresion(
      'msg_cierra',
      'dlv_cierra',
      5.5,
      'BAR'
    );
    Map<String, Object> segundo = TestDataFactory.mensajePresion(
      'msg_reabre',
      'dlv_reabre',
      5.6,
      'BAR'
    );
    segundo.put('occurredAt', '2026-09-22T23:10:00.000Z');
    insert new List<Senal__c>{
      TestDataFactory.senalPendiente(primero, bomba.Id, bomba.Edificio__c),
      TestDataFactory.senalPendiente(segundo, bomba.Id, bomba.Edificio__c)
    };

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(primero) }
    );
    Case abierto = [
      SELECT Id, Status
      FROM Case
      WHERE Clave_Abierta__c = :CLAVE_PRESION
    ];
    abierto.Status = estadoCerrado();
    update abierto;
    Case cerrado = [
      SELECT Clave_Abierta__c, IsClosed
      FROM Case
      WHERE Id = :abierto.Id
    ];
    Assert.isTrue(cerrado.IsClosed, 'Quedo cerrado');
    Assert.isTrue(
      String.isBlank(cerrado.Clave_Abierta__c),
      'El flujo vacio la clave'
    );
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(segundo) }
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      [SELECT COUNT() FROM Case],
      'Se abre uno nuevo al reaparecer'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Case WHERE Clave_Abierta__c = :CLAVE_PRESION],
      'Solo el nuevo ocupa la clave'
    );
  }

  @isTest
  static void shouldMarcarSenalFallida_WhenFallaCrearCaso() {
    Activo__c bomba = bomba();
    Map<String, Object> mensaje = TestDataFactory.mensajePresion(
      'msg_fail',
      'dlv_fail',
      5.5,
      'BAR'
    );
    insert TestDataFactory.senalPendiente(mensaje, bomba.Id, bomba.Edificio__c);
    IncidentesServicio.inyectarFalloDeCaso = true;

    Test.startTest();
    ProcesamientoServicio.ResultadoTanda r = ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(mensaje) }
    );
    Test.stopTest();

    Assert.areEqual(1, r.fallidas, 'La senal no queda como aplicada');
    Assert.areEqual(0, [SELECT COUNT() FROM Case], 'No hay caso');
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Estado_Actual__c WHERE Clave__c = :CLAVE_PRESION],
      'El estado si se actualizo'
    );
    Senal__c senal = [
      SELECT Resultado__c, Motivo__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_fail'
    ];
    Assert.areEqual(IngestaConstantes.RESULTADO_FALLIDO, senal.Resultado__c);
    Assert.areEqual(IngestaConstantes.MOTIVO_SISTEMA, senal.Motivo__c);
  }

  @isTest
  static void shouldNoCerrar_WhenVuelveANormal() {
    Activo__c bomba = bomba();
    Map<String, Object> critico = TestDataFactory.mensajePresion(
      'msg_mal',
      'dlv_mal',
      5.5,
      'BAR'
    );
    Map<String, Object> normal = TestDataFactory.mensajePresion(
      'msg_ok',
      'dlv_ok',
      2.76,
      'BAR'
    );
    normal.put('occurredAt', '2026-09-22T22:56:00.000Z');
    insert new List<Senal__c>{
      TestDataFactory.senalPendiente(critico, bomba.Id, bomba.Edificio__c),
      TestDataFactory.senalPendiente(normal, bomba.Id, bomba.Edificio__c)
    };

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(critico) }
    );
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(normal) }
    );
    Test.stopTest();

    Case incidente = [SELECT IsClosed, Clave_Abierta__c, Priority FROM Case];
    Assert.isFalse(incidente.IsClosed, 'Normal no cierra');
    Assert.areEqual(
      CLAVE_PRESION,
      incidente.Clave_Abierta__c,
      'Sigue ocupando la clave'
    );
    Estado_Actual__c estado = [
      SELECT Severidad__c
      FROM Estado_Actual__c
      WHERE Clave__c = :CLAVE_PRESION
    ];
    Assert.areEqual(
      IngestaConstantes.SEV_NORMAL,
      estado.Severidad__c,
      'El estado si volvio'
    );
  }

  @isTest
  static void shouldUnCaso_WhenMismoEpisodioDeCamara() {
    Activo__c camara = camara();
    List<Senal__c> senales = new List<Senal__c>();
    List<Aviso_de_Senal__e> avisos = new List<Aviso_de_Senal__e>();
    for (Integer i = 0; i < 3; i++) {
      Map<String, Object> mensaje = TestDataFactory.mensajeCamara();
      mensaje.put('messageId', 'msg_lost_' + i);
      mensaje.put('deliveryId', 'dlv_lost_' + i);
      mensaje.put(
        'occurredAt',
        '2026-09-22T22:1' + String.valueOf(i) + ':00.000Z'
      );
      Map<String, Object> comm = (Map<String, Object>) mensaje.get(
        'communication'
      );
      comm.put('status', 'LOST');
      comm.put('gapSeconds', 900 + (i * 60));
      comm.put('episodeId', 'EPI-BOG-out-0');
      senales.add(
        TestDataFactory.senalPendiente(mensaje, camara.Id, camara.Edificio__c)
      );
      avisos.add(TestDataFactory.avisoDe(mensaje));
    }
    insert senales;

    Test.startTest();
    ProcesamientoServicio.procesar(avisos);
    Test.stopTest();

    Assert.areEqual(1, [SELECT COUNT() FROM Case], 'Un episodio, un caso');
    Case incidente = [
      SELECT Clave_Abierta__c, Episodio_Id__c, Priority, Subject
      FROM Case
    ];
    Assert.areEqual('CONN|EPI-BOG-out-0', incidente.Clave_Abierta__c);
    Assert.areEqual(
      'Corte de comunicaci\u00f3n EPI-BOG-out-0',
      incidente.Subject
    );
    Assert.areEqual('EPI-BOG-out-0', incidente.Episodio_Id__c);
    Assert.areEqual(
      IncidentesServicio.PRIORIDAD_BAJA,
      incidente.Priority,
      '15 min es advertencia'
    );
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

  private static String estadoCerrado() {
    return [
      SELECT ApiName
      FROM CaseStatus
      WHERE IsClosed = TRUE
      LIMIT 1
    ]
    .ApiName;
  }
}
