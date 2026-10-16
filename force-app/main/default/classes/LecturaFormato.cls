/**
 * Como se le dice una lectura a una persona: el numero con los decimales del
 * umbral, la unidad, la comunicacion y la antiguedad. El monitor, los resumenes
 * de las paginas y el incidente usan esta clase para decir lo mismo con las
 * mismas palabras.
 *
 * inherited sharing: no consulta datos; solo da formato.
 */
public inherited sharing class LecturaFormato {
  public static final String CONECTIVIDAD = 'CAMERA_CONNECTIVITY';
  public static final String SIN_VALOR = '\u2014';

  /**
   * El texto que el caso guarda de una lectura: el valor con su unidad en una
   * medicion, el estado del corte en una camara.
   */
  public static String lectura(
    String tipoMedicion,
    Decimal valor,
    String unidad,
    Integer lugares,
    String estadoComunicacion,
    Decimal gapSegundos
  ) {
    if (tipoMedicion == CONECTIVIDAD) {
      String texto = corte(estadoComunicacion, gapSegundos);
      return texto == null ? SIN_VALOR : texto;
    }
    return valor(valor, unidad, lugares);
  }

  public static String valor(Decimal valor, String unidad, Integer lugares) {
    if (valor == null) {
      return SIN_VALOR;
    }
    String numero = conDecimales(valor, lugares == null ? 0 : lugares);
    String etiqueta = unidad(unidad);
    return String.isBlank(etiqueta) ? numero : numero + ' ' + etiqueta;
  }

  // format() respeta la configuracion regional pero borra los ceros finales.
  public static String conDecimales(Decimal valor, Integer lugares) {
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

  /**
   * El estado de una camara en una frase corta. Una camara en linea tambien se
   * nombra: si no, la fila de la camara queda en blanco y parece un error.
   */
  public static String corte(String estado, Decimal gapSegundos) {
    if (estado == 'LOST') {
      return gapSegundos == null
        ? 'Sin comunicaci\u00f3n'
        : 'Sin comunicaci\u00f3n \u00b7 ' + duracion(gapSegundos);
    }
    if (estado == 'RESTORED') {
      return 'Comunicaci\u00f3n recuperada';
    }
    if (estado == 'HEALTHY') {
      return 'En l\u00ednea';
    }
    return null;
  }

  /**
   * Solo lo anomalo: LOST y RESTORED. Una camara sana no tiene nada que avisar.
   */
  public static String comunicacion(String estado) {
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

  public static String duracion(Decimal segundos) {
    if (segundos == null) {
      return SIN_VALOR;
    }
    Long total = segundos.longValue();
    if (total < 60) {
      return total + ' s';
    }
    Long minutos = total / 60;
    if (minutos < 60) {
      return minutos + ' min';
    }
    Long horas = minutos / 60;
    if (horas < 24) {
      return horas + ' h';
    }
    return (horas / 24) + ' d';
  }

  /**
   * Cuanto hace que ocurrio. Una fecha por delante del reloj de la org, como
   * las del simulador, se lee como recien ocurrida.
   */
  public static String antiguedad(Datetime origen, Datetime ahora) {
    if (origen == null || ahora == null) {
      return 'Sin fecha';
    }
    Long segundos = (ahora.getTime() - origen.getTime()) / 1000;
    if (segundos < 60) {
      return 'hace un momento';
    }
    return 'hace ' + duracion(segundos);
  }

  public static String medicion(String tipo) {
    Map<String, String> etiquetas = new Map<String, String>{
      'TEMPERATURE' => 'Temperatura',
      'WATER_PRESSURE' => 'Presi\u00f3n de agua',
      'WATER_CONSUMPTION' => 'Consumo de agua',
      'ENERGY_CONSUMPTION' => 'Consumo de energ\u00eda',
      CONECTIVIDAD => 'Conectividad'
    };
    return etiquetas.containsKey(tipo) ? etiquetas.get(tipo) : tipo;
  }

  public static String tipoActivo(String tipo) {
    Map<String, String> etiquetas = new Map<String, String>{
      'TECHNICAL_ROOM' => 'Sala t\u00e9cnica',
      'WATER_METER' => 'Medidor de agua',
      'ENERGY_METER' => 'Medidor de energ\u00eda',
      'WATER_PUMP' => 'Bomba de presi\u00f3n',
      'SECURITY_CAMERA' => 'C\u00e1mara de seguridad'
    };
    return etiquetas.containsKey(tipo) ? etiquetas.get(tipo) : tipo;
  }

  public static String severidad(Integer nivel) {
    if (nivel == 2) {
      return 'Cr\u00edtico';
    }
    if (nivel == 1) {
      return 'Advertencia';
    }
    return 'Normal';
  }

  /**
   * El valor de la lista Severidad, sin tilde, que es el que se guarda.
   */
  public static String severidadApi(Integer nivel) {
    if (nivel == 2) {
      return IngestaConstantes.SEV_CRITICO;
    }
    if (nivel == 1) {
      return IngestaConstantes.SEV_ADVERTENCIA;
    }
    return IngestaConstantes.SEV_NORMAL;
  }

  public static Integer nivelDe(String severidad) {
    if (severidad == IngestaConstantes.SEV_CRITICO) {
      return 2;
    }
    if (severidad == IngestaConstantes.SEV_ADVERTENCIA) {
      return 1;
    }
    return 0;
  }

  public static String unidad(String unidad) {
    Map<String, String> etiquetas = new Map<String, String>{
      'BAR' => 'bar',
      'CELSIUS' => '\u00b0C',
      'LITER_PER_15_MIN' => 'L/15 min',
      'KWH_PER_15_MIN' => 'kWh/15 min',
      'SECONDS' => 's'
    };
    return etiquetas.containsKey(unidad) ? etiquetas.get(unidad) : unidad;
  }
}
