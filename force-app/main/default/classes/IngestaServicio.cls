/**
 * Orquesta un ciclo de ingesta: llama al simulador, valida, guarda senales y publica avisos.
 *
 * without sharing: la senal cubre todos los edificios, sin importar quien programe la ingesta.
 * Las consultas van en SYSTEM_MODE porque en API 67 without sharing no salta FLS.
 */
public without sharing class IngestaServicio {
  @TestVisible
  static System.Callable antesDeGuardar;

  public class ResultadoCiclo {
    public Boolean encadenar;
    public Integer indiceSiguiente;
    public String motivoCorte;
    public Integer senales;
    public Integer publicadas;
  }

  private static ResultadoCiclo detenerCiclo(String motivo) {
    ResultadoCiclo r = new ResultadoCiclo();
    r.encadenar = false;
    r.motivoCorte = motivo;
    r.senales = 0;
    r.publicadas = 0;
    return r;
  }

  public class ResultadoPagina {
    public Integer senales;
    public Integer publicadas;
    public String siguienteCursor;
    public Boolean hasMore;
    public Boolean versionRechazada;
    public String errorGuardado;
  }

  /**
   * Un eslabon de la cadena: callouts primero, DML despues.
   */
  public static ResultadoCiclo ejecutar(Integer indicePagina) {
    Control_de_Ingesta__c control = bloquearControl();
    if (control == null) {
      return detenerCiclo('Sin control de ingesta');
    }
    if (control.Activo__c != true) {
      return detenerCiclo('Ingesta inactiva');
    }
    Decimal fallos = nvlNum(control.Fallos_Consecutivos__c);
    if (fallos > IngestaConstantes.FALLOS_PARA_CORTAR) {
      return detenerCiclo('Demasiados fallos consecutivos');
    }

    Integer limite = control.Tamano_Tanda__c == null
      ? IngestaConstantes.TAMANO_TANDA_DEFECTO
      : Integer.valueOf(control.Tamano_Tanda__c);
    IngestaCliente cliente = new IngestaCliente();
    Boolean sesionNueva = false;

    if (String.isBlank(control.Cursor__c)) {
      IngestaCliente.Respuesta sesion = cliente.abrirSesion(control);
      if (!esSesionOk(sesion)) {
        return registrarCorte(control, sesion, true);
      }
      aplicarSesion(control, sesion.cuerpo);
      sesionNueva = true;
    }

    IngestaCliente.Respuesta tel = consultarConReintento(
      cliente,
      control.Cursor__c,
      limite
    );

    if (
      tel.codigo == 409 ||
      (tel.codigo == 400 &&
      faltaCursor(tel) &&
      !sesionNueva)
    ) {
      control.Ultimo_Error__c = recortar(
        (tel.codigo == 409 ? '409 cursor-conflict. ' : '400 cursor ausente. ') +
        nvl(tel.detalle)
      );
      IngestaCliente.Respuesta sesion = cliente.abrirSesion(control);
      if (!esSesionOk(sesion)) {
        return registrarCorte(control, sesion, true);
      }
      aplicarSesion(control, sesion.cuerpo);
      tel = consultarConReintento(cliente, control.Cursor__c, limite);
    }

    if (tel.tiempoAgotado) {
      return registrarCorte(control, tel, false);
    }
    if (tel.codigo == 401) {
      return registrarCorte(control, tel, true);
    }
    if (tel.codigo == 429 || tel.codigo == 503) {
      return registrarCorte(control, tel, false);
    }
    if (tel.codigo != 200) {
      return registrarCorte(control, tel, true);
    }

    ResultadoPagina pagina = procesarPagina(
      tel.cuerpo,
      Datetime.now(),
      control.Sesion_Iniciada__c
    );
    if (String.isNotBlank(pagina.siguienteCursor)) {
      control.Cursor__c = pagina.siguienteCursor;
    }
    control.Ultima_Consulta_Exitosa__c = Datetime.now();
    if (pagina.versionRechazada) {
      control.Ultimo_Error__c = recortar('schemaVersion no soportada');
    } else if (String.isNotBlank(pagina.errorGuardado)) {
      control.Ultimo_Error__c = pagina.errorGuardado;
    }
    control.Fallos_Consecutivos__c = 0;
    control.Paginas_Procesadas__c = nvlNum(control.Paginas_Procesadas__c) + 1;
    Database.update(control, AccessLevel.SYSTEM_MODE);

    ResultadoCiclo r = new ResultadoCiclo();
    r.encadenar =
      pagina.hasMore == true &&
      (indicePagina + 1) < IngestaConstantes.PAGINAS_POR_CICLO &&
      control.Activo__c == true;
    r.indiceSiguiente = indicePagina + 1;
    r.senales = pagina.senales;
    r.publicadas = pagina.publicadas;
    return r;
  }

  public static ResultadoPagina procesarPagina(String cuerpo, Datetime ahora) {
    return procesarPagina(cuerpo, ahora, null);
  }

  /**
   * Deduplica, valida, upsert y publica. Pensado tambien para tests sin callout.
   */
  public static ResultadoPagina procesarPagina(
    String cuerpo,
    Datetime ahora,
    Datetime inicioSesion
  ) {
    ResultadoPagina resultado = new ResultadoPagina();
    resultado.senales = 0;
    resultado.publicadas = 0;
    resultado.hasMore = false;
    resultado.versionRechazada = false;

    Map<String, Object> sobre = parsearSobre(cuerpo);
    Map<String, Object> pagination = IngestaValidador.mapa(sobre, 'pagination');
    resultado.siguienteCursor = IngestaValidador.texto(
      pagination,
      'nextCursor'
    );
    Object hasMore = pagination == null ? null : pagination.get('hasMore');
    resultado.hasMore = hasMore instanceof Boolean && (Boolean) hasMore;

    String version = IngestaValidador.texto(sobre, 'schemaVersion');
    List<Object> data = sobre.get('data') instanceof List<Object>
      ? (List<Object>) sobre.get('data')
      : new List<Object>();
    Boolean versionOk = version == IngestaConstantes.VERSION_ESQUEMA;

    IngestaValidador.Catalogo catalogo = IngestaValidador.cargarCatalogo();
    Map<String, Senal__c> porClave = new Map<String, Senal__c>();
    Map<String, Map<String, Object>> originales = new Map<String, Map<String, Object>>();

    for (Object item : data) {
      if (!(item instanceof Map<String, Object>)) {
        continue;
      }
      Map<String, Object> mensaje = (Map<String, Object>) item;
      String clave = IngestaValidador.claveDe(mensaje, inicioSesion);
      if (String.isBlank(clave)) {
        Senal__c huerfana = senalRechazadaSinClave(mensaje, ahora);
        porClave.put(huerfana.Clave__c, huerfana);
        originales.put(huerfana.Clave__c, mensaje);
        continue;
      }
      String hash = IngestaValidador.hashDe(mensaje);
      if (porClave.containsKey(clave)) {
        Senal__c primera = porClave.get(clave);
        primera.Entregas__c = nvlNum(primera.Entregas__c) + 1;
        primera.Ultimo_Delivery_Id__c = IngestaValidador.texto(
          mensaje,
          'deliveryId'
        );
        primera.Ultima_Fecha_Publicacion__c = IngestaValidador.parsearIso(
          IngestaValidador.texto(mensaje, 'publishedAt')
        );
        if (primera.Hash_Contenido__c != hash) {
          IngestaConstantes.aplicar(
            primera,
            IngestaConstantes.RESULTADO_CONFLICTO,
            null
          );
          primera.Detalle__c = detalleConflicto(primera.Ultimo_Delivery_Id__c);
        }
        continue;
      }
      Senal__c senal;
      if (!versionOk) {
        resultado.versionRechazada = true;
        senal = nuevaSenal(mensaje, ahora, hash, clave);
        IngestaConstantes.aplicar(
          senal,
          IngestaConstantes.RESULTADO_RECHAZADO,
          IngestaConstantes.MOTIVO_VERSION
        );
      } else {
        senal = construirSenal(mensaje, catalogo, ahora, hash, clave);
      }
      porClave.put(clave, senal);
      originales.put(clave, mensaje);
    }

    if (porClave.isEmpty()) {
      resultado.senales = 0;
      return resultado;
    }

    Set<String> clavesReales = new Set<String>();
    for (String clave : porClave.keySet()) {
      if (!clave.startsWith('sin-clave-')) {
        clavesReales.add(clave);
      }
    }
    Map<String, Senal__c> existentes = new Map<String, Senal__c>();
    if (!clavesReales.isEmpty()) {
      for (Senal__c previa : [
        SELECT
          Id,
          Clave__c,
          Hash_Contenido__c,
          Entregas__c,
          Reintentable__c,
          Fecha_Recepcion__c
        FROM Senal__c
        WHERE Clave__c IN :clavesReales
        WITH SYSTEM_MODE
      ]) {
        existentes.put(previa.Clave__c, previa);
      }
    }

    List<Senal__c> aGuardar = new List<Senal__c>();
    Set<String> publicar = new Set<String>();
    for (String clave : porClave.keySet()) {
      Senal__c senal = porClave.get(clave);
      Senal__c previa = existentes.get(clave);
      if (previa != null) {
        Boolean distinta = previa.Hash_Contenido__c != senal.Hash_Contenido__c;
        if (
          distinta ||
          senal.Resultado__c == IngestaConstantes.RESULTADO_CONFLICTO
        ) {
          senal = conflictoSobre(
            previa,
            senal,
            distinta
              ? detalleConflicto(senal.Ultimo_Delivery_Id__c)
              : senal.Detalle__c
          );
          aGuardar.add(senal);
          continue;
        }
        if (previa.Reintentable__c == true) {
          senal.Id = previa.Id;
          senal.Fecha_Recepcion__c = previa.Fecha_Recepcion__c;
          senal.Entregas__c =
            nvlNum(previa.Entregas__c) + nvlNum(senal.Entregas__c);
          if (senal.Resultado__c == IngestaConstantes.RESULTADO_PENDIENTE) {
            publicar.add(clave);
          }
        } else {
          senal = entregaSobre(previa, senal);
        }
      } else if (senal.Resultado__c == IngestaConstantes.RESULTADO_PENDIENTE) {
        publicar.add(clave);
      }
      aGuardar.add(senal);
    }

    if (antesDeGuardar != null) {
      antesDeGuardar.call('antesDeGuardar', null);
    }
    Database.UpsertResult[] resultados = Database.upsert(
      aGuardar,
      Senal__c.Clave__c,
      false,
      AccessLevel.SYSTEM_MODE
    );
    resultado.senales = aGuardar.size();

    List<Aviso_de_Senal__e> avisos = new List<Aviso_de_Senal__e>();
    List<Integer> indicesAviso = new List<Integer>();
    List<Senal__c> rastros = new List<Senal__c>();
    List<String> sinGuardar = new List<String>();
    for (Integer i = 0; i < aGuardar.size(); i++) {
      if (!resultados[i].isSuccess()) {
        publicar.remove(aGuardar[i].Clave__c);
        String error =
          aGuardar[i].Clave__c +
          ': ' +
          resultados[i].getErrors()[0].getMessage();
        if (aGuardar[i].Id == null) {
          rastros.add(rastroDe(aGuardar[i], error));
        } else {
          sinGuardar.add(error);
        }
        continue;
      }
      if (publicar.contains(aGuardar[i].Clave__c)) {
        avisos.add(avisoDe(aGuardar[i], originales.get(aGuardar[i].Clave__c)));
        indicesAviso.add(i);
      }
    }

    if (!rastros.isEmpty()) {
      Database.UpsertResult[] guardados = Database.upsert(
        rastros,
        Senal__c.Clave__c,
        false,
        AccessLevel.SYSTEM_MODE
      );
      for (Integer i = 0; i < guardados.size(); i++) {
        if (!guardados[i].isSuccess()) {
          sinGuardar.add(rastros[i].Detalle__c);
        }
      }
    }
    if (!sinGuardar.isEmpty()) {
      resultado.errorGuardado = recortar(
        sinGuardar.size() + ' senales sin guardar. ' + sinGuardar[0]
      );
    }

    if (!avisos.isEmpty()) {
      List<Database.SaveResult> publicados = EventBus.publish(avisos);
      for (Integer i = 0; i < publicados.size(); i++) {
        if (publicados[i].isSuccess()) {
          resultado.publicadas++;
        } else {
          Integer idx = indicesAviso[i];
          IngestaConstantes.aplicar(
            aGuardar[idx],
            IngestaConstantes.RESULTADO_FALLIDO,
            IngestaConstantes.MOTIVO_SISTEMA
          );
          aGuardar[idx].Detalle__c = recortar(
            publicados[i].getErrors()[0].getMessage()
          );
        }
      }
      List<Senal__c> fallosPublicacion = new List<Senal__c>();
      for (Integer i = 0; i < publicados.size(); i++) {
        if (!publicados[i].isSuccess()) {
          fallosPublicacion.add(aGuardar[indicesAviso[i]]);
        }
      }
      if (!fallosPublicacion.isEmpty()) {
        Database.update(fallosPublicacion, false, AccessLevel.SYSTEM_MODE);
      }
    }
    return resultado;
  }

  private static Control_de_Ingesta__c bloquearControl() {
    List<Control_de_Ingesta__c> filas = [
      SELECT
        Id,
        Name,
        Cursor__c,
        Escenario__c,
        Semilla__c,
        Tamano_Tanda__c,
        Sesion_Iniciada__c,
        Sesion_Expira__c,
        Ultima_Consulta_Exitosa__c,
        Ultimo_Error__c,
        Fallos_Consecutivos__c,
        Activo__c,
        Paginas_Procesadas__c
      FROM Control_de_Ingesta__c
      WHERE Activo__c = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
      FOR UPDATE
    ];
    return filas.isEmpty() ? null : filas[0];
  }

  private static IngestaCliente.Respuesta consultarConReintento(
    IngestaCliente cliente,
    String cursor,
    Integer limite
  ) {
    IngestaCliente.Respuesta primera = cliente.consultarTelemetria(
      cursor,
      limite
    );
    if (primera.tiempoAgotado) {
      return cliente.consultarTelemetria(cursor, limite);
    }
    return primera;
  }

  private static ResultadoCiclo registrarCorte(
    Control_de_Ingesta__c control,
    IngestaCliente.Respuesta respuesta,
    Boolean contarFallo
  ) {
    String detalle = respuesta.tiempoAgotado
      ? 'Tiempo agotado. ' + nvl(respuesta.detalle)
      : String.valueOf(respuesta.codigo) + ' ' + nvl(respuesta.detalle);
    control.Ultimo_Error__c = recortar(detalle);
    if (contarFallo) {
      control.Fallos_Consecutivos__c =
        nvlNum(control.Fallos_Consecutivos__c) + 1;
    }
    Database.update(control, AccessLevel.SYSTEM_MODE);
    return detenerCiclo(detalle);
  }

  private static Boolean esSesionOk(IngestaCliente.Respuesta sesion) {
    return !sesion.tiempoAgotado &&
      (sesion.codigo == 201 ||
      sesion.codigo == 200);
  }

  private static Boolean faltaCursor(IngestaCliente.Respuesta respuesta) {
    String blobTexto = (nvl(respuesta.detalle) +
      ' ' +
      nvl(respuesta.cuerpo))
      .toLowerCase();
    return blobTexto.contains('cursor') ||
      blobTexto.contains('invalid-request');
  }

  private static void aplicarSesion(
    Control_de_Ingesta__c control,
    String cuerpo
  ) {
    Map<String, Object> mapa = parsearSobre(cuerpo);
    String cursor = IngestaValidador.texto(mapa, 'cursor');
    if (String.isBlank(cursor)) {
      cursor = IngestaValidador.texto(
        IngestaValidador.mapa(mapa, 'pagination'),
        'nextCursor'
      );
    }
    if (String.isNotBlank(cursor)) {
      control.Cursor__c = cursor;
    }
    Map<String, Object> session = IngestaValidador.mapa(mapa, 'session');
    if (session != null) {
      if (session.get('seed') != null) {
        control.Semilla__c = IngestaValidador.decimalDe(session.get('seed'));
      }
      if (session.get('batchSize') != null) {
        control.Tamano_Tanda__c = IngestaValidador.decimalDe(
          session.get('batchSize')
        );
      }
      String escenario = IngestaValidador.texto(session, 'scenario');
      if (String.isNotBlank(escenario)) {
        control.Escenario__c = escenario;
      }
      control.Sesion_Iniciada__c = IngestaValidador.parsearIso(
        IngestaValidador.texto(session, 'startedAt')
      );
      control.Sesion_Expira__c = IngestaValidador.parsearIso(
        IngestaValidador.texto(session, 'expiresAt')
      );
    }
  }

  private static Map<String, Object> parsearSobre(String cuerpo) {
    if (String.isBlank(cuerpo)) {
      throw new IngestaException('Cuerpo vacio');
    }
    Object crudo = JSON.deserializeUntyped(cuerpo);
    if (!(crudo instanceof Map<String, Object>)) {
      throw new IngestaException('El cuerpo no es un objeto JSON');
    }
    return (Map<String, Object>) crudo;
  }

  private static Senal__c construirSenal(
    Map<String, Object> mensaje,
    IngestaValidador.Catalogo catalogo,
    Datetime ahora,
    String hash,
    String clave
  ) {
    Senal__c senal = nuevaSenal(mensaje, ahora, hash, clave);
    IngestaValidador.Dictamen dictamen = IngestaValidador.validar(
      mensaje,
      catalogo
    );
    senal.Edificio__c = dictamen.edificio == null ? null : dictamen.edificio.Id;
    senal.Activo__c = dictamen.activo == null ? null : dictamen.activo.Id;
    senal.Fecha_Origen__c = dictamen.origen;
    senal.Fecha_Publicacion__c = dictamen.publicacion;
    senal.Ultima_Fecha_Publicacion__c = dictamen.publicacion;
    if (dictamen.esValido()) {
      IngestaConstantes.aplicar(
        senal,
        IngestaConstantes.RESULTADO_PENDIENTE,
        null
      );
    } else {
      IngestaConstantes.aplicar(
        senal,
        IngestaConstantes.RESULTADO_RECHAZADO,
        dictamen.motivo
      );
      senal.Detalle__c = recortar(dictamen.detalle);
    }
    return senal;
  }

  private static Senal__c nuevaSenal(
    Map<String, Object> mensaje,
    Datetime ahora,
    String hash,
    String clave
  ) {
    Senal__c senal = new Senal__c();
    senal.Clave__c = clave;
    senal.Message_Id__c = IngestaValidador.texto(mensaje, 'messageId');
    String tipo = IngestaValidador.texto(mensaje, 'messageType');
    senal.Tipo_Mensaje__c = tipo == IngestaConstantes.TIPO_MEDICION ||
      tipo == IngestaConstantes.TIPO_CONECTIVIDAD
      ? tipo
      : null;
    senal.Hash_Contenido__c = hash;
    senal.Carga__c = JSON.serialize(mensaje);
    senal.Fecha_Recepcion__c = ahora;
    senal.Fecha_Procesamiento__c = null;
    senal.Entregas__c = 1;
    senal.Ultimo_Delivery_Id__c = IngestaValidador.texto(mensaje, 'deliveryId');
    senal.Ultima_Fecha_Publicacion__c = IngestaValidador.parsearIso(
      IngestaValidador.texto(mensaje, 'publishedAt')
    );
    senal.Fecha_Origen__c = IngestaValidador.parsearIso(
      IngestaValidador.texto(mensaje, 'occurredAt')
    );
    senal.Fecha_Publicacion__c = senal.Ultima_Fecha_Publicacion__c;
    return senal;
  }

  /**
   * De la entrega nueva solo se anota que existio. Lo demas no se escribe: el suscriptor
   * puede estar resolviendo la senal en este mismo segundo, y una copia de lo leido lo pisaria.
   */
  private static Senal__c entregaSobre(Senal__c previa, Senal__c entrega) {
    return new Senal__c(
      Id = previa.Id,
      Clave__c = previa.Clave__c,
      Entregas__c = nvlNum(previa.Entregas__c) + nvlNum(entrega.Entregas__c),
      Ultimo_Delivery_Id__c = entrega.Ultimo_Delivery_Id__c,
      Ultima_Fecha_Publicacion__c = entrega.Ultima_Fecha_Publicacion__c
    );
  }

  /**
   * La fila guardada conserva la primera afirmacion: carga, resumen, fechas y procesamiento.
   */
  private static Senal__c conflictoSobre(
    Senal__c previa,
    Senal__c entrega,
    String detalle
  ) {
    Senal__c conflicto = entregaSobre(previa, entrega);
    conflicto.Detalle__c = detalle;
    IngestaConstantes.aplicar(
      conflicto,
      IngestaConstantes.RESULTADO_CONFLICTO,
      null
    );
    return conflicto;
  }

  private static String detalleConflicto(String deliveryId) {
    return recortar(
      'La entrega ' +
        nvl(deliveryId) +
        ' trajo otro contenido. Se conserva la primera afirmacion.'
    );
  }

  /**
   * Lo minimo para que la senal no desaparezca: identidad, fechas y el error.
   * Sin la carga, que puede ser lo que no cupo.
   */
  private static Senal__c rastroDe(Senal__c senal, String error) {
    Senal__c rastro = new Senal__c(
      Clave__c = senal.Clave__c,
      Message_Id__c = senal.Message_Id__c == null
        ? null
        : senal.Message_Id__c.left(60),
      Tipo_Mensaje__c = senal.Tipo_Mensaje__c,
      Hash_Contenido__c = senal.Hash_Contenido__c,
      Edificio__c = senal.Edificio__c,
      Activo__c = senal.Activo__c,
      Fecha_Recepcion__c = senal.Fecha_Recepcion__c,
      Fecha_Origen__c = senal.Fecha_Origen__c,
      Fecha_Publicacion__c = senal.Fecha_Publicacion__c,
      Ultima_Fecha_Publicacion__c = senal.Ultima_Fecha_Publicacion__c,
      Ultimo_Delivery_Id__c = senal.Ultimo_Delivery_Id__c == null
        ? null
        : senal.Ultimo_Delivery_Id__c.left(60),
      Entregas__c = senal.Entregas__c,
      Detalle__c = recortar(error)
    );
    IngestaConstantes.aplicar(
      rastro,
      IngestaConstantes.RESULTADO_FALLIDO,
      IngestaConstantes.MOTIVO_SISTEMA
    );
    return rastro;
  }

  private static Senal__c senalRechazadaSinClave(
    Map<String, Object> mensaje,
    Datetime ahora
  ) {
    Senal__c senal = nuevaSenal(
      mensaje,
      ahora,
      IngestaValidador.hashDe(mensaje),
      'nova-casa-simulator|sin-id-' + String.valueOf(Crypto.getRandomInteger())
    );
    IngestaConstantes.aplicar(
      senal,
      IngestaConstantes.RESULTADO_RECHAZADO,
      IngestaConstantes.MOTIVO_CAMPO
    );
    senal.Detalle__c = 'Falta source o messageId';
    return senal;
  }

  private static Aviso_de_Senal__e avisoDe(
    Senal__c senal,
    Map<String, Object> mensaje
  ) {
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
    aviso.Codigo_Edificio__c = IngestaValidador.texto(building, 'id');
    aviso.Codigo_Activo__c = IngestaValidador.texto(asset, 'id');
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

  private static Decimal nvlNum(Decimal valor) {
    return valor == null ? 0 : valor;
  }

  private static String nvl(String valor) {
    return valor == null ? '' : valor;
  }

  private static String recortar(String valor) {
    if (String.isBlank(valor)) {
      return valor;
    }
    return valor.left(255);
  }
}
