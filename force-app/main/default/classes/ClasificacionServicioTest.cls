/**
 * Fronteras cerradas de medicion y escalada de conectividad por minutos.
 */
@isTest
private class ClasificacionServicioTest {
    @TestSetup
    static void setup() {
        TestDataFactory.sembrarCatalogoMinimo();
    }

    @isTest
    static void shouldSerNormal_WhenPresionEnBanda() {
        Umbral__c umbral = umbralDe('WATER_PUMP|WATER_PRESSURE');
        Test.startTest();
        ClasificacionServicio.Dictamen d = ClasificacionServicio.clasificarMedicion(2.76, umbral);
        Test.stopTest();
        Assert.areEqual(IngestaConstantes.SEV_NORMAL, d.severidad, '2.76 BAR es normal');
        Assert.areEqual(0, d.nivel, 'Nivel 0');
        Assert.isTrue(d.esValido(), 'Sin motivo');
    }

    @isTest
    static void shouldSerAdvertencia_WhenFronteraInclusiva() {
        Umbral__c umbral = umbralDe('WATER_PUMP|WATER_PRESSURE');
        Test.startTest();
        ClasificacionServicio.Dictamen d = ClasificacionServicio.clasificarMedicion(4.01, umbral);
        Test.stopTest();
        Assert.areEqual(IngestaConstantes.SEV_ADVERTENCIA, d.severidad, '4.01 es el minimo de advertencia alta');
    }

    @isTest
    static void shouldSerCritico_WhenPorEncimaDelTecho() {
        Umbral__c umbral = umbralDe('TECHNICAL_ROOM|TEMPERATURE');
        Test.startTest();
        ClasificacionServicio.Dictamen d = ClasificacionServicio.clasificarMedicion(60.19, umbral);
        Test.stopTest();
        Assert.areEqual(IngestaConstantes.SEV_CRITICO, d.severidad, 'Hueco del catalogo sigue siendo critico');
    }

    @isTest
    static void shouldSerNormal_WhenLostCorto() {
        Umbral__c umbral = umbralDe('SECURITY_CAMERA|CAMERA_CONNECTIVITY');
        Test.startTest();
        ClasificacionServicio.Dictamen d = ClasificacionServicio.clasificarConectividad(
            'LOST',
            180,
            umbral
        );
        Test.stopTest();
        Assert.areEqual(IngestaConstantes.SEV_NORMAL, d.severidad, 'Tres minutos no despiertan');
    }

    @isTest
    static void shouldSerAdvertencia_WhenLostDeQuinceMinutos() {
        Umbral__c umbral = umbralDe('SECURITY_CAMERA|CAMERA_CONNECTIVITY');
        Test.startTest();
        ClasificacionServicio.Dictamen d = ClasificacionServicio.clasificarConectividad(
            'LOST',
            15 * 60,
            umbral
        );
        Test.stopTest();
        Assert.areEqual(IngestaConstantes.SEV_ADVERTENCIA, d.severidad, 'Exactamente 15 min ya es advertencia');
    }

    private static Umbral__c umbralDe(String clave) {
        return [
            SELECT Clave__c, Critico_Bajo__c, Critico_Alto__c, Advertencia_Bajo__c,
                   Advertencia_Alto__c, Minutos_Advertencia__c, Minutos_Critico__c, Unidad__c
            FROM Umbral__c
            WHERE Clave__c = :clave
        ];
    }
}
