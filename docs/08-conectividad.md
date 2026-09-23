# 08 · Conectividad

Cubre la parte de comunicación de **US-205** y **US-206**.

Este módulo es el que más cambió respecto al discovery, y cambió para bien. Lo que era el
riesgo más serio del sprint resultó estar resuelto por el proveedor.

## El concepto de base: detectar una ausencia

Detectar que algo **pasó** es fácil: llega un mensaje. Detectar que algo **dejó de pasar**
no lo es, porque la ausencia de mensajes no produce ningún evento que se pueda escuchar.

Hay dos familias de solución.

**Inferir el silencio.** El consumidor guarda cuándo vio por última vez a cada emisor y un
proceso periódico recorre la lista buscando a los que llevan demasiado sin aparecer. Es
autónomo: funciona aunque el emisor desaparezca del todo. Pero tiene dos costes. El de
vigilancia crece con el número de emisores, porque hay que recorrerlos todos. Y produce
falsas alarmas cada vez que el proveedor se retrasa, porque un retraso de la integración
es indistinguible de un sensor caído.

**Que el proveedor avise.** El emisor manda un mensaje explícito diciendo que perdió a un
sensor. El coste de vigilancia es cero y no hay falsas alarmas por retraso. A cambio, si
el proveedor entero desaparece no llega ningún aviso, porque el aviso venía de él.

El discovery eligió la segunda, apostando a que el proveedor avisaría. Eso dejó abierta la
pregunta Q-14, que era la única cuya respuesta cambiaba el diseño en lugar de completarlo:
**¿el aviso se repite mientras la pérdida persiste, o llega una sola vez?**

Importaba porque toda la escalada por tiempo dependía de ello. Si llegara una sola vez y
nada estuviera mirando el reloj, la gravedad se quedaría en advertencia para siempre y el
incidente crítico no se crearía nunca. Ese era el riesgo R-16.

## Lo que hace el proveedor

El escenario `CAMERA_OUTAGE` responde la pregunta. Esta es una secuencia real de un mismo
episodio, resumida:

| Mensaje | `status` | `gapSeconds` | `episodeId` |
| --- | --- | --- | --- |
| `msg_000006` | `HEALTHY` | 60 | `EPI-BOG-hb` |
| `msg_000007` | `LOST` | 90 | `EPI-BOG-out-0` |
| `msg_000008` | `LOST` | 180 | `EPI-BOG-out-0` |
| `msg_000009` | `LOST` | 270 | `EPI-BOG-out-0` |
| `msg_000010` | `LOST` | 360 | `EPI-BOG-out-0` |
| `msg_000011` | `LOST` | 450 | `EPI-BOG-out-0` |
| `msg_000012` | `RESTORED` | 450 | `EPI-BOG-out-0` |
| `msg_000025` | `HEALTHY` | 45 | `EPI-BOG-hb` |

**El aviso se repite.** El supuesto S-01 se confirma y el riesgo R-16 se cierra. Toda la
escalada por tiempo del diseño funciona tal como estaba pensada.

Y hay tres regalos que no habíamos previsto.

### `gapSeconds`

El proveedor **calcula y envía** los segundos transcurridos desde el último contacto. El
discovery preveía guardar la hora del primer aviso y recalcular el tiempo transcurrido en
cada mensaje. No hace falta: se lee el campo.

Eso elimina una fuente de error real. Calcular el tiempo transcurrido nosotros exigiría
que nuestro reloj y el del proveedor estuvieran de acuerdo, y un desfase produciría
escaladas prematuras o tardías. Ahora la medida del silencio la da quien está en posición
de saberlo.

**Decisión: la severidad de conectividad se calcula sobre `gapSeconds` del mensaje, nunca
sobre una diferencia de fechas calculada por nosotros.**

### `HEALTHY`

Existe un tercer estado que el discovery no anticipó: un latido periódico que confirma que
el sensor sigue vivo. En una secuencia normal es la mayoría del tráfico de conectividad.

Un latido es valioso justo por lo que parece que no dice. Un `HEALTHY` reciente es la
prueba de que el canal entero funciona, y por tanto la única forma de distinguir «este
sensor está bien» de «hace rato que no sé nada de nadie».

### `episodeId`

Cada corte tiene identificador propio. Todos los mensajes de un mismo corte lo comparten,
y dos cortes de la misma cámara tienen identificadores distintos: `EPI-BOG-out-0`,
`EPI-BOG-out-2`. Los latidos usan un identificador aparte, `EPI-BOG-hb`.

## El alcance del aviso

El mensaje trae `asset.id` y `sensorId`. No hay avisos a nivel de edificio.

Eso responde Q-16: **el aviso es por activo.** El sensor se guarda como dato informativo,
porque en el catálogo actual cada activo tiene exactamente uno, y hacer el modelo por
sensor añadiría un nivel de indirección que hoy no compra nada.

Si más adelante un activo tuviera varios sensores, la granularidad tendría que bajar a
sensor. El modelo lo absorbería añadiendo el sensor a la clave del estado actual, sin
rediseñarse.

En el catálogo actual, los únicos activos que emiten conectividad son las dos cámaras. Su
medición es `CAMERA_CONNECTIVITY`, con unidad `SECONDS`, y **no tiene umbrales de
referencia en el catálogo**: la conectividad no se clasifica por valor sino por tiempo.

## La escalada por tiempo

`Umbral__c` tiene dos campos para esto: `Minutos_Advertencia__c` y `Minutos_Critico__c`.
Se configuran contra la clave `SECURITY_CAMERA|CAMERA_CONNECTIVITY`.

**Valores iniciales: quince minutos para advertencia, sesenta para crítico.** No vienen del
catálogo; los fijamos nosotros y quedan como supuesto documentado, sustituible editando el
registro, que es la capacidad que pide US-204.

La regla:

| Estado | Condición | Severidad |
| --- | --- | --- |
| `HEALTHY` | siempre | Normal |
| `LOST` | `gapSeconds / 60 >= Minutos_Critico__c` | Crítico |
| `LOST` | `gapSeconds / 60 >= Minutos_Advertencia__c` | Advertencia |
| `LOST` | por debajo de ambos | Normal |
| `RESTORED` | siempre | Normal |

Igual que en la clasificación por valor, **se evalúa crítico antes que advertencia**, y las
comparaciones son inclusivas: exactamente quince minutos ya es advertencia.

Un `LOST` de noventa segundos con estos umbrales clasifica como normal. Eso es correcto y
conviene que no sorprenda: un corte de minuto y medio no merece despertar a nadie. Lo que
sí hace es marcar `Estado_Comunicacion__c` como `LOST`, de modo que la pantalla lo
distinga visualmente aunque no escale.

## El estado actual de conectividad

Un mensaje de conectividad escribe el mismo `Estado_Actual__c` que una medición, con la
clave `AST-BOG-CAM-001|CAMERA_CONNECTIVITY`. Es la misma fila y el mismo mecanismo de
vigencia por `occurredAt`.

Los campos que toca:

| Campo | `HEALTHY` | `LOST` | `RESTORED` |
| --- | --- | --- | --- |
| `Estado_Comunicacion__c` | `HEALTHY` | `LOST` | `RESTORED` |
| `Sin_Comunicacion_Num__c` | 0 | 1 | 0 |
| `Gap_Segundos__c` | el del mensaje | el del mensaje | el del mensaje |
| `Ultima_Vez_Visto__c` | `lastSeenAt` | `lastSeenAt` | `lastSeenAt` |
| `Episodio_Id__c` | se vacía | el del mensaje | se conserva |
| `Severidad__c` | Normal | según la tabla | Normal |
| `Valor__c` | — | — | — |

`Valor__c` queda vacío siempre: un mensaje de conectividad no es una lectura y no tiene
valor. Es el supuesto S-03, confirmado contra la API.

Que `Episodio_Id__c` se conserve en `RESTORED` y se vacíe en `HEALTHY` es deliberado: el
mensaje de recuperación todavía pertenece al episodio que acaba de terminar, y el latido
siguiente ya no.

## El incidente de conectividad

### Por qué el episodio es la clave

Para las mediciones, la clave del incidente es `activo|medición`. Aplicarlo aquí daría
`AST-BOG-CAM-001|CAMERA_CONNECTIVITY`, y sería incorrecto.

El motivo se ve en la secuencia real. La misma cámara sufre `EPI-BOG-out-0` y, un rato
después, `EPI-BOG-out-2`. Con la clave por activo, si el primer caso siguiera abierto —y
va a seguirlo, porque el cierre es humano— el segundo corte no abriría nada y se
confundiría con el primero. El coordinador vería un caso donde hubo dos averías.

El `episodeId` resuelve exactamente eso, y lo resuelve mejor que cualquier clave que
pudiéramos construir nosotros, porque lo emite quien sabe dónde empieza y termina cada
corte.

**Decisión: la clave del incidente de conectividad es `CONN|` más el `episodeId`.**

Las propiedades que da: los cinco `LOST` de un mismo corte producen un solo caso que
escala de baja a alta conforme crece `gapSeconds`; dos cortes distintos producen dos casos,
aunque el primero siga abierto; y el caso queda etiquetado con el episodio, así que el
coordinador puede correlacionarlo con la bitácora sin ambigüedad.

### Qué hace `RESTORED`

**Decisión: `RESTORED` marca el caso como recuperado pero no lo cierra.**

Concretamente: limpia el estado de comunicación, escribe la evidencia en el caso y lo deja
abierto para que una persona lo revise. Es coherente con la regla general del
[módulo 07](07-incidentes.md) de que cerrar es una afirmación humana.

Aquí hay además un motivo específico. Una cámara que se cae y se recupera sola cinco veces
en una tarde tiene un problema, aunque en ningún momento esté caída. Si el sistema cerrara
cada episodio al recuperarse, ese patrón sería invisible. Dejando los casos abiertos, el
coordinador ve tres casos de la misma cámara en el tablero y entiende que hay que mirarla.

## Los latidos y la bitácora

En una secuencia normal, la mayoría de los mensajes de conectividad son `HEALTHY`. Surge
la pregunta de si vale la pena guardarlos, porque van a ser la parte que más hace crecer
la bitácora y no indican ningún problema.

**Decisión: se guardan todos, con el mismo tratamiento que cualquier otra señal.**

Tres razones. La primera es literal: US-201 pide distinguir una publicación aceptada de una
señal efectivamente procesada **para toda señal recibida**, sin excepciones por tipo.
Excluir los latidos abriría un agujero en esa garantía.

La segunda es de diagnóstico. La pregunta «¿desde cuándo no sé nada de esta cámara?» se
responde mirando el último latido. Sin latidos en la bitácora, no hay forma de
distinguir un sensor que estaba bien de uno del que nunca supimos nada.

La tercera es de coherencia del modelo. Un tipo de mensaje que se procesa pero no se
registra sería una excepción que habría que recordar en cada consulta a la bitácora, y las
excepciones que hay que recordar se olvidan.

El coste es volumen, y está acotado: dos cámaras. El diseño ya asume que la bitácora crece
sin techo y que la pantalla no la consulta nunca.

## Lo que sigue sin cubrirse

Hay que decirlo claro, porque es el riesgo R-15 y se acepta a conciencia.

**Si el proveedor entero deja de responder, no llega ningún aviso de pérdida y el sistema
no tiene forma de enterarse.** El aviso venía justamente de él. Todos los sensores
aparecerían con su último estado conocido, que probablemente sea `HEALTHY`, y la pantalla
mostraría todo en orden.

La única defensa es el indicador de consulta atrasada del
[módulo 09](09-experiencia-del-operador.md), alimentado por
`Control_de_Ingesta__c.Ultima_Consulta_Exitosa__c`. Es insuficiente si el silencio se
prolonga y nadie mira la pantalla, y así queda dicho.

Construir un vigilante propio para cubrir este caso costaría más de lo que evita y
reintroduciría exactamente las falsas alarmas que quisimos quitar al elegir el modelo de
aviso explícito. Es un intercambio consciente, no un olvido.

**El resto de activos no emite conectividad.** Solo las cámaras. Una bomba que deja de
reportar no produce ningún `LOST`: su última lectura se queda ahí, y la única defensa es la
columna de antigüedad de la lectura descrita en el [módulo 06](06-estado-actual.md). Con el
catálogo actual es así y no está en nuestra mano cambiarlo.
