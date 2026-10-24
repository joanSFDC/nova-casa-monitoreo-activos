/**
 * US-203: vigencia por occurredAt, desempate por messageId y perdedoras atrasadas.
 */
@isTest
private class EstadoActualTest {
  private static final String CLAVE_PRESION = 'AST-BOG-PUMP-001|WATER_PRESSURE';
  private static final String CLAVE_CONSUMO = 'AST-BOG-PUMP-001|WATER_CONSUMPTION';

  @TestSetup
  static void setup() {
    TestDataFactory.sembrarCatalogoMinimo();
  }

  @isTest
  static void shouldReemplazarEstado_WhenLecturaMasNueva() {
    Activo__c bomba = bomba();
    Map<String, Object> primera = presion(
      'msg_nueva_1',
      'dlv_nueva_1',
      2.76,
      '2026-09-22T22:50:18.000Z'
    );
    Map<String, Object> segunda = presion(
      'msg_nueva_2',
      'dlv_nueva_2',
      4.66,
      '2026-09-22T22:51:19.000Z'
    );
    insert new List<Senal__c>{
      TestDataFactory.senalPendiente(primera, bomba.Id, bomba.Edificio__c),
      TestDataFactory.senalPendiente(segunda, bomba.Id, bomba.Edificio__c)
    };

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{
        TestDataFactory.avisoDe(primera),
        TestDataFactory.avisoDe(segunda)
      }
    );
    Test.stopTest();

    Estado_Actual__c estado = [
      SELECT Valor__c, Fecha_Origen__c, Ultimo_Message_Id__c
      FROM Estado_Actual__c
      WHERE Clave__c = :CLAVE_PRESION
    ];
    Assert.areEqual(4.66, estado.Valor__c);
    Assert.areEqual('msg_nueva_2', estado.Ultimo_Message_Id__c);
    Assert.areEqual(
      Datetime.newInstanceGmt(2026, 9, 22, 22, 51, 19),
      estado.Fecha_Origen__c
    );
    Assert.areEqual(
      IngestaConstantes.RESULTADO_ATRASADO,
      resultadoDe('msg_nueva_1')
    );
    Assert.areEqual(
      IngestaConstantes.RESULTADO_APLICADO,
      resultadoDe('msg_nueva_2')
    );
  }

  @isTest
  static void shouldNoReemplazar_WhenLecturaAtrasada() {
    Activo__c bomba = bomba();
    insert new Estado_Actual__c(
      Activo__c = bomba.Id,
      Clave__c = CLAVE_PRESION,
      Tipo_Medicion__c = 'WATER_PRESSURE',
      Valor__c = 3.73,
      Unidad__c = 'BAR',
      Fecha_Origen__c = Datetime.newInstanceGmt(2026, 9, 22, 22, 51, 19),
      Ultimo_Message_Id__c = 'msg_000004',
      Severidad__c = IngestaConstantes.SEV_NORMAL,
      Severidad_Nivel__c = 0
    );
    Map<String, Object> atrasada = presion(
      'msg_000005',
      'dlv_000005',
      3.54,
      '2026-09-22T22:42:20.000Z'
    );
    insert TestDataFactory.senalPendiente(
      atrasada,
      bomba.Id,
      bomba.Edificio__c
    );

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(atrasada) }
    );
    Test.stopTest();

    Assert.areEqual(
      IngestaConstantes.RESULTADO_ATRASADO,
      resultadoDe('msg_000005')
    );
    Estado_Actual__c estado = [
      SELECT Valor__c, Ultimo_Message_Id__c
      FROM Estado_Actual__c
      WHERE Clave__c = :CLAVE_PRESION
    ];
    Assert.areEqual(3.73, estado.Valor__c);
    Assert.areEqual('msg_000004', estado.Ultimo_Message_Id__c);
  }

  @isTest
  static void shouldGanarOccurredAtMayor_WhenTandaDesordenada() {
    procesarTandaLateMessages();

    Estado_Actual__c estado = [
      SELECT Valor__c, Ultimo_Message_Id__c
      FROM Estado_Actual__c
      WHERE Clave__c = :CLAVE_PRESION
    ];
    Assert.areEqual(3.73, estado.Valor__c, 'Gana 22:51, no el 3.54 atrasado');
    Assert.areEqual('msg_000004', estado.Ultimo_Message_Id__c);
    Assert.areEqual(
      IngestaConstantes.RESULTADO_APLICADO,
      resultadoDe('msg_000004')
    );
    Assert.areEqual(
      IngestaConstantes.RESULTADO_ATRASADO,
      resultadoDe('msg_000003')
    );
    Assert.areEqual(
      IngestaConstantes.RESULTADO_ATRASADO,
      resultadoDe('msg_000005')
    );
  }

  @isTest
  static void shouldGanarMessageIdMayor_WhenEmpateDeFecha() {
    procesarEmpate(true);
    afirmarGanadorDelEmpate();
  }

  @isTest
  static void shouldMismoResultado_WhenEmpateAlReves() {
    procesarEmpate(false);
    afirmarGanadorDelEmpate();
  }

  @isTest
  static void shouldNoAbrirCaso_WhenCriticoAtrasado() {
    Activo__c bomba = bomba();
    insert new Estado_Actual__c(
      Activo__c = bomba.Id,
      Clave__c = CLAVE_PRESION,
      Tipo_Medicion__c = 'WATER_PRESSURE',
      Valor__c = 3.1,
      Unidad__c = 'BAR',
      Fecha_Origen__c = Datetime.newInstanceGmt(2026, 9, 22, 22, 51, 0),
      Ultimo_Message_Id__c = 'msg_vigente',
      Severidad__c = IngestaConstantes.SEV_NORMAL,
      Severidad_Nivel__c = 0
    );
    Map<String, Object> criticoViejo = presion(
      'msg_critico_viejo',
      'dlv_critico_viejo',
      0.8,
      '2026-09-22T22:31:00.000Z'
    );
    insert TestDataFactory.senalPendiente(
      criticoViejo,
      bomba.Id,
      bomba.Edificio__c
    );
    Integer casosAntes = [SELECT COUNT() FROM Case];

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(criticoViejo) }
    );
    Test.stopTest();

    Assert.areEqual(
      IngestaConstantes.RESULTADO_ATRASADO,
      resultadoDe('msg_critico_viejo')
    );
    Assert.areEqual(
      casosAntes,
      [SELECT COUNT() FROM Case],
      'No abre incidente'
    );
    Estado_Actual__c estado = [
      SELECT Valor__c, Severidad__c
      FROM Estado_Actual__c
      WHERE Clave__c = :CLAVE_PRESION
    ];
    Assert.areEqual(3.1, estado.Valor__c);
    Assert.areEqual(IngestaConstantes.SEV_NORMAL, estado.Severidad__c);
  }

  @isTest
  static void shouldDosFilas_WhenDosMedicionesDelMismoActivo() {
    Activo__c bomba = bomba();
    insert new Umbral__c(
      Clave__c = 'WATER_PUMP|WATER_CONSUMPTION',
      Tipo_Activo__c = 'WATER_PUMP',
      Tipo_Medicion__c = 'WATER_CONSUMPTION',
      Unidad__c = 'LITER_PER_15_MIN',
      Advertencia_Alto__c = 401,
      Critico_Alto__c = 651,
      Vigente__c = true
    );
    Map<String, Object> presionOk = presion(
      'msg_med_presion',
      'dlv_med_presion',
      2.76,
      '2026-09-22T22:50:18.000Z'
    );
    Map<String, Object> consumoCritico = presion(
      'msg_med_consumo',
      'dlv_med_consumo',
      700,
      '2026-09-22T22:50:20.000Z'
    );
    Map<String, Object> medicion = (Map<String, Object>) consumoCritico.get(
      'measurement'
    );
    medicion.put('type', 'WATER_CONSUMPTION');
    medicion.put('unit', 'LITER_PER_15_MIN');
    insert new List<Senal__c>{
      TestDataFactory.senalPendiente(presionOk, bomba.Id, bomba.Edificio__c),
      TestDataFactory.senalPendiente(
        consumoCritico,
        bomba.Id,
        bomba.Edificio__c
      )
    };

    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{
        TestDataFactory.avisoDe(presionOk),
        TestDataFactory.avisoDe(consumoCritico)
      }
    );
    Test.stopTest();

    Map<String, Estado_Actual__c> porClave = new Map<String, Estado_Actual__c>();
    for (Estado_Actual__c estado : [
      SELECT Clave__c, Valor__c, Tipo_Medicion__c, Severidad_Nivel__c
      FROM Estado_Actual__c
      WHERE Activo__c = :bomba.Id
    ]) {
      porClave.put(estado.Clave__c, estado);
    }
    Assert.areEqual(2, porClave.size(), 'Dos filas, una por medicion');
    Assert.areEqual(2.76, porClave.get(CLAVE_PRESION).Valor__c);
    Assert.areEqual(700, porClave.get(CLAVE_CONSUMO).Valor__c);
    Assert.areEqual(0, porClave.get(CLAVE_PRESION).Severidad_Nivel__c);
    Assert.areEqual(2, porClave.get(CLAVE_CONSUMO).Severidad_Nivel__c);

    Activo__c activo = [
      SELECT Severidad_Nivel__c, Severidad__c
      FROM Activo__c
      WHERE Id = :bomba.Id
    ];
    Assert.areEqual(2, activo.Severidad_Nivel__c, 'El resumen toma lo peor');
  }

  private static void procesarTandaLateMessages() {
    Activo__c bomba = bomba();
    Map<String, Object> d3 = presion(
      'msg_000003',
      'dlv_000003',
      4.66,
      '2026-09-22T22:50:18.000Z'
    );
    Map<String, Object> d4 = presion(
      'msg_000004',
      'dlv_000004',
      3.73,
      '2026-09-22T22:51:19.000Z'
    );
    Map<String, Object> d5 = presion(
      'msg_000005',
      'dlv_000005',
      3.54,
      '2026-09-22T22:42:20.000Z'
    );
    insert new List<Senal__c>{
      TestDataFactory.senalPendiente(d3, bomba.Id, bomba.Edificio__c),
      TestDataFactory.senalPendiente(d4, bomba.Id, bomba.Edificio__c),
      TestDataFactory.senalPendiente(d5, bomba.Id, bomba.Edificio__c)
    };
    Test.startTest();
    ProcesamientoServicio.procesar(
      new List<Aviso_de_Senal__e>{
        TestDataFactory.avisoDe(d3),
        TestDataFactory.avisoDe(d4),
        TestDataFactory.avisoDe(d5)
      }
    );
    Test.stopTest();
  }

  private static void procesarEmpate(Boolean menorPrimero) {
    Activo__c bomba = bomba();
    Map<String, Object> menor = presion(
      'msg_000009',
      'dlv_000009',
      2.5,
      '2026-09-22T22:50:18.000Z'
    );
    Map<String, Object> mayor = presion(
      'msg_000015',
      'dlv_000015',
      4.0,
      '2026-09-22T22:50:18.000Z'
    );
    insert new List<Senal__c>{
      TestDataFactory.senalPendiente(menor, bomba.Id, bomba.Edificio__c),
      TestDataFactory.senalPendiente(mayor, bomba.Id, bomba.Edificio__c)
    };
    List<Aviso_de_Senal__e> avisos = menorPrimero
      ? new List<Aviso_de_Senal__e>{
          TestDataFactory.avisoDe(menor),
          TestDataFactory.avisoDe(mayor)
        }
      : new List<Aviso_de_Senal__e>{
          TestDataFactory.avisoDe(mayor),
          TestDataFactory.avisoDe(menor)
        };
    Test.startTest();
    ProcesamientoServicio.procesar(avisos);
    Test.stopTest();
  }

  private static void afirmarGanadorDelEmpate() {
    Estado_Actual__c estado = [
      SELECT Valor__c, Ultimo_Message_Id__c
      FROM Estado_Actual__c
      WHERE Clave__c = :CLAVE_PRESION
    ];
    Assert.areEqual(4.0, estado.Valor__c);
    Assert.areEqual('msg_000015', estado.Ultimo_Message_Id__c);
    Assert.areEqual(
      IngestaConstantes.RESULTADO_APLICADO,
      resultadoDe('msg_000015')
    );
    Assert.areEqual(
      IngestaConstantes.RESULTADO_ATRASADO,
      resultadoDe('msg_000009')
    );
  }

  private static Map<String, Object> presion(
    String messageId,
    String deliveryId,
    Decimal valor,
    String occurredAt
  ) {
    Map<String, Object> mensaje = TestDataFactory.mensajePresion(
      messageId,
      deliveryId,
      valor,
      'BAR'
    );
    mensaje.put('occurredAt', occurredAt);
    return mensaje;
  }

  private static String resultadoDe(String messageId) {
    return [
      SELECT Resultado__c
      FROM Senal__c
      WHERE Clave__c = :('nova-casa-simulator|' + messageId)
    ]
    .Resultado__c;
  }

  private static Activo__c bomba() {
    return [
      SELECT Id, Edificio__c
      FROM Activo__c
      WHERE Codigo_Externo__c = :TestDataFactory.AST_PUMP
    ];
  }
}
