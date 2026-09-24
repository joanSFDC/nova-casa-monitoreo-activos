/**
 * Mock HTTP del simulador. Distingue POST /session de GET /telemetry y cubre 409/timeout.
 */
@isTest
public class IngestaSimuladorMock implements HttpCalloutMock {
    public Integer codigoSesion = 201;
    public Integer codigoTelemetria = 200;
    public String cuerpoSesion = TestDataFactory.sesionOk(
        'cursor-inicial-de-prueba-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
    );
    public String cuerpoTelemetria;
    public Integer tiemposAgotadosPendientes = 0;
    public Boolean primerGetEs409 = false;
    public Integer llamadas = 0;
    public Integer llamadasGet = 0;
    public List<String> metodos = new List<String>();
    public String ultimoCursor;

    public IngestaSimuladorMock() {
        this.cuerpoTelemetria = TestDataFactory.sobre(
            new List<Map<String, Object>>{ TestDataFactory.mensajePresion() },
            'cursor-siguiente',
            true
        );
    }

    public HTTPResponse respond(HTTPRequest req) {
        llamadas++;
        metodos.add(req.getMethod());
        ultimoCursor = req.getHeader('X-Simulator-Cursor');
        if (tiemposAgotadosPendientes > 0) {
            tiemposAgotadosPendientes--;
            throw new System.CalloutException('Read timed out');
        }
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        if (req.getMethod() == 'POST') {
            res.setStatusCode(codigoSesion);
            res.setBody(cuerpoSesion);
            return res;
        }
        llamadasGet++;
        if (primerGetEs409 && llamadasGet == 1) {
            res.setStatusCode(409);
            res.setBody(
                '{"type":"cursor-conflict","title":"Conflict","status":409,"detail":"cursor no vale"}'
            );
            return res;
        }
        res.setStatusCode(codigoTelemetria);
        res.setBody(cuerpoTelemetria);
        return res;
    }
}
