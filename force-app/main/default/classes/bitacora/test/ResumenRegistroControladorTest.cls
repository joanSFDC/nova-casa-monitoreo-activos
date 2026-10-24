/**
 * Los resumenes de incidente, activo y edificio: lo que muestran y lo que no
 * le muestran a quien no ve el registro.
 */
@isTest
private class ResumenRegistroControladorTest {
  private static final String CLAVE_BOMBA =
    TestDataFactory.AST_PUMP + '|WATER_PRESSURE';
  private static final String CLAVE_SALA =
    TestDataFactory.AST_TEMP + '|TEMPERATURE';

  @TestSetup
  static void setup() {
    TestDataFactory.sembrarCatalogoMinimo();
    Activo__c bomba = activo(TestDataFactory.AST_PUMP);
    Activo__c camara = activo(TestDataFactory.AST_CAM);
    Activo__c sala = activo(TestDataFactory.AST_TEMP);
    insert new List<Estado_Actual__c>{
      new Estado_Actual__c(
        Activo__c = bomba.Id,
        Clave__c = CLAVE_BOMBA,
        Tipo_Medicion__c = 'WATER_PRESSURE',
        Valor__c = 3.8,
        Unidad__c = 'BAR',
        Severidad__c = IngestaConstantes.SEV_NORMAL,
        Severidad_Nivel__c = 0,
        Fecha_Origen__c = Datetime.now().addMinutes(-5)
      ),
      new Estado_Actual__c(
        Activo__c = camara.Id,
        Clave__c = TestDataFactory.AST_CAM + '|CAMERA_CONNECTIVITY',
        Tipo_Medicion__c = 'CAMERA_CONNECTIVITY',
        Estado_Comunicacion__c = 'LOST',
        Gap_Segundos__c = 900,
        Episodio_Id__c = 'EPI-1',
        Sin_Comunicacion_Num__c = 1,
        Severidad__c = IngestaConstantes.SEV_ADVERTENCIA,
        Severidad_Nivel__c = 1,
        Fecha_Origen__c = Datetime.now().addMinutes(-2)
      ),
      new Estado_Actual__c(
        Activo__c = sala.Id,
        Clave__c = CLAVE_SALA,
        Tipo_Medicion__c = 'TEMPERATURE',
        Valor__c = 36,
        Unidad__c = 'CELSIUS',
        Severidad__c = IngestaConstantes.SEV_CRITICO,
        Severidad_Nivel__c = 2,
        Fecha_Origen__c = Datetime.now().addMinutes(-1)
      )
    };
    insert new List<Case>{
      new Case(
        Subject = 'Lectura fuera de rango ' + CLAVE_BOMBA,
        Status = 'New',
        Origin = 'Web',
        Priority = 'High',
        Activo__c = bomba.Id,
        Tipo_Medicion__c = 'WATER_PRESSURE',
        Clave_Abierta__c = CLAVE_BOMBA,
        Lectura_Apertura__c = '5,50 bar',
        Severidad_Apertura__c = IngestaConstantes.SEV_CRITICO,
        Fecha_Lectura_Apertura__c = Datetime.newInstanceGmt(
          2026,
          10,
          16,
          10,
          0,
          0
        ),
        Ultima_Lectura__c = '3,80 bar',
        Severidad_Ultima_Lectura__c = IngestaConstantes.SEV_NORMAL,
        Fecha_Ultima_Lectura__c = Datetime.newInstanceGmt(
          2026,
          10,
          16,
          10,
          30,
          0
        ),
        Condicion_Equipo__c = IncidentesServicio.CONDICION_NORMALIZADO,
        Normalizado_En__c = Datetime.newInstanceGmt(2026, 10, 16, 10, 30, 0)
      ),
      new Case(
        Subject = 'Lectura fuera de rango ' + CLAVE_SALA,
        Status = 'New',
        Origin = 'Web',
        Priority = 'High',
        Activo__c = sala.Id,
        Tipo_Medicion__c = 'TEMPERATURE',
        Clave_Abierta__c = CLAVE_SALA,
        Condicion_Equipo__c = IncidentesServicio.CONDICION_EN_FALLA
      )
    };
  }

  @isTest
  static void shouldResumirIncidente_ConLasTresLecturas() {
    Case caso = caso(CLAVE_BOMBA);

    Test.startTest();
    ResumenRegistroControlador.IncidenteDTO dto = ResumenRegistroControlador.incidente(
      caso.Id
    );
    Test.stopTest();

    Assert.areEqual('5,50 bar', dto.apertura.texto, 'Lo que lo abrio');
    Assert.areEqual('Cr\u00edtico', dto.apertura.severidadEtiqueta);
    Assert.areEqual('3,80 bar', dto.ultima.texto, 'El ultimo cambio');
    Assert.areEqual('Normal', dto.ultima.severidadEtiqueta);
    Assert.areEqual(
      '3,80 bar',
      dto.ahora.lectura.replace('.', ','),
      'Y el estado actual, en vivo'
    );
    Assert.isTrue(dto.normalizado);
    Assert.isFalse(dto.cerrado);
    Assert.areEqual('Bomba de presion de agua', dto.equipo.nombre);
    Assert.areEqual('Bogota', dto.equipo.ciudad);
    Assert.areEqual('Presi\u00f3n de agua', dto.medicion);
  }

  @isTest
  static void shouldNoResumirIncidente_WhenOperadorDeOtraCiudad() {
    User operador = operadorDeAlameda();
    Case caribe = caso(CLAVE_SALA);

    ResumenRegistroControlador.IncidenteDTO dto;
    Test.startTest();
    System.runAs(operador) {
      dto = ResumenRegistroControlador.incidente(caribe.Id);
    }
    Test.stopTest();

    Assert.isNull(dto, 'Un caso de Caribe no se resume para Bogota');
  }

  @isTest
  static void shouldResumirActivo_ConMedicionesCasosYLimites() {
    Activo__c sala = activo(TestDataFactory.AST_TEMP);

    Test.startTest();
    ResumenRegistroControlador.ActivoDTO dto = ResumenRegistroControlador.activo(
      sala.Id
    );
    Test.stopTest();

    Assert.areEqual(IngestaConstantes.SEV_CRITICO, dto.severidad);
    Assert.areEqual('Sala t\u00e9cnica', dto.equipo.tipoEtiqueta);
    Assert.areEqual(1, dto.mediciones.size());
    Assert.areEqual(
      '36,0 \u00b0C',
      dto.mediciones[0].lectura.replace('.', ','),
      'Con el decimal que pide el umbral'
    );
    Assert.areEqual(1, dto.casos.size(), 'Su incidente abierto');
    Assert.areEqual('Alta', dto.casos[0].prioridad);
    Assert.isFalse(dto.casos[0].normalizado);
    Assert.areEqual(1, dto.limites.size(), 'El umbral de su tipo');
    Assert.areEqual(35.1, dto.limites[0].criticoAlto);
    Assert.areEqual('\u00b0C', dto.limites[0].unidad);
  }

  @isTest
  static void shouldResumirEdificio_ConConteosEquiposYCasos() {
    Edificio__c alameda = edificio(TestDataFactory.BLD_BOG);

    Test.startTest();
    ResumenRegistroControlador.EdificioDTO dto = ResumenRegistroControlador.edificio(
      alameda.Id
    );
    Test.stopTest();

    Assert.areEqual('Bogota', dto.ciudad);
    Assert.areEqual(0, dto.criticos);
    Assert.areEqual(1, dto.advertencias, 'La camara en corte');
    Assert.areEqual(1, dto.normales, 'La bomba');
    Assert.areEqual(1, dto.sinComunicacion);
    Assert.areEqual(2, dto.equipos.size());
    Assert.areEqual(
      'Sin comunicaci\u00f3n \u00b7 15 min',
      dto.equipos[0].lectura,
      'Lo peor primero: la camara'
    );
    Assert.areEqual(1, dto.casos.size(), 'El caso de la bomba');
    Assert.isTrue(dto.casos[0].normalizado);
    Assert.isTrue(
      dto.equipos[1].casoNormalizado,
      'La bomba volvio a lo normal con su caso abierto'
    );
  }

  @isTest
  static void shouldNoResumirEdificio_WhenOperadorNoLoVe() {
    User operador = operadorDeAlameda();
    Edificio__c caribe = edificio(TestDataFactory.BLD_BAQ);
    Activo__c sala = activo(TestDataFactory.AST_TEMP);

    ResumenRegistroControlador.EdificioDTO dto;
    ResumenRegistroControlador.ActivoDTO salaVista;
    Test.startTest();
    System.runAs(operador) {
      dto = ResumenRegistroControlador.edificio(caribe.Id);
      salaVista = ResumenRegistroControlador.activo(sala.Id);
    }
    Test.stopTest();

    Assert.isNull(dto, 'Caribe no existe para el operador de Bogota');
    Assert.isNull(salaVista, 'Ni sus equipos');
  }

  private static User operadorDeAlameda() {
    User operador;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      operador = TestDataFactory.usuarioConConjunto('Nova_Casa_Operador');
    }
    insert new Edificio__Share(
      ParentId = edificio(TestDataFactory.BLD_BOG).Id,
      UserOrGroupId = operador.Id,
      AccessLevel = 'Read',
      RowCause = Schema.Edificio__Share.RowCause.Manual
    );
    return operador;
  }

  private static Activo__c activo(String codigo) {
    return [SELECT Id FROM Activo__c WHERE Codigo_Externo__c = :codigo];
  }

  private static Edificio__c edificio(String codigo) {
    return [SELECT Id FROM Edificio__c WHERE Codigo_Externo__c = :codigo];
  }

  private static Case caso(String clave) {
    return [SELECT Id FROM Case WHERE Clave_Abierta__c = :clave];
  }
}
