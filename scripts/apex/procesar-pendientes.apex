// Aplica las senales Pendiente que ya estan en la bitacora.
// No llama al simulador. Sirve para drenar la cola de US-201 cuando el
// aviso ya se publico o para reprocesar tras un despliegue del suscriptor.

ProcesamientoServicio.ResultadoTanda r = ProcesamientoServicio.procesarPendientes();
System.debug(
    'PROCESAMIENTO senales=' + r.senales
    + ' aplicadas=' + r.aplicadas
    + ' rechazadas=' + r.rechazadas
    + ' atrasadas=' + r.atrasadas
    + ' fallidas=' + r.fallidas
);
