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
        IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(cuerpo, ahora);
        Senal__c publicada = [
            SELECT Resultado__c, Fecha_Origen__c, Fecha_Publicacion__c,
                   Fecha_Recepcion__c, Fecha_Procesamiento__c, Clave__c, Entregas__c
            FROM Senal__c
            WHERE Clave__c = 'nova-casa-simulator|msg_000002'
        ];
        Assert.areEqual(IngestaConstantes.RESULTADO_PENDIENTE, publicada.Resultado__c, 'Pendiente, no aplicado');
        Assert.isNull(publicada.Fecha_Procesamiento__c, 'Procesamiento lo llena el suscriptor');
        Test.stopTest();

        Assert.areEqual(1, r.senales, 'Una senal');
        Assert.areEqual(1, r.publicadas, 'Un aviso');
        Senal__c senal = [
            SELECT Resultado__c, Fecha_Origen__c, Fecha_Publicacion__c,
                   Fecha_Recepcion__c, Fecha_Procesamiento__c, Clave__c, Entregas__c
            FROM Senal__c
            WHERE Clave__c = 'nova-casa-simulator|msg_000002'
        ];
        Assert.areEqual(IngestaConstantes.RESULTADO_APLICADO, senal.Resultado__c, 'El suscriptor aplica al entregar');
        Assert.areEqual(ahora, senal.Fecha_Recepcion__c, 'Recepcion es ahora');
        Assert.isNotNull(senal.Fecha_Procesamiento__c, 'Ya no esta pendiente');
        Assert.areNotEqual(senal.Fecha_Origen__c, senal.Fecha_Publicacion__c, 'Origen distinto de publicacion');
        Assert.areNotEqual(senal.Fecha_Origen__c, senal.Fecha_Recepcion__c, 'Origen distinto de recepcion');
        Assert.areNotEqual(senal.Fecha_Publicacion__c, senal.Fecha_Recepcion__c, 'Publicacion distinta de recepcion');
        Assert.areEqual(senal.Clave__c, 'nova-casa-simulator|msg_000002', 'Misma clave publicada');
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
        Assert.areEqual(IngestaConstantes.RESULTADO_RECHAZADO, senal.Resultado__c, 'Rechazado');
        Assert.areEqual(IngestaConstantes.MOTIVO_VALOR, senal.Motivo__c, 'Valor invalido');
        Assert.isFalse(senal.Reintentable__c, 'El mensaje esta mal');
        Assert.isTrue(senal.Carga__c.contains('"value":null') || senal.Carga__c.contains('"value": null'), 'Conserva la carga');
    }

    @isTest
    static void shouldNoTumbarPagina_WhenClavesRepetidas() {
        Map<String, Object> primero = TestDataFactory.mensajePresion();
        Map<String, Object> segundo = TestDataFactory.mensajePresion('msg_000002', 'dlv_000004', 2.76, 'BAR');
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
        Assert.areEqual(2, r.senales, 'Dos claves distintas; el duplicado no inserta fila');
        Assert.areEqual(2, r.publicadas, 'Presion y camara');
        Senal__c senal = [
            SELECT Entregas__c, Ultimo_Delivery_Id__c, Resultado__c
            FROM Senal__c
            WHERE Clave__c = 'nova-casa-simulator|msg_000002'
        ];
        Assert.areEqual(2, senal.Entregas__c.intValue(), 'Dos entregas del mismo mensaje');
        Assert.areEqual('dlv_000004', senal.Ultimo_Delivery_Id__c, 'Ultima entrega');
        Assert.areNotEqual(IngestaConstantes.RESULTADO_DUPLICADO, senal.Resultado__c, 'No pisa a Duplicado');
    }

    @isTest
    static void shouldMarcarConflicto_WhenMismoIdDistintoValor() {
        Map<String, Object> a = TestDataFactory.mensajePresion('msg_000014', 'dlv_000014', 19.7, 'BAR');
        Map<String, Object> b = TestDataFactory.mensajePresion('msg_000014', 'dlv_000016', 60.19, 'BAR');
        String cuerpo = TestDataFactory.sobre(new List<Map<String, Object>>{ a, b }, 'c', false);
        Test.startTest();
        IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
            cuerpo,
            Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0)
        );
        Test.stopTest();
        Senal__c senal = [
            SELECT Resultado__c, Entregas__c
            FROM Senal__c
            WHERE Clave__c = 'nova-casa-simulator|msg_000014'
        ];
        Assert.areEqual(IngestaConstantes.RESULTADO_CONFLICTO, senal.Resultado__c, 'Conflicto');
        Assert.areEqual(2, senal.Entregas__c.intValue(), 'Dos afirmaciones');
        Assert.areEqual(0, r.publicadas, 'Un conflicto no se publica');
    }

    @isTest
    static void shouldIncrementarEntregas_WhenReenvioEnOtraPagina() {
        Datetime ahora = Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0);
        IngestaServicio.procesarPagina(
            TestDataFactory.sobre(
                new List<Map<String, Object>>{ TestDataFactory.mensajePresion() },
                'c1',
                true
            ),
            ahora
        );
        Map<String, Object> reenvio = TestDataFactory.mensajePresion('msg_000002', 'dlv_000099', 2.76, 'BAR');
        Test.startTest();
        IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
            TestDataFactory.sobre(new List<Map<String, Object>>{ reenvio }, 'c2', true),
            ahora.addMinutes(2)
        );
        Test.stopTest();
        Assert.areEqual(0, r.publicadas, 'Reenvio no republica');
        Senal__c senal = [
            SELECT Entregas__c, Resultado__c, Fecha_Recepcion__c
            FROM Senal__c
            WHERE Clave__c = 'nova-casa-simulator|msg_000002'
        ];
        Assert.areEqual(2, senal.Entregas__c.intValue(), 'Contador');
        Assert.areNotEqual(IngestaConstantes.RESULTADO_DUPLICADO, senal.Resultado__c, 'No cambia a Duplicado');
        Assert.areEqual(ahora, senal.Fecha_Recepcion__c, 'La primera recepcion se conserva');
    }

    @isTest
    static void shouldGuardarTodos_WhenPaginaDeCincuenta() {
        List<Map<String, Object>> mensajes = new List<Map<String, Object>>();
        for (Integer i = 1; i <= 50; i++) {
            String n = String.valueOf(i).leftPad(6, '0');
            mensajes.add(TestDataFactory.mensajePresion('msg_' + n, 'dlv_' + n, 2.76, 'BAR'));
        }
        Test.startTest();
        IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
            TestDataFactory.sobre(mensajes, 'c', true),
            Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0)
        );
        Assert.areEqual(
            50,
            [SELECT COUNT() FROM Senal__c WHERE Resultado__c = :IngestaConstantes.RESULTADO_PENDIENTE],
            'Tras publicar, todavia pendientes'
        );
        Test.stopTest();
        Assert.areEqual(50, r.senales, 'Cincuenta senales');
        Assert.areEqual(50, r.publicadas, 'Cincuenta avisos');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Senal__c WHERE Resultado__c = :IngestaConstantes.RESULTADO_PENDIENTE],
            'El suscriptor drena la tanda'
        );
    }

    @isTest
    static void shouldRechazarPagina_WhenVersionDesconocida() {
        Map<String, Object> sobre = new Map<String, Object>{
            'schemaVersion' => '9.9',
            'data' => new List<Object>{ TestDataFactory.mensajePresion() },
            'pagination' => new Map<String, Object>{ 'nextCursor' => 'c', 'hasMore' => true }
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
        Assert.areEqual(IngestaConstantes.MOTIVO_VERSION, senal.Motivo__c, 'Version no soportada');
        Assert.areEqual(IngestaConstantes.RESULTADO_RECHAZADO, senal.Resultado__c, 'Rechazado');
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
            TestDataFactory.sobre(new List<Map<String, Object>>{ mensaje }, 'c1', true),
            ahora
        );
        Senal__c antes = [
            SELECT Resultado__c, Motivo__c, Reintentable__c
            FROM Senal__c
            WHERE Clave__c = 'nova-casa-simulator|msg_unknown'
        ];
        Assert.areEqual(IngestaConstantes.RESULTADO_RECHAZADO, antes.Resultado__c, 'Primera vez rechazado');
        Assert.areEqual(IngestaConstantes.MOTIVO_ACTIVO, antes.Motivo__c, 'Activo no encontrado');
        Assert.isTrue(antes.Reintentable__c, 'Se puede reintentar');

        Edificio__c baq = [SELECT Id FROM Edificio__c WHERE Codigo_Externo__c = :TestDataFactory.BLD_BAQ];
        insert new Activo__c(
            Name = 'Activo que faltaba',
            Codigo_Externo__c = 'AST-UNKNOWN-0001',
            Tipo__c = 'WATER_PUMP',
            Sensor_Id__c = 'SNS-UNKNOWN-0001',
            Edificio__c = baq.Id
        );

        Test.startTest();
        IngestaServicio.ResultadoPagina r = IngestaServicio.procesarPagina(
            TestDataFactory.sobre(new List<Map<String, Object>>{ mensaje }, 'c2', true),
            ahora.addMinutes(1)
        );
        Senal__c pendiente = [
            SELECT Resultado__c, Motivo__c, Reintentable__c, Activo__c, Entregas__c
            FROM Senal__c
            WHERE Clave__c = 'nova-casa-simulator|msg_unknown'
        ];
        Assert.areEqual(IngestaConstantes.RESULTADO_PENDIENTE, pendiente.Resultado__c, 'El alta desbloquea');
        Assert.isNull(pendiente.Motivo__c, 'Sin motivo');
        Assert.isFalse(pendiente.Reintentable__c, 'Pendiente no se reintenta');
        Test.stopTest();

        Senal__c despues = [
            SELECT Resultado__c, Motivo__c, Reintentable__c, Activo__c, Entregas__c
            FROM Senal__c
            WHERE Clave__c = 'nova-casa-simulator|msg_unknown'
        ];
        Assert.areEqual(IngestaConstantes.RESULTADO_APLICADO, despues.Resultado__c, 'El aviso se aplica');
        Assert.isNotNull(despues.Activo__c, 'Resuelve el activo');
        Assert.areEqual(2, despues.Entregas__c.intValue(), 'Cuenta el reenvio');
        Assert.areEqual(1, r.publicadas, 'Publica al quedar pendiente');
    }
}
