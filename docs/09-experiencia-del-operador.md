# 09 · Experiencia del operador

Cubre **US-207 · Experiencia propia para el rol principal**.

## Por qué solo el operador tiene pantalla propia

Cuatro personas usan el sistema y solo una recibe un componente a medida. La decisión es
deliberada y conviene justificarla, porque construir menos es más fácil de defender cuando
está razonado.

El coordinador necesita revisar una cola de casos y asignar trabajo: eso es exactamente
para lo que sirven las colas y las vistas de lista estándar, con filtros, ordenación
masiva y asignación en bloque que ya funcionan. La gerencia necesita ver qué edificios
concentran situaciones graves: eso es un tablero, que además el propio gerente puede
filtrar, suscribir y recibir por correo sin pedirnos nada. El administrador necesita
investigar señales: eso es una vista de lista sobre la bitácora, con búsqueda y filtros.

El operador es el único cuyo trabajo no encaja en una pantalla estándar, por dos razones.
Necesita **reconocer** el estado de todos sus equipos de un vistazo, sin filtrar ni buscar,
y eso es una tarea de percepción visual que una tabla genérica no resuelve. Y es el único
que pasa de **ver** a **hacer** en la misma pantalla: mira el estado y abre la
intervención.

Esa segunda propiedad es la que hace que su recorrido sea el que mejor demuestra que el
sistema completo funciona, desde que el sensor reporta hasta que alguien tiene trabajo
asignado.

## El concepto de base: dónde se calcula qué

La decisión estructural de un componente Lightning es qué ocurre en el servidor y qué en el
navegador. Tiene tres dimensiones y conviene separarlas.

**Rendimiento.** Lo que se calcula en el servidor viaja ya resuelto; lo que se calcula en
el navegador obliga a mandar los datos crudos.

**Seguridad.** Y aquí está lo importante: **todo lo que llega al navegador es visible para
quien sepa mirar.** Las herramientas de desarrollo del navegador muestran la respuesta
completa del servidor, no solo lo que la pantalla pinta. Filtrar en el navegador no es
filtrar: es enviar y ocultar.

**Reactividad.** Un componente que recalcula en el navegador responde al instante; uno que
va al servidor tiene latencia de red.

En este sistema la dimensión que manda es la segunda, y por un motivo concreto: un operador
solo debe ver sus edificios, y eso no es una preferencia de interfaz sino una frontera de
autorización.

## La decisión: nada se calcula en el navegador

**Todo dato que la pantalla muestra viene del servidor, ya filtrado y ya agregado.** El
componente recibe una estructura lista para pintar y no hace ninguna operación sobre los
datos más allá de la presentación.

Eso incluye los contadores. El encabezado muestra cuántos equipos hay en cada severidad, y
esos números **se calculan en el servidor**. Si se calcularan contando las filas recibidas
funcionaría igual, pero abriría una fuga sutil: bastaría con enviar una fila de más para
que el número delatara la existencia de un registro que esa persona no debería ver.

Los contadores son además filtros: pulsar «3 críticos» filtra la tabla. Esa interacción sí
ocurre en el navegador, sobre datos que ya pasaron el filtro de autorización, y por tanto
no abre nada.

## Lo que se ve

### Encabezado

Los tres contadores por severidad, que funcionan como filtros, y un selector de edificio
cuando el operador tiene más de uno.

También, cuando corresponde, el **aviso de consulta atrasada**: una franja visible que
aparece si `Control_de_Ingesta__c.Ultima_Consulta_Exitosa__c` es demasiado antigua.

Ese aviso es la defensa contra dos fallos silenciosos: que la cadena de ingesta se rompa
sin que nadie se entere, y que el proveedor entero deje de responder. En los dos casos el
sistema seguiría pareciendo sano y la pantalla mostraría datos viejos como si fueran
actuales. No es una alarma, pero es la diferencia entre un operador que sabe que está
mirando datos de hace dos horas y uno que no.

### Tabla de equipos

Una fila por activo y medición, ordenada con lo peor arriba. Las columnas:

| Columna | De dónde sale |
| --- | --- |
| Edificio | `Activo__c.Edificio__r.Name` |
| Equipo | `Activo__c.Name` |
| Medición | `Estado_Actual__c.Tipo_Medicion__c` |
| Valor | `Valor__c` y `Unidad__c`, con los decimales del umbral |
| Severidad | `Severidad__c`, con tratamiento visual propio |
| Antigüedad | Calculada desde `Fecha_Origen__c` en la presentación |
| Comunicación | `Estado_Comunicacion__c` cuando no es `HEALTHY` |
| Acción | Abrir intervención, o ir al incidente si ya existe |

La **antigüedad** merece su columna propia y no es decorativa. Es la única defensa, para
los activos que no emiten conectividad, contra el riesgo R-03: un equipo que deja de
reportar con su última lectura normal se vería sano indefinidamente. Con la antigüedad a la
vista, «normal hace tres minutos» y «normal hace nueve horas» dejan de parecer lo mismo.

La ordenación por defecto es severidad descendente y, dentro de cada severidad, antigüedad
descendente. Así lo primero que se ve es lo más grave y, entre cosas igual de graves, lo
que lleva más tiempo sin atenderse.

### Detalle del incidente

Una sola página. Muestra el caso con su prioridad, su estado, su propietario si lo tiene,
el activo y la medición implicados, y la línea de actividad con las intervenciones.

Se resolvió en una sola página, sin pestañas ni navegación intermedia, porque el operador
llega aquí desde una alarma: quiere saber qué pasa y qué se está haciendo, y cada clic
intermedio es tiempo entre el aviso y la acción.

### Los tres estados de la pantalla

| Estado | Cuándo | Qué muestra |
| --- | --- | --- |
| Cargando | Mientras el servidor responde | Esqueleto con la forma de la tabla |
| Vacío | El operador no tiene equipos asignados | Explicación y a quién pedir acceso |
| Error | El servidor falló | Qué pasó y un botón de reintentar |

El estado vacío tiene que decir **por qué** está vacío. «No hay datos» es inútil: el
operador no sabe si es que todo está bien, si es que no tiene permisos o si es que el
sistema está roto. El mensaje distingue «no tienes edificios asignados, habla con tu
coordinador» de «tus equipos no tienen lecturas todavía».

El estado de error tampoco puede ser un texto genérico. Distingue entre un fallo de
servidor, que se reintenta, y una falta de permisos, que no se arregla reintentando.

## La actualización

US-207 pide que la pantalla permita actualizar bajo demanda, y dice explícitamente que la
actualización automática es un extra.

**Decisión: se construyen las dos, con el botón como mecanismo principal.**

El botón «actualizar» es la garantía: siempre está, siempre funciona y no depende de
ninguna infraestructura de suscripción. Si la actualización automática fallara, la pantalla
sigue siendo usable.

### La actualización automática

El componente se suscribe al mismo evento de plataforma que usa el procesamiento, mediante
la biblioteca de mensajería empresarial del navegador.

Y aquí está la decisión más importante del módulo: **el componente nunca pinta el contenido
del aviso. Lo usa solo como señal para volver a pedir los datos al servidor.**

El motivo es una frontera de seguridad. **El canal de eventos de plataforma no filtra por
permisos.** Un suscriptor recibe todos los eventos publicados, con independencia de a qué
registros tenga acceso. Si la pantalla pintara lo que le llega, un operador de Bogotá vería
aparecer lecturas de Barranquilla en su tabla.

Al usar el aviso solo como disparador y volver a consultar, el filtro de autorización del
servidor se aplica **siempre**, en cada refresco, sin que el componente tenga que acordarse
de nada. Es el riesgo R-07 y está resuelto por construcción, no por disciplina.

El coste de este diseño es una consulta extra por cada ráfaga de eventos. Se contiene con
una **espera de dos segundos**: el componente agrupa los avisos que llegan en esa ventana y
hace una sola consulta. Con doscientos mensajes procesados de golpe, eso es una consulta en
lugar de doscientas.

La suscripción se cancela al desmontar el componente, para no dejar conexiones abiertas
cuando el operador navega a otra parte.

## El contrato con el servidor

Una sola clase Apex con dos métodos de lectura y uno de acción.

| Método | Qué devuelve | Anotación |
| --- | --- | --- |
| `obtenerPanel(String edificioId)` | Contadores, filas y estado de la ingesta | `@AuraEnabled(cacheable=true)` |
| `obtenerIncidente(Id casoId)` | El caso con sus intervenciones | `@AuraEnabled(cacheable=true)` |
| `abrirIntervencion(Id estadoId, String nota)` | El identificador del caso creado | `@AuraEnabled` |

`cacheable=true` habilita el servicio de datos de Lightning, que cachea la respuesta en el
cliente y la invalida sola. Solo se puede marcar así un método que no modifica datos, y por
eso la acción de abrir intervención no lo lleva.

El método devuelve un objeto de transferencia propio, no registros de Salesforce en crudo.
Eso permite tres cosas: enviar solo los campos que la pantalla usa, incluir los contadores
ya calculados en la misma llamada, y que un cambio en el modelo no rompa el componente si
la forma del objeto de transferencia se mantiene.

La clase se declara `with sharing` y todas sus consultas usan `WITH USER_MODE`. El detalle
está en el [módulo 10](10-seguridad-y-accesos.md).

## Qué se consulta, y qué no

La pantalla consulta **únicamente `Estado_Actual__c`**, con su activo y su edificio por
relación. Una fila por activo y medición: un tamaño acotado por el número de equipos, no
por el tiempo.

**No consulta nunca `Senal__c`.** Es la tabla que crece sin techo, y es el riesgo R-10: con
volumen llega a millones de filas y cualquier consulta que la toque degrada la pantalla.

Esta separación es la razón de que el modelo tenga dos objetos donde podría tener uno, y
es lo que hace que el rendimiento de la pantalla no dependa del volumen histórico.

## La accesibilidad

No es un añadido opcional: una pantalla de monitorización que solo comunica por color
excluye a una parte real de los operadores.

- La severidad se comunica con **color y con texto**, nunca solo con color.
- Los contadores son botones alcanzables con teclado, con su estado de selección anunciado.
- La tabla tiene encabezados asociados y es navegable con teclado.
- Los cambios de estado —cargando, error, actualizado— se anuncian en una región activa,
  de modo que un lector de pantalla informe de que la tabla se refrescó.
- El contraste cumple el mínimo de la norma para texto y para los indicadores de severidad.
