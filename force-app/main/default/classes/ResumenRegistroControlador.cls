/**
 * Los resumenes de las paginas de incidente, activo y edificio: lo que una
 * persona necesita ver de un registro sin ir a otros. with sharing y USER_MODE,
 * como el monitor: un registro que no puede ver devuelve null, no un error que
 * delate que existe.
 */
public with sharing class ResumenRegistroControlador {
  public class EquipoDTO {
    @AuraEnabled
    public Id activoId;
    @AuraEnabled
    public String nombre;
    @AuraEnabled
    public String codigo;
    @AuraEnabled
    public String tipo;
    @AuraEnabled
    public String tipoEtiqueta;
    @AuraEnabled
    public Id edificioId;
    @AuraEnabled
    public String edificio;
    @AuraEnabled
    public String ciudad;
  }

  public class LecturaDTO {
    @AuraEnabled
    public String texto;
    @AuraEnabled
    public String severidad;
    @AuraEnabled
    public String severidadEtiqueta;
    @AuraEnabled
    public Datetime fecha;
  }

  public class MedicionDTO {
    @AuraEnabled
    public Id estadoId;
    @AuraEnabled
    public Id activoId;
    @AuraEnabled
    public String equipo;
    @AuraEnabled
    public String tipoActivo;
    @AuraEnabled
    public String tipoActivoEtiqueta;
    @AuraEnabled
    public String medicion;
    @AuraEnabled
    public String lectura;
    @AuraEnabled
    public Boolean esCamara;
    @AuraEnabled
    public String comunicacionEstado;
    @AuraEnabled
    public String severidad;
    @AuraEnabled
    public String severidadEtiqueta;
    @AuraEnabled
    public Integer nivel;
    @AuraEnabled
    public String antiguedad;
    @AuraEnabled
    public Id casoId;
    @AuraEnabled
    public Boolean casoNormalizado;
  }

  public class CasoDTO {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String numero;
    @AuraEnabled
    public String asunto;
    @AuraEnabled
    public String prioridad;
    @AuraEnabled
    public String equipo;
    @AuraEnabled
    public Boolean normalizado;
    @AuraEnabled
    public String ultimaLectura;
  }

  public class LimiteDTO {
    @AuraEnabled
    public String medicion;
    @AuraEnabled
    public String tipoMedicion;
    @AuraEnabled
    public String unidad;
    @AuraEnabled
    public Integer decimales;
    @AuraEnabled
    public Decimal criticoBajo;
    @AuraEnabled
    public Decimal advertenciaBajo;
    @AuraEnabled
    public Decimal advertenciaAlto;
    @AuraEnabled
    public Decimal criticoAlto;
    @AuraEnabled
    public Decimal minutosAdvertencia;
    @AuraEnabled
    public Decimal minutosCritico;
  }

  public class IncidenteDTO {
    @AuraEnabled
    public EquipoDTO equipo;
    @AuraEnabled
    public LecturaDTO apertura;
    @AuraEnabled
    public LecturaDTO ultima;
    @AuraEnabled
    public MedicionDTO ahora;
    @AuraEnabled
    public String medicion;
    @AuraEnabled
    public Boolean normalizado;
    @AuraEnabled
    public Datetime normalizadoEn;
    @AuraEnabled
    public Boolean cerrado;
  }

  public class ActivoDTO {
    @AuraEnabled
    public EquipoDTO equipo;
    @AuraEnabled
    public String severidad;
    @AuraEnabled
    public String severidadEtiqueta;
    @AuraEnabled
    public List<MedicionDTO> mediciones;
    @AuraEnabled
    public List<CasoDTO> casos;
    @AuraEnabled
    public List<LimiteDTO> limites;
  }

  public class EdificioDTO {
    @AuraEnabled
    public String nombre;
    @AuraEnabled
    public String ciudad;
    @AuraEnabled
    public String region;
    @AuraEnabled
    public Integer criticos;
    @AuraEnabled
    public Integer advertencias;
    @AuraEnabled
    public Integer normales;
    @AuraEnabled
    public Integer sinComunicacion;
    @AuraEnabled
    public List<MedicionDTO> equipos;
    @AuraEnabled
    public List<CasoDTO> casos;
  }

  @AuraEnabled(cacheable=true)
  public static IncidenteDTO incidente(Id caseId) {
    List<Case> casos = [
      SELECT
        Id,
        IsClosed,
        Activo__c,
        Tipo_Medicion__c,
        Lectura_Apertura__c,
        Severidad_Apertura__c,
        Fecha_Lectura_Apertura__c,
        Ultima_Lectura__c,
        Severidad_Ultima_Lectura__c,
        Fecha_Ultima_Lectura__c,
        Condicion_Equipo__c,
        Normalizado_En__c
      FROM Case
      WHERE Id = :caseId
      WITH USER_MODE
      LIMIT 1
    ];
    if (casos.isEmpty()) {
      return null;
    }
    Case caso = casos[0];
    IncidenteDTO dto = new IncidenteDTO();
    dto.medicion = LecturaFormato.medicion(caso.Tipo_Medicion__c);
    dto.cerrado = caso.IsClosed;
    dto.apertura = lectura(
      caso.Lectura_Apertura__c,
      caso.Severidad_Apertura__c,
      caso.Fecha_Lectura_Apertura__c
    );
    dto.ultima = lectura(
      caso.Ultima_Lectura__c,
      caso.Severidad_Ultima_Lectura__c,
      caso.Fecha_Ultima_Lectura__c
    );
    dto.normalizado =
      caso.Condicion_Equipo__c == IncidentesServicio.CONDICION_NORMALIZADO;
    dto.normalizadoEn = caso.Normalizado_En__c;
    if (caso.Activo__c == null) {
      return dto;
    }
    List<Activo__c> activos = activos(new Set<Id>{ caso.Activo__c });
    if (activos.isEmpty()) {
      return dto;
    }
    dto.equipo = equipoDe(activos[0]);
    for (Estado_Actual__c estado : [
      SELECT
        Id,
        Activo__c,
        Tipo_Medicion__c,
        Valor__c,
        Unidad__c,
        Severidad__c,
        Severidad_Nivel__c,
        Fecha_Origen__c,
        Estado_Comunicacion__c,
        Gap_Segundos__c,
        Activo__r.Name,
        Activo__r.Tipo__c
      FROM Estado_Actual__c
      WHERE
        Activo__c = :caso.Activo__c
        AND Tipo_Medicion__c = :caso.Tipo_Medicion__c
      WITH USER_MODE
      LIMIT 1
    ]) {
      dto.ahora = medicionDe(estado, decimales(), new Map<String, Case>());
    }
    return dto;
  }

  @AuraEnabled(cacheable=true)
  public static ActivoDTO activo(Id activoId) {
    List<Activo__c> activos = activos(new Set<Id>{ activoId });
    if (activos.isEmpty()) {
      return null;
    }
    Activo__c activo = activos[0];
    ActivoDTO dto = new ActivoDTO();
    dto.equipo = equipoDe(activo);
    Integer nivel = activo.Severidad_Nivel__c == null
      ? 0
      : Integer.valueOf(activo.Severidad_Nivel__c);
    dto.severidad = LecturaFormato.severidadApi(nivel);
    dto.severidadEtiqueta = LecturaFormato.severidad(nivel);

    List<Case> abiertos = abiertos(new Set<Id>{ activoId }, null);
    dto.casos = casosDe(abiertos);
    dto.mediciones = mediciones(
      [
        SELECT
          Id,
          Activo__c,
          Tipo_Medicion__c,
          Valor__c,
          Unidad__c,
          Severidad__c,
          Severidad_Nivel__c,
          Fecha_Origen__c,
          Estado_Comunicacion__c,
          Gap_Segundos__c,
          Activo__r.Name,
          Activo__r.Tipo__c
        FROM Estado_Actual__c
        WHERE Activo__c = :activoId
        WITH USER_MODE
        ORDER BY Severidad_Nivel__c DESC, Tipo_Medicion__c
      ],
      abiertos
    );

    dto.limites = new List<LimiteDTO>();
    for (Umbral__c umbral : [
      SELECT
        Tipo_Medicion__c,
        Unidad__c,
        Decimales__c,
        Critico_Bajo__c,
        Advertencia_Bajo__c,
        Advertencia_Alto__c,
        Critico_Alto__c,
        Minutos_Advertencia__c,
        Minutos_Critico__c
      FROM Umbral__c
      WHERE Tipo_Activo__c = :activo.Tipo__c AND Vigente__c = TRUE
      WITH USER_MODE
      ORDER BY Tipo_Medicion__c
    ]) {
      dto.limites.add(limiteDe(umbral));
    }
    return dto;
  }

  @AuraEnabled(cacheable=true)
  public static EdificioDTO edificio(Id edificioId) {
    List<Edificio__c> edificios = [
      SELECT Id, Name, Ciudad__c, Region__c
      FROM Edificio__c
      WHERE Id = :edificioId
      WITH USER_MODE
      LIMIT 1
    ];
    if (edificios.isEmpty()) {
      return null;
    }
    EdificioDTO dto = new EdificioDTO();
    dto.nombre = edificios[0].Name;
    dto.ciudad = edificios[0].Ciudad__c;
    dto.region = edificios[0].Region__c;
    dto.criticos = 0;
    dto.advertencias = 0;
    dto.normales = 0;
    dto.sinComunicacion = 0;

    List<Case> abiertos = abiertos(null, edificioId);
    dto.casos = casosDe(abiertos);
    dto.equipos = mediciones(
      [
        SELECT
          Id,
          Activo__c,
          Tipo_Medicion__c,
          Valor__c,
          Unidad__c,
          Severidad__c,
          Severidad_Nivel__c,
          Fecha_Origen__c,
          Estado_Comunicacion__c,
          Gap_Segundos__c,
          Activo__r.Name,
          Activo__r.Tipo__c
        FROM Estado_Actual__c
        WHERE Activo__r.Edificio__c = :edificioId
        WITH USER_MODE
        ORDER BY Severidad_Nivel__c DESC, Activo__r.Name
      ],
      abiertos
    );
    for (MedicionDTO medicion : dto.equipos) {
      if (medicion.nivel == 2) {
        dto.criticos++;
      } else if (medicion.nivel == 1) {
        dto.advertencias++;
      } else {
        dto.normales++;
      }
      if (medicion.comunicacionEstado == 'LOST') {
        dto.sinComunicacion++;
      }
    }
    return dto;
  }

  private static List<Activo__c> activos(Set<Id> ids) {
    return [
      SELECT
        Id,
        Name,
        Codigo_Externo__c,
        Tipo__c,
        Severidad_Nivel__c,
        Edificio__c,
        Edificio__r.Name,
        Edificio__r.Ciudad__c
      FROM Activo__c
      WHERE Id IN :ids
      WITH USER_MODE
    ];
  }

  private static List<Case> abiertos(Set<Id> activoIds, Id edificioId) {
    if (activoIds != null) {
      return [
        SELECT
          Id,
          CaseNumber,
          Subject,
          Priority,
          Activo__c,
          Activo__r.Name,
          Tipo_Medicion__c,
          Condicion_Equipo__c,
          Ultima_Lectura__c
        FROM Case
        WHERE Activo__c IN :activoIds AND IsClosed = FALSE
        WITH USER_MODE
        ORDER BY CreatedDate DESC
        LIMIT 50
      ];
    }
    return [
      SELECT
        Id,
        CaseNumber,
        Subject,
        Priority,
        Activo__c,
        Activo__r.Name,
        Tipo_Medicion__c,
        Condicion_Equipo__c,
        Ultima_Lectura__c
      FROM Case
      WHERE Activo__r.Edificio__c = :edificioId AND IsClosed = FALSE
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 50
    ];
  }

  private static List<CasoDTO> casosDe(List<Case> casos) {
    List<CasoDTO> lista = new List<CasoDTO>();
    for (Case caso : casos) {
      CasoDTO dto = new CasoDTO();
      dto.id = caso.Id;
      dto.numero = caso.CaseNumber;
      dto.asunto = caso.Subject;
      dto.prioridad = caso.Priority == IncidentesServicio.PRIORIDAD_ALTA
        ? 'Alta'
        : (caso.Priority == IncidentesServicio.PRIORIDAD_BAJA
            ? 'Baja'
            : 'Media');
      dto.equipo = caso.Activo__r == null ? null : caso.Activo__r.Name;
      dto.normalizado =
        caso.Condicion_Equipo__c == IncidentesServicio.CONDICION_NORMALIZADO;
      dto.ultimaLectura = caso.Ultima_Lectura__c;
      lista.add(dto);
    }
    return lista;
  }

  private static List<MedicionDTO> mediciones(
    List<Estado_Actual__c> estados,
    List<Case> abiertos
  ) {
    Map<String, Case> porEquipo = new Map<String, Case>();
    for (Case caso : abiertos) {
      String clave = caso.Activo__c + '|' + caso.Tipo_Medicion__c;
      if (!porEquipo.containsKey(clave)) {
        porEquipo.put(clave, caso);
      }
    }
    Map<String, Integer> lugares = decimales();
    List<MedicionDTO> lista = new List<MedicionDTO>();
    for (Estado_Actual__c estado : estados) {
      lista.add(medicionDe(estado, lugares, porEquipo));
    }
    return lista;
  }

  private static MedicionDTO medicionDe(
    Estado_Actual__c estado,
    Map<String, Integer> lugares,
    Map<String, Case> porEquipo
  ) {
    MedicionDTO dto = new MedicionDTO();
    dto.estadoId = estado.Id;
    dto.activoId = estado.Activo__c;
    dto.equipo = estado.Activo__r == null ? null : estado.Activo__r.Name;
    dto.tipoActivo = estado.Activo__r == null ? null : estado.Activo__r.Tipo__c;
    dto.tipoActivoEtiqueta = LecturaFormato.tipoActivo(dto.tipoActivo);
    dto.medicion = LecturaFormato.medicion(estado.Tipo_Medicion__c);
    dto.esCamara = estado.Tipo_Medicion__c == LecturaFormato.CONECTIVIDAD;
    dto.comunicacionEstado = estado.Estado_Comunicacion__c;
    dto.nivel = estado.Severidad_Nivel__c == null
      ? 0
      : Integer.valueOf(estado.Severidad_Nivel__c);
    dto.severidad = LecturaFormato.severidadApi(dto.nivel);
    dto.severidadEtiqueta = LecturaFormato.severidad(dto.nivel);
    dto.lectura = LecturaFormato.lectura(
      estado.Tipo_Medicion__c,
      estado.Valor__c,
      estado.Unidad__c,
      lugares.get(dto.tipoActivo + '|' + estado.Tipo_Medicion__c),
      estado.Estado_Comunicacion__c,
      estado.Gap_Segundos__c
    );
    dto.antiguedad = LecturaFormato.antiguedad(
      estado.Fecha_Origen__c,
      Datetime.now()
    );
    Case caso = porEquipo.get(estado.Activo__c + '|' + estado.Tipo_Medicion__c);
    dto.casoId = caso == null ? null : caso.Id;
    dto.casoNormalizado =
      caso != null &&
      dto.nivel == 0 &&
      estado.Estado_Comunicacion__c != 'LOST';
    return dto;
  }

  private static EquipoDTO equipoDe(Activo__c activo) {
    EquipoDTO dto = new EquipoDTO();
    dto.activoId = activo.Id;
    dto.nombre = activo.Name;
    dto.codigo = activo.Codigo_Externo__c;
    dto.tipo = activo.Tipo__c;
    dto.tipoEtiqueta = LecturaFormato.tipoActivo(activo.Tipo__c);
    dto.edificioId = activo.Edificio__c;
    dto.edificio = activo.Edificio__r == null ? null : activo.Edificio__r.Name;
    dto.ciudad = activo.Edificio__r == null
      ? null
      : activo.Edificio__r.Ciudad__c;
    return dto;
  }

  private static LecturaDTO lectura(
    String texto,
    String severidad,
    Datetime fecha
  ) {
    if (String.isBlank(texto) && String.isBlank(severidad)) {
      return null;
    }
    LecturaDTO dto = new LecturaDTO();
    dto.texto = texto;
    dto.severidad = severidad;
    dto.severidadEtiqueta = LecturaFormato.severidad(
      LecturaFormato.nivelDe(severidad)
    );
    dto.fecha = fecha;
    return dto;
  }

  private static LimiteDTO limiteDe(Umbral__c umbral) {
    LimiteDTO dto = new LimiteDTO();
    dto.tipoMedicion = umbral.Tipo_Medicion__c;
    dto.medicion = LecturaFormato.medicion(umbral.Tipo_Medicion__c);
    dto.unidad = LecturaFormato.unidad(umbral.Unidad__c);
    dto.decimales = umbral.Decimales__c == null
      ? 0
      : Integer.valueOf(umbral.Decimales__c);
    dto.criticoBajo = umbral.Critico_Bajo__c;
    dto.advertenciaBajo = umbral.Advertencia_Bajo__c;
    dto.advertenciaAlto = umbral.Advertencia_Alto__c;
    dto.criticoAlto = umbral.Critico_Alto__c;
    dto.minutosAdvertencia = umbral.Minutos_Advertencia__c;
    dto.minutosCritico = umbral.Minutos_Critico__c;
    return dto;
  }

  private static Map<String, Integer> decimales() {
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
}
