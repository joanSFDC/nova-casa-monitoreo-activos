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
    public Integer sinComunicacion;
    @AuraEnabled
    public Boolean sinEdificios;
    @AuraEnabled
    public Boolean sinLecturas;
    @AuraEnabled
    public Boolean consultaAtrasada;
    @AuraEnabled
    public Datetime ultimaConsultaExitosa;
    @AuraEnabled
    public Boolean puedeAbrir;
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
    @AuraEnabled
    public Id edificioId;
    @AuraEnabled
    public String ciudad;
    @AuraEnabled
    public String codigo;
    @AuraEnabled
    public String tipoActivo;
    @AuraEnabled
    public String tipoActivoEtiqueta;
    @AuraEnabled
    public Boolean esCamara;
    @AuraEnabled
    public String comunicacionEstado;
    @AuraEnabled
    public String lectura;
    @AuraEnabled
    public Datetime fechaOrigen;
    @AuraEnabled
    public Boolean casoNormalizado;
  }

  @AuraEnabled(cacheable=true)
  public static PanelDTO obtenerPanel(String edificioId) {
    PanelDTO panel = new PanelDTO();
    panel.criticos = 0;
    panel.advertencias = 0;
    panel.normales = 0;
    panel.sinComunicacion = 0;
    panel.sinEdificios = false;
    panel.sinLecturas = false;
    panel.consultaAtrasada = false;
    panel.puedeAbrir = puedeAbrir();
    panel.edificios = new List<EdificioDTO>();
    panel.filas = new List<FilaDTO>();

    List<Edificio__c> edificios = [
      SELECT Id, Name
      FROM Edificio__c
      WITH USER_MODE
      ORDER BY Name
      LIMIT :IngestaConstantes.TOPE_CATALOGO
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
          Activo__r.Edificio__r.Name,
          Activo__r.Edificio__r.Ciudad__c
        FROM Estado_Actual__c
        WITH USER_MODE
        ORDER BY Severidad_Nivel__c DESC, Fecha_Origen__c ASC
        LIMIT :IngestaConstantes.TOPE_CATALOGO
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
          Activo__r.Edificio__r.Name,
          Activo__r.Edificio__r.Ciudad__c
        FROM Estado_Actual__c
        WHERE Activo__r.Edificio__c = :edificioId
        WITH USER_MODE
        ORDER BY Severidad_Nivel__c DESC, Fecha_Origen__c ASC
        LIMIT :IngestaConstantes.TOPE_CATALOGO
      ];
    }
    if (estados.isEmpty()) {
      panel.sinLecturas = true;
      rellenarIngesta(panel);
      return panel;
    }

    Map<String, Integer> decimales = decimalesPorClave();
    Map<String, Case> casosAbiertos = casosPorEquipo(estados);
    Datetime ahora = Datetime.now();
    for (Estado_Actual__c estado : estados) {
      FilaDTO fila = filaDe(
        estado,
        decimales,
        casosAbiertos,
        ahora,
        panel.puedeAbrir
      );
      panel.filas.add(fila);
      if (fila.comunicacionEstado == 'LOST') {
        panel.sinComunicacion++;
      }
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
        Severidad__c,
        Severidad_Nivel__c,
        Estado_Comunicacion__c,
        Gap_Segundos__c,
        Valor__c,
        Unidad__c,
        Fecha_Origen__c,
        Activo__c,
        Activo__r.Codigo_Externo__c,
        Activo__r.Tipo__c
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
      LecturaFormato.comunicacion(estado.Estado_Comunicacion__c) == null;
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
    if (!puedeAbrir()) {
      throw new AuraHandledException(
        'No tienes permiso para abrir intervenciones.'
      );
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
      ? 'Corte de comunicaci\u00f3n ' + estado.Episodio_Id__c
      : 'Lectura fuera de rango ' + clave;
    incidente.Description = nota;
    Database.SaveResult resultado = Database.insert(
      incidente,
      false,
      AccessLevel.USER_MODE
    );
    if (resultado.isSuccess()) {
      new RegistroLectura()
        .completar(
          resultado.getId(),
          estado,
          decimalesPorClave()
            .get(estado.Activo__r.Tipo__c + '|' + estado.Tipo_Medicion__c)
        );
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
    if (IncidentesServicio.esDuplicado(resultado)) {
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
    throw new AuraHandledException(
      'No se pudo abrir la intervenci\u00f3n. Si no tienes permiso, habla con tu coordinador.'
    );
  }

  /**
   * La lectura con la que una persona abre el caso. Va despues del insert en
   * USER_MODE, en modo sistema, porque las personas leen estos campos pero no
   * los escriben: son evidencia del sistema, como en el procesamiento.
   */
  private without sharing class RegistroLectura {
    void completar(Id casoId, Estado_Actual__c estado, Integer lugares) {
      String texto = LecturaFormato.lectura(
        estado.Tipo_Medicion__c,
        estado.Valor__c,
        estado.Unidad__c,
        lugares,
        estado.Estado_Comunicacion__c,
        estado.Gap_Segundos__c
      );
      String severidad = String.isBlank(estado.Severidad__c)
        ? IngestaConstantes.SEV_NORMAL
        : estado.Severidad__c;
      Case incidente = new Case(
        Id = casoId,
        Lectura_Apertura__c = texto,
        Severidad_Apertura__c = severidad,
        Fecha_Lectura_Apertura__c = estado.Fecha_Origen__c,
        Ultima_Lectura__c = texto,
        Severidad_Ultima_Lectura__c = severidad,
        Fecha_Ultima_Lectura__c = estado.Fecha_Origen__c,
        Condicion_Equipo__c = IncidentesServicio.CONDICION_EN_FALLA
      );
      Database.update(incidente, false, AccessLevel.SYSTEM_MODE);
    }
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

  /**
   * El caso abierto de cada fila se busca por equipo y medicion, no por clave:
   * la clave de una camara es su episodio, y al volver la comunicacion el estado
   * lo borra. Buscando por equipo, la fila sigue llevando al caso del ultimo
   * corte mientras siga abierto.
   */
  private static Map<String, Case> casosPorEquipo(
    List<Estado_Actual__c> estados
  ) {
    Set<Id> activos = new Set<Id>();
    for (Estado_Actual__c estado : estados) {
      activos.add(estado.Activo__c);
    }
    Map<String, Case> mapa = new Map<String, Case>();
    for (Case incidente : [
      SELECT Id, Activo__c, Tipo_Medicion__c
      FROM Case
      WHERE Activo__c IN :activos AND IsClosed = FALSE
      WITH USER_MODE
      ORDER BY CreatedDate DESC
    ]) {
      String clave = incidente.Activo__c + '|' + incidente.Tipo_Medicion__c;
      if (!mapa.containsKey(clave)) {
        mapa.put(clave, incidente);
      }
    }
    return mapa;
  }

  /**
   * Abrir intervencion es crear un caso: quien no puede, no ve el boton. El
   * gerente lee los casos y no los crea; ver un caso existente no lo pide.
   */
  private static Boolean puedeAbrir() {
    return Schema.SObjectType.Case.isCreateable();
  }

  private static FilaDTO filaDe(
    Estado_Actual__c estado,
    Map<String, Integer> decimales,
    Map<String, Case> casosAbiertos,
    Datetime ahora,
    Boolean puedeAbrir
  ) {
    FilaDTO fila = new FilaDTO();
    fila.estadoId = estado.Id;
    fila.activoId = estado.Activo__c;
    fila.edificio = estado.Activo__r.Edificio__r.Name;
    fila.edificioId = estado.Activo__r.Edificio__c;
    fila.ciudad = estado.Activo__r.Edificio__r.Ciudad__c;
    fila.equipo = estado.Activo__r.Name;
    fila.codigo = estado.Activo__r.Codigo_Externo__c;
    fila.tipoActivo = estado.Activo__r.Tipo__c;
    fila.tipoActivoEtiqueta = LecturaFormato.tipoActivo(fila.tipoActivo);
    fila.medicion = LecturaFormato.medicion(estado.Tipo_Medicion__c);
    fila.severidad = estado.Severidad__c;
    fila.severidadNivel = estado.Severidad_Nivel__c == null
      ? 0
      : Integer.valueOf(estado.Severidad_Nivel__c);
    fila.severidadEtiqueta = LecturaFormato.severidad(fila.severidadNivel);
    fila.fechaOrigen = estado.Fecha_Origen__c;
    fila.antiguedad = LecturaFormato.antiguedad(estado.Fecha_Origen__c, ahora);
    fila.esCamara = estado.Tipo_Medicion__c == LecturaFormato.CONECTIVIDAD;
    fila.comunicacionEstado = estado.Estado_Comunicacion__c;
    fila.comunicacion = LecturaFormato.comunicacion(
      estado.Estado_Comunicacion__c
    );
    fila.valor = valorDe(estado, decimales);
    fila.lectura = fila.esCamara
      ? LecturaFormato.corte(
          estado.Estado_Comunicacion__c,
          estado.Gap_Segundos__c
        )
      : fila.valor;
    Case caso = casosAbiertos.get(
      estado.Activo__c + '|' + estado.Tipo_Medicion__c
    );
    fila.casoId = caso == null ? null : caso.Id;
    fila.casoNormalizado =
      caso != null &&
      fila.severidadNivel == 0 &&
      estado.Estado_Comunicacion__c != 'LOST';
    fila.puedeIntervenir =
      fila.casoId != null ||
      (puedeAbrir &&
      String.isNotBlank(claveDe(estado)) &&
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
        return LecturaFormato.SIN_VALOR;
      }
      return String.valueOf(estado.Gap_Segundos__c.intValue()) + ' s';
    }
    String claveUmbral =
      (estado.Activo__r == null ? '' : estado.Activo__r.Tipo__c) +
      '|' +
      estado.Tipo_Medicion__c;
    Integer lugares = decimales.containsKey(claveUmbral)
      ? decimales.get(claveUmbral)
      : 0;
    return LecturaFormato.valor(estado.Valor__c, estado.Unidad__c, lugares);
  }
}
