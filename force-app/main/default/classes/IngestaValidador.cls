/**
 * Validacion de un mensaje del simulador. Un mensaje invalido no impide al resto.
 */
public inherited sharing class IngestaValidador {
    public class Catalogo {
        public Map<String, Edificio__c> edificios;
        public Map<String, Activo__c> activos;
        public Map<String, Umbral__c> umbrales;

        public Catalogo() {
            this.edificios = new Map<String, Edificio__c>();
            this.activos = new Map<String, Activo__c>();
            this.umbrales = new Map<String, Umbral__c>();
        }
    }

    public class Dictamen {
        public String motivo;
        public String detalle;
        public Edificio__c edificio;
        public Activo__c activo;
        public Umbral__c umbral;
        public Datetime origen;
        public Datetime publicacion;

        public Boolean esValido() {
            return String.isBlank(motivo);
        }
    }

    public static Catalogo cargarCatalogo() {
        Catalogo catalogo = new Catalogo();
        for (Edificio__c edificio : [
            SELECT Id, Codigo_Externo__c, Name
            FROM Edificio__c
            WITH SYSTEM_MODE
        ]) {
            catalogo.edificios.put(edificio.Codigo_Externo__c, edificio);
        }
        for (Activo__c activo : [
            SELECT Id, Codigo_Externo__c, Name, Tipo__c, Edificio__c,
                   Edificio__r.Codigo_Externo__c
            FROM Activo__c
            WITH SYSTEM_MODE
        ]) {
            catalogo.activos.put(activo.Codigo_Externo__c, activo);
        }
        for (Umbral__c umbral : [
            SELECT Id, Clave__c, Tipo_Activo__c, Tipo_Medicion__c, Unidad__c,
                   Minutos_Advertencia__c, Minutos_Critico__c, Vigente__c
            FROM Umbral__c
            WHERE Vigente__c = true
            WITH SYSTEM_MODE
        ]) {
            catalogo.umbrales.put(umbral.Clave__c, umbral);
        }
        return catalogo;
    }

    public static Dictamen validar(Map<String, Object> mensaje, Catalogo catalogo, Datetime ahora) {
        Dictamen dictamen = new Dictamen();
        String messageId = texto(mensaje, 'messageId');
        String messageType = texto(mensaje, 'messageType');
        Map<String, Object> building = mapa(mensaje, 'building');
        Map<String, Object> asset = mapa(mensaje, 'asset');
        String buildingId = texto(building, 'id');
        String assetId = texto(asset, 'id');

        if (String.isBlank(messageId) || String.isBlank(texto(mensaje, 'source'))
            || building == null || asset == null
            || String.isBlank(buildingId) || String.isBlank(assetId)
            || String.isBlank(texto(mensaje, 'occurredAt'))
            || String.isBlank(texto(mensaje, 'publishedAt'))) {
            dictamen.motivo = IngestaConstantes.MOTIVO_CAMPO;
            dictamen.detalle = 'Falta un campo obligatorio del tronco comun';
            return dictamen;
        }

        if (messageType != IngestaConstantes.TIPO_MEDICION
            && messageType != IngestaConstantes.TIPO_CONECTIVIDAD) {
            dictamen.motivo = IngestaConstantes.MOTIVO_TIPO_MENSAJE;
            return dictamen;
        }

        dictamen.edificio = catalogo.edificios.get(buildingId);
        if (dictamen.edificio == null) {
            dictamen.motivo = IngestaConstantes.MOTIVO_EDIFICIO;
            return dictamen;
        }

        dictamen.activo = catalogo.activos.get(assetId);
        if (dictamen.activo == null) {
            dictamen.motivo = IngestaConstantes.MOTIVO_ACTIVO;
            return dictamen;
        }
        if (dictamen.activo.Edificio__c != dictamen.edificio.Id) {
            dictamen.motivo = IngestaConstantes.MOTIVO_ACTIVO_EDIFICIO;
            return dictamen;
        }

        dictamen.origen = parsearIso(texto(mensaje, 'occurredAt'));
        dictamen.publicacion = parsearIso(texto(mensaje, 'publishedAt'));
        if (dictamen.origen == null || dictamen.publicacion == null) {
            dictamen.motivo = IngestaConstantes.MOTIVO_FECHA;
            return dictamen;
        }
        if (dictamen.origen > ahora.addMinutes(IngestaConstantes.TOLERANCIA_FUTURO_MINUTOS)) {
            dictamen.motivo = IngestaConstantes.MOTIVO_FUTURA;
            return dictamen;
        }

        if (messageType == IngestaConstantes.TIPO_MEDICION) {
            validarMedicion(mensaje, catalogo, dictamen);
        } else {
            validarConectividad(mensaje, catalogo, dictamen);
        }
        return dictamen;
    }

    private static void validarMedicion(
        Map<String, Object> mensaje,
        Catalogo catalogo,
        Dictamen dictamen
    ) {
        Map<String, Object> measurement = mapa(mensaje, 'measurement');
        if (measurement == null) {
            dictamen.motivo = IngestaConstantes.MOTIVO_CAMPO;
            dictamen.detalle = 'Falta el bloque measurement';
            return;
        }
        String tipo = texto(measurement, 'type');
        if (String.isBlank(tipo) || !IngestaConstantes.MEDICIONES.contains(tipo)) {
            dictamen.motivo = IngestaConstantes.MOTIVO_TIPO_MEDICION;
            return;
        }
        if (measurement.get('value') == null) {
            dictamen.motivo = IngestaConstantes.MOTIVO_VALOR;
            return;
        }
        try {
            Decimal valor = decimalDe(measurement.get('value'));
            if (valor == null) {
                dictamen.motivo = IngestaConstantes.MOTIVO_VALOR;
                return;
            }
        } catch (Exception e) {
            dictamen.motivo = IngestaConstantes.MOTIVO_VALOR;
            return;
        }

        String claveUmbral = dictamen.activo.Tipo__c + '|' + tipo;
        dictamen.umbral = catalogo.umbrales.get(claveUmbral);
        if (dictamen.umbral == null) {
            dictamen.motivo = IngestaConstantes.MOTIVO_SIN_LIMITE;
            return;
        }
        String unidad = texto(measurement, 'unit');
        if (String.isBlank(unidad) || unidad != dictamen.umbral.Unidad__c) {
            dictamen.motivo = IngestaConstantes.MOTIVO_UNIDAD;
        }
    }

    private static void validarConectividad(
        Map<String, Object> mensaje,
        Catalogo catalogo,
        Dictamen dictamen
    ) {
        Map<String, Object> communication = mapa(mensaje, 'communication');
        if (communication == null
            || String.isBlank(texto(communication, 'status'))
            || String.isBlank(texto(communication, 'episodeId'))
            || String.isBlank(texto(communication, 'lastSeenAt'))
            || communication.get('gapSeconds') == null) {
            dictamen.motivo = IngestaConstantes.MOTIVO_CAMPO;
            dictamen.detalle = 'Falta un campo de communication';
            return;
        }
        if (!IngestaConstantes.ESTADOS_COMUNICACION.contains(texto(communication, 'status'))) {
            dictamen.motivo = IngestaConstantes.MOTIVO_COMUNICACION;
            return;
        }
        if (parsearIso(texto(communication, 'lastSeenAt')) == null) {
            dictamen.motivo = IngestaConstantes.MOTIVO_FECHA;
            return;
        }

        String claveUmbral = dictamen.activo.Tipo__c + '|CAMERA_CONNECTIVITY';
        dictamen.umbral = catalogo.umbrales.get(claveUmbral);
        if (dictamen.umbral == null) {
            dictamen.motivo = IngestaConstantes.MOTIVO_SIN_LIMITE;
            return;
        }
        if (dictamen.umbral.Minutos_Advertencia__c == null
            || dictamen.umbral.Minutos_Critico__c == null) {
            dictamen.motivo = IngestaConstantes.MOTIVO_SIN_MINUTOS;
        }
    }

    public static String claveDe(Map<String, Object> mensaje) {
        String source = texto(mensaje, 'source');
        String messageId = texto(mensaje, 'messageId');
        if (String.isBlank(source) || String.isBlank(messageId)) {
            return null;
        }
        return source + '|' + messageId;
    }

    public static String hashDe(Map<String, Object> mensaje) {
        String tipo = texto(mensaje, 'messageType');
        Map<String, Object> asset = mapa(mensaje, 'asset');
        String assetId = texto(asset, 'id');
        String occurredAt = texto(mensaje, 'occurredAt');
        String base;
        if (tipo == IngestaConstantes.TIPO_CONECTIVIDAD) {
            Map<String, Object> communication = mapa(mensaje, 'communication');
            base = String.join(
                new List<String>{
                    nvl(assetId),
                    nvl(texto(communication, 'status')),
                    nvl(textoPlano(communication == null ? null : communication.get('gapSeconds'))),
                    nvl(texto(communication, 'lastSeenAt')),
                    nvl(texto(communication, 'episodeId')),
                    nvl(occurredAt)
                },
                '|'
            );
        } else {
            Map<String, Object> measurement = mapa(mensaje, 'measurement');
            base = String.join(
                new List<String>{
                    nvl(assetId),
                    nvl(texto(measurement, 'type')),
                    nvl(textoPlano(measurement == null ? null : measurement.get('value'))),
                    nvl(texto(measurement, 'unit')),
                    nvl(occurredAt)
                },
                '|'
            );
        }
        return EncodingUtil.base64Encode(Crypto.generateDigest('SHA-256', Blob.valueOf(base)));
    }

    public static Datetime parsearIso(String iso) {
        if (String.isBlank(iso)) {
            return null;
        }
        try {
            String s = iso.trim();
            if (s.endsWith('Z')) {
                s = s.substring(0, s.length() - 1);
            }
            Integer plus = s.lastIndexOf('+');
            if (plus > 10) {
                s = s.substring(0, plus);
            }
            s = s.replace('T', ' ');
            Integer punto = s.indexOf('.');
            if (punto > 0) {
                String frac = s.substring(punto + 1);
                if (frac.length() > 3) {
                    s = s.substring(0, punto + 4);
                }
            }
            return Datetime.valueOfGmt(s);
        } catch (Exception e) {
            return null;
        }
    }

    public static String texto(Map<String, Object> mapa, String clave) {
        if (mapa == null || mapa.get(clave) == null) {
            return null;
        }
        String valor = String.valueOf(mapa.get(clave));
        return String.isBlank(valor) ? null : valor;
    }

    public static Map<String, Object> mapa(Map<String, Object> padre, String clave) {
        if (padre == null || !(padre.get(clave) instanceof Map<String, Object>)) {
            return null;
        }
        return (Map<String, Object>) padre.get(clave);
    }

    public static Decimal decimalDe(Object valor) {
        if (valor == null) {
            return null;
        }
        if (valor instanceof Decimal) {
            return (Decimal) valor;
        }
        if (valor instanceof Integer) {
            return Decimal.valueOf((Integer) valor);
        }
        if (valor instanceof Long) {
            return Decimal.valueOf((Long) valor);
        }
        if (valor instanceof Double) {
            return Decimal.valueOf((Double) valor);
        }
        return Decimal.valueOf(String.valueOf(valor));
    }

    private static String textoPlano(Object valor) {
        return valor == null ? null : String.valueOf(valor);
    }

    private static String nvl(String valor) {
        return valor == null ? 'null' : valor;
    }
}
