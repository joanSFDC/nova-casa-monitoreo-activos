/**
 * El Schedulable solo encola. La cadena vive en IngestaQueueable.
 */
@isTest
private class IngestaSchedulableTest {
    @TestSetup
    static void setup() {
        TestDataFactory.sembrarCatalogoMinimo();
        TestDataFactory.crearControl(true);
    }

    @isTest
    static void shouldEncolarQueueable_WhenSeDispara() {
        IngestaSimuladorMock mock = new IngestaSimuladorMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new IngestaSchedulable().execute(null);
        Test.stopTest();
        Assert.areEqual(1, [SELECT COUNT() FROM Senal__c], 'El execute encola y corre el queueable');
    }

    @isTest
    static void shouldProgramarCadaMinuto_WhenSeLlama() {
        Test.startTest();
        List<String> ids = IngestaSchedulable.programarCadaMinuto();
        Test.stopTest();
        Assert.areEqual(60, ids.size(), 'Un trabajo por minuto');
        IngestaSchedulable.abortar();
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Nova Casa Ingesta%'],
            'Abortar limpia los sesenta'
        );
    }

    @isTest
    static void shouldProgramarYAbortar_WhenSeLlama() {
        Test.startTest();
        String jobId = IngestaSchedulable.programarCadaHora();
        Assert.isNotNull(jobId, 'Queda un CronTrigger');
        IngestaSchedulable.abortar();
        Test.stopTest();
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Nova Casa Ingesta%'],
            'Abortar limpia los trabajos'
        );
    }
}
