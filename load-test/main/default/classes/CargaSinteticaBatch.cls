/**
 * Generador de la prueba de carga (docs/12). Fabrica paginas con el formato del
 * proveedor para el edificio de carga y las pasa por la ingesta real, una pagina
 * por transaccion como IngestaQueueable. Vive fuera de force-app y se retira al
 * terminar la prueba.
 *
 * Todo sale del indice del mensaje: categoria, equipo, fase, valor y fechas. Asi
 * un reenvio o un conflicto repiten exactamente el mensaje que ya se guardo, y
 * otro escalon sigue la misma secuencia donde quedo el anterior.
 */
public with sharing class CargaSinteticaBatch implements Database.Batchable<Integer>, Database.Stateful {
  public static final String EDIFICIO = 'BLD-CARGA-001';
  public static final String CIUDAD = 'Carga';
  public static final String TRABAJO = 'Nova Casa - Carga sintetica';
  public static final String FUENTE = 'nova-casa-simulator';
  public static final String PREFIJO_MENSAJE = 'carga_';
  // La sesion de la carga: va en la clave de cada senal y ancla el reloj virtual.
  public static final Datetime INICIO = Datetime.newInstanceGmt(
    2026,
    10,
    24,
    21,
    0,
    0
  );
  public static final Integer POR_PAGINA = 200;

  static final Integer PAGINAS_POR_CICLO = 100;
  static final Integer TOPE_PENDIENTES = 20000;
  static final Integer EVENTOS_LIBRES_MINIMO = 150000;
  static final Integer ESPERA_FRENO_MINUTOS = 5;
  static final Long SIN_REPETIDOS_ANTES_DE = 2000;
  static final Long DISTANCIA_REPETIDO = 1000;
  // El reloj virtual avanza 10 ms por mensaje: a 200.000 por hora va mas
  // despacio que el real, asi que occurredAt nunca queda en el futuro.
  static final Long MS_POR_MENSAJE = 10;
  static final Long MS_TARDIO = 3600000;
  static final Integer CAMARA = 4;

  public enum Categoria {
    VALIDO,
    RECHAZADO,
    CONFLICTO,
    DUPLICADO
  }

  static final List<String> EQUIPOS = new List<String>{
    'AST-CARGA-TEMP-001',
    'AST-CARGA-PUMP-001',
    'AST-CARGA-WATER-001',
    'AST-CARGA-ENERGY-001',
    'AST-CARGA-CAM-001'
  };
  static final List<String> TIPOS_ACTIVO = new List<String>{
    'TECHNICAL_ROOM',
    'WATER_PUMP',
    'WATER_METER',
    'ENERGY_METER',
    'SECURITY_CAMERA'
  };
  static final List<String> MEDICIONES = new List<String>{
    'TEMPERATURE',
    'WATER_PRESSURE',
    'WATER_CONSUMPTION',
    'ENERGY_CONSUMPTION',
    'CAMERA_CONNECTIVITY'
  };
  static final List<String> NOMBRES = new List<String>{
    'Sala t\u00e9cnica (carga)',
    'Bomba de presi\u00f3n (carga)',
    'Medidor de agua (carga)',
    'Medidor de energ\u00eda (carga)',
    'C\u00e1mara (carga)'
  };

  public Long siguiente;
  public Long filas;
  public Long meta;
  public Integer ritmoPorHora;
  public Datetime inicioEscalon;
  public Long filasAlIniciar;
  Long baseCiclo;
  Integer paginasCiclo;
  transient Map<String, Umbral__c> umbrales;

  public CargaSinteticaBatch(
    Long siguiente,
    Long filas,
    Long meta,
    Integer ritmoPorHora
  ) {
    this.siguiente = siguiente;
    this.filas = filas;
    this.meta = meta;
    this.ritmoPorHora = ritmoPorHora;
    this.inicioEscalon = Datetime.now();
    this.filasAlIniciar = filas;
  }

  /**
   * Sigue desde el mensaje `siguiente` hasta que la carga tenga `meta` filas.
   * El script de la prueba lee de la org cuantas hay y cual fue la ultima.
   */
  public static Id lanzar(
    Long siguiente,
    Long filas,
    Long meta,
    Integer ritmoPorHora
  ) {
    return Database.executeBatch(
      new CargaSinteticaBatch(siguiente, filas, meta, ritmoPorHora),
      1
    );
  }

  public static void detener() {
    String nombres = TRABAJO + '%';
    for (CronTrigger programado : [
      SELECT Id
      FROM CronTrigger
      WHERE CronJobDetail.Name LIKE :nombres
    ]) {
      System.abortJob(programado.Id);
    }
    for (AsyncApexJob trabajo : [
      SELECT Id
      FROM AsyncApexJob
      WHERE
        ApexClass.Name = 'CargaSinteticaBatch'
        AND JobType = 'BatchApex'
        AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
    ]) {
      System.abortJob(trabajo.Id);
    }
  }

  /**
   * El edificio en la ciudad Carga, que no tiene operadores ni avisos, y un
   * equipo de cada tipo, como los edificios reales.
   */
  public static void preparar() {
    Edificio__c edificio = new Edificio__c(
      Name = 'Edificio de carga',
      Codigo_Externo__c = EDIFICIO,
      Ciudad__c = CIUDAD
    );
    upsert edificio Codigo_Externo__c;
    List<Activo__c> activos = new List<Activo__c>();
    for (Integer i = 0; i < EQUIPOS.size(); i++) {
      activos.add(
        new Activo__c(
          Name = NOMBRES[i],
          Codigo_Externo__c = EQUIPOS[i],
          Tipo__c = TIPOS_ACTIVO[i],
          Sensor_Id__c = EQUIPOS[i].replace('AST-', 'SNS-'),
          Edificio__c = edificio.Id
        )
      );
    }
    upsert activos Codigo_Externo__c;
  }

  public static String prefijoClave() {
    return FUENTE +
      '|' +
      INICIO.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') +
      '|' +
      PREFIJO_MENSAJE;
  }

  public Iterable<Integer> start(Database.BatchableContext contexto) {
    baseCiclo = siguiente;
    Long faltan = meta - filas;
    Integer paginas = faltan <= 0
      ? 0
      : Math.min(
          PAGINAS_POR_CICLO,
          Math.ceil(faltan / (Decimal) POR_PAGINA).intValue()
        );
    paginasCiclo = paginas;
    List<Integer> lista = new List<Integer>();
    for (Integer i = 0; i < paginas; i++) {
      lista.add(i);
    }
    return lista;
  }

  public void execute(
    Database.BatchableContext contexto,
    List<Integer> paginas
  ) {
    for (Integer pagina : paginas) {
      Long desde = baseCiclo + pagina * POR_PAGINA;
      List<Object> data = new List<Object>();
      Integer nuevas = 0;
      for (Long n = desde; n < desde + POR_PAGINA; n++) {
        data.add(mensaje(n, umbrales()));
        if (creaFila(n)) {
          nuevas++;
        }
      }
      IngestaServicio.procesarPagina(
        JSON.serialize(sobre(data)),
        Datetime.now(),
        INICIO
      );
      filas += nuevas;
    }
  }

  public void finish(Database.BatchableContext contexto) {
    siguiente = baseCiclo + paginasCiclo * POR_PAGINA;
    if (paginasCiclo == 0 || filas >= meta) {
      return;
    }
    CargaSinteticaBatch continuacion = new CargaSinteticaBatch(
      siguiente,
      filas,
      meta,
      ritmoPorHora
    );
    continuacion.inicioEscalon = inicioEscalon;
    continuacion.filasAlIniciar = filasAlIniciar;
    System.scheduleBatch(
      continuacion,
      TRABAJO + ' ' + siguiente,
      esperaMinutos(),
      1
    );
  }

  /**
   * Lo que falta para ir al ritmo pedido, con un minuto como minimo. Si la org
   * se atrasa con los pendientes o se queda sin eventos, espera y no produce.
   */
  @TestVisible
  Integer esperaMinutos() {
    if (frenoActivo()) {
      return ESPERA_FRENO_MINUTOS;
    }
    Decimal objetivo = (filas - filasAlIniciar) * 60.0 / ritmoPorHora;
    Decimal transcurridos =
      (Datetime.now().getTime() - inicioEscalon.getTime()) / 60000.0;
    return Math.max(1, Math.ceil(objetivo - transcurridos).intValue());
  }

  static Boolean frenoActivo() {
    Integer tope = TOPE_PENDIENTES + 1;
    Integer pendientes = [
      SELECT COUNT()
      FROM Senal__c
      WHERE
        Resultado_Indice__c = :IngestaConstantes.RESULTADO_PENDIENTE
        AND CreatedDate >= :Datetime.now().addMinutes(-15)
      LIMIT :tope
    ];
    if (pendientes > TOPE_PENDIENTES) {
      return true;
    }
    System.OrgLimit eventos = OrgLimits.getMap()
      .get('HourlyPublishedPlatformEvents');
    return eventos != null &&
      eventos.getLimit() - eventos.getValue() < EVENTOS_LIBRES_MINIMO;
  }

  Map<String, Umbral__c> umbrales() {
    if (umbrales == null) {
      umbrales = new Map<String, Umbral__c>();
      for (Umbral__c umbral : [
        SELECT
          Clave__c,
          Unidad__c,
          Advertencia_Bajo__c,
          Advertencia_Alto__c,
          Critico_Alto__c,
          Minutos_Advertencia__c,
          Minutos_Critico__c
        FROM Umbral__c
        WHERE Vigente__c = TRUE
      ]) {
        umbrales.put(umbral.Clave__c, umbral);
      }
    }
    return umbrales;
  }

  /**
   * 2,6 % rechazadas y, desde el mensaje 2.000, 0,6 % conflictos y 1 % reenvios
   * de un mensaje mil posiciones atras. El resto son validas.
   */
  @TestVisible
  static Categoria categoria(Long n) {
    Long r = Math.mod(n * 7919 + 13, 1000);
    if (r < 26) {
      return Categoria.RECHAZADO;
    }
    if (n < SIN_REPETIDOS_ANTES_DE) {
      return Categoria.VALIDO;
    }
    if (r < 32) {
      return Categoria.CONFLICTO;
    }
    if (r < 42) {
      return Categoria.DUPLICADO;
    }
    return Categoria.VALIDO;
  }

  /**
   * Un reenvio o un conflicto no crean fila: tocan la del mensaje original.
   */
  @TestVisible
  static Boolean creaFila(Long n) {
    Categoria c = categoria(n);
    return c == Categoria.VALIDO || c == Categoria.RECHAZADO;
  }

  /**
   * La valida de medicion mas cercana a mil posiciones atras: la que se reenvia
   * o se contradice.
   */
  @TestVisible
  static Long original(Long n) {
    Long m = n - DISTANCIA_REPETIDO;
    while (categoria(m) != Categoria.VALIDO || equipoDe(m) == CAMARA) {
      m--;
    }
    return m;
  }

  static Integer equipoDe(Long m) {
    return Math.mod(m, EQUIPOS.size()).intValue();
  }

  // Tres de cada cuatro llegan una hora tarde: como en el ultimo dia real, la
  // mayoria queda Atrasado.
  static Boolean esTardio(Long m) {
    return Math.mod(m * 104729 + 7, 100) >= 25;
  }

  // Cada equipo pasa por 200 lecturas criticas, 200 de advertencia y 3.600
  // normales: abre, escala y normaliza su incidente una y otra vez.
  static String faseDe(Long m) {
    Long j = Math.mod(m / EQUIPOS.size(), 4000);
    if (j < 200) {
      return 'CRITICO';
    }
    if (j < 400) {
      return 'ADVERTENCIA';
    }
    return 'NORMAL';
  }

  @TestVisible
  static Map<String, Object> mensaje(Long n, Map<String, Umbral__c> umbrales) {
    Categoria c = categoria(n);
    Long m = c == Categoria.CONFLICTO ||
      c == Categoria.DUPLICADO
      ? original(n)
      : n;
    Integer equipo = equipoDe(m);
    Datetime ocurrio = Datetime.newInstance(
      INICIO.getTime() + m * MS_POR_MENSAJE - (esTardio(m) ? MS_TARDIO : 0L)
    );
    Map<String, Object> mensaje = new Map<String, Object>{
      'deliveryId' => 'dlv_carga_' + n,
      'messageId' => PREFIJO_MENSAJE + String.valueOf(m).leftPad(9, '0'),
      'source' => FUENTE,
      'building' => new Map<String, Object>{
        'id' => EDIFICIO,
        'name' => 'Edificio de carga',
        'city' => CIUDAD
      },
      'asset' => new Map<String, Object>{
        'id' => EQUIPOS[equipo],
        'name' => NOMBRES[equipo],
        'type' => TIPOS_ACTIVO[equipo]
      },
      'sensorId' => EQUIPOS[equipo].replace('AST-', 'SNS-'),
      'occurredAt' => iso(ocurrio),
      'publishedAt' => iso(Datetime.now())
    };
    Umbral__c umbral = umbrales.get(
      TIPOS_ACTIVO[equipo] + '|' + MEDICIONES[equipo]
    );
    String fase = faseDe(m);
    if (equipo == CAMARA) {
      mensaje.put('messageType', IngestaConstantes.TIPO_CONECTIVIDAD);
      mensaje.put('communication', comunicacion(m, ocurrio, fase, umbral));
    } else {
      Decimal valor = valorDe(umbral, fase, m);
      if (c == Categoria.CONFLICTO) {
        valor += 1;
      }
      mensaje.put('messageType', IngestaConstantes.TIPO_MEDICION);
      mensaje.put(
        'measurement',
        new Map<String, Object>{
          'type' => MEDICIONES[equipo],
          'value' => valor,
          'unit' => umbral?.Unidad__c
        }
      );
    }
    if (c == Categoria.RECHAZADO) {
      romper(mensaje, m, equipo);
    }
    return mensaje;
  }

  /**
   * Tres rechazos que el validador reconoce: un equipo que no existe, un dato
   * que falta y una unidad o un estado que no corresponden.
   */
  static void romper(Map<String, Object> mensaje, Long m, Integer equipo) {
    Long forma = Math.mod(m / 7, 3);
    if (forma == 0) {
      ((Map<String, Object>) mensaje.get('asset'))
        .put('id', 'AST-CARGA-NOEXISTE');
    } else if (equipo == CAMARA) {
      Map<String, Object> comunicacion = (Map<String, Object>) mensaje.get(
        'communication'
      );
      if (forma == 1) {
        comunicacion.remove('episodeId');
      } else {
        comunicacion.put('status', 'UNKNOWN');
      }
    } else {
      Map<String, Object> medicion = (Map<String, Object>) mensaje.get(
        'measurement'
      );
      if (forma == 1) {
        medicion.put('value', null);
      } else {
        medicion.put('unit', 'UNIDAD_X');
      }
    }
  }

  /**
   * Normal en el centro de la banda; advertencia entre el limite alto de
   * advertencia y el critico; critico un 10 % por encima del critico alto.
   * Varia hasta un 4 % para que las lecturas no sean todas iguales.
   */
  static Decimal valorDe(Umbral__c umbral, String fase, Long m) {
    Decimal base;
    if (fase == 'CRITICO') {
      base = umbral.Critico_Alto__c * 1.1;
    } else if (fase == 'ADVERTENCIA') {
      base = (umbral.Advertencia_Alto__c + umbral.Critico_Alto__c) / 2;
    } else if (umbral.Advertencia_Bajo__c != null) {
      base = (umbral.Advertencia_Bajo__c + umbral.Advertencia_Alto__c) / 2;
    } else {
      base = umbral.Advertencia_Alto__c / 2;
    }
    return (base * (1 + Math.mod(m, 5) * 0.01)).setScale(2);
  }

  static Map<String, Object> comunicacion(
    Long m,
    Datetime ocurrio,
    String fase,
    Umbral__c umbral
  ) {
    Integer gap;
    String estado = 'LOST';
    if (fase == 'CRITICO') {
      gap = (umbral.Minutos_Critico__c * 90).intValue();
    } else if (fase == 'ADVERTENCIA') {
      gap = ((umbral.Minutos_Advertencia__c + umbral.Minutos_Critico__c) * 30)
        .intValue();
    } else {
      estado = 'HEALTHY';
      gap = 30 + Math.mod(m, 30).intValue();
    }
    return new Map<String, Object>{
      'status' => estado,
      'gapSeconds' => gap,
      'lastSeenAt' => iso(ocurrio.addSeconds(-gap)),
      'episodeId' => 'ep-carga-' + (m / EQUIPOS.size() / 4000)
    };
  }

  static Map<String, Object> sobre(List<Object> data) {
    return new Map<String, Object>{
      'schemaVersion' => IngestaConstantes.VERSION_ESQUEMA,
      'generatedAt' => iso(Datetime.now()),
      'data' => data,
      'pagination' => new Map<String, Object>{
        'nextCursor' => null,
        'hasMore' => false,
        'pollAfterMs' => 10000
      }
    };
  }

  static String iso(Datetime momento) {
    return momento.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
  }
}
