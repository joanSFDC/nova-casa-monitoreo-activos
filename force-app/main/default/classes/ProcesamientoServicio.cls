/**
 * Orquesta una tanda de avisos: cuatro consultas, resuelve en memoria, dos escrituras.
 * Los incidentes (US-205) no se abren aqui.
 *
 * without sharing: proceso de sistema. El disparador corre como usuario automatizado.
 */
public without sharing class ProcesamientoServicio {
    public class ResultadoTanda {
        public Integer senales;
        public Integer aplicadas;
        public Integer rechazadas;
        public Integer atrasadas;
        public Integer fallidas;

        public ResultadoTanda() {
            this.senales = 0;
            this.aplicadas = 0;
            this.rechazadas = 0;
            this.atrasadas = 0;
            this.fallidas = 0;
        }
    }

    @TestVisible
    static Boolean inyectarFalloDeEscritura = false;

    public static ResultadoTanda procesar(List<Aviso_de_Senal__e> avisos) {
        ResultadoTanda resultado = new ResultadoTanda();
        if (avisos == null || avisos.isEmpty()) {
            return resultado;
        }

        Set<String> clavesSenal = new Set<String>();
        Set<String> codigosActivo = new Set<String>();
        Set<String> clavesEstado = new Set<String>();
        for (Aviso_de_Senal__e aviso : avisos) {
            if (String.isNotBlank(aviso.Clave__c)) {
                clavesSenal.add(aviso.Clave__c);
            }
            if (String.isNotBlank(aviso.Codigo_Activo__c)) {
                codigosActivo.add(aviso.Codigo_Activo__c);
                String tipo = tipoMedicionDe(aviso);
                if (String.isNotBlank(tipo)) {
                    clavesEstado.add(aviso.Codigo_Activo__c + '|' + tipo);
                }
            }
        }

        Map<String, Senal__c> senales = cargarSenales(clavesSenal);
        Map<String, Activo__c> activos = cargarActivos(codigosActivo);
        Map<String, Estado_Actual__c> estados = cargarEstados(clavesEstado);
        Map<String, Umbral__c> umbrales = cargarUmbrales();

        Datetime ahora = Datetime.now();
        Map<String, Senal__c> aActualizar = new Map<String, Senal__c>();
        Map<String, Estado_Actual__c> aUpsertar = new Map<String, Estado_Actual__c>();
        Map<String, String> estadoAClaveSenal = new Map<String, String>();

        for (Aviso_de_Senal__e aviso : avisos) {
            if (String.isBlank(aviso.Clave__c) || !senales.containsKey(aviso.Clave__c)) {
                continue;
            }
            Senal__c senal = senales.get(aviso.Clave__c);
            if (senal.Resultado__c != IngestaConstantes.RESULTADO_PENDIENTE) {
                continue;
            }
            resultado.senales++;
            resolver(aviso, senal, activos, umbrales, estados, aUpsertar, estadoAClaveSenal, ahora);
            aActualizar.put(senal.Clave__c, senal);
        }

        List<Estado_Actual__c> listaEstados = ordenarPorActivo(aUpsertar.values());
        if (inyectarFalloDeEscritura && !listaEstados.isEmpty()) {
            listaEstados[0].Activo__c = null;
        }
        if (!listaEstados.isEmpty()) {
            Database.UpsertResult[] resEstados = Database.upsert(
                listaEstados,
                Estado_Actual__c.Clave__c,
                false,
                AccessLevel.SYSTEM_MODE
            );
            for (Integer i = 0; i < resEstados.size(); i++) {
                if (resEstados[i].isSuccess()) {
                    continue;
                }
                String claveEstado = listaEstados[i].Clave__c;
                String claveSenal = estadoAClaveSenal.get(claveEstado);
                Senal__c senal = aActualizar.get(claveSenal);
                if (senal == null) {
                    continue;
                }
                IngestaConstantes.aplicar(
                    senal,
                    IngestaConstantes.RESULTADO_FALLIDO,
                    IngestaConstantes.MOTIVO_SISTEMA
                );
                senal.Detalle__c = recortar(resEstados[i].getErrors()[0].getMessage());
                senal.Fecha_Procesamiento__c = ahora;
            }
        }

        List<Senal__c> listaSenales = aActualizar.values();
        if (!listaSenales.isEmpty()) {
            Database.SaveResult[] resSenales = Database.update(
                listaSenales,
                false,
                AccessLevel.SYSTEM_MODE
            );
            for (Integer i = 0; i < resSenales.size(); i++) {
                if (!resSenales[i].isSuccess()) {
                    IngestaConstantes.aplicar(
                        listaSenales[i],
                        IngestaConstantes.RESULTADO_FALLIDO,
                        IngestaConstantes.MOTIVO_SISTEMA
                    );
                    listaSenales[i].Detalle__c = recortar(resSenales[i].getErrors()[0].getMessage());
                }
            }
        }

        for (Senal__c senal : aActualizar.values()) {
            if (senal.Resultado__c == IngestaConstantes.RESULTADO_APLICADO) {
                resultado.aplicadas++;
            } else if (senal.Resultado__c == IngestaConstantes.RESULTADO_RECHAZADO) {
                resultado.rechazadas++;
            } else if (senal.Resultado__c == IngestaConstantes.RESULTADO_ATRASADO) {
                resultado.atrasadas++;
            } else if (senal.Resultado__c == IngestaConstantes.RESULTADO_FALLIDO) {
                resultado.fallidas++;
            }
        }

        marcarReanudacion(avisos);
        return resultado;
    }

    public static ResultadoTanda procesarPendientes() {
        List<Senal__c> pendientes = [
            SELECT Id, Clave__c, Message_Id__c, Tipo_Mensaje__c, Resultado__c, Carga__c,
                   Fecha_Origen__c, Activo__r.Codigo_Externo__c, Edificio__r.Codigo_Externo__c
            FROM Senal__c
            WHERE Resultado__c = :IngestaConstantes.RESULTADO_PENDIENTE
            WITH SYSTEM_MODE
            LIMIT 200
        ];
        List<Aviso_de_Senal__e> avisos = new List<Aviso_de_Senal__e>();
        for (Senal__c senal : pendientes) {
            avisos.add(avisoDesdeSenal(senal));
        }
        return procesar(avisos);
    }

    private static void resolver(
        Aviso_de_Senal__e aviso,
        Senal__c senal,
        Map<String, Activo__c> activos,
        Map<String, Umbral__c> umbrales,
        Map<String, Estado_Actual__c> estados,
        Map<String, Estado_Actual__c> aUpsertar,
        Map<String, String> estadoAClaveSenal,
        Datetime ahora
    ) {
        String tipoMensaje = aviso.Tipo_Mensaje__c;
        if (tipoMensaje != IngestaConstantes.TIPO_MEDICION
            && tipoMensaje != IngestaConstantes.TIPO_CONECTIVIDAD) {
            rechazar(senal, IngestaConstantes.MOTIVO_TIPO_MENSAJE, ahora);
            return;
        }

        Activo__c activo = activos.get(aviso.Codigo_Activo__c);
        if (activo == null) {
            rechazar(senal, IngestaConstantes.MOTIVO_ACTIVO, ahora);
            return;
        }

        String tipoMedicion = tipoMedicionDe(aviso);
        Umbral__c umbral = umbrales.get(activo.Tipo__c + '|' + tipoMedicion);
        ClasificacionServicio.Dictamen dictamen;
        if (tipoMensaje == IngestaConstantes.TIPO_MEDICION) {
            if (umbral != null && String.isNotBlank(aviso.Unidad__c)
                && aviso.Unidad__c != umbral.Unidad__c) {
                rechazar(senal, IngestaConstantes.MOTIVO_UNIDAD, ahora);
                return;
            }
            dictamen = ClasificacionServicio.clasificarMedicion(aviso.Valor__c, umbral);
        } else {
            dictamen = ClasificacionServicio.clasificarConectividad(
                aviso.Estado_Comunicacion__c,
                aviso.Gap_Segundos__c,
                umbral
            );
        }
        if (!dictamen.esValido()) {
            rechazar(senal, dictamen.motivo, ahora);
            return;
        }

        String claveEstado = aviso.Codigo_Activo__c + '|' + tipoMedicion;
        Estado_Actual__c vigente = estados.get(claveEstado);
        if (!esMasVigente(aviso, vigente)) {
            IngestaConstantes.aplicar(
                senal,
                IngestaConstantes.RESULTADO_ATRASADO,
                null
            );
            senal.Fecha_Procesamiento__c = ahora;
            return;
        }

        Estado_Actual__c estado = vigente == null ? new Estado_Actual__c() : vigente;
        estado.Clave__c = claveEstado;
        if (estado.Id == null) {
            estado.Activo__c = activo.Id;
        }
        estado.Tipo_Medicion__c = tipoMedicion;
        estado.Fecha_Origen__c = aviso.Fecha_Origen__c;
        estado.Fecha_Actualizacion__c = ahora;
        estado.Ultimo_Message_Id__c = aviso.Message_Id__c;
        estado.Severidad__c = dictamen.severidad;
        estado.Severidad_Nivel__c = dictamen.nivel;
        if (tipoMensaje == IngestaConstantes.TIPO_MEDICION) {
            estado.Valor__c = aviso.Valor__c;
            estado.Unidad__c = aviso.Unidad__c;
            estado.Estado_Comunicacion__c = null;
            estado.Gap_Segundos__c = null;
            estado.Episodio_Id__c = null;
            estado.Ultima_Vez_Visto__c = null;
            estado.Sin_Comunicacion_Num__c = 0;
        } else {
            estado.Valor__c = aviso.Gap_Segundos__c;
            estado.Unidad__c = null;
            estado.Estado_Comunicacion__c = aviso.Estado_Comunicacion__c;
            estado.Gap_Segundos__c = aviso.Gap_Segundos__c;
            estado.Episodio_Id__c = aviso.Episodio_Id__c;
            estado.Ultima_Vez_Visto__c = aviso.Ultima_Vez_Visto__c;
            estado.Sin_Comunicacion_Num__c = aviso.Estado_Comunicacion__c == 'LOST' ? 1 : 0;
        }
        estados.put(claveEstado, estado);
        aUpsertar.put(claveEstado, estado);
        estadoAClaveSenal.put(claveEstado, senal.Clave__c);

        IngestaConstantes.aplicar(
            senal,
            IngestaConstantes.RESULTADO_APLICADO,
            null
        );
        senal.Fecha_Procesamiento__c = ahora;
        senal.Activo__c = activo.Id;
    }

    private static Boolean esMasVigente(Aviso_de_Senal__e aviso, Estado_Actual__c vigente) {
        if (vigente == null || vigente.Fecha_Origen__c == null) {
            return true;
        }
        if (aviso.Fecha_Origen__c == null) {
            return false;
        }
        if (aviso.Fecha_Origen__c > vigente.Fecha_Origen__c) {
            return true;
        }
        if (aviso.Fecha_Origen__c < vigente.Fecha_Origen__c) {
            return false;
        }
        String actual = vigente.Ultimo_Message_Id__c == null ? '' : vigente.Ultimo_Message_Id__c;
        String candidato = aviso.Message_Id__c == null ? '' : aviso.Message_Id__c;
        if (candidato == actual) {
            return true;
        }
        return candidato > actual;
    }

    private static void rechazar(Senal__c senal, String motivo, Datetime ahora) {
        IngestaConstantes.aplicar(
            senal,
            IngestaConstantes.RESULTADO_RECHAZADO,
            motivo
        );
        senal.Fecha_Procesamiento__c = ahora;
    }

    private static Map<String, Senal__c> cargarSenales(Set<String> claves) {
        Map<String, Senal__c> mapa = new Map<String, Senal__c>();
        if (claves.isEmpty()) {
            return mapa;
        }
        for (Senal__c senal : [
            SELECT Id, Clave__c, Resultado__c, Motivo__c, Reintentable__c, Detalle__c,
                   Fecha_Procesamiento__c, Activo__c, Carga__c
            FROM Senal__c
            WHERE Clave__c IN :claves
            WITH SYSTEM_MODE
        ]) {
            mapa.put(senal.Clave__c, senal);
        }
        return mapa;
    }

    private static Map<String, Activo__c> cargarActivos(Set<String> codigos) {
        Map<String, Activo__c> mapa = new Map<String, Activo__c>();
        if (codigos.isEmpty()) {
            return mapa;
        }
        for (Activo__c activo : [
            SELECT Id, Codigo_Externo__c, Tipo__c, Edificio__c
            FROM Activo__c
            WHERE Codigo_Externo__c IN :codigos
            WITH SYSTEM_MODE
        ]) {
            mapa.put(activo.Codigo_Externo__c, activo);
        }
        return mapa;
    }

    private static Map<String, Estado_Actual__c> cargarEstados(Set<String> claves) {
        Map<String, Estado_Actual__c> mapa = new Map<String, Estado_Actual__c>();
        if (claves.isEmpty()) {
            return mapa;
        }
        for (Estado_Actual__c estado : [
            SELECT Id, Clave__c, Activo__c, Fecha_Origen__c, Ultimo_Message_Id__c,
                   Tipo_Medicion__c, Valor__c, Unidad__c, Severidad__c, Severidad_Nivel__c
            FROM Estado_Actual__c
            WHERE Clave__c IN :claves
            WITH SYSTEM_MODE
        ]) {
            mapa.put(estado.Clave__c, estado);
        }
        return mapa;
    }

    private static Map<String, Umbral__c> cargarUmbrales() {
        Map<String, Umbral__c> mapa = new Map<String, Umbral__c>();
        for (Umbral__c umbral : [
            SELECT Id, Clave__c, Tipo_Activo__c, Tipo_Medicion__c, Unidad__c,
                   Critico_Bajo__c, Critico_Alto__c, Advertencia_Bajo__c, Advertencia_Alto__c,
                   Minutos_Advertencia__c, Minutos_Critico__c, Vigente__c
            FROM Umbral__c
            WHERE Vigente__c = true
            WITH SYSTEM_MODE
        ]) {
            mapa.put(umbral.Clave__c, umbral);
        }
        return mapa;
    }

    private static List<Estado_Actual__c> ordenarPorActivo(List<Estado_Actual__c> origen) {
        List<EstadoPorActivo> envoltorios = new List<EstadoPorActivo>();
        for (Estado_Actual__c estado : origen) {
            envoltorios.add(new EstadoPorActivo(estado));
        }
        envoltorios.sort();
        List<Estado_Actual__c> ordenados = new List<Estado_Actual__c>();
        for (EstadoPorActivo item : envoltorios) {
            ordenados.add(item.registro);
        }
        return ordenados;
    }

    private static void marcarReanudacion(List<Aviso_de_Senal__e> avisos) {
        if (avisos.isEmpty()) {
            return;
        }
        Aviso_de_Senal__e ultimo = avisos[avisos.size() - 1];
        if (ultimo.ReplayId == null) {
            return;
        }
        try {
            EventBus.TriggerContext.currentContext().setResumeCheckpoint(ultimo.ReplayId);
        } catch (Exception e) {
            // Fuera del disparador (pruebas directas y procesarPendientes) no hay contexto.
        }
    }

    private static String tipoMedicionDe(Aviso_de_Senal__e aviso) {
        if (String.isNotBlank(aviso.Tipo_Medicion__c)) {
            return aviso.Tipo_Medicion__c;
        }
        return aviso.Tipo_Mensaje__c == IngestaConstantes.TIPO_CONECTIVIDAD
            ? 'CAMERA_CONNECTIVITY'
            : null;
    }

    public static Aviso_de_Senal__e avisoDesdeSenal(Senal__c senal) {
        Map<String, Object> mensaje = new Map<String, Object>();
        if (String.isNotBlank(senal.Carga__c)) {
            try {
                Object crudo = JSON.deserializeUntyped(senal.Carga__c);
                if (crudo instanceof Map<String, Object>) {
                    mensaje = (Map<String, Object>) crudo;
                }
            } catch (Exception e) {
                mensaje = new Map<String, Object>();
            }
        }
        Map<String, Object> building = IngestaValidador.mapa(mensaje, 'building');
        Map<String, Object> asset = IngestaValidador.mapa(mensaje, 'asset');
        Map<String, Object> measurement = IngestaValidador.mapa(mensaje, 'measurement');
        Map<String, Object> communication = IngestaValidador.mapa(mensaje, 'communication');
        Aviso_de_Senal__e aviso = new Aviso_de_Senal__e();
        aviso.Clave__c = senal.Clave__c;
        aviso.Message_Id__c = senal.Message_Id__c;
        aviso.Tipo_Mensaje__c = senal.Tipo_Mensaje__c;
        aviso.Codigo_Edificio__c = building != null
            ? IngestaValidador.texto(building, 'id')
            : senal.Edificio__r == null ? null : senal.Edificio__r.Codigo_Externo__c;
        aviso.Codigo_Activo__c = asset != null
            ? IngestaValidador.texto(asset, 'id')
            : senal.Activo__r == null ? null : senal.Activo__r.Codigo_Externo__c;
        aviso.Fecha_Origen__c = senal.Fecha_Origen__c;
        if (senal.Tipo_Mensaje__c == IngestaConstantes.TIPO_MEDICION) {
            aviso.Tipo_Medicion__c = IngestaValidador.texto(measurement, 'type');
            aviso.Valor__c = IngestaValidador.decimalDe(
                measurement == null ? null : measurement.get('value')
            );
            aviso.Unidad__c = IngestaValidador.texto(measurement, 'unit');
        } else {
            aviso.Tipo_Medicion__c = 'CAMERA_CONNECTIVITY';
            aviso.Estado_Comunicacion__c = IngestaValidador.texto(communication, 'status');
            aviso.Gap_Segundos__c = IngestaValidador.decimalDe(
                communication == null ? null : communication.get('gapSeconds')
            );
            aviso.Ultima_Vez_Visto__c = IngestaValidador.parsearIso(
                IngestaValidador.texto(communication, 'lastSeenAt')
            );
            aviso.Episodio_Id__c = IngestaValidador.texto(communication, 'episodeId');
        }
        return aviso;
    }

    private static String recortar(String valor) {
        if (String.isBlank(valor)) {
            return valor;
        }
        return valor.left(255);
    }

    private class EstadoPorActivo implements Comparable {
        public Estado_Actual__c registro;

        EstadoPorActivo(Estado_Actual__c registro) {
            this.registro = registro;
        }

        public Integer compareTo(Object other) {
            EstadoPorActivo o = (EstadoPorActivo) other;
            String a = registro.Activo__c == null ? '' : String.valueOf(registro.Activo__c);
            String b = o.registro.Activo__c == null ? '' : String.valueOf(o.registro.Activo__c);
            return a.compareTo(b);
        }
    }
}
