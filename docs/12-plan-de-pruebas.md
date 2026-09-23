# 12 · Plan de pruebas

Cubre la parte verificable de **US-202** y prepara **US-210 · Calidad y entrega**.

## El regalo de los escenarios

El simulador expone nueve escenarios y no son un catálogo decorativo: **mapean casi uno a
uno contra nuestros criterios de aceptación.** Quien los diseñó pensó en lo que hay que
demostrar.

| Escenario | Qué produce | Qué criterio demuestra |
| --- | --- | --- |
| `MIXED` | Mediciones, conectividad, algún duplicado y alguna fecha futura | El recorrido completo. Es el de la demo |
| `QA_200` | Exactamente 200 mensajes en una página, con `hasMore` falso | US-202, la prueba de volumen |
| `BOUNDARIES` | Los valores frontera exactos de cada medición | US-204, la clasificación en la frontera |
| `CRITICAL_BURST` | Ráfaga de lecturas críticas | US-205, un solo incidente bajo ráfaga |
| `LATE_MESSAGES` | Mensajes con hasta veinte minutos de retraso y fuera de orden | US-203, la vigencia por fecha de origen |
| `DUPLICATES` | El mismo `messageId` con contenido idéntico | US-205, la deduplicación |
| `CONFLICT` | El mismo `messageId` con contenido distinto | US-205, la detección de conflicto |
| `INVALID_DATA` | Valores nulos, fechas futuras, activos desconocidos | US-202, el aislamiento de fallos |
| `CAMERA_OUTAGE` | Ciclo completo de latido, corte y recuperación | US-206, la escalada por tiempo |

La **semilla** es lo que los convierte en pruebas de verdad. El simulador es determinista:
la misma semilla con el mismo escenario produce exactamente la misma secuencia. Una prueba
que fija la semilla es reproducible, y una demo que fija la semilla no depende de la
suerte.

## Las dos capas de prueba

Conviene separarlas porque responden preguntas distintas y fallan por motivos distintos.

**Pruebas unitarias en Apex.** Corren sin red, con datos construidos a mano. Verifican la
lógica: clasificación, vigencia, desempate, idempotencia, permisos. Son rápidas, se
ejecutan en cada despliegue y son las que impiden las regresiones.

**Verificación contra el simulador.** Corre contra la API real y verifica que el contrato
que escribimos es el contrato que existe. Es lo que habría detectado que
`COMMUNICATION_STATUS` no se llama así.

Las dos hacen falta. Unas pruebas unitarias perfectas contra un contrato equivocado pasan
todas y no sirven de nada.

### Cómo se prueba el callout sin red

Apex no permite llamadas HTTP dentro de una prueba. La plataforma ofrece
`HttpCalloutMock`: una clase que intercepta la llamada y devuelve una respuesta preparada.

**Decisión: las respuestas simuladas son capturas literales de la API real**, guardadas
como recursos estáticos, no JSON escrito a mano.

La diferencia no es menor. Un JSON escrito a mano refleja lo que **creemos** que manda el
proveedor, así que una prueba contra él confirma nuestras creencias en lugar de ponerlas a
prueba. Una captura real refleja lo que manda de verdad, con sus campos inesperados y sus
nombres exactos.

Los recursos estáticos que se guardan, uno por escenario, se capturan una vez y se
versionan en el repositorio.

## Las pruebas por historia

### US-201 · Recibir señales

| Prueba | Afirma |
| --- | --- |
| Página válida | Se crean las señales, se publican los eventos y se avanza el cursor |
| Fecha de origen separada | `Fecha_Origen__c`, `Fecha_Publicacion__c` y `Fecha_Recepcion__c` tienen valores distintos |
| Publicado no es procesado | Tras la ingesta, las señales están pendientes, no aplicadas |
| Cursor persistido | Tras la ingesta, `Control_de_Ingesta__c.Cursor__c` cambió |
| Respuesta 409 | Se abre sesión nueva y se registra en `Ultimo_Error__c` |
| Respuesta 429 | El ciclo se corta y el cursor **no** se pierde |
| Respuesta 401 | La cadena se corta y queda registrado |
| Claves repetidas en la misma página | Se deduplica en memoria y no falla la operación entera |

La penúltima es la que más vale y la que menos se escribe: verifica que un fallo de
autenticación no deje el sistema girando en vacío.

### US-202 · Procesar sin perder las válidas

Esta es la historia que pide resultados verificables, así que sus pruebas son las más
explícitas.

| Prueba | Afirma |
| --- | --- |
| Doscientos mensajes | Existen 200 señales, **ninguna pendiente**, y la suma de resultados es 200 |
| Cinco malos entre doscientos | 195 aplicadas y 5 rechazadas, cada una con su motivo |
| Consultas constantes | El número de consultas con 200 mensajes es igual que con 5 |
| Escrituras constantes | Lo mismo para las operaciones de escritura |
| Uno malo no tumba la tanda | Un valor nulo no impide que los demás se apliquen |
| Fallo del sistema aislado | Un fallo al escribir marca esa señal como fallida, no la tanda |

Las dos pruebas de conteo se escriben con `Limits.getQueries()` y `Limits.getDmlStatements()`
alrededor del bloque, comparando el consumo entre una tanda de cinco y una de doscientos.
Es la forma directa de verificar el criterio, y falla en el momento en que alguien mete una
consulta en un bucle.

**La trampa a evitar.** Una prueba que afirme «al publicar doscientos eventos el disparador
se ejecuta una vez con doscientos en `Trigger.new`» es frágil: la plataforma no garantiza
ese reparto. La afirmación correcta es sobre el resultado final, no sobre cómo se repartió
el trabajo.

### US-203 · Estado actual

| Prueba | Afirma |
| --- | --- |
| Lectura nueva | Reemplaza el estado y actualiza la fecha de origen |
| Lectura atrasada | **No** reemplaza el estado, y se guarda con resultado atrasado |
| Fuera de orden en la misma tanda | El estado final es el del `occurredAt` mayor |
| Empate de fecha | Gana el `messageId` mayor, de forma determinista |
| Empate procesado al revés | Mismo resultado que la prueba anterior |
| Crítico atrasado | Se registra como atrasado y **no** abre incidente |
| Dos mediciones del mismo activo | Son dos filas, y una no tapa a la otra |

Las pruebas cuarta y quinta son la misma situación procesada en los dos órdenes posibles.
Que den el mismo resultado es lo que demuestra que la regla de desempate es determinista,
y es la única forma de probarlo.

### US-204 · Límites administrables

| Prueba | Afirma |
| --- | --- |
| Valor en la frontera de normal | 30 °C clasifica normal |
| Valor en la frontera de advertencia | 35 °C clasifica advertencia |
| Un decimal por encima | 35.1 °C clasifica crítico |
| Frontera inferior | 15 °C clasifica advertencia, 14.9 crítico |
| Fuera de todas las bandas | 60.19 °C clasifica **crítico**, no se rechaza |
| Sin umbral | Rechazo con motivo, marcado reintentable |
| Rango contradictorio | La regla de validación impide guardar el umbral |
| Cambiar un límite | El historial **no** se reclasifica |
| Aplicar límites | Los estados afectados se reclasifican, sin abrir casos |

Los valores de las cinco primeras salen de las columnas de fronteras del catálogo. No son
inventados.

### US-205 · Una sola intervención

| Prueba | Afirma |
| --- | --- |
| Reenvío del proveedor | La segunda entrega incrementa `Entregas__c` y no publica evento |
| Reentrega del bus | El segundo procesamiento no crea un segundo caso |
| Ráfaga de críticos | Diez mensajes críticos del mismo activo producen **un** caso |
| Escalada | Una advertencia y después un crítico producen un caso que sube de prioridad |
| Conflicto | Misma clave con distinto contenido se marca conflicto y no abre caso |
| Concurrencia | Un error de duplicado se trata como éxito y se reintenta la escalada |
| **Cierre y reapertura** | Cerrar, volver a poner en crítico, y se abre uno nuevo |
| Fallo al crear el caso | La señal queda fallida y el estado actual **sí** se actualizó |

La séptima es la que protege contra el riesgo R-18 y **no es negociable**. Si el cierre
dejara de vaciar `Clave_Abierta__c`, ese activo no podría volver a abrir un incidente nunca
más, y el fallo sería completamente invisible sin esta prueba.

### US-206 · Severidad y conectividad

| Prueba | Afirma |
| --- | --- |
| Tres niveles | Normal, advertencia y crítico se distinguen en el estado |
| Peor gana | Un activo con normal y crítico resume como crítico |
| Latido | `HEALTHY` deja la severidad en normal y limpia el episodio |
| Corte corto | `LOST` con 90 segundos marca sin comunicación pero no escala |
| Corte de quince minutos | Escala a advertencia |
| Corte de una hora | Escala a crítico, sobre el **mismo** caso |
| Recuperación | `RESTORED` limpia el estado y **no** cierra el caso |
| Dos episodios | Dos cortes distintos producen dos casos, aunque el primero siga abierto |
| Advertencia | Crea caso en prioridad baja, sin propietario |

### US-207 · Experiencia del operador

| Prueba | Afirma |
| --- | --- |
| Contadores | Se calculan en el servidor y coinciden con las filas visibles |
| Orden | Lo crítico aparece primero |
| Antigüedad | Se calcula desde la fecha de origen |
| Estado vacío | Un operador sin edificios recibe una respuesta vacía, no un error |
| Aviso de ingesta atrasada | Aparece cuando la última consulta exitosa es antigua |
| Actualización manual | Vuelve a consultar el servidor |
| Suscripción | El aviso dispara una consulta nueva, no pinta su contenido |

La última se verifica en el componente comprobando que la carga del evento no llega a
ninguna propiedad del estado visual. Es la prueba del riesgo R-07.

### US-208 · Autorización

Detallada en el [módulo 10](10-seguridad-y-accesos.md). Cuatro usuarios de prueba, todas
las consultas dentro de `System.runAs`.

### US-209 · Trazabilidad

| Prueba | Afirma |
| --- | --- |
| Toda señal tiene resultado | Ninguna `Senal__c` queda sin `Resultado__c` |
| Los seis resultados | Cada uno se produce con un escenario que lo provoca |
| Reintentable derivado | Se deriva del motivo y es coherente en todas las ramas |
| Sin secretos | La carga guardada no contiene la cabecera de autorización |
| Acceso restringido | El operador no puede consultar la bitácora |

## La prueba de volumen

El riesgo R-05 dice que doscientas escrituras por ciclo pueden producir bloqueos sobre el
activo padre, por el recálculo de los resúmenes.

**La prueba: `QA_200` con los dos edificios, procesado en una sola tanda, verificando que
no aparecen errores de bloqueo y midiendo el consumo de límites.**

Se ejecuta dos veces: una con los estados ordenados por identificador de activo y otra sin
ordenar, para documentar la diferencia. Es la evidencia de que la decisión de ordenar del
[módulo 04](04-procesamiento.md) tiene efecto.

## La cobertura

Salesforce exige un 75 % para desplegar a producción. Es un mínimo administrativo, no un
objetivo de calidad: se puede llegar al 75 % con pruebas que no afirmen nada.

**Decisión: el objetivo es que cada criterio de aceptación tenga al menos una prueba que
falle si el criterio deja de cumplirse.** La cobertura es una consecuencia, no la meta.

El repaso de entrega se hace contra la tabla de criterios, no contra el porcentaje.

## El guion de la demo

`MIXED` con semilla fija para el recorrido completo, y después los escenarios concretos
para los momentos que hay que demostrar:

1. **`MIXED`** — el monitor con datos reales, lo crítico arriba, refresco automático.
2. **`DUPLICATES`** — se reenvía el mismo mensaje. El contador de entregas sube y el caso
   sigue siendo uno.
3. **`LATE_MESSAGES`** — llega una lectura vieja. La pantalla no cambia y la señal queda
   como atrasada.
4. **`BOUNDARIES`** — un valor exactamente en el límite, clasificado según la regla escrita.
5. **`CAMERA_OUTAGE`** — el ciclo completo de corte, escalada a crítico y recuperación.
6. **`INVALID_DATA`** — la bitácora con sus motivos y su distinción de reintentables.

Los tres primeros son los indicadores de éxito que se comprometieron en el Entregable 1 del
discovery. Los tres tienen la misma propiedad y por eso se eligieron: **se pueden ver
fallar.** Si el sistema se comportara mal, la demo lo mostraría en el momento, no en un
informe posterior.
