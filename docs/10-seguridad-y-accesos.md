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

El acceso a esa credencial se concede por conjunto de permisos y ese conjunto **se asigna
solo al usuario de integración**. Ningún operador puede hacer la llamada al proveedor,
aunque conozca el endpoint.

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

Las clases de ingesta y de procesamiento se declaran `without sharing`, deliberadamente y
con un comentario que lo explique. Tienen que poder escribir el estado de cualquier activo
con independencia de a quién se le haya compartido, porque no actúan en nombre de ninguna
persona. **Esa es la única excepción del sistema, y está acotada a clases que ningún
componente de interfaz puede invocar.**

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

| Objeto | Operador | Coordinador | Gerente | Administrador |
| --- | --- | --- | --- | --- |
| `Edificio__c` | Leer | Leer | Leer | Todo |
| `Activo__c` | Leer | Leer | Leer | Todo |
| `Estado_Actual__c` | Leer | Leer | Leer | Todo |
| `Umbral__c` | Leer | Leer, editar | Leer | Todo |
| `Senal__c` | — | Leer | — | Leer |
| `Control_de_Ingesta__c` | — | — | — | Leer, editar |
| `Case` | Leer, crear | Leer, crear, editar | Leer | Todo |
| `Task` | Leer, crear | Leer, crear, editar | Leer | Todo |

Dos ausencias que son decisiones, no olvidos.

**El operador no ve la bitácora.** Su trabajo es reconocer el estado de sus equipos y abrir
intervenciones, no investigar por qué se rechazó un mensaje. Darle acceso añadiría ruido a
su experiencia y ampliaría la superficie de exposición sin ningún beneficio. Es además lo
que pide el criterio de US-209 sobre restringir la vista de investigación a personas
autorizadas.

**Nadie borra nada, salvo el administrador.** La bitácora es un registro de auditoría y un
registro de auditoría que se puede borrar no es un registro de auditoría. Ni siquiera el
administrador tiene borrado masivo desde la interfaz.

### Acceso a registros

| Objeto | Valor por defecto | Cómo se amplía |
| --- | --- | --- |
| `Edificio__c` | Privado | Reglas de compartición por ciudad y grupos de operadores |
| `Activo__c` | Controlado por el edificio | Hereda, por la relación principal-detalle |
| `Estado_Actual__c` | Controlado por el activo | Hereda, por la relación principal-detalle |
| `Umbral__c` | Lectura y escritura públicas | El botón de editar lo controla el permiso de objeto, no el dueño |
| `Senal__c` | Privado | «Ver todo» para administrador y coordinador. Solo el administrador ve `Carga__c` y `Detalle__c` |
| `Case` | Privado | Colas y jerarquía de funciones |

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

**Decisión: se crean cuatro usuarios de prueba en el código de pruebas, uno por rol, y las
pruebas de la capa de consulta se ejecutan dentro de `System.runAs`.**

Lo que cada prueba verifica:

| Prueba | Afirma |
| --- | --- |
| Operador con un edificio | Solo ve los estados de ese edificio |
| Operador con otro edificio | No ve los del primero, y el resultado es vacío, no un error |
| Operador sobre umbrales | Puede leer, **no** puede editar |
| Coordinador sobre umbrales | Puede editar |
| Operador sobre la bitácora | No tiene acceso |
| Administrador sobre la bitácora | Ve todas las señales |
| Operador sobre `Carga__c` | El campo no viene en la respuesta |
| Ingesta sin usuario | Procesa y escribe correctamente |

La penúltima es la que más veces se olvida y la que más vale: comprueba que la seguridad a
nivel de campo funciona de verdad, no solo la de registro.

La última verifica la segunda frontera: que el procesamiento no dependa de que haya una
persona con permisos detrás.

## El resumen en una frase

Tres fronteras independientes, un usuario de integración que no es una persona, `with
sharing` más `WITH USER_MODE` en todo lo que toca un humano, `without sharing` solo en las
clases que ninguna interfaz puede invocar, y pruebas con usuarios reales que fallan si algo
de esto se rompe.
