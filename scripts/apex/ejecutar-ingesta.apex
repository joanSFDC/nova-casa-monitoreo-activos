// Encola el primer eslabon de la ingesta. Una sola pagina en tests;
// en la org la cadena sigue hasta seis si hasMore sigue en true.

Id jobId = System.enqueueJob(new IngestaQueueable(0));
System.debug('INGESTA job=' + jobId);
