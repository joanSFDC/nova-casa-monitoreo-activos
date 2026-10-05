/**
 * Una sola intervencion por problema: unicidad por Clave_Abierta__c, escalada
 * de prioridad y evidencia de recuperacion. No cierra el caso. Lo critico va a
 * la cola Coordinacion; lo bajo no es de nadie.
 *
 * without sharing: proceso de sistema. Lo invoca el procesamiento, no una persona.
 */
public without sharing class IncidentesServicio {
  public static final String PREFIJO_CONN = 'CONN|';
  public static final String PRIORIDAD_BAJA = 'Low';
  public static final String PRIORIDAD_ALTA = 'High';
  public static final String COLA_COORDINACION = 'Coordinacion';

  @TestVisible
  static Boolean inyectarFalloDeCaso = false;

  private static Id colaCoordinacionId;
  private static Boolean colaBuscada = false;

  public class Decision {
    public String clave;
    public Id activoId;
    public String tipoMedicion;
    public String episodioId;
    public String claveSenal;
    public Set<String> clavesSenal;
    public Integer nivel;
    public Boolean marcarRecuperado;
    public List<String> orden = new List<String>();
    public Map<String, Integer> nivelPorSenal = new Map<String, Integer>();
    public Set<String> recuperadas = new Set<String>();
  }

  public static String claveDe(Aviso_de_Senal__e aviso) {
    if (aviso == null) {
      return null;
    }
    if (
      aviso.Tipo_Mensaje__c == IngestaConstantes.TIPO_CONECTIVIDAD &&
      String.isNotBlank(aviso.Episodio_Id__c)
    ) {
      return PREFIJO_CONN + aviso.Episodio_Id__c;
    }
    String tipo = String.isNotBlank(aviso.Tipo_Medicion__c)
      ? aviso.Tipo_Medicion__c
      : (aviso.Tipo_Mensaje__c == IngestaConstantes.TIPO_CONECTIVIDAD
          ? 'CAMERA_CONNECTIVITY'
          : null);
    if (String.isBlank(aviso.Codigo_Activo__c) || String.isBlank(tipo)) {
      return null;
    }
    return aviso.Codigo_Activo__c + '|' + tipo;
  }

  public static Map<String, Case> cargarAbiertos(Set<String> claves) {
    Map<String, Case> mapa = new Map<String, Case>();
    if (claves == null || claves.isEmpty()) {
      return mapa;
    }
    for (Case incidente : [
      SELECT
        Id,
        Clave_Abierta__c,
        Priority,
        OwnerId,
        Description,
        IsClosed,
        Status
      FROM Case
      WHERE Clave_Abierta__c IN :claves
      WITH SYSTEM_MODE
    ]) {
      mapa.put(incidente.Clave_Abierta__c, incidente);
    }
    return mapa;
  }

  public static void acumular(
    Map<String, Decision> decisiones,
    Aviso_de_Senal__e aviso,
    Senal__c senal,
    Activo__c activo,
    String tipoMedicion,
    ClasificacionServicio.Dictamen dictamen
  ) {
    if (
      decisiones == null ||
      aviso == null ||
      senal == null ||
      dictamen == null
    ) {
      return;
    }
    Boolean restored =
      aviso.Tipo_Mensaje__c == IngestaConstantes.TIPO_CONECTIVIDAD &&
      aviso.Estado_Comunicacion__c == 'RESTORED';
    Integer nivel = dictamen.nivel == null ? 0 : dictamen.nivel;
    if (nivel < 1 && !restored) {
      return;
    }
    String clave = claveDe(aviso);
    if (String.isBlank(clave)) {
      return;
    }
    Decision decision = decisiones.get(clave);
    if (decision == null) {
      decision = new Decision();
      decision.clave = clave;
      decision.activoId = activo == null ? null : activo.Id;
      decision.tipoMedicion = tipoMedicion;
      decision.episodioId = aviso.Episodio_Id__c;
      decision.claveSenal = senal.Clave__c;
      decision.clavesSenal = new Set<String>();
      decision.nivel = nivel;
      decision.marcarRecuperado = restored;
      decisiones.put(clave, decision);
    }
    decision.clavesSenal.add(senal.Clave__c);
    decision.orden.add(senal.Clave__c);
    decision.nivelPorSenal.put(senal.Clave__c, nivel);
    if (restored) {
      decision.recuperadas.add(senal.Clave__c);
    }
  }

  /**
   * Nivel, origen y recuperacion salen solo de las senales que quedaron Aplicado.
   * Una perdedora de la tanda es Atrasado y no abre ni escala (modulo 06).
   */
  private static Boolean depurarConAplicadas(
    Decision decision,
    Map<String, Senal__c> senales
  ) {
    if (decision.orden.isEmpty()) {
      return hayAplicada(decision, senales);
    }
    Boolean alguna = false;
    Integer nivel = 0;
    String origen;
    Boolean recuperado = false;
    for (String claveSenal : decision.orden) {
      Senal__c senal = senales.get(claveSenal);
      if (
        senal == null ||
        senal.Resultado__c != IngestaConstantes.RESULTADO_APLICADO
      ) {
        continue;
      }
      Integer nivelSenal = decision.nivelPorSenal.get(claveSenal);
      if (!alguna || nivelSenal > nivel) {
        nivel = nivelSenal;
        origen = claveSenal;
      }
      alguna = true;
      if (decision.recuperadas.contains(claveSenal)) {
        recuperado = true;
      }
    }
    if (alguna) {
      decision.nivel = nivel;
      decision.claveSenal = origen;
      decision.marcarRecuperado = recuperado;
    }
    return alguna;
  }

  private static Boolean hayAplicada(
    Decision decision,
    Map<String, Senal__c> senales
  ) {
    for (String claveSenal : decision.clavesSenal) {
      Senal__c senal = senales.get(claveSenal);
      if (
        senal != null &&
        senal.Resultado__c == IngestaConstantes.RESULTADO_APLICADO
      ) {
        return true;
      }
    }
    return false;
  }

  public static void escribir(
    Map<String, Decision> decisiones,
    Map<String, Case> abiertos,
    Map<String, Senal__c> senales,
    Datetime ahora
  ) {
    if (decisiones == null || decisiones.isEmpty() || senales == null) {
      return;
    }
    if (abiertos == null) {
      abiertos = new Map<String, Case>();
    }

    List<Case> aInsertar = new List<Case>();
    List<String> senalesInsert = new List<String>();
    Map<Id, Case> aActualizar = new Map<Id, Case>();
    Map<Id, String> senalPorCaso = new Map<Id, String>();
    Set<String> clavesDuplicado = new Set<String>();

    for (Decision decision : decisiones.values()) {
      if (decision.clavesSenal == null) {
        decision.clavesSenal = new Set<String>();
      }
      if (String.isNotBlank(decision.claveSenal)) {
        decision.clavesSenal.add(decision.claveSenal);
      }
      if (!depurarConAplicadas(decision, senales)) {
        continue;
      }
      Case abierto = abiertos.get(decision.clave);
      if (decision.marcarRecuperado && abierto != null && !abierto.IsClosed) {
        abierto.Description = lineaRecuperado(
          abierto.Description,
          decision.claveSenal,
          ahora
        );
        aActualizar.put(abierto.Id, abierto);
        senalPorCaso.put(abierto.Id, decision.claveSenal);
      }
      if (decision.nivel < 1) {
        continue;
      }
      if (abierto == null) {
        aInsertar.add(armarCaso(decision));
        senalesInsert.add(decision.clave);
        continue;
      }
      if (abierto.IsClosed) {
        continue;
      }
      if (debeEscalar(abierto, decision.nivel)) {
        escalar(abierto);
        aActualizar.put(abierto.Id, abierto);
        senalPorCaso.put(abierto.Id, decision.claveSenal);
      } else {
        ligar(decision, senales, abierto.Id);
      }
    }

    if (!aInsertar.isEmpty()) {
      Database.SaveResult[] resultados = Database.insert(
        aInsertar,
        false,
        AccessLevel.SYSTEM_MODE
      );
      for (Integer i = 0; i < resultados.size(); i++) {
        Decision decision = decisiones.get(senalesInsert[i]);
        if (decision == null) {
          continue;
        }
        if (resultados[i].isSuccess()) {
          ligar(decision, senales, resultados[i].getId());
          continue;
        }
        if (esDuplicado(resultados[i])) {
          clavesDuplicado.add(aInsertar[i].Clave_Abierta__c);
          continue;
        }
        marcarFallidas(decision, senales, resultados[i], ahora);
      }
    }

    if (!clavesDuplicado.isEmpty()) {
      reintentarEscalada(clavesDuplicado, decisiones, senales);
    }

    if (!aActualizar.isEmpty()) {
      List<Case> listaActualizar = aActualizar.values();
      Database.SaveResult[] resultados = Database.update(
        listaActualizar,
        false,
        AccessLevel.SYSTEM_MODE
      );
      for (Integer i = 0; i < resultados.size(); i++) {
        String claveSenal = senalPorCaso.get(listaActualizar[i].Id);
        Decision decision = decisionPorSenal(decisiones, claveSenal);
        if (resultados[i].isSuccess()) {
          if (decision != null) {
            ligar(decision, senales, listaActualizar[i].Id);
          }
          continue;
        }
        if (decision == null) {
          continue;
        }
        marcarFallidas(decision, senales, resultados[i], ahora);
      }
    }
  }

  @TestVisible
  static Boolean esDuplicado(Database.SaveResult resultado) {
    if (resultado == null || resultado.isSuccess()) {
      return false;
    }
    for (Database.Error error : resultado.getErrors()) {
      if (error.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
        return true;
      }
    }
    return false;
  }

  private static void reintentarEscalada(
    Set<String> claves,
    Map<String, Decision> decisiones,
    Map<String, Senal__c> senales
  ) {
    Map<String, Case> ganadores = cargarAbiertos(claves);
    List<Case> aEscalar = new List<Case>();
    for (String clave : claves) {
      Case ganador = ganadores.get(clave);
      Decision decision = decisiones.get(clave);
      if (ganador == null || decision == null) {
        continue;
      }
      ligar(decision, senales, ganador.Id);
      if (debeEscalar(ganador, decision.nivel)) {
        escalar(ganador);
        aEscalar.add(ganador);
      }
    }
    if (!aEscalar.isEmpty()) {
      Database.update(aEscalar, false, AccessLevel.SYSTEM_MODE);
    }
  }

  private static void ligar(
    Decision decision,
    Map<String, Senal__c> senales,
    Id casoId
  ) {
    if (decision == null || senales == null || casoId == null) {
      return;
    }
    if (decision.clavesSenal == null) {
      return;
    }
    for (String claveSenal : decision.clavesSenal) {
      Senal__c senal = senales.get(claveSenal);
      if (
        senal != null &&
        senal.Resultado__c == IngestaConstantes.RESULTADO_APLICADO
      ) {
        senal.Incidente__c = casoId;
      }
    }
  }

  private static void marcarFallidas(
    Decision decision,
    Map<String, Senal__c> senales,
    Database.SaveResult resultado,
    Datetime ahora
  ) {
    String detalle = resultado.getErrors().isEmpty()
      ? IngestaConstantes.MOTIVO_SISTEMA
      : recortar(resultado.getErrors()[0].getMessage());
    if (decision.clavesSenal == null) {
      return;
    }
    for (String claveSenal : decision.clavesSenal) {
      Senal__c senal = senales.get(claveSenal);
      if (
        senal == null ||
        senal.Resultado__c == IngestaConstantes.RESULTADO_FALLIDO
      ) {
        continue;
      }
      if (senal.Resultado__c != IngestaConstantes.RESULTADO_APLICADO) {
        continue;
      }
      IngestaConstantes.aplicar(
        senal,
        IngestaConstantes.RESULTADO_FALLIDO,
        IngestaConstantes.MOTIVO_SISTEMA
      );
      senal.Detalle__c = detalle;
      senal.Fecha_Procesamiento__c = ahora;
    }
  }

  private static Decision decisionPorSenal(
    Map<String, Decision> decisiones,
    String claveSenal
  ) {
    if (String.isBlank(claveSenal)) {
      return null;
    }
    for (Decision decision : decisiones.values()) {
      if (decision.claveSenal == claveSenal) {
        return decision;
      }
      if (
        decision.clavesSenal != null &&
        decision.clavesSenal.contains(claveSenal)
      ) {
        return decision;
      }
    }
    return null;
  }

  private static Case armarCaso(Decision decision) {
    Case incidente = new Case();
    incidente.Clave_Abierta__c = decision.clave;
    incidente.Activo__c = decision.activoId;
    incidente.Tipo_Medicion__c = decision.tipoMedicion;
    incidente.Episodio_Id__c = decision.episodioId;
    incidente.Origen_Senal__c = decision.claveSenal;
    incidente.Status = 'New';
    incidente.Origin = 'Web';
    incidente.Priority = decision.nivel >= 2 ? PRIORIDAD_ALTA : PRIORIDAD_BAJA;
    if (incidente.Priority == PRIORIDAD_ALTA && colaCoordinacion() != null) {
      incidente.OwnerId = colaCoordinacion();
    }
    incidente.Subject = asuntoDe(decision);
    if (inyectarFalloDeCaso) {
      incidente.Tipo_Medicion__c = 'TIPO_INEXISTENTE';
    }
    return incidente;
  }

  private static String asuntoDe(Decision decision) {
    if (String.isNotBlank(decision.episodioId)) {
      return 'Corte de comunicaci\u00f3n ' + decision.episodioId;
    }
    return 'Lectura fuera de rango ' + decision.clave;
  }

  private static Boolean debeEscalar(Case abierto, Integer nivel) {
    if (abierto == null || nivel == null || nivel < 2) {
      return false;
    }
    return abierto.Priority != PRIORIDAD_ALTA;
  }

  /**
   * Sube a alta y pasa a la cola del coordinador. Si una persona ya tomo el
   * caso, lo conserva: solo se mueve mientras es de quien corre el proceso.
   */
  private static void escalar(Case abierto) {
    abierto.Priority = PRIORIDAD_ALTA;
    if (colaCoordinacion() != null && abierto.OwnerId == UserInfo.getUserId()) {
      abierto.OwnerId = colaCoordinacion();
    }
  }

  @TestVisible
  static Id colaCoordinacion() {
    if (!colaBuscada) {
      colaBuscada = true;
      for (Group cola : [
        SELECT Id
        FROM Group
        WHERE Type = 'Queue' AND DeveloperName = :COLA_COORDINACION
        WITH SYSTEM_MODE
        LIMIT 1
      ]) {
        colaCoordinacionId = cola.Id;
      }
    }
    return colaCoordinacionId;
  }

  private static String lineaRecuperado(
    String actual,
    String claveSenal,
    Datetime ahora
  ) {
    String linea =
      'Recuperado ' +
      String.valueOf(ahora) +
      ' se\u00f1al ' +
      claveSenal;
    if (String.isBlank(actual)) {
      return linea;
    }
    return actual + '\n' + linea;
  }

  private static String recortar(String valor) {
    if (String.isBlank(valor)) {
      return valor;
    }
    return valor.left(255);
  }
}
