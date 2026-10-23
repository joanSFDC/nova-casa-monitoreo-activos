/**
 * Lecturas del periodo: paginas de 50 por posicion sin repetir ni saltar filas,
 * aunque varias senales compartan el segundo; solo el equipo, el tipo de mensaje
 * y el periodo del caso; y un caso ajeno no se delata.
 */
@isTest
private class LecturasPeriodoControladorTest {
  private static final Datetime APERTURA = Datetime.now().addHours(-6);

  @TestSetup
  static void preparar() {
    TestDataFactory.sembrarCatalogoMinimo();
  }

  @isTest
  static void shouldRecorrerTodasSinRepetir_WhenHayEmpatesEnElBorde() {
    Activo__c bomba = bomba();
    Case caso = caso(bomba, APERTURA);
    List<Senal__c> senales = new List<Senal__c>();
    for (Integer i = 0; i < 120; i++) {
      senales.add(senal(bomba, 'k' + i, IngestaConstantes.TIPO_MEDICION));
    }
    insert senales;
    for (Integer i = 0; i < 120; i++) {
      Integer segundo = i < 48 ? i : (i < 53 ? 48 : i);
      Test.setCreatedDate(senales[i].Id, APERTURA.addSeconds(5000 - segundo));
    }

    Test.startTest();
    Set<Id> vistas = new Set<Id>();
    List<Integer> tamanos = new List<Integer>();
    Datetime anterior;
    Datetime hasta;
    List<Id> vistos = new List<Id>();
    Boolean hayMas = true;
    while (hayMas) {
      LecturasPeriodoControlador.PaginaDTO pagina = LecturasPeriodoControlador.pagina(
        caso.Id,
        hasta,
        vistos
      );
      tamanos.add(pagina.filas.size());
      for (LecturasPeriodoControlador.FilaDTO fila : pagina.filas) {
        Assert.isTrue(vistas.add(fila.id), 'Ninguna fila se repite');
        Assert.isTrue(
          anterior == null || fila.recibida <= anterior,
          'De la mas nueva a la mas vieja'
        );
        anterior = fila.recibida;
      }
      hayMas = pagina.hayMas;
      hasta = pagina.siguienteHasta;
      vistos = pagina.siguienteVistos;
    }
    Test.stopTest();

    Assert.areEqual(120, vistas.size(), 'Ninguna fila se salta');
    Assert.areEqual(new List<Integer>{ 50, 50, 20 }, tamanos, 'Paginas de 50');
  }

  @isTest
  static void shouldFiltrarPorEquipoTipoYPeriodo_WhenHayOtrasSenales() {
    Activo__c bomba = bomba();
    Activo__c camara = camara();
    Case caso = caso(bomba, APERTURA);
    Senal__c propia = senal(bomba, 'propia', IngestaConstantes.TIPO_MEDICION);
    propia.Lectura__c = '4,93 bar';
    propia.Resultado__c = IngestaConstantes.RESULTADO_ATRASADO;
    Senal__c vieja = senal(bomba, 'vieja', IngestaConstantes.TIPO_MEDICION);
    Senal__c otroTipo = senal(
      bomba,
      'otro-tipo',
      IngestaConstantes.TIPO_CONECTIVIDAD
    );
    Senal__c otroEquipo = senal(
      camara,
      'otro-equipo',
      IngestaConstantes.TIPO_MEDICION
    );
    Senal__c sinLectura = senal(
      bomba,
      'sin-lectura',
      IngestaConstantes.TIPO_MEDICION
    );
    sinLectura.Lectura__c = null;
    insert new List<Senal__c>{
      propia,
      vieja,
      otroTipo,
      otroEquipo,
      sinLectura
    };
    Test.setCreatedDate(propia.Id, APERTURA.addMinutes(10));
    Test.setCreatedDate(sinLectura.Id, APERTURA.addMinutes(5));
    Test.setCreatedDate(vieja.Id, APERTURA.addDays(-1));
    Test.setCreatedDate(otroTipo.Id, APERTURA.addMinutes(10));
    Test.setCreatedDate(otroEquipo.Id, APERTURA.addMinutes(10));

    Test.startTest();
    LecturasPeriodoControlador.PaginaDTO pagina = LecturasPeriodoControlador.pagina(
      caso.Id,
      null,
      null
    );
    Test.stopTest();

    Assert.areEqual(2, pagina.filas.size(), 'Solo las del periodo del equipo');
    Assert.areEqual(propia.Id, pagina.filas[0].id, 'La mas nueva primero');
    Assert.areEqual('4,93 bar', pagina.filas[0].lectura, 'La lectura guardada');
    Assert.areEqual(
      IngestaConstantes.RESULTADO_ATRASADO,
      pagina.filas[0].resultado,
      'El resultado de la senal'
    );
    Assert.isNotNull(pagina.filas[0].resultadoEtiqueta, 'Con su etiqueta');
    Assert.areEqual(
      LecturaFormato.SIN_VALOR,
      pagina.filas[1].lectura,
      'Una senal anterior al campo dice que no hay lectura'
    );
    Assert.isFalse(pagina.hayMas, 'No hay mas');
    Assert.isFalse(pagina.fueraDeVentana, 'El caso es de hoy');
  }

  @isTest
  static void shouldEmpezarEnLaSenalQueLoAbrio_WhenSeGuardoAntesQueElCaso() {
    Activo__c bomba = bomba();
    Senal__c origen = senal(bomba, 'origen', IngestaConstantes.TIPO_MEDICION);
    insert origen;
    Test.setCreatedDate(origen.Id, APERTURA.addSeconds(-20));
    Case caso = caso(bomba, APERTURA);
    caso.Origen_Senal__c = origen.Clave__c;
    update caso;

    LecturasPeriodoControlador.PaginaDTO pagina = LecturasPeriodoControlador.pagina(
      caso.Id,
      null,
      null
    );

    Assert.areEqual(1, pagina.filas.size(), 'La que lo abrio entra');
    Assert.areEqual(origen.Id, pagina.filas[0].id);
  }

  @isTest
  static void shouldAvisarLaVentana_WhenElCasoEsMasViejo() {
    Case caso = caso(bomba(), Datetime.now().addDays(-10));

    LecturasPeriodoControlador.PaginaDTO pagina = LecturasPeriodoControlador.pagina(
      caso.Id,
      null,
      null
    );

    Assert.isTrue(pagina.fueraDeVentana, 'Diez dias es mas que la ventana');
    Assert.areEqual(0, pagina.filas.size());
  }

  @isTest
  static void shouldRechazarLaPosicion_WhenTraeDemasiadosVistos() {
    Case caso = caso(bomba(), APERTURA);
    List<Id> vistos = new List<Id>();
    String prefijo = String.valueOf(caso.Id).left(12);
    for (Integer i = 0; i <= LecturasPeriodoControlador.TOPE_VISTOS; i++) {
      vistos.add(Id.valueOf(prefijo + String.valueOf(i).leftPad(3, '0')));
    }

    try {
      LecturasPeriodoControlador.pagina(caso.Id, Datetime.now(), vistos);
      Assert.fail('Debio rechazar la posicion');
    } catch (AuraHandledException error) {
      Assert.isNotNull(error.getMessage());
    }
  }

  @isTest
  static void shouldDevolverNull_WhenNoLeeLaBitacora() {
    User operador = TestDataFactory.usuarioConConjunto('Nova_Casa_Operador');
    Case caso;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      caso = caso(bomba(), APERTURA);
    }

    LecturasPeriodoControlador.PaginaDTO pagina;
    Test.startTest();
    System.runAs(operador) {
      pagina = LecturasPeriodoControlador.pagina(caso.Id, null, null);
    }
    Test.stopTest();

    Assert.isNull(pagina, 'Sin acceso a la bitacora no hay lecturas');
    Assert.isNull(
      LecturasPeriodoControlador.pagina(null, null, null),
      'Sin caso no hay pagina'
    );
  }

  @isTest
  static void shouldTraerLasLecturas_WhenLasPideElCoordinador() {
    User coordinador = TestDataFactory.usuarioConConjunto(
      'Nova_Casa_Coordinador'
    );
    Case caso;
    Senal__c propia;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Activo__c bomba = bomba();
      caso = caso(bomba, APERTURA);
      propia = senal(bomba, 'del-coordinador', IngestaConstantes.TIPO_MEDICION);
      insert propia;
      Test.setCreatedDate(propia.Id, APERTURA.addMinutes(1));
    }

    LecturasPeriodoControlador.PaginaDTO pagina;
    Test.startTest();
    System.runAs(coordinador) {
      pagina = LecturasPeriodoControlador.pagina(caso.Id, null, null);
    }
    Test.stopTest();

    Assert.isNotNull(pagina, 'El coordinador ve todos los casos');
    Assert.areEqual(1, pagina.filas.size(), 'Y sus lecturas');
    Assert.areEqual('4,50 bar', pagina.filas[0].lectura);
  }

  private static Case caso(Activo__c activo, Datetime creado) {
    Case caso = new Case(
      Subject = 'Lectura fuera de rango de prueba',
      Activo__c = activo.Id,
      Tipo_Medicion__c = 'WATER_PRESSURE'
    );
    insert caso;
    Test.setCreatedDate(caso.Id, creado);
    return caso;
  }

  private static Senal__c senal(Activo__c activo, String clave, String tipo) {
    return new Senal__c(
      Clave__c = 'prueba|' + clave,
      Message_Id__c = clave,
      Activo__c = activo.Id,
      Edificio__c = activo.Edificio__c,
      Tipo_Mensaje__c = tipo,
      Resultado__c = IngestaConstantes.RESULTADO_APLICADO,
      Lectura__c = '4,50 bar'
    );
  }

  private static Activo__c bomba() {
    return [
      SELECT Id, Edificio__c
      FROM Activo__c
      WHERE Codigo_Externo__c = :TestDataFactory.AST_PUMP
    ];
  }

  private static Activo__c camara() {
    return [
      SELECT Id, Edificio__c
      FROM Activo__c
      WHERE Codigo_Externo__c = :TestDataFactory.AST_CAM
    ];
  }
}
