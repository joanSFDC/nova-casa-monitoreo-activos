/**
 * Las lecturas del equipo de un incidente durante su periodo, en paginas de 50,
 * de la mas nueva a la mas vieja. Pagina por posicion, sin OFFSET: la fecha de
 * creacion de la ultima fila y los Id ya mostrados de ese mismo segundo. Ordenar
 * tambien por Id le quita a la consulta el indice de CreatedDate y la lleva a
 * recorrer todas las senales del activo; por eso el desempate va en el filtro.
 *
 * with sharing y USER_MODE: la usan el coordinador y el administrador, que leen
 * la bitacora. Un caso que no se ve, o una persona sin acceso a la bitacora,
 * devuelve null. Los limites del periodo (fechas, activo y senal de origen) se
 * leen en modo sistema una vez comprobado que el caso se ve: no se muestran, y
 * no todos los roles tienen permiso de campo sobre ClosedDate.
 */
public with sharing class LecturasPeriodoControlador {
  public static final Integer TAMANO_PAGINA = 50;
  public static final Integer VENTANA_DIAS = 7;
  @TestVisible
  static final Integer TOPE_VISTOS = 500;

  public class FilaDTO {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String nombre;
    @AuraEnabled
    public Datetime recibida;
    @AuraEnabled
    public String lectura;
    @AuraEnabled
    public String resultado;
    @AuraEnabled
    public String resultadoEtiqueta;
    @AuraEnabled
    public String motivo;
  }

  public class PaginaDTO {
    @AuraEnabled
    public List<FilaDTO> filas = new List<FilaDTO>();
    @AuraEnabled
    public Boolean hayMas = false;
    @AuraEnabled
    public Datetime siguienteHasta;
    @AuraEnabled
    public List<Id> siguienteVistos = new List<Id>();
    @AuraEnabled
    public String equipo;
    @AuraEnabled
    public Boolean cerrado = false;
    @AuraEnabled
    public Boolean fueraDeVentana = false;
  }

  /**
   * @param casoId El incidente
   * @param hasta La fecha de creacion de la ultima fila vista; null en la primera pagina
   * @param vistos Los Id de ese mismo segundo que ya se mostraron
   * @return La pagina, o null si el caso no existe o no se puede ver
   */
  @AuraEnabled
  public static PaginaDTO pagina(Id casoId, Datetime hasta, List<Id> vistos) {
    if (casoId == null || !Schema.SObjectType.Senal__c.isAccessible()) {
      return null;
    }
    Set<Id> excluidos = vistos == null ? new Set<Id>() : new Set<Id>(vistos);
    if (excluidos.size() > TOPE_VISTOS) {
      throw new AuraHandledException('La posición de la página no es válida.');
    }
    if ([SELECT COUNT() FROM Case WHERE Id = :casoId WITH USER_MODE] == 0) {
      return null;
    }
    Case caso = [
      SELECT
        Id,
        Activo__c,
        Activo__r.Name,
        Tipo_Medicion__c,
        Origen_Senal__c,
        CreatedDate,
        ClosedDate,
        IsClosed
      FROM Case
      WHERE Id = :casoId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    PaginaDTO dto = new PaginaDTO();
    dto.equipo = caso.Activo__r?.Name;
    dto.cerrado = caso.IsClosed;
    if (caso.Activo__c == null) {
      return dto;
    }

    Datetime desde = desdeDe(caso);
    dto.fueraDeVentana = desde < Datetime.now().addDays(-VENTANA_DIAS);
    Datetime tope = caso.IsClosed && caso.ClosedDate != null
      ? caso.ClosedDate
      : Datetime.now();
    if (hasta != null && hasta < tope) {
      tope = hasta;
    }
    String tipoMensaje = caso.Tipo_Medicion__c == LecturaFormato.CONECTIVIDAD
      ? IngestaConstantes.TIPO_CONECTIVIDAD
      : IngestaConstantes.TIPO_MEDICION;
    Integer conUnaMas = TAMANO_PAGINA + 1;

    List<Senal__c> senales = [
      SELECT Id, Name, CreatedDate, Lectura__c, Resultado__c, toLabel(Motivo__c)
      FROM Senal__c
      WHERE
        Activo__c = :caso.Activo__c
        AND Tipo_Mensaje__c = :tipoMensaje
        AND CreatedDate >= :desde
        AND CreatedDate <= :tope
        AND Id NOT IN :excluidos
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT :conUnaMas
    ];
    dto.hayMas = senales.size() > TAMANO_PAGINA;
    Map<String, String> etiquetas = etiquetasDeResultado();
    for (Integer i = 0; i < senales.size() && i < TAMANO_PAGINA; i++) {
      dto.filas.add(filaDe(senales[i], etiquetas));
    }
    if (!dto.filas.isEmpty()) {
      Datetime ultima = dto.filas[dto.filas.size() - 1].recibida;
      Set<Id> siguientes = new Set<Id>();
      if (hasta != null && ultima == hasta) {
        siguientes.addAll(excluidos);
      }
      for (FilaDTO fila : dto.filas) {
        if (fila.recibida == ultima) {
          siguientes.add(fila.id);
        }
      }
      dto.siguienteHasta = ultima;
      dto.siguienteVistos = new List<Id>(siguientes);
    }
    return dto;
  }

  /**
   * La senal que abrio el caso se guarda unos segundos antes que el caso: el
   * periodo empieza en ella.
   */
  private static Datetime desdeDe(Case caso) {
    Datetime desde = caso.CreatedDate;
    if (String.isBlank(caso.Origen_Senal__c)) {
      return desde;
    }
    for (Senal__c origen : [
      SELECT CreatedDate
      FROM Senal__c
      WHERE Clave__c = :caso.Origen_Senal__c
      WITH USER_MODE
      LIMIT 1
    ]) {
      if (origen.CreatedDate < desde) {
        desde = origen.CreatedDate;
      }
    }
    return desde;
  }

  private static FilaDTO filaDe(Senal__c senal, Map<String, String> etiquetas) {
    FilaDTO fila = new FilaDTO();
    fila.id = senal.Id;
    fila.nombre = senal.Name;
    fila.recibida = senal.CreatedDate;
    fila.lectura = String.isBlank(senal.Lectura__c)
      ? LecturaFormato.SIN_VALOR
      : senal.Lectura__c;
    fila.resultado = senal.Resultado__c;
    fila.resultadoEtiqueta = etiquetas.containsKey(senal.Resultado__c)
      ? etiquetas.get(senal.Resultado__c)
      : senal.Resultado__c;
    fila.motivo = senal.Motivo__c;
    return fila;
  }

  private static Map<String, String> etiquetasDeResultado() {
    Map<String, String> etiquetas = new Map<String, String>();
    for (
      Schema.PicklistEntry entrada : Senal__c.Resultado__c.getDescribe()
        .getPicklistValues()
    ) {
      etiquetas.put(entrada.getValue(), entrada.getLabel());
    }
    return etiquetas;
  }
}
