/**
 * Pantalla del operador (US-207). with sharing y USER_MODE: solo ve sus edificios.
 * No consulta Senal__c. Los contadores se calculan aqui, no en el navegador.
 */
public with sharing class MonitorControlador {
  public static final Integer MINUTOS_CONSULTA_ATRASADA = 5;

  public class PanelDTO {
    @AuraEnabled
    public Integer criticos;
    @AuraEnabled
    public Integer advertencias;
    @AuraEnabled
    public Integer normales;
    @AuraEnabled
    public Boolean sinEdificios;
    @AuraEnabled
    public Boolean sinLecturas;
    @AuraEnabled
    public Boolean consultaAtrasada;
    @AuraEnabled
    public Datetime ultimaConsultaExitosa;
    @AuraEnabled
    public List<EdificioDTO> edificios;
    @AuraEnabled
    public List<FilaDTO> filas;
  }

  public class EdificioDTO {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String nombre;
  }

  public class FilaDTO {
    @AuraEnabled
    public Id estadoId;
    @AuraEnabled
    public Id activoId;
    @AuraEnabled
    public Id casoId;
    @AuraEnabled
    public String edificio;
    @AuraEnabled
    public String equipo;
    @AuraEnabled
    public String medicion;
    @AuraEnabled
    public String valor;
    @AuraEnabled
    public String severidad;
    @AuraEnabled
    public Integer severidadNivel;
    @AuraEnabled
    public String severidadEtiqueta;
    @AuraEnabled
    public Boolean puedeIntervenir;
    @AuraEnabled
    public String antiguedad;
    @AuraEnabled
    public String comunicacion;
  }

  public class IncidenteDTO {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String asunto;
    @AuraEnabled
    public String estado;
    @AuraEnabled
    public String prioridad;
    @AuraEnabled
    public String propietario;
    @AuraEnabled
    public String equipo;
    @AuraEnabled
    public String medicion;
    @AuraEnabled
    public String descripcion;
    @AuraEnabled
    public List<ActividadDTO> actividades;
  }

  public class ActividadDTO {
    @AuraEnabled
    public String cuando;
    @AuraEnabled
    public String autor;
    @AuraEnabled
    public String texto;
  }

  @AuraEnabled(cacheable=true)
  public static PanelDTO obtenerPanel(String edificioId) {
    PanelDTO panel = new PanelDTO();
    panel.criticos = 0;
    panel.advertencias = 0;
    panel.normales = 0;
    panel.sinEdificios = false;
    panel.sinLecturas = false;
    panel.consultaAtrasada = false;
    panel.edificios = new List<EdificioDTO>();
    panel.filas = new List<FilaDTO>();

    List<Edificio__c> edificios = [
      SELECT Id, Name
      FROM Edificio__c
      WITH USER_MODE
      ORDER BY Name
    ];
    if (edificios.isEmpty()) {
      panel.sinEdificios = true;
      rellenarIngesta(panel);
      return panel;
    }
    for (Edificio__c edificio : edificios) {
      EdificioDTO dto = new EdificioDTO();
      dto.id = edificio.Id;
      dto.nombre = edificio.Name;
      panel.edificios.add(dto);
    }

    List<Estado_Actual__c> estados;
    if (String.isBlank(edificioId)) {
      estados = [
        SELECT
          Id,
          Tipo_Medicion__c,
          Valor__c,
          Unidad__c,
          Severidad__c,
          Severidad_Nivel__c,
          Fecha_Origen__c,
          Estado_Comunicacion__c,
          Gap_Segundos__c,
          Episodio_Id__c,
          Activo__c,
          Activo__r.Name,
          Activo__r.Codigo_Externo__c,
          Activo__r.Tipo__c,
          Activo__r.Edificio__c,
          Activo__r.Edificio__r.Name
        FROM Estado_Actual__c
        WITH USER_MODE
        ORDER BY Severidad_Nivel__c DESC, Fecha_Origen__c ASC
      ];
    } else {
      estados = [
        SELECT
          Id,
          Tipo_Medicion__c,
          Valor__c,
          Unidad__c,
          Severidad__c,
          Severidad_Nivel__c,
          Fecha_Origen__c,
          Estado_Comunicacion__c,
          Gap_Segundos__c,
          Episodio_Id__c,
          Activo__c,
          Activo__r.Name,
          Activo__r.Codigo_Externo__c,
          Activo__r.Tipo__c,
          Activo__r.Edificio__c,
          Activo__r.Edificio__r.Name
        FROM Estado_Actual__c
        WHERE Activo__r.Edificio__c = :edificioId
        WITH USER_MODE
        ORDER BY Severidad_Nivel__c DESC, Fecha_Origen__c ASC
      ];
    }
    if (estados.isEmpty()) {
      panel.sinLecturas = true;
      rellenarIngesta(panel);
      return panel;
    }

    Map<String, Integer> decimales = decimalesPorClave();
    Map<String, Id> casosAbiertos = casosPorClave(estados);
    Datetime ahora = Datetime.now();
    for (Estado_Actual__c estado : estados) {
      FilaDTO fila = filaDe(estado, decimales, casosAbiertos, ahora);
      panel.filas.add(fila);
      if (fila.severidadNivel == 2) {
        panel.criticos++;
      } else if (fila.severidadNivel == 1) {
        panel.advertencias++;
      } else {
        panel.normales++;
      }
    }
    rellenarIngesta(panel);
    return panel;
  }

  @AuraEnabled(cacheable=true)
  public static IncidenteDTO obtenerIncidente(Id casoId) {
    if (casoId == null) {
      throw new AuraHandledException('Falta el incidente.');
    }
    List<Case> casos = [
      SELECT
        Id,
        Subject,
        Status,
        Priority,
        Description,
        Owner.Name,
        Activo__r.Name,
        Tipo_Medicion__c
      FROM Case
      WHERE Id = :casoId
      WITH USER_MODE
      LIMIT 1
    ];
    if (casos.isEmpty()) {
      throw new AuraHandledException(
        'No tienes acceso a este incidente o no existe.'
      );
    }
    Case incidente = casos[0];
    IncidenteDTO dto = new IncidenteDTO();
    dto.id = incidente.Id;
    dto.asunto = incidente.Subject;
    dto.estado = incidente.Status;
    dto.prioridad = incidente.Priority;
    dto.descripcion = incidente.Description;
    dto.propietario = incidente.Owner == null ? null : incidente.Owner.Name;
    dto.equipo = incidente.Activo__r == null ? null : incidente.Activo__r.Name;
    dto.medicion = etiquetaMedicion(incidente.Tipo_Medicion__c);
    dto.actividades = new List<ActividadDTO>();
    for (Task tarea : [
      SELECT Subject, Description, CreatedDate, CreatedBy.Name
      FROM Task
      WHERE WhatId = :casoId
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 20
    ]) {
      ActividadDTO actividad = new ActividadDTO();
      actividad.cuando = antiguedadDe(tarea.CreatedDate, Datetime.now());
      actividad.autor = tarea.CreatedBy.Name;
      actividad.texto = String.isBlank(tarea.Description)
        ? tarea.Subject
        : tarea.Description;
      dto.actividades.add(actividad);
    }
    return dto;
  }

  @AuraEnabled
  public static Id abrirIntervencion(Id estadoId, String nota) {
    if (estadoId == null) {
      throw new AuraHandledException('Falta el estado actual.');
    }
    List<Estado_Actual__c> estados = [
      SELECT
        Id,
        Tipo_Medicion__c,
        Episodio_Id__c,
        Severidad_Nivel__c,
        Estado_Comunicacion__c,
        Activo__c,
        Activo__r.Codigo_Externo__c
      FROM Estado_Actual__c
      WHERE Id = :estadoId
      WITH USER_MODE
      LIMIT 1
    ];
    if (estados.isEmpty()) {
      throw new AuraHandledException(
        'No tienes acceso a este equipo o no existe.'
      );
    }
    Estado_Actual__c estado = estados[0];
    String clave = claveDe(estado);
    if (String.isBlank(clave)) {
      throw new AuraHandledException(
        'No se pudo armar la clave del incidente.'
      );
    }
    Boolean sano =
      (estado.Severidad_Nivel__c == null || estado.Severidad_Nivel__c == 0) &&
      comunicacionDe(estado.Estado_Comunicacion__c) == null;
    List<Case> abiertos = [
      SELECT Id
      FROM Case
      WHERE Clave_Abierta__c = :clave AND IsClosed = FALSE
      WITH USER_MODE
      LIMIT 1
    ];
    if (!abiertos.isEmpty()) {
      return abiertos[0].Id;
    }
    if (sano) {
      throw new AuraHandledException(
        'Este equipo est\u00e1 normal: no hay nada que intervenir.'
      );
    }

    Case incidente = new Case();
    incidente.Clave_Abierta__c = clave;
    incidente.Activo__c = estado.Activo__c;
    incidente.Tipo_Medicion__c = estado.Tipo_Medicion__c;
    incidente.Episodio_Id__c = estado.Episodio_Id__c;
    incidente.Status = 'New';
    incidente.Origin = 'Web';
    incidente.Priority = estado.Severidad_Nivel__c == 2 ? 'High' : 'Low';
    incidente.Subject = String.isNotBlank(estado.Episodio_Id__c)
      ? 'Corte de comunicacion ' + estado.Episodio_Id__c
      : 'Lectura fuera de rango ' + clave;
    incidente.Description = nota;
    Database.SaveResult resultado = Database.insert(
      incidente,
      false,
      AccessLevel.USER_MODE
    );
    if (resultado.isSuccess()) {
      if (String.isNotBlank(nota)) {
        Task tarea = new Task();
        tarea.WhatId = resultado.getId();
        tarea.Subject = 'Nota del operador';
        tarea.Description = nota;
        tarea.Status = 'Completed';
        Database.insert(tarea, false, AccessLevel.USER_MODE);
      }
      return resultado.getId();
    }
    for (Database.Error error : resultado.getErrors()) {
      if (error.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
        List<Case> ganador = [
          SELECT Id
          FROM Case
          WHERE Clave_Abierta__c = :clave AND IsClosed = FALSE
          WITH USER_MODE
          LIMIT 1
        ];
        if (!ganador.isEmpty()) {
          return ganador[0].Id;
        }
      }
    }
    throw new AuraHandledException(
      'No se pudo abrir la intervencion. Si no tienes permiso, habla con tu coordinador.'
    );
  }

  private static void rellenarIngesta(PanelDTO panel) {
    List<Control_de_Ingesta__c> controles;
    try {
      controles = [
        SELECT Ultima_Consulta_Exitosa__c
        FROM Control_de_Ingesta__c
        WITH USER_MODE
        ORDER BY LastModifiedDate DESC
        LIMIT 1
      ];
    } catch (Exception e) {
      return;
    }
    if (controles == null || controles.isEmpty()) {
      return;
    }
    panel.ultimaConsultaExitosa = controles[0].Ultima_Consulta_Exitosa__c;
    if (panel.ultimaConsultaExitosa == null) {
      panel.consultaAtrasada = true;
      return;
    }
    panel.consultaAtrasada =
      panel.ultimaConsultaExitosa.addMinutes(MINUTOS_CONSULTA_ATRASADA) <
      Datetime.now();
  }

  private static Map<String, Integer> decimalesPorClave() {
    Map<String, Integer> mapa = new Map<String, Integer>();
    for (Umbral__c umbral : [
      SELECT Clave__c, Decimales__c
      FROM Umbral__c
      WHERE Vigente__c = TRUE
      WITH USER_MODE
    ]) {
      mapa.put(
        umbral.Clave__c,
        umbral.Decimales__c == null ? 0 : Integer.valueOf(umbral.Decimales__c)
      );
    }
    return mapa;
  }

  private static Map<String, Id> casosPorClave(List<Estado_Actual__c> estados) {
    Set<String> claves = new Set<String>();
    for (Estado_Actual__c estado : estados) {
      String clave = claveDe(estado);
      if (String.isNotBlank(clave)) {
        claves.add(clave);
      }
    }
    Map<String, Id> mapa = new Map<String, Id>();
    if (claves.isEmpty()) {
      return mapa;
    }
    for (Case incidente : [
      SELECT Id, Clave_Abierta__c
      FROM Case
      WHERE Clave_Abierta__c IN :claves AND IsClosed = FALSE
      WITH USER_MODE
    ]) {
      mapa.put(incidente.Clave_Abierta__c, incidente.Id);
    }
    return mapa;
  }

  private static FilaDTO filaDe(
    Estado_Actual__c estado,
    Map<String, Integer> decimales,
    Map<String, Id> casosAbiertos,
    Datetime ahora
  ) {
    FilaDTO fila = new FilaDTO();
    fila.estadoId = estado.Id;
    fila.activoId = estado.Activo__c;
    fila.edificio = estado.Activo__r.Edificio__r.Name;
    fila.equipo = estado.Activo__r.Name;
    fila.medicion = etiquetaMedicion(estado.Tipo_Medicion__c);
    fila.severidad = estado.Severidad__c;
    fila.severidadNivel = estado.Severidad_Nivel__c == null
      ? 0
      : Integer.valueOf(estado.Severidad_Nivel__c);
    fila.severidadEtiqueta = etiquetaSeveridad(fila.severidadNivel);
    fila.antiguedad = antiguedadDe(estado.Fecha_Origen__c, ahora);
    fila.comunicacion = comunicacionDe(estado.Estado_Comunicacion__c);
    fila.valor = valorDe(estado, decimales);
    String clave = claveDe(estado);
    fila.casoId = casosAbiertos.get(clave);
    fila.puedeIntervenir =
      fila.casoId != null ||
      (String.isNotBlank(clave) &&
      (fila.severidadNivel > 0 ||
      fila.comunicacion != null));
    return fila;
  }

  private static String claveDe(Estado_Actual__c estado) {
    if (estado.Tipo_Medicion__c == 'CAMERA_CONNECTIVITY') {
      return String.isBlank(estado.Episodio_Id__c)
        ? null
        : IncidentesServicio.PREFIJO_CONN + estado.Episodio_Id__c;
    }
    if (
      estado.Activo__r == null ||
      String.isBlank(estado.Activo__r.Codigo_Externo__c) ||
      String.isBlank(estado.Tipo_Medicion__c)
    ) {
      return null;
    }
    return estado.Activo__r.Codigo_Externo__c + '|' + estado.Tipo_Medicion__c;
  }

  private static String valorDe(
    Estado_Actual__c estado,
    Map<String, Integer> decimales
  ) {
    if (estado.Tipo_Medicion__c == 'CAMERA_CONNECTIVITY') {
      if (estado.Gap_Segundos__c == null) {
        return '—';
      }
      return String.valueOf(estado.Gap_Segundos__c.intValue()) + ' s';
    }
    if (estado.Valor__c == null) {
      return '—';
    }
    String claveUmbral =
      (estado.Activo__r == null ? '' : estado.Activo__r.Tipo__c) +
      '|' +
      estado.Tipo_Medicion__c;
    Integer lugares = decimales.containsKey(claveUmbral)
      ? decimales.get(claveUmbral)
      : 0;
    String numero = conDecimales(estado.Valor__c, lugares);
    String unidad = etiquetaUnidad(estado.Unidad__c);
    return String.isBlank(unidad) ? numero : numero + ' ' + unidad;
  }

  // format() respeta la configuracion regional pero borra los ceros finales.
  @TestVisible
  static String conDecimales(Decimal valor, Integer lugares) {
    String numero = valor.setScale(lugares).format();
    if (lugares <= 0) {
      return numero;
    }
    String separador = Decimal.valueOf('1.5').format().substring(1, 2);
    Integer posicion = numero.lastIndexOf(separador);
    if (posicion < 0) {
      numero += separador;
      posicion = numero.length() - 1;
    }
    Integer faltan = lugares - (numero.length() - posicion - 1);
    for (Integer i = 0; i < faltan; i++) {
      numero += '0';
    }
    return numero;
  }

  private static String comunicacionDe(String estado) {
    if (String.isBlank(estado) || estado == 'HEALTHY') {
      return null;
    }
    if (estado == 'LOST') {
      return 'Sin comunicaci\u00f3n';
    }
    if (estado == 'RESTORED') {
      return 'Recuperada';
    }
    return estado;
  }

  @TestVisible
  static String antiguedadDe(Datetime origen, Datetime ahora) {
    if (origen == null || ahora == null) {
      return 'Sin fecha';
    }
    Long segundos = (ahora.getTime() - origen.getTime()) / 1000;
    if (segundos < 60) {
      return 'hace un momento';
    }
    Long minutos = segundos / 60;
    if (minutos < 60) {
      return 'hace ' + minutos + ' min';
    }
    Long horas = minutos / 60;
    if (horas < 24) {
      return 'hace ' + horas + ' h';
    }
    return 'hace ' + (horas / 24) + ' d';
  }

  private static String etiquetaMedicion(String tipo) {
    Map<String, String> etiquetas = new Map<String, String>{
      'TEMPERATURE' => 'Temperatura',
      'WATER_PRESSURE' => 'Presi\u00f3n de agua',
      'WATER_CONSUMPTION' => 'Consumo de agua',
      'ENERGY_CONSUMPTION' => 'Consumo de energ\u00eda',
      'CAMERA_CONNECTIVITY' => 'Conectividad'
    };
    return etiquetas.containsKey(tipo) ? etiquetas.get(tipo) : tipo;
  }

  private static String etiquetaSeveridad(Integer nivel) {
    if (nivel == 2) {
      return 'Cr\u00edtico';
    }
    if (nivel == 1) {
      return 'Advertencia';
    }
    return 'Normal';
  }

  private static String etiquetaUnidad(String unidad) {
    Map<String, String> etiquetas = new Map<String, String>{
      'BAR' => 'bar',
      'CELSIUS' => '°C',
      'LITER_PER_15_MIN' => 'L/15 min',
      'KWH_PER_15_MIN' => 'kWh/15 min',
      'SECONDS' => 's'
    };
    return etiquetas.containsKey(unidad) ? etiquetas.get(unidad) : unidad;
  }
}
