@IsTest
private class UmbralAplicacionServicioTest {
  private static String sufijo() {
    return String.valueOf(Math.abs(Crypto.getRandomInteger()));
  }

  private static Umbral__c sembrarTemperatura(Decimal criticoAlto) {
    String marca = sufijo();
    Edificio__c edificio = new Edificio__c(
      Name = 'Edificio prueba ' + marca,
      Codigo_Externo__c = 'T' + marca.left(12),
      Ciudad__c = 'Bogotá'
    );
    insert edificio;

    Activo__c activo = new Activo__c(
      Name = 'Sala prueba',
      Codigo_Externo__c = 'A' + marca.left(12),
      Tipo__c = 'TECHNICAL_ROOM',
      Edificio__c = edificio.Id
    );
    insert activo;

    Umbral__c umbral = new Umbral__c(
      Clave__c = 'TECHNICAL_ROOM|TEMPERATURE|' + marca.left(8),
      Tipo_Activo__c = 'TECHNICAL_ROOM',
      Tipo_Medicion__c = 'TEMPERATURE',
      Unidad__c = 'CELSIUS',
      Critico_Bajo__c = 14.9,
      Advertencia_Bajo__c = 17.9,
      Advertencia_Alto__c = 30.1,
      Critico_Alto__c = criticoAlto,
      Decimales__c = 1,
      Vigente__c = true
    );
    insert umbral;

    insert new Estado_Actual__c(
      Activo__c = activo.Id,
      Clave__c = activo.Codigo_Externo__c + '|TEMPERATURE',
      Tipo_Medicion__c = 'TEMPERATURE',
      Valor__c = 32,
      Unidad__c = 'CELSIUS',
      Severidad__c = 'Advertencia',
      Severidad_Nivel__c = 1
    );

    insert new Senal__c(
      Clave__c = 'nova-casa-simulator|msg_' + marca.left(8),
      Resultado__c = 'Aplicado',
      Motivo__c = null
    );

    return umbral;
  }

  @IsTest
  static void rangoContradictorioNoSeGuarda() {
    Umbral__c umbral = new Umbral__c(
      Clave__c = 'TECHNICAL_ROOM|TEMPERATURE|' + sufijo().left(8),
      Tipo_Activo__c = 'TECHNICAL_ROOM',
      Tipo_Medicion__c = 'TEMPERATURE',
      Critico_Bajo__c = 20,
      Advertencia_Bajo__c = 17.9,
      Advertencia_Alto__c = 30.1,
      Critico_Alto__c = 35.1
    );

    try {
      insert umbral;
      System.assert(false, 'Debio bloquear el orden bajo invertido');
    } catch (DmlException e) {
      System.assert(e.getMessage().contains('crítico bajo'), e.getMessage());
    }
  }

  @IsTest
  static void sinNingunaFronteraNoSeGuarda() {
    Umbral__c umbral = new Umbral__c(
      Clave__c = 'TECHNICAL_ROOM|TEMPERATURE|' + sufijo().left(8),
      Tipo_Activo__c = 'TECHNICAL_ROOM',
      Tipo_Medicion__c = 'TEMPERATURE'
    );

    try {
      insert umbral;
      System.assert(false, 'Debio bloquear un umbral vacio');
    } catch (DmlException e) {
      System.assert(e.getMessage().contains('frontera'), e.getMessage());
    }
  }

  @IsTest
  static void camaraSoloConMinutosSiSeGuarda() {
    Umbral__c umbral = new Umbral__c(
      Clave__c = 'SECURITY_CAMERA|CAMERA_CONNECTIVITY|' + sufijo().left(8),
      Tipo_Activo__c = 'SECURITY_CAMERA',
      Tipo_Medicion__c = 'CAMERA_CONNECTIVITY',
      Minutos_Advertencia__c = 15,
      Minutos_Critico__c = 60,
      Vigente__c = true
    );
    insert umbral;
    System.assertNotEquals(null, umbral.Id);
  }

  @IsTest
  static void aplicarLimitesReclasificaSinAbrirCasosNiTocarBitacora() {
    Umbral__c umbral = sembrarTemperatura(35.1);

    umbral.Advertencia_Alto__c = 31;
    umbral.Critico_Alto__c = 32;
    update umbral;

    Integer casosAntes = [SELECT COUNT() FROM Case];
    Senal__c senalAntes = [
      SELECT Resultado__c, Motivo__c
      FROM Senal__c
      LIMIT 1
    ];

    Test.startTest();
    UmbralAplicacionServicio.Peticion peticion = new UmbralAplicacionServicio.Peticion();
    peticion.umbralId = umbral.Id;
    List<UmbralAplicacionServicio.Respuesta> respuestas = UmbralAplicacionServicio.aplicar(
      new List<UmbralAplicacionServicio.Peticion>{ peticion }
    );
    Test.stopTest();

    System.assertEquals(1, respuestas[0].estadosActualizados);

    Estado_Actual__c estado = [
      SELECT Severidad__c, Severidad_Nivel__c, Valor__c
      FROM Estado_Actual__c
      WHERE Valor__c = 32
      LIMIT 1
    ];
    System.assertEquals('Critico', estado.Severidad__c);
    System.assertEquals(2, estado.Severidad_Nivel__c);

    System.assertEquals(casosAntes, [SELECT COUNT() FROM Case]);

    Senal__c senalDespues = [
      SELECT Resultado__c, Motivo__c
      FROM Senal__c
      WHERE Id = :senalAntes.Id
    ];
    System.assertEquals(senalAntes.Resultado__c, senalDespues.Resultado__c);
    System.assertEquals(senalAntes.Motivo__c, senalDespues.Motivo__c);
  }

  @IsTest
  static void cambiarLimiteSinAplicarNoReclasifica() {
    Umbral__c umbral = sembrarTemperatura(35.1);
    umbral.Critico_Alto__c = 32;
    update umbral;

    Estado_Actual__c estado = [
      SELECT Severidad__c, Severidad_Nivel__c
      FROM Estado_Actual__c
      WHERE Valor__c = 32
      LIMIT 1
    ];
    System.assertEquals('Advertencia', estado.Severidad__c);
    System.assertEquals(1, estado.Severidad_Nivel__c);
  }
}
