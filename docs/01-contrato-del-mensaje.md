# 01 · Contrato del mensaje

Cubre **US-201 · Recibir señales del simulador**.

Todo lo que sigue está verificado contra la API real, no contra el ejemplo del enunciado.
Los payloads de este documento son transcripciones literales de respuestas obtenidas del
simulador.

## El concepto de base

Un contrato de mensajería es el acuerdo sobre la forma de los datos que cruzan una
frontera entre dos sistemas que evolucionan por separado. Importa porque el productor y
el consumidor se despliegan en momentos distintos: si el consumidor asume una forma que
el productor deja de cumplir, la integración se rompe en silencio y los datos se pierden
o se guardan mal, que es peor.

Un contrato bien escrito responde cuatro preguntas. Qué campos vienen y cuáles son
obligatorios. Qué significa cada uno, sobre todo cuando hay varios que parecen lo mismo.
Cómo se reconoce que dos mensajes son en realidad el mismo. Y qué pasa cuando algo no
cumple, porque un contrato que solo describe el camino feliz no sirve de nada en
producción.

## La forma de la respuesta

El simulador no empuja datos hacia la organización: expone un endpoint que hay que
consultar. Cada consulta devuelve un sobre con metadatos y un arreglo de mensajes.

```json
{
  "schemaVersion": "1.0",
  "generatedAt": "2026-09-22T21:52:25.181Z",
  "data": [ /* mensajes */ ],
  "pagination": {
    "nextCursor": "eyJ2IjoiMSIsInRlYW0iOiJlcXVpcG8tNCIsInNlZWQiOjIw...",
    "hasMore": true,
    "pollAfterMs": 10000
  }
}
```

Conviene separar tres conceptos de versión que el simulador expone con nombres parecidos
y que no son lo mismo:

| Dónde aparece | Campo | Valor observado | Qué significa |
| --- | --- | --- | --- |
| `GET /health` y `POST /session` | `contractVersion` | `"1"` | La versión del contrato que sirve el simulador |
| Raíz de `GET /telemetry` | `schemaVersion` | `"1.0"` | La versión de la forma de la respuesta |
| Mensaje individual | — | — | **No existe.** La versión no viaja por mensaje |

Esto cambia algo que habíamos diseñado. El discovery preveía un `schemaVersion` por
mensaje para que dos formatos pudieran convivir durante una migración. No se puede: la
versión es de la respuesta entera. La validación de versión, por tanto, se hace una vez
por página y no una vez por mensaje, y si la versión no es reconocida se rechaza la
página completa en lugar de sus mensajes uno a uno.

## El mensaje

Todos los mensajes comparten un tronco común. Lo que cambia según `messageType` es el
bloque de datos específico y, con él, qué campos se vuelven obligatorios.

### Tronco común

| Campo | Tipo | Obligatorio | Qué es |
| --- | --- | --- | --- |
| `deliveryId` | texto | sí | El intento de entrega. Cambia en cada reenvío |
| `messageId` | texto | sí | El mensaje. **Se repite en los reenvíos** |
| `messageType` | texto | sí | `MEASUREMENT` o `CONNECTIVITY` |
| `source` | texto | sí | Siempre `nova-casa-simulator` en este sprint |
| `building.id` | texto | sí | Código del edificio, p. ej. `BLD-BOG-001` |
| `building.name` | texto | no | Informativo |
| `building.city` | texto | no | Informativo |
| `asset.id` | texto | sí | Código del activo, p. ej. `AST-BOG-PUMP-001` |
| `asset.name` | texto | no | Informativo |
| `asset.type` | texto | no | Informativo. El tipo real lo manda nuestro registro |
| `sensorId` | texto | no | Informativo |
| `occurredAt` | fecha ISO 8601 UTC | sí | Cuándo ocurrió el hecho en el mundo |
| `publishedAt` | fecha ISO 8601 UTC | sí | Cuándo el simulador lo puso a disposición |

### Bloque de medición, cuando `messageType` es `MEASUREMENT`

| Campo | Tipo | Obligatorio | Qué es |
| --- | --- | --- | --- |
| `measurement.type` | texto | sí | `TEMPERATURE`, `WATER_CONSUMPTION`, `ENERGY_CONSUMPTION` o `WATER_PRESSURE` |
| `measurement.value` | número | sí | El valor medido. **Puede venir `null`** |
| `measurement.unit` | texto | sí | La unidad. Puede venir la unidad alterna |

### Bloque de comunicación, cuando `messageType` es `CONNECTIVITY`

| Campo | Tipo | Obligatorio | Qué es |
| --- | --- | --- | --- |
| `communication.status` | texto | sí | `HEALTHY`, `LOST` o `RESTORED` |
| `communication.gapSeconds` | número | sí | Segundos transcurridos desde el último contacto |
| `communication.lastSeenAt` | fecha ISO 8601 UTC | sí | Cuándo se vio al sensor por última vez |
| `communication.episodeId` | texto | sí | Agrupa los mensajes de un mismo corte |

## Las dos fechas, y por qué no se pueden confundir

`occurredAt` es cuándo pasó el hecho. `publishedAt` es cuándo el simulador lo publicó.
Que sean distintas no es un detalle: es el mecanismo entero de la historia US-203.

El escenario `LATE_MESSAGES` lo demuestra. Estos son mensajes reales de una misma página,
en el orden en que llegaron:

| Entrega | `occurredAt` | `publishedAt` | Retraso |
| --- | --- | --- | --- |
| `dlv_000003` | 22:50:18 | 22:50:21 | 3 s |
| `dlv_000004` | 22:51:19 | 22:51:21 | 2 s |
| `dlv_000005` | **22:42:20** | 22:52:20 | **10 min** |

La quinta entrega llega después de la cuarta pero describe un hecho nueve minutos
anterior. Si ordenáramos por llegada, el estado del activo retrocedería en el tiempo.

**Decisión: solo `occurredAt` determina qué lectura es más reciente.** `publishedAt` se
guarda como evidencia en la bitácora y no participa en ninguna comparación de vigencia.
Una tercera fecha, la de recepción en nuestro sistema, se calcula al insertar y sirve
únicamente para medir la latencia de la integración.

Todas las fechas llegan en UTC. Colombia está cinco horas por detrás durante todo el año,
sin horario de verano, así que las 15:05Z son las 10:05 de la mañana en Bogotá. La
conversión se deja a la capa de presentación: en base de datos todo se guarda en UTC,
que es lo que hace `Datetime` en Salesforce de forma nativa.

## La identidad del mensaje

Aquí está la parte más importante del contrato, y la que más se presta a error.

### El concepto

Un canal de entrega «al menos una vez» garantiza que ningún mensaje se pierde, pero no
garantiza que ninguno se entregue dos veces. Es la garantía habitual, porque la
alternativa —«exactamente una vez»— es imposible de conseguir de extremo a extremo sin
cooperación del consumidor. La cooperación que se le pide al consumidor se llama
idempotencia: procesar el mismo mensaje dos veces tiene que producir el mismo resultado
que procesarlo una.

Para ser idempotente hay que poder decir si dos mensajes son el mismo. Y eso exige una
clave de identidad estable, que el productor mantenga igual entre reenvíos.

### Lo que hace el simulador

Manda dos identificadores. El escenario `DUPLICATES` deja claro cuál es cuál:

```
dlv_000002  msg_000002  TEMPERATURE 29.6  occurredAt 21:54:27.806  publishedAt 21:54:29.498
dlv_000004  msg_000002  TEMPERATURE 29.6  occurredAt 21:54:27.806  publishedAt 21:56:30.273
```

Mismo `messageId`, mismo contenido, mismo `occurredAt`. Solo cambian `deliveryId` y
`publishedAt`. Es un reenvío.

El escenario `CONFLICT` manda otra cosa:

```
dlv_000014  msg_000014  TEMPERATURE 19.7   occurredAt 22:06:28.953
dlv_000016  msg_000014  TEMPERATURE 60.19  occurredAt 22:06:28.953
```

Mismo `messageId` y mismo `occurredAt`, pero el valor cambió de 19.7 a 60.19. Eso no es
un reenvío: es una contradicción sobre un hecho que ya se afirmó.

### La decisión

**La clave de identidad es `source` + `messageId`**, concatenados con una barra vertical:
`nova-casa-simulator|msg_000002`. Se guarda en `Senal__c.Clave__c`, marcado como External
ID y Unique. La unicidad la impone la base de datos, no una comprobación escrita a mano
que alguien pueda olvidar en una rama del código.

Se incluye `source` en la clave aunque hoy solo haya un origen, porque el día que haya
dos proveedores sus numeraciones van a colisionar y el cambio de esquema en ese momento
sería caro.

**Para distinguir un reenvío de un conflicto se guarda además un resumen del contenido**,
en `Senal__c.Hash_Contenido__c`. Es un SHA-256 en base 64 calculado sobre los campos que
afirman un hecho, no sobre el mensaje entero:

- Para `MEASUREMENT`: `assetId | measurement.type | measurement.value | measurement.unit | occurredAt`
- Para `CONNECTIVITY`: `assetId | communication.status | communication.gapSeconds | communication.lastSeenAt | communication.episodeId | occurredAt`

Se excluyen a propósito `deliveryId`, `publishedAt` y los campos informativos como
`building.name`. Si el simulador cambiara el nombre de un edificio entre dos entregas del
mismo mensaje, eso no es una contradicción sobre la medición y no debe marcarse como
conflicto.

La regla queda así: misma clave y mismo resumen es **duplicado**; misma clave con resumen
distinto es **conflicto**, y un conflicto no se resuelve solo, requiere que una persona
lo mire.

### Cómo se registra el reenvío

Hay una tensión que conviene nombrar. La clave es única en base de datos, así que la
segunda entrega no puede insertarse como una fila nueva. Pero US-209 pide poder
inspeccionar los duplicados, y la bitácora es donde se verían.

Se consideraron tres salidas. Una fila por `deliveryId`, con `messageId` indexado pero no
único: da trazabilidad completa pero traslada la protección anti-duplicado a código, que
es justo lo que queríamos evitar. Dos objetos, `Senal__c` única por mensaje y una
`Entrega__c` hija por cada intento: es lo más limpio conceptualmente pero añade un objeto
y un `insert` por ciclo para un beneficio que nadie pidió. Y una sola fila con contador.

**Decisión: una sola `Senal__c` por `messageId`, con contador de entregas.** Cuando llega
un reenvío se incrementa `Entregas__c` y se actualizan `Ultimo_Delivery_Id__c` y
`Ultima_Fecha_Publicacion__c`. La garantía de unicidad sigue viniendo de la base de datos
y la bitácora sigue respondiendo «a este mensaje me llegaron tres entregas, la última a
las 21:56». Si más adelante hiciera falta el detalle entrega a entrega, se añade el objeto
hijo sin tocar nada de lo existente.

## Las unidades

El catálogo declara para cada medición una unidad principal y una alterna:

| Medición | Unidad | Unidad alterna | Decimales |
| --- | --- | --- | --- |
| `TEMPERATURE` | `CELSIUS` | `FAHRENHEIT` | 1 |
| `WATER_CONSUMPTION` | `LITER_PER_15_MIN` | `GALLON_PER_15_MIN` | 0 |
| `ENERGY_CONSUMPTION` | `KWH_PER_15_MIN` | `WATT` | 1 |
| `WATER_PRESSURE` | `BAR` | `PSI` | 2 |

No es teórico: en una tanda de 200 mensajes del escenario `QA_200` apareció al menos una
lectura de energía en `WATT`.

**Decisión: la unidad se valida contra la del límite configurado y no se convierte.** Una
lectura que llega en la unidad alterna se rechaza con el motivo «unidad no compatible».

La razón es que convertir exige una tabla de factores que hoy no tenemos confirmada, y un
factor equivocado clasificaría mal la lectura en silencio. Un dato ausente es visible; un
dato mal clasificado no lo es, y el operador confía en él. Queda registrado que esta
decisión es reversible: si más adelante se añade la conversión, el motivo pasa de no
reintentable a reintentable y los mensajes ya guardados se pueden reprocesar, porque la
bitácora conserva la carga original.

## Validaciones

Cada mensaje se valida por separado. Un mensaje inválido se rechaza con un motivo escrito
y no impide que los demás de la misma página sigan su camino.

| Validación | Motivo registrado | ¿Reintentable? |
| --- | --- | --- |
| `schemaVersion` de la página reconocida | Versión no soportada | Sí |
| `messageId` presente y no vacío | Campo faltante | No |
| `messageType` en el catálogo conocido | Tipo de mensaje desconocido | Sí |
| Existe un `Edificio__c` con ese `building.id` | Edificio no encontrado | Sí |
| Existe un `Activo__c` con ese `asset.id` | Activo no encontrado | Sí |
| El activo pertenece a ese edificio | Activo no coincide con el edificio | No |
| `occurredAt` es una fecha válida | Fecha inválida | No |
| `occurredAt` no supera la tolerancia de futuro | Fecha futura | No |
| `measurement.type` en el catálogo | Tipo de medición desconocido | Sí |
| `measurement.value` presente y numérico | Valor inválido | No |
| `measurement.unit` coincide con la del límite | Unidad no compatible | No |
| Existe un `Umbral__c` vigente para ese tipo y medición | Sin límite configurado | Sí |
| `communication.status` en `HEALTHY`/`LOST`/`RESTORED` | Estado de comunicación inválido | No |
| `communication.episodeId` presente | Campo faltante | No |

El criterio que separa reintentable de no reintentable es sencillo y conviene dejarlo
explícito, porque es lo que responde la pregunta que hace el administrador en US-209: si
el mensaje está bien y lo que falta es configuración nuestra, reintentar va a funcionar en
cuanto la configuración exista. Si el mensaje está mal, reintentar da exactamente el
mismo resultado y no tiene sentido.

### Sobre la tolerancia de futuro

Los escenarios `MIXED` e `INVALID_DATA` envían mensajes con `occurredAt` dos días por
delante de `publishedAt`:

```
occurredAt  2026-09-24T21:55:28.402Z
publishedAt 2026-09-22T21:55:28.402Z
```

Un reloj mal sincronizado en un sensor produce desfases de segundos o minutos, no de días.
**Decisión: se aceptan hasta cinco minutos de adelanto sobre la hora del sistema y se
rechaza por encima.** El valor se guarda en una constante nombrada y no repartida por el
código, para que cambiarlo sea una línea.

### Sobre las claves repetidas dentro de una misma página

Hay una validación que no depende de ningún campo sino de la página completa: que dos
mensajes de la misma tanda no traigan la misma clave. Importa más de lo que parece,
porque una operación de `upsert` con claves repetidas en la misma llamada falla entera,
no a medias, y se lleva por delante los mensajes buenos.

**Decisión: la deduplicación dentro de la página se hace en memoria antes de tocar la base
de datos.** Se recorre la página construyendo un mapa por clave; si la clave ya está, se
compara el resumen de contenido y se marca el segundo como duplicado o conflicto sin
volver a insertarlo. Es la diferencia entre procesar 189 mensajes correctamente y perder
los 200.

## Ejemplos verificados

### Una lectura normal

```json
{
  "deliveryId": "dlv_000002",
  "messageId": "msg_000002",
  "messageType": "MEASUREMENT",
  "source": "nova-casa-simulator",
  "building": { "id": "BLD-BOG-001", "name": "Edificio Nova Alameda", "city": "Bogotá" },
  "asset": { "id": "AST-BOG-PUMP-001", "name": "Bomba de presión de agua", "type": "WATER_PUMP" },
  "sensorId": "SNS-BOG-PUMP-001",
  "measurement": { "type": "WATER_PRESSURE", "value": 2.76, "unit": "BAR" },
  "occurredAt": "2026-09-22T21:54:25.597Z",
  "publishedAt": "2026-09-22T21:54:28.614Z"
}
```

Se guarda con la clave `nova-casa-simulator|msg_000002`. La presión normal para una bomba
va de 2.5 a 4 BAR, así que 2.76 clasifica como normal, se actualiza el estado actual de
presión de esa bomba y no se abre ningún incidente.

### Una pérdida de comunicación

```json
{
  "deliveryId": "dlv_000008",
  "messageId": "msg_000008",
  "messageType": "CONNECTIVITY",
  "source": "nova-casa-simulator",
  "building": { "id": "BLD-BOG-001", "name": "Edificio Nova Alameda", "city": "Bogotá" },
  "asset": { "id": "AST-BOG-CAM-001", "name": "Cámara acceso vehicular", "type": "SECURITY_CAMERA" },
  "sensorId": "SNS-BOG-CAM-001",
  "communication": {
    "status": "LOST",
    "gapSeconds": 180,
    "lastSeenAt": "2026-09-22T21:56:50.118Z",
    "episodeId": "EPI-BOG-out-0"
  },
  "occurredAt": "2026-09-22T21:59:46.520Z",
  "publishedAt": "2026-09-22T21:59:50.118Z"
}
```

No trae valor ni unidad, y por eso esos campos son condicionales. Ciento ochenta segundos
de silencio con una tolerancia de advertencia de quince minutos todavía no escala.

### Un mensaje inválido

```json
{
  "deliveryId": "dlv_000001",
  "messageId": "msg_000001",
  "messageType": "MEASUREMENT",
  "source": "nova-casa-simulator",
  "building": { "id": "BLD-BAQ-001", "name": "Edificio Nova Caribe", "city": "Barranquilla" },
  "asset": { "id": "AST-BAQ-TEMP-001", "name": "Sala técnica principal", "type": "TECHNICAL_ROOM" },
  "sensorId": "SNS-BAQ-TEMP-001",
  "measurement": { "type": "TEMPERATURE", "value": null, "unit": "CELSIUS" },
  "occurredAt": "2026-09-22T21:53:30.162Z",
  "publishedAt": "2026-09-22T21:53:31.344Z"
}
```

El valor viene nulo. Se rechaza con el motivo «valor inválido», se marca como no
reintentable y se guarda la carga original. Los demás mensajes de la tanda no se enteran.

### Un activo que no existe

```json
{
  "deliveryId": "dlv_000008",
  "messageId": "msg_000008",
  "messageType": "MEASUREMENT",
  "source": "nova-casa-simulator",
  "building": { "id": "BLD-BAQ-001", "name": "Edificio Nova Caribe", "city": "Barranquilla" },
  "asset": { "id": "AST-UNKNOWN-0001", "name": "Activo no catalogado", "type": "UNKNOWN" },
  "sensorId": "SNS-UNKNOWN-0001",
  "measurement": { "type": "WATER_PRESSURE", "value": 2.56, "unit": "BAR" },
  "occurredAt": "2026-09-22T22:00:28.667Z",
  "publishedAt": "2026-09-22T22:00:29.512Z"
}
```

Se rechaza con «activo no encontrado» y se marca **reintentable**, porque el mensaje está
bien: lo que falta es un registro nuestro. Si alguien da de alta ese activo, reintentar
funciona. Es exactamente el caso que justifica que la bitácora guarde la carga completa.
