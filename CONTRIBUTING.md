# Cómo trabajar en este repositorio

Esta guía es el manual de operación del proyecto. Está escrita para seguirse paso a paso,
copiando y pegando los comandos tal cual aparecen. Si algo no encaja con lo que ves en tu
pantalla, para y pregunta antes de improvisar: es más rápido resolver una duda que
deshacer un enredo.

---

## 1. Qué hay aquí

| Carpeta | Qué contiene |
| --- | --- |
| `docs/` | **La especificación técnica.** Trece documentos, uno por módulo |
| `force-app/` | El código de Salesforce |

**Antes de escribir una sola línea de código, lee el documento del módulo que te toca.**
No es burocracia: ahí están las decisiones ya tomadas, con el porqué. Si implementas algo
distinto a lo que dice el documento, el código va a chocar con el de la otra persona.

Empieza siempre por [`docs/README.md`](docs/README.md), que es el índice y te dice qué
módulo corresponde a cada historia de usuario.

---

## 2. Preparación, una sola vez

Estos pasos se hacen **una vez en la vida** de tu computador. Si ya los hiciste, salta a
la sección 3.

### 2.1 · Comprueba que tienes git

Abre la terminal y escribe:

```bash
git --version
```

Si responde algo como `git version 2.39.5`, ya lo tienes. Si dice «command not found»,
instálalo desde [git-scm.com](https://git-scm.com/downloads) y vuelve a probar.

### 2.2 · Dile a git quién eres

Git firma cada cambio con tu nombre y tu correo. **Usa tu correo de Salesforce**, el mismo
con el que entras a todo lo demás.

```bash
git config --global user.name "Tu Nombre Completo"
git config --global user.email "tu.correo@salesforce.com"
```

Comprueba que quedó bien:

```bash
git config --global user.name
git config --global user.email
```

Tiene que responder exactamente lo que escribiste. Si te equivocaste, vuelve a ejecutar el
comando con el valor correcto: se sobrescribe sin problema.

> **Por qué importa:** si el correo está mal, tus cambios aparecen en GitHub como si los
> hubiera hecho un desconocido, y no se te acreditan.

### 2.3 · Conéctate a GitHub

GitHub ya no acepta contraseña desde la terminal. La forma más cómoda es la herramienta
oficial `gh`.

**Instálala** (en Mac, con Homebrew):

```bash
brew install gh
```

**Inicia sesión:**

```bash
gh auth login
```

Te va a hacer cuatro preguntas. Responde así, moviéndote con las flechas y confirmando con
Enter:

| Pregunta | Respuesta |
| --- | --- |
| *What account do you want to log into?* | `GitHub.com` |
| *What is your preferred protocol...?* | `HTTPS` |
| *Authenticate Git with your GitHub credentials?* | `Yes` |
| *How would you like to authenticate?* | `Login with a web browser` |

Te va a mostrar un código de ocho caracteres, tipo `A1B2-C3D4`. **Cópialo.** Presiona Enter
y se abre el navegador; pega el código, autoriza, y vuelve a la terminal.

**Comprueba que funcionó:**

```bash
gh auth status
```

Tiene que decir `✓ Logged in to github.com account ...` con tu usuario.

> Si tu cuenta de GitHub no es la de Salesforce, no pasa nada: lo importante es que el
> **correo del paso 2.2** sea el de Salesforce, porque es el que firma los cambios.

### 2.4 · Descarga el proyecto

Colócate donde quieras guardarlo y ejecuta:

```bash
gh repo clone joanSFDC/nova-casa-monitoreo-activos
cd nova-casa-monitoreo-activos
```

Ya está. A partir de aquí, **todos los comandos se ejecutan dentro de esta carpeta.**

---

## 3. El ciclo de trabajo

Este es el ciclo completo. Se repite igual para cada tarea, siempre en el mismo orden.

### Paso 1 · Ponte al día

Antes de empezar cualquier cosa, trae los cambios que la otra persona ya subió:

```bash
git checkout main
git pull
```

> **Nunca te saltes este paso.** Si empiezas a trabajar sobre una versión vieja, después
> hay que reconciliar dos versiones distintas del mismo archivo, y eso es lo único
> realmente incómodo de git.

### Paso 2 · Crea tu rama

Una rama es tu copia privada para trabajar sin estorbar a nadie.

```bash
git checkout -b us-203-estado-actual
```

El nombre se arma así: **el número de la historia, y un resumen corto en minúsculas y con
guiones.**

| Historia | Nombre de la rama |
| --- | --- |
| US-203 | `us-203-estado-actual` |
| US-204 | `us-204-limites-administrables` |
| US-205 | `us-205-una-sola-intervencion` |
| US-206 | `us-206-severidad` |

Sin tildes, sin eñes, sin espacios y sin mayúsculas.

### Paso 3 · Trabaja

Escribe tu código. Cuando quieras ver qué has tocado:

```bash
git status
```

Te lista los archivos modificados. Es seguro ejecutarlo tantas veces como quieras: solo
mira, no cambia nada.

### Paso 4 · Guarda tus cambios

Se hace en dos tiempos, y esto confunde a todo el mundo al principio. `git add` es
**elegir** qué cambios entran; `git commit` es **guardarlos** con un mensaje.

```bash
git add .
git commit -m "feat(estado): aplicar solo la lectura mas reciente por activo y medicion"
```

El punto en `git add .` significa «todo lo que cambié». El mensaje va entre comillas y
sigue la convención de la sección 4, que es obligatoria.

### Paso 5 · Súbelo a GitHub

**La primera vez** en cada rama:

```bash
git push -u origin us-203-estado-actual
```

**Las veces siguientes**, en esa misma rama, basta con:

```bash
git push
```

### Paso 6 · Abre el Pull Request

Un Pull Request es pedir que tus cambios entren a `main`. Se crea así:

```bash
gh pr create --fill
```

Después ábrelo en el navegador para revisarlo y completar la descripción:

```bash
gh pr view --web
```

### Paso 7 · Avisa y mueve la tarjeta

Escribe en el chat del equipo que el Pull Request está listo, y **mueve la tarjeta en
MDSS** de `In Progress` a `Code Review`.

### Paso 8 · Cuando te lo aprueben

Se fusiona el Pull Request desde GitHub, y tú vuelves al paso 1 para la siguiente tarea.

---

## 4. Cómo se escriben los mensajes de commit

**Todos los mensajes siguen esta forma, sin excepciones:**

```
etiqueta(modulo): mensaje
```

Ejemplo real:

```
feat(incidentes): reutilizar el caso abierto en lugar de crear uno nuevo
```

Tres piezas. La **etiqueta** dice qué clase de cambio es. El **módulo** dice dónde. El
**mensaje** dice qué hace, en una frase.

### Las etiquetas

| Etiqueta | Cuándo se usa |
| --- | --- |
| `feat` | Código nuevo que añade una capacidad |
| `fix` | Arreglar algo que estaba mal |
| `test` | Añadir o cambiar pruebas |
| `docs` | Cambios en la documentación o en comentarios |
| `refactor` | Reorganizar código sin cambiar lo que hace |
| `chore` | Configuración, metadatos, permisos, datos de ejemplo |

### Los módulos

Son los mismos nombres que la carpeta `docs/`, para que exista un solo vocabulario en todo
el proyecto.

| Módulo | Qué abarca | Documento |
| --- | --- | --- |
| `contrato` | La forma del mensaje y sus validaciones | [01](docs/01-contrato-del-mensaje.md) |
| `ingesta` | Llamada al simulador, sesión, cursor, publicación | [02](docs/02-ingesta.md) |
| `modelo` | Objetos, campos y relaciones | [03](docs/03-modelo-de-datos.md) |
| `procesamiento` | El suscriptor y el trabajo en lote | [04](docs/04-procesamiento.md) |
| `limites` | Umbrales y clasificación de severidad | [05](docs/05-clasificacion-y-limites.md) |
| `estado` | El estado actual por activo y medición | [06](docs/06-estado-actual.md) |
| `incidentes` | Casos, escalada y duplicados | [07](docs/07-incidentes.md) |
| `conectividad` | Latidos, cortes y episodios | [08](docs/08-conectividad.md) |
| `monitor` | El componente del operador | [09](docs/09-experiencia-del-operador.md) |
| `seguridad` | Permisos, compartición y matriz de acceso | [10](docs/10-seguridad-y-accesos.md) |
| `trazabilidad` | La bitácora de señales | [11](docs/11-trazabilidad.md) |
| `pruebas` | Pruebas y datos de prueba | [12](docs/12-plan-de-pruebas.md) |
| `repo` | Configuración del proyecto, nada de negocio |  |

### Cómo se escribe el mensaje

- **En minúscula**, salvo nombres propios.
- **Sin punto final.**
- **Sin tildes ni eñes.** Evita problemas de codificación entre computadores distintos.
- **En infinitivo**, describiendo qué hace el cambio: «añadir», «corregir», «mover».
- **Máximo 70 caracteres.** Si no cabe, probablemente sean dos commits.
- **Di el qué, no el cómo.** El código ya muestra el cómo.

### Ejemplos

Así sí:

```
feat(ingesta): encadenar paginas con tope de seis por ciclo
feat(limites): clasificar por intervalos cerrados en las fronteras
fix(estado): no reemplazar la lectura vigente con una atrasada
test(incidentes): cerrar y reabrir para verificar que se libera la clave
docs(conectividad): documentar los tres estados de comunicacion
chore(repo): anadir conjunto de permisos del usuario de integracion
```

Así no, y por qué:

| Mensaje | Problema |
| --- | --- |
| `cambios` | No dice nada |
| `Arreglado el bug` | Falta etiqueta y módulo, y no dice qué bug |
| `feat: nueva funcionalidad` | Falta el módulo, y «funcionalidad» no informa |
| `feat(estado): Arreglé el problema.` | Empieza en mayúscula, tiene punto y es vago |
| `WIP` | No se suben trabajos a medias a `main` |

> **Si no sabes qué módulo poner**, mira en qué carpeta está el archivo que tocaste y busca
> su documento en la tabla de arriba. Si tocaste varios módulos, es señal de que el commit
> debería partirse en dos.

---

## 5. Los Pull Requests

**El título del Pull Request usa exactamente la misma forma que los commits**, y menciona
la historia:

```
feat(estado): mantener la lectura mas reciente por activo y medicion (US-203)
```

En la descripción, tres cosas y nada más:

1. **Qué hace**, en dos o tres frases.
2. **Cierra #N**, con el número del issue. Escribir literalmente la palabra `Cierra`
   seguida del número hace que GitHub cierre el issue solo al fusionar.
3. **Cómo se probó**: qué escenario del simulador usaste o qué prueba escribiste.

Antes de pedir revisión, comprueba estas cuatro:

- [ ] Hice lo que dice el documento del módulo, o expliqué en el PR por qué me aparté
- [ ] No hay tokens, contraseñas ni claves en ningún archivo
- [ ] Las pruebas pasan
- [ ] Los mensajes de commit siguen la convención

> **Sobre la segunda:** el token del simulador **nunca** va en un archivo del repositorio,
> ni en un comentario, ni en una captura de pantalla. Vive en la configuración de
> Salesforce. Está explicado en [`docs/02-ingesta.md`](docs/02-ingesta.md).

---

## 6. Cuando algo sale mal

Nada de lo que hagas en tu rama es irreversible. Estos son los apuros más comunes.

**«Hice commit con el mensaje mal escrito»**  Si todavía no lo subiste:

```bash
git commit --amend -m "feat(estado): el mensaje correcto"
```

**«Quiero deshacer todo lo que cambié desde el último commit»**  Ojo, esto borra tu
trabajo sin guardar:

```bash
git checkout .
```

**«Empecé a trabajar sin crear la rama, estoy en main»**  Tranquilo, no has perdido nada.
Crea la rama ahora y tus cambios se vienen contigo:

```bash
git checkout -b us-203-estado-actual
```

**«Me dice que hay conflictos»**  Es que los dos tocaron el mismo archivo. No lo resuelvas
a ciegas: escribe en el chat del equipo y se mira en conjunto.

**«No sé en qué rama estoy»**

```bash
git branch --show-current
```

**«Quiero ver qué he hecho»**

```bash
git log --oneline -10
```

---

## 7. Las reglas que no se negocian

1. **No se trabaja directo sobre `main`.** Siempre una rama.
2. **No se sube nada sin Pull Request.**
3. **Ningún secreto en el repositorio.** Ni tokens, ni contraseñas, ni claves.
4. **Se lee el documento del módulo antes de escribir código.**
5. **Un issue, una rama, un Pull Request.**
6. **Si te apartas de lo documentado, lo explicas en el Pull Request.** Puede que tengas
   razón y haya que actualizar el documento; lo que no puede pasar es que el código y la
   documentación digan cosas distintas sin que nadie lo sepa.
