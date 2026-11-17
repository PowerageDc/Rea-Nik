# Deploy pendiente

Se vacía al publicar. Reglas y uso en `05_REAPACK_DEPLOY.md`, sección
"Deploy pendiente". El título de cada sección lleva la versión publicada.

## RemoteControl (scripts) — publicado 1.11

## MusicState (scripts) — publicado 1.7

- M Módulo de foco de ventanas ReaImGui: suma toHwnd, sin cambios visibles en el Helper
- M Cues con posición y duración libres (ya no en grilla): lista con filtro por rol, panel de edición y alta en el cursor; los cues guardados antes se leen sin migración → @provides del Helper: `MusicStateCuesModel_common_logic.lua`, `MusicStateCuesData_common_logic.lua`, `MusicStateCuesEdit_common_logic.lua`, `MusicStateJson_common_logic.lua`
- M Roles desde un catálogo (bajo, bateria, guitarra, guitarra 2, teclado, teclado 2, voz) en vez de tipearlos: un rol con cues no se puede quitar y un proyecto sin roles guardados arranca con los de por defecto → @provides del Helper: `MusicStateRoles_config.lua`; la config se pisa en destino
- M Guardar y cargar roles y cues con comillas, llaves o barras en el texto ya no rompe el dato
- M Publicación de letras: usa el módulo JSON compartido, sin cambios visibles → instalar junto con `MusicStateJson_common_logic.lua`

## MonitorMix (scripts) — publicado 1.2

## ProjectFolder (scripts) — publicado 1.2

## Interfaz web (.www) — publicado 1.10