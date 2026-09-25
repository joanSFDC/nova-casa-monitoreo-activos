/**
 * Datos de prueba del catalogo Nova Casa. Un solo sitio para edificios, activos,
 * umbrales y el control de ingesta. No usa SeeAllData.
 */
@isTest
public class TestDataFactory {
    public static final String BLD_BOG = 'BLD-BOG-001';
    public static final String BLD_BAQ = 'BLD-BAQ-001';
    public static final String AST_PUMP = 'AST-BOG-PUMP-001';
    public static final String AST_CAM = 'AST-BOG-CAM-001';
    public static final String AST_TEMP = 'AST-BAQ-TEMP-001';

    public static void sembrarCatalogoMinimo() {
        List<Edificio__c> edificios = new List<Edificio__c>{
            new Edificio__c(
                Name = 'Edificio Nova Alameda',
                Codigo_Externo__c = BLD_BOG,
                Ciudad__c = 'Bogota',
                Region__c = 'Andina'
            ),
            new Edificio__c(
                Name = 'Edificio Nova Caribe',
                Codigo_Externo__c = BLD_BAQ,
                Ciudad__c = 'Barranquilla',
                Region__c = 'Caribe'
            )
        };
        insert edificios;

        Map<String, Id> idsEdificio = new Map<String, Id>();
        for (Edificio__c edificio : edificios) {
            idsEdificio.put(edificio.Codigo_Externo__c, edificio.Id);
        }

        insert new List<Activo__c>{
            new Activo__c(
                Name = 'Bomba de presion de agua',
                Codigo_Externo__c = AST_PUMP,
                Tipo__c = 'WATER_PUMP',
                Sensor_Id__c = 'SNS-BOG-PUMP-001',
                Edificio__c = idsEdificio.get(BLD_BOG)
            ),
            new Activo__c(
                Name = 'Camara acceso vehicular',
                Codigo_Externo__c = AST_CAM,
                Tipo__c = 'SECURITY_CAMERA',
                Sensor_Id__c = 'SNS-BOG-CAM-001',
                Edificio__c = idsEdificio.get(BLD_BOG)
            ),
            new Activo__c(
                Name = 'Sala tecnica principal',
                Codigo_Externo__c = AST_TEMP,
                Tipo__c = 'TECHNICAL_ROOM',
                Sensor_Id__c = 'SNS-BAQ-TEMP-001',
                Edificio__c = idsEdificio.get(BLD_BAQ)
            )
        };

        insert new List<Umbral__c>{
            new Umbral__c(
                Clave__c = 'WATER_PUMP|WATER_PRESSURE',
                Tipo_Activo__c = 'WATER_PUMP',
                Tipo_Medicion__c = 'WATER_PRESSURE',
                Unidad__c = 'BAR',
                Critico_Bajo__c = 1.49,
                Advertencia_Bajo__c = 2.49,
                Advertencia_Alto__c = 4.01,
                Critico_Alto__c = 5.01,
                Decimales__c = 2,
                Vigente__c = true
            ),
            new Umbral__c(
                Clave__c = 'TECHNICAL_ROOM|TEMPERATURE',
                Tipo_Activo__c = 'TECHNICAL_ROOM',
                Tipo_Medicion__c = 'TEMPERATURE',
                Unidad__c = 'CELSIUS',
                Critico_Bajo__c = 14.9,
                Advertencia_Bajo__c = 17.9,
                Advertencia_Alto__c = 30.1,
                Critico_Alto__c = 35.1,
                Decimales__c = 1,
                Vigente__c = true
            ),
            new Umbral__c(
                Clave__c = 'SECURITY_CAMERA|CAMERA_CONNECTIVITY',
                Tipo_Activo__c = 'SECURITY_CAMERA',
                Tipo_Medicion__c = 'CAMERA_CONNECTIVITY',
                Minutos_Advertencia__c = 15,
                Minutos_Critico__c = 60,
                Vigente__c = true
            )
        };
    }

    public static Control_de_Ingesta__c crearControl(Boolean doInsert) {
        Control_de_Ingesta__c control = new Control_de_Ingesta__c(
            Name = 'Control principal',
            Activo__c = true,
            Escenario__c = 'MIXED',
            Semilla__c = 20260922,
            Tamano_Tanda__c = 50,
            Fallos_Consecutivos__c = 0,
            Paginas_Procesadas__c = 0
        );
        if (doInsert) {
            insert control;
        }
        return control;
    }

    public static Map<String, Object> mensajePresion() {
        return mensajePresion('msg_000002', 'dlv_000002', 2.76, 'BAR');
    }

    public static Map<String, Object> mensajePresion(
        String messageId,
        String deliveryId,
        Decimal valor,
        String unidad
    ) {
        return new Map<String, Object>{
            'deliveryId' => deliveryId,
            'messageId' => messageId,
            'messageType' => 'MEASUREMENT',
            'source' => 'nova-casa-simulator',
            'building' => new Map<String, Object>{
                'id' => BLD_BOG,
                'name' => 'Edificio Nova Alameda',
                'city' => 'Bogota'
            },
            'asset' => new Map<String, Object>{
                'id' => AST_PUMP,
                'name' => 'Bomba de presion de agua',
                'type' => 'WATER_PUMP'
            },
            'sensorId' => 'SNS-BOG-PUMP-001',
            'measurement' => new Map<String, Object>{
                'type' => 'WATER_PRESSURE',
                'value' => valor,
                'unit' => unidad
            },
            'occurredAt' => '2026-09-22T21:54:25.597Z',
            'publishedAt' => '2026-09-22T21:54:28.614Z'
        };
    }

    public static Map<String, Object> mensajeCamara() {
        return new Map<String, Object>{
            'deliveryId' => 'dlv_000008',
            'messageId' => 'msg_000008',
            'messageType' => 'CONNECTIVITY',
            'source' => 'nova-casa-simulator',
            'building' => new Map<String, Object>{
                'id' => BLD_BOG,
                'name' => 'Edificio Nova Alameda',
                'city' => 'Bogota'
            },
            'asset' => new Map<String, Object>{
                'id' => AST_CAM,
                'name' => 'Camara acceso vehicular',
                'type' => 'SECURITY_CAMERA'
            },
            'sensorId' => 'SNS-BOG-CAM-001',
            'communication' => new Map<String, Object>{
                'status' => 'LOST',
                'gapSeconds' => 180,
                'lastSeenAt' => '2026-09-22T21:56:50.118Z',
                'episodeId' => 'EPI-BOG-out-0'
            },
            'occurredAt' => '2026-09-22T21:59:46.520Z',
            'publishedAt' => '2026-09-22T21:59:50.118Z'
        };
    }

    public static Map<String, Object> mensajeTemperaturaNula() {
        return new Map<String, Object>{
            'deliveryId' => 'dlv_000001',
            'messageId' => 'msg_000001',
            'messageType' => 'MEASUREMENT',
            'source' => 'nova-casa-simulator',
            'building' => new Map<String, Object>{
                'id' => BLD_BAQ,
                'name' => 'Edificio Nova Caribe',
                'city' => 'Barranquilla'
            },
            'asset' => new Map<String, Object>{
                'id' => AST_TEMP,
                'name' => 'Sala tecnica principal',
                'type' => 'TECHNICAL_ROOM'
            },
            'sensorId' => 'SNS-BAQ-TEMP-001',
            'measurement' => new Map<String, Object>{
                'type' => 'TEMPERATURE',
                'value' => null,
                'unit' => 'CELSIUS'
            },
            'occurredAt' => '2026-09-22T21:53:30.162Z',
            'publishedAt' => '2026-09-22T21:53:31.344Z'
        };
    }

    public static Map<String, Object> mensajeActivoDesconocido() {
        Map<String, Object> mensaje = mensajePresion('msg_unknown', 'dlv_unknown', 2.56, 'BAR');
        mensaje.put(
            'building',
            new Map<String, Object>{
                'id' => BLD_BAQ,
                'name' => 'Edificio Nova Caribe',
                'city' => 'Barranquilla'
            }
        );
        mensaje.put(
            'asset',
            new Map<String, Object>{
                'id' => 'AST-UNKNOWN-0001',
                'name' => 'Activo no catalogado',
                'type' => 'UNKNOWN'
            }
        );
        return mensaje;
    }

    public static String sobre(List<Map<String, Object>> mensajes, String cursor, Boolean hasMore) {
        Map<String, Object> cuerpo = new Map<String, Object>{
            'schemaVersion' => '1.0',
            'generatedAt' => '2026-09-22T21:52:25.181Z',
            'data' => mensajes,
            'pagination' => new Map<String, Object>{
                'nextCursor' => cursor,
                'hasMore' => hasMore,
                'pollAfterMs' => 10000
            }
        };
        return JSON.serialize(cuerpo);
    }

    public static String sesionOk(String cursor) {
        return JSON.serialize(
            new Map<String, Object>{
                'cursor' => cursor,
                'session' => new Map<String, Object>{
                    'scenario' => 'MIXED',
                    'seed' => 20260922,
                    'batchSize' => 50,
                    'startedAt' => '2026-09-22T21:51:49.358Z',
                    'expiresAt' => '2026-10-22T21:51:49.358Z'
                }
            }
        );
    }

    public static Senal__c senalPendiente(Map<String, Object> mensaje, Id activoId, Id edificioId) {
        String messageId = String.valueOf(mensaje.get('messageId'));
        Senal__c senal = new Senal__c();
        senal.Clave__c = 'nova-casa-simulator|' + messageId;
        senal.Message_Id__c = messageId;
        senal.Tipo_Mensaje__c = String.valueOf(mensaje.get('messageType'));
        senal.Resultado__c = IngestaConstantes.RESULTADO_PENDIENTE;
        senal.Carga__c = JSON.serialize(mensaje);
        senal.Fecha_Origen__c = IngestaValidador.parsearIso(String.valueOf(mensaje.get('occurredAt')));
        senal.Fecha_Publicacion__c = IngestaValidador.parsearIso(String.valueOf(mensaje.get('publishedAt')));
        senal.Fecha_Recepcion__c = Datetime.newInstanceGmt(2026, 9, 22, 22, 0, 0);
        senal.Entregas__c = 1;
        senal.Activo__c = activoId;
        senal.Edificio__c = edificioId;
        return senal;
    }

    public static Aviso_de_Senal__e avisoDe(Map<String, Object> mensaje) {
        Senal__c senal = new Senal__c();
        senal.Clave__c = 'nova-casa-simulator|' + String.valueOf(mensaje.get('messageId'));
        senal.Message_Id__c = String.valueOf(mensaje.get('messageId'));
        senal.Tipo_Mensaje__c = String.valueOf(mensaje.get('messageType'));
        senal.Carga__c = JSON.serialize(mensaje);
        senal.Fecha_Origen__c = IngestaValidador.parsearIso(String.valueOf(mensaje.get('occurredAt')));
        return ProcesamientoServicio.avisoDesdeSenal(senal);
    }
}
