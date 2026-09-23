# 05 · Clasificación y límites

Cubre **US-204 · Ajustar límites sin desplegar código** y la parte de clasificación de
**US-206 · Diferenciar severidad**.

## El concepto de base

Clasificar es convertir una magnitud continua en una de tres categorías discretas. Suena
trivial y no lo es, porque toda clasificación por umbrales tiene que responder tres
preguntas que casi siempre se dejan implícitas, y que después aparecen como defectos:

1. **¿Qué pasa exactamente en la frontera?** Un valor idéntico al límite, ¿a qué banda
   pertenece?
2. **¿Qué pasa fuera de todas las bandas declaradas?** Si las bandas no cubren la recta
   real entera, hay valores huérfanos.
3. **¿Qué pasa si no hay configuración, o si la que hay se contradice?**

US-204 pide explícitamente respuesta a las tres. Este módulo las da.

## Lo que declara el simulador

`GET /catalog` devuelve una tabla de referencia por medición. Transcrita de la respuesta
real:

| Medición | Normal | Advertencia | Crítico | Inválido | Fronteras |
| --- | --- | --- | --- | --- | --- |
| `TEMPERATURE` | 18 – 30 | 15 – 17.9 y 30.1 – 35 | 5 – 14.9 y 35.1 – 55 | −40 – −11 y 81 – 140 | 15, 18, 30, 35 |
| `WATER_PRESSURE` | 2.5 – 4 | 1.5 – 2.49 y 4.01 – 5 | 0 – 1.49 y 5.01 – 9 | 20.1 – 60 | 1.5, 2.5, 4, 5 |
| `WATER_CONSUMPTION` | 0 – 400 | 401 – 650 | 651 – 1800 | −500 – −1 y 5001 – 9000 | 0, 400, 650 |
| `ENERGY_CONSUMPTION` | 0 – 40 | 40.1 – 65 | 65.1 – 220 | −80 – −1 y 1001 – 3000 | 0, 40, 65 |

Dos observaciones que cambian el diseño.

La primera es que **las bandas son bidireccionales** para temperatura y presión: hay
problema por exceso y por defecto. Un cuarto técnico demasiado frío es tan anómalo como
uno demasiado caliente, y una bomba con presión excesiva puede reventar una tubería igual
que una sin presión deja sin agua. Los consumos, en cambio, solo tienen frontera por
arriba. El modelo de cuatro valores del [módulo 03](03-modelo-de-datos.md) absorbe los dos
casos dejando vacíos los campos que no aplican.

La segunda es que **el simulador declara explícitamente los valores frontera**, y el
escenario `BOUNDARIES` los envía. No hay que adivinar qué se va a probar.

`CAMERA_CONNECTIVITY` no aparece en esta tabla. La conectividad no se clasifica por valor
sino por tiempo de silencio, y está en el [módulo 08](08-conectividad.md).

## La frontera

### El problema

Con bandas contiguas hay que decidir de qué lado cae el punto de corte. Es la clase de
detalle que nadie discute en diseño y que después produce defectos que tardan semanas en
aparecer, porque solo se manifiestan con el valor exacto.

### Lo que dice la evidencia

El escenario `BOUNDARIES` envía exactamente los valores de la columna «fronteras»:

```
WATER_PRESSURE  1.5   →  mínimo de la banda de advertencia baja
TEMPERATURE     15    →  mínimo de la banda de advertencia baja
WATER_PRESSURE  4     →  máximo de la banda normal
WATER_CONSUMPTION 0   →  mínimo de la banda normal
TEMPERATURE     30    →  máximo de la banda normal
WATER_PRESSURE  2.5   →  mínimo de la banda normal
```

Cruzando esos valores con la tabla de rangos, la lectura es inequívoca: los rangos son
**intervalos cerrados por ambos extremos**, y las bandas no se solapan porque el siguiente
rango empieza un decimal más allá. La temperatura normal llega hasta 30 y la advertencia
empieza en 30.1, con un decimal de precisión declarado.

### La decisión

**La clasificación se define por pertenencia a intervalos cerrados: un valor pertenece a
la banda que lo contiene, incluidos sus extremos.**

Expresado contra nuestros cuatro campos de `Umbral__c`, y con `v` el valor leído:

| Condición | Severidad |
| --- | --- |
| `Critico_Bajo__c` no vacío y `v <= Critico_Bajo__c` | Crítico |
| `Critico_Alto__c` no vacío y `v >= Critico_Alto__c` | Crítico |
| `Advertencia_Bajo__c` no vacío y `v <= Advertencia_Bajo__c` | Advertencia |
| `Advertencia_Alto__c` no vacío y `v >= Advertencia_Alto__c` | Advertencia |
| En cualquier otro caso | Normal |

El orden de evaluación importa: **primero crítico por los dos lados, después advertencia
por los dos lados, y normal como caso por defecto.** Evaluar advertencia antes que crítico
clasificaría toda lectura crítica como advertencia, porque una lectura crítica también
cumple la condición de advertencia.

Los valores concretos, traducidos desde la tabla del simulador:

| Medición | Crítico bajo | Advertencia bajo | Advertencia alto | Crítico alto |
| --- | --- | --- | --- | --- |
| `TEMPERATURE` | 14.9 | 17.9 | 30.1 | 35.1 |
| `WATER_PRESSURE` | 1.49 | 2.49 | 4.01 | 5.01 |
| `WATER_CONSUMPTION` | *vacío* | *vacío* | 401 | 651 |
| `ENERGY_CONSUMPTION` | *vacío* | *vacío* | 40.1 | 65.1 |

Con esta tabla, una temperatura de exactamente 30 no cumple `v >= 30.1` y clasifica como
normal; una de exactamente 35 no cumple `v >= 35.1` y clasifica como advertencia. Es lo
que declara el simulador.

Un campo vacío se interpreta como «no hay frontera por ese lado». Es lo que permite que
los consumos usen la misma lógica sin ramas especiales: la comparación simplemente no se
evalúa.

## Los valores fuera de todas las bandas

### El problema

Las bandas del simulador no cubren la recta real. Para la temperatura, crítico llega hasta
55 e inválido empieza en 81. **Entre 55 y 81 no hay nada.**

Y no es teórico: el escenario `CONFLICT` envía una temperatura de **60.19 °C**, que cae
justo en ese hueco.

### Las alternativas

Rechazar como valor fuera de rango es defendible: un valor que no encaja en ninguna banda
declarada podría ser un sensor averiado. Pero tiene un fallo grave de seguridad operativa:
un cuarto técnico a 60 °C es una emergencia, y el sistema lo descartaría en silencio
justo cuando más importa.

Guardarlo con severidad «sin clasificar» es honesto pero inútil: nadie sabe qué hacer con
esa categoría y la pantalla tendría un cuarto estado que no significa nada accionable.

### La decisión

**Las bandas extremas son abiertas: por encima del crítico alto sigue siendo crítico, y
por debajo del crítico bajo también.** Las tablas de arriba ya lo expresan así: la
condición es `v >= Critico_Alto__c`, sin techo.

El principio que lo justifica se puede enunciar en una frase, y sirve para resolver
cualquier caso parecido que aparezca después: **ante la duda, nunca subestimar la
gravedad.** Un falso crítico cuesta que alguien mire un equipo que estaba bien. Un falso
normal cuesta que nadie mire un equipo que estaba mal.

Los rangos `invalid` del catálogo son de referencia para la generación de datos del
simulador, no una banda de clasificación nuestra. Una temperatura de 100 °C clasifica como
crítica por nuestra regla, no como inválida. Se descarta un valor por inválido cuando es
nulo, no numérico o viene en una unidad incompatible, no por su magnitud.

## Configuración ausente o contradictoria

US-204 pide que ambas situaciones produzcan un resultado explicable.

### Sin umbral configurado

Se rechaza la señal con motivo **«sin límite configurado»** y se marca **reintentable**. El
mensaje está bien; lo que falta es configuración nuestra. En cuanto el coordinador cree el
umbral, reintentar funciona.

No se clasifica como normal por defecto, que sería la salida perezosa. Una lectura sin
límite no es una lectura normal: es una lectura que no sabemos clasificar, y decir que
está bien sería mentir.

### Rango contradictorio

Un umbral donde el crítico alto sea menor que la advertencia alta, o donde las bandas se
crucen, produciría clasificaciones arbitrarias.

**Decisión: se impide en el origen con reglas de validación en `Umbral__c`**, de modo que
el registro no se pueda guardar contradictorio:

| Regla | Condición que bloquea |
| --- | --- |
| Orden bajo | `Critico_Bajo__c > Advertencia_Bajo__c` |
| Orden alto | `Critico_Alto__c < Advertencia_Alto__c` |
| Bandas cruzadas | `Advertencia_Bajo__c >= Advertencia_Alto__c` |
| Bandas altas incompletas | `Advertencia_Alto__c` vacío y `Critico_Alto__c` con valor |
| Sin ninguna frontera | Los cuatro campos vacíos |
| Minutos de silencio | `Minutos_Advertencia__c >= Minutos_Critico__c` |

Validar en el origen es mejor que validar al clasificar por una razón de momento: el error
aparece delante de la persona que lo puede corregir, en el instante en que lo comete, con
un mensaje que explica qué está mal. Validar al clasificar lo haría aparecer horas después,
en la bitácora, delante de alguien que no sabe quién tocó qué.

Las reglas de validación se escriben con mensajes en español dirigidos al coordinador, no
mensajes técnicos.

## La administración de los límites

El requisito literal es que la persona autorizada pueda cambiar los límites **sin
modificar ni volver a desplegar código**. La justificación de por qué es un objeto y no un
tipo de metadato personalizado está en el [módulo 03](03-modelo-de-datos.md).

Lo que se construye:

- Una **pestaña** de `Umbral__c` en la aplicación, visible para el coordinador.
- Una **vista de lista** por defecto agrupada por tipo de activo, con los cuatro valores y
  la unidad en columnas.
- El **historial de cambios** activado en los cuatro campos de umbral y en los dos de
  minutos, para que quede quién cambió qué y cuándo.
- Las **reglas de validación** de la sección anterior.
- Un **conjunto de permisos** que da lectura a todos y edición solo al coordinador, según
  el [módulo 10](10-seguridad-y-accesos.md).

No se construye pantalla a medida. Una pestaña estándar con una vista de lista hace todo
lo que se pide, trae búsqueda, filtros, edición en línea y auditoría de fábrica, y
funciona en móvil. Construir un componente propio sería reemplazar algo que ya funciona.

## La reclasificación

### El problema

Como la severidad se guarda como dato, cambiar un límite **no reclasifica lo ya guardado**.
Entre el cambio y la siguiente lectura, la pantalla muestra la clasificación anterior. Es
el riesgo R-06 y es una consecuencia directa de la decisión del [módulo 03](03-modelo-de-datos.md).

### La decisión

**Una acción «aplicar límites» en la pestaña de umbrales, que recalcula la severidad de
los estados actuales afectados por ese umbral.**

Funciona así: recorre los `Estado_Actual__c` cuyo activo es del tipo del umbral y cuya
medición coincide, vuelve a clasificar el valor vigente con los límites nuevos y actualiza
`Severidad__c` y `Severidad_Nivel__c` donde haya cambiado.

Tres precisiones sobre el alcance, porque definen qué **no** hace:

- **No toca la bitácora.** El histórico registra lo que se decidió en su momento con los
  límites de su momento, y reescribirlo sería falsificar el registro. Es también lo que
  pide el criterio de US-204 sobre no reclasificar todo el historial.
- **No abre ni cierra incidentes.** Si al reclasificar un estado pasa a crítico, eso queda
  reflejado en la pantalla pero no genera un caso. Abrir casos en masa desde un cambio de
  configuración sería una sorpresa desagradable para el coordinador, que acaba de tocar un
  número y se encuentra veinte casos nuevos.
- **No es automática.** Se dispara con un botón, no con un disparador sobre el umbral. Así
  quien cambia el límite decide cuándo aplicar el efecto, y puede ajustar los cuatro
  valores antes de propagarlos.

Si el volumen de estados a recalcular creciera, la acción pasaría a ejecutarse como
proceso por lotes. Con dos edificios y diez activos cabe holgadamente en una transacción
síncrona.

## Cómo se siembran los umbrales iniciales

Los valores de la tabla de arriba salen de `thresholdsReference` del catálogo, que el
propio simulador marca como «rangos de referencia». Se cargan mediante el mismo script de
datos que siembra edificios y activos, con `upsert` por `Clave__c` para que sea repetible.

Esto cierra en buena parte el riesgo R-17, que anticipaba tener que trabajar con valores
inventados hasta que el cliente entregara los definitivos. Queda como supuesto documentado
que los valores de referencia del simulador son aceptables para la demo; si el cliente
entrega otros, se sustituyen editando registros, que es exactamente la capacidad que pide
US-204.

Los minutos de tolerancia de comunicación no vienen en el catálogo. Los fijamos nosotros
en quince minutos para advertencia y sesenta para crítico, y quedan documentados como
supuesto en el [módulo 08](08-conectividad.md).
