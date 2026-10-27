# 09 · Experiencia del operador

Cubre **US-207 · Experiencia propia para el rol principal**.

## Por qué solo el operador tiene pantalla propia

Cuatro personas usan el sistema y solo una recibe un componente a medida. La decisión es
deliberada y conviene justificarla, porque construir menos es más fácil de defender cuando
está razonado.

El coordinador necesita revisar una cola de casos y asignar trabajo: eso es exactamente
para lo que sirven las colas y las vistas de lista estándar, con filtros, ordenación
masiva y asignación en bloque que ya funcionan. Su cola es **Coordinación** y la ve en dos
vistas de Casos, las dos en su inicio: «Cola de coordinación», con lo que sigue en falla, y
«Normalizados por cerrar», con lo que ya volvió y espera que alguien lo verifique y lo
cierre ([módulo 07](07-incidentes.md)). La gerencia
necesita ver qué edificios concentran situaciones graves: eso es un tablero, que el propio
gerente filtra por ciudad y cuyos informes recibe por correo sin pedirnos nada
([más abajo](#el-tablero-de-la-gerencia)). El administrador necesita
investigar señales: eso es una vista de lista sobre la bitácora, con búsqueda y filtros.

El operador es el único cuyo trabajo no encaja en una pantalla estándar, por dos razones.
Necesita **reconocer** el estado de todos sus equipos de un vistazo, sin filtrar ni buscar,
y eso es una tarea de percepción visual que una tabla genérica no resuelve. Y es el único
que pasa de **ver** a **hacer** en la misma pantalla: mira el estado y abre la
intervención.

Esa segunda propiedad es la que hace que su recorrido sea el que mejor demuestra que el
sistema completo funciona, desde que el sensor reporta hasta que alguien tiene trabajo
asignado.

### Una app por rol

Antes había una sola app, «Nova Casa», con todas las pestañas para todos, y el Inicio era
el de ventas. **Decisión: cada rol entra por su app, con su propio inicio**, armado con las
piezas que ya existen.

| App | Pestañas | Inicio |
| --- | --- | --- |
| Nova Casa Operación | Inicio, Monitor, Incidentes, Activos, Edificios | El monitor a todo lo ancho y «Incidentes abiertos», que la compartición deja en su ciudad |
| Nova Casa Coordinación | Inicio, Incidentes, Monitor, Señales, Umbrales, Activos, Edificios, Estados actuales, Informes, Paneles | La cola de coordinación y el monitor a todo lo ancho, y debajo «Rechazadas hoy» |
| Nova Casa Gerencia | Inicio, Paneles, Informes, Incidentes, Monitor, Edificios | El panel Gerencia y «Críticos abiertos» |
| Nova Casa Administración | Inicio, Controles de ingesta, Señales, Umbrales, Monitor, Incidentes, Activos, Edificios, Estados actuales, Informes, Paneles | «Salud de la ingesta» y «Atascadas», con «Rechazadas hoy» al lado |

- **Cada inicio es una página de inicio propia** (`Inicio_Operacion`, `Inicio_Coordinacion`,
  `Inicio_Gerencia`, `Inicio_Administracion`), asignada en su app. Usa el componente del
  monitor, tarjetas de vista de lista y el panel incrustado: ningún componente nuevo.
- **Activos, Edificios y Estados actuales** tienen ahora la vista «Todos»; antes solo
  ofrecían «Vistos recientemente». La compartición la filtra por ciudad, como la página.
- **Vistas de lista nuevas:** «Incidentes abiertos» y «Críticos abiertos» de incidentes, y
  «Salud de la ingesta» del control, con activa, escenario, última consulta exitosa, fallos
  seguidos, caída avisada y último error. Es una vista y no un componente: no hace falta
  código para mostrar cinco campos de un registro.
- **El coordinador va apilado.** Con «Rechazadas hoy» al lado, como en la maqueta, el monitor
  quedaba en una columna angosta y sus botones se partían; apilado, monitor y cola van a todo
  lo ancho.
- **Cada app la hace visible el conjunto de su rol.** El de Administración ve además las
  otras tres: el administrador las gestiona, y el script de usuarios, que corre como él,
  necesita encontrarlas.
- **La app de entrada** de cada persona la pone `scripts/crear-usuarios-demo.apex` según su
  conjunto de permisos ([módulo 10](10-seguridad-y-accesos.md)).
- **«Nova Casa» se retiró** después de pasar a cada persona a su app.
- Las apps estándar de Salesforce (Servicio, Ventas y las demás) siguen en el selector de
  apps del operador: el perfil de acceso mínimo las deja ver y se decidió no tocarlo. Su
  entrada y su inicio son los de su rol.

### El tablero de la gerencia

Es el panel **Gerencia · Nova Casa**, en la pestaña Paneles, con dos gráficos:

| Gráfico | Informe | Qué cuenta |
| --- | --- | --- |
| Equipos fuera de rango por edificio | `Equipos_fuera_de_rango` | Activos en advertencia o crítico, por edificio y severidad |
| Casos abiertos por ciudad y prioridad | `Casos_abiertos_por_ciudad` | Casos sin cerrar, por ciudad y prioridad |

El panel es **dinámico**: cada persona lo ve con sus propios permisos y su compartición, no
con los de quien lo creó. Un panel con usuario fijo enseñaría a quien lo abre lo que ve ese
usuario, y es la misma fuga que la de calcular en el navegador. Hoy gerente y coordinador
ven las dos ciudades, así que los números coinciden, pero si mañana hay un gerente por
región el panel no cambia.

El filtro **Ciudad** usa `Edificio__c.Ciudad__c` en el gráfico de equipos y
`Case.Ciudad__c` en el de casos. Los dos son el mismo texto, así que «Bogotá» filtra igual
en ambos.

Salesforce no admite suscripciones a un panel dinámico: sin un usuario fijo no sabe con
qué permisos armar el correo. Por eso la suscripción va por los **informes**, que se
ejecutan con los permisos de quien se suscribe. Gerente y coordinador tienen «Suscribirse
a informes»; «Suscribirse a paneles» no se concede porque no tendría dónde usarse.

Los dos informes están en la carpeta **Nova Casa**, y el panel en otra carpeta con el mismo
nombre. Las dos se comparten en lectura con el grupo `Gerencia_y_Coordinacion`
([módulo 10](10-seguridad-y-accesos.md#acceso-a-los-informes)).

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

### Encabezado y barra de filtros

El título, el botón **Actualizar** y, debajo, una barra con todo lo que filtra y ordena:

- **Cuatro fichas** con un punto de color y su conteo: críticos, advertencias, normales y
  sin comunicación. Una ficha con conteo se tiñe de su color; en cero queda gris. Pulsarla
  filtra y queda marcada (`aria-pressed`); pulsarla otra vez quita el filtro. Los conteos
  los calcula el servidor.
- **Edificio**, cuando la persona tiene más de uno. Es el único filtro que va al servidor.
- **Tipo de equipo**, con los tipos presentes en sus filas.
- **Ordenar por**: severidad (lo grave primero, el orden por defecto), antigüedad (lo más
  viejo primero), equipo o edificio, de la A a la Z.
- **Buscar equipo**, por nombre o código, sin importar mayúsculas ni tildes.

Tipo, orden y búsqueda se aplican en el navegador **sobre filas que el servidor ya
autorizó**: no muestran nada nuevo, solo eligen entre lo que la persona ya puede ver. Por
eso no rompen la regla de que nada se calcula en el navegador. Si los filtros dejan la
tabla vacía, la pantalla lo dice y ofrece **Quitar filtros**.

El encabezado no muestra la hora de la última actualización ni un indicador de «en vivo»:
se quitaron para no recargar la cabecera. La hora se sigue anunciando en la región activa
para lectores de pantalla, y si la suscripción falla aparece el aviso de que la
actualización automática no está disponible.

También, cuando corresponde, el **aviso de consulta atrasada**: una franja visible que
aparece si `Control_de_Ingesta__c.Ultima_Consulta_Exitosa__c` es demasiado antigua.

Ese aviso es la defensa contra dos fallos silenciosos: que la cadena de ingesta se rompa
sin que nadie se entere, y que el proveedor entero deje de responder. En los dos casos el
sistema seguiría pareciendo sano y la pantalla mostraría datos viejos como si fueran
actuales. No es una alarma, pero es la diferencia entre un operador que sabe que está
mirando datos de hace dos horas y uno que no.

### Tabla de equipos

Una fila por activo y medición, **agrupada por edificio**. Cada grupo abre con el nombre
del edificio, su ciudad y un resumen («2 críticos · 1 sin comunicación», o «Todo
normal»). Con el orden por severidad, el edificio que tiene lo más grave va primero. Cada
fila lleva a la izquierda una barra del color de su severidad. Las columnas:

| Columna | Qué muestra | De dónde sale |
| --- | --- | --- |
| Equipo | Ícono del tipo, nombre (enlace al activo), tipo y código | `Activo__c.Name`, `Tipo__c`, `Codigo_Externo__c` |
| Lectura | El valor con su unidad y, debajo, la medición. En una cámara, una ficha con el estado del corte: «Sin comunicación · 15 min», «Comunicación recuperada» o «En línea» | `Valor__c` y `Unidad__c` con los decimales del umbral; `Estado_Comunicacion__c` y `Gap_Segundos__c` |
| Severidad | La pastilla de color y, si el equipo volvió a lo normal con un caso abierto, la insignia «Normalizado · caso abierto» | `Severidad__c` y el caso abierto |
| Antigüedad | Cuánto hace que ocurrió | `Fecha_Origen__c` |
| Acción | Abrir intervención, o ir al incidente si ya existe | `puedeIntervenir` y el caso abierto |

**La columna Comunicación desapareció.** En casi todas las filas quedaba vacía, porque
solo las cámaras emiten conectividad, y una columna vacía parece un dato que falta. Ahora
la cámara dice su estado en su propia lectura, y una cámara sana también se nombra («En
línea») para que su fila no quede en blanco.

**La insignia de normalizado** responde a algo que parecía un error: un equipo en normal
con «Ver incidente». El caso sigue abierto porque cerrarlo es una decisión humana
([módulo 07](07-incidentes.md)); la insignia dice que el equipo ya volvió y que falta que
coordinación lo verifique y lo cierre. El caso abierto de una fila se busca por equipo y
medición, no por la clave: la clave de una cámara es su episodio, que el estado borra
cuando vuelve la comunicación, y así la fila sigue llevando al caso del último corte.

**El ícono** dibuja el tipo de equipo: bomba, gota (agua), rayo (energía), termómetro
(sala técnica) y cámara. Son SVG propios dentro del componente `iconoEquipo`, porque los
íconos de SLDS no tienen bomba ni medidor de agua. Son decorativos (`aria-hidden`): el tipo
va escrito al lado. La severidad la pinta `pastillaSeveridad`, que también usan los
resúmenes de las páginas de registro.

«Abrir intervención» solo aparece si el panel trae `puedeAbrir`, es decir, si la persona
puede crear casos ([módulo 10](10-seguridad-y-accesos.md)). El gerente ve «Ver incidente»
y nunca «Abrir intervención».

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
número, la ciudad y la condición del equipo, con Editar solo para quien puede editar el
caso y, solo para el coordinador, «Registrar intervención» y «Cerrar incidente», esta
última mientras el caso siga abierto. Debajo, el **resumen del
incidente**, «Lecturas del periodo» para quien lee la bitácora y tres secciones: Incidente,
con la descripción, «Cómo se resolvió» y el propietario; Lecturas, con
los campos que guarda el caso; y Equipo, con el activo, la medición, la ciudad y lo que ata
el caso a su señal (clave, episodio y origen). Al lado, la **historia del incidente**, con
las intervenciones abiertas y lo que pasó, y, para quien lee la bitácora, «Señales del
caso»: las últimas señales ligadas.

Esa lista es una lista relacionada dinámica, no una lista del formato de página. El perfil
de acceso mínimo no tiene formato de página asignado para Case, y una lista relacionada
normal solo se pinta si está en el formato de página del perfil: al coordinador no le salía.
La dinámica no depende del formato. Su encabezado cuenta lo que carga («5+»), no el total.

### La historia del incidente

El panel de actividad estándar mostraba «Upcoming & Overdue», en inglés, y no decía nada
de los cambios del caso: para saber qué se había hecho había que abrir cada tarea, y para
saber qué cambió, el historial. **Decisión: un componente propio, `historiaIncidente`, en
lugar del panel**, con dos partes:

- **Intervenciones abiertas**, primero la que vence antes, con su responsable, fecha
  límite, prioridad y estado. Quien puede registrarlas (el permiso
  `Nova_Casa_Registrar_Intervencion`) ve en cada una «Completar», que la deja Completada con
  `updateRecord` y los permisos de la persona; la historia se recarga y avisa si no se pudo.
- **Lo que pasó**, una línea de tiempo del más reciente al más viejo: la apertura, los
  cambios de prioridad, estado, severidad de la última lectura y condición del equipo, y
  las intervenciones completadas. Cada punto tiene su color (rojo si el cambio sube a
  alta o a crítico, azul para un cambio, verde para una intervención completada y gris
  para la apertura) y un texto para el lector de pantalla con el mismo dato, porque el
  color solo no basta.

Lo que escribe la integración o un flujo aparece como «Sistema»; lo que hace una persona,
con su nombre. Muestra los diez eventos más recientes y «Ver toda la historia» trae hasta
cien. Se recarga cuando la página se actualiza, por ejemplo al registrar una intervención.

Lee con `HistoriaIncidenteControlador`, `with sharing` y `WITH USER_MODE` como los
resúmenes: un caso que la persona no ve devuelve `null`. Los cambios salen del historial de
campos del caso, que ya seguía el estado, la prioridad y el propietario; la severidad de la
última lectura y la condición del equipo lo llevan desde el 22 de octubre de 2026, así que
los incidentes anteriores no muestran esos cambios antes de esa fecha. El estado y la
prioridad de las intervenciones muestran etiquetas en español (`TaskStatus` y
`TaskPriority`), con los valores de API intactos, como los del caso.

### El aviso de caso crítico

Cuando un incidente pasa a rojo, el operador de su ciudad y el coordinador reciben un
correo, y si a las 2 horas sigue abierto y en alta, el gerente recibe «Caso crítico sin
atender» en la campana. El botón del correo y la notificación abren la página del
incidente. Cómo se decide y a quién llega está en el [módulo 07](07-incidentes.md).

### Las lecturas del periodo

«Señales del caso» muestra solo las señales que cambiaron el incidente, con su resultado y
cuándo se recibieron, de la más reciente a la más vieja. Para ver todo lo
que midió el equipo mientras estuvo abierto, el coordinador y el administrador tienen
**«Lecturas del periodo»** (`lecturasPeriodo`), debajo del resumen:

- **Bajo demanda.** Entra cerrada y no consulta nada hasta que se pulsa «Ver lecturas».
- **Páginas de 50**, de la más nueva a la más vieja, con Primera, Anterior y Siguiente y el
  rango a la vista («Lecturas 51 a 100»). Una página ya vista no se vuelve a pedir.
- **Columnas:** la señal, con enlace a su registro; cuándo se recibió; la lectura; y el
  resultado en color, con el motivo debajo si lo hay. La hora del sensor no se muestra: el
  reloj del simulador va años adelantado. Sigue en el registro de la señal.
- **Todas las señales** del activo y de su tipo de mensaje entre la señal que abrió el
  incidente y su cierre (o ahora): aplicadas, atrasadas, rechazadas y las demás.
- Si el incidente empezó hace más de siete días, una línea recuerda que la bitácora guarda
  siete días de lecturas aplicadas y atrasadas, y que las que lo cambiaron siguen en
  «Señales del caso».

Quien no lee la bitácora (operador y gerente) no ve la tarjeta: el componente pregunta por
el objeto `Senal__c` con `getObjectInfo` y, si no tiene acceso, no se pinta.

La consulta va por el índice de `CreatedDate` y pagina por posición, sin `OFFSET`: la fecha
de creación de la última fila y los identificadores de ese mismo segundo que ya se
mostraron. El plan de consulta mostró por qué no se desempata con `ORDER BY CreatedDate,
Id`: con el segundo campo la plataforma deja el índice de fecha y recorre unas 222.000
señales del activo. Medido en la org con 2,28 millones de señales, una página tarda entre
59 y 92 ms en el servidor (851 ms una página de hace una semana), y en pantalla 0,9 s la
primera y 0,7 s la siguiente.

La lectura sale de `Senal__c.Lectura__c`, que escribe el procesamiento con los decimales
del umbral; una señal rechazada al recibir la guarda tal como llegó, con su unidad. Las
señales anteriores al 22 de octubre de 2026 no la tienen y muestran «—».

### Los resúmenes de las páginas de registro

Una página estándar muestra los campos de **su** registro; para saber cómo está el equipo
de un caso había que ir al activo, de ahí al estado y de ahí al umbral. **Decisión: cada
página que las personas visitan abre con un resumen en un componente propio**, que junta
lo de los registros relacionados y pinta la severidad con color, cosa que un campo estándar
no puede.

| Página | Componente | Qué junta |
| --- | --- | --- |
| Caso | `resumenIncidente` | El equipo con su ícono, edificio y ciudad; tres tarjetas: **lo abrió**, **último cambio** y **ahora** (el estado actual en vivo), cada una con su severidad; y el aviso de normalizado si el equipo volvió y el caso sigue abierto |
| Activo | `resumenActivo` | La severidad del equipo, cómo está cada medición, sus incidentes abiertos con su condición y la regla de bandas de los límites que se le aplican |
| Edificio | `resumenEdificio` | Cuántos equipos hay en cada severidad, cada equipo con ícono, lectura y severidad, y los incidentes abiertos de todo el edificio con su última lectura |
| Umbral | `bandasUmbral` | Las bandas dibujadas como una regla: crítico, advertencia, normal, advertencia y crítico con sus fronteras; en una cámara, los minutos sin señal |
| Señal | `resultadoSenal` | El resultado en color, el motivo, si se puede reintentar, cuántas veces llegó y qué significa ese resultado |

Los tres primeros leen con `ResumenRegistroControlador`, que es `with sharing` y consulta con
`WITH USER_MODE`, igual que el monitor: si la persona no ve el registro, devuelve `null` y
el componente no muestra nada.

**Las fechas de los resúmenes son las del sistema, no las del sensor.** El reloj del
simulador avanza un minuto por mensaje y va años adelantado, y en un resumen esa fecha
confunde. Qué lectura es más reciente se sigue decidiendo por la hora del sensor; solo cambia
lo que se muestra:

- **Lo abrió:** cuándo se creó el caso, segundos después de llegar la lectura que lo abrió.
- **Último cambio** y el aviso de normalizado: la última vez que cambiaron la severidad o la
  condición del caso, desde su historial (`CaseHistory`, en `USER_MODE`). Es la misma hora
  de la última fila de «Historia del incidente». Sin cambios, es la apertura. Un caso
  normalizado no vuelve a cambiar hasta que falla otra vez, así que su último cambio es el
  de normalizarse.
- **Ahora** y las mediciones del activo y del edificio: la antigüedad cuenta desde
  `Fecha_Actualizacion__c`, cuando se escribió el estado.

Los campos del caso (`Fecha_Lectura_Apertura__c`, `Fecha_Ultima_Lectura__c`,
`Normalizado_En__c`) siguen guardando la hora del sensor, como evidencia, en la sección de
campos. Los dos últimos leen con LDS (`getRecord`), que ya aplica
los permisos de campo. Las secciones de campos de cada página siguen debajo, para quien
necesite el dato exacto o editar.

Se descartaron las fórmulas con `IMAGE()`: dan un semáforo también en las vistas de lista,
pero con imágenes antiguas y sin texto, y no juntan registros relacionados.

Se resolvió en una sola página, sin pestañas ni navegación intermedia, porque el operador
llega aquí desde una alarma: quiere saber qué pasa y qué se está haciendo, y cada clic
intermedio es tiempo entre el aviso y la acción.

No hay componente propio para los campos del caso. La página de Lightning ya aplica la
compartición por ciudad y los permisos de campo. Por eso el servidor no expone una lectura
del caso; la historia solo lee el historial y las intervenciones.

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

El componente se suscribe, mediante la biblioteca de mensajería empresarial del navegador,
a un evento de plataforma propio: `Panel_Actualizado__e`. El procesamiento lo publica
cuando una tanda escribe estados, como mucho una vez cada 30 segundos, y también suena al
cerrar un incidente. **No lleva ningún campo: solo dice «hay estados nuevos».** El componente lo usa como señal para volver a pedir los datos al servidor.

Y aquí está la decisión más importante del módulo: **la pantalla nunca recibe datos por el
canal de eventos.** El motivo es una frontera de seguridad. **El canal de eventos de
plataforma no filtra por permisos.** Un suscriptor recibe todos los eventos publicados, con
independencia de a qué registros tenga acceso, y para suscribirse Salesforce le exige leer
el evento. Si el monitor escuchara `Aviso_de_Senal__e`, el evento de la ingesta, habría que
dar a operadores, coordinador y gerente lectura sobre códigos, valores y fechas de las dos
ciudades: aunque la tabla no los pintara, cualquiera con las herramientas de desarrollo del
navegador los vería pasar. Un timbre vacío no tiene nada que filtrar.

Al volver a consultar con cada timbre, el filtro de autorización del servidor se aplica
**siempre**, en cada refresco, sin que el componente tenga que acordarse de nada. Es el
riesgo R-07 y está resuelto por construcción, no por disciplina.

El coste de este diseño es una consulta extra por cada ráfaga de timbres. Una tanda de
doscientos mensajes ya produce uno solo, y la **espera de dos segundos** agrupa además las
tandas que llegan seguidas: el componente hace una sola consulta por ventana.

La suscripción se cancela al desmontar el componente, para no dejar conexiones abiertas
cuando el operador navega a otra parte.

### Cuidar las entregas del timbre

Cada monitor abierto recibe cada timbre, y la org tiene un límite de **75.000 entregas de
eventos por día**. Con un timbre por tanda sonaba hasta 6 veces por minuto (8.640 al día):
alcanzaba para unos 8 monitores abiertos todo el día. **Decisión: como mucho un timbre cada
30 segundos, por ventanas fijas, y ninguna entrega a una pestaña oculta.**

- **Ventanas fijas de 30 s.** Antes de guardar los estados de la tanda, el procesamiento lee
  la última modificación de `Estado_Actual__c` (unas 20 filas, una por equipo y medición).
  Si cayó en otra ventana de 30 segundos, la tanda toca el timbre; si cayó en la misma, ya
  tocó otra antes. Así suena la primera tanda de cada ventana: 2.880 timbres al día como
  máximo, que alcanzan para unos 26 monitores. Lo que cambie después dentro de la misma
  ventana lo recoge el timbre siguiente o la vigilancia de un minuto.
- **Pestaña oculta.** Con la pestaña oculta el monitor cancela la suscripción y la
  vigilancia; al volver se suscribe otra vez y se pone al día con una consulta.
- **Al cerrar un incidente.** El flujo `Avisar_Monitor_Al_Cerrar` publica el timbre, para
  que «Ver incidente» y «Normalizado · caso abierto» desaparezcan en segundos.

| Alternativa | Por qué no |
|---|---|
| «Hace menos de 30 s» desde el último timbre | Con la ingesta continua siempre hay una tanda reciente: no tocaría nunca |
| Guardar la hora del último timbre (caché de plataforma, configuración o el control de ingesta) | Una escritura o una partición de caché más; el control además lo bloquea la ingesta cada minuto |
| Seguir con un timbre por tanda | Agota el límite de entregas con unos 8 monitores abiertos |

Si la suscripción falla, el monitor lo dice. Cuando la biblioteca informa un error o la
suscripción no se completa, aparece bajo el título una línea discreta: la actualización
automática no está disponible, y el monitor se revisa solo cada minuto y con el botón
**Actualizar**. La región activa la anuncia una vez. Si después llega un timbre, la línea
desaparece. Sin este aviso el operador cree que ve tiempo real cuando solo ve la
vigilancia: fue lo que pasó mientras los roles humanos no podían leer el evento.

### La vigilancia de un minuto

Los timbres solo llegan mientras la ingesta trae señales. Si la cadena se para, no hay
timbres, no hay consultas y la pantalla abierta se congela: la antigüedad seguiría diciendo
«hace 3 min» y el aviso de consulta atrasada no aparecería nunca, porque los dos los
calcula el servidor al consultar.

Por eso el componente tiene una **vigilancia**: si pasa un minuto sin ninguna consulta, por
botón, por timbre o por la propia vigilancia, vuelve a pedir el panel. Cada consulta
reinicia el minuto, así que con la ingesta al día la vigilancia casi nunca llega a
dispararse. Con la ingesta parada, a los cinco minutos de la última consulta exitosa el
servidor marca el panel como atrasado y la franja aparece sola. La regla de que nada se
calcula en el navegador se mantiene: la vigilancia solo decide cuándo preguntar.

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
  de modo que un lector de pantalla informe de que la tabla se refrescó. Al pulsar
  «Actualizar» o cambiar de edificio anuncia «Actualizando el monitor»; tras cada consulta
  por botón o por timbre, «Monitor actualizado a las HH:MM», con la hora para que el texto
  cambie y se vuelva a leer; si falla, el error. La vigilancia de un minuto consulta en
  silencio y solo habla si el aviso de atraso aparece o desaparece.
- El contraste cumple el mínimo de la norma para texto y para los indicadores de severidad.

## La identidad visual

Cubre el **issue #15**. El componente del operador ya usaba la paleta del prototipo; lo
que faltaba era que la aplicación que lo contiene también la usara, para que no pareciera
pegado encima de algo ajeno.

### Tema de la org y marca de la aplicación

Salesforce separa dos cosas. El **tema** es de la org entera: barra superior, logo,
fondo y color de enlaces y botones. La **marca de la aplicación** es el logo y el color
de una aplicación concreta, y solo se ve si la aplicación pide sobrescribir el tema. Las
cuatro apps por rol llevan la misma marca.

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
| `contentassets/NovaCasaLogoHorizontal` | Logo de la barra y de la pantalla de carga, 600 × 120: la proporción 5:1 de la caja de 200 × 40 donde Salesforce lo muestra; con otra proporción lo recorta |
| `contentassets/NovaCasaFondoEncabezado` | Fondo del encabezado, 1800 × 360 |
| `contentassets/NovaCasaLogoApp` | La casa sola, 256 × 256, sobre blanco y con un 15 % de margen, para la aplicación |
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

Los colores de severidad se fijan en `pastillaSeveridad.css` y `monitorDeActivos.css` en
lugar de tomarse de los ganchos del sistema de diseño: crítico `#ba0517` sobre `#fef1ee`,
advertencia `#8c4b02` sobre `#fef4e6` y normal `#22683e` sobre `#ebf7e6`. La advertencia y
el normal son más oscuros que antes porque ahora van sobre un fondo tenue, no sobre blanco.
Sin comunicación es morado (`#5a1ba9`) y la comunicación recuperada y la insignia de
normalizado, azul (`#0b5cab`). Así un cambio de tema, o volver a Cosmos, no los mueve. Lo
que no es severidad (bordes, fondos, texto suave) usa los ganchos de SLDS con un valor de
respaldo.

### El pulso de la severidad

**Decisión: la pastilla de advertencia y la de crítico pulsan, y la de crítico más rápido**,
para que lo grave se note sin leer la tabla. Es un anillo que crece alrededor de toda la
pastilla y se desvanece; el texto y el punto no se mueven.

- Advertencia cada 2 segundos y crítico cada 0,8 segundos: 1,25 pulsos por segundo, lejos
  de los 3 destellos por segundo que las pautas de accesibilidad ponen como máximo.
- Se apaga si el sistema de la persona pide reducir movimiento.
- El monitor trae el botón «Detener animación», con `aria-pressed`, porque las pautas piden
  poder detener lo que se mueve más de 5 segundos. La elección se recuerda en el navegador
  y vale para todas las pastillas, también las de los resúmenes del incidente, el activo y
  el edificio, que se enteran al momento si están abiertas.
- Es una sombra y no una escala, para que crezca lo mismo a lo alto que a lo ancho.

| Alternativa | Por qué no |
|---|---|
| Que parpadee toda la pastilla, fondo y texto | Es lo más visible, pero cansa y distrae en un monitor con varios críticos |
| Pulsar solo 5 segundos al cambiar de severidad | Cumple las pautas sin botón, pero un crítico que ya estaba no se notaría |
| Pulsar solo el punto de color | Se veía poco; se pidió el anillo alrededor de la pastilla |

Los campos estándar de Salesforce, como la severidad en las secciones de campos de una
página de registro, no se pueden animar: el pulso está en el componente compartido
`pastillaSeveridad` y en el módulo `animacionSeveridad`, que guarda la elección.

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
Estados actuales, Umbrales, Señales, Control de ingesta y Paneles. No lleva Inicio: la de
fábrica es la página de ventas. Cada usuario ve solo las de los objetos que tiene, y
Paneles solo gerente y coordinador. Informes no está en la barra: el perfil mínimo la
muestra a todos, y el operador vería una pestaña que no puede usar. Al informe se llega
desde «Ver informe», en cada gráfico del panel. Quien ya hubiera personalizado su barra conserva su orden.

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
