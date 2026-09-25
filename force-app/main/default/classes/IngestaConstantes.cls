/**
 * Constantes de la ingesta US-201. Un solo sitio para cadencia, contrato y motivos.
 */
public inherited sharing class IngestaConstantes {
    public static final String CREDENCIAL = 'Nova_Casa_Simulador';
    public static final String ORIGEN = 'nova-casa-simulator';
    public static final String VERSION_ESQUEMA = '1.0';
    public static final Integer PAGINAS_POR_CICLO = 6;
    public static final Integer FALLOS_PARA_CORTAR = 3;
    public static final Integer TOLERANCIA_FUTURO_MINUTOS = 5;
    public static final Integer TIEMPO_ESPERA_MS = 20000;
    public static final Integer TAMANO_TANDA_DEFECTO = 50;
    public static final Integer SEMILLA_DEFECTO = 20260922;
    public static final String ESCENARIO_DEFECTO = 'MIXED';

    public static final String TIPO_MEDICION = 'MEASUREMENT';
    public static final String TIPO_CONECTIVIDAD = 'CONNECTIVITY';

    public static final String RESULTADO_PENDIENTE = 'Pendiente';
    public static final String RESULTADO_APLICADO = 'Aplicado';
    public static final String RESULTADO_DUPLICADO = 'Duplicado';
    public static final String RESULTADO_ATRASADO = 'Atrasado';
    public static final String RESULTADO_CONFLICTO = 'Conflicto';
    public static final String RESULTADO_RECHAZADO = 'Rechazado';
    public static final String RESULTADO_FALLIDO = 'Fallido';

    public static final String SEV_NORMAL = 'Normal';
    public static final String SEV_ADVERTENCIA = 'Advertencia';
    public static final String SEV_CRITICO = 'Critico';

    public static final String MOTIVO_VERSION = 'Version no soportada';
    public static final String MOTIVO_TIPO_MENSAJE = 'Tipo de mensaje desconocido';
    public static final String MOTIVO_EDIFICIO = 'Edificio no encontrado';
    public static final String MOTIVO_ACTIVO = 'Activo no encontrado';
    public static final String MOTIVO_TIPO_MEDICION = 'Tipo de medicion desconocido';
    public static final String MOTIVO_SIN_LIMITE = 'Sin limite configurado';
    public static final String MOTIVO_SIN_MINUTOS = 'Sin minutos configurados';
    public static final String MOTIVO_SISTEMA = 'Error del sistema';
    public static final String MOTIVO_CAMPO = 'Campo faltante';
    public static final String MOTIVO_VALOR = 'Valor invalido';
    public static final String MOTIVO_FECHA = 'Fecha invalida';
    public static final String MOTIVO_FUTURA = 'Fecha futura';
    public static final String MOTIVO_ACTIVO_EDIFICIO = 'Activo no coincide con el edificio';
    public static final String MOTIVO_COMUNICACION = 'Estado de comunicacion invalido';
    public static final String MOTIVO_UNIDAD = 'Unidad no compatible';

    public static final Set<String> MEDICIONES = new Set<String>{
        'TEMPERATURE',
        'WATER_CONSUMPTION',
        'ENERGY_CONSUMPTION',
        'WATER_PRESSURE'
    };

    public static final Set<String> ESTADOS_COMUNICACION = new Set<String>{
        'HEALTHY',
        'LOST',
        'RESTORED'
    };

    private static final Set<String> REINTENTABLES = new Set<String>{
        MOTIVO_VERSION,
        MOTIVO_TIPO_MENSAJE,
        MOTIVO_EDIFICIO,
        MOTIVO_ACTIVO,
        MOTIVO_TIPO_MEDICION,
        MOTIVO_SIN_LIMITE,
        MOTIVO_SIN_MINUTOS,
        MOTIVO_SISTEMA
    };

    public static Boolean esReintentable(String motivo) {
        return String.isNotBlank(motivo) && REINTENTABLES.contains(motivo);
    }
}
