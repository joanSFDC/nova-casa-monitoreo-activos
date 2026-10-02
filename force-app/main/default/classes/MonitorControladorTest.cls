/**
 * US-207: panel del operador, contadores en servidor, aviso de ingesta y abrir caso.
 */
@isTest
private class MonitorControladorTest {
  @TestSetup
  static void setup() {
    TestDataFactory.sembrarCatalogoMinimo();
    TestDataFactory.crearControl(true);
  }

  @isTest
  static void shouldVaciarPorLecturas_WhenCatalogoSinEstados() {
    Test.startTest();
    MonitorControlador.PanelDTO panel = MonitorControlador.obtenerPanel(null);
    Test.stopTest();

    Assert.isFalse(panel.sinEdificios, 'Hay edificios sembrados');
    Assert.isTrue(panel.sinLecturas, 'Todavia no hay estados');
    Assert.areEqual(0, panel.filas.size());
    Assert.areEqual(0, panel.criticos);
    Assert.areEqual(2, panel.edificios.size());
  }

  @isTest
  static void shouldOrdenarCriticoPrimero_WhenHayVariasSeveridades() {
    sembrarEstados();

    Test.startTest();
    MonitorControlador.PanelDTO panel = MonitorControlador.obtenerPanel(null);
    Test.stopTest();

    Assert.isFalse(panel.sinLecturas);
    Assert.areEqual(3, panel.filas.size());
    Assert.areEqual(1, panel.criticos);
    Assert.areEqual(1, panel.advertencias);
    Assert.areEqual(1, panel.normales);
    Assert.areEqual(
      panel.criticos + panel.advertencias + panel.normales,
      panel.filas.size(),
      'Los contadores coinciden con las filas'
    );
    Assert.areEqual('Critico', panel.filas[0].severidad);
    Assert.areEqual('Cr\u00edtico', panel.filas[0].severidadEtiqueta);
    Assert.areEqual('0,80 bar', panel.filas[0].valor.replace('.', ','));
    Assert.isTrue(panel.filas[0].puedeIntervenir);
    Assert.areEqual('Advertencia', panel.filas[1].severidad);
    Assert.areEqual('Normal', panel.filas[2].severidad);
  }

  @isTest
  static void shouldFiltrarPorEdificio_WhenSePideUno() {
    sembrarEstados();
    Id bogota = [
      SELECT Id
      FROM Edificio__c
      WHERE Codigo_Externo__c = :TestDataFactory.BLD_BOG
    ]
    .Id;

    Test.startTest();
    MonitorControlador.PanelDTO panel = MonitorControlador.obtenerPanel(bogota);
    Test.stopTest();

    Assert.areEqual(2, panel.filas.size(), 'Bomba y camara de Bogota');
    for (MonitorControlador.FilaDTO fila : panel.filas) {
      Assert.areEqual('Edificio Nova Alameda', fila.edificio);
    }
  }

  @isTest
  static void shouldMarcarConsultaAtrasada_WhenUltimaConsultaEsVieja() {
    Control_de_Ingesta__c control = [
      SELECT Id
      FROM Control_de_Ingesta__c
      LIMIT 1
    ];
    control.Ultima_Consulta_Exitosa__c = Datetime.now().addMinutes(-30);
    update control;

    Test.startTest();
    MonitorControlador.PanelDTO panel = MonitorControlador.obtenerPanel(null);
    Test.stopTest();

    Assert.isTrue(panel.consultaAtrasada);
  }

  @isTest
  static void shouldCalcularAntiguedadDesdeOrigen() {
    Datetime ahora = Datetime.newInstanceGmt(2026, 10, 1, 12, 0, 0);
    Assert.areEqual(
      'hace un momento',
      MonitorControlador.antiguedadDe(ahora.addSeconds(-20), ahora)
    );
    Assert.areEqual(
      'hace 15 min',
      MonitorControlador.antiguedadDe(ahora.addMinutes(-15), ahora)
    );
    Assert.areEqual(
      'hace 3 h',
      MonitorControlador.antiguedadDe(ahora.addHours(-3), ahora)
    );
    Assert.areEqual(
      'hace un momento',
      MonitorControlador.antiguedadDe(ahora.addHours(2), ahora),
      'Una lectura con el reloj del simulador por delante no se pinta en el futuro'
    );
  }

  @isTest
  static void shouldPintarComunicacion_WhenCamaraLost() {
    sembrarEstados();

    Test.startTest();
    MonitorControlador.PanelDTO panel = MonitorControlador.obtenerPanel(null);
    Test.stopTest();

    MonitorControlador.FilaDTO camara;
    for (MonitorControlador.FilaDTO fila : panel.filas) {
      if (fila.medicion == 'Conectividad') {
        camara = fila;
      }
    }
    Assert.isNotNull(camara);
    Assert.areEqual('Sin comunicaci\u00f3n', camara.comunicacion);
    Assert.areEqual('90 s', camara.valor);
    Assert.areEqual(null, camara.casoId, 'LOST corto no abre caso');
    Assert.isTrue(camara.puedeIntervenir, 'Sin comunicacion se puede atender');
  }

  @isTest
  static void shouldReutilizarCaso_WhenYaExisteAbierto() {
    Activo__c bomba = [
      SELECT Id, Codigo_Externo__c
      FROM Activo__c
      WHERE Codigo_Externo__c = :TestDataFactory.AST_PUMP
    ];
    Estado_Actual__c estado = new Estado_Actual__c(
      Activo__c = bomba.Id,
      Clave__c = bomba.Codigo_Externo__c + '|WATER_PRESSURE',
      Tipo_Medicion__c = 'WATER_PRESSURE',
      Valor__c = 0.8,
      Unidad__c = 'BAR',
      Severidad__c = IngestaConstantes.SEV_CRITICO,
      Severidad_Nivel__c = 2,
      Fecha_Origen__c = Datetime.now()
    );
    insert estado;
    Case abierto = new Case(
      Subject = 'Ya abierto',
      Status = 'New',
      Origin = 'Web',
      Priority = 'High',
      Clave_Abierta__c = bomba.Codigo_Externo__c + '|WATER_PRESSURE',
      Activo__c = bomba.Id,
      Tipo_Medicion__c = 'WATER_PRESSURE'
    );
    insert abierto;

    Test.startTest();
    Id devuelto = MonitorControlador.abrirIntervencion(estado.Id, 'revisar');
    Test.stopTest();

    Assert.areEqual(abierto.Id, devuelto);
    Assert.areEqual(1, [SELECT COUNT() FROM Case]);
  }

  @isTest
  static void shouldCrearCaso_WhenNoHayAbierto() {
    Activo__c bomba = [
      SELECT Id, Codigo_Externo__c
      FROM Activo__c
      WHERE Codigo_Externo__c = :TestDataFactory.AST_PUMP
    ];
    Estado_Actual__c estado = new Estado_Actual__c(
      Activo__c = bomba.Id,
      Clave__c = bomba.Codigo_Externo__c + '|WATER_PRESSURE',
      Tipo_Medicion__c = 'WATER_PRESSURE',
      Valor__c = 0.8,
      Unidad__c = 'BAR',
      Severidad__c = IngestaConstantes.SEV_CRITICO,
      Severidad_Nivel__c = 2,
      Fecha_Origen__c = Datetime.now()
    );
    insert estado;

    Test.startTest();
    Id casoId = MonitorControlador.abrirIntervencion(estado.Id, 'voy');
    Test.stopTest();

    Case incidente = [
      SELECT
        Priority,
        Description,
        Activo__c,
        Tipo_Medicion__c,
        Clave_Abierta__c
      FROM Case
      WHERE Id = :casoId
    ];
    Assert.areEqual(
      'High',
      incidente.Priority,
      'Critico abre en prioridad alta'
    );
    Assert.areEqual('voy', incidente.Description);
    Assert.areEqual(bomba.Id, incidente.Activo__c);
    Assert.areEqual('WATER_PRESSURE', incidente.Tipo_Medicion__c);
    Assert.areEqual(
      estado.Clave__c,
      incidente.Clave_Abierta__c,
      'Un caso abierto por equipo y medicion'
    );
  }

  @isTest
  static void shouldDejarLaNotaEnLaActividad_WhenSeAbreConNota() {
    Estado_Actual__c estado = estadoCriticoDeLaBomba();

    Test.startTest();
    Id casoId = MonitorControlador.abrirIntervencion(
      estado.Id,
      'Revisar la bomba'
    );
    Test.stopTest();

    List<Task> tareas = [
      SELECT Subject, Description, Status
      FROM Task
      WHERE WhatId = :casoId
    ];
    Assert.areEqual(1, tareas.size(), 'La nota es la primera actividad');
    Assert.areEqual('Revisar la bomba', tareas[0].Description);
    Assert.areEqual('Nota del operador', tareas[0].Subject);
    Assert.areEqual('Completed', tareas[0].Status);
  }

  @isTest
  static void shouldAbrirSinTarea_WhenNotaEnBlanco() {
    Estado_Actual__c estado = estadoCriticoDeLaBomba();

    Test.startTest();
    Id casoId = MonitorControlador.abrirIntervencion(estado.Id, null);
    Test.stopTest();

    Assert.isNotNull(casoId, 'Sin nota el caso se abre igual');
    Assert.areEqual(0, [SELECT COUNT() FROM Task WHERE WhatId = :casoId]);
  }

  private static Estado_Actual__c estadoCriticoDeLaBomba() {
    Activo__c bomba = [
      SELECT Id, Codigo_Externo__c
      FROM Activo__c
      WHERE Codigo_Externo__c = :TestDataFactory.AST_PUMP
    ];
    Estado_Actual__c estado = new Estado_Actual__c(
      Activo__c = bomba.Id,
      Clave__c = bomba.Codigo_Externo__c + '|WATER_PRESSURE',
      Tipo_Medicion__c = 'WATER_PRESSURE',
      Valor__c = 0.8,
      Unidad__c = 'BAR',
      Severidad__c = IngestaConstantes.SEV_CRITICO,
      Severidad_Nivel__c = 2,
      Fecha_Origen__c = Datetime.now()
    );
    insert estado;
    return estado;
  }

  @isTest
  static void shouldConservarCerosFinales_WhenUmbralPideDecimales() {
    String separador = Decimal.valueOf('1.5').format().substring(1, 2);
    Assert.areEqual(
      '0' + separador + '80',
      MonitorControlador.conDecimales(0.8, 2)
    );
    Assert.areEqual(
      '18' + separador + '0',
      MonitorControlador.conDecimales(18, 1)
    );
    Assert.areEqual('247', MonitorControlador.conDecimales(247, 0));
  }

  @isTest
  static void shouldRechazarIntervencion_WhenEquipoNormal() {
    Activo__c bomba = [
      SELECT Id, Codigo_Externo__c
      FROM Activo__c
      WHERE Codigo_Externo__c = :TestDataFactory.AST_PUMP
    ];
    Estado_Actual__c estado = new Estado_Actual__c(
      Activo__c = bomba.Id,
      Clave__c = bomba.Codigo_Externo__c + '|WATER_PRESSURE',
      Tipo_Medicion__c = 'WATER_PRESSURE',
      Valor__c = 3.2,
      Unidad__c = 'BAR',
      Severidad__c = IngestaConstantes.SEV_NORMAL,
      Severidad_Nivel__c = 0,
      Fecha_Origen__c = Datetime.now()
    );
    insert estado;

    Boolean rechazado = false;
    Test.startTest();
    try {
      MonitorControlador.abrirIntervencion(estado.Id, null);
    } catch (AuraHandledException e) {
      rechazado = true;
    }
    Test.stopTest();

    Assert.isTrue(rechazado, 'Normal y con comunicacion no abre caso');
    Assert.areEqual(0, [SELECT COUNT() FROM Case]);
    MonitorControlador.PanelDTO panel = MonitorControlador.obtenerPanel(null);
    Assert.isFalse(panel.filas[0].puedeIntervenir, 'Sin boton en fila normal');
  }

  @isTest
  static void shouldMostrarSoloSuCiudad_WhenOperadorBogota() {
    sembrarEstados();
    Edificio__c bogota = [
      SELECT Id
      FROM Edificio__c
      WHERE Codigo_Externo__c = :TestDataFactory.BLD_BOG
    ];
    Control_de_Ingesta__c control = [
      SELECT Id
      FROM Control_de_Ingesta__c
      LIMIT 1
    ];
    control.Ultima_Consulta_Exitosa__c = Datetime.now().addMinutes(-30);
    update control;

    User operador;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      operador = TestDataFactory.usuarioConConjunto('Nova_Casa_Operador');
    }
    // En la org la regla por ciudad comparte con un grupo; en prueba ese
    // recalculo no llega a tiempo, asi que se comparte directo.
    insert new Edificio__Share(
      ParentId = bogota.Id,
      UserOrGroupId = operador.Id,
      AccessLevel = 'Read',
      RowCause = Schema.Edificio__Share.RowCause.Manual
    );

    MonitorControlador.PanelDTO panel;
    Test.startTest();
    System.runAs(operador) {
      panel = MonitorControlador.obtenerPanel(null);
    }
    Test.stopTest();

    Assert.areEqual(1, panel.edificios.size(), 'Solo Alameda');
    Assert.areEqual(2, panel.filas.size(), 'Bomba y camara, sin Caribe');
    Assert.areEqual(0, panel.advertencias, 'La sala de Caribe no cuenta');
    for (MonitorControlador.FilaDTO fila : panel.filas) {
      Assert.areEqual('Edificio Nova Alameda', fila.edificio);
    }
    Assert.isTrue(panel.consultaAtrasada, 'El operador ve el aviso');
  }

  private static void sembrarEstados() {
    Activo__c bomba = [
      SELECT Id, Codigo_Externo__c
      FROM Activo__c
      WHERE Codigo_Externo__c = :TestDataFactory.AST_PUMP
    ];
    Activo__c camara = [
      SELECT Id, Codigo_Externo__c
      FROM Activo__c
      WHERE Codigo_Externo__c = :TestDataFactory.AST_CAM
    ];
    Activo__c sala = [
      SELECT Id, Codigo_Externo__c
      FROM Activo__c
      WHERE Codigo_Externo__c = :TestDataFactory.AST_TEMP
    ];
    insert new List<Estado_Actual__c>{
      new Estado_Actual__c(
        Activo__c = bomba.Id,
        Clave__c = bomba.Codigo_Externo__c + '|WATER_PRESSURE',
        Tipo_Medicion__c = 'WATER_PRESSURE',
        Valor__c = 0.8,
        Unidad__c = 'BAR',
        Severidad__c = IngestaConstantes.SEV_CRITICO,
        Severidad_Nivel__c = 2,
        Fecha_Origen__c = Datetime.now().addMinutes(-40)
      ),
      new Estado_Actual__c(
        Activo__c = sala.Id,
        Clave__c = sala.Codigo_Externo__c + '|TEMPERATURE',
        Tipo_Medicion__c = 'TEMPERATURE',
        Valor__c = 18.0,
        Unidad__c = 'CELSIUS',
        Severidad__c = IngestaConstantes.SEV_ADVERTENCIA,
        Severidad_Nivel__c = 1,
        Fecha_Origen__c = Datetime.now().addMinutes(-10)
      ),
      new Estado_Actual__c(
        Activo__c = camara.Id,
        Clave__c = camara.Codigo_Externo__c + '|CAMERA_CONNECTIVITY',
        Tipo_Medicion__c = 'CAMERA_CONNECTIVITY',
        Estado_Comunicacion__c = 'LOST',
        Episodio_Id__c = 'EP-PRUEBA-1',
        Gap_Segundos__c = 90,
        Sin_Comunicacion_Num__c = 1,
        Severidad__c = IngestaConstantes.SEV_NORMAL,
        Severidad_Nivel__c = 0,
        Fecha_Origen__c = Datetime.now().addMinutes(-5)
      )
    };
  }
}
