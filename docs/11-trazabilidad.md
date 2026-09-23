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

Toda `Senal__c` tiene exactamente uno de estos siete valores en `Resultado__c`. No hay
señales sin resultado.

| Resultado | Qué significa | ¿Tocó el estado? | ¿Reintentar? |
| --- | --- | --- | --- |
| **Pendiente** | Se recibió y se publicó. El procesamiento no ha terminado | No | — |
| **Aplicado** | Actualizó el estado. Puede haber abierto o escalado un incidente | Sí | Sí, sin efecto |
| **Duplicado** | La clave ya estaba procesada, con contenido idéntico | No | Sí, sin efecto |
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

**Conflicto** es el único que exige una persona. El sistema recibió dos afirmaciones
contradictorias sobre el mismo hecho y no tiene forma de saber cuál es cierta. Reintentar
no aporta nada: seguirían siendo contradictorias.

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
| ¿Qué se rechazó hoy y por qué? | Filtrar por resultado y fecha, agrupar por motivo |
| ¿Cuáles puedo reintentar? | Filtrar por `Reintentable__c` |
| ¿Qué llegó duplicado? | Filtrar `Entregas__c` mayor que uno |
| ¿Hay conflictos sin resolver? | Filtrar por resultado conflicto |
| ¿Algo se quedó atascado? | Filtrar pendientes con recepción antigua |
| ¿Qué mensaje abrió este caso? | Desde el caso, `Origen_Senal__c` |
| ¿Este mensaje generó un caso? | Desde la señal, `Incidente__c` |
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
| Atascadas | Resultado pendiente, recepción hace más de una hora |
| Últimas 24 horas | Recepción en el último día, ordenada descendente |

Una vista de lista estándar trae de fábrica búsqueda, filtros, ordenación, exportación,
gráficos y acceso desde el móvil. Construir un componente a medida sería reemplazar todo
eso por menos.

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
  hijos son pocos.
- **Los campos por los que se filtra están indexados**: `Clave__c` y `Message_Id__c` por ser
  External ID, y `Fecha_Recepcion__c` y `Resultado__c` como índices adicionales.

Queda abierta Q-11: si se conserva todo el histórico o hay una política de retención. No
bloquea el sprint. Cuando se responda, la salida natural es archivar las señales aplicadas
con más de cierta antigüedad y conservar indefinidamente las rechazadas, las fallidas y las
de conflicto, que son las que se consultan.
