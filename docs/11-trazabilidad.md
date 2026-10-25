# 11 · Trazabilidad

Cubre **US-209 · Investigar el procesamiento**.

## El concepto de base: por qué guardar lo que se rechaza

Un sistema de integración que solo guarda lo que procesó correctamente no se puede
diagnosticar. Cuando alguien pregunta «¿qué pasó con el mensaje de las diez y cuarto?», la
respuesta es «no aparece», y eso no distingue tres situaciones completamente distintas:
que nunca llegó, que llegó y se rechazó, o que llegó y se perdió.

La diferencia importa porque cada una se arregla en un sitio. La primera es del proveedor,
la segunda es de configuración o de datos, la tercera es un defecto nuestro.

La práctica que lo resuelve es registrar **toda** señal recibida con un resultado
explícito, incluidas las que no se pudieron procesar. Convierte «no aparece» en «se rechazó
a las 10:15:33 porque el activo no existe, y se puede reintentar».

El segundo concepto es la diferencia entre **recibido** y **procesado**. Son dos momentos
separados por un bus asíncrono, y entre ellos puede pasar cualquier cosa. Un sistema que no
los distingue no puede responder si un mensaje está en camino o se quedó por el camino.

## Los resultados

Toda `Senal__c` tiene exactamente uno de estos seis valores en `Resultado__c`. No hay
señales sin resultado.

| Resultado | Qué significa | ¿Tocó el estado? | ¿Reintentar? |
| --- | --- | --- | --- |
| **Pendiente** | Se recibió y se publicó. El procesamiento no ha terminado | No | — |
| **Aplicado** | Actualizó el estado. Puede haber abierto o escalado un incidente | Sí | Sí, sin efecto |
| **Atrasado** | Su fecha de origen es anterior a la del estado vigente | No | Sí, sin efecto |
| **Conflicto** | Misma clave, contenido distinto | No | **No** |
| **Rechazado** | No pasó una validación | No | Según el motivo |
| **Fallido** | Pasó las validaciones pero falló al escribir | Parcialmente | Sí |

**Pendiente** es el que más se olvida y el que responde el criterio de US-201 sobre
distinguir una publicación aceptada de una señal efectivamente procesada. Una señal
pendiente significa que la ingesta hizo su trabajo y el procesamiento todavía no. Una
señal que lleva horas en pendiente es un síntoma: el aviso se publicó y nadie lo recogió.

**Fallido** es el resultado de la decisión del [módulo 04](04-procesamiento.md) sobre qué
pasa cuando falla la creación del incidente. El estado actual sí se actualizó; el caso no
se pudo crear. Es el único resultado donde estado e incidente quedan desalineados, y por
eso tiene nombre propio en lugar de confundirse con un rechazo.

La ingesta también lo usa cuando la propia señal no se puede guardar, o cuando el aviso no
se puede publicar. Si el guardado falla, se escribe un rastro mínimo: clave, identidad,
fechas y el error en `Detalle__c`, sin la carga, que puede ser justo lo que no cupo. Es
reintentable: un reenvío idéntico lo vuelve a intentar. Si tampoco entra el rastro, el
error queda en `Control_de_Ingesta__c.Ultimo_Error__c`.

Hay una excepción. A veces el `upsert` reporta `DUPLICATE_VALUE` sobre `Clave__c` para una
señal nueva que sí quedó guardada. Escribirle el rastro la sobrescribiría con Fallido y le
quitaría el aviso, así que la ingesta la relee por su clave: si existe, no hay rastro y,
si sigue Pendiente, su aviso se publica. Solo sin registro queda el rastro.

**Dónde se decidió** se lee en las fechas. La ingesta valida al recibir: lo que no pasa
queda Rechazado, un contenido distinto bajo la misma clave queda Conflicto y una señal que
no se puede guardar o avisar queda Fallido. Ninguna de las tres entra al bus, así que
`Fecha_Procesamiento__c` queda vacía y el momento de la decisión es `Fecha_Recepcion__c`.
El suscriptor vuelve a validar contra el catálogo y decide Aplicado, Atrasado, Rechazado o
Fallido; esas sí llevan fecha de procesamiento. Con la fecha vacía, solo Pendiente está
esperando algo.

**Conflicto** es el único que exige una persona. El sistema recibió dos afirmaciones
contradictorias sobre el mismo hecho y no tiene forma de saber cuál es cierta. Reintentar
no aporta nada: seguirían siendo contradictorias. Si la primera afirmación ya se había
aplicado, el estado y la fila la conservan; el conflicto avisa de que hay que revisarla
([módulo 01](01-contrato-del-mensaje.md)).

**Duplicado** sigue en la lista de valores, pero no se escribe. Un reenvío con la misma
clave y el mismo contenido suma uno a `Entregas__c` y la señal conserva su resultado:
si pasara a Duplicado, una señal ya aplicada perdería la constancia de que se aplicó. La
vista Duplicadas filtra por el contador, no por este valor.

El reenvío tampoco reescribe lo demás: solo anota la entrega. Si llega mientras el
suscriptor procesa la primera, el resultado que queda es el del suscriptor
([módulo 02](02-ingesta.md)). Una señal en Atascadas con `Entregas__c` en dos era el
síntoma de lo contrario.

## Los motivos

Cuando el resultado es rechazado o fallido, `Motivo__c` dice por qué. Es una lista
desplegable y no texto libre, porque los motivos hay que poder filtrar y contar. El texto
libre va en `Detalle__c`.

| Motivo | Resultado | Reintentable | Por qué |
| --- | --- | --- | --- |
| Versión no soportada | Rechazado | **Sí** | Se resuelve ampliando el contrato |
| Tipo de mensaje desconocido | Rechazado | **Sí** | Se resuelve ampliando el contrato |
| Edificio no encontrado | Rechazado | **Sí** | Falta configuración nuestra |
| Activo no encontrado | Rechazado | **Sí** | Falta configuración nuestra |
| Tipo de medición desconocido | Rechazado | **Sí** | Falta configuración nuestra |
| Sin límite configurado | Rechazado | **Sí** | Falta configuración nuestra |
| Sin minutos configurados | Rechazado | **Sí** | Falta configuración nuestra |
| Error del sistema | Fallido | **Sí** | Fallo temporal del entorno |
| Campo faltante | Rechazado | No | El mensaje está mal |
| Valor inválido | Rechazado | No | El mensaje está mal |
| Fecha inválida | Rechazado | No | El mensaje está mal |
| Fecha futura | Rechazado | No | El mensaje está mal |
| Activo no coincide con el edificio | Rechazado | No | El mensaje está mal |
| Estado de comunicación inválido | Rechazado | No | El mensaje está mal |
| Unidad no compatible | Rechazado | No, **por ahora** | Se acordó rechazar en vez de convertir |

El criterio que separa las dos mitades se puede decir en una frase, y es la que responde la
pregunta que hace el administrador: **si el mensaje está bien y lo que falta es algo
nuestro, reintentar va a funcionar en cuanto eso exista. Si el mensaje está mal, reintentar
da exactamente el mismo resultado.**

`Reintentable__c` no se escribe a mano en cada rama del código: se deriva del motivo en un
único sitio, un mapa de motivo a reintentabilidad. Así es imposible que dos ramas
clasifiquen el mismo motivo de forma distinta, y cambiar la política de un motivo es
cambiar una línea.

La última fila tiene un matiz que conviene conservar. «Unidad no compatible» es no
reintentable **hoy**, porque se decidió rechazar en lugar de convertir. El día que se añada
la conversión de unidades pasa a reintentable y los mensajes ya guardados se pueden
reprocesar, porque la bitácora conserva la carga original. Esa es una de las razones de
guardarla.

## Qué puede consultar el administrador

Con los campos del [módulo 03](03-modelo-de-datos.md), estas son las preguntas que la
bitácora responde directamente:

| Pregunta | Cómo se responde |
| --- | --- |
| ¿Qué pasó con este mensaje? | Buscar por `Clave__c` o `Message_Id__c` |
| ¿Qué se rechazó hoy y por qué? | Filtrar por resultado y fecha, ordenar por motivo |
| ¿Cuáles puedo reintentar? | Filtrar por `Reintentable__c` |
| ¿Qué llegó duplicado? | Filtrar `Entregas__c` mayor que uno |
| ¿Hay conflictos sin resolver? | Filtrar por resultado conflicto |
| ¿Algo se quedó atascado? | Filtrar pendientes con más de una hora desde la recepción |
| ¿Qué mensaje abrió este caso? | Desde el caso, `Origen_Senal__c` |
| ¿Este mensaje generó un caso? | Desde la señal, `Incidente__c`: el caso que abrió o cambió |
| ¿Qué midió el equipo durante el incidente? | Desde el caso, «Lecturas del periodo» |
| ¿Dónde está la demora? | Comparar las cuatro fechas |

## Cómo se accede

US-209 dice explícitamente que no se exige una consola nueva ni un botón de reproceso. Así
que no se construyen.

**Decisión: vistas de lista estándar sobre `Senal__c`, con una página de registro
configurada.**

Las vistas que se entregan:

| Vista | Filtro |
| --- | --- |
| Rechazadas hoy | Resultado rechazado, recepción de hoy |
| Reintentables | Reintentable marcado, resultado rechazado o fallido |
| Conflictos | Resultado conflicto |
| Duplicadas | `Entregas__c` mayor que uno |
| Atascadas | Resultado pendiente, más de una hora desde la recepción |
| Últimas 24 horas | Menos de 24 horas desde la recepción |

Una vista de lista estándar trae de fábrica búsqueda, filtros, ordenación, exportación,
gráficos y acceso desde el móvil. Construir un componente a medida sería reemplazar todo
eso por menos.

Las dos últimas filtran por **`Horas_Desde_Recepcion__c`**, una fórmula
`(NOW() - Fecha_Recepcion__c) * 24`. Sobre una fecha, una vista de lista solo filtra por
días: no admite `LAST_N_HOURS`, y `LAST_N_DAYS:1` son hoy y ayer enteros, hasta 48 horas.
Sobre un número calculado al leer, «más de 1» y «menos de 24» son horas exactas. La
fórmula no se puede indexar, así que cada vista lleva además un filtro sobre un campo
indexado que acota la búsqueda antes de mirar las horas: el resultado Pendiente en
Atascadas, y `LAST_N_DAYS:1` sobre la recepción en Últimas 24 horas.

El metadato de una vista **no fija orden ni agrupación**. Salesforce la abre ordenada por
nombre; quien la usa pulsa otra columna, por ejemplo la fecha de recepción o el motivo, y
la vista recuerda su elección.

La página de registro agrupa los campos en tres secciones que corresponden a las tres
preguntas que se hacen al abrir una señal: **identidad** (clave, mensaje, entregas, tipo),
**resultado** (resultado, motivo, detalle, reintentable, incidente) y **momentos** (las
cuatro fechas). La carga original va en su propia sección al final, porque es larga y
ocupa toda la pantalla.

El acceso está restringido al administrador, según el
[módulo 10](10-seguridad-y-accesos.md). El operador no ve la bitácora.

## Qué no se guarda

Es tan importante como qué sí.

**No se guardan credenciales ni secretos.** Lo que se almacena en `Carga__c` es el cuerpo
del mensaje, no la petición completa: las cabeceras, y con ellas el token, nunca llegan a
la base de datos. Tampoco aparecen en registros de depuración, porque la Named Credential
inyecta la cabecera fuera del alcance de Apex.

**No se guardan datos personales.** Los mensajes del simulador contienen edificios,
activos, sensores y magnitudes físicas. No hay nombres de residentes, ni direcciones, ni
nada que identifique a una persona. Si el contrato cambiara y empezaran a llegar, habría
que revisar esta decisión antes de guardarlos.

**No se guarda el cursor en la bitácora.** Está en `Control_de_Ingesta__c`, que solo ve el
administrador.

Todo esto responde el criterio de US-209 sobre no almacenar contraseñas, tokens ni datos
innecesarios.

## El crecimiento

`Senal__c` es la única tabla sin techo: una fila por mensaje recibido, para siempre. Con
los latidos de conectividad del [módulo 08](08-conectividad.md), el ritmo es aún mayor.

Las tres consecuencias de diseño que ya están tomadas:

- **La pantalla del operador no la consulta nunca.** Consulta `Estado_Actual__c`, cuyo
  tamaño depende del número de equipos y no del tiempo.
- **No hay resúmenes automáticos sobre la bitácora.** Los únicos están en el activo, cuyos
  hijos son pocos. El resumen de la limpieza lo escribe el Batch, no la plataforma.
- **Los campos por los que se filtra están indexados**: `Clave__c` y `Message_Id__c` por ser
  External ID, `CreatedDate` de fábrica y `Resultado_Indice__c`, una copia del resultado.
  `Resultado__c` es una lista de selección y Salesforce no la indexa; pedir un índice a
  medida exige un caso con Soporte. Por eso las vistas filtran por la copia, un campo de
  texto External ID que la plataforma indexa sola. La escribe `IngestaConstantes.aplicar`,
  el único lugar que pone resultados, y el flujo `Copiar_Resultado_Indice` la corrige si el
  administrador cambia un resultado a mano.

| Vista | Antes | Con el índice |
| --- | --- | --- |
| Atascadas | 15.254 ms, recorre la tabla entera porque casi nunca hay | 34 ms |
| Conflictos | 1.517 ms | 389 ms |
| Rechazadas hoy | 1.505 ms | 365 ms, con `CreatedDate = TODAY` |
| Duplicadas | 1,8 s | Igual: filtra por entregas, que no tiene índice, y solo se usa para investigar |

Medido en el servidor el 24 de octubre de 2026 con 2,5 millones de señales. Las señales que
ya existían se rellenaron una vez con `SenalIndiceRellenoBatch` (unas 96.000, en 4 minutos);
las aplicadas y atrasadas no lo necesitan, porque ninguna vista las busca.

### La limpieza nocturna (Q-11)

Con unas 347.500 señales por día, la bitácora llenaba el almacenamiento de la org en meses.
**Decisión: una limpieza cada noche, a las 2 a. m., que borra lo que ya no se consulta y
deja contado lo que borró.**

| Señales | Se borran a los | Por qué |
| --- | --- | --- |
| Aplicadas y atrasadas | 7 días | Su efecto ya está en el estado actual y en el incidente; «Lecturas del periodo» cubre la última semana |
| Rechazadas, fallidas y en conflicto | 90 días | Son las que se investigan |
| Ligadas a cualquier incidente, abierto o cerrado | Nunca | Son la evidencia de por qué se abrió, escaló o normalizó |
| Pendientes | Nunca | Una pendiente vieja está atascada, y eso se investiga |

`BitacoraRetencionBatch` lo hace **en una sola pasada**, en lotes de 2.000. Cada lote borra
sus señales, suma lo que borró a `Resumen_Bitacora__c` (una fila por día, equipo, resultado
y motivo, con una clave única) y vacía su papelera, para que el espacio se libere esa misma
noche. El día del resumen es el de recepción en hora de Bogotá. Un lote vuelve a mirar cada
señal antes de borrarla, por si se ligó a un caso después de la consulta inicial.

Si la ingesta tiene una caída avisada o hay más de 2.000 señales pendientes de los últimos
15 minutos, el lote no borra y la limpieza termina: sigue la noche siguiente. Se cuentan
solo las de 15 minutos porque contarlas en el último día recorría unas 347.000 señales y
tardaba 11 segundos por lote; así tarda 60 ms, y un atraso real del procesamiento siempre
deja pendientes recientes.

| Alternativa | Por qué no |
| --- | --- |
| Primero resumir todo y después borrar, en dos trabajos | Dos recorridos de millones de filas, y si el segundo falla queda un resumen de algo que no se borró |
| Archivar en un objeto grande o fuera de Salesforce | Más almacenamiento o una integración nueva para algo que se consulta poco; el resumen guarda el conteo |
| Borrar sin vaciar la papelera | El espacio no se libera hasta 15 días después |

`./scripts/programar-limpieza.sh novacasa2` la programa, `--abortar` la quita y `--ahora` la
corre una vez. `./scripts/ver-limpieza.sh novacasa2` muestra su avance cada 20 segundos.

La primera corrida, el 24 de octubre de 2026 con la ingesta funcionando, hizo 227 lotes en
unos 41 minutos y sin errores: borró 452.402 señales (364.886 atrasadas y 87.516 aplicadas),
que quedaron contadas en 113 filas del resumen. La bitácora quedó en 2.508.222 señales, y la
ingesta siguió consultando cada minuto mientras tanto.

La primera noche programada, el 25 de octubre, corrió de 2:00:36 a 2:25:50 a. m., en 77 lotes
y sin errores. Borró 153.876 señales, 121.690 atrasadas y 32.186 aplicadas: lo que quedaba
del 17 de octubre después de la corrida a mano y el comienzo del 18. No le quitó nada a la
operación. La ingesta trajo unas 6.200 señales cada 26 minutos antes, durante y después de
la limpieza, y la latencia del procesamiento fue la misma en las tres ventanas: 1 s de
mediana y 3 s en el percentil 95.
