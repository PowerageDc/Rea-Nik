# Git y Tooling de Desarrollo

Documenta el repo git, el workspace de VS Code y el flujo de trabajo
alrededor de `Scripts/Custom/` y `reaper_www_root/`. No duplica
convenciones de nomenclatura (ver `01_CONVENCIONES.md`).

## Alcance del repo

Repo: `reaper-nik` (GitHub, privado).

El repo vive físicamente en `%APPDATA%\REAPER` (no en una carpeta aparte),
para que las rutas que REAPER resuelve en runtime no cambien. Solo trackea
dos carpetas — el resto de `%APPDATA%\REAPER` (configs, cache, `.ini`,
temas, etc.) queda fuera vía `.gitignore`:

- `Scripts/Custom/` — scripts Lua (ver estructura de subcarpetas en
  `01_CONVENCIONES.md`).
- `reaper_www_root/` — control remoto web (html/css/js).

`.gitignore`:
```
# ignorar todo por defecto
/*

# re-incluir Scripts/Custom (no todo Scripts/)
!/Scripts/
/Scripts/*
!/Scripts/Custom/

# re-incluir reaper_www_root completo
!/reaper_www_root/

# workspace de VS Code
!/reaper-rig.code-workspace
```

## Setup en una PC nueva

```powershell
cd "$env:APPDATA\REAPER"
git clone https://github.com/<usuario>/reaper-nik.git .
```

Después: re-registrar en el Action List cualquier script que se dispare
desde ahí o esté mapeado a un footswitch MIDI — los Command ID están
hasheados por ruta absoluta y son propios de cada PC (no viajan con el
repo). Ver nota en `01_CONVENCIONES.md`.

## Workspace de VS Code

`reaper-rig.code-workspace` (en la raíz de `%APPDATA%\REAPER`, trackeado en
git, con rutas relativas para que sea portable entre PCs):

```json
{
  "folders": [
    { "name": "Scripts (Lua)", "path": "Scripts/Custom" },
    { "name": "Remote Control (Web)", "path": "reaper_www_root" }
  ],
  "settings": {}
}
```

Acceso directo de escritorio apuntando a:
```
"C:\Users\<user>\AppData\Local\Programs\Microsoft VS Code\Code.exe" "%APPDATA%\REAPER\reaper-rig.code-workspace"
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