// Programa la ingesta cada minuto (60 CronTrigger). Para quitarla:
// IngestaSchedulable.abortar();

List<String> ids = IngestaSchedulable.programarCadaMinuto();
System.debug('PROGRAMADA trabajos=' + ids.size());
