# Git y Tooling de Desarrollo

Documenta el repo git, el workspace de VS Code y el flujo de trabajo del
repo `Rea-Nik`. No duplica convenciones de nomenclatura (ver
`01_CONVENCIONES.md`) ni el detalle de por qué el repo vive fuera de
`%APPDATA%\REAPER` (ver "Entorno de desarrollo" en
`00_CONTEXTO_GENERAL.md`).

## Alcance del repo

Repo: `Rea-Nik` (GitHub, privado).

El repo vive en `C:\dev\Rea-Nik\`, fuera de `%APPDATA%\REAPER` — el Command
ID de un script no depende de que viva bajo el resource path de REAPER
(se resuelve por dónde REAPER lo encuentra al registrarlo, no por
convención de carpeta), así que no hace falta la raíz vieja. Toda la
carpeta es del repo, sin allow-list de `.gitignore`:

- Carpetas de dominio (`AutoColor/`, `RemoteControl/`, etc.) — scripts Lua,
  ver estructura en `01_CONVENCIONES.md`.
- `web/` — control remoto web (html/css/js), expuesto a REAPER vía junction
  (ver abajo).
- `_docs/` — esta documentación.

`.gitignore` (mínimo, solo ruido de SO/editor — ya no hace falta allow-list
porque no hay nada ajeno al repo en esta carpeta):
```
# Sistema operativo
Thumbs.db
Desktop.ini
.DS_Store

# VS Code (config de usuario, si en algún momento se generan)
.vscode/*.log
```

**Junction para `reaper_www_root`**: el servidor web embebido de REAPER
espera esa carpeta en una ubicación fija dentro de su resource path, así
que `web/` se expone ahí vía junction (no symlink — no requiere admin en
Windows 10):
```powershell
New-Item -ItemType Junction -Path "$env:APPDATA\REAPER\reaper_www_root" -Target "C:\dev\Rea-Nik\web"
```
Se crea una sola vez por PC (dev o destino con setup manual); no viaja con
el repo ni con `git clone`.

## Setup en una PC nueva

```powershell
git clone https://github.com/PowerageDc/Rea-Nik.git C:\dev\Rea-Nik
```

Después, crear el junction de `reaper_www_root` (ver comando arriba, en
"Alcance del repo") — necesario en cualquier PC nueva, dev o destino.

Después: re-registrar en el Action List cualquier script que se dispare
desde ahí o esté mapeado a un footswitch MIDI — los Command ID están
hasheados por ruta absoluta y son propios de cada PC (no viajan con el
repo). Ver nota en `01_CONVENCIONES.md`.

## Workspace de VS Code

`Rea-Nik.code-workspace` (en la raíz de `C:\dev\Rea-Nik\`, trackeado en
git). Carpeta única — al vivir el repo fuera de `%APPDATA%\REAPER`, ya no
hace falta abrir subcarpetas sueltas vía `.gitignore` allow-list; abrir la
raíz del repo directo también resolvió que GitGraph (y en general
cualquier extensión que espere el repo entre las carpetas abiertas) vea
el historial correctamente:

```json
{
    "folders": [
        { "path": "." }
    ],
    "settings": {}
}
```

Acceso directo de escritorio apuntando a:
```
"C:\Users\<user>\AppData\Local\Programs\Microsoft VS Code\Code.exe" "C:\dev\Rea-Nik\Rea-Nik.code-workspace"
```
(sin `.bat`/`cmd.exe` de por medio, abre directo sin ventana de consola).

## Flujo básico de git

- `git status` — qué cambió sin comitear.
- `git add .` / `git add <archivo>` — stagear cambios.
- `git commit -m "<dominio>: <qué cambió>"` — ver convención de mensajes
  abajo.
- `git push` — subir a GitHub (una vez seteado el upstream con
  `git push -u origin main`, después alcanza con `git push` solo).
- `git log --oneline` — historial compacto, un commit por línea. Punto de
  partida para ubicar un commit viejo antes de usar `diff`/`checkout`.
- `git diff` — cambios sin comitear todavía, línea por línea.
- `git diff <commit1> <commit2>` — compara dos commits puntuales.
- `git restore <archivo>` (o `git checkout -- <archivo>`) — descarta
  cambios sin comitear en ese archivo, vuelve al último commit. El
  "control-Z de sesión" antes de comitear.
- `git checkout <hash> -- <archivo>` — trae la versión de un archivo
  puntual desde un commit viejo, sin tocar el resto del repo.

## Convención de mensajes de commit

```
<dominio>: <qué cambió>
```
Ejemplos: `ReaPitchBus: fix reset en doble-click`,
`remote_control: agregar marker_bars al poll`,
`tooling: reorganizar Scripts/Custom en subcarpetas por dominio`.

`<dominio>` coincide, cuando aplica, con el nombre de subcarpeta o con el
`<Dominio>` del naming de scripts (`01_CONVENCIONES.md`). Para cambios que
no son de un dominio específico (setup, docs, estructura), usar `tooling`
o `docs`.

## Gotchas conocidos

- Mover/renombrar un `.lua` ya registrado en REAPER invalida su Command
  ID — re-registrar ("Load ReaScript") desde la ubicación nueva antes de
  comitear, para no dejar una ventana donde el archivo en disco y lo
  registrado en REAPER no coincidan.
- `git add .` sobre una carpeta nueva no expande el listado hasta el
  primer `add` — para revisar qué va a entrar antes de comitear, hacer
  `git add .` seguido de `git status` (no fiarse del status previo al add
  en carpetas sin trackear todavía).
- Herramientas basadas en `rugged`/`libgit2` (ej. `reapack-index`) hacen
  un chequeo de "ownership" del repo más estricto que git nativo — tiran
  `Rugged::ConfigError: repository path ... is not owned by current user`
  aunque `git status` funcione sin problema. Fix: agregar la ruta como
  segura en la config global de git (barras `/`, no `\`, aunque sea ruta
  Windows):
  ```
  git config --global --add safe.directory "C:/dev/Rea-Nik"
  ```