# Documentación técnica · Nova Casa

Esta carpeta es la especificación de implementación de la fase Development del Sprint 2.
No es un resumen del discovery: es el documento contra el que se escribe el código.

Cada módulo sigue la misma estructura. Primero explica el concepto técnico de base,
porque una decisión solo se puede discutir si se entiende el mecanismo sobre el que se
apoya. Después presenta las alternativas que se consideraron. Y termina con la decisión
final y cómo funciona exactamente, al nivel de campo y de método.

## Índice

| Módulo | De qué trata | Historias que cubre |
| --- | --- | --- |
| [01 · Contrato del mensaje](01-contrato-del-mensaje.md) | Qué manda el simulador, campo por campo, verificado contra la API real | US-201 |
| [02 · Ingesta](02-ingesta.md) | Sesión, cursor, paginación, cadencia, errores y reintentos | US-201 |
| [03 · Modelo de datos](03-modelo-de-datos.md) | Objetos, campos, claves y relaciones | US-201, US-203, US-209 |
| [04 · Procesamiento](04-procesamiento.md) | El suscriptor, el enrutado y el aislamiento de fallos en lote | US-202 |
| [05 · Clasificación y límites](05-clasificacion-y-limites.md) | Bandas, fronteras, unidades y administración de umbrales | US-204, US-206 |
| [06 · Estado actual](06-estado-actual.md) | La foto de ahora, mensajes atrasados y resumen por activo | US-203, US-206 |
| [07 · Incidentes](07-incidentes.md) | Una sola intervención, escalada y concurrencia | US-205 |
| [08 · Conectividad](08-conectividad.md) | Latidos, cortes, episodios y escalada por tiempo | US-205, US-206 |
| [09 · Experiencia del operador](09-experiencia-del-operador.md) | El componente propio y su contrato con el servidor | US-207 |
| [10 · Seguridad y accesos](10-seguridad-y-accesos.md) | Matriz de acceso y las tres fronteras de autorización | US-208 |
| [11 · Trazabilidad](11-trazabilidad.md) | La bitácora, los resultados y qué se puede reintentar | US-209 |
| [12 · Plan de pruebas](12-plan-de-pruebas.md) | Qué escenario del simulador demuestra cada criterio | US-202, US-210 |
| [Diagrama del modelo](data-model/README.md) | El modelo de datos dibujado campo por campo, para construirlo | — |

## Lo que cambió respecto al discovery

El discovery se escribió contra el ejemplo del enunciado. La documentación de la API
real llegó después y obligó a rehacer parte del contrato. Los cambios están detallados
en cada módulo, pero conviene tener presentes los cuatro de fondo:

1. El tipo de mensaje de comunicación se llama `CONNECTIVITY`, no `COMMUNICATION_STATUS`,
   y sus datos vienen anidados en un objeto `communication`.
2. El simulador calcula y envía `gapSeconds`. No tenemos que medir el silencio nosotros.
3. Cada corte de comunicación trae un `episodeId` propio, que resuelve la identidad del
   incidente de conectividad mejor que la clave que habíamos diseñado.
4. Cada mensaje trae dos identificadores: `messageId`, que es el mensaje, y `deliveryId`,
   que es el intento de entrega. La deduplicación va por el primero.

## Supuestos del discovery, resueltos contra la API

| Supuesto | Estado |
| --- | --- |
| S-01 · El aviso de pérdida se repite mientras la pérdida continúa | **Confirmado.** `CAMERA_OUTAGE` emite `LOST` sucesivos con `gapSeconds` creciente |
| S-02 · Agua y energía son mediciones distintas | **Confirmado.** `WATER_CONSUMPTION` y `ENERGY_CONSUMPTION`, con unidades distintas |
| S-03 · Un mensaje de comunicación no trae valor ni unidad | **Confirmado.** Trae `communication`, nunca `measurement` |
| S-04 · Los límites caben en el modelo de cuatro valores | **Confirmado.** Los rangos son bidireccionales y encajan |

## Preguntas abiertas, resueltas contra la API

| Pregunta | Respuesta |
| --- | --- |
| Q-06 · ¿Cargamos los edificios y activos o los crea el proceso? | `GET /catalog` los expone. Se siembran antes de la demo |
| Q-08 · ¿Cada cuánto produce datos y qué demora es aceptable? | `pollAfterMs` es 10 000 ms. Ver [módulo 02](02-ingesta.md) |
| Q-14 · ¿El aviso de pérdida se repite? | Sí. Cierra el riesgo R-16 |
| Q-16 · ¿El aviso viene por sensor, activo o edificio? | Por activo, con el sensor como dato informativo |
| Q-17 · ¿Qué valor informa la recuperación? | `RESTORED`. Existe además `HEALTHY` como latido |

Siguen abiertas Q-09 (volumen esperado en producción), Q-10 (cómo se asigna el operador
a edificios), Q-11 (política de retención de la bitácora) y Q-13 (el vocabulario de
cara al usuario). Ninguna bloquea la implementación del sprint.
