/**
 * Pruebas de validacion de un mensaje, una conducta por metodo.
 */
@isTest
private class IngestaValidadorTest {
    @TestSetup
    static void setup() {
        TestDataFactory.sembrarCatalogoMinimo();
    }

    @isTest
    static void shouldAceptar_WhenMedicionValida() {
        IngestaValidador.Catalogo catalogo = IngestaValidador.cargarCatalogo();
        Test.startTest();
        IngestaValidador.Dictamen dictamen = IngestaValidador.validar(
            TestDataFactory.mensajePresion(),
            catalogo
        );
        Test.stopTest();
        Assert.isTrue(dictamen.esValido(), 'Una lectura de 2.76 BAR debe pasar');
        Assert.areEqual(TestDataFactory.AST_PUMP, dictamen.activo.Codigo_Externo__c, 'Activo bomba');
    }

    @isTest
    static void shouldRechazarValor_WhenValueNulo() {
        IngestaValidador.Catalogo catalogo = IngestaValidador.cargarCatalogo();
        Test.startTest();
        IngestaValidador.Dictamen dictamen = IngestaValidador.validar(
            TestDataFactory.mensajeTemperaturaNula(),
            catalogo
        );
        Test.stopTest();
        Assert.areEqual(IngestaConstantes.MOTIVO_VALOR, dictamen.motivo, 'Valor nulo');
        Assert.isFalse(IngestaConstantes.esReintentable(dictamen.motivo), 'No reintentable');
    }

    @isTest
    static void shouldRechazarActivo_WhenNoExiste() {
        IngestaValidador.Catalogo catalogo = IngestaValidador.cargarCatalogo();
        Test.startTest();
        IngestaValidador.Dictamen dictamen = IngestaValidador.validar(
            TestDataFactory.mensajeActivoDesconocido(),
            catalogo
        );
        Test.stopTest();
        Assert.areEqual(IngestaConstantes.MOTIVO_ACTIVO, dictamen.motivo, 'Activo desconocido');
        Assert.isTrue(IngestaConstantes.esReintentable(dictamen.motivo), 'Reintentable');
    }

    @isTest
    static void shouldRechazarUnidad_WhenNoCoincide() {
        IngestaValidador.Catalogo catalogo = IngestaValidador.cargarCatalogo();
        Test.startTest();
        IngestaValidador.Dictamen dictamen = IngestaValidador.validar(
            TestDataFactory.mensajePresion('msg_psi', 'dlv_psi', 40, 'PSI'),
            catalogo
        );
        Test.stopTest();
        Assert.areEqual(IngestaConstantes.MOTIVO_UNIDAD, dictamen.motivo, 'PSI no se convierte');
    }

    @isTest
    static void shouldRechazarFuturo_WhenOcurreMasDeCincoMinutosDespuesDePublicarse() {
        IngestaValidador.Catalogo catalogo = IngestaValidador.cargarCatalogo();
        Map<String, Object> mensaje = TestDataFactory.mensajePresion();
        mensaje.put('publishedAt', '2026-09-22T22:00:00.000Z');
        mensaje.put('occurredAt', '2026-09-22T22:20:00.000Z');
        Test.startTest();
        IngestaValidador.Dictamen dictamen = IngestaValidador.validar(
            mensaje,
            catalogo
        );
        Test.stopTest();
        Assert.areEqual(IngestaConstantes.MOTIVO_FUTURA, dictamen.motivo, '20 minutos es demasiado');
    }

    @isTest
    static void shouldAceptar_WhenRelojDelSimuladorVaPorDelanteDeLaOrg() {
        IngestaValidador.Catalogo catalogo = IngestaValidador.cargarCatalogo();
        Map<String, Object> mensaje = TestDataFactory.mensajePresion();
        String dentroDeDosDias = Datetime.now().addDays(2).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
        mensaje.put('occurredAt', dentroDeDosDias);
        mensaje.put('publishedAt', dentroDeDosDias);
        Test.startTest();
        IngestaValidador.Dictamen dictamen = IngestaValidador.validar(
            mensaje,
            catalogo
        );
        Test.stopTest();
        Assert.isTrue(dictamen.esValido(), 'Publicado y ocurrido a la vez: no es futuro aunque la org vaya detras');
    }

    @isTest
    static void shouldAceptarConectividad_WhenCamaraValida() {
        IngestaValidador.Catalogo catalogo = IngestaValidador.cargarCatalogo();
        Test.startTest();
        IngestaValidador.Dictamen dictamen = IngestaValidador.validar(
            TestDataFactory.mensajeCamara(),
            catalogo
        );
        Test.stopTest();
        Assert.isTrue(dictamen.esValido(), 'Corte de camara de 180 s debe pasar');
    }

    @isTest
    static void shouldArmarClaveYHashEstables() {
        Map<String, Object> a = TestDataFactory.mensajePresion();
        Map<String, Object> b = TestDataFactory.mensajePresion('msg_000002', 'dlv_otro', 2.76, 'BAR');
        b.put('publishedAt', '2026-09-22T21:56:30.273Z');
        Assert.areEqual(
            'nova-casa-simulator|msg_000002',
            IngestaValidador.claveDe(a, null),
            'Clave estable'
        );
        Assert.areEqual(IngestaValidador.hashDe(a), IngestaValidador.hashDe(b), 'Mismo hecho, mismo hash');
    }

    @isTest
    static void shouldIncluirInicioDeSesion_WhenArmaLaClave() {
        Map<String, Object> mensaje = TestDataFactory.mensajePresion();
        Datetime recienAbierta = IngestaValidador.parsearIso('2026-09-24T21:44:55.383Z');
        Datetime guardada = Datetime.newInstanceGmt(2026, 9, 24, 21, 44, 55);
        Assert.areEqual(
            'nova-casa-simulator|2026-09-24T21:44:55Z|msg_000002',
            IngestaValidador.claveDe(mensaje, recienAbierta),
            'La sesion forma parte de la clave'
        );
        Assert.areEqual(
            IngestaValidador.claveDe(mensaje, recienAbierta),
            IngestaValidador.claveDe(mensaje, guardada),
            'Recien abierta o leida del control, la sesion da la misma clave'
        );
        Assert.areNotEqual(
            IngestaValidador.claveDe(mensaje, guardada),
            IngestaValidador.claveDe(mensaje, guardada.addDays(8)),
            'El mismo messageId en otra sesion es otro mensaje'
        );
    }
}
