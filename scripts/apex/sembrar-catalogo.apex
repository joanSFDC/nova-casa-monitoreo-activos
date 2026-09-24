// Siembra el catalogo de Nova Casa: 2 edificios, 10 activos, 5 umbrales.
//
// Uso, desde la raiz del repositorio:
//   sf apex run -f scripts/apex/sembrar-catalogo.apex
//   ./scripts/sembrar-catalogo.sh
//
// Es idempotente: upsert por External ID. Correrlo dos veces deja los mismos
// 17 registros. Los codigos salen de GET /catalog del simulador MDSS
// (AST-*-WATER-001 y AST-*-ENERGY-001, no WMET/EMET).

List<Edificio__c> edificios = new List<Edificio__c>{
    new Edificio__c(
        Name = 'Edificio Nova Alameda',
        Codigo_Externo__c = 'BLD-BOG-001',
        Ciudad__c = 'Bogotá',
        Region__c = 'Andina'),
    new Edificio__c(
        Name = 'Edificio Nova Caribe',
        Codigo_Externo__c = 'BLD-BAQ-001',
        Ciudad__c = 'Barranquilla',
        Region__c = 'Caribe')
};
Database.upsert(edificios, Edificio__c.Codigo_Externo__c);

delete [
    SELECT Id
    FROM Activo__c
    WHERE Codigo_Externo__c IN (
        'AST-BOG-WMET-001',
        'AST-BAQ-WMET-001',
        'AST-BOG-EMET-001',
        'AST-BAQ-EMET-001'
    )
];

List<Activo__c> activos = new List<Activo__c>{
    // Bogota
    new Activo__c(
        Name = 'Sala técnica principal',
        Codigo_Externo__c = 'AST-BOG-TEMP-001',
        Tipo__c = 'TECHNICAL_ROOM',
        Sensor_Id__c = 'SNS-BOG-TEMP-001',
        Edificio__r = new Edificio__c(Codigo_Externo__c = 'BLD-BOG-001')),
    new Activo__c(
        Name = 'Medidor de agua torre A',
        Codigo_Externo__c = 'AST-BOG-WATER-001',
        Tipo__c = 'WATER_METER',
        Sensor_Id__c = 'SNS-BOG-WATER-001',
        Edificio__r = new Edificio__c(Codigo_Externo__c = 'BLD-BOG-001')),
    new Activo__c(
        Name = 'Medidor de energía torre A',
        Codigo_Externo__c = 'AST-BOG-ENERGY-001',
        Tipo__c = 'ENERGY_METER',
        Sensor_Id__c = 'SNS-BOG-ENERGY-001',
        Edificio__r = new Edificio__c(Codigo_Externo__c = 'BLD-BOG-001')),
    new Activo__c(
        Name = 'Bomba de presión de agua',
        Codigo_Externo__c = 'AST-BOG-PUMP-001',
        Tipo__c = 'WATER_PUMP',
        Sensor_Id__c = 'SNS-BOG-PUMP-001',
        Edificio__r = new Edificio__c(Codigo_Externo__c = 'BLD-BOG-001')),
    new Activo__c(
        Name = 'Cámara acceso vehicular',
        Codigo_Externo__c = 'AST-BOG-CAM-001',
        Tipo__c = 'SECURITY_CAMERA',
        Sensor_Id__c = 'SNS-BOG-CAM-001',
        Edificio__r = new Edificio__c(Codigo_Externo__c = 'BLD-BOG-001')),
    // Barranquilla
    new Activo__c(
        Name = 'Sala técnica principal',
        Codigo_Externo__c = 'AST-BAQ-TEMP-001',
        Tipo__c = 'TECHNICAL_ROOM',
        Sensor_Id__c = 'SNS-BAQ-TEMP-001',
        Edificio__r = new Edificio__c(Codigo_Externo__c = 'BLD-BAQ-001')),
    new Activo__c(
        Name = 'Medidor de agua torre única',
        Codigo_Externo__c = 'AST-BAQ-WATER-001',
        Tipo__c = 'WATER_METER',
        Sensor_Id__c = 'SNS-BAQ-WATER-001',
        Edificio__r = new Edificio__c(Codigo_Externo__c = 'BLD-BAQ-001')),
    new Activo__c(
        Name = 'Medidor de energía torre única',
        Codigo_Externo__c = 'AST-BAQ-ENERGY-001',
        Tipo__c = 'ENERGY_METER',
        Sensor_Id__c = 'SNS-BAQ-ENERGY-001',
        Edificio__r = new Edificio__c(Codigo_Externo__c = 'BLD-BAQ-001')),
    new Activo__c(
        Name = 'Bomba de presión de agua',
        Codigo_Externo__c = 'AST-BAQ-PUMP-001',
        Tipo__c = 'WATER_PUMP',
        Sensor_Id__c = 'SNS-BAQ-PUMP-001',
        Edificio__r = new Edificio__c(Codigo_Externo__c = 'BLD-BAQ-001')),
    new Activo__c(
        Name = 'Cámara azotea',
        Codigo_Externo__c = 'AST-BAQ-CAM-001',
        Tipo__c = 'SECURITY_CAMERA',
        Sensor_Id__c = 'SNS-BAQ-CAM-001',
        Edificio__r = new Edificio__c(Codigo_Externo__c = 'BLD-BAQ-001'))
};
Database.upsert(activos, Activo__c.Codigo_Externo__c);

List<Umbral__c> umbrales = new List<Umbral__c>{
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
        Vigente__c = true),
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
        Vigente__c = true),
    new Umbral__c(
        Clave__c = 'WATER_METER|WATER_CONSUMPTION',
        Tipo_Activo__c = 'WATER_METER',
        Tipo_Medicion__c = 'WATER_CONSUMPTION',
        Unidad__c = 'LITER_PER_15_MIN',
        Advertencia_Alto__c = 401,
        Critico_Alto__c = 651,
        Decimales__c = 0,
        Vigente__c = true),
    new Umbral__c(
        Clave__c = 'ENERGY_METER|ENERGY_CONSUMPTION',
        Tipo_Activo__c = 'ENERGY_METER',
        Tipo_Medicion__c = 'ENERGY_CONSUMPTION',
        Unidad__c = 'KWH_PER_15_MIN',
        Advertencia_Alto__c = 40.1,
        Critico_Alto__c = 65.1,
        Decimales__c = 1,
        Vigente__c = true),
    new Umbral__c(
        Clave__c = 'SECURITY_CAMERA|CAMERA_CONNECTIVITY',
        Tipo_Activo__c = 'SECURITY_CAMERA',
        Tipo_Medicion__c = 'CAMERA_CONNECTIVITY',
        Minutos_Advertencia__c = 15,
        Minutos_Critico__c = 60,
        Vigente__c = true)
};
Database.upsert(umbrales, Umbral__c.Clave__c);

Integer nEdificios = [SELECT COUNT() FROM Edificio__c];
Integer nActivos = [SELECT COUNT() FROM Activo__c];
Integer nUmbrales = [SELECT COUNT() FROM Umbral__c];
System.debug('SIEMBRA edificios=' + nEdificios
    + ' activos=' + nActivos
    + ' umbrales=' + nUmbrales);
