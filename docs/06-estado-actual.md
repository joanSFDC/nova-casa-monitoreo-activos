# 06 · Estado actual

Cubre **US-203 · Mantener el estado actual por activo y medición** y la parte de resumen
de **US-206**.

## El concepto de base: vigencia contra llegada

Un sistema que recibe hechos de otro tiene que distinguir dos ordenaciones que la
intuición confunde: el orden en que las cosas **pasaron** y el orden en que **llegaron**.

En una red fiable con un solo emisor coinciden. En cuanto hay reintentos, colas, varios
caminos o cualquier asincronía, dejan de coincidir. Y cuando dejan de coincidir, un
sistema que ordena por llegada escribe estados que retroceden en el tiempo: el operador ve
un valor de hace media hora presentado como si fuera el actual.

La solución estándar es rechazar las escrituras obsoletas comparando contra una marca de
vigencia guardada. Se conoce como escritura condicional o «el último escritor por tiempo
de evento gana». La propiedad que da es fuerte y conviene enunciarla: **el estado final no
depende del orden de llegada**, solo del contenido de los mensajes. Se pueden reordenar,
repetir o reenviar y el resultado es el mismo.

## Que el problema es real

El escenario `LATE_MESSAGES` lo demuestra con datos. Una página completa, en orden de
llegada:

| Entrega | Activo | Valor | `occurredAt` | `publishedAt` |
| --- | --- | --- | --- | --- |
| `dlv_000003` | `AST-BOG-PUMP-001` | 4.66 | 22:50:18 | 22:50:21 |
| `dlv_000004` | `AST-BOG-PUMP-001` | 3.73 | 22:51:19 | 22:51:21 |
| `dlv_000005` | `AST-BOG-PUMP-001` | 3.54 | **22:42:20** | 22:52:20 |

La quinta entrega llega en último lugar pero describe la bomba nueve minutos antes que la
cuarta. Sin protección, el estado de esa bomba terminaría en 3.54, que es un valor real
pero viejo.

Y no es un caso aislado: en esa misma página, seis de los ocho mensajes tenían un retraso
de entre seis y veinte minutos entre el hecho y su publicación.

## La regla de vigencia

**Decisión: un mensaje reemplaza el estado actual si y solo si su `occurredAt` es
estrictamente posterior al `Fecha_Origen__c` guardado.**

La comparación es contra el estado guardado, no contra la hora del sistema ni contra
`publishedAt`. Solo `occurredAt` participa. La justificación completa de por qué las otras
fechas no sirven está en el [módulo 01](01-contrato-del-mensaje.md).

Un estado que todavía no existe se trata como si tuviera fecha infinitamente antigua: el
primer mensaje siempre lo crea.

### El empate

Dos mensajes con exactamente el mismo `occurredAt` para el mismo activo y la misma
medición no se pueden ordenar por tiempo. Hay que romper el empate con algo, y ese algo
tiene que ser determinista: la misma pareja de mensajes tiene que producir siempre el
mismo ganador, procesados en el orden que sea.

**Decisión: con `occurredAt` idéntico, gana el `messageId` mayor en orden lexicográfico.**

Es una regla arbitraria y se admite que lo es. Lo que no es arbitrario es la propiedad que
cumple: es total —cualquier par se puede comparar—, es determinista y no depende del orden
de procesamiento. Con la numeración del simulador, `msg_000015` gana a `msg_000009`, que
es además lo intuitivo.

`Ultimo_Message_Id__c` en `Estado_Actual__c` existe para esto: guarda el identificador del
mensaje que escribió el estado vigente, de modo que el desempate se pueda resolver sin
consultar la bitácora.

La regla está documentada porque el criterio de US-203 pide una regla documentada para
empates, no una regla cualquiera.

## Qué pasa con un mensaje atrasado

No se descarta. Se guarda en la bitácora con resultado **atrasado**, con su valor, su
fecha de origen y su carga completa, y **no reemplaza el estado ni abre incidente**.

La distinción entre «descartar» y «no aplicar» es la diferencia entre poder responder qué
pasó con un mensaje y no poder. Un mensaje atrasado es evidencia: dice que el proveedor
tuvo un retraso, y esa información sirve para diagnosticar la integración aunque no sirva
para pintar la pantalla.

### El caso incómodo: un crítico que llega tarde

Esta es la situación que el criterio de US-203 llama «la política acordada de acción sobre
señales críticas atrasadas», y merece pensarse despacio porque las dos respuestas son
defendibles.

Llega una lectura de presión 0.8 BAR, que es crítica, pero con `occurredAt` de hace veinte
minutos. El estado actual ya tiene una lectura de hace dos minutos con 3.1 BAR, que es
normal.

Abrir un incidente sería alarmar por un problema que, según la evidencia más reciente, ya
no existe. El operador iría a mirar una bomba que está bien.

No abrirlo deja sin registrar que hubo un episodio crítico. Pero no del todo: **la señal
queda en la bitácora con su valor y su resultado atrasado**, así que la evidencia existe y
es consultable.

**Decisión: una señal crítica atrasada se registra como atrasada y no abre incidente ni
modifica el estado.** El principio es que el incidente representa una situación **vigente**
que requiere acción ahora, y una lectura superada por otra posterior no describe una
situación vigente.

Nótese que esto no contradice el principio de «ante la duda, no subestimar la gravedad»
del [módulo 05](05-clasificacion-y-limites.md), porque aquí no hay duda: hay una lectura
posterior que dice que la bomba está bien.

## La escritura

Se hace con `upsert` por `Estado_Actual__c.Clave__c`, que es External ID y Unique.

```apex
Database.UpsertResult[] resultados =
    Database.upsert(estados, Estado_Actual__c.Clave__c, false);
```

Dos propiedades de esta forma de escribir merecen nombrarse.

**No hace falta consultar antes para saber si insertar o actualizar.** La plataforma lo
resuelve por la clave. Eso ahorra una consulta y, más importante, elimina la ventana entre
consultar y escribir en la que otra transacción podría haber insertado la fila.

**La unicidad la impone la base de datos.** Si dos transacciones concurrentes intentan
crear el estado de la misma combinación, una gana y la otra recibe un error de valor
duplicado. No hace falta ningún bloqueo explícito ni ninguna comprobación en código.

El `allOrNone` en falso hace que un estado que falle no arrastre a los demás, según el
[módulo 04](04-procesamiento.md).

### Varios mensajes del mismo estado en una tanda

Una tanda puede traer tres lecturas de la misma bomba. Enviarlas las tres al `upsert`
fallaría: **una operación con claves repetidas en la misma llamada falla entera**, y se
llevaría por delante los estados buenos.

**Decisión: la reducción se hace en memoria antes de escribir.** Se recorre la tanda
manteniendo un mapa por clave y quedándose siempre con el mensaje más reciente según la
regla de vigencia, incluido el desempate. A la base de datos llega un solo registro por
clave, que es el ganador.

Las lecturas perdedoras no desaparecen: se registran en la bitácora como atrasadas, igual
que si hubieran llegado en otra tanda. El resultado es el mismo que si se hubieran
procesado de una en una, que es la propiedad que queríamos.

## El resumen por activo

US-206 pide que el activo muestre su peor estado. El mecanismo es el resumen automático
descrito en el [módulo 03](03-modelo-de-datos.md): `MAX` sobre `Severidad_Nivel__c` de los
estados hijos, con la traducción a texto en una fórmula.

**La política de múltiples mediciones es «la peor gana».** Un activo con la temperatura
normal y la presión crítica se muestra crítico.

La alternativa —mostrar la más reciente, o alguna combinación— se descartó porque
escondería el problema. Si una bomba tiene la presión crítica y treinta segundos después
llega una temperatura normal, mostrarla como normal sería exactamente el fallo que este
sistema existe para evitar.

Lo que la plataforma da gratis con esta elección merece decirse: el recálculo es
automático, es transaccional, no cuesta una línea de código y no se puede olvidar en una
rama del procesamiento. Un resumen escrito a mano en un disparador sí se puede olvidar.

## La antigüedad de la lectura

Hay un modo de fallo que el resumen no cubre y que es el riesgo R-03: un equipo deja de
reportar, su última lectura era normal, y la pantalla lo muestra sano indefinidamente.
Nadie se entera de que ese equipo lleva seis horas mudo.

La defensa tiene dos partes.

La primera es que la cámara emite mensajes de conectividad que **sí** detectan el silencio,
según el [módulo 08](08-conectividad.md). Pero solo la cámara: el resto de activos no tiene
ese tipo de mensaje.

La segunda, que cubre a todos, es presentar la antigüedad. `Fecha_Origen__c` está en cada
estado, y el componente del operador muestra una columna con cuánto hace que llegó esa
lectura, con un tratamiento visual distinto cuando pasa de un umbral.

**Decisión: la antigüedad se calcula y se presenta en la capa de presentación, no se guarda
como dato.** Guardarla obligaría a un proceso que recorriera los estados actualizando el
contador, que es exactamente el proceso periódico que todo el diseño evita. Calculada al
mostrar, cuesta cero y siempre está al día.

## Lo que este módulo garantiza

Puestos juntos, los mecanismos anteriores dan una propiedad que conviene enunciar entera,
porque es lo que hace demostrable la historia US-203:

**Dado un conjunto de mensajes, el estado actual resultante es el mismo con independencia
del orden en que se procesen, de cuántas veces se repita cada uno y de si llegan juntos o
separados.**

Las tres piezas que la sostienen son la clave única del mensaje, que impide el doble
procesamiento; la comparación por `occurredAt` con desempate determinista, que impide el
retroceso; y el `upsert` por clave única, que impide las filas duplicadas. Ninguna de las
tres depende de que el código recuerde hacer una comprobación.
