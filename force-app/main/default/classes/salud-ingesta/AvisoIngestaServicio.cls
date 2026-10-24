/**
 * Marca en el control cuando la ingesta se cae y cuando vuelve, para avisar al
 * administrador aunque nadie mire el monitor (riesgo R-15). Una caida es la
 * ingesta cortada por fallos o sin consultas exitosas en MINUTOS_SIN_CONSULTA.
 * El flujo Avisar_Ingesta_Caida manda la campana y el correo cuando cambia
 * Caida_Desde__c: una marca por caida, no un aviso por minuto.
 *
 * without sharing: proceso de sistema. Lo invocan el disparador del control y el vigia.
 */
public without sharing class AvisoIngestaServicio {
  public static final Integer MINUTOS_SIN_CONSULTA = 10;

  /**
   * Antes de guardar el control: el corte por fallos y la vuelta. La vuelta es la
   * primera consulta exitosa despues de una caida avisada.
   */
  public static void alGuardar(
    List<Control_de_Ingesta__c> nuevos,
    Map<Id, Control_de_Ingesta__c> anteriores,
    Datetime ahora
  ) {
    for (Control_de_Ingesta__c control : nuevos) {
      Control_de_Ingesta__c anterior = anteriores.get(control.Id);
      if (anterior == null) {
        continue;
      }
      if (volvio(control, anterior)) {
        Datetime desde = anterior.Ultima_Consulta_Exitosa__c ??
          anterior.Caida_Desde__c;
        control.Minutos_Ultima_Caida__c = minutosEntre(
          desde,
          control.Ultima_Consulta_Exitosa__c
        );
        control.Caida_Desde__c = null;
        continue;
      }
      if (control.Caida_Desde__c == null && seCorto(control, anterior)) {
        marcar(
          control,
          'Se cortó tras ' +
            control.Fallos_Consecutivos__c.intValue() +
            ' fallos seguidos. Último error: ' +
            (control.Ultimo_Error__c ?? 'sin detalle'),
          ahora
        );
      }
    }
  }

  /**
   * Lo que mira el vigia: la ingesta activa, sin caida avisada y sin consultas
   * exitosas en MINUTOS_SIN_CONSULTA.
   * @return true si marco una caida
   */
  public static Boolean revisar(Datetime ahora) {
    List<Control_de_Ingesta__c> filas = [
      SELECT Id, Caida_Desde__c, Ultima_Consulta_Exitosa__c
      FROM Control_de_Ingesta__c
      WHERE Activo__c = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (filas.isEmpty() || filas[0].Caida_Desde__c != null) {
      return false;
    }
    Datetime ultima = filas[0].Ultima_Consulta_Exitosa__c;
    if (ultima != null && ultima > ahora.addMinutes(-MINUTOS_SIN_CONSULTA)) {
      return false;
    }
    Control_de_Ingesta__c marca = new Control_de_Ingesta__c(Id = filas[0].Id);
    marcar(
      marca,
      ultima == null
        ? 'Nunca hubo una consulta exitosa.'
        : 'Sin consultas exitosas desde hace ' +
          minutosEntre(ultima, ahora) +
          ' min.',
      ahora
    );
    // Si la ingesta tiene el control bloqueado, el vigia siguiente lo intenta otra vez.
    return Database.update(marca, false, AccessLevel.SYSTEM_MODE).isSuccess();
  }

  private static Boolean volvio(
    Control_de_Ingesta__c control,
    Control_de_Ingesta__c anterior
  ) {
    return anterior.Caida_Desde__c != null &&
      control.Ultima_Consulta_Exitosa__c != null &&
      control.Ultima_Consulta_Exitosa__c != anterior.Ultima_Consulta_Exitosa__c;
  }

  private static Boolean seCorto(
    Control_de_Ingesta__c control,
    Control_de_Ingesta__c anterior
  ) {
    Decimal antes = anterior.Fallos_Consecutivos__c ?? 0;
    Decimal ahora = control.Fallos_Consecutivos__c ?? 0;
    return antes <= IngestaConstantes.FALLOS_PARA_CORTAR &&
      ahora > IngestaConstantes.FALLOS_PARA_CORTAR;
  }

  private static void marcar(
    Control_de_Ingesta__c control,
    String motivo,
    Datetime ahora
  ) {
    control.Caida_Desde__c = ahora;
    control.Motivo_Caida__c = motivo.left(255);
  }

  private static Integer minutosEntre(Datetime desde, Datetime hasta) {
    if (desde == null || hasta == null) {
      return 0;
    }
    return Integer.valueOf((hasta.getTime() - desde.getTime()) / 60000);
  }
}
