/**
 * Orquesta una tanda de avisos: consulta, resuelve en memoria, escribe estado,
 * incidente y bitacora. Orden: estado, caso, senal. Si escribio estados y es la
 * primera tanda de su ventana fija de 30 segundos, publica el timbre del monitor,
 * Panel_Actualizado__e.
 *
 * without sharing: proceso de sistema. El disparador corre como el usuario de
 * integracion (scripts/configurar-suscriptor.sh), que no ve por ciudad.
 */
public without sharing class ProcesamientoServicio {
  private static final Integer LARGO_LECTURA = 100;
  @TestVisible
  static final Long VENTANA_TIMBRE_MS = 30000;

  public class ResultadoTanda {
    public Integer senales;
    public Integer aplicadas;
    public Integer rechazadas;
    public Integer atrasadas;
    public Integer fallidas;

    public ResultadoTanda() {
      this.senales = 0;
      this.aplicadas = 0;
      this.rechazadas = 0;
      this.atrasadas = 0;
      this.fallidas = 0;
    }
  }

  @TestVisible
  static Boolean inyectarFalloDeEscritura = false;

  @TestVisible
  static Integer timbresPublicados = 0;

  public static ResultadoTanda procesar(List<Aviso_de_Senal__e> avisos) {
    ResultadoTanda resultado = new ResultadoTanda();
    if (avisos == null || avisos.isEmpty()) {
      return resultado;
    }

    Set<String> clavesSenal = new Set<String>();
    Set<String> codigosActivo = new Set<String>();
    Set<String> clavesEstado = new Set<String>();
    Set<String> clavesIncidente = new Set<String>();
    for (Aviso_de_Senal__e aviso : avisos) {
      if (String.isNotBlank(aviso.Clave__c)) {
        clavesSenal.add(aviso.Clave__c);
      }
      if (String.isNotBlank(aviso.Codigo_Activo__c)) {
        codigosActivo.add(aviso.Codigo_Activo__c);
        String tipo = tipoMedicionDe(aviso);
        if (String.isNotBlank(tipo)) {
          clavesEstado.add(aviso.Codigo_Activo__c + '|' + tipo);
        }
      }
      String claveIncidente = IncidentesServicio.claveDe(aviso);
      if (String.isNotBlank(claveIncidente)) {
        clavesIncidente.add(claveIncidente);
      }
    }

    Map<String, Senal__c> senales = cargarSenales(clavesSenal);
    Map<String, Activo__c> activos = cargarActivos(codigosActivo);
    Map<String, Estado_Actual__c> estados = cargarEstados(clavesEstado);
    Map<String, Umbral__c> umbrales = cargarUmbrales();
    Map<String, Case> abiertos = IncidentesServicio.cargarAbiertos(
      clavesIncidente
    );

    Datetime ahora = Datetime.now();
    Tanda tanda = new Tanda(activos, umbrales, estados, ahora);
    Map<String, Senal__c> aActualizar = tanda.aActualizar;
    Map<String, Estado_Actual__c> aUpsertar = tanda.aUpsertar;
    Map<String, String> estadoAClaveSenal = tanda.estadoAClaveSenal;
    Map<String, IncidentesServicio.Decision> decisiones = tanda.decisiones;

    for (Aviso_de_Senal__e aviso : avisos) {
      if (
        String.isBlank(aviso.Clave__c) || !senales.containsKey(aviso.Clave__c)
      ) {
        continue;
      }
      Senal__c senal = senales.get(aviso.Clave__c);
      if (senal.Resultado__c != IngestaConstantes.RESULTADO_PENDIENTE) {
        continue;
      }
      resultado.senales++;
      aActualizar.put(senal.Clave__c, senal);
      resolver(aviso, senal, tanda);
    }

    List<Estado_Actual__c> listaEstados = ordenarPorActivo(aUpsertar.values());
    Datetime ultimaPrevia = listaEstados.isEmpty()
      ? null
      : ultimaModificacionDeEstados();
    if (inyectarFalloDeEscritura && !listaEstados.isEmpty()) {
      listaEstados[0].Activo__c = null;
    }
    if (!listaEstados.isEmpty()) {
      Database.UpsertResult[] resEstados = Database.upsert(
        listaEstados,
        Estado_Actual__c.Clave__c,
        false,
        AccessLevel.SYSTEM_MODE
      );
      for (Integer i = 0; i < resEstados.size(); i++) {
        if (resEstados[i].isSuccess()) {
          continue;
        }
        String claveEstado = listaEstados[i].Clave__c;
        String claveSenal = estadoAClaveSenal.get(claveEstado);
        Senal__c senal = aActualizar.get(claveSenal);
        if (senal == null) {
          continue;
        }
        IngestaConstantes.aplicar(
          senal,
          IngestaConstantes.RESULTADO_FALLIDO,
          IngestaConstantes.MOTIVO_SISTEMA
        );
        senal.Detalle__c = recortar(resEstados[i].getErrors()[0].getMessage());
        senal.Fecha_Procesamiento__c = ahora;
      }
    }

    IncidentesServicio.escribir(decisiones, abiertos, aActualizar, ahora);

    List<Senal__c> listaSenales = aActualizar.values();
    if (!listaSenales.isEmpty()) {
      Database.SaveResult[] resSenales = Database.update(
        listaSenales,
        false,
        AccessLevel.SYSTEM_MODE
      );
      for (Integer i = 0; i < resSenales.size(); i++) {
        if (!resSenales[i].isSuccess()) {
          IngestaConstantes.aplicar(
            listaSenales[i],
            IngestaConstantes.RESULTADO_FALLIDO,
            IngestaConstantes.MOTIVO_SISTEMA
          );
          listaSenales[i].Detalle__c = recortar(
            resSenales[i].getErrors()[0].getMessage()
          );
        }
      }
    }

    for (Senal__c senal : aActualizar.values()) {
      if (senal.Resultado__c == IngestaConstantes.RESULTADO_APLICADO) {
        resultado.aplicadas++;
      } else if (senal.Resultado__c == IngestaConstantes.RESULTADO_RECHAZADO) {
        resultado.rechazadas++;
      } else if (senal.Resultado__c == IngestaConstantes.RESULTADO_ATRASADO) {
        resultado.atrasadas++;
      } else if (senal.Resultado__c == IngestaConstantes.RESULTADO_FALLIDO) {
        resultado.fallidas++;
      }
    }

    if (!listaEstados.isEmpty() && debeTocarTimbre(ultimaPrevia, ahora)) {
      avisarAlMonitor();
    }

    marcarReanudacion(avisos);
    return resultado;
  }

  /**
   * Toca la primera tanda de cada ventana fija de 30 s: si la ultima escritura de
   * estados cayo en otra ventana, nadie toco todavia en esta. Con «hace menos de
   * 30 s» y la ingesta continua no tocaria nunca. Lo que cambie despues en la
   * misma ventana lo recoge la siguiente o la vigilancia de un minuto del monitor.
   */
  @TestVisible
  static Boolean debeTocarTimbre(Datetime ultimaPrevia, Datetime ahora) {
    if (ultimaPrevia == null || ahora == null) {
      return true;
    }
    return ultimaPrevia.getTime() / VENTANA_TIMBRE_MS !=
      ahora.getTime() / VENTANA_TIMBRE_MS;
  }

  // Unas 20 filas, una por equipo y medicion: leerlas no cuesta casi nada.
  private static Datetime ultimaModificacionDeEstados() {
    AggregateResult[] fila = [
      SELECT MAX(SystemModstamp) ultima
      FROM Estado_Actual__c
      WITH SYSTEM_MODE
    ];
    return fila.isEmpty() ? null : (Datetime) fila[0].get('ultima');
  }

  /**
   * Si el timbre no sale, la vigilancia de un minuto del monitor lo cubre: no
   * es motivo para marcar ninguna senal como fallida.
   */
  private static void avisarAlMonitor() {
    if (EventBus.publish(new Panel_Actualizado__e()).isSuccess()) {
      timbresPublicados++;
    }
  }

  public static ResultadoTanda procesarPendientes() {
    List<Senal__c> pendientes = [
      SELECT
        Id,
        Clave__c,
        Message_Id__c,
        Tipo_Mensaje__c,
        Resultado__c,
        Carga__c,
        Fecha_Origen__c,
        Activo__r.Codigo_Externo__c,
        Edificio__r.Codigo_Externo__c
      FROM Senal__c
      WHERE Resultado__c = :IngestaConstantes.RESULTADO_PENDIENTE
      WITH SYSTEM_MODE
      LIMIT 200
    ];
    List<Aviso_de_Senal__e> avisos = new List<Aviso_de_Senal__e>();
    for (Senal__c senal : pendientes) {
      avisos.add(avisoDesdeSenal(senal));
    }
    return procesar(avisos);
  }

  /**
   * Lo que comparten las senales de una tanda al resolverse: el catalogo y los
   * estados cargados, lo que se va a escribir y las decisiones de incidente.
   */
  private class Tanda {
    final Map<String, Activo__c> activos;
    final Map<String, Umbral__c> umbrales;
    final Map<String, Estado_Actual__c> estados;
    final Datetime ahora;
    Map<String, Estado_Actual__c> aUpsertar = new Map<String, Estado_Actual__c>();
    Map<String, Senal__c> aActualizar = new Map<String, Senal__c>();
    Map<String, String> estadoAClaveSenal = new Map<String, String>();
    Map<String, IncidentesServicio.Decision> decisiones = new Map<String, IncidentesServicio.Decision>();

    Tanda(
      Map<String, Activo__c> activos,
      Map<String, Umbral__c> umbrales,
      Map<String, Estado_Actual__c> estados,
      Datetime ahora
    ) {
      this.activos = activos;
      this.umbrales = umbrales;
      this.estados = estados;
      this.ahora = ahora;
    }
  }

  /**
   * Una senal se rechaza, queda atrasada o gana su estado: entonces se aplica y
   * suma a la decision de su incidente.
   */
  private static void resolver(
    Aviso_de_Senal__e aviso,
    Senal__c senal,
    Tanda tanda
  ) {
    String motivo = motivoDeRechazo(aviso, tanda);
    if (motivo != null) {
      rechazar(senal, motivo, tanda.ahora);
      return;
    }
    Activo__c activo = tanda.activos.get(aviso.Codigo_Activo__c);
    String tipoMedicion = tipoMedicionDe(aviso);
    Umbral__c umbral = tanda.umbrales.get(activo.Tipo__c + '|' + tipoMedicion);
    Integer lugares = umbral == null ||
      umbral.Decimales__c == null
      ? 0
      : Integer.valueOf(umbral.Decimales__c);
    senal.Lectura__c = LecturaFormato.lectura(
        tipoMedicion,
        aviso.Valor__c,
        aviso.Unidad__c,
        lugares,
        aviso.Estado_Comunicacion__c,
        aviso.Gap_Segundos__c
      )
      ?.left(LARGO_LECTURA);
    if (unidadIncompatible(aviso, umbral)) {
      rechazar(senal, IngestaConstantes.MOTIVO_UNIDAD, tanda.ahora);
      return;
    }
    ClasificacionServicio.Dictamen dictamen = clasificar(aviso, umbral);
    if (!dictamen.esValido()) {
      rechazar(senal, dictamen.motivo, tanda.ahora);
      return;
    }

    String claveEstado = aviso.Codigo_Activo__c + '|' + tipoMedicion;
    Estado_Actual__c vigente = tanda.estados.get(claveEstado);
    if (!esMasVigente(aviso, vigente)) {
      atrasar(senal, tanda.ahora);
      return;
    }
    Estado_Actual__c estado = vigente == null
      ? new Estado_Actual__c(Activo__c = activo.Id)
      : vigente;
    estado.Clave__c = claveEstado;
    estado.Tipo_Medicion__c = tipoMedicion;
    estado.Fecha_Origen__c = aviso.Fecha_Origen__c;
    estado.Fecha_Actualizacion__c = tanda.ahora;
    estado.Ultimo_Message_Id__c = aviso.Message_Id__c;
    estado.Severidad__c = dictamen.severidad;
    estado.Severidad_Nivel__c = dictamen.nivel;
    copiarLectura(estado, aviso);
    marcarGanadora(senal, claveEstado, estado, tanda);
    senal.Activo__c = activo.Id;
    IncidentesServicio.acumular(
      tanda.decisiones,
      aviso,
      senal,
      activo,
      tipoMedicion,
      dictamen,
      lugares
    );
  }

  private static String motivoDeRechazo(Aviso_de_Senal__e aviso, Tanda tanda) {
    if (
      aviso.Tipo_Mensaje__c != IngestaConstantes.TIPO_MEDICION &&
      aviso.Tipo_Mensaje__c != IngestaConstantes.TIPO_CONECTIVIDAD
    ) {
      return IngestaConstantes.MOTIVO_TIPO_MENSAJE;
    }
    if (!tanda.activos.containsKey(aviso.Codigo_Activo__c)) {
      return IngestaConstantes.MOTIVO_ACTIVO;
    }
    return null;
  }

  private static Boolean unidadIncompatible(
    Aviso_de_Senal__e aviso,
    Umbral__c umbral
  ) {
    return aviso.Tipo_Mensaje__c == IngestaConstantes.TIPO_MEDICION &&
      umbral != null &&
      String.isNotBlank(aviso.Unidad__c) &&
      aviso.Unidad__c != umbral.Unidad__c;
  }

  private static ClasificacionServicio.Dictamen clasificar(
    Aviso_de_Senal__e aviso,
    Umbral__c umbral
  ) {
    if (aviso.Tipo_Mensaje__c == IngestaConstantes.TIPO_MEDICION) {
      return ClasificacionServicio.clasificarMedicion(aviso.Valor__c, umbral);
    }
    return ClasificacionServicio.clasificarConectividad(
      aviso.Estado_Comunicacion__c,
      aviso.Gap_Segundos__c,
      umbral
    );
  }

  private static void atrasar(Senal__c senal, Datetime ahora) {
    IngestaConstantes.aplicar(
      senal,
      IngestaConstantes.RESULTADO_ATRASADO,
      null
    );
    senal.Fecha_Procesamiento__c = ahora;
  }

  /**
   * Una medicion deja su valor y borra lo de comunicacion; una camara, al reves.
   * Un latido sano cierra el episodio del corte.
   */
  private static void copiarLectura(
    Estado_Actual__c estado,
    Aviso_de_Senal__e aviso
  ) {
    Boolean medicion = aviso.Tipo_Mensaje__c == IngestaConstantes.TIPO_MEDICION;
    estado.Valor__c = medicion ? aviso.Valor__c : null;
    estado.Unidad__c = medicion ? aviso.Unidad__c : null;
    estado.Estado_Comunicacion__c = medicion
      ? null
      : aviso.Estado_Comunicacion__c;
    estado.Gap_Segundos__c = medicion ? null : aviso.Gap_Segundos__c;
    estado.Ultima_Vez_Visto__c = medicion ? null : aviso.Ultima_Vez_Visto__c;
    estado.Sin_Comunicacion_Num__c = !medicion &&
      aviso.Estado_Comunicacion__c == 'LOST'
      ? 1
      : 0;
    estado.Episodio_Id__c = medicion ||
      aviso.Estado_Comunicacion__c == 'HEALTHY'
      ? null
      : aviso.Episodio_Id__c;
  }

  /**
   * La mas vigente de la tanda gana el estado; la que ganaba antes pasa a
   * atrasada.
   */
  private static void marcarGanadora(
    Senal__c senal,
    String claveEstado,
    Estado_Actual__c estado,
    Tanda tanda
  ) {
    String ganadorPrevio = tanda.estadoAClaveSenal.get(claveEstado);
    if (String.isNotBlank(ganadorPrevio) && ganadorPrevio != senal.Clave__c) {
      Senal__c perdedora = tanda.aActualizar.get(ganadorPrevio);
      if (perdedora != null) {
        atrasar(perdedora, tanda.ahora);
      }
    }
    tanda.estados.put(claveEstado, estado);
    tanda.aUpsertar.put(claveEstado, estado);
    tanda.estadoAClaveSenal.put(claveEstado, senal.Clave__c);
    IngestaConstantes.aplicar(
      senal,
      IngestaConstantes.RESULTADO_APLICADO,
      null
    );
    senal.Fecha_Procesamiento__c = tanda.ahora;
  }

  private static Boolean esMasVigente(
    Aviso_de_Senal__e aviso,
    Estado_Actual__c vigente
  ) {
    if (vigente == null || vigente.Fecha_Origen__c == null) {
      return true;
    }
    if (aviso.Fecha_Origen__c == null) {
      return false;
    }
    if (aviso.Fecha_Origen__c > vigente.Fecha_Origen__c) {
      return true;
    }
    if (aviso.Fecha_Origen__c < vigente.Fecha_Origen__c) {
      return false;
    }
    String actual = vigente.Ultimo_Message_Id__c == null
      ? ''
      : vigente.Ultimo_Message_Id__c;
    String candidato = aviso.Message_Id__c == null ? '' : aviso.Message_Id__c;
    if (candidato == actual) {
      return true;
    }
    return candidato > actual;
  }

  private static void rechazar(Senal__c senal, String motivo, Datetime ahora) {
    IngestaConstantes.aplicar(
      senal,
      IngestaConstantes.RESULTADO_RECHAZADO,
      motivo
    );
    senal.Fecha_Procesamiento__c = ahora;
  }

  private static Map<String, Senal__c> cargarSenales(Set<String> claves) {
    Map<String, Senal__c> mapa = new Map<String, Senal__c>();
    if (claves.isEmpty()) {
      return mapa;
    }
    for (Senal__c senal : [
      SELECT
        Id,
        Clave__c,
        Resultado__c,
        Motivo__c,
        Reintentable__c,
        Detalle__c,
        Fecha_Procesamiento__c,
        Activo__c,
        Carga__c,
        Incidente__c
      FROM Senal__c
      WHERE Clave__c IN :claves
      WITH SYSTEM_MODE
    ]) {
      mapa.put(senal.Clave__c, senal);
    }
    return mapa;
  }

  private static Map<String, Activo__c> cargarActivos(Set<String> codigos) {
    Map<String, Activo__c> mapa = new Map<String, Activo__c>();
    if (codigos.isEmpty()) {
      return mapa;
    }
    for (Activo__c activo : [
      SELECT Id, Codigo_Externo__c, Tipo__c, Edificio__c
      FROM Activo__c
      WHERE Codigo_Externo__c IN :codigos
      WITH SYSTEM_MODE
    ]) {
      mapa.put(activo.Codigo_Externo__c, activo);
    }
    return mapa;
  }

  private static Map<String, Estado_Actual__c> cargarEstados(
    Set<String> claves
  ) {
    Map<String, Estado_Actual__c> mapa = new Map<String, Estado_Actual__c>();
    if (claves.isEmpty()) {
      return mapa;
    }
    for (Estado_Actual__c estado : [
      SELECT
        Id,
        Clave__c,
        Activo__c,
        Fecha_Origen__c,
        Ultimo_Message_Id__c,
        Tipo_Medicion__c,
        Valor__c,
        Unidad__c,
        Severidad__c,
        Severidad_Nivel__c
      FROM Estado_Actual__c
      WHERE Clave__c IN :claves
      WITH SYSTEM_MODE
    ]) {
      mapa.put(estado.Clave__c, estado);
    }
    return mapa;
  }

  private static Map<String, Umbral__c> cargarUmbrales() {
    Map<String, Umbral__c> mapa = new Map<String, Umbral__c>();
    for (Umbral__c umbral : [
      SELECT
        Id,
        Clave__c,
        Tipo_Activo__c,
        Tipo_Medicion__c,
        Unidad__c,
        Critico_Bajo__c,
        Critico_Alto__c,
        Advertencia_Bajo__c,
        Advertencia_Alto__c,
        Minutos_Advertencia__c,
        Minutos_Critico__c,
        Decimales__c,
        Vigente__c
      FROM Umbral__c
      WHERE Vigente__c = TRUE
      WITH SYSTEM_MODE
    ]) {
      mapa.put(umbral.Clave__c, umbral);
    }
    return mapa;
  }

  private static List<Estado_Actual__c> ordenarPorActivo(
    List<Estado_Actual__c> origen
  ) {
    List<EstadoPorActivo> envoltorios = new List<EstadoPorActivo>();
    for (Estado_Actual__c estado : origen) {
      envoltorios.add(new EstadoPorActivo(estado));
    }
    envoltorios.sort();
    List<Estado_Actual__c> ordenados = new List<Estado_Actual__c>();
    for (EstadoPorActivo item : envoltorios) {
      ordenados.add(item.registro);
    }
    return ordenados;
  }

  private static void marcarReanudacion(List<Aviso_de_Senal__e> avisos) {
    if (avisos.isEmpty()) {
      return;
    }
    Aviso_de_Senal__e ultimo = avisos[avisos.size() - 1];
    if (ultimo.ReplayId == null) {
      return;
    }
    // Fuera del disparador (pruebas directas y procesarPendientes) no hay contexto.
    if (!Trigger.isExecuting) {
      return;
    }
    EventBus.TriggerContext.currentContext()
      .setResumeCheckpoint(ultimo.ReplayId);
  }

  private static String tipoMedicionDe(Aviso_de_Senal__e aviso) {
    if (String.isNotBlank(aviso.Tipo_Medicion__c)) {
      return aviso.Tipo_Medicion__c;
    }
    return aviso.Tipo_Mensaje__c == IngestaConstantes.TIPO_CONECTIVIDAD
      ? 'CAMERA_CONNECTIVITY'
      : null;
  }

  public static Aviso_de_Senal__e avisoDesdeSenal(Senal__c senal) {
    Map<String, Object> mensaje = new Map<String, Object>();
    if (String.isNotBlank(senal.Carga__c)) {
      try {
        Object crudo = JSON.deserializeUntyped(senal.Carga__c);
        if (crudo instanceof Map<String, Object>) {
          mensaje = (Map<String, Object>) crudo;
        }
      } catch (Exception e) {
        mensaje = new Map<String, Object>();
      }
    }
    Map<String, Object> building = IngestaValidador.mapa(mensaje, 'building');
    Map<String, Object> asset = IngestaValidador.mapa(mensaje, 'asset');
    Map<String, Object> measurement = IngestaValidador.mapa(
      mensaje,
      'measurement'
    );
    Map<String, Object> communication = IngestaValidador.mapa(
      mensaje,
      'communication'
    );
    Aviso_de_Senal__e aviso = new Aviso_de_Senal__e();
    aviso.Clave__c = senal.Clave__c;
    aviso.Message_Id__c = senal.Message_Id__c;
    aviso.Tipo_Mensaje__c = senal.Tipo_Mensaje__c;
    aviso.Codigo_Edificio__c = building != null
      ? IngestaValidador.texto(building, 'id')
      : senal.Edificio__r == null ? null : senal.Edificio__r.Codigo_Externo__c;
    aviso.Codigo_Activo__c = asset != null
      ? IngestaValidador.texto(asset, 'id')
      : senal.Activo__r == null ? null : senal.Activo__r.Codigo_Externo__c;
    aviso.Fecha_Origen__c = senal.Fecha_Origen__c;
    if (senal.Tipo_Mensaje__c == IngestaConstantes.TIPO_MEDICION) {
      aviso.Tipo_Medicion__c = IngestaValidador.texto(measurement, 'type');
      aviso.Valor__c = IngestaValidador.decimalDe(
        measurement == null ? null : measurement.get('value')
      );
      aviso.Unidad__c = IngestaValidador.texto(measurement, 'unit');
    } else {
      aviso.Tipo_Medicion__c = 'CAMERA_CONNECTIVITY';
      aviso.Estado_Comunicacion__c = IngestaValidador.texto(
        communication,
        'status'
      );
      aviso.Gap_Segundos__c = IngestaValidador.decimalDe(
        communication == null ? null : communication.get('gapSeconds')
      );
      aviso.Ultima_Vez_Visto__c = IngestaValidador.parsearIso(
        IngestaValidador.texto(communication, 'lastSeenAt')
      );
      aviso.Episodio_Id__c = IngestaValidador.texto(communication, 'episodeId');
    }
    return aviso;
  }

  private static String recortar(String valor) {
    if (String.isBlank(valor)) {
      return valor;
    }
    return valor.left(255);
  }

  private class EstadoPorActivo implements Comparable {
    public Estado_Actual__c registro;

    EstadoPorActivo(Estado_Actual__c registro) {
      this.registro = registro;
    }

    public Integer compareTo(Object other) {
      EstadoPorActivo o = (EstadoPorActivo) other;
      String a = registro.Activo__c == null
        ? ''
        : String.valueOf(registro.Activo__c);
      String b = o.registro.Activo__c == null
        ? ''
        : String.valueOf(o.registro.Activo__c);
      return a.compareTo(b);
    }
  }
}
