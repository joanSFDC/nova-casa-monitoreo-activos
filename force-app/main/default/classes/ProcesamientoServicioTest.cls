/**
 * Tanda de avisos: aislamiento, vigencia, volumen y consumo constante.
 */
@isTest
private class ProcesamientoServicioTest {
    @TestSetup
    static void setup() {
        TestDataFactory.sembrarCatalogoMinimo();
    }

    @isTest
    static void shouldAplicarYEscribirEstado_WhenMedicionValida() {
        Activo__c bomba = activoDe(TestDataFactory.AST_PUMP);
        Map<String, Object> mensaje = TestDataFactory.mensajePresion();
        insert TestDataFactory.senalPendiente(mensaje, bomba.Id, bomba.Edificio__c);

        Test.startTest();
        ProcesamientoServicio.ResultadoTanda r = ProcesamientoServicio.procesar(
            new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(mensaje) }
        );
        Test.stopTest();

        Assert.areEqual(1, r.aplicadas, 'Una aplicada');
        Senal__c senal = [
            SELECT Resultado__c, Fecha_Procesamiento__c
            FROM Senal__c
            WHERE Clave__c = 'nova-casa-simulator|msg_000002'
        ];
        Assert.areEqual(IngestaConstantes.RESULTADO_APLICADO, senal.Resultado__c, 'Aplicado');
        Assert.isNotNull(senal.Fecha_Procesamiento__c, 'Procesamiento lleno');
        Estado_Actual__c estado = [
            SELECT Valor__c, Severidad__c, Clave__c
            FROM Estado_Actual__c
            WHERE Clave__c = 'AST-BOG-PUMP-001|WATER_PRESSURE'
        ];
        Assert.areEqual(2.76, estado.Valor__c, 'Valor vigente');
        Assert.areEqual(IngestaConstantes.SEV_NORMAL, estado.Severidad__c, 'Normal');
    }

    @isTest
    static void shouldRechazarYAplicarElResto_WhenActivoDesconocidoYValido() {
        Activo__c bomba = activoDe(TestDataFactory.AST_PUMP);
        Map<String, Object> bueno = TestDataFactory.mensajePresion();
        Map<String, Object> malo = TestDataFactory.mensajeActivoDesconocido();
        insert new List<Senal__c>{
            TestDataFactory.senalPendiente(bueno, bomba.Id, bomba.Edificio__c),
            TestDataFactory.senalPendiente(malo, null, bomba.Edificio__c)
        };

        Test.startTest();
        ProcesamientoServicio.ResultadoTanda r = ProcesamientoServicio.procesar(
            new List<Aviso_de_Senal__e>{
                TestDataFactory.avisoDe(malo),
                TestDataFactory.avisoDe(bueno)
            }
        );
        Test.stopTest();

        Assert.areEqual(1, r.aplicadas, 'El valido se aplica');
        Assert.areEqual(1, r.rechazadas, 'El desconocido se rechaza');
        Senal__c rechazada = [
            SELECT Resultado__c, Motivo__c, Fecha_Procesamiento__c
            FROM Senal__c
            WHERE Clave__c = 'nova-casa-simulator|msg_unknown'
        ];
        Assert.areEqual(IngestaConstantes.RESULTADO_RECHAZADO, rechazada.Resultado__c, 'Rechazado');
        Assert.areEqual(IngestaConstantes.MOTIVO_ACTIVO, rechazada.Motivo__c, 'Activo no encontrado');
        Assert.isNotNull(rechazada.Fecha_Procesamiento__c, 'Ya no esta pendiente');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Estado_Actual__c],
            'Solo el valido escribe estado'
        );
    }

    @isTest
    static void shouldMarcarAtrasado_WhenOccurredAtAnterior() {
        Activo__c bomba = activoDe(TestDataFactory.AST_PUMP);
        insert new Estado_Actual__c(
            Activo__c = bomba.Id,
            Clave__c = 'AST-BOG-PUMP-001|WATER_PRESSURE',
            Tipo_Medicion__c = 'WATER_PRESSURE',
            Valor__c = 3.73,
            Unidad__c = 'BAR',
            Fecha_Origen__c = Datetime.newInstanceGmt(2026, 9, 22, 22, 51, 19),
            Ultimo_Message_Id__c = 'msg_000004',
            Severidad__c = IngestaConstantes.SEV_NORMAL,
            Severidad_Nivel__c = 0
        );
        Map<String, Object> atrasado = TestDataFactory.mensajePresion('msg_000005', 'dlv_000005', 3.54, 'BAR');
        atrasado.put('occurredAt', '2026-09-22T22:42:20.000Z');
        insert TestDataFactory.senalPendiente(atrasado, bomba.Id, bomba.Edificio__c);

        Test.startTest();
        ProcesamientoServicio.procesar(
            new List<Aviso_de_Senal__e>{ TestDataFactory.avisoDe(atrasado) }
        );
        Test.stopTest();

        Senal__c senal = [
            SELECT Resultado__c FROM Senal__c WHERE Clave__c = 'nova-casa-simulator|msg_000005'
        ];
        Assert.areEqual(IngestaConstantes.RESULTADO_ATRASADO, senal.Resultado__c, 'Atrasado');
        Estado_Actual__c estado = [
            SELECT Valor__c, Ultimo_Message_Id__c
            FROM Estado_Actual__c
            WHERE Clave__c = 'AST-BOG-PUMP-001|WATER_PRESSURE'
        ];
        Assert.areEqual(3.73, estado.Valor__c, 'No retrocede');
        Assert.areEqual('msg_000004', estado.Ultimo_Message_Id__c, 'Sigue el vigente');
    }

    @isTest
    static void shouldConsumoConstanteYCerrarPendientes_WhenCincoYDoscientos() {
        Activo__c bomba = activoDe(TestDataFactory.AST_PUMP);
        List<Senal__c> senales = new List<Senal__c>();
        List<Aviso_de_Senal__e> cinco = new List<Aviso_de_Senal__e>();
        List<Aviso_de_Senal__e> doscientos = new List<Aviso_de_Senal__e>();
        for (Integer i = 1; i <= 205; i++) {
            String n = String.valueOf(i).leftPad(6, '0');
            Map<String, Object> mensaje = TestDataFactory.mensajePresion('msg_' + n, 'dlv_' + n, 2.76, 'BAR');
            senales.add(TestDataFactory.senalPendiente(mensaje, bomba.Id, bomba.Edificio__c));
            Aviso_de_Senal__e aviso = TestDataFactory.avisoDe(mensaje);
            if (i <= 5) {
                cinco.add(aviso);
            } else {
                doscientos.add(aviso);
            }
        }
        insert senales;

        Test.startTest();
        Integer q0 = Limits.getQueries();
        Integer d0 = Limits.getDmlStatements();
        ProcesamientoServicio.procesar(cinco);
        Integer q5 = Limits.getQueries() - q0;
        Integer d5 = Limits.getDmlStatements() - d0;
        q0 = Limits.getQueries();
        d0 = Limits.getDmlStatements();
        ProcesamientoServicio.ResultadoTanda r200 = ProcesamientoServicio.procesar(doscientos);
        Integer q200 = Limits.getQueries() - q0;
        Integer d200 = Limits.getDmlStatements() - d0;
        Test.stopTest();

        Assert.areEqual(q5, q200, 'Las consultas no crecen con el volumen');
        Assert.areEqual(d5, d200, 'Las escrituras no crecen con el volumen');
        Assert.areEqual(200, r200.aplicadas, 'Doscientas aplicadas');
        Assert.areEqual(0, r200.senales - r200.aplicadas - r200.rechazadas - r200.atrasadas - r200.fallidas, 'Cuadre');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Senal__c WHERE Resultado__c = :IngestaConstantes.RESULTADO_PENDIENTE],
            'Ninguna pendiente'
        );
        Assert.areEqual(205, [SELECT COUNT() FROM Senal__c], 'Cinco mas doscientas');
    }

    @isTest
    static void shouldMarcarFallido_WhenEscrituraDeEstadoFalla() {
        Activo__c bomba = activoDe(TestDataFactory.AST_PUMP);
        Activo__c camara = activoDe(TestDataFactory.AST_CAM);
        Map<String, Object> presion = TestDataFactory.mensajePresion();
        Map<String, Object> latido = TestDataFactory.mensajeCamara();
        ((Map<String, Object>) latido.get('communication')).put('status', 'HEALTHY');
        insert new List<Senal__c>{
            TestDataFactory.senalPendiente(presion, bomba.Id, bomba.Edificio__c),
            TestDataFactory.senalPendiente(latido, camara.Id, camara.Edificio__c)
        };
        ProcesamientoServicio.inyectarFalloDeEscritura = true;

        Test.startTest();
        ProcesamientoServicio.ResultadoTanda r = ProcesamientoServicio.procesar(
            new List<Aviso_de_Senal__e>{
                TestDataFactory.avisoDe(presion),
                TestDataFactory.avisoDe(latido)
            }
        );
        Test.stopTest();

        Assert.areEqual(1, r.fallidas, 'Una escritura fallida');
        Assert.areEqual(1, r.aplicadas, 'La otra sigue');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Senal__c WHERE Resultado__c = :IngestaConstantes.RESULTADO_PENDIENTE],
            'Ninguna queda a medias'
        );
    }

    @isTest
    static void shouldAplicarViaEvento_WhenSePublicaAviso() {
        Activo__c bomba = activoDe(TestDataFactory.AST_PUMP);
        Map<String, Object> mensaje = TestDataFactory.mensajePresion();
        insert TestDataFactory.senalPendiente(mensaje, bomba.Id, bomba.Edificio__c);

        Test.startTest();
        EventBus.publish(TestDataFactory.avisoDe(mensaje));
        Test.stopTest();

        Senal__c senal = [
            SELECT Resultado__c FROM Senal__c WHERE Clave__c = 'nova-casa-simulator|msg_000002'
        ];
        Assert.areEqual(IngestaConstantes.RESULTADO_APLICADO, senal.Resultado__c, 'El disparador aplica');
    }

    private static Activo__c activoDe(String codigo) {
        return [
            SELECT Id, Edificio__c, Codigo_Externo__c
            FROM Activo__c
            WHERE Codigo_Externo__c = :codigo
        ];
    }
}
