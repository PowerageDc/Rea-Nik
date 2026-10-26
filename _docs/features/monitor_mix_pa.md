# Feature — Monitor Mix: capa PA

Corte del PA por track sin tocar la mezcla de monitoreo del baterista:
modelo de estado, órdenes, contrato de datos e interfaz en el remoto
principal. Lo lee quien toca el script de ruteo PA, el formato de `pa_state`
o el modo PA del remoto.

Fuera de este doc: ruteo, bus de monitoreo y qué mutea qué
(`monitor_mix.md` §3.3), disparo de `Publish` y ciclo de proyecto
(`monitor_mix.md` §5), protocolo del web control y tope de `EXTSTATE`
(`musicstate_data_model.md` §3, §6), deploy (`05_REAPACK_DEPLOY.md`),
convenciones (`01_CONVENCIONES.md`).

## 1. Objetivo

En ensayo suena música por el PA (par 1/2), muchas veces como pre-roll para
que los músicos no entren en frío. Cuando tienen que tocar, hay que sacar de
ese PA los tracks correspondientes, todos de golpe o algunos, sin alterar la
mezcla del baterista (par 3/4).

El mute y el solo del remoto no sirven para esto: actúan sobre el track y
arrastran sus sends (`monitor_mix.md` §3.3). La capa PA quita en cambio el
send al master/padre del track, que no toca los sends al monitoreo.

- Corte y activación por hoja, por folder (grupo) o de todo el PA.
- Solo de PA: escuchar por el PA solo lo elegido.
- En el remoto, M/S de PA se ven distintos de los reales (§4).

## 2. Modelo

**Hoja:** todo track que no es folder ni bus de monitoreo (por nombre en
`buses` del config, o por tener receives y hardware output a la vez). El
filtro de Monitor Mix no interviene: un track que el filtro rechaza, como el
count-in, también se puede cortar. Los folders son grupos: operar sobre uno
opera sobre todas sus hojas, a cualquier profundidad; el track del folder en
sí no se toca.

**Cortar** una hoja es poner `B_MAINSEND = 0` (para un hijo de folder, el send
al padre). Por proyecto hay dos conjuntos de GUID, `cut` y `solo`, y el send
de cada hoja queda:

> activo ⇔ no está en `cut` y (`solo` está vacío o la hoja está en `solo`)

Es la misma lógica que M y S de REAPER: soleada y cortada, queda silenciosa.
Salir del solo es vaciar el conjunto; no hay estado previo que restaurar. El
solo es acumulable.

- **Sin solo activo manda el `B_MAINSEND` real:** las hojas con 0 se leen como
  cortadas. Así se adoptan los cambios hechos a mano en REAPER.
- **Con solo activo mandan los conjuntos**, persistidos en `ProjExtState`
  (namespace `NikMonitorMix`, keys `pa_cut` y `pa_solo`, GUIDs separados por
  coma), y el `B_MAINSEND` se deriva. Solo se escribe cuando el valor cambia,
  y sin solo no se guarda nada.
- **Undo:** una entrada `Monitor Mix: PA` por orden que cambia algún send;
  una orden sin cambios no deja entrada.

## 3. Contrato

### 3.1. Órdenes (`pa_cmd`)

El web control no pasa argumentos a un script: el remoto escribe el ExtState
`NikMonitorMix/pa_cmd` (sin persistencia) y dispara
`Nik_MonitorMix_PaRoute.lua`, que lo lee y lo borra. Formato `<op>:<destino>`.
El separador es `:` porque `;` separa pedidos del web control y `|` se
codifica en la URL.

| Orden | Efecto |
|---|---|
| `cut:D` | Corta el destino |
| `on:D` | Lo reactiva |
| `toggle:D` | Si todas sus hojas están cortadas lo reactiva; si no, lo corta |
| `solo:D` | Si todas sus hojas están en solo las saca; si no, las agrega |
| `clear` | Vacía `cut` y `solo`: todo vuelve al PA |

`D` es el número de track del web control (base 1) o `all`. Una hoja es esa
hoja; un folder son sus hojas. Un destino que no es hoja ni folder (el bus de
monitoreo) se ignora. Sin orden pendiente el script solo republica el estado.

El pedido completo que manda el remoto trae la lectura del estado resultante,
que ya refleja la orden porque el script corre antes del `GET`:

```
SET/EXTSTATE/NikMonitorMix/pa_cmd/toggle:3;<commandId>;GET/EXTSTATE/NikMonitorMix/pa_state
```

Con `debug = true` en el config cada orden escribe en la consola una línea
`[MonitorMix.PA hora] op:destino -> N sends cambiados`, y las ignoradas lo
avisan.

### 3.2. Estado (`pa_state`)

ExtState global `NikMonitorMix/pa_state`, JSON compacto en una línea. Lo
escribe el script de ruteo y también `Nik_MonitorMix_Publish.lua`, para que
cada cambio de proyecto reemplace el estado del proyecto anterior.

```json
{"n":10,"cut":[3],"solo":[],"folders":[{"track":2,"n":8,"cut":1,"solo":0}]}
```

- `n`: total de hojas.
- `cut` y `solo`: números de track (base 1) de las hojas en cada conjunto.
- `folders`: un registro por folder con al menos una hoja. `n`, `cut` y `solo`
  cuentan sus hojas: todo cortado si `cut == n`, parcial si `0 < cut < n`.
  Lo mismo para `solo`.

## 4. Interfaz del remoto principal

**Modo PA:** botón en la fila MASTER, a la derecha del centro y pegado al M.
Con el modo activo:

- M de cada fila manda `toggle:N` y S manda `solo:N`; en un folder actúan
  sobre el grupo.
- M del master manda `toggle:all`.
- Los botones muestran el estado PA, no el de REAPER, que sigue intacto.
  Con el modo apagado vuelven los M/S reales.

El modo no se guarda: al recargar la página arranca apagado.

**Chip:**

| Estado | Aspecto |
|---|---|
| Apagado, sin cortes ni solos | Gris, `PA` |
| Apagado, con cortes o solos | Borde y texto celestes, `PA 3` (hojas cortadas), `PA S` (solo activo) o `PA 3 S` |
| Encendido | Relleno azul, texto blanco |

El estado con cortes avisa que el proyecto tiene tracks fuera del PA, guardados
en el `.rpp` (§5).

**Colores.** Los M/S reales tienen 3,8:1 (mute) y 1,65:1 (solo) con el glifo
blanco. Los de PA son más oscuros y se distinguen del rojo y del amarillo:

| Elemento | Color | Contraste |
|---|---|---|
| M de PA activo | fondo `#0277BD`, glifo blanco | 4,8:1 |
| S de PA activo | fondo `#00796B`, glifo blanco | 5,3:1 |
| M parcial (folder) | fondo `#B3E5FC`, glifo y borde `#01579B` | 5,5:1 |
| S parcial (folder) | fondo `#B2DFDB`, glifo y borde `#004D40` | 6,8:1 |
| Chip apagado | texto `#A8A8A8` sobre `#262626` | 6,4:1 |
| Chip con cortes | texto `#81D4FA` sobre `#262626` | 9,2:1 |
| Chip encendido | texto blanco sobre `#0277BD` | 4,8:1 |

El parcial no usa opacidad reducida porque degradaría el contraste del glifo.

**Mecánica.** El código vive en `core/pa-mode.js` y en tres ganchos de
`core/wwr-dispatch.js` (`nikPaReq`, `nikPaApplyRow`, `nikPaApplyMaster`); el
estado entra por `nikPaApplyState`.

- `pa_state` se pide en el slow poll (`nikBuildSlowPoll`, `config.js`) y
  también llega en la respuesta de cada orden.
- Los botones M/S se redibujan en cada línea `TRACK`, después del bloque de
  flags, que los pinta desde REAPER. Cada fila guarda la firma de lo último
  pintado y su elemento, para repintar si cambia la fila o se recrea.
- Los colores no tocan el SVG: se agregan las clases `nikPaAll` y `nikPaPart`
  al grupo `.mute` o `.solo` (al grupo `#mute` en el master) y `styles.css`
  pisa el `fill` de los elementos por su color original.
- Con rec armado (flag 64) el botón mute está oculto, lo ocupa el de
  monitoreo: en ese caso solo se pinta el solo.
- Alternar el modo limpia `trackFlagsAr` para que el próximo ciclo repinte
  los botones desde los flags reales.

## 5. Riesgos y límites

- **El corte queda guardado en el `.rpp` y el track cortado tampoco sale en
  el render.** El chip lo avisa con el modo apagado, y `clear` lo restaura.
- **Solo el camino directo al master/padre:** los sends de una hoja a otros
  tracks (aux de reverb o delay) siguen sonando por el PA.
- **Hojas con el send al master apagado por otro motivo** aparecen como
  cortadas (adopción, §2).
- **Track agregado con solo activo:** suena por el PA hasta la próxima orden
  y `pa_state` lo muestra como no soleado.
- **Undo:** cada orden con cambios agrega una entrada, a propósito: sin ella
  un Undo de otra acción podría revertir el ruteo. El historial crece con el
  uso intensivo.
- **Retardo entre clientes:** un cambio hecho desde otro cliente llega hasta
  1 s después (slow poll).

## 6. Pendientes

- Cortar también los sends de la hoja a tracks que salen por el master (aux de
  reverb y delay). No es foco en ensayo.
- Render Workflow: llamar `clear` o verificar el `B_MAINSEND` de las hojas
  antes de renderizar.
- Evaluar que los snapshots `SN_*` usen el corte de PA en lugar del mute
  (riesgo en `monitor_mix.md` §7).
- Aplicar el modelo al track agregado con solo activo (§5).
