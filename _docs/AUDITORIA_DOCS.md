# Auditoría de docs

Cómo auditar y limpiar un doc del repo: política, métodos de búsqueda y
limpieza, reparto de datos entre docs, referencias y arranque de una
conversación nueva. Lo lee quien va a auditar un doc, o quien escribe uno
nuevo y quiere que nazca dentro de la política. Convenciones generales y
reglas de comentarios de código: `01_CONVENCIONES.md`.

## 1. Política

**Un doc describe cómo está hecho hoy.** La historia es el repo (`git
log`); el doc no la cuenta.

Qué se escribe:

- Hechos vigentes: qué hace, con qué nombres, con qué valores.
- El motivo de una decisión cuando evita una regresión o una duda
  recurrente (una frase junto al hecho, no un relato).
- Gotchas verificados: lo que falla si se hace distinto.
- Lo descartado y por qué, en una sección propia, solo si evita reabrir la
  discusión.
- Lo no probado o no hecho, **solo** en la sección de pendientes.

Qué no se escribe:

- Pasos, fases, etapas, líneas (A/B/C), versiones del plan ("v1", "paso
  3c"), marcas de avance (✅, "cerrado", "hecho").
- Informes de prueba: dónde se verificó (dev, sala, celular), cuántas
  pruebas, qué bytes midió una sesión. Si algo funciona se escribe como
  hecho; si no se probó, es un pendiente.
- Fechas y versiones de herramientas de una sesión concreta.
- Marcas de "resuelto", "antes", "ya no", "ahora", "nuevo", "todavía no",
  "por ahora", "a futuro" fuera de una sección de pendientes. De un
  "resuelto" se conserva solo el hecho vivo que dejó.
- Citas a docs que ya no existen o a investigaciones fuera del repo.
- Pendientes de una feature en un doc central.

Prueba rápida por línea: ¿sigue siendo verdad si nadie toca el repo
durante un año? Si no, es historia, un pendiente o un error.

## 2. Un dato, un hogar

Cada dato vive en un solo doc; los demás lo citan en una línea con
puntero. Hogar según qué es el dato:

| Dato | Hogar |
|---|---|
| Formato de una key, protocolo, escape del web control | doc de modelo de datos de la feature |
| Código que ya tiene doc propio (dispatchers, polls, ciclo de proyecto) | el doc de ese código, no el de la feature que lo usa |
| Deploy, `@provides`, config que ReaPack pisa | `05_REAPACK_DEPLOY.md` |
| Nombres, estructura de carpetas, patrones de módulos | `01_CONVENCIONES.md` |
| Estado, decisiones y pendientes de una feature | el doc de la feature (o el de su capa) |
| Estado en una línea por feature, y qué adjuntar | `00_CONTEXTO_GENERAL.md`, **sin pendientes** |

- Un pendiente tiene un solo hogar: el doc de la capa donde se resuelve.
  Los demás lo omiten o lo citan.
- Un patrón (p. ej. "uno dispara el script, otro solo lee") se explica en
  un doc; los demás declaran que lo usan, en una línea.
- Un mismo estado ("no_pair", "status") no se describe en tres secciones:
  se elige la tabla canónica y el resto la cita.

## 3. Relación docs ↔ código

- Los docs citan código (archivos, funciones, constantes). El código no
  cita docs ni secciones, ni historia (`01_CONVENCIONES.md`).
- Al renombrar o mover código, los docs se actualizan con una búsqueda de
  los nombres (§5).

## 4. Estructura y cuándo partir un doc

Capas habituales de una feature: Lua (ruteo, filtro, config), datos
(contrato, cliente), UI. Criterios:

- **Capas dentro del mismo doc** si cada una es corta y se lee junta.
- **Split** cuando un subsistema tiene archivos, herramienta y pendientes
  propios y quien lo toca no necesita el resto (precedente: la tab Lyrics
  del Helper). Un doc hub conserva estado, decisiones y contrato; el doc
  de la capa, el detalle y su "Para retomar".
- **No partir** cuando lo que sobra ya tiene otro hogar (protocolo,
  timing, módulos visuales): primero se quitan duplicados, después se
  mide. Un hub razonable queda alrededor de 250 líneas; sobre 300, se
  reevalúa.
- Estructura típica del doc de una capa: qué hace, archivos, secciones por
  tema, pendientes, "Para retomar" (qué adjuntar).

## 5. Métodos de búsqueda (PowerShell, desde la raíz del repo)

Sin `grep`: `Select-String` alcanza.

**Línea base de referencias.** Antes y después de cualquier cambio:

```powershell
.\Tests-Debug\check_refs.ps1
```

**Quién cita el doc** (docs y código):

```powershell
$d = "monitor_mix"   # nombre sin extensión
Select-String -Path _docs\*.md,_docs\features\*.md -Pattern $d | ForEach-Object { "$($_.Filename):$($_.LineNumber): $($_.Line.Trim())" }
Get-ChildItem -Recurse -Include *.lua,*.js,*.html,*.ps1 | Where-Object { $_.FullName -notmatch '\\\.git\\' } | Select-String -Pattern $d
```

**Señales de historia** en un doc (pasos y fases, temporales, validaciones
narradas, fechas):

```powershell
.\Tests-Debug\check_history.ps1 _docs\features\<doc>.md
```

Cada coincidencia se juzga: "hoy" o "nuevo" a veces son legítimos. La
lista es un punto de partida, no un veredicto.

**Citas sin `§`** (de la forma "doc 3.5", "doc paso 2"):

```powershell
Select-String -Path _docs\*.md,_docs\features\*.md -Pattern '\.md`?\s+\d' | ForEach-Object { "$($_.Filename):$($_.LineNumber): $($_.Line.Trim())" }
```

**Datos duplicados con otros docs.** Los identificadores entre backticks
del doc (funciones, constantes, keys) que aparecen también en otros docs
son candidatos a duplicación:

```powershell
$doc = "_docs\features\ARCHIVO.md"
$leaf = Split-Path $doc -Leaf
$ids = Select-String -Path $doc -Pattern '`([A-Za-z_][A-Za-z0-9_.]{5,})`' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
foreach ($i in $ids) {
  $hits = Select-String -Path _docs\*.md,_docs\features\*.md -Pattern $i -SimpleMatch | Where-Object { $_.Filename -ne $leaf }
  if ($hits) { "$i -> " + (($hits | ForEach-Object Filename | Sort-Object -Unique) -join ', ') }
}
```

**Estado real del código** cuando el doc afirma algo verificable (qué
carga un HTML, qué función llama otra):

```powershell
Select-String -Path web\ARCHIVO.html -Pattern "<script|<link"
Select-String -Path web\musicstate-ui\DOMINIO\*.js -Pattern "funcionA|funcionB"
```

Una afirmación del doc que el código contradice es un error, no una
cuestión de estilo: se corrige o se anota como pendiente.

## 6. Referencias

- Citas siempre con `§` y nombre de archivo (`<doc>` §5), nunca un
  número suelto.
- Al **mover, renombrar o dividir** secciones, se buscan las citas
  entrantes (§5) y se corrigen antes de dar el cambio por cerrado.
- Si solo cambia el título de una sección, se **conserva la numeración**:
  las citas a `§N` siguen válidas.
- Si se agrega una sección, va al final de su bloque o con numeración que
  no desplace las citadas.
- Al final, `check_refs.ps1` limpio.

## 7. Proceso de auditoría de un doc

1. **Inventario:** tabla de secciones del doc con su capa, tamaño
   aproximado y citas entrantes y salientes.
2. **Hallazgos**, en este orden: errores y contradicciones (con el código o
   con otros docs), duplicaciones (tabla dato / dónde está / hogar),
   historia y narrativa, referencias rotas, estructura.
3. **Decisiones** que dependen de quien conoce el estado real (qué está
   realmente cerrado, qué doc citado ya no existe, qué se conserva como
   motivo). Se preguntan antes de escribir.
4. **Cambios.** Si el contenido se reubica o se reescribe en gran parte,
   el doc completo (uno por mensaje, avisando el tamaño). Si no, diffs de
   buscar/reemplazar en bloques de código, de a pocos archivos por
   mensaje, con la fuente literal que se ve en el adjunto.
5. **Cierre:** `check_refs.ps1`, búsqueda de citas entrantes, y un solo
   commit.

## 8. Qué adjuntar para auditar un doc

- El doc a auditar.
- `01_CONVENCIONES.md` y `00_CONTEXTO_GENERAL.md`.
- Los docs que el doc cita o que lo citan (salida de la búsqueda de citas
  entrantes, §5), y los que comparten identificadores con él.
- Salida de `check_refs.ps1`.
- Código solo si el doc afirma algo verificable que hay que confirmar.

Un doc ya auditado sirve de modelo de estructura; adjuntarlo solo si hace
falta como referencia.

## 9. Commits

Conventional Commits: prefijo y `(dominio)` en inglés, el resto en
español con tildes. Durante la sesión, commits `wip(...)` locales cortos;
al terminar, un solo commit:

```powershell
git reset --soft (git merge-base main HEAD)
git commit    # el mensaje en el editor, no con -m (tildes en PowerShell 5.1)
git checkout main
git merge --ff-only RAMA
git branch -d RAMA
```

`_docs/` queda fuera del escaneo de `reapack-index`: un commit solo de docs
no necesita `--rebuild` ni bump de `@version`.

## 10. Prompt de arranque

Adjuntar los archivos de §8 y pegar, cambiando el doc:

```
Quiero auditar `<doc>` siguiendo `AUDITORIA_DOCS.md` (adjunto).
Modo de trabajo del proyecto: un paso por vez, esperando mi confirmación;
aviso antes de más de 300 líneas; diffs listos para buscar/copiar/pegar.

Paso 1: inventario de secciones (capa, tamaño, citas entrantes y
salientes) y hallazgos según §7: errores y contradicciones, duplicaciones
con otros docs (dato / dónde está / hogar propuesto), historia y
narrativa, referencias, estructura. Sin escribir cambios todavía.
Terminá con las decisiones que necesitás de mí y los comandos de §5 que
debo correr (no tenés acceso al repo).

Contexto: <qué se sabe del estado real: qué está cerrado, qué doc citado
ya no existe, etc.>
```
