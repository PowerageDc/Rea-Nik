# Roadmap — UI de Instrumentista (MusicState)

Doc transicional (checklist de avance) — no reemplaza a
`musicstate_instrumentista.md` (diseño ya cerrado, con su sección 9 de
estado de implementación) ni a `IMPL_MusicState.md` (fuente de verdad de
`music-state.js`). Se actualiza a medida que se cierra cada punto; se
consolida/descarta cuando el perfil quede terminado.

## Hecho y validado

Ver `musicstate_instrumentista.md` sección 9 para el detalle completo.
Resumen: `ms-dispatch.js`, `ms-tempo.js`, `ms-section.js` escritos y
probados contra REAPER real vía `nsaudio_musicstate_test.html` (se
mantiene como herramienta de diagnóstico). Fix de
`Nik_MusicState_PublishAll.lua` (ya no pisa datos reales con sample).

## Pendiente — refresco automático vía `publish_version`

Diseño cerrado en sesión (ver charla) — contador que solo sube,
puenteado igual que las otras 4 keys de MusicState, no una fecha.

- [ ] **Lua — `Nik_MusicState_Helper.lua`**
  - [ ] `H.publish_version`, cargado en
        `nikMusicStateLoadFromProjExtState` (default `0` si la key no
        existe todavía en `ProjExtState`)
  - [ ] Incrementar + `SetProjExtState(proj, Bridge.NAMESPACE,
        'publish_version', ...)` en `nikMusicStateSaveAndPublish`, mismo
        bloque que las otras 4 `SetProjExtState`
  - [ ] Sumar `'publish_version'` a `Bridge.KEYS` (o bridge manual
        análogo) — necesario para que `Nik_MusicState_PublishAll.lua`
        también lo re-puentee en cambio de tab, no solo al guardar
- [ ] **JS — `ms-dispatch.js`**
  - [ ] Sumar `GET/EXTSTATE/NikMusicState/publish_version` al poll
        consolidado de 1000ms (mismo poll que `active_project_name`/
        `reapitch_semitone`)
  - [ ] `var nikMsLastKnownPublishVersion = null;` — reseteada a `null`
        dentro de `nikMsResetProjectState()` (clave para que la
        comparación quede acotada al proyecto activo, ver charla de
        sesión)
  - [ ] Handler `EXTSTATE`/`publish_version`: primera vez visto en este
        proyecto → solo cachear, sin refresh extra (el cambio de
        proyecto ya disparó el suyo). Cambió estando en el mismo
        proyecto → sí disparar `nikMusicStateRequestAll()`
- [ ] **Testear**: guardar en el Helper con la UI de instrumentista ya
      abierta en el mismo proyecto, confirmar refresh en ≤1s sin
      recargar la página
- [ ] Una vez confirmado, actualizar `musicstate_instrumentista.md` §8
      (sacar el pendiente de "gesto de refresh manual" — queda resuelto
      automático, no por gesto de UI)

## Pendiente — `instrumentista.js`

Orden sugerido (cada uno validado en REAPER real antes de pasar al
siguiente, mismo modo de trabajo de siempre):

1. [ ] Bootstrapping real (`init()`, polls definitivos — reemplaza el
       inline de `nsaudio_musicstate_test.html`)
2. [ ] Selector de rol + persistencia (`localStorage` por dispositivo,
       fallback visible en rojo si el rol guardado no existe en
       `project_roles` del proyecto activo — decidido en sesión)
3. [ ] Layout vertical (jerarquía visual, doc §5)
4. [ ] Conmutación de layout por proporción de viewport (debounce
       150-200ms, doc §6)
5. [ ] Layout horizontal (4 slots, doc §6)
6. [ ] `nsaudio_musicstate_instrumentista.html` (shell final,
       reemplaza al HTML de test en el flujo real de uso)

## Pendientes menores heredados (ver `musicstate_instrumentista.md` §8)

- [x] Cadena `x2`/`x3...` — confirmado funcionando con proyecto real
- [ ] Semitono `"mixed"` del Stem Bus — sin testear
- [ ] Mitigación de carrera (token de generación si el bug de datos
      colgados reaparece pese al debounce de 400ms)
- [ ] Cantidad final de slots de acorde en layout vertical — contra
      dispositivo real
- [ ] Estructura final de banda terciaria en horizontal (una fila vs.
      dos) — contra dispositivo real
- [ ] String exacto reportado por REAPER para proyecto sin guardar
      (afecta el recorte de `.rpp` del nombre de canción)
