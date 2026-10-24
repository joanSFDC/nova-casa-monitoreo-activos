/**
 * La limpieza borra lo que toca, cuenta lo que borra en el resumen y respeta lo
 * ligado a casos y lo reciente; con la ingesta caida o atrasada no borra nada.
 */
@isTest
private class BitacoraRetencionBatchTest {
  @TestSetup
  static void preparar() {
    TestDataFactory.sembrarCatalogoMinimo();
    TestDataFactory.crearControl(true);
  }

  @isTest
  static void shouldBorrarYResumir_WhenVencieronSusDias() {
    Activo__c bomba = bomba();
    Case caso = new Case(Subject = 'Caso de prueba', Activo__c = bomba.Id);
    insert caso;
    Datetime ahora = Datetime.now();
    List<Senal__c> senales = new List<Senal__c>{
      senal(
        bomba,
        'aplicada-vieja-1',
        IngestaConstantes.RESULTADO_APLICADO,
        null
      ),
      senal(
        bomba,
        'aplicada-vieja-2',
        IngestaConstantes.RESULTADO_APLICADO,
        null
      ),
      senal(
        bomba,
        'atrasada-vieja',
        IngestaConstantes.RESULTADO_ATRASADO,
        null
      ),
      senal(
        bomba,
        'aplicada-reciente',
        IngestaConstantes.RESULTADO_APLICADO,
        null
      ),
      senal(
        bomba,
        'rechazada-de-un-mes',
        IngestaConstantes.RESULTADO_RECHAZADO,
        null
      ),
      senal(
        bomba,
        'rechazada-vieja',
        IngestaConstantes.RESULTADO_RECHAZADO,
        null
      ),
      senal(
        bomba,
        'ligada-vieja',
        IngestaConstantes.RESULTADO_APLICADO,
        caso.Id
      ),
      senal(
        bomba,
        'pendiente-vieja',
        IngestaConstantes.RESULTADO_PENDIENTE,
        null
      )
    };
    senales[5].Motivo__c = IngestaConstantes.MOTIVO_UNIDAD;
    insert senales;
    Map<String, Integer> dias = new Map<String, Integer>{
      'aplicada-vieja-1' => 8,
      'aplicada-vieja-2' => 8,
      'atrasada-vieja' => 8,
      'aplicada-reciente' => 2,
      'rechazada-de-un-mes' => 30,
      'rechazada-vieja' => 91,
      'ligada-vieja' => 40,
      'pendiente-vieja' => 40
    };
    for (Senal__c s : senales) {
      Test.setCreatedDate(s.Id, ahora.addDays(-dias.get(s.Message_Id__c)));
    }

    Test.startTest();
    Database.executeBatch(new BitacoraRetencionBatch(ahora), 2000);
    Test.stopTest();

    Set<String> quedan = new Set<String>();
    for (Senal__c s : [SELECT Message_Id__c FROM Senal__c]) {
      quedan.add(s.Message_Id__c);
    }
    Assert.areEqual(
      new Set<String>{
        'aplicada-reciente',
        'rechazada-de-un-mes',
        'ligada-vieja',
        'pendiente-vieja'
      },
      quedan,
      'Quedan lo reciente, lo ligado a un caso y lo pendiente'
    );
    Map<String, Decimal> conteo = new Map<String, Decimal>();
    for (Resumen_Bitacora__c fila : [
      SELECT Resultado__c, Motivo__c, Cantidad__c, Activo__c
      FROM Resumen_Bitacora__c
    ]) {
      Assert.areEqual(bomba.Id, fila.Activo__c, 'Por equipo');
      conteo.put(fila.Resultado__c + '|' + fila.Motivo__c, fila.Cantidad__c);
    }
    Assert.areEqual(
      2,
      conteo.get('Aplicado|null'),
      'Dos aplicadas del mismo dia'
    );
    Assert.areEqual(1, conteo.get('Atrasado|null'));
    Assert.areEqual(
      1,
      conteo.get('Rechazado|' + IngestaConstantes.MOTIVO_UNIDAD),
      'Con su motivo'
    );
  }

  @isTest
  static void shouldSumarAlResumen_WhenYaHabiaUnaFila() {
    Activo__c bomba = bomba();
    Datetime ahora = Datetime.now();
    Senal__c vieja = senal(
      bomba,
      'aplicada-vieja',
      IngestaConstantes.RESULTADO_APLICADO,
      null
    );
    insert vieja;
    Datetime creada = ahora.addDays(-10);
    Test.setCreatedDate(vieja.Id, creada);
    Date dia = creada.addHours(-5).dateGmt();
    insert new Resumen_Bitacora__c(
      Clave__c = String.valueOf(dia) + '|' + bomba.Id + '|Aplicado|-',
      Fecha__c = dia,
      Activo__c = bomba.Id,
      Resultado__c = IngestaConstantes.RESULTADO_APLICADO,
      Cantidad__c = 5
    );

    Test.startTest();
    Database.executeBatch(new BitacoraRetencionBatch(ahora), 2000);
    Test.stopTest();

    Assert.areEqual(
      6,
      [SELECT Cantidad__c FROM Resumen_Bitacora__c].Cantidad__c,
      'Suma a la fila del dia'
    );
  }

  @isTest
  static void shouldNoBorrar_WhenLaIngestaEstaCaida() {
    Activo__c bomba = bomba();
    Senal__c vieja = senal(
      bomba,
      'aplicada-vieja',
      IngestaConstantes.RESULTADO_APLICADO,
      null
    );
    insert vieja;
    Test.setCreatedDate(vieja.Id, Datetime.now().addDays(-10));
    Control_de_Ingesta__c control = [
      SELECT Id
      FROM Control_de_Ingesta__c
      LIMIT 1
    ];
    control.Caida_Desde__c = Datetime.now();
    update control;

    Test.startTest();
    Database.executeBatch(new BitacoraRetencionBatch(), 2000);
    Test.stopTest();

    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Senal__c],
      'No borra con la ingesta caida'
    );
    Assert.areEqual(0, [SELECT COUNT() FROM Resumen_Bitacora__c]);
  }

  @isTest
  static void shouldNoBorrar_WhenHayMuchasPendientes() {
    Activo__c bomba = bomba();
    BitacoraRetencionBatch.maximoPendientes = 1;
    Senal__c vieja = senal(
      bomba,
      'aplicada-vieja',
      IngestaConstantes.RESULTADO_APLICADO,
      null
    );
    insert new List<Senal__c>{
      vieja,
      senal(bomba, 'pendiente-1', IngestaConstantes.RESULTADO_PENDIENTE, null),
      senal(bomba, 'pendiente-2', IngestaConstantes.RESULTADO_PENDIENTE, null)
    };
    Test.setCreatedDate(vieja.Id, Datetime.now().addDays(-10));

    Assert.isTrue(
      BitacoraRetencionBatch.ingestaAtrasada(),
      'Mas pendientes que el maximo'
    );
    Test.startTest();
    Database.executeBatch(new BitacoraRetencionBatch(), 2000);
    Test.stopTest();

    Assert.areEqual(
      3,
      [SELECT COUNT() FROM Senal__c],
      'Espera a la noche siguiente'
    );
  }

  @isTest
  static void shouldProgramarALasDos_WhenSeProgramaYSeQuita() {
    Test.startTest();
    BitacoraRetencionSchedulable.programar();
    Test.stopTest();

    CronTrigger trabajo = [
      SELECT CronExpression
      FROM CronTrigger
      WHERE CronJobDetail.Name = :BitacoraRetencionSchedulable.NOMBRE_JOB
    ];
    Assert.areEqual('0 0 2 * * ?', trabajo.CronExpression);
    BitacoraRetencionSchedulable.abortar();
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE CronJobDetail.Name = :BitacoraRetencionSchedulable.NOMBRE_JOB
      ]
    );
  }

  @isTest
  static void shouldLanzarLaLimpieza_WhenCorreElProgramador() {
    Test.startTest();
    new BitacoraRetencionSchedulable().execute(null);
    Test.stopTest();

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'BitacoraRetencionBatch'
      ],
      'Lanza el Batch'
    );
  }

  private static Activo__c bomba() {
    return [
      SELECT Id, Edificio__c
      FROM Activo__c
      WHERE Codigo_Externo__c = :TestDataFactory.AST_PUMP
    ];
  }

  private static Senal__c senal(
    Activo__c activo,
    String id,
    String resultado,
    Id casoId
  ) {
    return new Senal__c(
      Clave__c = 'prueba|' + id,
      Message_Id__c = id,
      Activo__c = activo.Id,
      Edificio__c = activo.Edificio__c,
      Tipo_Mensaje__c = IngestaConstantes.TIPO_MEDICION,
      Resultado__c = resultado,
      Incidente__c = casoId
    );
  }
}
