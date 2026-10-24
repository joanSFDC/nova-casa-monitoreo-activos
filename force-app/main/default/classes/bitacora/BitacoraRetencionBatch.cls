/**
 * La limpieza nocturna de la bitacora, en una sola pasada: cada lote suma sus
 * conteos a Resumen_Bitacora__c (dia, equipo, resultado y motivo), borra ese
 * mismo lote y vacia su papelera. Aplicadas y atrasadas se borran a los 7 dias;
 * rechazadas, fallidas y en conflicto, a los 90. Las ligadas a cualquier caso no
 * se borran nunca. Si la ingesta esta caida o hay mas de 2.000 pendientes de los
 * ultimos 15 minutos, el lote no borra y la limpieza termina: sigue la noche siguiente.
 *
 * without sharing: proceso de sistema sobre toda la bitacora.
 */
public without sharing class BitacoraRetencionBatch implements Database.Batchable<SObject>, Database.Stateful {
  public static final Integer TAMANO_LOTE = 2000;
  public static final Integer DIAS_CORTOS = 7;
  public static final Integer DIAS_LARGOS = 90;
  @TestVisible
  static Integer maximoPendientes = 2000;
  // Un atraso del procesamiento deja pendientes recientes. Contarlas en el ultimo
  // dia recorre unas 347.000 senales (11 s por lote); en 15 minutos, unas 3.600 (60 ms).
  private static final Integer MINUTOS_PENDIENTES = 15;

  private static final Set<String> CORTOS = new Set<String>{
    IngestaConstantes.RESULTADO_APLICADO,
    IngestaConstantes.RESULTADO_ATRASADO
  };
  private static final Set<String> LARGOS = new Set<String>{
    IngestaConstantes.RESULTADO_RECHAZADO,
    IngestaConstantes.RESULTADO_FALLIDO,
    IngestaConstantes.RESULTADO_CONFLICTO
  };

  @TestVisible
  Integer borradas = 0;
  @TestVisible
  Boolean pausada = false;
  private final Datetime limiteCorto;
  private final Datetime limiteLargo;

  public BitacoraRetencionBatch() {
    this(Datetime.now());
  }

  @TestVisible
  BitacoraRetencionBatch(Datetime ahora) {
    this.limiteCorto = ahora.addDays(-DIAS_CORTOS);
    this.limiteLargo = ahora.addDays(-DIAS_LARGOS);
  }

  public Database.QueryLocator start(Database.BatchableContext contexto) {
    Set<String> cortos = CORTOS;
    Set<String> largos = LARGOS;
    Datetime corto = limiteCorto;
    Datetime largo = limiteLargo;
    return Database.getQueryLocator(
      [
        SELECT Id, CreatedDate, Activo__c, Resultado__c, Motivo__c
        FROM Senal__c
        WHERE
          Incidente__c = NULL
          AND ((Resultado__c IN :cortos
          AND CreatedDate < :corto)
          OR (Resultado__c IN :largos
          AND CreatedDate < :largo))
      ]
    );
  }

  public void execute(Database.BatchableContext contexto, List<Senal__c> lote) {
    if (pausada || ingestaAtrasada()) {
      pausada = true;
      return;
    }
    List<Senal__c> borrables = new List<Senal__c>();
    for (Senal__c senal : lote) {
      if (sigueSiendoBorrable(senal)) {
        borrables.add(senal);
      }
    }
    Map<String, Resumen_Bitacora__c> resumen = new Map<String, Resumen_Bitacora__c>();
    List<Id> borradasAhora = new List<Id>();
    Database.DeleteResult[] resultados = Database.delete(
      borrables,
      false,
      AccessLevel.SYSTEM_MODE
    );
    for (Integer i = 0; i < resultados.size(); i++) {
      if (!resultados[i].isSuccess()) {
        continue;
      }
      borradasAhora.add(borrables[i].Id);
      sumar(resumen, borrables[i]);
    }
    guardarResumen(resumen);
    if (!borradasAhora.isEmpty()) {
      Database.emptyRecycleBin(borradasAhora);
    }
    borradas += borradasAhora.size();
  }

  public void finish(Database.BatchableContext contexto) {
    System.debug(
      LoggingLevel.INFO,
      'Limpieza de bitacora: ' +
        borradas +
        ' senales borradas' +
        (pausada ? '; pausada por la ingesta' : '')
    );
  }

  /**
   * Con la ingesta caida o con muchas senales esperando al procesamiento, borrar
   * le quitaria tiempo a lo que importa: la limpieza espera a la noche siguiente.
   */
  @TestVisible
  static Boolean ingestaAtrasada() {
    for (Control_de_Ingesta__c control : [
      SELECT Caida_Desde__c
      FROM Control_de_Ingesta__c
      WHERE Activo__c = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ]) {
      if (control.Caida_Desde__c != null) {
        return true;
      }
    }
    Integer tope = maximoPendientes + 1;
    Datetime desde = Datetime.now().addMinutes(-MINUTOS_PENDIENTES);
    return [
        SELECT COUNT()
        FROM Senal__c
        WHERE
          Resultado__c = :IngestaConstantes.RESULTADO_PENDIENTE
          AND CreatedDate >= :desde
        WITH SYSTEM_MODE
        LIMIT :tope
      ] > maximoPendientes;
  }

  // Una senal puede haberse ligado a un caso entre la consulta inicial y su lote.
  private Boolean sigueSiendoBorrable(Senal__c senal) {
    if (CORTOS.contains(senal.Resultado__c)) {
      return senal.CreatedDate < limiteCorto;
    }
    return LARGOS.contains(senal.Resultado__c) &&
      senal.CreatedDate < limiteLargo;
  }

  private static void sumar(
    Map<String, Resumen_Bitacora__c> resumen,
    Senal__c senal
  ) {
    Date dia = senal.CreatedDate.addHours(-5).dateGmt();
    String clave = String.join(
      new List<String>{
        String.valueOf(dia),
        senal.Activo__c == null ? '-' : String.valueOf(senal.Activo__c),
        senal.Resultado__c ?? '-',
        senal.Motivo__c ?? '-'
      },
      '|'
    );
    Resumen_Bitacora__c fila = resumen.get(clave);
    if (fila == null) {
      fila = new Resumen_Bitacora__c(
        Clave__c = clave,
        Fecha__c = dia,
        Activo__c = senal.Activo__c,
        Resultado__c = senal.Resultado__c,
        Motivo__c = senal.Motivo__c,
        Cantidad__c = 0
      );
      resumen.put(clave, fila);
    }
    fila.Cantidad__c += 1;
  }

  private static void guardarResumen(Map<String, Resumen_Bitacora__c> resumen) {
    if (resumen.isEmpty()) {
      return;
    }
    Set<String> claves = resumen.keySet();
    for (Resumen_Bitacora__c previa : [
      SELECT Clave__c, Cantidad__c
      FROM Resumen_Bitacora__c
      WHERE Clave__c IN :claves
      WITH SYSTEM_MODE
    ]) {
      Resumen_Bitacora__c fila = resumen.get(previa.Clave__c);
      fila.Cantidad__c += previa.Cantidad__c ?? 0;
    }
    Database.upsert(
      resumen.values(),
      Resumen_Bitacora__c.Clave__c,
      true,
      AccessLevel.SYSTEM_MODE
    );
  }
}
