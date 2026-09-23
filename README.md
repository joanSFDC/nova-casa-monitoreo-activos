# Nova Casa · Monitoreo de activos

Sistema de monitoreo de equipos de edificios sobre Salesforce. Recibe señales de sensores
desde un proveedor externo, mantiene el estado de cada equipo, clasifica las lecturas
contra límites que el negocio administra y abre una sola intervención por problema.

Sprint 2 · fase Development.

## Por dónde empezar

| Si vas a… | Lee |
| --- | --- |
| **Escribir código** | [`CONTRIBUTING.md`](CONTRIBUTING.md) primero, siempre |
| Entender el sistema | [`docs/README.md`](docs/README.md), que es el índice |
| Construir los objetos | [`docs/data-model/`](docs/data-model/README.md) |
| Saber qué te toca | Los [issues](../../issues), con tu nombre en el asignado |

## Cómo está organizado

`docs/` es la **especificación técnica**: trece documentos, uno por módulo. Cada uno
explica el concepto técnico de base, las alternativas que se consideraron y la decisión
final, al nivel de campo y de método. No es un resumen: es el documento contra el que se
escribe el código.

Cada issue apunta al documento de su módulo. **Antes de empezar una historia, lee ese
documento**: ahí están las decisiones ya tomadas, con el porqué.

`force-app/` es el código de Salesforce.

## Las reglas cortas

1. No se trabaja directo sobre `main`. Siempre una rama.
2. No se sube nada sin Pull Request.
3. Ningún secreto en el repositorio. Ni tokens, ni contraseñas, ni claves.
4. Un issue, una rama, un Pull Request.

Los mensajes de commit siguen `etiqueta(modulo): mensaje`. El detalle, con ejemplos y la
lista de módulos válidos, está en [`CONTRIBUTING.md`](CONTRIBUTING.md).
