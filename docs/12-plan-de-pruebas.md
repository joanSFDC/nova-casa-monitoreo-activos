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
| Respuesta 409 | Se abre sesión nueva y se registra en `Ultimo_Error__c`, que la página buena siguiente no borra |
| Cambio de escenario o semilla | El cursor se vacía y el ciclo siguiente abre sesión con el escenario elegido; cambiar la tanda o apagar la ingesta lo conserva, y la sesión que abre la ingesta conserva su cursor |
| Respuesta 429 | El ciclo se corta y el cursor **no** se pierde |
| Respuesta 401 | La cadena se corta y queda registrado |
| Claves repetidas en la misma página | Se deduplica en memoria y no falla la operación entera |
| Reenvío idéntico de una señal aplicada | Conserva resultado y `Fecha_Procesamiento__c` |
| Conflicto en otra página | La fila conserva la primera afirmación y el detalle nombra la entrega distinta |
| Mensaje sin `messageId` | Se guarda rechazado por campo faltante, con su carga y una clave inventada que no se busca entre las previas; el válido de la misma página sigue su camino |
| Tipo de mensaje desconocido | La señal se guarda rechazada, con el tipo recibido en el detalle |
| Señal que no se puede guardar | Queda un rastro Fallido con «Error del sistema» y el error |

La de la respuesta 401 es la que más vale y la que menos se escribe: verifica que un fallo
de autenticación no deje el sistema girando en vacío.

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
| Crítico bajo sobre las altas | Crítico bajo 20 con advertencia alta 10 no se guarda |
| Medición solo con minutos | Un umbral de temperatura sin bandas no se guarda |
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
| Crítico superado en la tanda | Un crítico y una advertencia posterior en la misma tanda abren el caso en baja, con la advertencia como origen |
| Conflicto | Misma clave con distinto contenido se marca conflicto y no abre caso |
| Concurrencia | Un error de duplicado se trata como éxito y se reintenta la escalada |
| **Cierre y reapertura** | Cerrar, volver a poner en crítico, y se abre uno nuevo |
| Fallo al crear el caso | La señal queda fallida y el estado actual **sí** se actualizó |
| Cola del coordinador | El crítico nace en la cola Coordinación; la advertencia no; la escalada y su reintento pasan el caso a la cola |
| Caso ya tomado | Escala a alta y conserva a la persona que lo tomó |
| Lectura de apertura | El caso guarda la lectura que lo abrió con su unidad, su severidad y su fecha de origen; al abrir, la última lectura es la misma |
| Escalada con lecturas | La apertura sigue siendo la advertencia y la última lectura pasa a ser el crítico, con su señal |
| Severidad repetida | Otro crítico no reescribe el caso ni se liga a él, y guarda su lectura con los decimales del umbral |
| Bajada | De crítico a advertencia cambia la última lectura y no baja la prioridad |
| Normalización | Una lectura normal deja el caso abierto, «Normalizado», con la fecha de origen; la señal queda ligada y la prioridad no baja |
| Reincidencia | Falla después de normalizado: vuelve a «En falla», se borra la fecha y no se abre otro caso |
| Normal sin caso | Una lectura normal sin caso abierto no abre nada |
| Caso manual | El que abre el monitor guarda la lectura del estado actual, sin que la persona pueda escribir esos campos |

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
| Recuperación | `RESTORED` limpia el estado y **no** cierra el caso: lo deja «Normalizado», con «Comunicación recuperada» como última lectura |
| Lecturas del corte | El caso de un corte guarda «Sin comunicación · 15 min» al abrir y «Sin comunicación · 1 h» al escalar |
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
| Suscripción | Escucha `Panel_Actualizado__e`, no el aviso de la ingesta; el timbre dispara una consulta nueva y nada de lo que llegue por el canal se pinta |
| Timbre | Una tanda que escribe estados publica un solo timbre; una que solo rechaza, ninguno; dentro de una ventana de 30 s solo toca la primera tanda, y la de la ventana siguiente vuelve a tocar (`ProcesamientoServicioTest`). Operador, coordinador y gerente leen el timbre y no el aviso |
| Pestaña oculta | Con la pestaña oculta el monitor cancela la suscripción y no consulta; al volver se suscribe otra vez, consulta y reanuda la vigilancia (`monitorDeActivos`) |
| Vigilancia | Sin consultas en un minuto, vuelve a pedir el panel; una consulta por timbre reinicia el minuto; al desmontar se cancela |
| Sin tiempo real | Si empApi informa un error o la suscripción no se completa, aparece y se anuncia que la actualización automática no está disponible; un timbre posterior lo quita |
| Región activa | Anuncia «Actualizando», «Monitor actualizado a las HH:MM» y el error; la vigilancia solo anuncia si cambia el aviso de atraso |
| Agrupación | Una sección por edificio, con su ciudad y su resumen; con el orden por severidad, el edificio con lo más grave va primero |
| Ícono | Cada fila dibuja el tipo de su equipo, y un tipo desconocido usa un ícono genérico |
| Comunicación en la lectura | No hay columna Comunicación; solo la cámara muestra la ficha de su corte, también «En línea» |
| Normalizado | Un equipo normal con caso abierto muestra «Normalizado · caso abierto» y «Ver incidente»; la cámara sigue llevando al caso del corte cuando vuelve la comunicación |
| Filtros del navegador | Tipo de equipo, búsqueda sin tildes, orden por antigüedad y la ficha sin comunicación filtran sobre filas ya autorizadas; sin resultados, ofrece quitar los filtros |
| Pastilla de severidad | Pinta cada severidad con su color y su nombre, y «Sin datos» cuando falta |
| Resumen del incidente | Muestra lo que lo abrió, su último cambio y cómo está ahora; avisa de normalizado si el caso sigue abierto, no si está cerrado; dice «Sin registro» en un caso anterior a las lecturas; no muestra nada si el servidor no deja ver el caso |
| Historia del incidente | Las intervenciones abiertas, primero la que vence antes; la línea de tiempo del más reciente al más viejo con la intervención completada, el cambio crítico, el cambio y la apertura; la integración se muestra como «Sistema»; diez eventos y «Ver toda la historia» hasta cien; un caso ajeno devuelve `null` (`HistoriaIncidenteControladorTest`); el texto «Prioridad: Baja a Alta» y un nombre para el lector de pantalla en cada punto (`historiaIncidente`) |
| Lecturas del periodo | Recorre 120 señales en páginas de 50, 50 y 20 sin repetir ni saltar ninguna, aunque cinco compartan el segundo del borde; solo el activo, su tipo de mensaje y el periodo del caso; empieza en la señal que lo abrió; avisa la ventana de siete días; el coordinador recibe la página; quien no lee la bitácora recibe `null`; una posición con demasiados identificadores se rechaza (`LecturasPeriodoControladorTest`) |
| Tarjeta de lecturas | No aparece sin acceso a la bitácora; entra cerrada sin consultar; trae la primera página con su rango y la nota de la ventana; pide la siguiente con la posición y vuelve sin pedir otra vez; muestra la rechazada con su lectura, su color y su motivo; vacío, error y caso ajeno; tabla con encabezados y tarjeta con nombre (`lecturasPeriodo`) |
| Aviso de caso crítico | El incidente queda guardado al nacer en rojo, al escalar desde advertencia y sin ciudad; las fórmulas del correo dicen «Nació en rojo», «Escaló desde advertencia», la hora de Bogotá de la última modificación, el corte de una cámara y «Está en la cola de Coordinación, sin responsable.» (`AvisoCasoCriticoTest`) |
| Limpieza de la bitácora | Borra las aplicadas y atrasadas de más de 7 días y las rechazadas de más de 90; deja las recientes, una rechazada de un mes, las ligadas a un caso y las pendientes; cuenta lo borrado por día, equipo, resultado y motivo y suma a la fila que ya existe; con la ingesta caída o con más pendientes que el máximo no borra; se programa a las 2 a. m. y el programador lanza el Batch (`BitacoraRetencionBatchTest`) |
| Ingesta caída | El corte por fallos marca la caída con el último error, y seguir fallando no la repite; diez minutos sin consultas la marcan; cinco no, una ingesta apagada tampoco y una ya avisada no se vuelve a marcar; la siguiente consulta exitosa la cierra con los minutos que duró; el vigía se programa en seis trabajos y se quita (`AvisoIngestaServicioTest`) |
| Lectura recibida | Una unidad que no es la del umbral se rechaza al recibir y guarda «72,5 PSI»; una cámara rechazada guarda su corte; un valor nulo no guarda lectura; una señal en conflicto antes de procesarse guarda la lectura de la primera afirmación (`IngestaServicioTest`) |
| Resumen del activo y del edificio | Junta mediciones, casos y límites o conteos; «En falla» solo si el caso lo registra; el operador de Bogotá no recibe el resumen de Caribe (`ResumenRegistroControladorTest`) |
| Bandas del umbral | Dibuja las cinco bandas con sus fronteras, omite la que falta y en una cámara cuenta minutos; en la página del umbral lee el registro |
| Resultado de la señal | Pinta el resultado con su color, su motivo, si se puede reintentar y las entregas, y explica qué significa |

La última se verifica en el componente comprobando que la carga del evento no llega a
ninguna propiedad del estado visual. Es la prueba del riesgo R-07.

### US-208 · Autorización

Detallada en el [módulo 10](10-seguridad-y-accesos.md). Cuatro usuarios de prueba, todas
las consultas dentro de `System.runAs`. Cada botón tiene la suya: «Abrir intervención» se
ofrece a quien crea casos y se niega al gerente también en el servidor, «Registrar
intervención» solo lo tiene el coordinador, y las lecturas del caso se leen sin poder
escribirse.

El panel de gerencia es metadato y no tiene prueba de Apex. Se comprueba en la org con
«Iniciar sesión como»:

| Prueba | Afirma |
| --- | --- |
| Gerente, filtro Bogotá | Los dos gráficos quedan vacíos |
| Gerente, filtro Barranquilla | Equipos fuera de rango y casos abiertos coinciden con los informes |
| Gerente, informe | Ve «Suscribir» en el informe de casos |
| Operador | La barra no muestra Paneles ni Informes |
| Gerente, monitor | Ve «Ver incidente» y nunca «Abrir intervención» |
| Coordinador, caso | La cabecera muestra «Registrar intervención» y crea la tarea; operador, gerente y administrador no la ven |
| Cada rol, inicio | El operador entra por Nova Casa Operación con el monitor y sus incidentes abiertos; el coordinador por Coordinación con la cola, el monitor y las rechazadas de hoy; el gerente por Gerencia con el panel y los críticos abiertos; el administrador por Administración con la salud de la ingesta, las atascadas y las rechazadas de hoy |
| Operador, coordinador y gerente, caso | «Historia del incidente» muestra la intervención abierta de 00001149 en español y los cambios con «Sistema»; el operador de Bogotá no abre el caso de Barranquilla |
| Coordinador, caso | «Lecturas del periodo» entra cerrada; al abrirla trae 50 lecturas en menos de un segundo, la siguiente página dice «Lecturas 51 a 100» y volver no consulta; el operador no ve la tarjeta |
| Incidente crítico de prueba | El 00002442, en la bomba de Barranquilla, escala de advertencia a alta: llegan los dos correos de «Nova Casa · Monitoreo», el del operador de Barranquilla y el del coordinador; a las 2 horas, el gerente recibe «Caso crítico sin atender» en la campana. Después se cierra |
| Primera limpieza en la org | Con la ingesta funcionando: 227 lotes en unos 41 minutos, sin errores; 452.402 señales borradas y contadas en el resumen; la ingesta siguió consultando cada minuto y no hubo caída avisada |
| Ingesta caída de prueba | Se marca la caída a mano en el control con el motivo «Prueba del aviso de ingesta caída»: llegan el correo y la campana de caída al administrador, y la siguiente consulta exitosa la cierra sola y manda el de vuelta |
| Bitácora en la org | Después de desplegar, toda aplicada, atrasada y rechazada nueva tiene lectura, y cada señal ligada nueva corresponde a un cambio del caso en su historial |

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

**La prueba de volumen con críticos.** La prueba de cinco contra doscientos avisos usa
lecturas normales y nunca pasa por los casos. Por eso hay una segunda,
`ProcesamientoServicioTest.shouldUnCasoPorEquipoYConsumoConstante_WhenDoscientosCriticos`:
quince bombas, una tanda de cinco críticos de cinco bombas y otra de doscientos críticos
de las otras diez, veinte por bomba. Comprueba que la tanda grande no hace más consultas
ni más escrituras que la chica, que hay un solo caso abierto por bomba, todos en prioridad
alta, y que en cada bomba gana una lectura y las otras diecinueve quedan Atrasado.

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
