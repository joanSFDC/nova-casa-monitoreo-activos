/**
 * Cerrar un incidente completa sus intervenciones abiertas, con el flujo
 * Completar_Intervenciones_Al_Cerrar, y no toca las de otros casos.
 */
@isTest
private class CierreIncidenteTest {
  @isTest
  static void shouldCompletarSusIntervenciones_WhenSeCierraElIncidente() {
    Case caso = caso('Bomba de prueba');
    Case otro = caso('Sala de prueba');
    Task abierta = tarea(caso.Id, 'Revisar el equipo en sitio', 'Not Started');
    Task enCurso = tarea(caso.Id, 'Cambiar una pieza', 'In Progress');
    Task ajena = tarea(otro.Id, 'Revisar el sensor', 'Not Started');
    insert new List<Task>{ abierta, enCurso, ajena };

    Test.startTest();
    update new Case(
      Id = caso.Id,
      Status = 'Closed',
      Resolucion__c = 'Se cambió el manómetro y la presión quedó normal.'
    );
    Test.stopTest();

    Map<Id, Task> despues = new Map<Id, Task>(
      [SELECT Id, Status, IsClosed FROM Task]
    );
    Assert.areEqual('Completed', despues.get(abierta.Id).Status);
    Assert.areEqual('Completed', despues.get(enCurso.Id).Status);
    Assert.areEqual(
      'Not Started',
      despues.get(ajena.Id).Status,
      'Las de otro incidente siguen abiertas'
    );
    Assert.areEqual(
      'Se cambió el manómetro y la presión quedó normal.',
      [SELECT Resolucion__c FROM Case WHERE Id = :caso.Id].Resolucion__c
    );
  }

  @isTest
  static void shouldDejarLasIntervenciones_WhenElIncidenteSigueAbierto() {
    Case caso = caso('Bomba de prueba');
    Task abierta = tarea(caso.Id, 'Revisar el equipo en sitio', 'Not Started');
    insert abierta;

    Test.startTest();
    update new Case(Id = caso.Id, Status = 'On Hold');
    Test.stopTest();

    Assert.areEqual(
      'Not Started',
      [SELECT Status FROM Task WHERE Id = :abierta.Id].Status,
      'Solo el cierre completa las intervenciones'
    );
  }

  private static Case caso(String asunto) {
    Case caso = new Case(
      Subject = asunto,
      Status = 'New',
      Origin = 'Web',
      Priority = 'High'
    );
    insert caso;
    return caso;
  }

  private static Task tarea(Id casoId, String asunto, String estado) {
    return new Task(
      WhatId = casoId,
      Subject = asunto,
      Status = estado,
      Priority = 'High',
      ActivityDate = Date.today().addDays(2)
    );
  }
}
