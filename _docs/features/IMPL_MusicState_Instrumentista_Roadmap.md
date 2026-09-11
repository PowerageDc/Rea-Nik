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

## Hecho — refresco automático vía `publish_version`

Implementado y confirmado en REAPER real (guardar en el Helper con la UI
de instrumentista ya abierta en el mismo proyecto → refresh automático,
sin recargar la página). Detalle de la implementación en
`musicstate_instrumentista.md` §9.

- [ ] **Pendiente de sync de doc** (no bloqueante, ver convención de
      consolidación en `00_CONTEXTO_GENERAL.md`): `IMPL_MusicState.md`
      secciones 10-11 listan las 4 keys de `Bridge.KEYS` sin
      `publish_version` — desactualizado desde este cambio. Sesión
      aparte para consolidar, no urge.

## Pendiente — `instrumentista.js`

Orden sugerido (cada uno validado en REAPER real antes de pasar al
siguiente, mismo modo de trabajo de siempre):

1. [x] Bootstrapping real (`init()`, polls definitivos — reemplaza el
       inline de `nsaudio_musicstate_test.html`)
2. [x] Selector de rol + persistencia (`localStorage` por dispositivo,
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
