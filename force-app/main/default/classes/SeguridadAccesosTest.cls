/**
 * US-208: cada prueba corre como una persona con un solo conjunto de permisos
 * y afirma un resultado concreto: filas, campos, excepciones o registros que no
 * se crearon. Dos filas de la matriz ya tenian prueba y siguen donde estaban:
 * MonitorControladorTest.shouldMostrarSoloSuCiudad_WhenOperadorBogota y
 * TrazabilidadTest.shouldOcultarBitacora_WhenOperador.
 */
@isTest
private class SeguridadAccesosTest {
  private static final String CLAVE_BOMBA =
    TestDataFactory.AST_PUMP + '|WATER_PRESSURE';
  private static final String CLAVE_SALA =
    TestDataFactory.AST_TEMP + '|TEMPERATURE';
  private static final String CLAVE_UMBRAL_PRESION = 'WATER_PUMP|WATER_PRESSURE';

  @TestSetup
  static void setup() {
    TestDataFactory.sembrarCatalogoMinimo();
    TestDataFactory.crearControl(true);
    Activo__c bomba = activo(TestDataFactory.AST_PUMP);
    Activo__c sala = activo(TestDataFactory.AST_TEMP);
    insert new List<Estado_Actual__c>{
      new Estado_Actual__c(
        Activo__c = bomba.Id,
        Clave__c = CLAVE_BOMBA,
        Tipo_Medicion__c = 'WATER_PRESSURE',
        Valor__c = 4.5,
        Unidad__c = 'BAR',
        Severidad__c = IngestaConstantes.SEV_NORMAL,
        Severidad_Nivel__c = 0,
        Fecha_Origen__c = Datetime.now().addMinutes(-20)
      ),
      new Estado_Actual__c(
        Activo__c = sala.Id,
        Clave__c = CLAVE_SALA,
        Tipo_Medicion__c = 'TEMPERATURE',
        Valor__c = 31.3,
        Unidad__c = 'CELSIUS',
        Severidad__c = IngestaConstantes.SEV_ADVERTENCIA,
        Severidad_Nivel__c = 1,
        Fecha_Origen__c = Datetime.now().addMinutes(-10)
      )
    };
    insert new Case(
      Subject = 'Lectura fuera de rango ' + CLAVE_SALA,
      Description = 'Nota interna de Caribe',
      Status = 'New',
      Origin = 'Web',
      Priority = 'Low',
      Activo__c = sala.Id,
      Tipo_Medicion__c = 'TEMPERATURE',
      Clave_Abierta__c = CLAVE_SALA
    );
  }

  @isTest
  static void shouldDevolverVacio_WhenOperadorPideOtroEdificio() {
    User operador = operadorDeAlameda();
    Edificio__c caribe = edificio(TestDataFactory.BLD_BAQ);

    MonitorControlador.PanelDTO panel;
    Test.startTest();
    System.runAs(operador) {
      panel = MonitorControlador.obtenerPanel(caribe.Id);
    }
    Test.stopTest();

    Assert.areEqual(0, panel.filas.size(), 'Pedir Caribe no trae sus filas');
    Assert.isTrue(
      panel.sinLecturas,
      'Vacio, no un error que delate el edificio'
    );
    Assert.areEqual(
      0,
      panel.criticos + panel.advertencias + panel.normales,
      'Los contadores no cuentan Caribe'
    );
    Assert.areEqual(1, panel.edificios.size(), 'Solo le ofrece Alameda');
    Assert.areNotEqual(caribe.Id, panel.edificios[0].id, 'Y no es Caribe');
  }

  @isTest
  static void shouldDejarLaNota_WhenOperadorIntervieneEnSuCiudad() {
    User operador = operadorDeAlameda();
    Estado_Actual__c bomba = estado(CLAVE_BOMBA);
    bomba.Severidad__c = IngestaConstantes.SEV_ADVERTENCIA;
    bomba.Severidad_Nivel__c = 1;
    update bomba;

    Id casoId;
    Test.startTest();
    System.runAs(operador) {
      casoId = MonitorControlador.abrirIntervencion(
        bomba.Id,
        'Revisar la bomba'
      );
    }
    Test.stopTest();

    List<Task> tareas = [
      SELECT Description, CreatedById
      FROM Task
      WHERE WhatId = :casoId
    ];
    Assert.areEqual(1, tareas.size(), 'El operador deja su nota en el caso');
    Assert.areEqual('Revisar la bomba', tareas[0].Description);
    Assert.areEqual(operador.Id, tareas[0].CreatedById, 'Y queda a su nombre');
  }

  @isTest
  static void shouldNoEditarNotaAjena_WhenOperador() {
    User operador = operadorDeAlameda();
    Case incidente = new Case(
      Subject = 'Lectura fuera de rango ' + CLAVE_BOMBA,
      Status = 'New',
      Origin = 'Web',
      Priority = 'Low',
      Activo__c = activo(TestDataFactory.AST_PUMP).Id,
      Tipo_Medicion__c = 'WATER_PRESSURE',
      Clave_Abierta__c = CLAVE_BOMBA
    );
    insert incidente;
    Task ajena = new Task(
      WhatId = incidente.Id,
      Subject = 'Nota del operador',
      Description = 'Nota del coordinador',
      Status = 'Completed'
    );
    insert ajena;

    Database.SaveResult resultado;
    Test.startTest();
    System.runAs(operador) {
      resultado = Database.update(
        new Task(Id = ajena.Id, Description = 'Cambiada'),
        false,
        AccessLevel.USER_MODE
      );
    }
    Test.stopTest();

    Assert.isFalse(resultado.isSuccess(), 'Edit Tasks no le deja tocar notas de otros');
    Assert.areEqual(
      'Nota del coordinador',
      [SELECT Description FROM Task WHERE Id = :ajena.Id].Description
    );
  }

  @isTest
  static void shouldNegarCasoYEquipo_WhenOperadorLosPideDirectoAApex() {
    User operador = operadorDeAlameda();
    Case casoCaribe = [
      SELECT Id
      FROM Case
      WHERE Clave_Abierta__c = :CLAVE_SALA
    ];
    Estado_Actual__c salaCaribe = estado(CLAVE_SALA);

    Boolean incidenteNegado = false;
    Boolean intervencionNegada = false;
    Test.startTest();
    System.runAs(operador) {
      try {
        MonitorControlador.obtenerIncidente(casoCaribe.Id);
      } catch (AuraHandledException e) {
        incidenteNegado = true;
      }
      try {
        MonitorControlador.abrirIntervencion(salaCaribe.Id, 'Desde la consola');
      } catch (AuraHandledException e) {
        intervencionNegada = true;
      }
    }
    Test.stopTest();

    Assert.isTrue(
      incidenteNegado,
      'El caso de Caribe no se lee llamando a Apex'
    );
    Assert.isTrue(intervencionNegada, 'Ni se interviene un equipo de Caribe');
    Assert.areEqual(1, [SELECT COUNT() FROM Case], 'No se creo ningun caso');
    Assert.areEqual(0, [SELECT COUNT() FROM Task], 'Ni una nota');
  }

  @isTest
  static void shouldLeerSinEditarNiAplicar_WhenOperadorSobreUmbrales() {
    User operador = operadorDeAlameda();
    Umbral__c presion = umbral(CLAVE_UMBRAL_PRESION);

    Integer leidos;
    Boolean edicionBloqueada;
    Boolean aplicarBloqueado = false;
    Test.startTest();
    System.runAs(operador) {
      leidos = [SELECT Id FROM Umbral__c WITH USER_MODE].size();
      presion.Critico_Alto__c = 4.4;
      edicionBloqueada = !guardar(presion);
      try {
        UmbralAplicacionServicio.aplicar(peticion(presion.Id));
      } catch (UmbralAplicacionServicio.SinPermisoException e) {
        aplicarBloqueado = true;
      }
    }
    Test.stopTest();

    Assert.areEqual(3, leidos, 'Consulta los limites aplicados');
    Assert.isTrue(edicionBloqueada, 'No los modifica');
    Assert.isTrue(aplicarBloqueado, 'Ni dispara Aplicar limites');
    Assert.areEqual(
      5.01,
      umbral(CLAVE_UMBRAL_PRESION).Critico_Alto__c,
      'El umbral sigue igual'
    );
    Assert.areEqual(
      0,
      estado(CLAVE_BOMBA).Severidad_Nivel__c,
      'Y el estado tampoco cambia'
    );
  }

  @isTest
  static void shouldEditarYAplicar_WhenCoordinadorSobreUmbrales() {
    User coordinador;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      coordinador = TestDataFactory.usuarioConConjunto('Nova_Casa_Coordinador');
    }
    compartirEdificio(TestDataFactory.BLD_BOG, coordinador.Id);
    compartirEdificio(TestDataFactory.BLD_BAQ, coordinador.Id);
    Umbral__c presion = umbral(CLAVE_UMBRAL_PRESION);

    List<UmbralAplicacionServicio.Respuesta> respuestas;
    Test.startTest();
    System.runAs(coordinador) {
      presion.Critico_Alto__c = 4.4;
      Database.update(presion, AccessLevel.USER_MODE);
      respuestas = UmbralAplicacionServicio.aplicar(peticion(presion.Id));
    }
    Test.stopTest();

    Assert.areEqual(
      4.4,
      umbral(CLAVE_UMBRAL_PRESION).Critico_Alto__c,
      'Edita el limite'
    );
    Assert.areEqual(
      1,
      respuestas[0].estadosActualizados,
      'Lo aplica a la bomba'
    );
    Assert.areEqual(
      IngestaConstantes.SEV_CRITICO,
      estado(CLAVE_BOMBA).Severidad__c,
      '4,5 bar con el limite nuevo ya es critico'
    );
  }

  @isTest
  static void shouldVerTodaSinEditarNiBorrar_WhenAdministradorSobreBitacora() {
    insertarSenales();
    User administrador;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      administrador = TestDataFactory.usuarioConConjunto(
        'Nova_Casa_Administracion'
      );
    }

    List<Senal__c> vistas;
    Boolean edicionBloqueada;
    Boolean borradoBloqueado;
    Test.startTest();
    System.runAs(administrador) {
      vistas = [SELECT Id, Carga__c, Detalle__c FROM Senal__c WITH USER_MODE];
      Senal__c cambiada = new Senal__c(
        Id = vistas[0].Id,
        Detalle__c = 'Editado'
      );
      edicionBloqueada = !guardar(cambiada);
      borradoBloqueado = !borrar(new Senal__c(Id = vistas[0].Id));
    }
    Test.stopTest();

    Assert.areEqual(2, vistas.size(), 'Ve todas, aunque no sean suyas');
    Assert.isNotNull(vistas[0].Carga__c, 'Con la carga');
    Assert.isNotNull(vistas[0].Detalle__c, 'Y el detalle');
    Assert.isTrue(edicionBloqueada, 'La bitacora no se reescribe');
    Assert.isTrue(borradoBloqueado, 'Ni se borra');
    Assert.areEqual(2, [SELECT COUNT() FROM Senal__c], 'Siguen las dos');
  }

  @isTest
  static void shouldEditarControlAjeno_WhenAdministradorYNoCoordinador() {
    User administrador;
    User coordinador;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      administrador = TestDataFactory.usuarioConConjunto(
        'Nova_Casa_Administracion'
      );
      coordinador = TestDataFactory.usuarioConConjunto('Nova_Casa_Coordinador');
    }
    Id controlId = [SELECT Id FROM Control_de_Ingesta__c LIMIT 1].Id;

    Boolean administradorEdita;
    Boolean coordinadorEdita;
    Test.startTest();
    System.runAs(coordinador) {
      coordinadorEdita = guardar(
        new Control_de_Ingesta__c(Id = controlId, Tamano_Tanda__c = 10)
      );
    }
    System.runAs(administrador) {
      administradorEdita = guardar(
        new Control_de_Ingesta__c(Id = controlId, Tamano_Tanda__c = 25)
      );
    }
    Test.stopTest();

    Assert.isTrue(
      administradorEdita,
      'El control no es suyo y aun asi lo edita'
    );
    Assert.isFalse(coordinadorEdita, 'El coordinador solo lo lee');
    Assert.areEqual(
      25,
      [SELECT Tamano_Tanda__c FROM Control_de_Ingesta__c].Tamano_Tanda__c,
      'Queda el valor del administrador'
    );
  }

  @isTest
  static void shouldOmitirCargaYDetalle_WhenCoordinadorLeeBitacora() {
    insertarSenales();
    User coordinador;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      coordinador = TestDataFactory.usuarioConConjunto('Nova_Casa_Coordinador');
    }

    Integer filas;
    Boolean consultaRechazada = false;
    SObjectAccessDecision decision;
    Test.startTest();
    System.runAs(coordinador) {
      filas = [SELECT Id, Resultado__c FROM Senal__c WITH USER_MODE].size();
      try {
        List<Senal__c> conCarga = [
          SELECT Id, Carga__c
          FROM Senal__c
          WITH USER_MODE
        ];
      } catch (System.QueryException e) {
        consultaRechazada = true;
      } catch (System.SecurityException e) {
        consultaRechazada = true;
      }
      decision = Security.stripInaccessible(
        AccessType.READABLE,
        [
          SELECT Id, Resultado__c, Carga__c, Detalle__c
          FROM Senal__c
          WITH SYSTEM_MODE
        ]
      );
    }
    Test.stopTest();

    Assert.areEqual(2, filas, 'Lee la bitacora entera');
    Assert.isTrue(consultaRechazada, 'Pedir Carga__c en USER_MODE falla');
    Map<String, Object> campos = decision.getRecords()[0]
      .getPopulatedFieldsAsMap();
    Assert.isTrue(campos.containsKey('Resultado__c'), 'El resultado si llega');
    Assert.isFalse(campos.containsKey('Carga__c'), 'La carga no viene');
    Assert.isFalse(campos.containsKey('Detalle__c'), 'El detalle tampoco');
  }

  @isTest
  static void shouldProcesarYEscribir_WhenUsuarioDeIntegracion() {
    User integracion;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      integracion = TestDataFactory.usuarioDeIntegracion();
    }
    Map<String, Object> mensaje = TestDataFactory.mensajePresion(
      'msg_integ1',
      'dlv_integ1',
      5.5,
      'BAR'
    );
    String ahoraIso = Datetime.now()
      .addMinutes(-1)
      .formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
    mensaje.put('occurredAt', ahoraIso);
    mensaje.put('publishedAt', ahoraIso);
    String cuerpo = TestDataFactory.sobre(
      new List<Map<String, Object>>{ mensaje },
      'cur_integ',
      false
    );

    Test.startTest();
    System.runAs(integracion) {
      IngestaServicio.procesarPagina(cuerpo, Datetime.now());
      ProcesamientoServicio.procesar(
        new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(mensaje) }
      );
    }
    Test.stopTest();

    Senal__c senal = [
      SELECT Resultado__c, CreatedById
      FROM Senal__c
      WHERE Message_Id__c = 'msg_integ1'
    ];
    Assert.areEqual(
      integracion.Id,
      senal.CreatedById,
      'La ingesta escribe como integracion'
    );
    Assert.areEqual(
      IngestaConstantes.RESULTADO_APLICADO,
      senal.Resultado__c,
      'Y el procesamiento la aplica'
    );
    Assert.areEqual(
      IngestaConstantes.SEV_CRITICO,
      estado(CLAVE_BOMBA).Severidad__c,
      'El estado queda critico'
    );
    Case incidente = [
      SELECT OwnerId, Ciudad__c
      FROM Case
      WHERE Clave_Abierta__c = :CLAVE_BOMBA
    ];
    Assert.areEqual(
      integracion.Id,
      incidente.OwnerId,
      'El caso no es de ninguna persona'
    );
    Assert.areEqual(
      'Bogota',
      incidente.Ciudad__c,
      'Y lleva la ciudad para compartirse'
    );
  }

  @isTest
  static void shouldSellarCiudadDelActivo_WhenCasoSeGuardaOCambia() {
    Case caso = [
      SELECT Id, Ciudad__c
      FROM Case
      WHERE Clave_Abierta__c = :CLAVE_SALA
    ];
    Assert.areEqual(
      'Barranquilla',
      caso.Ciudad__c,
      'Sale del edificio del activo'
    );

    Test.startTest();
    caso.Activo__c = activo(TestDataFactory.AST_PUMP).Id;
    caso.Ciudad__c = 'Barranquilla';
    update caso;
    Case sinActivo = new Case(
      Subject = 'Sin equipo',
      Status = 'New',
      Origin = 'Web',
      Ciudad__c = 'Bogota'
    );
    insert sinActivo;
    Test.stopTest();

    Assert.areEqual(
      'Bogota',
      [SELECT Ciudad__c FROM Case WHERE Id = :caso.Id].Ciudad__c,
      'Sigue al activo, no a lo que se escriba'
    );
    Assert.isNull(
      [SELECT Ciudad__c FROM Case WHERE Id = :sinActivo.Id].Ciudad__c,
      'Sin activo no se comparte con ninguna ciudad'
    );
  }

  private static User operadorDeAlameda() {
    User operador;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      operador = TestDataFactory.usuarioConConjunto('Nova_Casa_Operador');
    }
    // En la org la regla por ciudad comparte con un grupo; en prueba ese
    // recalculo no llega a tiempo, asi que se comparte directo.
    compartirEdificio(TestDataFactory.BLD_BOG, operador.Id);
    return operador;
  }

  private static void compartirEdificio(String codigo, Id usuarioId) {
    insert new Edificio__Share(
      ParentId = edificio(codigo).Id,
      UserOrGroupId = usuarioId,
      AccessLevel = 'Read',
      RowCause = Schema.Edificio__Share.RowCause.Manual
    );
  }

  private static void insertarSenales() {
    Activo__c bomba = activo(TestDataFactory.AST_PUMP);
    List<Senal__c> senales = new List<Senal__c>();
    for (String n : new List<String>{ '1', '2' }) {
      Senal__c senal = TestDataFactory.senalPendiente(
        TestDataFactory.mensajePresion(
          'msg_seg' + n,
          'dlv_seg' + n,
          2.7,
          'BAR'
        ),
        bomba.Id,
        bomba.Edificio__c
      );
      senal.Detalle__c = 'Detalle interno ' + n;
      senales.add(senal);
    }
    insert senales;
  }

  private static Boolean guardar(SObject registro) {
    try {
      return Database.update(registro, false, AccessLevel.USER_MODE)
        .isSuccess();
    } catch (Exception e) {
      return false;
    }
  }

  private static Boolean borrar(SObject registro) {
    try {
      return Database.delete(registro, false, AccessLevel.USER_MODE)
        .isSuccess();
    } catch (Exception e) {
      return false;
    }
  }

  private static List<UmbralAplicacionServicio.Peticion> peticion(Id umbralId) {
    UmbralAplicacionServicio.Peticion peticion = new UmbralAplicacionServicio.Peticion();
    peticion.umbralId = umbralId;
    return new List<UmbralAplicacionServicio.Peticion>{ peticion };
  }

  private static Activo__c activo(String codigo) {
    return [
      SELECT Id, Edificio__c
      FROM Activo__c
      WHERE Codigo_Externo__c = :codigo
    ];
  }

  private static Edificio__c edificio(String codigo) {
    return [SELECT Id FROM Edificio__c WHERE Codigo_Externo__c = :codigo];
  }

  private static Umbral__c umbral(String clave) {
    return [SELECT Id, Critico_Alto__c FROM Umbral__c WHERE Clave__c = :clave];
  }

  private static Estado_Actual__c estado(String clave) {
    return [
      SELECT Id, Severidad__c, Severidad_Nivel__c
      FROM Estado_Actual__c
      WHERE Clave__c = :clave
    ];
  }
}
