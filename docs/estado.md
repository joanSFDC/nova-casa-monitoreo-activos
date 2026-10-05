# Estado de la implementación

Este documento no es un módulo más. Es el tablero de **qué ya existe**, qué se
está haciendo y qué queda. Se actualiza en el mismo Pull Request que el cambio
que describe. Si el código y esta página no coinciden, esta página está mal.

La especificación sigue en los módulos [01](01-contrato-del-mensaje.md) a
[12](12-plan-de-pruebas.md). Aquí no se rediseña nada: se registra lo construido.

## Dónde estamos

| Pieza | Estado | Dónde vive |
| --- | --- | --- |
| Proyecto Salesforce DX | Hecho | `sfdx-project.json`, `force-app/` |
| Modelo de datos (issue #2) | En `main` | [PR #16](https://github.com/joanSFDC/nova-casa-monitoreo-activos/pull/16) |
| Conjuntos de permisos (cinco roles) | En `main` | [PR #18](https://github.com/joanSFDC/nova-casa-monitoreo-activos/pull/18) |
| Siembra del catálogo (issue #3) | En `main` | [PR #17](https://github.com/joanSFDC/nova-casa-monitoreo-activos/pull/17) |
| Usuarios de la demo (issue #14) | En `main` | [PR #18](https://github.com/joanSFDC/nova-casa-monitoreo-activos/pull/18) |
| Ingesta US-201 (issue #4) | En `main` | [PR #19](https://github.com/joanSFDC/nova-casa-monitoreo-activos/pull/19) |
| Procesamiento US-202 (issue #5) | En `main` | [PR #20](https://github.com/joanSFDC/nova-casa-monitoreo-activos/pull/20) |
| Trazabilidad US-209 (issue #12) | En `main` | [PR #21](https://github.com/joanSFDC/nova-casa-monitoreo-activos/pull/21) |
| Límites administrables US-204 (issue #7) | En `main` | [PR #22](https://github.com/joanSFDC/nova-casa-monitoreo-activos/pull/22) |
| Incidentes US-205 (issue #8) | En `main` | [PR #24](https://github.com/joanSFDC/nova-casa-monitoreo-activos/pull/24) |
| Conectividad US-206 (issue #9) | En `main` | [PR #25](https://github.com/joanSFDC/nova-casa-monitoreo-activos/pull/25) |
| Estado actual US-203 (issue #6) | En `main` | [PR #23](https://github.com/joanSFDC/nova-casa-monitoreo-activos/pull/23) |
| Monitor US-207 (issue #10) | En `main` | [PR #26](https://github.com/joanSFDC/nova-casa-monitoreo-activos/pull/26) |
| Autorización US-208 (issue #11) | En `main` | [PR #27](https://github.com/joanSFDC/nova-casa-monitoreo-activos/pull/27) |
| Identidad visual (issue #15) | En `main` | [PR #36](https://github.com/joanSFDC/nova-casa-monitoreo-activos/pull/36) |
| El resto de historias | Pendiente | Issue #13 |

Org de trabajo: alias `novacasa2`, dominio
`trailsignup-95b2e3a11aa777`. Caduca el 23 de octubre de 2026. Lo que no esté
en el repositorio desaparece ese día.

## Qué hay hoy en la org

### Modelo

Ocho elementos desplegados y verificados:

- Objetos: `Edificio__c`, `Activo__c`, `Estado_Actual__c`, `Umbral__c`,
  `Senal__c`, `Control_de_Ingesta__c`
- Evento: `Aviso_de_Senal__e` (`PublishAfterCommit`)
- Campos en `Case`: `Clave_Abierta__c`, `Activo__c`, `Tipo_Medicion__c`,
  `Episodio_Id__c`, `Origen_Senal__c`, `Ciudad__c`
- Catálogos globales: `Tipo_Activo`, `Tipo_Medicion`, `Unidad`, `Severidad`

Las claves External ID y Unique funcionan: dos estados con la misma
`Clave__c` se rechazan; varios casos con `Clave_Abierta__c` vacía se admiten.
El resumen de severidad del activo toma el máximo de sus estados.

### Catálogo sembrado

El script `./scripts/sembrar-catalogo.sh` hace `upsert` por External ID.
Correrlo dos veces deja exactamente 2 edificios, 10 activos y 5 umbrales.

| Código | Qué es |
| --- | --- |
| `BLD-BOG-001` | Edificio Nova Alameda, Bogotá, región Andina |
| `BLD-BAQ-001` | Edificio Nova Caribe, Barranquilla, región Caribe |
| `AST-BOG-TEMP-001` / `AST-BAQ-TEMP-001` | Sala técnica |
| `AST-BOG-WATER-001` / `AST-BAQ-WATER-001` | Medidor de agua |
| `AST-BOG-ENERGY-001` / `AST-BAQ-ENERGY-001` | Medidor de energía |
| `AST-BOG-PUMP-001` / `AST-BAQ-PUMP-001` | Bomba de presión |
| `AST-BOG-CAM-001` / `AST-BAQ-CAM-001` | Cámara |

Umbrales, clave `Tipo_Activo\|Tipo_Medicion`:

| Clave | Unidad | Banda |
| --- | --- | --- |
| `TECHNICAL_ROOM\|TEMPERATURE` | `CELSIUS` | 14.9 / 17.9 / 30.1 / 35.1 |
| `WATER_PUMP\|WATER_PRESSURE` | `BAR` | 1.49 / 2.49 / 4.01 / 5.01 |
| `WATER_METER\|WATER_CONSUMPTION` | `LITER_PER_15_MIN` | solo alto: 401 / 651 |
| `ENERGY_METER\|ENERGY_CONSUMPTION` | `KWH_PER_15_MIN` | solo alto: 40.1 / 65.1 |
| `SECURITY_CAMERA\|CAMERA_CONNECTIVITY` | (vacío) | 15 min advertencia, 60 min crítico |

### Ingesta

Clases en `force-app/main/default/classes/`:

| Clase | Rol |
| --- | --- |
| `IngestaSchedulable` | Cada minuto encola el primer eslabón |
| `IngestaQueueable` | Una página por transacción, hasta seis por ciclo |
| `IngestaCliente` | `callout:Nova_Casa_Simulador` — el token no está aquí |
| `IngestaValidador` | Contrato del [módulo 01](01-contrato-del-mensaje.md) |
| `IngestaServicio` | Deduplica, upsert `Senal__c`, publica `Aviso_de_Senal__e`, avanza el cursor |
| `ClasificacionServicio` | Severidad de medición y de conectividad contra `Umbral__c` |
| `ProcesamientoServicio` | Suscriptor de `Aviso_de_Senal__e`: estado actual, incidentes y bitácora |
| `IncidentesServicio` | Un Case por `Clave_Abierta__c`; duplicado concurrente = éxito y reintenta escalada |

Named Credential `Nova_Casa_Simulador` + External Credential del mismo nombre,
principal `Equipo`. El administrador necesita el conjunto
`Nova_Casa_Administracion`: el acceso al principal **no lo concede el perfil**.
El token se carga con `./scripts/configurar-credencial.sh` y **no vive en git**.
La URL base de la Named Credential es
`https://mdss-study-01ed1c1eca26.herokuapp.com/api/sprint-2/simulator/v1`.
Apex añade `/session` y `/telemetry`. MIXED mezcla lecturas buenas, fechas
futuras y algún activo desconocido (`AST-UNKNOWN-0001`): Pendiente con
`Fecha_Procesamiento__c` vacía es el criterio de US-201.

Recorrido reproducible:

```bash
sf project deploy start --source-dir force-app -o novacasa2
sf org assign permset -o novacasa2 -n Nova_Casa_Administracion
./scripts/sembrar-catalogo.sh novacasa2
export NOVA_CASA_SIMULADOR_TOKEN='...'   # fuera del repo
./scripts/configurar-credencial.sh novacasa2
./scripts/ejecutar-ingesta.sh novacasa2
./scripts/ejecutar-procesamiento.sh novacasa2
```

Después de una página buena: señales en **Pendiente**,
`Fecha_Procesamiento__c` vacía, cursor distinto del inicial. Un 429 deja el
cursor igual. Los diagramas de secuencia están al final del
[módulo 02](02-ingesta.md).

### Bitácora

La investigación es vistas de lista estándar y la página de registro
`Senal_Registro` (identidad, resultado, momentos, carga). No hay consola LWC
ni botón de reproceso.

| Vista | Filtro |
| --- | --- |
| Rechazadas hoy | `Rechazado` y recepción de hoy |
| Reintentables | `Reintentable__c` y resultado rechazado o fallido |
| Conflictos | Resultado conflicto |
| Duplicadas | `Entregas__c` mayor que uno |
| Atascadas | Pendiente con recepción anterior a hoy |
| Últimas 24 horas | Recepción del último día, más reciente primero |

`IngestaConstantes.aplicar` es el único sitio que escribe resultado, motivo y
reintentable juntos. El reenvío idéntico **no** cambia el resultado a
Duplicado: sube `Entregas__c`, que es lo que filtra la vista. `Message_Id__c`
es External ID para la búsqueda global. El operador no tiene el objeto.

La regla `Resultado_obligatorio` impide guardar una señal sin resultado.

### Usuarios y accesos de la demo

Cinco conjuntos de permisos. Los humanos parten de `Minimum Access - Salesforce`.
El usuario de integración usa el perfil `Salesforce API Only System Integrations`
y la licencia Salesforce Integration: no inicia sesión.

| Usuario de login | Rol | Conjunto | Ve |
| --- | --- | --- | --- |
| `operador.bogota.novacasa.95b2e3a11aa777@salesforce.com` | Operador Bogotá | `Nova_Casa_Operador` | Solo Alameda |
| `operador.baq.novacasa.95b2e3a11aa777@salesforce.com` | Operador Barranquilla | `Nova_Casa_Operador` | Solo Caribe |
| `coordinador.novacasa.95b2e3a11aa777@salesforce.com` | Coordinador | `Nova_Casa_Coordinador` | Las dos ciudades, edita umbrales, lee bitácora sin campos sensibles |
| `gerente.novacasa.95b2e3a11aa777@salesforce.com` | Gerente | `Nova_Casa_Gerencia` | Las dos ciudades, no edita umbrales |
| `admin.novacasa.95b2e3a11aa777@salesforce.com` | Administrador | `Nova_Casa_Administracion` | Todo, incluidos `Carga__c` y `Detalle__c` |
| `integracion.novacasa.95b2e3a11aa777@salesforce.com` | Integración | `Nova_Casa_Integracion` | Proceso. Nadie inicia sesión con él |

Q-10 quedó en **por ciudad**: regla sobre `Edificio__c.Ciudad__c` hacia los grupos
`Operadores_Bogota` y `Operadores_Barranquilla`. Coordinador y gerente están en
los dos grupos. El edificio sigue siendo la unidad de autorización; activo y
estado actual heredan. Los casos se comparten igual, por `Case.Ciudad__c`
(US-208). El coordinador es además miembro de la cola de casos **Coordinación**.

La aplicación `Nova_Casa` abre en la pestaña **Monitor**. Logo y tema están en
la sección de identidad visual, más abajo.

### US-204 · Límites administrables

En `main` (PR #22): validaciones, historial, vista, FlexiPage `Umbral_Registro`
y **Aplicar límites**. En cámara usa `clasificarConectividad`.

### US-203 · Estado actual

La vigencia vive en `ProcesamientoServicio` (PR #20). El hueco de la **misma
tanda** está en `main` (PR #23): si llega primero la lectura vieja y después
la nueva, la perdedora queda **Atrasado**, no Aplicado. Las pruebas de
`EstadoActualTest` cubren LATE_MESSAGES, empate en los dos órdenes, crítico
atrasado sin caso y dos mediciones del mismo activo.

La antigüedad en pantalla es el monitor (US-207): no se guarda como dato.

### US-205 · Una sola intervención

`IncidentesServicio` abre el Case después del estado y antes de la bitácora.
La clave de medición es `activo|tipoMedicion`; la de conectividad es
`CONN|episodioId`. Advertencia entra en prioridad baja; crítico sube a alta.
Un error `DUPLICATE_VALUE` se trata como éxito y se reintenta la escalada.
Al cerrar, el disparador `CaseLiberarClave` (y el flujo
`Liberar_Clave_Abierta`) vacían `Clave_Abierta__c` (R-18).
La vuelta a normal **no** cierra el caso. Si falla crear el Case, la señal
queda Fallido y el estado actual sí se actualizó.

### US-206 · Severidad y conectividad

La clasificación ya venía de US-204. Aquí el procesamiento deja `Valor__c`
vacío en cámara (el silencio vive en `Gap_Segundos__c`), vacía el episodio
en `HEALTHY` y lo conserva en `RESTORED`. Un `LOST` de 90 s marca sin
comunicación y no abre caso; a 15 min abre en baja; a 60 min el mismo caso
sube a alta. `RESTORED` no cierra. Dos episodios son dos casos. El resumen
del activo sigue siendo `MAX` de `Severidad_Nivel__c`.

### US-207 · Monitor del operador

`MonitorControlador` arma el panel en el servidor (`with sharing`, `USER_MODE`):
contadores, filas de `Estado_Actual__c` y aviso de consulta atrasada (5 min).
No consulta `Senal__c`. La antigüedad se calcula en Apex. El LWC
`monitorDeActivos` filtra severidad en el navegador sobre esos datos, se
suscribe a `Aviso_de_Senal__e` solo como disparador (R-07) y agrupa 2 s.

«Abrir intervención» solo aparece si hay algo que atender (advertencia,
crítico o sin comunicación) o si ya hay caso, y entonces dice «Ver
incidente». El valor conserva los decimales del umbral («0,80 bar», no
«0,8»). La pestaña **Monitor** es la primera de la aplicación.

### US-208 · Autorización

La matriz del [módulo 10](10-seguridad-y-accesos.md) es lo desplegado. Lo que
cambió para que lo fuera:

- **`Case` privado**, con reglas `Casos_Bogota` y `Casos_Barranquilla` sobre
  `Case.Ciudad__c`. Lo escribe el disparador `CaseCiudad` desde el edificio
  del activo, sin importar lo que traiga el registro.
  `scripts/apex/sellar-ciudad-casos.apex` rellena los casos que ya existían.
- **`Control_de_Ingesta__c` en lectura y escritura públicas**, para que el
  administrador edite el control aunque no sea suyo.
- **Aplicar límites** exige poder editar `Umbral__c` y escribe en una clase
  interna `without sharing`. Antes fallaba para el coordinador.
- **Operador, coordinador y gerente** recibieron FLS sobre los campos estándar
  de `Case` y `Task` que leen el monitor y la página del caso. Sin eso, el
  panel del incidente fallaba con "No such column 'Subject'".
- **Administración** lee la bitácora entera sin editarla ni borrarla.
- **El procesamiento corre como integración**, configurado por
  `./scripts/configurar-suscriptor.sh`.
- **Página `Caso_Registro`** para ver un caso: incidente, equipo y
  actividades. La estándar dejaba el panel de detalles en error para todos
  los usuarios de la demo (punto 28).
- **Página `Control_Registro`** para el control de ingesta: escenario, tanda
  y reactivarla, más lo que deja cada ciclo. El formato del objeto solo
  traía los campos estándar (punto 29).

Comprobado en la org con `UserRecordAccess`, sobre los cuatro casos de Caribe
y el control:

| Usuario | Casos de Caribe | Control |
| --- | --- | --- |
| Operador Bogotá | Sin acceso | Lee |
| Operador Barranquilla | Lee | Lee |
| Coordinador | Lee, edita | Lee |
| Gerente | Lee | Lee |
| Administrador | Lee, edita | Lee, edita |

Tras suspender y reanudar la suscripción, un ciclo de MIXED dejó 234 señales
procesadas por Usuario Integración. Las 5 rechazadas o en conflicto quedan a
nombre de quien lanzó la ingesta, porque se deciden al llegar.

### Identidad visual

El detalle está en el [módulo 09](09-experiencia-del-operador.md#la-identidad-visual).
Lo desplegado:

- **Tema `Nova_Casa` sobre SLDS 1**, activo para toda la org: cabecera blanca
  con el logo horizontal, fondo de encabezado con la línea cobre y enlaces y
  botones en `#122d4f` (`OVERRIDE_A11Y_COLOR`).
- **Aplicación** con la casa como logo, descripción nueva y pestañas en el orden
  del operador: Monitor, Casos, Activos, Edificios, Estados actuales, Umbrales,
  Señales, Control de ingesta e Inicio.
- **Iconos** con sentido en las siete pestañas propias.
- **Severidad fija** en el CSS del monitor: `#ba0517`, `#a15c00`, `#2e844a`.
- **Páginas** `Activo_Registro`, `Edificio_Registro` y `Estado_Registro`.
- **Etiquetas**: campos reescritos, Estado y Prioridad del caso en español
  (`CaseStatus`, `CasePriority`) y dos decimales en `Valor__c` y en los límites.

Medido en la org: las parejas de texto y fondo que introduce el tema van de
4,65:1 (normal) a 17,76:1 (pestañas). El cobre, 4,32:1, solo está en imágenes.

## Cómo reconstruir el entorno

```bash
sf project deploy start --source-dir force-app -o novacasa2
sf org assign permset -o novacasa2 -n Nova_Casa_Administracion
./scripts/sembrar-catalogo.sh novacasa2
./scripts/crear-usuarios-demo.sh novacasa2
./scripts/configurar-suscriptor.sh novacasa2
```

`crear-usuarios-demo.sh` se puede volver a correr: solo manda el correo de
clave a los usuarios que crea en esa corrida, así que no invalida las claves
de quienes ya existían.

`configurar-suscriptor.sh` va después de los usuarios porque busca al de
integración. Si el disparador ya estaba suscrito, hay que suspender y
reanudar la suscripción (el script dice dónde). Pasar `Case` a privado lanza
un recálculo de compartición: hasta que termina, las pruebas de
`SeguridadAccesosTest` pueden ver los casos como públicos.

El despliegue deja activo el tema `Nova_Casa`
(`settings/LightningExperience.settings`). Una sesión abierta tarda unos
minutos en ver el tema, el logo y las páginas nuevas.

## Qué se está haciendo ahora

Los arreglos encontrados al cerrar US-208 están hechos: la fecha futura
contra `publishedAt` (issue #28), la sesión dentro de la clave de la señal
(issue #31), la nota al abrir una intervención (issue #29) y `Caso_Registro`
como detalle del incidente (issue #30). La identidad visual (issue #15) está
hecha. US-210 (issue #13) espera sus criterios.

La revisión previa a la entrega encontró faltas que se cierran una por issue:
el formato y la codificación (issue #37), la evidencia de la bitácora en la
ingesta (issue #39), el crítico superado dentro de una tanda (issue #41), los
rangos contradictorios del umbral (issue #43), la cola del coordinador
(issue #45), las claves que el script de usuarios restablecía en cada
corrida (issue #47), el monitor que no se recalculaba con la ingesta parada
(issue #49) y la aplicación de entrada de los humanos (issue #51).

## Decisiones que aparecieron al implementar

No estaban en la especificación y conviene no redescubrirlas.

1. **Un despliegue de metadatos no concede seguridad a nivel de campo.** Sin
   `Nova_Casa_Administracion`, los campos existían y Apex decía "No such
   column". Detalle en [PR #16](https://github.com/joanSFDC/nova-casa-monitoreo-activos/pull/16)
   y [módulo 10](10-seguridad-y-accesos.md).
2. **`Activo__c.Severidad__c` no devuelve "Sin datos"** si el activo no tiene
   estados: el resumen automático devuelve cero, no vacío, y la fórmula cae en
   "Normal". Quedó como está en el [módulo 03](03-modelo-de-datos.md).
3. **`Edificio__c.Region__c`** se sembró con Andina y Caribe. El módulo 03 pide
   el campo y no fija los valores.
4. Los perfiles están en `.forceignore`. El acceso se concede solo por conjunto
   de permisos.
5. **`Umbral__c` en ReadWrite, no en Read.** Lectura pública no deja editar
   registros de otro dueño, y los umbrales los sembró la administración.
6. **Q-10: compartición por ciudad**, no por región ni edificio a edificio.
7. **Apex 67 y `without sharing` no saltan FLS.** Las consultas de ingesta van
   con `WITH SYSTEM_MODE`. Sin eso, el proceso de sistema choca con los mismos
   "No such column" del punto 1.
8. **El token no cabe en el metadato de la External Credential.** Se crea el
   principal vacío y el valor se cifra después con ConnectApi, desde el script,
   nunca desde un archivo versionado.
9. Un cron de Apex no admite "cada minuto" en una sola expresión: son sesenta
   `CronTrigger` con nombre `Nova Casa Ingesta mm`.
10. **`Aviso_de_Senal__e` va con `PublishAfterCommit`.** `PublishImmediately`
    disparaba el suscriptor antes de que `Senal__c` fuera visible: 70 aplicadas
    y 155 Pendiente en el mismo ciclo de MIXED. `procesarPendientes` drena las
    que ya se perdieron el aviso.
11. **El resultado Duplicado no se escribe.** Un reenvío idéntico incrementa
    `Entregas__c` y conserva Pendiente/Aplicado/etc. La vista Duplicadas filtra
    por el contador, no por el valor de la lista. Cambiar a Duplicado perdería
    si esa señal ya se aplicó.
12. GitHub no cierra issues con `Cierra #N`. En el PR hay que escribir
    `Closes #N`.
13. Las vistas de lista **no aceptan** `LAST_N_HOURS`. Atascadas queda como
    Pendiente con recepción anterior a hoy.
14. **«Sin ninguna frontera» incluye los minutos.** La cámara no tiene bandas
    de valor, solo 15/60 minutos: si la regla mirara solo los cuatro números,
    no se podría guardar.
15. **Un `.layout` desplegado no llega al usuario.** Los perfiles están en
    `.forceignore`, así que la página de registro por defecto ignora el layout.
    El patrón es un FlexiPage con `actionOverrides` de View, como `Senal_Registro`.
16. **Aplicar límites en cámara no usa `clasificarMedicion`.** Aunque
    `Valor__c` quede vacío, sin bandas de valor un `Gap_Segundos__c` copiado
    ahí caería en Normal. Se llama a `clasificarConectividad` con estado y gap.
17. **`Clave_Abierta__c` no lleva la severidad.** Advertencia y crítico del
    mismo activo y medición son el mismo caso, que escala. El texto de ayuda
    del campo en el modelo original decía `|severidad`; el [módulo 07](07-incidentes.md)
    no.
18. **El índice único no trata `''` como vacío.** Varios nulos sí conviven;
    dos cadenas vacías chocan. El disparador `CaseLiberarClave` pone `null`.
    El flujo `Liberar_Clave_Abierta` es la defensa del [módulo 07](07-incidentes.md);
    el disparador es lo que deja el campo realmente nulo.
19. **Conectividad no escribe `Valor__c`.** El [módulo 08](08-conectividad.md)
    deja el valor vacío: el silencio está en `Gap_Segundos__c`. Copiar el gap
    al valor confundía Aplicar límites (punto 16) y pintaba segundos como si
    fueran una lectura.
20. **En la misma tanda, la perdedora no puede quedar Aplicado.** El
    procesamiento marcaba Aplicado al ir viendo cada aviso. Si después ganaba
    otra lectura de la misma clave, el estado era el correcto pero la bitácora
    mentía. Se corrige al aplicar el ganador: el previo de esa tanda pasa a
    Atrasado.
21. **El monitor lee `Ultima_Consulta_Exitosa__c` y nada más del control.**
    El aviso de ingesta atrasada necesita esa fecha. El cursor y la semilla
    siguen ocultos. El objeto es privado, así que operador, coordinador y
    gerente tienen «ver todo» sobre ese único registro: si no, `USER_MODE`
    no devolvería la fila. No tienen pestaña ni el resto de campos. Desde
    US-208 el objeto es público (punto 26) y el «ver todo» sobra, pero se
    queda: el aviso no depende del valor por defecto.
22. **`Case` estaba en lectura y escritura públicas.** Es el valor de fábrica
    de la org y nadie lo había tocado: el operador de Bogotá leía los casos de
    Caribe por su Id. La regla del edificio no alcanza al caso, que solo tiene
    una búsqueda al activo.
23. **Las reglas por criterio no aceptan fórmulas.** `Case.Ciudad__c` no puede
    ser `Activo__r.Edificio__r.Ciudad__c`: es texto y lo escribe `CaseCiudad`.
24. **`with sharing` también frena la escritura en modo de sistema.**
    `Database.update(..., AccessLevel.SYSTEM_MODE)` salta permisos de objeto y
    campo, pero la compartición la decide la clase. Editar un detalle exige
    editar el principal: Aplicar límites daba
    `INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY` al coordinador.
25. **Los campos estándar de `Case` y `Task` también llevan FLS.** Subject,
    Description, Priority y Origin en Case; Description y WhatId en Task.
    Status, OwnerId o CaseNumber no se pueden conceder ni quitar. El monitor
    pedía Subject con `USER_MODE` y el operador no lo tenía.
26. **«Modificar todo» exige borrar.** Para que el administrador edite un
    control ajeno sin poder borrarlo, el objeto pasó a lectura y escritura
    públicas, como `Umbral__c` (punto 5). Solo administración e integración
    tienen editar.
27. **El suscriptor del evento no va como metadato.** El
    `PlatformEventSubscriberConfig` lleva el Username escrito, y cambia en cada
    org. Lo crea un script por Tooling API. Si el disparador ya estaba
    suscrito, el cambio no entra hasta suspender y reanudar (Resume, no
    Resume from Tip).
28. **El perfil de acceso mínimo no tiene formato de página para `Case`.** La
    página estándar del caso abría con el panel de detalles en error ("One or
    more profiles have no page layout assigned"). Con Case público ya pasaba,
    pero nadie lo veía: el administrador de la org tiene otro perfil. Mismo
    remedio que el punto 15: `Caso_Registro`, con secciones de campos que no
    dependen del formato, en `actionOverrides` de View. El botón Editar solo
    aparece a quien puede editar el caso.
29. **El formato de `Control_de_Ingesta__c` solo trae los campos estándar.**
    Los campos llegaron después por metadato y ningún formato los suma, así
    que el administrador veía Nombre y Divisa y no podía cambiar el escenario
    ni reactivar la ingesta. `Control_Registro` muestra la configuración
    editable y el progreso (cursor, sesión, último error) en solo lectura.
30. **El reloj del simulador no es el de la org.** Arranca al abrir la sesión
    y avanza un minuto por mensaje. Medida contra la hora de la org, la
    «Fecha futura» rechazó 471 lecturas buenas en la primera ingesta, que
    bajó 450 mensajes en diez minutos; hoy, consultado poco, va cinco días
    atrás. Se mide contra el `publishedAt` del mismo mensaje
    ([módulo 01](01-contrato-del-mensaje.md)). Una lectura por delante de la
    org se pinta «hace un momento». Las 471 rechazadas se quedan como están:
    esos activos ya tienen lecturas más nuevas y reprocesarlas no cambiaría
    ningún estado.
31. **Cada sesión del simulador empieza en `msg_000001`.** Con cualquier
    semilla, y con fechas que arrancan al abrirla. Con la clave
    `source|messageId`, una sesión nueva (409, cursor perdido, caducidad o
    cambio de escenario) chocaba con la bitácora y quedaba entera en
    Conflicto. La clave lleva el inicio de la sesión
    ([módulo 01](01-contrato-del-mensaje.md)). Las 1.693 señales anteriores
    conservan su clave; en el paso, un reenvío en vuelo puede dejar una
    segunda fila con el mismo hecho, sin efecto en el estado.
32. **Crear tareas exige «Edit Tasks».** El permiso de objeto sobre `Task`
    no basta, y ni el operador ni el coordinador lo tenían: la nota de una
    intervención se perdía en silencio porque la tarea se inserta con
    `allOrNone` en falso. Los dos conjuntos lo llevan ahora. Salesforce no
    separa crear de editar tareas, así que el operador edita sus notas,
    no las ajenas ([módulo 10](10-seguridad-y-accesos.md)).
33. **El detalle del incidente es `Caso_Registro`, no un método propio.**
    `obtenerIncidente` leía el caso para un panel que no se construyó: el
    monitor lleva a la página del caso, que ya aplica la compartición y trae
    la actividad. Se quitó con sus objetos de transferencia. La prueba de
    seguridad que lo usaba ahora consulta el caso en modo usuario.
34. **El color de la barra va en el tema, no en la aplicación.** Con
    `shouldOverrideOrgTheme`, la marca de la aplicación solo cambia el logo al
    rato de cargar; la barra de navegación sigue con el color del tema. La
    aplicación lleva su logo y deja el color al tema.
35. **El tema es SLDS 1.** Cosmos (SLDS 2) cambia los colores de severidad del
    sistema de diseño: crítico `#b60554`, advertencia `#8c4b02`, normal
    `#056764`. Con SLDS 1 y los tres valores fijos en el CSS del monitor, la
    severidad no depende del tema.
36. **Sin `OVERRIDE_A11Y_COLOR`, enlaces y botones salen `#415c8a`.** Salesforce
    deriva su propio azul del color de marca. La propiedad lo fija en `#122d4f`.
37. **De un motivo de pestaña solo cuenta el número.** `Custom67: Building`
    pinta engranajes, porque el 67 son engranajes. Cuatro pestañas tenían un
    nombre que no correspondía a su número.
38. **Un despliegue fallido no deja nada.** Al crear las páginas de Activo,
    Edificio y Estado, un lote falló por un byte mal codificado en la de
    Activo. Las otras dos parecían desplegadas pero no lo estaban: la org deshace
    el lote entero. Hay que mirar el estado del despliegue, no solo sus errores.
39. **Las etiquetas de `CaseStatus` y `CasePriority` se traducen sin tocar el
    valor de API.** La org es `en_US` y el caso decía New y High. El código
    escribe `New`, `High` y `Low`, que siguen siendo los mismos. La prueba
    `shouldAbrirNuevo_WhenCierreLiberaClave` cerraba el caso con el
    `MasterLabel` del estado cerrado, que ahora es «Cerrado» y no un valor de
    `Status`; falló con «Quedo cerrado». Ahora usa `ApiName`. El disparador
    `CaseLiberarClave` ya aceptaba los dos.
40. **Un campo de solo lectura en la página no frena al administrador del
    sistema.** Su perfil tiene «Edit Read Only Fields», que pasa por encima de la
    página y no se le puede quitar. `Estado_Registro` va con la lista de acciones
    vacía, que deja la cabecera sin botones, y Operador, Coordinador y Gerencia
    solo leen el estado. El administrador sigue viendo el lápiz en cada campo.
41. **La cabecera es blanca.** Sobre `#122d4f`, el logo necesitaba una placa
    blanca y parecía pegado encima. El azul marino queda en el logo, los enlaces
    y los botones. La línea de la pestaña activa sale `#6e94d5`, un tono que
    Salesforce genera desde `BRAND_COLOR`; `OVERRIDE_A11Y_COLOR` solo fija el de
    enlaces y botones. Cambia la lectura del punto 2 del issue #15: la barra ya
    no es el azul de Salesforce, pero tampoco es el token exacto.
42. **Prettier no toca los XML de metadatos.** Sobre ellos parte cada texto
    largo en `<etiqueta\n  >texto</etiqueta>` y los deja distintos de como los
    recupera Salesforce. `.prettierignore` excluye `**/*-meta.xml`; Apex, LWC,
    JavaScript y Markdown siguen pasando por `npm run prettier`. Dos XML de
    `Senal__c` estaban en ISO-8859-1 y la org guardó «se�al»: ya son UTF-8.
43. **Un `messageType` desconocido se perdía.** `Tipo_Mensaje__c` es una lista
    restringida y el `upsert` fallaba: la señal no llegaba a la bitácora. Ahora
    se guarda con el tipo vacío, rechazada, y el tipo recibido en `Detalle__c`.
44. **El conflicto conserva la primera afirmación.** Entre páginas, la segunda
    entrega reescribía carga, resumen y fechas de una señal que quizá ya estaba
    aplicada. Ahora solo suma la entrega y deja en `Detalle__c` el `deliveryId`
    que la contradice. Un reenvío idéntico conserva `Fecha_Procesamiento__c`.
45. **Una señal que no se puede guardar deja rastro.** Se reintenta como fila
    mínima Fallida con «Error del sistema» y el error, sin la carga. Si tampoco
    entra, el error va a `Ultimo_Error__c`. Antes se marcaba Rechazado solo en
    memoria. Un aviso que no se publica también queda Fallido, no Pendiente.
46. **`Ultimo_Error__c` es el último problema, no el estado de ahora.** Una
    consulta buena ya no lo borra; así el 409 no desaparece en la misma
    transacción. Tiene historial y `Control_Registro` lo muestra en la barra
    lateral. Para eso el formato de página del control entra en el repositorio
    con la lista de historial: la lista individual de Lightning solo ofrece las
    listas que están en el formato.
47. **Un crítico superado en la misma tanda no escala.** `acumular` guardaba el
    nivel más alto de la tanda y la primera señal como origen, aunque esa señal
    terminara Atrasado. Ahora la decisión guarda el nivel de cada señal y
    `escribir` lo recalcula solo con las que quedaron Aplicado, como pide el
    [módulo 06](06-estado-actual.md).
48. **Dos reglas más en `Umbral__c`.** «Crítico bajo cruzado» impide un crítico
    bajo igual o mayor que la advertencia alta: con la advertencia baja vacía,
    20 / 10 / 15 pasaba y todo salía crítico. «Medición sin bandas» impide un
    umbral de medición con solo minutos, que clasificaba todo como normal. El
    catálogo sembrado cumple las dos.
49. **La cola del coordinador es una cola de Case real.** «Coordinación» recibe
    el caso que nace en alta y el que escala mientras sigue siendo del sistema.
    Un caso que ya tomó una persona escala sin cambiar de propietario. El
    miembro lo pone el script de usuarios, porque el Username cambia en cada
    org; la vista «Cola de coordinación» lista los abiertos de la cola.
50. **El monitor se vigila a sí mismo cada minuto.** Sin avisos no había
    consultas y el aviso de atraso nunca aparecía con la ingesta parada. Si pasa
    un minuto sin consultar, el componente vuelve a pedir el panel. La región
    activa lleva la hora para que cada actualización se vuelva a anunciar, y la
    vigilancia solo habla si cambia el aviso de atraso.
51. **La aplicación de entrada es un `UserAppInfo`.** Un conjunto de permisos
    no puede marcar la aplicación por defecto y el perfil mínimo deja ver un
    centenar. El script de usuarios deja Nova Casa como entrada de los cinco
    humanos en escritorio, sin tocar el perfil.

## Historial breve

| Fecha | Qué |
| --- | --- |
| 2026-09-23 | Proyecto DX, modelo y permission set de administración. PR #16 fusionado. Cierra #2 |
| 2026-09-24 | Script de siembra del catálogo. PR #17 fusionado. Cierra #3 |
| 2026-09-24 | Usuarios de la demo, cinco conjuntos y reglas por ciudad. PR #18 fusionado. Cierra #14 |
| 2026-09-24 | Ingesta US-201: credenciales, cadena Queueable, diagramas. Cierra #4 |
| 2026-09-25 | Procesamiento US-202: tanda, aislamiento, vigencia. PR #20 fusionado. Cierra #5 |
| 2026-09-25 | Trazabilidad US-209: vistas, página de registro, reintentable. PR #21 fusionado. Cierra #12 |
| 2026-09-28 | Límites administrables US-204: validaciones, historial, aplicar límites. PR #22 fusionado. Cierra #7 |
| 2026-09-29 | Incidentes US-205: unicidad, escalada y clave al cerrar. PR #24 fusionado. Cierra #8 |
| 2026-09-29 | Conectividad US-206: silencio, episodios y resumen del activo. PR #25 fusionado. Cierra #9 |
| 2026-09-30 | Estado actual US-203: vigencia, empate y perdedoras de tanda. PR #23 fusionado. Cierra #6 |
| 2026-10-01 | Monitor US-207: panel del operador, contadores y aviso de ingesta. PR #26 fusionado. Cierra #10 |
| 2026-10-01 | Autorización US-208: casos por ciudad, acciones comprobadas, suscriptor como integración. PR #27 fusionado. Cierra #11 |
| 2026-10-01 | Fecha futura contra `publishedAt`: el reloj del simulador no es el de la org. PR #32 fusionado. Cierra #28 |
| 2026-10-01 | La sesión del simulador entra en la clave de la señal. PR #33 fusionado. Cierra #31 |
| 2026-10-01 | Nota opcional al abrir una intervención y «Edit Tasks» para operador y coordinador. PR #34 fusionado. Cierra #29 |
| 2026-10-01 | El detalle del incidente es `Caso_Registro`: fuera `obtenerIncidente`. PR #35 fusionado. Cierra #30 |
| 2026-10-03 | Identidad visual: tema SLDS 1 con cabecera blanca, logo, iconos, etiquetas y páginas de activo, edificio y estado. PR #36. Cierra #15 |
| 2026-10-05 | Formato de Prettier en 22 archivos, XML de metadatos fuera de Prettier y dos XML de la señal en UTF-8. PR #38 fusionado. Cierra #37 |
| 2026-10-05 | La bitácora conserva la evidencia: reenvío, conflicto, tipo desconocido, guardado fallido y 409. PR #40 fusionado. Cierra #39 |
| 2026-10-05 | Un crítico superado en la misma tanda no abre ni escala el caso. PR #42 fusionado. Cierra #41 |
| 2026-10-05 | Umbral: crítico bajo cruzado y medición sin bandas. PR #44 fusionado. Cierra #43 |
| 2026-10-05 | Cola Coordinación para los casos críticos y vista de lista. PR #46 fusionado. Cierra #45 |
| 2026-10-05 | El script de usuarios solo manda clave a los usuarios que crea. PR #48 fusionado. Cierra #47 |
| 2026-10-05 | Monitor: vigilancia de un minuto y región activa que anuncia cada cambio. PR #50 fusionado. Cierra #49 |
| 2026-10-05 | Nova Casa como aplicación de entrada de los humanos. Cierra #51 |
