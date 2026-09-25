/**
 * US-209: resultado obligatorio, reintentable derivado, carga sin secretos,
 * busqueda y el operador fuera de la bitacora.
 */
@isTest
private class TrazabilidadTest {
    @TestSetup
    static void setup() {
        TestDataFactory.sembrarCatalogoMinimo();
        Activo__c bomba = [
            SELECT Id, Edificio__c
            FROM Activo__c
            WHERE Codigo_Externo__c = :TestDataFactory.AST_PUMP
        ];
        insert TestDataFactory.senalPendiente(
            TestDataFactory.mensajePresion(),
            bomba.Id,
            bomba.Edificio__c
        );
    }

    @isTest
    static void shouldExigirResultado_WhenInsertaSinEl() {
        Senal__c senal = new Senal__c(
            Clave__c = 'nova-casa-simulator|msg_sin_resultado',
            Message_Id__c = 'msg_sin_resultado'
        );
        Test.startTest();
        try {
            insert senal;
            Assert.fail('Sin resultado no se guarda');
        } catch (DmlException e) {
            Assert.isTrue(
                e.getMessage().contains('resultado') || e.getMessage().contains('Resultado'),
                'La regla habla de resultado: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @isTest
    static void shouldDerivarReintentableDelMotivo_WhenCadaMotivo() {
        Test.startTest();
        Assert.isTrue(IngestaConstantes.esReintentable(IngestaConstantes.MOTIVO_VERSION), 'Version');
        Assert.isTrue(IngestaConstantes.esReintentable(IngestaConstantes.MOTIVO_TIPO_MENSAJE), 'Tipo');
        Assert.isTrue(IngestaConstantes.esReintentable(IngestaConstantes.MOTIVO_EDIFICIO), 'Edificio');
        Assert.isTrue(IngestaConstantes.esReintentable(IngestaConstantes.MOTIVO_ACTIVO), 'Activo');
        Assert.isTrue(IngestaConstantes.esReintentable(IngestaConstantes.MOTIVO_TIPO_MEDICION), 'Medicion');
        Assert.isTrue(IngestaConstantes.esReintentable(IngestaConstantes.MOTIVO_SIN_LIMITE), 'Limite');
        Assert.isTrue(IngestaConstantes.esReintentable(IngestaConstantes.MOTIVO_SIN_MINUTOS), 'Minutos');
        Assert.isTrue(IngestaConstantes.esReintentable(IngestaConstantes.MOTIVO_SISTEMA), 'Sistema');
        Assert.isFalse(IngestaConstantes.esReintentable(IngestaConstantes.MOTIVO_CAMPO), 'Campo');
        Assert.isFalse(IngestaConstantes.esReintentable(IngestaConstantes.MOTIVO_VALOR), 'Valor');
        Assert.isFalse(IngestaConstantes.esReintentable(IngestaConstantes.MOTIVO_FECHA), 'Fecha');
        Assert.isFalse(IngestaConstantes.esReintentable(IngestaConstantes.MOTIVO_FUTURA), 'Futura');
        Assert.isFalse(IngestaConstantes.esReintentable(IngestaConstantes.MOTIVO_ACTIVO_EDIFICIO), 'Activo-edificio');
        Assert.isFalse(IngestaConstantes.esReintentable(IngestaConstantes.MOTIVO_COMUNICACION), 'Comunicacion');
        Assert.isFalse(IngestaConstantes.esReintentable(IngestaConstantes.MOTIVO_UNIDAD), 'Unidad');
        Assert.isFalse(IngestaConstantes.esReintentable(null), 'Nulo');
        Assert.isFalse(IngestaConstantes.esReintentable(''), 'Vacio');
        Senal__c senal = new Senal__c();
        IngestaConstantes.aplicar(senal, IngestaConstantes.RESULTADO_RECHAZADO, IngestaConstantes.MOTIVO_ACTIVO);
        Assert.isTrue(senal.Reintentable__c, 'Activo no encontrado se reintenta');
        IngestaConstantes.aplicar(senal, IngestaConstantes.RESULTADO_APLICADO, null);
        Assert.isFalse(senal.Reintentable__c, 'Aplicado no se reintenta');
        Test.stopTest();
    }

    @isTest
    static void shouldNoIncluirAutorizacion_WhenGuardaCarga() {
        String cuerpo = TestDataFactory.sobre(
            new List<Map<String, Object>>{ TestDataFactory.mensajePresion('msg_carga', 'dlv_carga', 2.76, 'BAR') },
            'c',
            false
        );
        Test.startTest();
        IngestaServicio.procesarPagina(cuerpo, Datetime.newInstanceGmt(2026, 9, 24, 15, 0, 0));
        Test.stopTest();
        Senal__c senal = [
            SELECT Carga__c
            FROM Senal__c
            WHERE Message_Id__c = 'msg_carga'
        ];
        Assert.isNotNull(senal.Carga__c, 'Hay cuerpo');
        Assert.isFalse(senal.Carga__c.containsIgnoreCase('authorization'), 'Sin cabecera');
        Assert.isFalse(senal.Carga__c.containsIgnoreCase('bearer'), 'Sin token');
        Assert.isTrue(senal.Carga__c.contains('msg_carga'), 'Conserva el mensaje');
    }

    @isTest
    static void shouldEncontrarPorClaveYMessageId_WhenBusca() {
        Test.startTest();
        Senal__c porClave = [
            SELECT Id, Message_Id__c
            FROM Senal__c
            WHERE Clave__c = 'nova-casa-simulator|msg_000002'
        ];
        Senal__c porMensaje = [
            SELECT Id, Clave__c
            FROM Senal__c
            WHERE Message_Id__c = 'msg_000002'
        ];
        Test.stopTest();
        Assert.areEqual(porClave.Id, porMensaje.Id, 'Misma senal por las dos identidades');
    }

    @isTest
    static void shouldDistinguirResultados_WhenIngestaYProceso() {
        Activo__c bomba = [
            SELECT Id, Edificio__c
            FROM Activo__c
            WHERE Codigo_Externo__c = :TestDataFactory.AST_PUMP
        ];
        Map<String, Object> invalida = TestDataFactory.mensajeTemperaturaNula();
        Map<String, Object> conflictoA = TestDataFactory.mensajePresion('msg_conf', 'dlv_c1', 2.76, 'BAR');
        Map<String, Object> conflictoB = TestDataFactory.mensajePresion('msg_conf', 'dlv_c2', 9.99, 'BAR');
        IngestaServicio.procesarPagina(
            TestDataFactory.sobre(new List<Map<String, Object>>{ invalida, conflictoA, conflictoB }, 'c', false),
            Datetime.newInstanceGmt(2026, 9, 24, 15, 0, 0)
        );

        Map<String, Object> atrasado = TestDataFactory.mensajePresion('msg_atr', 'dlv_atr', 1.11, 'BAR');
        atrasado.put('occurredAt', '2026-09-22T21:00:00.000Z');
        insert TestDataFactory.senalPendiente(atrasado, bomba.Id, bomba.Edificio__c);

        Test.startTest();
        ProcesamientoServicio.procesar(
            new List<Aviso_de_Senal__e>{
                TestDataFactory.avisoDe(TestDataFactory.mensajePresion()),
                TestDataFactory.avisoDe(atrasado)
            }
        );
        Test.stopTest();

        Map<String, Senal__c> porClave = new Map<String, Senal__c>();
        for (Senal__c senal : [
            SELECT Clave__c, Resultado__c, Entregas__c, Fecha_Origen__c,
                   Fecha_Publicacion__c, Fecha_Recepcion__c, Fecha_Procesamiento__c
            FROM Senal__c
        ]) {
            porClave.put(senal.Clave__c, senal);
        }
        Assert.areEqual(
            IngestaConstantes.RESULTADO_APLICADO,
            porClave.get('nova-casa-simulator|msg_000002').Resultado__c,
            'Normal aplicada'
        );
        Assert.areEqual(
            IngestaConstantes.RESULTADO_RECHAZADO,
            porClave.get('nova-casa-simulator|msg_000001').Resultado__c,
            'Invalida'
        );
        Assert.areEqual(
            IngestaConstantes.RESULTADO_CONFLICTO,
            porClave.get('nova-casa-simulator|msg_conf').Resultado__c,
            'Conflicto'
        );
        Assert.areEqual(
            2,
            porClave.get('nova-casa-simulator|msg_conf').Entregas__c.intValue(),
            'Duplicada se ve en entregas'
        );
        Assert.areEqual(
            IngestaConstantes.RESULTADO_ATRASADO,
            porClave.get('nova-casa-simulator|msg_atr').Resultado__c,
            'Atrasada'
        );
        Senal__c aplicada = porClave.get('nova-casa-simulator|msg_000002');
        Assert.isNotNull(aplicada.Fecha_Origen__c, 'Origen');
        Assert.isNotNull(aplicada.Fecha_Publicacion__c, 'Publicacion');
        Assert.isNotNull(aplicada.Fecha_Recepcion__c, 'Recepcion');
        Assert.isNotNull(aplicada.Fecha_Procesamiento__c, 'Procesamiento');
    }

    @isTest
    static void shouldOcultarBitacora_WhenOperador() {
        User operador = TestDataFactory.usuarioConConjunto('Nova_Casa_Operador');
        Test.startTest();
        System.runAs(operador) {
            Boolean sinAcceso = false;
            try {
                List<Senal__c> filas = [SELECT Id FROM Senal__c WITH USER_MODE];
                Assert.areEqual(0, filas.size(), 'El operador no lee senales');
                sinAcceso = filas.isEmpty();
            } catch (System.QueryException e) {
                sinAcceso = true;
            } catch (System.SecurityException e) {
                sinAcceso = true;
            }
            Assert.isTrue(sinAcceso, 'Sin objeto o sin filas');
        }
        Test.stopTest();
    }
}
