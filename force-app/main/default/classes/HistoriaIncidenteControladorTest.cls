/**
 * Historia del incidente: intervenciones abiertas primero, linea de tiempo del
 * mas reciente al mas viejo, el sistema con su nombre y el tope de eventos.
 * CaseHistory no se escribe en pruebas, asi que el historial entra simulado.
 */
@isTest
private class HistoriaIncidenteControladorTest {
  @isTest
  static void shouldDevolverNull_WhenNoHayCaso() {
    Assert.isNull(
      HistoriaIncidenteControlador.historia(null, null),
      'Sin caso no hay historia'
    );
  }

  @isTest
  static void shouldPonerAbiertasYOrdenarEventos_WhenHayIntervencionesYCambios() {
    Case caso = caso();
    Datetime ahora = Datetime.now();
    insert new List<Task>{
      tarea(
        caso.Id,
        'Revisar la bomba',
        'Not Started',
        Date.today().addDays(2)
      ),
      tarea(
        caso.Id,
        'Llamar al proveedor',
        'Not Started',
        Date.today().addDays(1)
      ),
      tarea(caso.Id, 'Cambiar el manometro', 'Completed', Date.today())
    };
    HistoriaIncidenteControlador.historialSimulado = new List<HistoriaIncidenteControlador.FilaHistorial>{
      fila(
        HistoriaIncidenteControlador.CAMPO_CREADO,
        null,
        null,
        ahora.addDays(-3),
        null
      ),
      fila(
        'Condicion_Equipo__c',
        'Normalizado',
        'En falla',
        ahora.addHours(-2),
        null
      ),
      fila('Priority', 'Low', 'High', ahora.addHours(-1), null)
    };

    Test.startTest();
    HistoriaIncidenteControlador.HistoriaDTO historia = HistoriaIncidenteControlador.historia(
      caso.Id,
      null
    );
    Test.stopTest();

    Assert.areEqual(2, historia.abiertas.size(), 'Dos abiertas');
    Assert.areEqual(
      'Llamar al proveedor',
      historia.abiertas[0].asunto,
      'Primero la que vence antes'
    );
    Assert.areEqual(4, historia.eventos.size(), 'Tres cambios y una cerrada');
    Assert.areEqual(
      HistoriaIncidenteControlador.TIPO_INTERVENCION,
      historia.eventos[0].tipo,
      'La intervencion cerrada es lo mas reciente'
    );
    Assert.isTrue(
      historia.eventos[0].texto.contains('Cambiar el manometro'),
      'Dice cual intervencion'
    );
    HistoriaIncidenteControlador.EventoDTO prioridad = historia.eventos[1];
    Assert.areEqual(
      HistoriaIncidenteControlador.TIPO_CRITICO,
      prioridad.tipo,
      'Subir a alta es critico'
    );
    Assert.areEqual(
      Case.Priority.getDescribe().getLabel(),
      prioridad.campo,
      'La etiqueta del campo'
    );
    Assert.areEqual(etiqueta(Case.Priority, 'Low'), prioridad.antes, 'Antes');
    Assert.areEqual(
      etiqueta(Case.Priority, 'High'),
      prioridad.despues,
      'Despues'
    );
    Assert.areEqual(
      HistoriaIncidenteControlador.TIPO_CAMBIO,
      historia.eventos[2].tipo,
      'La condicion es un cambio'
    );
    Assert.areEqual(
      HistoriaIncidenteControlador.TIPO_APERTURA,
      historia.eventos[3].tipo,
      'Lo mas viejo es la apertura'
    );
    Assert.isFalse(historia.hayMas, 'No hay mas');
  }

  @isTest
  static void shouldMostrarSistema_WhenLoHizoLaIntegracion() {
    User integracion = TestDataFactory.usuarioDeIntegracion();
    Case caso;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      caso = caso();
    }
    HistoriaIncidenteControlador.historialSimulado = new List<HistoriaIncidenteControlador.FilaHistorial>{
      fila('Priority', 'Low', 'High', Datetime.now(), integracion.Id),
      fila(
        'Status',
        'New',
        'Working',
        Datetime.now().addMinutes(-1),
        UserInfo.getUserId()
      )
    };
    HistoriaIncidenteControlador.historialSimulado[1]
      .autorNombre = 'Coordinador';

    Test.startTest();
    HistoriaIncidenteControlador.HistoriaDTO historia = HistoriaIncidenteControlador.historia(
      caso.Id,
      null
    );
    Test.stopTest();

    Assert.areEqual(
      HistoriaIncidenteControlador.SISTEMA,
      historia.eventos[0].quien,
      'La integracion es el sistema'
    );
    Assert.areEqual(
      'Coordinador',
      historia.eventos[1].quien,
      'Una persona con su nombre'
    );
  }

  @isTest
  static void shouldCortarEnElTope_WhenHayMasEventos() {
    Case caso = caso();
    List<HistoriaIncidenteControlador.FilaHistorial> filas = new List<HistoriaIncidenteControlador.FilaHistorial>();
    for (Integer i = 0; i < 15; i++) {
      filas.add(
        fila('Status', 'New', 'Working', Datetime.now().addMinutes(-i), null)
      );
    }
    HistoriaIncidenteControlador.historialSimulado = filas;

    Test.startTest();
    HistoriaIncidenteControlador.HistoriaDTO primera = HistoriaIncidenteControlador.historia(
      caso.Id,
      null
    );
    HistoriaIncidenteControlador.HistoriaDTO toda = HistoriaIncidenteControlador.historia(
      caso.Id,
      HistoriaIncidenteControlador.TOPE_MAXIMO
    );
    Test.stopTest();

    Assert.areEqual(
      HistoriaIncidenteControlador.TOPE_INICIAL,
      primera.eventos.size(),
      'Primero diez'
    );
    Assert.isTrue(primera.hayMas, 'Avisa que hay mas');
    Assert.areEqual(15, toda.eventos.size(), 'Toda la historia');
    Assert.isFalse(toda.hayMas, 'Ya no hay mas');
  }

  @isTest
  static void shouldDevolverNull_WhenNoPuedeVerElCaso() {
    User operador = TestDataFactory.usuarioConConjunto('Nova_Casa_Operador');
    Case caso;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      caso = caso();
    }

    HistoriaIncidenteControlador.HistoriaDTO historia;
    Test.startTest();
    System.runAs(operador) {
      historia = HistoriaIncidenteControlador.historia(caso.Id, null);
    }
    Test.stopTest();

    Assert.isNull(historia, 'Un caso ajeno no delata que existe');
  }

  private static Case caso() {
    Case caso = new Case(Subject = 'Lectura fuera de rango de prueba');
    insert caso;
    return caso;
  }

  private static Task tarea(
    Id casoId,
    String asunto,
    String estado,
    Date vence
  ) {
    return new Task(
      WhatId = casoId,
      Subject = asunto,
      Status = estado,
      Priority = 'High',
      ActivityDate = vence
    );
  }

  private static HistoriaIncidenteControlador.FilaHistorial fila(
    String campo,
    String antes,
    String despues,
    Datetime fecha,
    Id autorId
  ) {
    HistoriaIncidenteControlador.FilaHistorial fila = new HistoriaIncidenteControlador.FilaHistorial();
    fila.campo = campo;
    fila.antes = antes;
    fila.despues = despues;
    fila.fecha = fecha;
    fila.autorId = autorId;
    fila.autorNombre = 'Alguien';
    return fila;
  }

  private static String etiqueta(Schema.SObjectField campo, String valor) {
    for (
      Schema.PicklistEntry entrada : campo.getDescribe().getPicklistValues()
    ) {
      if (entrada.getValue() == valor) {
        return entrada.getLabel();
      }
    }
    return valor;
  }
}
