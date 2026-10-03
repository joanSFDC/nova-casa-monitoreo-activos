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

**Abrir intervención** pregunta antes por una nota opcional, en un diálogo con el equipo y
la medición en la cabecera. Con nota, el caso nace con ella en la descripción y como
primera tarea de su actividad, a nombre del operador. Sin nota, se abre igual. Cancelar,
la X o Escape no crean nada. El diálogo es `lightning-modal`: lleva el foco a su título al
abrirse, lo mantiene dentro mientras está abierto y lo devuelve al botón al cerrarse.

### Detalle del incidente

Es la página de registro del caso, `Caso_Registro`, a la que lleva el monitor al abrir una
intervención o al ir a la que ya existe. Arriba, el asunto, el estado, la prioridad, el
número y la ciudad, con Editar solo para quien puede editar el caso. Debajo, dos secciones:
Incidente, con la descripción y el propietario, y Equipo, con el activo, la medición, la
ciudad y lo que ata el caso a su señal (clave, episodio y origen). Al lado, la actividad
con las intervenciones.

Se resolvió en una sola página, sin pestañas ni navegación intermedia, porque el operador
llega aquí desde una alarma: quiere saber qué pasa y qué se está haciendo, y cada clic
intermedio es tiempo entre el aviso y la acción.

No hay componente propio para el detalle. La página de Lightning ya aplica la compartición
por ciudad y los permisos de campo, y trae la actividad sin código. Por eso el servidor no
expone una lectura del caso.

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

Una sola clase Apex con un método de lectura y uno de acción. El detalle del incidente no
pasa por ella: es `Caso_Registro`.

| Método | Qué devuelve | Anotación |
| --- | --- | --- |
| `obtenerPanel(String edificioId)` | Contadores, filas y estado de la ingesta | `@AuraEnabled(cacheable=true)` |
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

## La identidad visual

Cubre el **issue #15**. El componente del operador ya usaba la paleta del prototipo; lo
que faltaba era que la aplicación que lo contiene también la usara, para que no pareciera
pegado encima de algo ajeno.

### Tema de la org y marca de la aplicación

Salesforce separa dos cosas. El **tema** es de la org entera: barra superior, logo,
fondo y color de enlaces y botones. La **marca de la aplicación** es el logo y el color
de una aplicación concreta, y solo se ve si la aplicación pide sobrescribir el tema.

En esta org la marca de la aplicación no pinta la barra de navegación, ni en Cosmos ni en
SLDS 1: solo cambia el logo al rato de cargar. Por eso **el color y el logo van en el
tema**, y la aplicación conserva `shouldOverrideOrgTheme` en falso. Su logo propio, la
casa sobre blanco, es el que se ve en el iniciador de aplicaciones.

### Por qué SLDS 1 y no Cosmos

La org venía con **Salesforce Cosmos**, que es SLDS 2. Ahí los colores de severidad del
sistema de diseño no son los documentados: crítico pasa a `#b60554`, advertencia a
`#8c4b02` y normal a `#056764`. Y la propia página de temas avisa de que SLDS 2 puede
tener efectos inesperados sobre un tema propio.

**Decisión: un tema propio sobre SLDS 1** (`designSystemVersion` `SLDS_v1`). Es el
sistema contra el que se escribió el componente y el que da los valores que el issue pide
conservar.

### Los archivos

| Archivo | Qué es |
| --- | --- |
| `lightningExperienceThemes/Nova_Casa` | El tema, sobre SLDS 1, con su conjunto de marca por defecto |
| `brandingSets/Nova_Casa` | Colores e imágenes del tema |
| `settings/LightningExperience.settings` | Deja `Nova_Casa` como tema activo |
| `contentassets/NovaCasaLogoHorizontal` | Logo de la barra, 438 × 120 |
| `contentassets/NovaCasaFondoEncabezado` | Fondo del encabezado, 1800 × 360 |
| `contentassets/NovaCasaLogoApp` | La casa sola, 128 × 128, para la aplicación |
| `applications/Nova_Casa` | Descripción, logo y orden de pestañas |

Las imágenes salen de `recursos/logos/logo-novacasa.png` y el tema las referencia como
`/file-asset/<Nombre>?v=N`. Si se cambia una imagen hay que subir su versión en el
`.asset-meta.xml` y en la referencia, o la org sigue sirviendo la anterior.

### Los colores

| Token del prototipo | Valor | Propiedad del tema |
| --- | --- | --- |
| `--nc-navy` | `#122d4f` | `BRAND_COLOR`, `OVERRIDE_A11Y_COLOR` |
| `--nc-page` | `#f3f2f2` | `PAGE_BACKGROUND_COLOR` |
| `--nc-navy-light` | `#e8eef4` | Degradado del fondo del encabezado |
| `--nc-copper` | `#ae6930` | Línea de 4 px en el fondo del encabezado y el logo |

`OVERRIDE_A11Y_COLOR` es necesario. Sin él, Salesforce deriva del color de marca un azul
propio, `#415c8a`, para enlaces y botones, y la aplicación tiene dos azules.

**La cabecera es blanca** (`HEADER_BACKGROUND_COLOR` `#ffffff`). Sobre la barra azul
marino, el logo necesitaba una placa blanca y se veía como una imagen pegada encima. Sobre
blanco la placa no se nota. El azul marino queda en el logo, los enlaces y los botones.

La línea bajo las pestañas y la marca de la pestaña activa salen `#6e94d5`. Es un tono de
la paleta que Salesforce genera a partir de `BRAND_COLOR`. `OVERRIDE_A11Y_COLOR` solo
fija el primer tono de esa paleta, el de enlaces y botones, así que esa línea no se puede
fijar desde el tema.

**El cobre solo aparece en imágenes.** Sobre blanco da 4,32:1, por debajo del 4,5:1 que
pide el texto pequeño. Si algún día hiciera falta texto en cobre, el tono es
`--nc-copper-700`, `#8c5224`, que da 6,27:1.

### La severidad no cambia con el tema

Los tres colores se fijan en `monitorDeActivos.css` en lugar de tomarse de los ganchos
del sistema de diseño: crítico `#ba0517`, advertencia `#a15c00` y normal `#2e844a`. Así un
cambio de tema, o volver a Cosmos, no los mueve.

### Los iconos

Salesforce **solo lee el número** del motivo de una pestaña; el nombre que lo acompaña es
decorativo. Los archivos decían, por ejemplo, `Custom67: Building` para el edificio, pero
el 67 son engranajes, y eso es lo que mostraba. Lo mismo pasaba con el activo, el estado
y el monitor.

| Objeto | Motivo | Icono |
| --- | --- | --- |
| Edificio | `Custom24` | Edificio |
| Activo | `Custom19` | Llave inglesa |
| Estado actual | `Custom97` | Termómetro |
| Umbral | `Custom79` | Cinta métrica |
| Señal | `Custom30` | Antena de radar |
| Control de ingesta | `Custom67` | Engranajes |
| Monitor | `Custom21` | Computador |

### Las etiquetas y las páginas

Los campos que todavía hablaban como su nombre de API se reescribieron como los leerá un
operador: «Último id de mensaje», «Visto por última vez», «Límite alto crítico»,
«Ingesta activa», «Inicio de la sesión». Estado y Prioridad del caso tenían etiquetas en
inglés, porque la org es `en_US`. Ahora dicen «Nuevo», «Escalado», «En espera», «Cerrado»
y «Alta», «Media», «Baja». **El valor de API no cambia**, que es lo que escribe el código.

`Valor__c` y los cuatro límites del umbral pasaron de cuatro decimales a dos: las páginas
estándar mostraban «0,4000». El simulador manda como mucho dos, en la presión.

Activo, Edificio y Estado actual tienen página de registro propia, por el mismo motivo
que Caso y Control ([estado.md](estado.md), puntos 15, 28 y 29): la estándar traía solo
los campos estándar, la divisa y el panel de actividad. En el estado todo es de solo
lectura y la cabecera no tiene Editar, porque lo escribe el procesamiento. El
administrador del sistema todavía ve el lápiz en cada campo: su permiso «Edit Read Only
Fields» pasa por encima de la página, y ese perfil no deja quitarlo.

Las pestañas siguen el recorrido del operador: Monitor, Casos, Activos, Edificios,
Estados actuales, Umbrales, Señales, Control de ingesta e Inicio. Cada usuario ve solo
las de los objetos que tiene. Quien ya hubiera personalizado su barra conserva su orden.

### El contraste medido

| Texto | Fondo | Contraste |
| --- | --- | --- |
| Crítico `#ba0517` | Blanco | 6,73 |
| Advertencia `#a15c00` | Blanco | 5,19 |
| Normal `#2e844a` | Blanco | 4,65 |
| Enlaces y botones `#122d4f` | Blanco | 13,87 |
| Pestañas `#181818` | Blanco | 17,76 |
| Título `#181818` | Página `#f3f2f2` | 15,89 |
| Aviso de ingesta `#181818` | `#dd7a01` | 5,80 |
| Cabecera de tabla `#444444` | `#f3f3f3` | 8,78 |
| Línea de la pestaña activa `#6e94d5` | Blanco | 3,06 |

Todo el texto pasa 4,5:1. La línea de la pestaña no es texto: es un indicador, y para
eso basta 3:1. Los colores se leyeron en la org con el estilo calculado de cada
elemento, no del archivo.

### Al desplegar

El tema, la marca y las páginas tardan unos minutos en llegar a una sesión abierta, por
la caché de Lightning. Si un despliegue falla, no se aplica nada de ese lote: una página
que parece no haber entrado puede ser de un despliegue fallido anterior.
