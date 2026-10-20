/**
 * Una sola intervencion por problema: unicidad por Clave_Abierta__c, escalada
 * de prioridad y evidencia de recuperacion. No cierra el caso. Lo critico va a
 * la cola Coordinacion; lo bajo no es de nadie.
 *
 * El caso guarda la lectura que lo abrio y la ultima que cambio su severidad,
 * y queda Normalizado cuando el equipo vuelve a lo normal. Una lectura que
 * repite la severidad no toca el caso.
 *
 * without sharing: proceso de sistema. Lo invoca el procesamiento, no una persona.
 */
public without sharing class IncidentesServicio {
  public static final String PREFIJO_CONN = 'CONN|';
  public static final String PRIORIDAD_BAJA = 'Low';
  public static final String PRIORIDAD_ALTA = 'High';
  public static final String COLA_COORDINACION = 'Coordinacion';
  public static final String CONDICION_EN_FALLA = 'En_falla';
  public static final String CONDICION_NORMALIZADO = 'Normalizado';

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
    public Map<String, Lectura> lecturaPorSenal = new Map<String, Lectura>();
  }

  /**
   * Lo que el caso guarda de una lectura. En una camara, normalizado es que
   * volvio la comunicacion, no que el silencio todavia sea corto.
   */
  public class Lectura {
    public String texto;
    public String severidad;
    public Datetime fecha;
    public Boolean normalizado;
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
        Status,
        Severidad_Ultima_Lectura__c,
        Condicion_Equipo__c
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
    acumular(decisiones, aviso, senal, activo, tipoMedicion, dictamen, null);
  }

  /**
   * Las lecturas normales tambien entran: son las que normalizan un caso
   * abierto. escribir no abre ningun caso por ellas.
   */
  public static void acumular(
    Map<String, Decision> decisiones,
    Aviso_de_Senal__e aviso,
    Senal__c senal,
    Activo__c activo,
    String tipoMedicion,
    ClasificacionServicio.Dictamen dictamen,
    Integer lugares
  ) {
    if (
      decisiones == null ||
      aviso == null ||
      senal == null ||
      dictamen == null
    ) {
      return;
    }
    Boolean conectividad =
      aviso.Tipo_Mensaje__c == IngestaConstantes.TIPO_CONECTIVIDAD;
    Boolean restored =
      conectividad && aviso.Estado_Comunicacion__c == 'RESTORED';
    Integer nivel = dictamen.nivel == null ? 0 : dictamen.nivel;
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

    Lectura lectura = new Lectura();
    lectura.texto = LecturaFormato.lectura(
      tipoMedicion,
      aviso.Valor__c,
      aviso.Unidad__c,
      lugares,
      aviso.Estado_Comunicacion__c,
      aviso.Gap_Segundos__c
    );
    lectura.severidad = LecturaFormato.severidadApi(nivel);
    lectura.fecha = aviso.Fecha_Origen__c;
    lectura.normalizado = conectividad
      ? aviso.Estado_Comunicacion__c != 'LOST'
      : nivel < 1;
    decision.lecturaPorSenal.put(senal.Clave__c, lectura);
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
    Map<Id, Decision> recuperaciones = new Map<Id, Decision>();

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
      if (
        decision.activoId != null &&
        decision.tipoMedicion == LecturaFormato.CONECTIVIDAD &&
        lecturaDe(decision).normalizado
      ) {
        recuperaciones.put(decision.activoId, decision);
      }
      Case abierto = abiertos.get(decision.clave);
      if (abierto != null && abierto.IsClosed) {
        continue;
      }
      if (abierto != null) {
        Boolean cambio = false;
        if (decision.marcarRecuperado) {
          abierto.Description = lineaRecuperado(
            abierto.Description,
            decision.claveSenal,
            ahora
          );
          cambio = true;
        }
        if (registrarCambio(abierto, decision, ahora)) {
          cambio = true;
        }
        if (debeEscalar(abierto, decision.nivel)) {
          escalar(abierto);
          cambio = true;
        }
        if (cambio) {
          aActualizar.put(abierto.Id, abierto);
          senalPorCaso.put(abierto.Id, decision.claveSenal);
        } else if (decision.nivel >= 1) {
          ligar(decision, senales, abierto.Id);
        }
        continue;
      }
      if (decision.nivel < 1) {
        continue;
      }
      aInsertar.add(armarCaso(decision));
      senalesInsert.add(decision.clave);
    }

    normalizarCortes(recuperaciones, aActualizar, ahora);

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

  /**
   * Una camara que vuelve a comunicarse normaliza todos sus cortes abiertos. El
   * proveedor no siempre repite el episodio del corte al recuperarse: con la clave
   * del episodio sola, esos casos quedarian En falla con la camara en linea.
   * La senal no se liga a esos casos: pertenece a otro episodio.
   */
  private static void normalizarCortes(
    Map<Id, Decision> recuperaciones,
    Map<Id, Case> aActualizar,
    Datetime ahora
  ) {
    if (recuperaciones.isEmpty()) {
      return;
    }
    for (Case corte : [
      SELECT Id, Activo__c, Severidad_Ultima_Lectura__c, Condicion_Equipo__c
      FROM Case
      WHERE
        IsClosed = FALSE
        AND Activo__c IN :recuperaciones.keySet()
        AND Tipo_Medicion__c = :LecturaFormato.CONECTIVIDAD
      WITH SYSTEM_MODE
    ]) {
      if (aActualizar.containsKey(corte.Id)) {
        continue;
      }
      if (registrarCambio(corte, recuperaciones.get(corte.Activo__c), ahora)) {
        aActualizar.put(corte.Id, corte);
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
      Boolean cambio = registrarCambio(ganador, decision, Datetime.now());
      if (debeEscalar(ganador, decision.nivel)) {
        escalar(ganador);
        cambio = true;
      }
      if (cambio) {
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
    Lectura lectura = lecturaDe(decision);
    incidente.Lectura_Apertura__c = lectura.texto;
    incidente.Severidad_Apertura__c = lectura.severidad;
    incidente.Fecha_Lectura_Apertura__c = lectura.fecha;
    incidente.Ultima_Lectura__c = lectura.texto;
    incidente.Severidad_Ultima_Lectura__c = lectura.severidad;
    incidente.Fecha_Ultima_Lectura__c = lectura.fecha;
    incidente.Ultima_Senal__c = decision.claveSenal;
    incidente.Condicion_Equipo__c = CONDICION_EN_FALLA;
    if (inyectarFalloDeCaso) {
      incidente.Tipo_Medicion__c = 'TIPO_INEXISTENTE';
    }
    return incidente;
  }

  /**
   * Solo cambia el caso si la lectura trae otra severidad o otra condicion que
   * la ultima registrada: abre, escala, baja, normaliza o vuelve a fallar.
   */
  private static Boolean registrarCambio(
    Case abierto,
    Decision decision,
    Datetime ahora
  ) {
    Lectura lectura = lecturaDe(decision);
    String condicion = lectura.normalizado
      ? CONDICION_NORMALIZADO
      : CONDICION_EN_FALLA;
    if (
      abierto.Severidad_Ultima_Lectura__c == lectura.severidad &&
      abierto.Condicion_Equipo__c == condicion
    ) {
      return false;
    }
    abierto.Ultima_Lectura__c = lectura.texto;
    abierto.Severidad_Ultima_Lectura__c = lectura.severidad;
    abierto.Fecha_Ultima_Lectura__c = lectura.fecha;
    abierto.Ultima_Senal__c = decision.claveSenal;
    abierto.Condicion_Equipo__c = condicion;
    abierto.Normalizado_En__c = lectura.normalizado
      ? (lectura.fecha == null ? ahora : lectura.fecha)
      : null;
    return true;
  }

  /**
   * La lectura de la senal que decide. Una decision armada a mano, sin lectura,
   * se describe solo por su nivel.
   */
  private static Lectura lecturaDe(Decision decision) {
    Lectura lectura = decision.lecturaPorSenal == null
      ? null
      : decision.lecturaPorSenal.get(decision.claveSenal);
    if (lectura != null) {
      return lectura;
    }
    lectura = new Lectura();
    Integer nivel = decision.nivel == null ? 0 : decision.nivel;
    lectura.severidad = LecturaFormato.severidadApi(nivel);
    lectura.normalizado = nivel < 1;
    return lectura;
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
