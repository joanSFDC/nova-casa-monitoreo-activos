/**
 * Accion "Aplicar limites": recalcula Severidad__c y Severidad_Nivel__c de los
 * estados actuales que coinciden con el umbral. No toca Senal__c. No abre ni
 * cierra casos. No es automatica: la dispara el coordinador.
 *
 * with sharing para que solo vea estados de sus edificios. El DML va en modo
 * de sistema porque el coordinador no edita Estado_Actual__c: su trabajo es
 * cambiar el umbral, no la foto operativa. Esa excepcion esta acotada a esta
 * clase, que ningun LWC invoca.
 */
public with sharing class UmbralAplicacionServicio {
  public class Peticion {
    @InvocableVariable(required=true)
    public Id umbralId;
  }

  public class Respuesta {
    @InvocableVariable
    public Integer estadosActualizados;
  }

  @InvocableMethod(
    label='Aplicar límites'
    description='Recalcula la severidad de los estados actuales de este umbral. No toca la bitácora ni abre casos.'
  )
  public static List<Respuesta> aplicar(List<Peticion> peticiones) {
    List<Respuesta> respuestas = new List<Respuesta>();
    if (peticiones == null || peticiones.isEmpty()) {
      return respuestas;
    }

    Set<Id> umbralIds = new Set<Id>();
    for (Peticion peticion : peticiones) {
      if (peticion.umbralId != null) {
        umbralIds.add(peticion.umbralId);
      }
    }

    Map<Id, Umbral__c> umbrales = new Map<Id, Umbral__c>(
      [
        SELECT
          Id,
          Tipo_Activo__c,
          Tipo_Medicion__c,
          Critico_Bajo__c,
          Advertencia_Bajo__c,
          Advertencia_Alto__c,
          Critico_Alto__c,
          Minutos_Advertencia__c,
          Minutos_Critico__c
        FROM Umbral__c
        WHERE Id IN :umbralIds
        WITH USER_MODE
      ]
    );

    Set<String> tipos = new Set<String>();
    Set<String> mediciones = new Set<String>();
    for (Umbral__c umbral : umbrales.values()) {
      if (umbral.Tipo_Activo__c != null) {
        tipos.add(umbral.Tipo_Activo__c);
      }
      if (umbral.Tipo_Medicion__c != null) {
        mediciones.add(umbral.Tipo_Medicion__c);
      }
    }

    List<Estado_Actual__c> estados = new List<Estado_Actual__c>();
    if (!tipos.isEmpty() && !mediciones.isEmpty()) {
      estados = [
        SELECT
          Id,
          Valor__c,
          Tipo_Medicion__c,
          Severidad__c,
          Severidad_Nivel__c,
          Estado_Comunicacion__c,
          Gap_Segundos__c,
          Activo__r.Tipo__c
        FROM Estado_Actual__c
        WHERE Activo__r.Tipo__c IN :tipos AND Tipo_Medicion__c IN :mediciones
        WITH USER_MODE
      ];
    }

    for (Peticion peticion : peticiones) {
      Respuesta respuesta = new Respuesta();
      respuesta.estadosActualizados = 0;
      Umbral__c umbral = umbrales.get(peticion.umbralId);
      if (umbral == null) {
        respuestas.add(respuesta);
        continue;
      }

      List<Estado_Actual__c> paraActualizar = new List<Estado_Actual__c>();
      for (Estado_Actual__c estado : estados) {
        if (estado.Activo__r.Tipo__c != umbral.Tipo_Activo__c) {
          continue;
        }
        if (estado.Tipo_Medicion__c != umbral.Tipo_Medicion__c) {
          continue;
        }

        ClasificacionServicio.Dictamen dictamen = clasificar(estado, umbral);
        if (dictamen == null || !dictamen.esValido()) {
          continue;
        }
        if (
          estado.Severidad__c == dictamen.severidad &&
          estado.Severidad_Nivel__c == dictamen.nivel
        ) {
          continue;
        }

        estado.Severidad__c = dictamen.severidad;
        estado.Severidad_Nivel__c = dictamen.nivel;
        paraActualizar.add(estado);
      }

      if (!paraActualizar.isEmpty()) {
        // El coordinador no edita Estado_Actual__c; la accion si, en su nombre.
        Database.update(paraActualizar, AccessLevel.SYSTEM_MODE);
        respuesta.estadosActualizados = paraActualizar.size();
      }
      respuestas.add(respuesta);
    }

    return respuestas;
  }

  /**
   * La conectividad guarda el silencio tambien en Valor__c. Clasificarla
   * por bandas de medicion la deja siempre en Normal. Se usa el dictamen
   * de minutos, igual que el procesamiento.
   */
  private static ClasificacionServicio.Dictamen clasificar(
    Estado_Actual__c estado,
    Umbral__c umbral
  ) {
    if (umbral.Tipo_Medicion__c == 'CAMERA_CONNECTIVITY') {
      return ClasificacionServicio.clasificarConectividad(
        estado.Estado_Comunicacion__c,
        estado.Gap_Segundos__c,
        umbral
      );
    }
    if (estado.Valor__c == null) {
      return null;
    }
    return ClasificacionServicio.clasificarMedicion(estado.Valor__c, umbral);
  }
}
