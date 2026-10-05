# 10 · Seguridad y accesos

Cubre **US-208 · Respetar la autorización del usuario**.

## El concepto de base: Apex no respeta permisos por defecto

Es la propiedad de la plataforma que más defectos de seguridad produce, y conviene
enunciarla sin rodeos: **Apex se ejecuta por defecto en modo de sistema.** Ignora el
perfil, los conjuntos de permisos, la seguridad a nivel de campo y las reglas de
compartición. Una consulta escrita sin cuidado devuelve todos los registros de la
organización, y el componente que la llama mostrará datos que el usuario no debería ver.

No es un error que se note. La pantalla funciona, los datos aparecen, nadie se queja. Solo
se descubre cuando alguien prueba con un usuario de permisos reducidos, que es exactamente
lo que pide el criterio de US-208.

Hay tres capas de control y son independientes. Confundirlas es la segunda fuente de
defectos.

**Objeto.** Si este usuario puede leer, crear, editar o borrar este tipo de registro. Se
concede con conjuntos de permisos.

**Campo.** Si puede ver o editar un campo concreto. Un usuario con lectura sobre el objeto
puede tener oculto un campo.

**Registro.** Cuáles de los registros de ese objeto puede ver. Se gobierna con el modelo de
compartición: valor por defecto de la organización, jerarquía de funciones, reglas de
compartición y compartición manual.

Las tres se activan con mecanismos distintos y ninguna implica a las otras.

## Las herramientas y cuándo se usa cada una

| Mecanismo | Qué controla | Notas |
| --- | --- | --- |
| `with sharing` en la clase | Registro | **No** controla objeto ni campo. Es el error más común |
| `WITH USER_MODE` en la consulta | Objeto, campo y registro | La forma moderna y preferida |
| `Security.stripInaccessible` | Campo | Para datos que no vienen de una consulta |
| `as user` en DML | Objeto, campo y registro al escribir | Equivalente de `USER_MODE` para escritura |

`with sharing` es necesario pero **no suficiente**. Una clase `with sharing` que consulte
sin `WITH USER_MODE` respeta qué registros ve el usuario pero le devuelve todos los campos,
incluidos los que tiene ocultos.

**Decisión: todas las clases expuestas al usuario se declaran `with sharing` y todas sus
consultas llevan `WITH USER_MODE`.** Las dos cosas, siempre, sin excepciones que haya que
recordar.

```apex
public with sharing class MonitorControlador {
    @AuraEnabled(cacheable=true)
    public static PanelDTO obtenerPanel(String edificioId) {
        List<Estado_Actual__c> estados = [
            SELECT Id, Tipo_Medicion__c, Valor__c, Unidad__c, Severidad__c,
                   Fecha_Origen__c, Estado_Comunicacion__c,
                   Activo__r.Name, Activo__r.Edificio__r.Name
            FROM Estado_Actual__c
            WHERE Activo__r.Edificio__c = :edificioId
            WITH USER_MODE
            ORDER BY Severidad_Nivel__c DESC, Fecha_Origen__c ASC
        ];
        // ...
    }
}
```

`WITH USER_MODE` lanza una excepción si el usuario no tiene acceso a un campo de la
consulta, en lugar de devolverlo vacío. Es lo correcto: un fallo ruidoso en desarrollo vale
más que una fuga silenciosa en producción.

## Las tres fronteras

La seguridad de este sistema no está en un solo sitio. Hay tres fronteras y cada una tiene
su control, de modo que saltarse una no abra las demás.

### Frontera 1 · La salida hacia el proveedor

Las credenciales viven en una External Credential y se invocan por Named Credential, según
el [módulo 02](02-ingesta.md). El código nunca ve el token y rotarlo no implica desplegar.

El acceso a esa credencial se concede por conjunto de permisos y **solo lo tienen dos**:
`Nova_Casa_Integracion` y `Nova_Casa_Administracion`. Ningún operador, coordinador ni
gerente puede hacer la llamada al proveedor, aunque conozca el endpoint. El administrador
lo necesita porque programar la ingesta es una acción suya, y un trabajo programado corre
como quien lo programó.

### Frontera 2 · El proceso de ingesta

El proceso corre con su propia autorización, **independiente del contexto de cualquier
persona**. Es un criterio literal de US-208 y tiene una consecuencia práctica importante:
que el proceso funcione no exige que ningún usuario humano tenga permisos elevados.

Se materializa en un **usuario de integración** con un conjunto de permisos propio, que le
da exactamente lo que necesita y nada más:

| Recurso | Acceso |
| --- | --- |
| `Senal__c` | Crear, leer, editar |
| `Estado_Actual__c` | Crear, leer, editar |
| `Control_de_Ingesta__c` | Leer, editar |
| `Umbral__c` | Solo leer |
| `Edificio__c`, `Activo__c` | Solo leer |
| `Case` | Crear, leer, editar |
| `Aviso_de_Senal__e` | Publicar y suscribirse |
| Named Credential del simulador | Acceso |

No tiene borrado sobre nada. No tiene acceso a la configuración del sistema. Y no es un
usuario con el que nadie inicie sesión.

**Quién ejecuta cada parte.** El procesamiento, que es el disparador de
`Aviso_de_Senal__e`, corre como el usuario de integración. Lo fija un
`PlatformEventSubscriberConfig` que crea `./scripts/configurar-suscriptor.sh`: sin él, el
disparador correría como Automated Process, un usuario al que no se le pueden quitar
permisos. No va como metadato porque lleva escrito el Username, que cambia en cada org. La
llamada al proveedor la hace la cadena `IngestaQueueable`, que corre como quien programó
la ingesta: el administrador, que es quien tiene la credencial. Así, las señales que se
deciden al llegar (rechazadas, en conflicto) quedan a nombre del administrador y las que se
aplican después, a nombre de integración.

Las clases de ingesta y de procesamiento se declaran `without sharing`, deliberadamente y
con un comentario que lo explique. Tienen que poder escribir el estado de cualquier activo
con independencia de a quién se le haya compartido, porque no actúan en nombre de ninguna
persona. **Es la excepción del sistema, y está acotada a clases que ningún componente de
interfaz puede invocar.** Hay una segunda, más estrecha: la escritura de Aplicar límites,
descrita en [Las acciones](#las-acciones). Corre después de comprobar que quien la pide
edita umbrales, y solo sobre estados que ya leyó con su compartición.

### Frontera 3 · La consulta del operador

Descrita arriba: `with sharing` más `WITH USER_MODE`. Un equipo no autorizado no aparece,
ni siquiera si alguien manipula la petición desde el navegador para pedir otro edificio.

Es importante que el filtro esté en el servidor y no en el parámetro. El componente manda
un identificador de edificio, pero **la consulta no confía en él**: `WITH USER_MODE` aplica
la compartición por encima de cualquier filtro que venga del cliente. Si el operador pide
un edificio que no tiene, el resultado es vacío, no un error que revele que existe.

### Y dos más que conviene contar aparte

**Los contadores y resúmenes** se calculan en el servidor sobre los registros que esa
persona puede ver. Calcularlos en el navegador delataría la existencia de registros
ocultos, según el [módulo 09](09-experiencia-del-operador.md).

**La bitácora** guarda el mensaje y el motivo del rechazo, pero **nunca credenciales ni
secretos del proveedor**. La carga que se almacena es el cuerpo del mensaje, no la petición
completa: las cabeceras, y con ellas el token, no se guardan jamás.

## La matriz de acceso

Esta es la matriz que pide US-208. La parte de umbrales viene del cliente; el resto se
deriva de ella y de los roles del discovery, y queda como propuesta a validar.

### Acceso a los umbrales · confirmado por el cliente

| Persona | Acceso a los umbrales |
| --- | --- |
| Operador de edificios | Consulta el estado y los límites aplicados, **no los modifica** |
| Coordinador de mantenimiento | **Modifica** los límites de los activos bajo su responsabilidad |
| Gerente regional | Consulta límites y resultados de su región. La edición es opcional |
| Administrador de Salesforce | Acceso completo, incluida la configuración |

Sobre la edición para gerencia: **decisión de no concederla.** La edición de umbrales es
una responsabilidad operativa del coordinador, y dar la misma capacidad a dos roles con
criterios distintos produce valores que cambian sin que nadie sepa quién ni por qué. El
gerente tiene lectura completa y el historial de cambios, que es lo que necesita para
supervisar. Si el cliente prefiere lo contrario, es marcar una casilla en un conjunto de
permisos.

### Acceso a objetos

| Objeto | Operador | Coordinador | Gerente | Administrador | Integración |
| --- | --- | --- | --- | --- | --- |
| `Edificio__c` | Leer | Leer | Leer | Todo | Leer |
| `Activo__c` | Leer | Leer | Leer | Todo | Leer |
| `Estado_Actual__c` | Leer | Leer | Leer | Todo | Crear, leer, editar |
| `Umbral__c` | Leer | Leer, editar | Leer | Todo | Leer |
| `Senal__c` | — | Leer, sin `Carga__c` ni `Detalle__c` | — | Leer, entera | Crear, leer, editar |
| `Control_de_Ingesta__c` | Solo la última consulta | Solo la última consulta | Solo la última consulta | Leer, editar | Leer, editar |
| `Case` | Leer, crear | Leer, crear, editar | Leer | Todo | Crear, leer, editar |
| `Task` | Leer, crear, editar las suyas | Leer, crear, editar | Leer | Todo | — |

«Solo la última consulta» es `Ultima_Consulta_Exitosa__c`, la fecha que necesita el aviso
de ingesta atrasada del monitor. El cursor, la semilla y el resto del control siguen
ocultos.

Crear tareas exige además el permiso de usuario «Edit Tasks»: el permiso de objeto sobre
`Task` no basta. Sin él, la nota con la que el operador abre una intervención se perdía en
silencio. Salesforce no separa crear de editar tareas, así que el operador también puede
editar sus propias notas; las de otros no, porque no edita el caso.

Dos ausencias que son decisiones, no olvidos.

**El operador no ve la bitácora.** Su trabajo es reconocer el estado de sus equipos y abrir
intervenciones, no investigar por qué se rechazó un mensaje. Darle acceso añadiría ruido a
su experiencia y ampliaría la superficie de exposición sin ningún beneficio. Es además lo
que pide el criterio de US-209 sobre restringir la vista de investigación a personas
autorizadas.

**Nadie borra la bitácora, ni el administrador.** La bitácora es un registro de auditoría y
un registro de auditoría que se puede borrar no es un registro de auditoría. El
administrador la lee entera, con carga y detalle, y no la edita: corregir una señal a mano
borraría la prueba de lo que pasó. El control de ingesta sí lo edita (escenario, tanda,
reactivarlo), pero no lo crea ni lo borra: es un registro único.

### Acceso a registros

| Objeto | Valor por defecto | Cómo se amplía |
| --- | --- | --- |
| `Edificio__c` | Privado | Reglas de compartición por ciudad y grupos de operadores |
| `Activo__c` | Controlado por el edificio | Hereda, por la relación principal-detalle |
| `Estado_Actual__c` | Controlado por el activo | Hereda, por la relación principal-detalle |
| `Umbral__c` | Lectura y escritura públicas | El botón de editar lo controla el permiso de objeto, no el dueño |
| `Senal__c` | Privado | «Ver todo» para administrador, coordinador e integración. Solo el administrador ve `Carga__c` y `Detalle__c` |
| `Control_de_Ingesta__c` | Lectura y escritura públicas | Como en `Umbral__c`: edita quien tiene el permiso de objeto, administración e integración |
| `Case` | Privado | Reglas por `Case.Ciudad__c` hacia los grupos de operadores. Coordinador y gerente con «ver todo» |

**El edificio es la unidad de autorización de todo el sistema.** Un operador tiene
edificios asignados y de ahí hereda el acceso a sus activos y a sus estados, sin que haya
que configurar nada más.

Esa herencia es gratuita y automática, y es consecuencia directa de haber elegido
relaciones principal-detalle en el [módulo 03](03-modelo-de-datos.md). Con relaciones de
búsqueda habría que mantener reglas de compartición en tres objetos y mantenerlas
sincronizadas, que es donde aparecen los agujeros.

**Q-10, resuelta para la demostración: por ciudad.** Hay dos grupos públicos
(`Operadores_Bogota`, `Operadores_Barranquilla`) y una regla de compartición por
`Edificio__c.Ciudad__c`. El operador de Bogotá solo está en el primer grupo; el de
Barranquilla, solo en el segundo. Coordinador y gerente están en los dos, porque tienen
que ver ambas ciudades. Si más adelante el cliente prefiere asignar edificio a edificio,
se cambia la membresía del grupo: el mecanismo de la regla no cambia.

`Umbral__c` quedó en lectura y escritura públicas, no en solo lectura. Con solo lectura el
coordinador no podría editar umbrales que sembró otro usuario, que es justo el caso de la
demo. El operador sigue sin botón de editar porque su conjunto no concede edición de
objeto.

`Control_de_Ingesta__c` sigue el mismo razonamiento. Privado con editar y «ver todo», el
administrador solo editaría los controles que fueran suyos, y el registro lo crea quien
siembra el entorno. «Modificar todo» lo resolvería, pero exige borrar, y el control no se
borra.

**`Case` es privado y se comparte por ciudad.** Estaba en lectura y escritura públicas,
el valor de fábrica de la org: el operador de Bogotá abría por su Id los casos de Caribe
aunque no viera el edificio. Las reglas por criterio no aceptan fórmulas, así que
`Case.Ciudad__c` es un texto que escribe el disparador `CaseCiudad` desde el edificio del
activo, al crear y al actualizar. No se toma lo que traiga el registro: si no, quien crea el
caso elegiría qué grupo lo ve. Un caso sin activo no tiene ciudad y solo lo ven su dueño y
quien tiene «ver todo». La regla concede edición, que es lo que deja al coordinador editar
casos de las dos ciudades. El operador no los edita porque su conjunto no lo concede.

Que un caso crítico sea de la cola **Coordinación** no cambia quién lo ve: la regla por
ciudad no mira el propietario, así que el operador de esa ciudad lo sigue viendo. Ser
miembro de la cola es lo que le permite al coordinador aceptarlo y tomarlo.

## Las acciones

Ver no basta: cada acción comprueba también quién la pide, en el servidor.

| Acción | Quién | Cómo se impide al resto |
| --- | --- | --- |
| Abrir intervención, en el monitor | Operador y coordinador | `abrirIntervencion` lee el estado con `USER_MODE` y crea caso y nota con `USER_MODE`. Sobre un equipo ajeno responde que no existe |
| Aplicar límites | Quien edita `Umbral__c`: coordinador y administrador | `UmbralAplicacionServicio.aplicar` lo comprueba antes de nada y lanza `SinPermisoException` |
| Programar la ingesta | Administrador | Es quien tiene la credencial. `./scripts/programar-ingesta.sh` |
| Procesar avisos | Usuario de integración | `./scripts/configurar-suscriptor.sh` |

Aplicar límites dependía de que el botón no estuviera en la página del operador. Llamada
desde Apex, la habría ejecutado cualquiera con lectura. Y fallaba justo a quien debía
poder usarla: la clase es `with sharing`, y en una clase así la escritura en modo de
sistema comprueba igual la compartición. Editar un estado actual, que es detalle del activo
y este del edificio, exige editar el edificio, y el coordinador solo lo lee. La lectura
sigue `with sharing`; la escritura va en una clase interna `without sharing`, después de
la comprobación.

## Los campos sensibles

Dos campos de `Senal__c` merecen tratamiento propio.

`Carga__c` guarda el JSON original del mensaje. No contiene secretos por construcción,
pero contiene todo lo que mandó el proveedor. **Solo visible para el administrador.**

`Detalle__c` puede contener el texto de un error de la plataforma. **Solo visible para el
administrador**, por la misma razón: un mensaje de error revela detalles de implementación
que no aportan nada a un usuario de negocio.

Cuando un campo está oculto para un perfil, `WITH USER_MODE` hace que la respuesta del
servidor **no lo incluya**. La pantalla no tiene que acordarse de esconderlo, que es la
clase de cosa que se olvida al añadir una columna.

## Cómo se prueba

El criterio de US-208 pide probar con dos usuarios de permisos diferentes. La prueba tiene
que estar escrita, no ser una comprobación manual en la demo.

**Decisión: cada prueba crea su usuario en el código de pruebas, con el perfil de acceso
mínimo y un solo conjunto de permisos, y corre dentro de `System.runAs`.** En prueba, la
pertenencia a los grupos no se recalcula a tiempo, así que el edificio se comparte a mano
con un `Edificio__Share`. Las reglas por ciudad se comprueban en la org.

Lo que cada prueba verifica. Salvo las dos primeras filas, están en `SeguridadAccesosTest`:

| Prueba | Método | Afirma |
| --- | --- | --- |
| Operador con un edificio | `MonitorControladorTest.shouldMostrarSoloSuCiudad_WhenOperadorBogota` | Solo ve los estados de ese edificio |
| Operador sobre la bitácora | `TrazabilidadTest.shouldOcultarBitacora_WhenOperador` | No tiene acceso |
| Operador con otro edificio | `shouldDevolverVacio_WhenOperadorPideOtroEdificio` | Pedir Caribe da vacío y contadores en cero, no un error |
| Operador llamando a Apex | `shouldNegarCasoYEquipo_WhenOperadorLosPideDirectoAApex` | En modo usuario no le llega el caso de Caribe, y abrir intervención sobre su equipo falla; no se crea nada |
| Operador sobre umbrales | `shouldLeerSinEditarNiAplicar_WhenOperadorSobreUmbrales` | Lee, **no** edita, y Aplicar límites lo rechaza |
| Coordinador sobre umbrales | `shouldEditarYAplicar_WhenCoordinadorSobreUmbrales` | Edita y aplica: la bomba pasa a crítico |
| Administrador sobre la bitácora | `shouldVerTodaSinEditarNiBorrar_WhenAdministradorSobreBitacora` | Ve todas, con carga y detalle; no edita ni borra |
| Coordinador sobre `Carga__c` | `shouldOmitirCargaYDetalle_WhenCoordinadorLeeBitacora` | Lee la bitácora; `Carga__c` y `Detalle__c` no vienen |
| Administrador sobre el control | `shouldEditarControlAjeno_WhenAdministradorYNoCoordinador` | Edita un control que no es suyo; el coordinador no |
| Ingesta como integración | `shouldProcesarYEscribir_WhenUsuarioDeIntegracion` | Solo con su conjunto, guarda, aplica y abre el caso con ciudad |
| Ciudad del caso | `shouldSellarCiudadDelActivo_WhenCasoSeGuardaOCambia` | La ciudad sale del activo, no de lo que se escriba |

La de `Carga__c` es la que más veces se olvida y la que más vale: comprueba que la
seguridad a nivel de campo funciona de verdad, no solo la de registro. Se hace con el
coordinador y no con el operador: el operador no tiene la bitácora, así que con él solo se
probaría el acceso al objeto. El coordinador sí lee las señales y aun así no recibe la
carga.

La de integración verifica la segunda frontera: que el procesamiento no dependa de que
haya una persona con permisos detrás.

## El resumen en una frase

Tres fronteras independientes, un usuario de integración que no es una persona, `with
sharing` más `WITH USER_MODE` en todo lo que toca un humano, `without sharing` solo en las
clases que ninguna interfaz puede invocar, y pruebas con usuarios reales que fallan si algo
de esto se rompe.
