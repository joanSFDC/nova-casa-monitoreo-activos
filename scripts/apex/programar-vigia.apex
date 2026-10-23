// Programa el vigia de la ingesta cada 10 minutos (6 CronTrigger, minutos 05 a 55).
// Para quitarlo: VigiaIngestaSchedulable.abortar();

List<String> ids = VigiaIngestaSchedulable.programar();
System.debug('VIGIA trabajos=' + ids.size());
