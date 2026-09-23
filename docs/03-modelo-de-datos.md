# 03 · Modelo de datos

Cubre **US-201**, **US-203** y **US-209** en su parte de persistencia.

El diagrama de este modelo, con cada campo y su tipo, esta en
[`data-model/`](data-model/README.md). Este documento explica **por que** es asi.

Ocho conceptos. Cuatro objetos personalizados de negocio, uno de configuración, uno de
control, dos objetos estándar de Salesforce y un evento que no se guarda en ninguna tabla.

## El concepto de base: por qué la elección de relación no es cosmética

Salesforce ofrece dos formas de relacionar objetos y la diferencia condiciona el diseño
entero.

Una **relación de búsqueda** (`Lookup`) es un puntero suelto. El hijo puede existir sin
padre, borrar el padre no borra al hijo, y los permisos de ambos son independientes.

Una **relación principal-detalle** (`Master-Detail`) es una relación de propiedad. El hijo
no puede existir sin padre, borrar el padre borra a los hijos, y —esto es lo importante—
el hijo **no tiene permisos propios: hereda los del padre**. Además, y solo en este caso,
el padre puede llevar campos de **resumen automático** (`Roll-Up Summary`) que la
plataforma recalcula sola, sin una línea de código.

Esas dos propiedades, herencia de permisos y resumen automático, son exactamente lo que
necesitamos, y son la razón por la que edificio y activo son objetos personalizados en
lugar del objeto estándar de activos: **un objeto estándar no puede ocupar el lado hijo de
una relación principal-detalle con un objeto personalizado.** Usar el estándar costaría
precisamente las dos cosas que queremos.

## El mapa

```
Edificio__c
    └── Activo__c                    (principal-detalle)
            └── Estado_Actual__c     (principal-detalle)

Umbral__c                            (configuración, sin relación)
Senal__c                             (bitácora, búsquedas a edificio y activo)
Control_de_Ingesta__c                (control, registro único)
Aviso_de_Senal__e                    (evento, no se guarda)

Case      ── Incidente               (estándar)
Task      ── Intervención            (estándar, en la actividad del caso)
```

## `Edificio__c`

Dónde está el equipo, y la unidad con la que se decide quién ve qué.

| Campo | Tipo | Notas |
| --- | --- | --- |
| `Name` | Text | El nombre visible, p. ej. «Edificio Nova Alameda» |
| `Codigo_Externo__c` | Text(30), External ID, Unique | `BLD-BOG-001` |
| `Ciudad__c` | Text(60) | «Bogotá», «Barranquilla» |
| `Region__c` | Picklist | Para el agrupado de gerencia |

El **External ID** merece una explicación. Es un campo marcado para que Salesforce lo
indexe y acepte que se use como clave en operaciones de `upsert`. Eso permite escribir
`Database.upsert(registros, Edificio__c.Codigo_Externo__c)` y que la plataforma decida
sola si inserta o actualiza, sin consultar primero. Es la pieza que hace que la siembra
del catálogo sea repetible: ejecutarla dos veces no duplica nada.

`Codigo_Externo__c` es además **Unique**, que es una cosa distinta de External ID aunque
se marquen juntas. External ID habilita el `upsert`; Unique impone la restricción en base
de datos. Se quieren las dos.

## `Activo__c`

El equipo en sí.

| Campo | Tipo | Notas |
| --- | --- | --- |
| `Name` | Text | «Bomba de presión de agua» |
| `Codigo_Externo__c` | Text(30), External ID, Unique | `AST-BOG-PUMP-001` |
| `Edificio__c` | Master-Detail(Edificio__c) | Herencia de permisos y resumen |
| `Tipo__c` | Picklist global | Ver más abajo |
| `Sensor_Id__c` | Text(40) | Informativo |
| `Severidad_Nivel__c` | Roll-Up Summary (MAX) | Sobre `Estado_Actual__c.Severidad_Nivel__c` |
| `Severidad__c` | Formula (Text) | Traduce el número a texto |
| `Sin_Comunicacion__c` | Roll-Up Summary (MAX) | Sobre `Estado_Actual__c.Sin_Comunicacion_Num__c` |

Los valores de `Tipo__c` salen del catálogo real: `TECHNICAL_ROOM`, `WATER_METER`,
`ENERGY_METER`, `WATER_PUMP`, `SECURITY_CAMERA`.

### El detalle que obliga a un campo numérico

Aquí hay una restricción de la plataforma que cambia el diseño y conviene entender antes
de tropezar con ella. **Un resumen automático solo opera sobre campos numéricos, de moneda
o de fecha.** No existe un resumen de tipo «el máximo de esta lista desplegable», porque
una lista desplegable no tiene orden definido para la plataforma.

Nosotros sí necesitamos ese máximo: el activo debe mostrar la peor severidad de todas sus
mediciones. La salida es representar la severidad dos veces.

`Estado_Actual__c.Severidad_Nivel__c` es un número que el código escribe: **0 normal,
1 advertencia, 2 crítico**. Sobre él se define el resumen `MAX` en el activo. Y encima del
resumen se pone una fórmula que lo traduce a algo legible:

```
CASE(Severidad_Nivel__c, 2, "Crítico", 1, "Advertencia", 0, "Normal", "Sin datos")
```

La fórmula no ocupa espacio en base de datos y se calcula al leer, así que el coste es
cero. El orden 0 < 1 < 2 no es arbitrario: es lo que hace que `MAX` signifique «lo peor».

El mismo truco se usa para la comunicación: `Sin_Comunicacion_Num__c` vale 1 cuando el
estado es `LOST` y 0 en cualquier otro caso, y su `MAX` en el activo responde «¿alguna de
mis mediciones está muda?».

## `Estado_Actual__c`

La foto de ahora. Es la única tabla que consulta la pantalla del operador.

| Campo | Tipo | Notas |
| --- | --- | --- |
| `Activo__c` | Master-Detail(Activo__c) | |
| `Tipo_Medicion__c` | Picklist global | |
| `Clave__c` | Text(80), External ID, Unique | `AST-BOG-PUMP-001\|WATER_PRESSURE` |
| `Valor__c` | Number(12,4) | |
| `Unidad__c` | Picklist global | |
| `Severidad__c` | Picklist | Normal, Advertencia, Crítico, Sin datos |
| `Severidad_Nivel__c` | Number(1,0) | 0, 1, 2. Alimenta el resumen del activo |
| `Fecha_Origen__c` | Datetime | El `occurredAt` de la lectura vigente |
| `Fecha_Actualizacion__c` | Datetime | Cuándo lo escribimos nosotros |
| `Ultimo_Message_Id__c` | Text(60) | Desempate y trazabilidad |
| `Estado_Comunicacion__c` | Picklist | `HEALTHY`, `LOST`, `RESTORED` |
| `Sin_Comunicacion_Num__c` | Number(1,0) | 1 si `LOST`, 0 si no |
| `Gap_Segundos__c` | Number(10,0) | El `gapSeconds` del último aviso |
| `Ultima_Vez_Visto__c` | Datetime | El `lastSeenAt` del último aviso |
| `Episodio_Id__c` | Text(60) | El episodio de corte en curso |

### Por qué una fila por activo **y** medición

Es la decisión de granularidad del modelo y tiene una consecuencia práctica inmediata: la
presión de una bomba y su temperatura son dos filas distintas.

Si hubiera una sola fila por activo, una lectura de temperatura sobrescribiría la última
de presión y el operador vería un estado que no corresponde a nada. Con una fila por
combinación, cada medición conserva su propia vigencia, su propia severidad y su propia
antigüedad.

`Clave__c` materializa esa granularidad como `codigoActivo|tipoMedicion` y es Unique. Eso
permite hacer `upsert` por esa clave sin consultar primero y garantiza en base de datos
que no puedan existir dos filas para la misma combinación, ni siquiera si dos
transacciones concurrentes intentan crearla a la vez.

### Por qué la severidad se guarda en lugar de calcularse al mostrar

La alternativa era una fórmula que comparara el valor contra el límite en el momento de
leer. Tiene una ventaja real: cambiar un límite reclasificaría todo al instante.

Se descartó por dos razones. Una fórmula no puede recorrer registros de otro objeto para
encontrar el límite que aplica, así que habría que desnormalizar los umbrales en cada
fila, que es peor. Y un campo de fórmula no se puede indexar ni usar eficientemente para
ordenar y filtrar, que es exactamente lo que hace la pantalla del operador cuando muestra
primero lo crítico.

El precio está asumido y documentado: **lo ya guardado no se reclasifica solo.** Entre que
alguien cambia un límite y que llega una lectura nueva, la pantalla muestra la
clasificación anterior. Para acotarlo existe la acción «aplicar límites» que describe el
[módulo 05](05-clasificacion-y-limites.md).

Esto es además lo que pide el criterio de US-204 sobre no tener que reclasificar todo el
historial al cambiar un límite: el historial en la bitácora no se toca nunca, y lo único
que se reclasifica es la foto actual, que tiene una fila por activo y medición.

## `Umbral__c`

Los valores que separan lo normal de la advertencia y de lo crítico. Es configuración que
el negocio edita, no código.

| Campo | Tipo | Notas |
| --- | --- | --- |
| `Tipo_Activo__c` | Picklist global | |
| `Tipo_Medicion__c` | Picklist global | |
| `Clave__c` | Text(80), External ID, Unique | `WATER_PUMP\|WATER_PRESSURE` |
| `Unidad__c` | Picklist global | La unidad en la que se expresan los valores |
| `Critico_Bajo__c` | Number(12,4) | Por debajo de aquí, crítico |
| `Advertencia_Bajo__c` | Number(12,4) | Por debajo de aquí, advertencia |
| `Advertencia_Alto__c` | Number(12,4) | Por encima de aquí, advertencia |
| `Critico_Alto__c` | Number(12,4) | Por encima de aquí, crítico |
| `Minutos_Advertencia__c` | Number(5,0) | Silencio tolerado antes de advertir |
| `Minutos_Critico__c` | Number(5,0) | Silencio tolerado antes de alarmar |
| `Vigente__c` | Checkbox | Permite desactivar sin borrar |
| `Decimales__c` | Number(1,0) | Precisión de presentación |

Los cuatro valores permiten bandas bidireccionales, que es lo que hacen falta: la
temperatura y la presión tienen problema por exceso y por defecto, mientras que los
consumos solo por exceso. En esos casos los dos campos bajos quedan vacíos, y un campo
vacío significa «sin frontera por ese lado». El detalle de cómo se clasifica está en el
[módulo 05](05-clasificacion-y-limites.md).

### Por qué un objeto y no un tipo de metadato personalizado

Esta es la decisión más discutible del modelo y merece las dos caras.

Un **Custom Metadata Type** es la forma natural en Salesforce para valores de
configuración. Viaja entre entornos como metadato, no consume consultas al leerse y está
cacheado. Es, técnicamente, la respuesta correcta para una tabla de umbrales.

Y aun así no sirve, por un requisito literal: **la persona autorizada debe poder cambiar
los límites sin modificar ni volver a desplegar código.** Esa persona es el coordinador de
mantenimiento. Los metadatos personalizados solo se editan desde la configuración del
sistema, y dar acceso a la configuración del sistema a un coordinador de mantenimiento es
exactamente lo que no queremos hacer.

Un objeto personalizado se edita desde una pestaña de la aplicación, con permisos de campo
granulares, historial de cambios y reglas de validación. Lo que se paga está contado:
consume consultas cuando se lee, no viaja entre entornos como configuración —hay que
migrar los datos— y obliga a definir explícitamente quién puede editarlo, que es
justamente la matriz del [módulo 10](10-seguridad-y-accesos.md).

El coste de las consultas se mitiga leyendo **todos** los umbrales de una vez al inicio de
cada transacción de procesamiento y cacheándolos en un mapa por clave. Son unos pocos
registros y no crecen con el volumen: una consulta por transacción, independientemente de
cuántos mensajes traiga la tanda.

## `Senal__c`

La bitácora. Cada mensaje recibido queda aquí con su resultado.

| Campo | Tipo | Notas |
| --- | --- | --- |
| `Clave__c` | Text(120), External ID, Unique | `nova-casa-simulator\|msg_000002` |
| `Message_Id__c` | Text(60) | El identificador desnudo |
| `Ultimo_Delivery_Id__c` | Text(60) | El último intento de entrega visto |
| `Entregas__c` | Number(6,0) | Cuántas veces nos llegó. Empieza en 1 |
| `Tipo_Mensaje__c` | Picklist | `MEASUREMENT`, `CONNECTIVITY` |
| `Resultado__c` | Picklist | Ver el [módulo 11](11-trazabilidad.md) |
| `Motivo__c` | Picklist | El motivo cuando se rechaza o falla |
| `Detalle__c` | Text(255) | Texto libre complementario |
| `Reintentable__c` | Checkbox | Lo escribe el código según el motivo |
| `Hash_Contenido__c` | Text(64) | SHA-256 en base 64 |
| `Carga__c` | Long Text Area (32768) | El JSON original del mensaje |
| `Fecha_Origen__c` | Datetime | `occurredAt` |
| `Fecha_Publicacion__c` | Datetime | `publishedAt` del primer intento |
| `Ultima_Fecha_Publicacion__c` | Datetime | `publishedAt` del último intento |
| `Fecha_Recepcion__c` | Datetime | Cuándo la insertamos |
| `Fecha_Procesamiento__c` | Datetime | Cuándo terminó el procesamiento |
| `Edificio__c` | Lookup(Edificio__c) | Vacío si el edificio no se resolvió |
| `Activo__c` | Lookup(Activo__c) | Vacío si el activo no se resolvió |
| `Incidente__c` | Lookup(Case) | El caso que abrió o escaló, si hubo |

### Las cuatro fechas

Parecen demasiadas hasta que se ve para qué sirve cada una. `Fecha_Origen__c` es cuándo
pasó el hecho y es la única que decide vigencia. `Fecha_Publicacion__c` es cuándo el
proveedor lo puso a disposición, y su distancia respecto a la anterior mide el retraso del
proveedor. `Fecha_Recepcion__c` es cuándo lo guardamos, y su distancia respecto a la
publicación mide el retraso de nuestra ingesta. `Fecha_Procesamiento__c` es cuándo
terminamos, y su distancia respecto a la recepción mide el retraso del bus.

Separadas, responden dónde está la demora. Juntas, no responden nada. El criterio de
US-201 que pide conservar la fecha de origen separada de la de recepción se cumple aquí de
forma literal.

### Por qué las relaciones a edificio y activo son de búsqueda

Son `Lookup` y no `Master-Detail` por una razón concreta: **una señal rechazada por activo
desconocido no tiene activo al que colgarse.** Con una relación principal-detalle el campo
sería obligatorio y no se podría guardar la señal, que es justamente el caso que más
necesitamos registrar.

La consecuencia es que la bitácora no hereda permisos del activo y hay que protegerla por
su cuenta. Está resuelto en el [módulo 10](10-seguridad-y-accesos.md).

### Por qué la pantalla nunca la consulta

Es la única tabla que crece sin techo: una fila por mensaje recibido, para siempre. Con el
tiempo llega a millones de filas y cualquier consulta que la toque degrada la pantalla.

El modelo está diseñado para que eso no pase. El operador consulta `Estado_Actual__c`, que
tiene una fila por activo y medición y por tanto un tamaño acotado por el número de
equipos, no por el tiempo. La bitácora la consulta el administrador desde vistas de lista
estándar, con filtros, y ese uso sí tolera ser más lento.

Queda abierta Q-11: si se conserva todo el histórico o hay política de retención. No
bloquea el sprint, pero conviene que esté decidido antes de producción.

## `Aviso_de_Senal__e`

El evento de plataforma. No se guarda en ninguna tabla: se publica, alguien lo recoge y se
acabó.

| Campo | Tipo |
| --- | --- |
| `Clave__c` | Text(120) |
| `Tipo_Mensaje__c` | Text(30) |
| `Codigo_Edificio__c` | Text(30) |
| `Codigo_Activo__c` | Text(30) |
| `Tipo_Medicion__c` | Text(40) |
| `Valor__c` | Number(12,4) |
| `Unidad__c` | Text(30) |
| `Estado_Comunicacion__c` | Text(20) |
| `Gap_Segundos__c` | Number(10,0) |
| `Ultima_Vez_Visto__c` | Datetime |
| `Episodio_Id__c` | Text(60) |
| `Fecha_Origen__c` | Datetime |
| `Message_Id__c` | Text(60) |

Hay tres restricciones de los eventos de plataforma que conviene tener presentes porque
condicionan el diseño. **No admiten campos únicos ni External ID**, así que ninguna
garantía de unicidad puede vivir aquí: toda la protección contra duplicados está en
`Senal__c.Clave__c`. **No admiten relaciones**, por eso el evento lleva los códigos
externos en texto y el suscriptor resuelve las referencias. Y **no se pueden marcar campos
como obligatorios de forma útil** en un evento que sirve para dos tipos de mensaje, que es
el precio de la decisión de tener uno solo.

El evento se publica con comportamiento **`Publish Immediately`**, no después de guardar.
Como la señal ya se insertó antes en la misma transacción, no hay nada que esperar, y
publicar de inmediato evita que un fallo posterior en la transacción retenga el aviso.

## `Control_de_Ingesta__c`

Descrito en detalle en el [módulo 02](02-ingesta.md). Registro único, con el cursor en un
`Long Text Area` porque supera los 255 caracteres que admite un campo de texto normal.

## Los objetos estándar

### `Case` como incidente

Trae de fábrica colas, propietario, estados, escalamiento, historial e informes, y un
campo de prioridad con tres niveles que coinciden con los que pidió el cliente. Construir
un objeto propio sería reimplementar todo eso peor.

Campos añadidos:

| Campo | Tipo | Notas |
| --- | --- | --- |
| `Clave_Abierta__c` | Text(100), External ID, Unique | El corazón de US-205 |
| `Activo__c` | Lookup(Activo__c) | |
| `Tipo_Medicion__c` | Picklist global | |
| `Episodio_Id__c` | Text(60) | Solo en incidentes de conectividad |
| `Origen_Senal__c` | Text(120) | La clave de la señal que lo abrió |

El mecanismo de `Clave_Abierta__c` está explicado en el [módulo 07](07-incidentes.md).

### `Task` como intervención

La unidad de trabajo que el coordinador asigna y sigue. Vive en la línea de actividad del
caso sin que haya que construir nada.

Queda pendiente verificar que la configuración de la organización admita los campos que
necesita el modelo de intervención. Es el riesgo R-04 y se resuelve revisando la org, no
diseñando.

## Los catálogos compartidos

`Tipo_Activo`, `Tipo_Medicion`, `Unidad` y `Severidad` se definen como **conjuntos de
valores globales** y se referencian desde los distintos objetos.

El motivo es que se usan en tres o cuatro sitios cada uno. Definidos por separado, tarde o
temprano uno se actualiza y los otros no, y aparece un valor que existe en el umbral pero
no en el estado actual. Definidos una sola vez, la desincronización es imposible por
construcción. Además viajan entre entornos como metadato, que es lo que son.
