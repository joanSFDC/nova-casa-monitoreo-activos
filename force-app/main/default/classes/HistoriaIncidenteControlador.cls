/**
 * La historia de un incidente para su pagina: las intervenciones abiertas y una
 * linea de tiempo con los cambios del caso y las intervenciones cerradas.
 * with sharing y USER_MODE, como los resumenes: un caso que no se puede ver
 * devuelve null, no un error que delate que existe.
 */
public with sharing class HistoriaIncidenteControlador {
  public static final Integer TOPE_INICIAL = 10;
  public static final Integer TOPE_MAXIMO = 100;
  public static final Integer TOPE_ABIERTAS = 50;
  public static final String SISTEMA = 'Sistema';
  public static final String TIPO_APERTURA = 'apertura';
  public static final String TIPO_CAMBIO = 'cambio';
  public static final String TIPO_CRITICO = 'critico';
  public static final String TIPO_INTERVENCION = 'intervencion';

  @TestVisible
  static final String CONJUNTO_INTEGRACION = 'Nova_Casa_Integracion';
  @TestVisible
  static final String CAMPO_CREADO = 'created';
  private static final String USUARIO_AUTOMATICO = 'AutomatedProcess';
  private static final List<String> CAMPOS = new List<String>{
    CAMPO_CREADO,
    'Priority',
    'Status',
    'Severidad_Ultima_Lectura__c',
    'Condicion_Equipo__c'
  };

  public class IntervencionDTO {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String asunto;
    @AuraEnabled
    public String responsable;
    @AuraEnabled
    public String estado;
    @AuraEnabled
    public Date fechaLimite;
    @AuraEnabled
    public String prioridad;
  }

  public class EventoDTO {
    @AuraEnabled
    public String clave;
    @AuraEnabled
    public String tipo;
    @AuraEnabled
    public Datetime fecha;
    @AuraEnabled
    public String campo;
    @AuraEnabled
    public String antes;
    @AuraEnabled
    public String despues;
    @AuraEnabled
    public String texto;
    @AuraEnabled
    public String quien;
  }

  public class HistoriaDTO {
    @AuraEnabled
    public List<IntervencionDTO> abiertas = new List<IntervencionDTO>();
    @AuraEnabled
    public List<EventoDTO> eventos = new List<EventoDTO>();
    @AuraEnabled
    public Boolean hayMas = false;
  }

  /**
   * Una fila del historial del caso. CaseHistory no deja escribir sus valores,
   * asi que las pruebas entran por aqui.
   */
  @TestVisible
  class FilaHistorial {
    public String campo;
    public Object antes;
    public Object despues;
    public Datetime fecha;
    public Id autorId;
    public String autorNombre;
  }

  @TestVisible
  static List<FilaHistorial> historialSimulado;

  /**
   * @param casoId El incidente
   * @param tope Cuantos eventos devolver; se acota entre 1 y TOPE_MAXIMO
   * @return La historia, o null si el caso no existe o no se puede ver
   */
  @AuraEnabled(cacheable=true)
  public static HistoriaDTO historia(Id casoId, Integer tope) {
    if (casoId == null) {
      return null;
    }
    if ([SELECT COUNT() FROM Case WHERE Id = :casoId WITH USER_MODE] == 0) {
      return null;
    }
    Integer limite = tope == null ||
      tope < 1
      ? TOPE_INICIAL
      : Math.min(tope, TOPE_MAXIMO);
    Integer conUnoMas = limite + 1;

    HistoriaDTO dto = new HistoriaDTO();
    List<EventoDTO> eventos = new List<EventoDTO>();
    Set<Id> idsSistema = usuariosDeSistema();

    for (Task tarea : [
      SELECT Id, Subject, Status, ActivityDate, Priority, Owner.Name
      FROM Task
      WHERE WhatId = :casoId AND IsClosed = FALSE
      WITH USER_MODE
      ORDER BY ActivityDate ASC NULLS LAST, CreatedDate ASC
      LIMIT :TOPE_ABIERTAS
    ]) {
      dto.abiertas.add(intervencionDe(tarea));
    }

    for (Task tarea : [
      SELECT
        Id,
        Subject,
        CompletedDateTime,
        LastModifiedDate,
        LastModifiedById,
        LastModifiedBy.Name
      FROM Task
      WHERE WhatId = :casoId AND IsClosed = TRUE
      WITH USER_MODE
      ORDER BY LastModifiedDate DESC
      LIMIT :conUnoMas
    ]) {
      eventos.add(intervencionCerrada(tarea, idsSistema));
    }

    for (FilaHistorial fila : historial(casoId, conUnoMas)) {
      eventos.add(eventoDe(fila, idsSistema));
    }

    eventos.sort(new MasRecientePrimero());
    for (Integer i = 0; i < eventos.size() && i < limite; i++) {
      dto.eventos.add(eventos[i]);
    }
    dto.hayMas = eventos.size() > limite;
    return dto;
  }

  private static List<FilaHistorial> historial(Id casoId, Integer limite) {
    if (historialSimulado != null) {
      return historialSimulado;
    }
    List<FilaHistorial> filas = new List<FilaHistorial>();
    for (CaseHistory registro : [
      SELECT Field, OldValue, NewValue, CreatedDate, CreatedById, CreatedBy.Name
      FROM CaseHistory
      WHERE CaseId = :casoId AND Field IN :CAMPOS
      WITH USER_MODE
      ORDER BY CreatedDate DESC, Id DESC
      LIMIT :limite
    ]) {
      FilaHistorial fila = new FilaHistorial();
      fila.campo = registro.Field;
      fila.antes = registro.OldValue;
      fila.despues = registro.NewValue;
      fila.fecha = registro.CreatedDate;
      fila.autorId = registro.CreatedById;
      fila.autorNombre = registro.CreatedBy?.Name;
      filas.add(fila);
    }
    return filas;
  }

  private static IntervencionDTO intervencionDe(Task tarea) {
    IntervencionDTO dto = new IntervencionDTO();
    dto.id = tarea.Id;
    dto.asunto = tarea.Subject;
    dto.responsable = tarea.Owner?.Name;
    dto.estado = etiqueta(Task.Status, tarea.Status);
    dto.fechaLimite = tarea.ActivityDate;
    dto.prioridad = etiqueta(Task.Priority, tarea.Priority);
    return dto;
  }

  private static EventoDTO intervencionCerrada(Task tarea, Set<Id> idsSistema) {
    EventoDTO dto = new EventoDTO();
    dto.clave = tarea.Id;
    dto.tipo = TIPO_INTERVENCION;
    dto.fecha = tarea.CompletedDateTime ?? tarea.LastModifiedDate;
    dto.texto = 'Intervención completada: «' + tarea.Subject + '»';
    dto.quien = autor(
      tarea.LastModifiedById,
      tarea.LastModifiedBy?.Name,
      idsSistema
    );
    return dto;
  }

  @TestVisible
  static EventoDTO eventoDe(FilaHistorial fila, Set<Id> idsSistema) {
    EventoDTO dto = new EventoDTO();
    dto.fecha = fila.fecha;
    dto.clave =
      fila.campo +
      '|' +
      String.valueOf(fila.fecha?.getTime()) +
      '|' +
      fila.autorId;
    dto.quien = autor(fila.autorId, fila.autorNombre, idsSistema);
    if (fila.campo == CAMPO_CREADO) {
      dto.tipo = TIPO_APERTURA;
      dto.texto = 'Se abrió el incidente';
      return dto;
    }
    Schema.SObjectField campo = Case.SObjectType.getDescribe()
      .fields.getMap()
      .get(fila.campo);
    dto.campo = campo == null ? fila.campo : campo.getDescribe().getLabel();
    dto.antes = etiqueta(campo, texto(fila.antes));
    dto.despues = etiqueta(campo, texto(fila.despues));
    dto.tipo = esCritico(fila) ? TIPO_CRITICO : TIPO_CAMBIO;
    return dto;
  }

  private static Boolean esCritico(FilaHistorial fila) {
    String despues = texto(fila.despues);
    return (fila.campo == 'Priority' &&
      despues == IncidentesServicio.PRIORIDAD_ALTA) ||
      (fila.campo == 'Severidad_Ultima_Lectura__c' &&
      despues == IngestaConstantes.SEV_CRITICO);
  }

  private static String autor(Id autorId, String nombre, Set<Id> idsSistema) {
    if (idsSistema.contains(autorId)) {
      return SISTEMA;
    }
    return nombre;
  }

  /**
   * Quien tiene el conjunto de integracion y el proceso automatico de los flujos
   * escriben por el sistema. Se consulta en modo sistema porque solo devuelve
   * identificadores de usuario.
   */
  private static Set<Id> usuariosDeSistema() {
    Set<Id> ids = new Set<Id>();
    for (PermissionSetAssignment asignacion : [
      SELECT AssigneeId
      FROM PermissionSetAssignment
      WHERE PermissionSet.Name = :CONJUNTO_INTEGRACION
      WITH SYSTEM_MODE
    ]) {
      ids.add(asignacion.AssigneeId);
    }
    ids.addAll(
      new Map<Id, User>(
          [
            SELECT Id
            FROM User
            WHERE UserType = :USUARIO_AUTOMATICO
            WITH SYSTEM_MODE
          ]
        )
        .keySet()
    );
    return ids;
  }

  private static String texto(Object valor) {
    return valor == null ? null : String.valueOf(valor);
  }

  private static String etiqueta(Schema.SObjectField campo, String valor) {
    if (campo == null || String.isBlank(valor)) {
      return valor;
    }
    for (
      Schema.PicklistEntry entrada : campo.getDescribe().getPicklistValues()
    ) {
      if (entrada.getValue() == valor) {
        return entrada.getLabel();
      }
    }
    return valor;
  }

  private class MasRecientePrimero implements System.Comparator<EventoDTO> {
    public Integer compare(EventoDTO a, EventoDTO b) {
      Long fa = a.fecha == null ? 0 : a.fecha.getTime();
      Long fb = b.fecha == null ? 0 : b.fecha.getTime();
      if (fa == fb) {
        return 0;
      }
      return fa > fb ? -1 : 1;
    }
  }
}
