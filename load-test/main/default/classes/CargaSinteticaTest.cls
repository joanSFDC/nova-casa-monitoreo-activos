/**
 * El generador de la prueba de carga y su limpieza. Antes de gastar horas de
 * carga comprueba que lo fabricado pasa el validador real, que un reenvio y un
 * conflicto repiten el original y que la limpieza no toca lo que no es suyo.
 */
@isTest
private class CargaSinteticaTest {
  @TestSetup
  static void preparar() {
    TestDataFactory.sembrarCatalogoMinimo();
    insert new List<Umbral__c>{
      new Umbral__c(
        Clave__c = 'WATER_METER|WATER_CONSUMPTION',
        Tipo_Activo__c = 'WATER_METER',
        Tipo_Medicion__c = 'WATER_CONSUMPTION',
        Unidad__c = 'LITER_PER_15_MIN',
        Advertencia_Alto__c = 401,
        Critico_Alto__c = 651,
        Decimales__c = 0,
        Vigente__c = true
      ),
      new Umbral__c(
        Clave__c = 'ENERGY_METER|ENERGY_CONSUMPTION',
        Tipo_Activo__c = 'ENERGY_METER',
        Tipo_Medicion__c = 'ENERGY_CONSUMPTION',
        Unidad__c = 'KWH_PER_15_MIN',
        Advertencia_Alto__c = 40.1,
        Critico_Alto__c = 65.1,
        Decimales__c = 1,
        Vigente__c = true
      )
    };
    CargaSinteticaBatch.preparar();
  }

  @isTest
  static void shouldPasarElValidador_WhenNoEsUnRechazo() {
    IngestaValidador.Catalogo catalogo = IngestaValidador.cargarCatalogo();
    Map<String, Umbral__c> umbrales = umbralesVigentes();
    Integer rechazos = 0;

    for (Long n = 0; n < 400; n++) {
      IngestaValidador.Dictamen dictamen = IngestaValidador.validar(
        CargaSinteticaBatch.mensaje(n, umbrales),
        catalogo
      );
      if (
        CargaSinteticaBatch.categoria(n) ==
        CargaSinteticaBatch.Categoria.RECHAZADO
      ) {
        Assert.isFalse(dictamen.esValido(), 'El rechazo ' + n + ' pasa');
        rechazos++;
      } else {
        Assert.isTrue(
          dictamen.esValido(),
          'El mensaje ' + n + ' no pasa: ' + dictamen.motivo
        );
      }
    }
    Assert.isTrue(rechazos > 0, 'Hay rechazos en los primeros 400');
  }

  @isTest
  static void shouldRepetirElOriginal_WhenEsReenvioOConflicto() {
    Map<String, Umbral__c> umbrales = umbralesVigentes();
    Long reenvio;
    Long conflicto;
    for (Long n = 2000; reenvio == null || conflicto == null; n++) {
      CargaSinteticaBatch.Categoria c = CargaSinteticaBatch.categoria(n);
      if (c == CargaSinteticaBatch.Categoria.DUPLICADO && reenvio == null) {
        reenvio = n;
      }
      if (c == CargaSinteticaBatch.Categoria.CONFLICTO && conflicto == null) {
        conflicto = n;
      }
    }

    Map<String, Object> repetido = CargaSinteticaBatch.mensaje(
      reenvio,
      umbrales
    );
    Map<String, Object> primero = CargaSinteticaBatch.mensaje(
      CargaSinteticaBatch.original(reenvio),
      umbrales
    );
    Assert.areEqual(primero.get('messageId'), repetido.get('messageId'));
    Assert.areNotEqual(primero.get('deliveryId'), repetido.get('deliveryId'));
    Assert.areEqual(
      IngestaValidador.hashDe(primero),
      IngestaValidador.hashDe(repetido),
      'Un reenvio trae el mismo contenido'
    );

    Map<String, Object> contradice = CargaSinteticaBatch.mensaje(
      conflicto,
      umbrales
    );
    Map<String, Object> afirmado = CargaSinteticaBatch.mensaje(
      CargaSinteticaBatch.original(conflicto),
      umbrales
    );
    Assert.areEqual(afirmado.get('messageId'), contradice.get('messageId'));
    Assert.areEqual(afirmado.get('occurredAt'), contradice.get('occurredAt'));
    Assert.areNotEqual(
      IngestaValidador.hashDe(afirmado),
      IngestaValidador.hashDe(contradice),
      'Un conflicto cambia el valor del mismo hecho'
    );
  }

  @isTest
  static void shouldSeguirLaMezclaReal_WhenSeCuentanLasCategorias() {
    Integer rechazos = 0;
    Integer conflictos = 0;
    Integer reenvios = 0;
    Integer total = 20000;
    for (Long n = 2000; n < 2000 + total; n++) {
      CargaSinteticaBatch.Categoria c = CargaSinteticaBatch.categoria(n);
      if (c == CargaSinteticaBatch.Categoria.RECHAZADO) {
        rechazos++;
      } else if (c == CargaSinteticaBatch.Categoria.CONFLICTO) {
        conflictos++;
      } else if (c == CargaSinteticaBatch.Categoria.DUPLICADO) {
        reenvios++;
      }
    }
    Assert.areEqual(520, rechazos, '2,6 %');
    Assert.areEqual(120, conflictos, '0,6 %');
    Assert.areEqual(200, reenvios, '1 %');
  }

  @isTest
  static void shouldGuardarLaMetaYNoProgramarOtroCiclo_WhenCorreUnaPagina() {
    Test.startTest();
    CargaSinteticaBatch.lanzar(0, 0, CargaSinteticaBatch.POR_PAGINA, 200000);
    Test.stopTest();

    String prefijo = CargaSinteticaBatch.prefijoClave() + '%';
    Assert.areEqual(
      CargaSinteticaBatch.POR_PAGINA,
      [SELECT COUNT() FROM Senal__c WHERE Clave__c LIKE :prefijo],
      'Una fila por mensaje antes del 2.000'
    );
    String nombres = CargaSinteticaBatch.TRABAJO + '%';
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE :nombres],
      'Con la meta cumplida no programa otro ciclo'
    );
  }

  @isTest
  static void shouldEsperarLoQueFaltaParaElRitmo_WhenVaAdelantado() {
    CargaSinteticaBatch carga = new CargaSinteticaBatch(0, 0, 1000000, 200000);
    carga.filas = 10000;

    Assert.areEqual(
      3,
      carga.esperaMinutos(),
      '10.000 filas a 200.000 por hora son 3 minutos'
    );
  }

  @isTest
  static void shouldBorrarSoloLoDeLaCarga_WhenSeLimpia() {
    Activo__c equipo = [
      SELECT Id
      FROM Activo__c
      WHERE Codigo_Externo__c = 'AST-CARGA-PUMP-001'
    ];
    String aplicado = IngestaConstantes.RESULTADO_APLICADO;
    insert new List<Senal__c>{
      new Senal__c(
        Clave__c = CargaSinteticaBatch.prefijoClave() + '000000001',
        Resultado__c = aplicado
      ),
      new Senal__c(
        Clave__c = 'rastro-carga',
        Activo__c = equipo.Id,
        Resultado__c = aplicado
      ),
      new Senal__c(
        Clave__c = 'nova-casa-simulator|msg_real',
        Resultado__c = aplicado
      )
    };
    insert new Case(Subject = 'Incidente de carga', Activo__c = equipo.Id);

    Test.startTest();
    CargaSinteticaLimpiezaBatch.lanzar();
    Test.stopTest();

    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Senal__c],
      'Solo queda la senal real'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Case WHERE Subject = 'Incidente de carga']
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM Edificio__c
        WHERE Codigo_Externo__c = :CargaSinteticaBatch.EDIFICIO
      ]
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM Activo__c
        WHERE Codigo_Externo__c LIKE 'AST-CARGA-%'
      ],
      'Los equipos caen con el edificio'
    );
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM Edificio__c],
      'Los edificios reales siguen'
    );
  }

  private static Map<String, Umbral__c> umbralesVigentes() {
    Map<String, Umbral__c> umbrales = new Map<String, Umbral__c>();
    for (Umbral__c umbral : [
      SELECT
        Clave__c,
        Unidad__c,
        Advertencia_Bajo__c,
        Advertencia_Alto__c,
        Critico_Alto__c,
        Minutos_Advertencia__c,
        Minutos_Critico__c
      FROM Umbral__c
      WHERE Vigente__c = TRUE
    ]) {
      umbrales.put(umbral.Clave__c, umbral);
    }
    return umbrales;
  }
}
