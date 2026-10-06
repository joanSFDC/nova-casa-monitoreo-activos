/**
 * Pruebas de una pagina: upsert, fechas, duplicados y eventos.
 */
@isTest
private class IngestaServicioTest {
  @TestSetup
  static void setup() {
    TestDataFactory.sembrarCatalogoMinimo();
  }

  @isTest
  static void shouldMarcarPendienteYPublicar_WhenMedicionValida() {
    String cuerpo = TestDataFactory.sobre(
      new List<Map<String, Object>>{ TestDataFactory.mensajePresion() },
      'cursor-2',
      true
    );
    Datetime ahora = Datetime.newInstanceGmt(2026, 9, 24, 15, 0, 0);

    Test.startTest();
    IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
      cuerpo,
      ahora
    );
    Senal__c publicada = [
      SELECT
        Resultado__c,
        Fecha_Origen__c,
        Fecha_Publicacion__c,
        Fecha_Recepcion__c,
        Fecha_Procesamiento__c,
        Clave__c,
        Entregas__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_000002'
    ];
    Assert.areEqual(
      IngestaConstantes.RESULTADO_PENDIENTE,
      publicada.Resultado__c,
      'Pendiente, no aplicado'
    );
    Assert.isNull(
      publicada.Fecha_Procesamiento__c,
      'Procesamiento lo llena el suscriptor'
    );
    Test.stopTest();

    Assert.areEqual(1, r.senales, 'Una senal');
    Assert.areEqual(1, r.publicadas, 'Un aviso');
    Senal__c senal = [
      SELECT
        Resultado__c,
        Fecha_Origen__c,
        Fecha_Publicacion__c,
        Fecha_Recepcion__c,
        Fecha_Procesamiento__c,
        Clave__c,
        Entregas__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_000002'
    ];
    Assert.areEqual(
      IngestaConstantes.RESULTADO_APLICADO,
      senal.Resultado__c,
      'El suscriptor aplica al entregar'
    );
    Assert.areEqual(ahora, senal.Fecha_Recepcion__c, 'Recepcion es ahora');
    Assert.isNotNull(senal.Fecha_Procesamiento__c, 'Ya no esta pendiente');
    Assert.areNotEqual(
      senal.Fecha_Origen__c,
      senal.Fecha_Publicacion__c,
      'Origen distinto de publicacion'
    );
    Assert.areNotEqual(
      senal.Fecha_Origen__c,
      senal.Fecha_Recepcion__c,
      'Origen distinto de recepcion'
    );
    Assert.areNotEqual(
      senal.Fecha_Publicacion__c,
      senal.Fecha_Recepcion__c,
      'Publicacion distinta de recepcion'
    );
    Assert.areEqual(
      senal.Clave__c,
      'nova-casa-simulator|msg_000002',
      'Misma clave publicada'
    );
  }

  @isTest
  static void shouldRechazarSinPublicar_WhenValorNulo() {
    String cuerpo = TestDataFactory.sobre(
      new List<Map<String, Object>>{ TestDataFactory.mensajeTemperaturaNula() },
      'c',
      false
    );
    Test.startTest();
    IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
      cuerpo,
      Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0)
    );
    Test.stopTest();
    Assert.areEqual(0, r.publicadas, 'Rechazado no se publica');
    Senal__c senal = [
      SELECT Resultado__c, Motivo__c, Reintentable__c, Carga__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_000001'
    ];
    Assert.areEqual(
      IngestaConstantes.RESULTADO_RECHAZADO,
      senal.Resultado__c,
      'Rechazado'
    );
    Assert.areEqual(
      IngestaConstantes.MOTIVO_VALOR,
      senal.Motivo__c,
      'Valor invalido'
    );
    Assert.isFalse(senal.Reintentable__c, 'El mensaje esta mal');
    Assert.isTrue(
      senal.Carga__c.contains('"value":null') ||
      senal.Carga__c.contains('"value": null'),
      'Conserva la carga'
    );
  }

  @isTest
  static void shouldNoTumbarPagina_WhenClavesRepetidas() {
    Map<String, Object> primero = TestDataFactory.mensajePresion();
    Map<String, Object> segundo = TestDataFactory.mensajePresion(
      'msg_000002',
      'dlv_000004',
      2.76,
      'BAR'
    );
    Map<String, Object> extra = TestDataFactory.mensajeCamara();
    String cuerpo = TestDataFactory.sobre(
      new List<Map<String, Object>>{ primero, segundo, extra },
      'c',
      true
    );
    Test.startTest();
    IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
      cuerpo,
      Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0)
    );
    Test.stopTest();
    Assert.areEqual(
      2,
      r.senales,
      'Dos claves distintas; el duplicado no inserta fila'
    );
    Assert.areEqual(2, r.publicadas, 'Presion y camara');
    Senal__c senal = [
      SELECT Entregas__c, Ultimo_Delivery_Id__c, Resultado__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_000002'
    ];
    Assert.areEqual(
      2,
      senal.Entregas__c.intValue(),
      'Dos entregas del mismo mensaje'
    );
    Assert.areEqual(
      'dlv_000004',
      senal.Ultimo_Delivery_Id__c,
      'Ultima entrega'
    );
    Assert.areNotEqual(
      IngestaConstantes.RESULTADO_DUPLICADO,
      senal.Resultado__c,
      'No pisa a Duplicado'
    );
  }

  @isTest
  static void shouldMarcarConflicto_WhenMismoIdDistintoValor() {
    Map<String, Object> a = TestDataFactory.mensajePresion(
      'msg_000014',
      'dlv_000014',
      19.7,
      'BAR'
    );
    Map<String, Object> b = TestDataFactory.mensajePresion(
      'msg_000014',
      'dlv_000016',
      60.19,
      'BAR'
    );
    String cuerpo = TestDataFactory.sobre(
      new List<Map<String, Object>>{ a, b },
      'c',
      false
    );
    Test.startTest();
    IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
      cuerpo,
      Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0)
    );
    Test.stopTest();
    Senal__c senal = [
      SELECT Resultado__c, Entregas__c, Carga__c, Detalle__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_000014'
    ];
    Assert.areEqual(
      IngestaConstantes.RESULTADO_CONFLICTO,
      senal.Resultado__c,
      'Conflicto'
    );
    Assert.areEqual(2, senal.Entregas__c.intValue(), 'Dos afirmaciones');
    Assert.areEqual(0, r.publicadas, 'Un conflicto no se publica');
    Assert.isTrue(
      senal.Carga__c.contains('dlv_000014'),
      'La carga es la de la primera afirmacion'
    );
    Assert.isTrue(
      senal.Detalle__c.contains('dlv_000016'),
      'El detalle senala la entrega que contradice'
    );
    Assert.isTrue(
      senal.Detalle__c.endsWith('la primera afirmaci\u00f3n.'),
      'Con tilde'
    );
  }

  @isTest
  static void shouldConservarPrimeraAfirmacion_WhenConflictoEnOtraPagina() {
    Datetime ahora = Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0);
    IngestaServicio.procesarPagina(
      TestDataFactory.sobre(
        new List<Map<String, Object>>{ TestDataFactory.mensajePresion() },
        'c1',
        true
      ),
      ahora
    );
    Test.getEventBus().deliver();
    Senal__c primera = [
      SELECT
        Resultado__c,
        Carga__c,
        Hash_Contenido__c,
        Fecha_Origen__c,
        Fecha_Procesamiento__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_000002'
    ];
    Assert.areEqual(
      IngestaConstantes.RESULTADO_APLICADO,
      primera.Resultado__c,
      'La primera afirmacion se aplico'
    );

    Test.startTest();
    IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
      TestDataFactory.sobre(
        new List<Map<String, Object>>{
          TestDataFactory.mensajePresion('msg_000002', 'dlv_000050', 3.9, 'BAR')
        },
        'c2',
        true
      ),
      ahora.addMinutes(2)
    );
    Test.stopTest();

    Senal__c despues = [
      SELECT
        Resultado__c,
        Carga__c,
        Hash_Contenido__c,
        Fecha_Origen__c,
        Fecha_Procesamiento__c,
        Entregas__c,
        Ultimo_Delivery_Id__c,
        Detalle__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_000002'
    ];
    Assert.areEqual(0, r.publicadas, 'Un conflicto no se publica');
    Assert.areEqual(
      IngestaConstantes.RESULTADO_CONFLICTO,
      despues.Resultado__c,
      'Dos afirmaciones distintas'
    );
    Assert.areEqual(
      primera.Carga__c,
      despues.Carga__c,
      'Conserva la carga de la primera'
    );
    Assert.areEqual(
      primera.Hash_Contenido__c,
      despues.Hash_Contenido__c,
      'Conserva su resumen'
    );
    Assert.areEqual(
      primera.Fecha_Origen__c,
      despues.Fecha_Origen__c,
      'Conserva su fecha de origen'
    );
    Assert.areEqual(
      primera.Fecha_Procesamiento__c,
      despues.Fecha_Procesamiento__c,
      'Conserva cuando se proceso'
    );
    Assert.areEqual(2, despues.Entregas__c.intValue(), 'Cuenta la entrega');
    Assert.areEqual(
      'dlv_000050',
      despues.Ultimo_Delivery_Id__c,
      'Ultima entrega'
    );
    Assert.isTrue(
      despues.Detalle__c.contains('dlv_000050'),
      'El detalle senala la entrega que contradice'
    );
  }

  @isTest
  static void shouldConservarProcesamiento_WhenReenvioIdenticoDeAplicada() {
    Datetime ahora = Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0);
    IngestaServicio.procesarPagina(
      TestDataFactory.sobre(
        new List<Map<String, Object>>{ TestDataFactory.mensajePresion() },
        'c1',
        true
      ),
      ahora
    );
    Test.getEventBus().deliver();
    Senal__c aplicada = [
      SELECT Resultado__c, Fecha_Procesamiento__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_000002'
    ];
    Assert.isNotNull(aplicada.Fecha_Procesamiento__c, 'Ya se proceso');

    Test.startTest();
    IngestaServicio.procesarPagina(
      TestDataFactory.sobre(
        new List<Map<String, Object>>{
          TestDataFactory.mensajePresion(
            'msg_000002',
            'dlv_000099',
            2.76,
            'BAR'
          )
        },
        'c2',
        true
      ),
      ahora.addMinutes(2)
    );
    Test.stopTest();

    Senal__c despues = [
      SELECT Resultado__c, Fecha_Procesamiento__c, Entregas__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_000002'
    ];
    Assert.areEqual(
      IngestaConstantes.RESULTADO_APLICADO,
      despues.Resultado__c,
      'Sigue aplicada'
    );
    Assert.areEqual(
      aplicada.Fecha_Procesamiento__c,
      despues.Fecha_Procesamiento__c,
      'El reenvio no borra la fecha de procesamiento'
    );
    Assert.areEqual(2, despues.Entregas__c.intValue(), 'Cuenta la entrega');
  }

  @isTest
  static void shouldGuardarRechazo_WhenTipoDeMensajeDesconocido() {
    Map<String, Object> alarma = TestDataFactory.mensajePresion();
    alarma.put('messageType', 'ALARM');
    Test.startTest();
    IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
      TestDataFactory.sobre(new List<Map<String, Object>>{ alarma }, 'c', true),
      Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0)
    );
    Test.stopTest();
    Assert.areEqual(0, r.publicadas, 'Un rechazo no se publica');
    Senal__c senal = [
      SELECT
        Resultado__c,
        Motivo__c,
        Reintentable__c,
        Tipo_Mensaje__c,
        Detalle__c,
        Carga__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_000002'
    ];
    Assert.areEqual(
      IngestaConstantes.RESULTADO_RECHAZADO,
      senal.Resultado__c,
      'Rechazado'
    );
    Assert.areEqual(
      IngestaConstantes.MOTIVO_TIPO_MENSAJE,
      senal.Motivo__c,
      'Tipo de mensaje desconocido'
    );
    Assert.isTrue(senal.Reintentable__c, 'Se resuelve ampliando el contrato');
    Assert.isNull(senal.Tipo_Mensaje__c, 'La lista no admite otros tipos');
    Assert.isTrue(senal.Detalle__c.contains('ALARM'), 'Dice que tipo llego');
    Assert.isTrue(senal.Carga__c.contains('ALARM'), 'Conserva la carga');
  }

  @isTest
  static void shouldRechazarSinBuscarPrevia_WhenFaltaMessageId() {
    Map<String, Object> sinId = TestDataFactory.mensajePresion();
    sinId.remove('messageId');
    Map<String, Object> buena = TestDataFactory.mensajePresion(
      'msg_000003',
      'dlv_000003',
      2.76,
      'BAR'
    );
    Test.startTest();
    IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
      TestDataFactory.sobre(
        new List<Map<String, Object>>{ sinId, buena },
        'c',
        true
      ),
      Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0)
    );
    Test.stopTest();

    Assert.areEqual(2, r.senales, 'Las dos se guardan');
    Assert.areEqual(1, r.publicadas, 'Solo la valida se publica');
    Senal__c huerfana = [
      SELECT
        Clave__c,
        Resultado__c,
        Motivo__c,
        Reintentable__c,
        Detalle__c,
        Carga__c
      FROM Senal__c
      WHERE Message_Id__c = NULL
    ];
    Assert.areEqual(
      IngestaConstantes.RESULTADO_RECHAZADO,
      huerfana.Resultado__c,
      'Rechazado'
    );
    Assert.areEqual(
      IngestaConstantes.MOTIVO_CAMPO,
      huerfana.Motivo__c,
      'Campo faltante'
    );
    Assert.isFalse(huerfana.Reintentable__c, 'El mensaje esta mal');
    Assert.areEqual(
      'Falta source o messageId',
      huerfana.Detalle__c,
      'Dice que falta'
    );
    Assert.isTrue(
      huerfana.Carga__c.contains('dlv_000002'),
      'Conserva la carga'
    );
    Assert.isTrue(
      IngestaServicio.esClaveSinId(huerfana.Clave__c),
      'La clave inventada no se busca entre las previas'
    );
    Assert.isFalse(
      IngestaServicio.esClaveSinId('nova-casa-simulator|msg_000003'),
      'Una clave real si se busca'
    );
  }

  @isTest
  static void shouldDejarRastroFallido_WhenLaSenalNoSePuedeGuardar() {
    Map<String, Object> enorme = TestDataFactory.mensajePresion();
    ((Map<String, Object>) enorme.get('building'))
      .put('name', 'x'.repeat(33000));
    Map<String, Object> buena = TestDataFactory.mensajePresion(
      'msg_000003',
      'dlv_000003',
      2.76,
      'BAR'
    );
    Test.startTest();
    IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
      TestDataFactory.sobre(
        new List<Map<String, Object>>{ enorme, buena },
        'c',
        true
      ),
      Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0)
    );
    Test.stopTest();
    Assert.areEqual(1, r.publicadas, 'La buena sigue su camino');
    Assert.isNull(r.errorGuardado, 'El rastro si entro');
    Senal__c rastro = [
      SELECT Resultado__c, Motivo__c, Reintentable__c, Detalle__c, Carga__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_000002'
    ];
    Assert.areEqual(
      IngestaConstantes.RESULTADO_FALLIDO,
      rastro.Resultado__c,
      'Fallo al escribir'
    );
    Assert.areEqual(
      IngestaConstantes.MOTIVO_SISTEMA,
      rastro.Motivo__c,
      'Error del sistema'
    );
    Assert.isTrue(rastro.Reintentable__c, 'Un reenvio lo vuelve a intentar');
    Assert.isTrue(String.isNotBlank(rastro.Detalle__c), 'Dice el error');
    Assert.isNull(rastro.Carga__c, 'El rastro va sin la carga que no cupo');
  }

  @isTest
  static void shouldIncrementarEntregas_WhenReenvioEnOtraPagina() {
    Datetime ahora = Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0);
    Datetime sesion = Datetime.newInstanceGmt(2026, 9, 22, 21, 51, 49);
    IngestaServicio.procesarPagina(
      TestDataFactory.sobre(
        new List<Map<String, Object>>{ TestDataFactory.mensajePresion() },
        'c1',
        true
      ),
      ahora,
      sesion
    );
    Map<String, Object> reenvio = TestDataFactory.mensajePresion(
      'msg_000002',
      'dlv_000099',
      2.76,
      'BAR'
    );
    Test.startTest();
    IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
      TestDataFactory.sobre(
        new List<Map<String, Object>>{ reenvio },
        'c2',
        true
      ),
      ahora.addMinutes(2),
      sesion
    );
    Test.stopTest();
    Assert.areEqual(0, r.publicadas, 'Reenvio no republica');
    Senal__c senal = [
      SELECT Entregas__c, Resultado__c, Fecha_Recepcion__c
      FROM Senal__c
      WHERE Message_Id__c = 'msg_000002'
    ];
    Assert.areEqual(2, senal.Entregas__c.intValue(), 'Contador');
    Assert.areNotEqual(
      IngestaConstantes.RESULTADO_DUPLICADO,
      senal.Resultado__c,
      'No cambia a Duplicado'
    );
    Assert.areEqual(
      ahora,
      senal.Fecha_Recepcion__c,
      'La primera recepcion se conserva'
    );
  }

  private static final Datetime PROCESADA_EN = Datetime.newInstanceGmt(
    2026,
    9,
    22,
    22,
    1,
    0
  );

  private class SuscriptorEntreLecturaYGuardado implements System.Callable {
    public Object call(String accion, Map<String, Object> argumentos) {
      Senal__c senal = [
        SELECT Id
        FROM Senal__c
        WHERE Clave__c = 'nova-casa-simulator|msg_000002'
      ];
      senal.Resultado__c = IngestaConstantes.RESULTADO_APLICADO;
      senal.Fecha_Procesamiento__c = PROCESADA_EN;
      update senal;
      return null;
    }
  }

  @isTest
  static void shouldConservarResultadoDelSuscriptor_WhenReenvioLlegaMientrasSeProcesa() {
    Datetime ahora = Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0);
    IngestaServicio.procesarPagina(
      TestDataFactory.sobre(
        new List<Map<String, Object>>{ TestDataFactory.mensajePresion() },
        'c1',
        true
      ),
      ahora
    );
    String cargaOriginal = [
      SELECT Carga__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_000002'
    ]
    .Carga__c;

    IngestaServicio.antesDeGuardar = new SuscriptorEntreLecturaYGuardado();
    IngestaServicio.procesarPagina(
      TestDataFactory.sobre(
        new List<Map<String, Object>>{
          TestDataFactory.mensajePresion(
            'msg_000002',
            'dlv_000099',
            2.76,
            'BAR'
          )
        },
        'c2',
        true
      ),
      ahora.addMinutes(2)
    );

    Senal__c despues = [
      SELECT
        Resultado__c,
        Fecha_Procesamiento__c,
        Entregas__c,
        Ultimo_Delivery_Id__c,
        Carga__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_000002'
    ];
    Assert.areEqual(
      IngestaConstantes.RESULTADO_APLICADO,
      despues.Resultado__c,
      'El reenvio no pisa lo que escribio el suscriptor'
    );
    Assert.areEqual(
      PROCESADA_EN,
      despues.Fecha_Procesamiento__c,
      'Ni su fecha de procesamiento'
    );
    Assert.areEqual(2, despues.Entregas__c.intValue(), 'Cuenta la entrega');
    Assert.areEqual(
      'dlv_000099',
      despues.Ultimo_Delivery_Id__c,
      'Ultima entrega'
    );
    Assert.areEqual(
      cargaOriginal,
      despues.Carga__c,
      'La carga es la de la primera entrega'
    );
  }

  @isTest
  static void shouldCrearOtraSenal_WhenMismoMessageIdEnSesionNueva() {
    Datetime ahora = Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0);
    Datetime sesionVieja = Datetime.newInstanceGmt(2026, 9, 22, 21, 51, 49);
    IngestaServicio.procesarPagina(
      TestDataFactory.sobre(
        new List<Map<String, Object>>{ TestDataFactory.mensajePresion() },
        'c1',
        true
      ),
      ahora,
      sesionVieja
    );
    Map<String, Object> otraSesion = TestDataFactory.mensajePresion(
      'msg_000002',
      'dlv_000002',
      3.10,
      'BAR'
    );
    otraSesion.put('occurredAt', '2026-09-30T21:52:27.806Z');
    otraSesion.put('publishedAt', '2026-09-30T21:52:29.498Z');
    Test.startTest();
    IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
      TestDataFactory.sobre(
        new List<Map<String, Object>>{ otraSesion },
        'c1',
        true
      ),
      ahora.addDays(8),
      sesionVieja.addDays(8)
    );
    Test.stopTest();
    Assert.areEqual(1, r.publicadas, 'La sesion nueva trae un mensaje nuevo');
    List<Senal__c> senales = [
      SELECT Clave__c, Resultado__c, Entregas__c
      FROM Senal__c
      WHERE Message_Id__c = 'msg_000002'
    ];
    Assert.areEqual(2, senales.size(), 'Una senal por sesion');
    for (Senal__c senal : senales) {
      Assert.areNotEqual(
        IngestaConstantes.RESULTADO_CONFLICTO,
        senal.Resultado__c,
        'No es una contradiccion: ' + senal.Clave__c
      );
      Assert.areEqual(
        1,
        senal.Entregas__c.intValue(),
        'Cada una con su entrega'
      );
    }
  }

  @isTest
  static void shouldGuardarTodos_WhenPaginaDeCincuenta() {
    List<Map<String, Object>> mensajes = new List<Map<String, Object>>();
    for (Integer i = 1; i <= 50; i++) {
      String n = String.valueOf(i).leftPad(6, '0');
      mensajes.add(
        TestDataFactory.mensajePresion('msg_' + n, 'dlv_' + n, 2.76, 'BAR')
      );
    }
    Test.startTest();
    IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
      TestDataFactory.sobre(mensajes, 'c', true),
      Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0)
    );
    Assert.areEqual(
      50,
      [
        SELECT COUNT()
        FROM Senal__c
        WHERE Resultado__c = :IngestaConstantes.RESULTADO_PENDIENTE
      ],
      'Tras publicar, todavia pendientes'
    );
    Test.stopTest();
    Assert.areEqual(50, r.senales, 'Cincuenta senales');
    Assert.areEqual(50, r.publicadas, 'Cincuenta avisos');
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM Senal__c
        WHERE Resultado__c = :IngestaConstantes.RESULTADO_PENDIENTE
      ],
      'El suscriptor drena la tanda'
    );
  }

  @isTest
  static void shouldRechazarPagina_WhenVersionDesconocida() {
    Map<String, Object> sobre = new Map<String, Object>{
      'schemaVersion' => '9.9',
      'data' => new List<Object>{ TestDataFactory.mensajePresion() },
      'pagination' => new Map<String, Object>{
        'nextCursor' => 'c',
        'hasMore' => true
      }
    };
    Test.startTest();
    IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
      JSON.serialize(sobre),
      Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0)
    );
    Test.stopTest();
    Assert.isTrue(r.versionRechazada, 'Version rechazada');
    Assert.areEqual(0, r.publicadas, 'Nada al bus');
    Senal__c senal = [SELECT Motivo__c, Resultado__c FROM Senal__c LIMIT 1];
    Assert.areEqual(
      IngestaConstantes.MOTIVO_VERSION,
      senal.Motivo__c,
      'Version no soportada'
    );
    Assert.areEqual(
      IngestaConstantes.RESULTADO_RECHAZADO,
      senal.Resultado__c,
      'Rechazado'
    );
  }

  @isTest
  static void shouldRechazarYSeguir_WhenActivoDesconocidoYValidoJuntos() {
    String cuerpo = TestDataFactory.sobre(
      new List<Map<String, Object>>{
        TestDataFactory.mensajeActivoDesconocido(),
        TestDataFactory.mensajePresion()
      },
      'c',
      true
    );
    Test.startTest();
    IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
      cuerpo,
      Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0)
    );
    Test.stopTest();
    Assert.areEqual(1, r.publicadas, 'Solo el valido se publica');
    Assert.areEqual(2, r.senales, 'Los dos se guardan');
  }

  @isTest
  static void shouldPasarAPendiente_WhenReintentoTrasAltaDeActivo() {
    Datetime ahora = Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0);
    Map<String, Object> mensaje = TestDataFactory.mensajeActivoDesconocido();
    IngestaServicio.procesarPagina(
      TestDataFactory.sobre(
        new List<Map<String, Object>>{ mensaje },
        'c1',
        true
      ),
      ahora
    );
    Senal__c antes = [
      SELECT Resultado__c, Motivo__c, Reintentable__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_unknown'
    ];
    Assert.areEqual(
      IngestaConstantes.RESULTADO_RECHAZADO,
      antes.Resultado__c,
      'Primera vez rechazado'
    );
    Assert.areEqual(
      IngestaConstantes.MOTIVO_ACTIVO,
      antes.Motivo__c,
      'Activo no encontrado'
    );
    Assert.isTrue(antes.Reintentable__c, 'Se puede reintentar');

    Edificio__c baq = [
      SELECT Id
      FROM Edificio__c
      WHERE Codigo_Externo__c = :TestDataFactory.BLD_BAQ
    ];
    insert new Activo__c(
      Name = 'Activo que faltaba',
      Codigo_Externo__c = 'AST-UNKNOWN-0001',
      Tipo__c = 'WATER_PUMP',
      Sensor_Id__c = 'SNS-UNKNOWN-0001',
      Edificio__c = baq.Id
    );

    Test.startTest();
    IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
      TestDataFactory.sobre(
        new List<Map<String, Object>>{ mensaje },
        'c2',
        true
      ),
      ahora.addMinutes(1)
    );
    Senal__c pendiente = [
      SELECT Resultado__c, Motivo__c, Reintentable__c, Activo__c, Entregas__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_unknown'
    ];
    Assert.areEqual(
      IngestaConstantes.RESULTADO_PENDIENTE,
      pendiente.Resultado__c,
      'El alta desbloquea'
    );
    Assert.isNull(pendiente.Motivo__c, 'Sin motivo');
    Assert.isFalse(pendiente.Reintentable__c, 'Pendiente no se reintenta');
    Test.stopTest();

    Senal__c despues = [
      SELECT Resultado__c, Motivo__c, Reintentable__c, Activo__c, Entregas__c
      FROM Senal__c
      WHERE Clave__c = 'nova-casa-simulator|msg_unknown'
    ];
    Assert.areEqual(
      IngestaConstantes.RESULTADO_APLICADO,
      despues.Resultado__c,
      'El aviso se aplica'
    );
    Assert.isNotNull(despues.Activo__c, 'Resuelve el activo');
    Assert.areEqual(2, despues.Entregas__c.intValue(), 'Cuenta el reenvio');
    Assert.areEqual(1, r.publicadas, 'Publica al quedar pendiente');
  }
}
