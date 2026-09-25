/**
 * Clasificacion de severidad contra Umbral__c. No escribe nada.
 * inherited sharing: no toca datos de una persona; los umbrales son de catalogo.
 */
public inherited sharing class ClasificacionServicio {
    public class Dictamen {
        public String severidad;
        public Integer nivel;
        public String motivo;

        public Boolean esValido() {
            return String.isBlank(motivo);
        }
    }

    public static Dictamen clasificarMedicion(Decimal valor, Umbral__c umbral) {
        Dictamen dictamen = new Dictamen();
        if (umbral == null) {
            dictamen.motivo = IngestaConstantes.MOTIVO_SIN_LIMITE;
            return dictamen;
        }
        if (valor == null) {
            dictamen.motivo = IngestaConstantes.MOTIVO_VALOR;
            return dictamen;
        }
        if (umbral.Critico_Bajo__c != null && valor <= umbral.Critico_Bajo__c) {
            return conSeveridad(IngestaConstantes.SEV_CRITICO, 2);
        }
        if (umbral.Critico_Alto__c != null && valor >= umbral.Critico_Alto__c) {
            return conSeveridad(IngestaConstantes.SEV_CRITICO, 2);
        }
        if (umbral.Advertencia_Bajo__c != null && valor <= umbral.Advertencia_Bajo__c) {
            return conSeveridad(IngestaConstantes.SEV_ADVERTENCIA, 1);
        }
        if (umbral.Advertencia_Alto__c != null && valor >= umbral.Advertencia_Alto__c) {
            return conSeveridad(IngestaConstantes.SEV_ADVERTENCIA, 1);
        }
        return conSeveridad(IngestaConstantes.SEV_NORMAL, 0);
    }

    public static Dictamen clasificarConectividad(
        String estado,
        Decimal gapSegundos,
        Umbral__c umbral
    ) {
        Dictamen dictamen = new Dictamen();
        if (umbral == null) {
            dictamen.motivo = IngestaConstantes.MOTIVO_SIN_LIMITE;
            return dictamen;
        }
        if (umbral.Minutos_Advertencia__c == null || umbral.Minutos_Critico__c == null) {
            dictamen.motivo = IngestaConstantes.MOTIVO_SIN_MINUTOS;
            return dictamen;
        }
        if (estado == 'HEALTHY' || estado == 'RESTORED') {
            return conSeveridad(IngestaConstantes.SEV_NORMAL, 0);
        }
        if (estado != 'LOST') {
            dictamen.motivo = IngestaConstantes.MOTIVO_COMUNICACION;
            return dictamen;
        }
        Decimal minutos = gapSegundos == null ? 0 : gapSegundos / 60;
        if (minutos >= umbral.Minutos_Critico__c) {
            return conSeveridad(IngestaConstantes.SEV_CRITICO, 2);
        }
        if (minutos >= umbral.Minutos_Advertencia__c) {
            return conSeveridad(IngestaConstantes.SEV_ADVERTENCIA, 1);
        }
        return conSeveridad(IngestaConstantes.SEV_NORMAL, 0);
    }

    private static Dictamen conSeveridad(String severidad, Integer nivel) {
        Dictamen dictamen = new Dictamen();
        dictamen.severidad = severidad;
        dictamen.nivel = nivel;
        return dictamen;
    }
}
