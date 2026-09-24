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
| Conjuntos de permisos (cinco roles) | En esta rama | `force-app/main/default/permissionsets/` |
| Siembra del catálogo (issue #3) | En `main` | [PR #17](https://github.com/joanSFDC/nova-casa-monitoreo-activos/pull/17) |
| Usuarios de la demo (issue #14) | En curso | `scripts/crear-usuarios-demo.sh` |
| Ingesta US-201 | Pendiente | Issue #4 |
| El resto de historias | Pendiente | Issues #5 a #13 |
| Identidad visual | Pendiente | Issue #15 |

Org de trabajo: alias `novacasa2`, dominio
`trailsignup-95b2e3a11aa777`. Caduca el 23 de octubre de 2026. Lo que no esté
en el repositorio desaparece ese día.

## Qué hay hoy en la org

### Modelo

Ocho elementos desplegados y verificados:

- Objetos: `Edificio__c`, `Activo__c`, `Estado_Actual__c`, `Umbral__c`,
  `Senal__c`, `Control_de_Ingesta__c`
- Evento: `Aviso_de_Senal__e` (publicación inmediata)
- Campos en `Case`: `Clave_Abierta__c`, `Activo__c`, `Tipo_Medicion__c`,
  `Episodio_Id__c`, `Origen_Senal__c`
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
| `AST-BOG-WMET-001` / `AST-BAQ-WMET-001` | Medidor de agua |
| `AST-BOG-EMET-001` / `AST-BAQ-EMET-001` | Medidor de energía |
| `AST-BOG-PUMP-001` / `AST-BAQ-PUMP-001` | Bomba de presión |
| `AST-BOG-CAM-001` / `AST-BAQ-CAM-001` | Cámara |

Tres códigos salen de los ejemplos de [módulo 01](01-contrato-del-mensaje.md):
`AST-BOG-PUMP-001`, `AST-BOG-CAM-001`, `AST-BAQ-TEMP-001`. Los otros siete
siguen el mismo patrón. Si `GET /catalog` usa IDs distintos, se cambian en el
script, no en el modelo.

Umbrales, clave `Tipo_Activo\|Tipo_Medicion`:

| Clave | Unidad | Banda |
| --- | --- | --- |
| `TECHNICAL_ROOM\|TEMPERATURE` | `CELSIUS` | 14.9 / 17.9 / 30.1 / 35.1 |
| `WATER_PUMP\|WATER_PRESSURE` | `BAR` | 1.49 / 2.49 / 4.01 / 5.01 |
| `WATER_METER\|WATER_CONSUMPTION` | `LITER_PER_15_MIN` | solo alto: 401 / 651 |
| `ENERGY_METER\|ENERGY_CONSUMPTION` | `KWH_PER_15_MIN` | solo alto: 40.1 / 65.1 |
| `SECURITY_CAMERA\|CAMERA_CONNECTIVITY` | (vacío) | 15 min advertencia, 60 min crítico |

La cámara no tiene umbrales de valor. `SECONDS` no está en el conjunto global
`Unidad`; no se añadió en la siembra para no mezclar modelo con datos.

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
estado actual heredan.

La aplicación `Nova_Casa` existe como cascarón (pestañas del modelo). Logo y
tema son el issue #15.

## Cómo reconstruir el entorno

```bash
sf project deploy start --source-dir force-app -o novacasa2
sf org assign permset -o novacasa2 -n Nova_Casa_Administracion
./scripts/sembrar-catalogo.sh novacasa2
./scripts/crear-usuarios-demo.sh novacasa2
```

## Qué se está haciendo ahora

Usuarios, conjuntos de permisos y compartición, issue #14. Desbloquea las
pruebas de US-208. Joan sigue con US-201 (issue #4), la ingesta.

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

## Historial breve

| Fecha | Qué |
| --- | --- |
| 2026-09-23 | Proyecto DX, modelo y permission set de administración. PR #16 fusionado. Cierra #2 |
| 2026-09-24 | Script de siembra del catálogo. PR #17 fusionado. Cierra #3 |
| 2026-09-24 | Usuarios de la demo, cinco conjuntos y reglas por ciudad. Issue #14 |
