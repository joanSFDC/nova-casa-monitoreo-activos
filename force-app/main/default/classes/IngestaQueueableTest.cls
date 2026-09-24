/**
 * Pruebas del eslabon Queueable: sesion, telemetria y cortes HTTP.
 */
@isTest
private class IngestaQueueableTest {
    @TestSetup
    static void setup() {
        TestDataFactory.sembrarCatalogoMinimo();
        TestDataFactory.crearControl(true);
    }

    @isTest
    static void shouldCrearSenalPendiente_WhenTelemetria200() {
        IngestaSimuladorMock mock = new IngestaSimuladorMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new IngestaQueueable());
        Test.stopTest();

        Senal__c senal = [
            SELECT Resultado__c, Clave__c
            FROM Senal__c
            WHERE Clave__c = 'nova-casa-simulator|msg_000002'
        ];
        Assert.areEqual(IngestaConstantes.RESULTADO_PENDIENTE, senal.Resultado__c, 'Pendiente');
        Control_de_Ingesta__c control = [
            SELECT Cursor__c, Fallos_Consecutivos__c, Paginas_Procesadas__c, Ultimo_Error__c
            FROM Control_de_Ingesta__c
            LIMIT 1
        ];
        Assert.areEqual('cursor-siguiente', control.Cursor__c, 'Avanza el cursor');
        Assert.areEqual(1, control.Paginas_Procesadas__c.intValue(), 'Una pagina');
        Assert.areEqual(0, control.Fallos_Consecutivos__c.intValue(), 'Sin fallos');
        Assert.isTrue(mock.llamadas >= 2, 'Sesion y telemetria');
        Assert.areEqual('POST', mock.metodos[0], 'Primero abre sesion');
    }

    @isTest
    static void shouldNoAvanzarCursor_When429() {
        Control_de_Ingesta__c control = [SELECT Id FROM Control_de_Ingesta__c LIMIT 1];
        control.Cursor__c = 'cursor-guardado';
        update control;

        IngestaSimuladorMock mock = new IngestaSimuladorMock();
        mock.codigoTelemetria = 429;
        mock.cuerpoTelemetria = '{"type":"too-many","title":"Too Many","status":429,"detail":"espera"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new IngestaQueueable(0));
        Test.stopTest();

        Control_de_Ingesta__c despues = [
            SELECT Cursor__c, Ultimo_Error__c, Paginas_Procesadas__c
            FROM Control_de_Ingesta__c
            WHERE Id = :control.Id
        ];
        Assert.areEqual('cursor-guardado', despues.Cursor__c, '429 no pierde el cursor');
        Assert.isTrue(despues.Ultimo_Error__c.contains('429'), 'Registra el 429');
        Assert.areEqual(0, [SELECT COUNT() FROM Senal__c], 'No guarda senales a medias');
    }

    @isTest
    static void shouldAbrirSesionNueva_When409() {
        Control_de_Ingesta__c control = [SELECT Id FROM Control_de_Ingesta__c LIMIT 1];
        control.Cursor__c = 'cursor-viejo';
        update control;

        IngestaSimuladorMock mock = new IngestaSimuladorMock();
        mock.primerGetEs409 = true;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new IngestaQueueable(0));
        Test.stopTest();

        Control_de_Ingesta__c despues = [
            SELECT Cursor__c, Paginas_Procesadas__c
            FROM Control_de_Ingesta__c
            WHERE Id = :control.Id
        ];
        Assert.areEqual('cursor-siguiente', despues.Cursor__c, 'Continua con la sesion nueva');
        Assert.areEqual(1, [SELECT COUNT() FROM Senal__c], 'Procesa la pagina posterior al 409');
        Assert.isTrue(mock.metodos.contains('POST'), 'Abre sesion nueva');
    }

    @isTest
    static void shouldCortarCadena_When401() {
        Control_de_Ingesta__c control = [SELECT Id FROM Control_de_Ingesta__c LIMIT 1];
        control.Cursor__c = 'cursor-guardado';
        update control;

        IngestaSimuladorMock mock = new IngestaSimuladorMock();
        mock.codigoTelemetria = 401;
        mock.cuerpoTelemetria = '{"type":"unauthorized","title":"Unauthorized","status":401,"detail":"token"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new IngestaQueueable(0));
        Test.stopTest();

        Control_de_Ingesta__c despues = [
            SELECT Cursor__c, Fallos_Consecutivos__c, Ultimo_Error__c
            FROM Control_de_Ingesta__c
            WHERE Id = :control.Id
        ];
        Assert.areEqual('cursor-guardado', despues.Cursor__c, 'No avanza');
        Assert.areEqual(1, despues.Fallos_Consecutivos__c.intValue(), 'Cuenta el fallo');
        Assert.isTrue(despues.Ultimo_Error__c.contains('401'), 'Registra 401');
    }

    @isTest
    static void shouldNoPerderCursor_WhenTiempoAgotado() {
        Control_de_Ingesta__c control = [SELECT Id FROM Control_de_Ingesta__c LIMIT 1];
        control.Cursor__c = 'cursor-guardado';
        update control;

        IngestaSimuladorMock mock = new IngestaSimuladorMock();
        mock.tiemposAgotadosPendientes = 2;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new IngestaQueueable(0));
        Test.stopTest();

        Control_de_Ingesta__c despues = [
            SELECT Cursor__c, Ultimo_Error__c
            FROM Control_de_Ingesta__c
            WHERE Id = :control.Id
        ];
        Assert.areEqual('cursor-guardado', despues.Cursor__c, 'Timeout no mueve el cursor');
        Assert.isTrue(despues.Ultimo_Error__c.contains('Tiempo agotado'), 'Registra timeout');
    }

    @isTest
    static void shouldRegistrarFallo_WhenCuerpoNoEsJson() {
        Control_de_Ingesta__c control = [SELECT Id FROM Control_de_Ingesta__c LIMIT 1];
        control.Cursor__c = 'cursor-guardado';
        update control;

        IngestaSimuladorMock mock = new IngestaSimuladorMock();
        mock.cuerpoTelemetria = 'no-es-json';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new IngestaQueueable(0));
        Test.stopTest();

        Control_de_Ingesta__c despues = [
            SELECT Fallos_Consecutivos__c, Ultimo_Error__c, Cursor__c
            FROM Control_de_Ingesta__c
            WHERE Id = :control.Id
        ];
        Assert.areEqual('cursor-guardado', despues.Cursor__c, 'No avanza si el cuerpo es inutil');
        Assert.isTrue(despues.Fallos_Consecutivos__c > 0, 'Cuenta el fallo');
        Assert.isTrue(String.isNotBlank(despues.Ultimo_Error__c), 'Registra el error');
    }

    @isTest
    static void shouldDetener_WhenIngestaInactiva() {
        Control_de_Ingesta__c control = [SELECT Id FROM Control_de_Ingesta__c LIMIT 1];
        control.Activo__c = false;
        update control;
        IngestaSimuladorMock mock = new IngestaSimuladorMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new IngestaQueueable(0));
        Test.stopTest();

        Assert.areEqual(0, mock.llamadas, 'No llama al simulador si esta apagada');
        Assert.areEqual(0, [SELECT COUNT() FROM Senal__c], 'No crea senales');
    }
}
