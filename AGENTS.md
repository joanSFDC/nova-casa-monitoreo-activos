# Cómo se trabaja este repositorio

Esta guía está escrita para que cualquiera, persona o agente de IA, pueda abrir el
proyecto y trabajar como trabajamos nosotros, sin tener que preguntar.

[`CONTRIBUTING.md`](CONTRIBUTING.md) explica **git y el flujo de equipo**: ramas, commits,
Pull Requests. Este documento explica **el proyecto**: qué hay dentro, qué decisiones ya
están tomadas y cuáles son las trampas conocidas. Los dos son obligatorios y no se repiten.

---

## 1. Qué es esto

Un sistema de monitoreo de activos para Nova Casa, una administradora de edificios.

Un proveedor externo expone un simulador de sensores. Nosotros consultamos sus mensajes,
los clasificamos contra unos límites configurables, mantenemos el estado actual de cada
equipo, abrimos incidentes cuando algo se sale de rango, y le damos al operador una
pantalla donde ve todo y actúa.

El recorrido completo, de punta a punta:

```
Simulador  -->  Ingesta      -->  Aviso_de_Senal__e  -->  Procesamiento
(HTTP)          Senal__c          (evento)                 clasifica
                (bitacora)                                    |
                                                              +--> Estado_Actual__c
                                                              +--> Case (incidente)
                                                                          |
                                                          Monitor (LWC) <-+
```

Hay trece módulos, uno por documento en `docs/`, y diez historias de usuario de US-201 a
US-210.

---

## 2. La estructura del repositorio

| Ruta | Qué es |
| --- | --- |
| `docs/` | **La especificación.** Trece documentos. Es la fuente de verdad del diseño |
| `docs/estado.md` | **Qué ya existe y qué se está haciendo.** Se actualiza en cada PR |
| `docs/data-model/` | El diagrama del modelo de datos |
| `force-app/main/default/` | El código y los metadatos de Salesforce |
| `scripts/` | Siembra y reconstrucción de la org. No es metadato |
| `CONTRIBUTING.md` | El manual de git y del flujo de equipo |
| `AGENTS.md` | Este archivo |

Dentro de `force-app/main/default/`:

| Carpeta | Contenido |
| --- | --- |
| `objects/` | Objetos personalizados, sus campos y el evento de plataforma |
| `globalValueSets/` | Los cuatro catálogos compartidos |
| `permissionsets/` | Conjuntos de permisos. **Todo el acceso se concede aquí** |
| `classes/` | Apex |
| `triggers/` | Disparadores |
| `lwc/` | Componentes Lightning |
| `applications/`, `tabs/`, `flexipages/` | La aplicación y su navegación |

---

## 3. Lo primero, antes de tocar nada

**Lee el documento del módulo que te toca.** No es burocracia: ahí están las decisiones ya
tomadas, con el porqué de cada una. Si implementas algo distinto, tu código va a chocar
con el de la otra persona y uno de los dos va a tener que rehacerlo.

`docs/README.md` es el índice y dice qué documento corresponde a cada historia.

Los trece, en orden:

| # | Documento | Cubre |
| --- | --- | --- |
| 01 | Contrato del mensaje | La forma del mensaje, la identidad, las validaciones |
| 02 | Ingesta | La llamada al simulador, la sesión, el cursor |
| 03 | Modelo de datos | Objetos, campos y relaciones |
| 04 | Procesamiento | El suscriptor y el trabajo en lote |
| 05 | Clasificación y límites | Umbrales y severidad |
| 06 | Estado actual | La foto de ahora y su vigencia |
| 07 | Incidentes | Casos, unicidad y escalada |
| 08 | Conectividad | Cortes de comunicación y episodios |
| 09 | Experiencia del operador | El componente Lightning |
| 10 | Seguridad y accesos | Permisos, compartición, la matriz |
| 11 | Trazabilidad | La bitácora, resultados y motivos |
| 12 | Plan de pruebas | Qué se prueba y cómo |

---

## 4. Preparar el entorno

```bash
gh repo clone joanSFDC/nova-casa-monitoreo-activos
cd nova-casa-monitoreo-activos
npm install
```

Autenticarse contra la organización y dejarla como destino por defecto:

```bash
sf org login web --alias novacasa2 \
  --instance-url https://trailsignup-95b2e3a11aa777.my.salesforce.com
sf config set target-org novacasa2 --global
```

Comprobar que responde:

```bash
sf org display -o novacasa2
```

Desplegar el metadato, asignar el permission set de administración y sembrar
el catálogo:

```bash
sf project deploy start --source-dir force-app
sf org assign permset -n Nova_Casa_Administracion
./scripts/sembrar-catalogo.sh
```

El detalle de qué queda sembrado está en [`docs/estado.md`](docs/estado.md).

---

## 5. El ciclo de un cambio

El flujo de git está en `CONTRIBUTING.md`. Lo que este documento añade es lo que pasa
entre "escribí el código" y "abro el Pull Request".

```bash
# 1 - Desplegar lo que cambiaste
sf project deploy start --source-dir force-app

# 2 - Si tocaste Apex, correr sus pruebas
sf apex run test --tests MiClaseTest --result-format human --code-coverage

# 3 - Si tocaste un LWC
npm run test:unit

# 4 - Antes de subir
npm run prettier
```

**Valida antes de desplegar** cuando el cambio sea grande o toque algo compartido. Un
`--dry-run` cuesta los mismos segundos y no deja la organización a medias:

```bash
sf project deploy start --source-dir force-app --dry-run
```

### Recuperar cambios hechos a mano en la organización

A veces es más rápido crear algo desde la interfaz de Salesforce. Si lo haces, **tráelo al
repositorio o no existe**:

```bash
sf project retrieve start --metadata CustomObject:Edificio__c
```

Nunca al revés: lo que está en la organización y no en el repositorio se pierde cuando la
organización expire.

---

## 6. Las decisiones que ya están tomadas

Estas no se vuelven a discutir en cada cambio. Si crees que una está mal, dilo en el Pull
Request y se actualiza el documento; lo que no puede pasar es que el código y la
documentación digan cosas distintas.

### Seguridad

**Todas las clases expuestas al usuario son `with sharing` y todas sus consultas llevan
`WITH USER_MODE`.** Las dos cosas, siempre. `with sharing` controla qué registros ve el
usuario pero le devuelve todos los campos, incluidos los que tiene ocultos: es necesario
pero no suficiente, y es el error de seguridad más común de la plataforma.

```apex
public with sharing class MonitorControlador {
    @AuraEnabled(cacheable=true)
    public static PanelDTO obtenerPanel(String edificioId) {
        List<Estado_Actual__c> estados = [
            SELECT Id, Tipo_Medicion__c, Valor__c, Severidad__c, Fecha_Origen__c
            FROM Estado_Actual__c
            WHERE Activo__r.Edificio__c = :edificioId
            WITH USER_MODE
        ];
    }
}
```

La única excepción son las clases de ingesta y procesamiento, que van `without sharing`
**con un comentario que lo explique**: no actúan en nombre de ninguna persona. Está acotada
a clases que ningún componente de interfaz puede invocar.

**Los permisos se conceden por conjunto de permisos, nunca por perfil.** Los perfiles están
en `.forceignore` a propósito, para que una recuperación de metadatos no los arrastre y
pise la configuración de la organización.

**Ningún secreto en el repositorio.** Ni tokens, ni contraseñas, ni claves, ni en un
comentario, ni en una captura. Las credenciales del simulador viven en una External
Credential dentro de Salesforce.

### Modelo de datos

**Edificio, activo y estado actual se relacionan por principal-detalle.** De ahí sale,
gratis y automática, la herencia de compartición que sostiene toda la matriz de seguridad.
No se cambian a búsqueda: habría que mantener reglas de compartición sincronizadas en tres
objetos, que es donde aparecen los agujeros.

**La bitácora usa búsquedas, no principal-detalle.** Con principal-detalle el activo sería
obligatorio, y una señal rechazada por activo desconocido no se podría guardar, que es
justo el caso que más necesitamos registrar.

**La severidad se guarda dos veces**: como número en `Severidad_Nivel__c` (0 normal,
1 advertencia, 2 crítico) y como texto en `Severidad__c`. No es redundancia: un resumen
automático solo opera sobre números, y el orden 0 < 1 < 2 es lo que hace que `MAX`
signifique lo peor.

**La pantalla nunca consulta `Senal__c`.** Es la única tabla que crece sin techo. El
operador consulta `Estado_Actual__c`, cuyo tamaño está acotado por el número de equipos y
no por el tiempo.

### Interfaz

**Nada se calcula en el navegador.** Todo dato que la pantalla muestra viene del servidor,
ya filtrado y ya agregado, contadores incluidos. Filtrar en el navegador no es filtrar: es
enviar y ocultar, y las herramientas de desarrollo muestran la respuesta completa.

**Los colores de severidad son los de SLDS**, `#ba0517`, `#a15c00` y `#2e844a`, y no se
cambian por los de la marca. Están elegidos por contraste, y es el único sitio donde el
color transmite información.

---

## 7. Las trampas conocidas

Cosas con las que ya tropezamos. Están aquí para que no vuelva a pasar.

**Un despliegue de metadatos no concede seguridad a nivel de campo.** Creas los campos,
despliegan sin error, y no los ve nadie: ni por pantalla, ni por SOQL, ni por Apex anónimo,
ni siquiera el administrador. Si añades un campo, **añádelo también al conjunto de
permisos** en el mismo commit. El síntoma es un "No such column" sobre un campo que sabes
que existe.

**Los campos obligatorios y los de principal-detalle no admiten entradas de seguridad a
nivel de campo.** La plataforma los considera siempre visibles, y el despliegue falla si
los incluyes en un conjunto de permisos.

**El cursor del simulador no cabe en 255 caracteres.** Ronda los 290. Eso descarta las
Custom Settings y los campos de texto normales, y es la razón de que
`Control_de_Ingesta__c` exista como objeto con un `Long Text Area`.

**En los escenarios continuos `hasMore` siempre vale `true`.** Un bucle escrito como "sigue
pidiendo mientras haya más" no termina nunca y agota los límites de la plataforma. Por eso
la ingesta tiene un tope de seis páginas por ciclo.

**Los eventos de plataforma no admiten campos únicos, ni External ID, ni relaciones.** Toda
la protección contra duplicados vive en `Senal__c.Clave__c`, y el evento lleva los códigos
externos en texto para que el suscriptor resuelva las referencias.

**Acentos y codificación.** Los archivos van en UTF-8. Los mensajes de commit van **sin**
tildes ni eñes, por convención. Las etiquetas de la interfaz sí las llevan, porque las lee
una persona. Si tu editor guarda en latin-1 vas a ver caracteres rotos en el diff:
conviértelo a UTF-8 antes de confirmar.

---

## 8. Convenciones de nombres

| Qué | Cómo | Ejemplo |
| --- | --- | --- |
| Objetos y campos | Español sin tildes ni eñes, con guion bajo | `Estado_Actual__c`, `Codigo_Externo__c` |
| Etiquetas visibles | Español **con** tildes | "Estado actual", "Código externo" |
| Valores de catálogo del proveedor | Tal cual los manda él, en mayúsculas | `WATER_PRESSURE`, `TECHNICAL_ROOM` |
| Valores de catálogo nuestros | En español legible | `Aplicado`, `Rechazado`, `Pendiente` |
| Clases Apex | Sustantivo en español, sin tildes | `MonitorControlador`, `IngestaServicio` |
| Componentes Lightning | camelCase | `monitorDeActivos` |
| Ramas y commits | Ver `CONTRIBUTING.md` | `us-203-estado-actual` |

Las claves compuestas se arman siempre con barra vertical y sin espacios:

```
Estado_Actual__c.Clave__c   AST-BOG-PUMP-001|WATER_PRESSURE
Umbral__c.Clave__c          WATER_PUMP|WATER_PRESSURE
Senal__c.Clave__c           nova-casa-simulator|msg_000002
```

---

## 9. Quién hace qué

| Persona | GitHub | Historias |
| --- | --- | --- |
| Joan Orduz | `joanSFDC` | US-201, US-202, US-207, US-208, US-209 |
| Juan José Palma (Cali) | `juanSFDC` | US-203, US-204, US-205, US-206 |

US-210 es la validación integrada y se reparte al final.

Los issues de GitHub llevan **dependencias nativas**: cada uno declara por cuáles está
bloqueado. Antes de empezar algo, mira en el issue si sus bloqueantes ya están cerrados.

---

## 10. Pull Requests e issues, siempre

Antes de escribir código y otra vez antes de abrir o actualizar un Pull Request:

**Revisa todos los Pull Requests, incluidos los fusionados y los cerrados.** Las
decisiones, los comentarios y las trampas ya descubiertas viven ahí. El #16, por
ejemplo, dejó sentado que un despliegue no concede seguridad a nivel de campo: no
hace falta volver a tropezar con eso. `gh pr list --state all` es el comando.

**Comenta en los issues a los que el cambio afecta**, no solo en el que cierras.
Un cambio de datos, de clave o de permiso suele desbloquear o condicionar el
trabajo de otra persona. El comentario dice qué cambió, qué tiene que usar a
partir de ahora y el número del PR. No se comenta un issue solo porque comparte
módulo: se comenta si quien lo implemente necesita saber algo nuevo.

Criterio para decidir si toca comentar:

| Sí, comenta | No hace falta |
| --- | --- |
| Aparece un código, un registro o un permiso que esa historia va a usar | El issue solo comparte carpeta o etiqueta |
| Una decisión de implementación cambia lo que esa historia daba por hecho | El efecto es transitivo y ya está en un bloqueante comentado |
| Desbloqueas trabajo que alguien más tiene asignado | El issue está cerrado y el dato no le aporta nada a nadie |

**Actualiza [`docs/estado.md`](docs/estado.md)** en el mismo Pull Request. Qué
entró, qué se está haciendo, cómo se reconstruye. Si no lo actualizas, el
siguiente va a sembrar a mano o a preguntar si el modelo ya existe.

Al terminar, abre el Pull Request. No se deja una rama subida esperando a que
alguien se acuerde.

## 11. Si eres un agente de IA

Además de todo lo anterior:

- **Lee el documento del módulo antes de escribir una línea.** Si el código y el documento
  no coinciden, el documento manda, salvo que expliques por qué en el Pull Request.
- **Lee `docs/estado.md` y los Pull Requests, también los cerrados**, antes de
  proponer un camino. Lo que ya se decidió no se vuelve a decidir.
- **No inventes campos ni objetos.** Todo lo que existe está en `docs/03-modelo-de-datos.md`.
  Si crees que falta algo, dilo antes de crearlo.
- **No despliegues a la organización sin avisar.** Es compartida y es la de la demostración.
- **Un issue, una rama, un Pull Request.** No mezcles módulos en un commit: si tocaste dos,
  probablemente sean dos commits. La documentación de estado y los comentarios a
  issues relacionados sí van en el mismo PR: no son otro módulo, son el rastro
  del cambio.
- **Comenta los issues afectados** según la sección 10, en el mismo turno en que
  subes el PR. No lo dejes para después.
- **Verifica, no supongas.** "Desplegó sin error" no es lo mismo que "funciona": la
  seguridad a nivel de campo es la prueba de que esas dos cosas son distintas.
