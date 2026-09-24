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
            catalogo,
            Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0)
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
            catalogo,
            Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0)
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
            catalogo,
            Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0)
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
            catalogo,
            Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0)
        );
        Test.stopTest();
        Assert.areEqual(IngestaConstantes.MOTIVO_UNIDAD, dictamen.motivo, 'PSI no se convierte');
    }

    @isTest
    static void shouldRechazarFuturo_WhenAdelantoMayorACincoMinutos() {
        IngestaValidador.Catalogo catalogo = IngestaValidador.cargarCatalogo();
        Map<String, Object> mensaje = TestDataFactory.mensajePresion();
        mensaje.put('occurredAt', '2026-09-22T22:20:00.000Z');
        Test.startTest();
        IngestaValidador.Dictamen dictamen = IngestaValidador.validar(
            mensaje,
            catalogo,
            Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0)
        );
        Test.stopTest();
        Assert.areEqual(IngestaConstantes.MOTIVO_FUTURA, dictamen.motivo, '20 minutos es demasiado');
    }

    @isTest
    static void shouldAceptarConectividad_WhenCamaraValida() {
        IngestaValidador.Catalogo catalogo = IngestaValidador.cargarCatalogo();
        Test.startTest();
        IngestaValidador.Dictamen dictamen = IngestaValidador.validar(
            TestDataFactory.mensajeCamara(),
            catalogo,
            Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0)
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
            IngestaValidador.claveDe(a),
            'Clave estable'
        );
        Assert.areEqual(IngestaValidador.hashDe(a), IngestaValidador.hashDe(b), 'Mismo hecho, mismo hash');
    }
}
