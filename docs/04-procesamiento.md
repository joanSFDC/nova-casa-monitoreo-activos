# 04 · Procesamiento

Cubre **US-202 · Procesar señales en lote sin perder las válidas**.

Este módulo es la zona de Procesamiento: toma los avisos del bus, decide qué son y aplica
las reglas. Es donde puede fallar cualquier cosa, y por eso está separado de la ingesta.

## El concepto de base: por qué el código en lote es distinto

Salesforce ejecuta sobre infraestructura compartida y protege a los vecinos con límites
por transacción. Los que condicionan este módulo son tres: cien consultas a la base de
datos, ciento cincuenta operaciones de escritura y cincuenta mil registros recuperados.

La consecuencia es la regla de oro de la plataforma: **nunca se consulta ni se escribe
dentro de un bucle.** Un código que hace una consulta por cada mensaje funciona
perfectamente con cinco mensajes y estalla con doscientos. Y estalla del peor modo
posible, porque el error no se parece a la causa: no dice «tu bucle tiene una consulta
dentro», dice que se superó un límite.

El patrón que lo resuelve tiene tres tiempos y conviene nombrarlos porque estructuran todo
el código de esta zona:

1. **Recolectar.** Recorrer la tanda entera acumulando en conjuntos las claves que van a
   hacer falta: códigos de activo, tipos de medición, claves de señal.
2. **Consultar una vez.** Traer todo lo necesario en un puñado de consultas y dejarlo en
   mapas indexados por clave.
3. **Resolver en memoria y escribir una vez.** Recorrer la tanda otra vez, ahora sin tocar
   la base de datos, y acumular los registros a escribir en listas que se guardan al final
   con una sola operación por objeto.

El número de consultas y de escrituras queda así **constante**: no depende de cuántos
mensajes traiga la tanda. Es la propiedad que pide el criterio de US-202.

## El segundo concepto: el aislamiento de fallos

Por defecto, una operación de escritura sobre una lista es de todo o nada. Si un solo
registro falla, se revierte la lista completa. Con doscientos mensajes en los que uno
tiene un valor nulo, eso significa perder los ciento noventa y nueve buenos por culpa de
uno malo.

Salesforce ofrece una variante de éxito parcial: `Database.insert(lista, false)`. Los
registros válidos se guardan, los inválidos no, y se devuelve un arreglo de resultados en
el **mismo orden que la lista de entrada**, donde cada uno dice si tuvo éxito y, si no,
por qué.

Ese «mismo orden» es lo que permite conectar cada fallo con el mensaje que lo causó. Es un
detalle de implementación, pero es el que hace posible escribir un motivo concreto en la
bitácora en lugar de un «falló algo».

**Decisión: todas las escrituras de la zona de procesamiento usan éxito parcial y todas
revisan sus resultados uno a uno.** Un resultado no revisado es un fallo silencioso, que
es peor que un error.

## El suscriptor

### Cómo entrega los eventos la plataforma

Un disparador sobre un evento de plataforma se ejecuta de forma asíncrona, en un usuario
del sistema, y recibe en `Trigger.new` un lote de eventos. El tamaño de ese lote lo decide
la plataforma: por defecto hasta dos mil, y se puede reducir.

Aquí hay una trampa en la que es fácil caer al escribir la prueba de volumen. **La
plataforma no garantiza entregar exactamente doscientos eventos en una invocación.** Puede
entregar doscientos, o dos tandas de cien, o cualquier otro reparto. Una prueba que
afirme «al publicar doscientos eventos, el disparador se ejecuta una vez con doscientos»
es una prueba frágil que va a fallar por motivos que no tienen que ver con nuestro código.

La prueba correcta afirma sobre el **resultado**: publicados doscientos mensajes, existen
doscientas señales con resultado final y ninguna quedó pendiente. Eso es lo que significa
«resultados verificables» en el criterio de US-202.

### El punto de reanudación

Cuando un disparador de evento de plataforma lanza una excepción no controlada, la
plataforma reintenta el lote completo desde el principio, hasta un número limitado de
veces. Si el fallo es determinista, el lote se reintenta y vuelve a fallar, y así hasta
agotar los intentos: los eventos se pierden.

`EventBus.TriggerContext.currentContext().setResumeCheckpoint(replayId)` permite marcar
hasta dónde se procesó bien, de modo que un reintento empiece desde ahí en lugar de desde
el principio.

**Decisión: se establece el punto de reanudación después de cada bloque procesado con
éxito, y las excepciones esperadas se capturan y se convierten en un resultado escrito en
la bitácora en lugar de propagarse.** Solo se deja escapar lo verdaderamente inesperado, y
en ese caso el punto de reanudación limita el daño.

El criterio para decidir qué se captura es sencillo: si el fallo es atribuible a un
mensaje concreto, se captura y se registra contra ese mensaje. Si el fallo es del entorno
—un límite de la plataforma, un tiempo excedido—, se deja propagar, porque reintentar
tiene sentido.

## El recorrido de una tanda

Paso a paso, con el número de operaciones entre paréntesis.

### 1 · Enrutar por tipo

Se recorre `Trigger.new` una vez y se separan los avisos en dos listas según
`Tipo_Mensaje__c`: mediciones por un lado, conectividad por otro. No se toca la base de
datos.

Los tipos desconocidos se apartan a una tercera lista y se resolverán como rechazo con
motivo «tipo de mensaje desconocido». No se descartan en silencio: un tipo nuevo en el
proveedor tiene que ser visible, no invisible.

### 2 · Recolectar las claves

Del recorrido anterior salen cuatro conjuntos: claves de señal, códigos de activo, claves
de estado actual (`activo|medición`) y claves de incidente abierto.

### 3 · Consultar (cuatro consultas, siempre cuatro)

| Consulta | Qué trae | Indexada por |
| --- | --- | --- |
| Señales | Las señales de esta tanda | `Clave__c` |
| Activos | Los activos implicados, con su tipo y su edificio | `Codigo_Externo__c` |
| Estados | Los estados actuales implicados | `Clave__c` |
| Umbrales | **Todos** los umbrales vigentes | `Clave__c` |

Los umbrales se traen enteros y no filtrados. Son pocos —uno por combinación de tipo de
activo y medición— y no crecen con el volumen, así que filtrar solo añadiría complejidad
sin ahorrar nada. Los incidentes abiertos se consultan aparte, dentro del módulo de
incidentes, porque su lógica de bloqueo es distinta.

### 4 · Resolver en memoria

Por cada aviso, y sin tocar la base de datos:

1. Se busca el activo en el mapa. Si no está, se marca la señal como rechazada.
2. Se busca el umbral por `tipoActivo|tipoMedicion`. Si no está, rechazo reintentable con
   motivo «sin límite configurado».
3. Se compara la unidad del mensaje con la del umbral. Si no coinciden, rechazo.
4. Se busca el estado actual y se compara la vigencia, según el
   [módulo 06](06-estado-actual.md). Si el mensaje está atrasado, se marca como tal y no
   se propone ningún cambio de estado.
5. Se clasifica la severidad, según el [módulo 05](05-clasificacion-y-limites.md).
6. Se acumula el estado actual a escribir y, si procede, la decisión sobre el incidente.

Al final de este paso hay tres listas en memoria: estados a guardar, decisiones de
incidente, y señales a actualizar con su resultado.

### 5 · Escribir (tres operaciones, siempre tres)

```apex
Database.UpsertResult[] resEstados =
    Database.upsert(estados, Estado_Actual__c.Clave__c, false);
// ... gestión de incidentes, ver módulo 07 ...
Database.SaveResult[] resSenales = Database.update(senales, false);
```

El orden importa y no es casual: **primero el estado, después el incidente, y la señal al
final**. El módulo de incidentes explica por qué.

### 6 · Reconciliar los resultados

Se recorren los arreglos de resultados en paralelo con las listas de entrada. Un registro
que falló hace que su señal pase a resultado **fallido**, con el motivo tomado del error
de la plataforma. Ninguna señal queda con su resultado sin escribir.

## Qué pasa cuando falla la creación del incidente

Es un criterio literal de US-205: una falla de creación no puede dejar una señal marcada
como procesada satisfactoriamente sin su resultado obligatorio.

### Las alternativas

Un `Savepoint` con reversión completa: si falla el caso, tampoco se guarda el estado
actual. Es la opción atómica y la más fácil de razonar. Su problema es operativo: el
operador dejaría de ver una lectura crítica que sí llegó, y la pantalla mostraría el valor
anterior como si nada hubiera pasado. El sistema ocultaría el problema justo cuando es más
grave.

Dejar la señal como pendiente y que un reintento posterior cree el caso que faltó: es
correcto, pero exige un mecanismo de reintento que hoy no existe y que nadie pidió.

### La decisión

**El estado actual se conserva actualizado y la señal queda con resultado «fallido» y su
motivo.** No se usa `Savepoint`.

El razonamiento es que las dos escrituras responden preguntas distintas. El estado actual
responde «¿cómo está este equipo?», y la respuesta correcta es el valor que acaba de
llegar, con independencia de que hayamos sabido abrir un caso. El caso responde «¿hay
trabajo asignado?», y si no se pudo crear, la respuesta honesta es que no lo hay.

Una señal fallida es visible en la bitácora, tiene motivo escrito y el administrador puede
actuar. Una señal revertida no deja nada, y el operador vería un valor viejo sin saber por
qué.

Queda registrado que esta decisión hace que estado e incidente puedan quedar
momentáneamente desalineados. Es deliberado y la bitácora lo documenta en cada caso.

## El riesgo de contención sobre el activo

Hay un efecto de la relación principal-detalle que solo aparece con volumen y que conviene
anticipar.

Cada vez que se escribe un `Estado_Actual__c`, la plataforma recalcula el resumen del
`Activo__c` padre. Ese recálculo **bloquea la fila del padre** durante la transacción. Si
doscientas escrituras de una tanda afectan a activos repetidos —y lo van a hacer, porque
son diez activos— los bloqueos se acumulan.

Con diez activos el riesgo es bajo. Con diez mil sería el cuello de botella principal del
sistema.

**Decisión: los estados de una misma tanda se ordenan por identificador de activo antes de
escribirlos.** Ordenar no elimina la contención, pero garantiza que todas las
transacciones adquieran los bloqueos en el mismo orden, que es la condición que evita los
interbloqueos. Es una línea de código y quita una clase entera de fallos intermitentes.

La medición está en el plan de pruebas: el escenario `QA_200` con doscientos mensajes es
exactamente la prueba de volumen del riesgo R-05.

## Lo que este módulo no hace

No consulta al proveedor: eso es ingesta. No decide si un valor es crítico: eso es
clasificación. No decide si abrir un caso: eso es incidentes. Este módulo orquesta, y su
responsabilidad es que una tanda de doscientos mensajes con cinco malos produzca ciento
noventa y cinco resultados aplicados y cinco resultados con motivo, en un número constante
de consultas y escrituras.
