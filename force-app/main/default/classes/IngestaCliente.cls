/**
 * Cliente HTTP del simulador. El token no viaja en este codigo: lo inyecta
 * la Named Credential Nova_Casa_Simulador.
 *
 * without sharing: es un proceso de sistema. No hay datos de una persona.
 */
public without sharing class IngestaCliente {
    public class Respuesta {
        public Integer codigo;
        public String cuerpo;
        public Boolean tiempoAgotado;
        public String detalle;

        public Respuesta(Integer codigo, String cuerpo) {
            this.codigo = codigo;
            this.cuerpo = cuerpo == null ? '' : cuerpo;
            this.tiempoAgotado = false;
            this.detalle = extraerDetalle(this.cuerpo);
        }
    }

    public Respuesta respuestaPorTiempoAgotado(String mensaje) {
        Respuesta r = new Respuesta(0, '');
        r.tiempoAgotado = true;
        r.detalle = mensaje;
        return r;
    }

    /**
     * POST /session. El cuerpo no lleva secreto.
     */
    public Respuesta abrirSesion(Control_de_Ingesta__c control) {
        Map<String, Object> cuerpo = new Map<String, Object>{
            'scenario' => String.isBlank(control.Escenario__c)
                ? IngestaConstantes.ESCENARIO_DEFECTO
                : control.Escenario__c,
            'seed' => control.Semilla__c == null
                ? IngestaConstantes.SEMILLA_DEFECTO
                : Integer.valueOf(control.Semilla__c),
            'batchSize' => control.Tamano_Tanda__c == null
                ? IngestaConstantes.TAMANO_TANDA_DEFECTO
                : Integer.valueOf(control.Tamano_Tanda__c),
            'buildings' => codigosEdificio()
        };

        HttpRequest peticion = nuevaPeticion(
            'callout:' + IngestaConstantes.CREDENCIAL + '/session',
            'POST',
            null
        );
        peticion.setHeader('Content-Type', 'application/json');
        peticion.setBody(JSON.serialize(cuerpo));
        return enviar(peticion);
    }

    /**
     * GET /telemetry con el cursor en cabecera. Reenviar el mismo cursor es idempotente.
     */
    public Respuesta consultarTelemetria(String cursor, Integer limite) {
        Integer tope = limite == null || limite < 1
            ? IngestaConstantes.TAMANO_TANDA_DEFECTO
            : limite;
        HttpRequest peticion = nuevaPeticion(
            'callout:' + IngestaConstantes.CREDENCIAL + '/telemetry?limit=' + tope,
            'GET',
            cursor
        );
        return enviar(peticion);
    }

    private HttpRequest nuevaPeticion(String endpoint, String metodo, String cursor) {
        HttpRequest peticion = new HttpRequest();
        peticion.setEndpoint(endpoint);
        peticion.setMethod(metodo);
        peticion.setTimeout(IngestaConstantes.TIEMPO_ESPERA_MS);
        peticion.setHeader('Accept', 'application/json');
        if (String.isNotBlank(cursor)) {
            peticion.setHeader('X-Simulator-Cursor', cursor);
        }
        return peticion;
    }

    private Respuesta enviar(HttpRequest peticion) {
        try {
            HttpResponse http = new Http().send(peticion);
            return new Respuesta(http.getStatusCode(), http.getBody());
        } catch (System.CalloutException e) {
            return respuestaPorTiempoAgotado(e.getMessage());
        }
    }

    private List<String> codigosEdificio() {
        List<String> codigos = new List<String>();
        for (Edificio__c edificio : [
            SELECT Codigo_Externo__c
            FROM Edificio__c
            WITH SYSTEM_MODE
            ORDER BY Codigo_Externo__c
        ]) {
            if (String.isNotBlank(edificio.Codigo_Externo__c)) {
                codigos.add(edificio.Codigo_Externo__c);
            }
        }
        return codigos;
    }

    private static String extraerDetalle(String cuerpo) {
        if (String.isBlank(cuerpo)) {
            return '';
        }
        try {
            Object crudo = JSON.deserializeUntyped(cuerpo);
            if (crudo instanceof Map<String, Object>) {
                Map<String, Object> mapa = (Map<String, Object>) crudo;
                Object detail = mapa.get('detail');
                if (detail != null) {
                    return String.valueOf(detail);
                }
                Object title = mapa.get('title');
                if (title != null) {
                    return String.valueOf(title);
                }
            }
        } catch (Exception e) {
            return cuerpo.left(255);
        }
        return cuerpo.left(255);
    }
}
