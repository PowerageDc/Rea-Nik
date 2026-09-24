# Red de la sala de ensayo

Diagnóstico e infraestructura de red para que el web control de REAPER
(control remoto general y prompter de MusicState) llegue estable a los
celulares de los músicos dentro de la sala.

Este doc es de infraestructura, no de código: no es una feature del repo,
pero `features/musicstate_instrumentista.md` depende de él (esa UI tiene
resiliencia de software ante cortes, pero no reemplaza una red que
funcione). Convenciones generales en `01_CONVENCIONES.md` y
`00_CONTEXTO_GENERAL.md`.

## 1. Síntoma y diagnóstico

La señal llega débil a la sala: la PC está conectada por cable, pero la
red cableada institucional ya es inestable por sí sola, y a eso se suman
las paredes/puerta gruesa de la sala para el tramo Wi-Fi hacia los
celulares. Además, la red institucional tiene un firewall a nivel de
la institución que no deja pasar sitios sin HTTPS — no debería afectar al
web control por ser tráfico local, pero si los celulares están en el
Wi-Fi institucional y la PC en el cable institucional, el tráfico sí pasa
por esos equipos.

**Antes de armar nada, diagnosticar dónde está el cuello de botella.**
Con la PC conectada por cable, abrir tres `cmd` y dejarlos corriendo
mientras se navega normal, hasta que se note un pegue:

```
ping -t 192.168.1.1
ping -t 8.8.8.8
ping -t google.com
```

(Cambiar la primera IP por la de la puerta de enlace real, visible con
`ipconfig`.) Cuando se note un pegue, mirar qué ventana muestra tiempos
altos o "tiempo de espera agotado":

- **Se pega el ping al router:** el problema es local (cable, puerto,
  placa de red de la PC, o el router mismo). Es el caso que más afecta al
  proyecto, y el que la red propia (§2) resuelve de raíz.
- **El router va bien pero `8.8.8.8` falla:** es el proveedor de
  internet. No afecta al web control, que es tráfico local.
- **Los dos IP van bien pero `google.com` tarda o falla:** es DNS. Se
  arregla cambiando el DNS de la PC (`1.1.1.1` / `8.8.8.8`); tampoco
  afecta al web control.

**Otro chequeo rápido:** con el web control abierto en el navegador de la
propia PC (`localhost`), si durante un pegue esa pestaña también se
congela, el cuello de botella es la PC o REAPER, no la red — en ese caso
conviene revisar la frecuencia de poll del cliente antes que la
infraestructura (ver `features/musicstate_instrumentista.md` §4.7 y §8).

**Antes de invertir en hardware, descartar lo barato:** probar otro cable
UTP y otro puerto del router; en Administrador de dispositivos → la placa
Ethernet → Opciones avanzadas/Administración de energía, desactivar
"Ethernet de bajo consumo / Energy Efficient Ethernet" y la opción de
apagar el dispositivo para ahorrar energía.

## 2. Solución de fondo: red propia para la sala

Un router propio, sin depender de la red institucional, con la PC
conectada por UTP a uno de sus puertos LAN y los celulares de los
músicos en su Wi-Fi.

**Qué resuelve:**

- Saca a la institución del camino (firewall, aislamiento entre
  clientes, saturación del switch/AP institucional).
- Dentro de la sala, el Wi-Fi nace ahí mismo: las paredes y la puerta
  dejan de interponerse entre el router y los celulares.
- Elimina el cable y el puerto institucionales como sospechosos.

**Qué no resuelve** (se cubre aparte):

- Problemas de la PC misma (placa de red, drivers, ahorro de energía,
  picos de latencia del sistema con REAPER abierto) — diagnosticados en
  §1.
- Saturación del servidor web de REAPER por un poll demasiado agresivo
  del cliente — resuelto del lado software, ver
  `features/musicstate_instrumentista.md` §4.7 y §8 (tope de
  `g_wwr_errcnt`, frecuencia de poll unificada).
- Un Wi-Fi interno malo si el router elegido es de mala calidad o queda
  mal ubicado.
- Internet en la PC: al conectarla solo a la red propia, pierde salida a
  internet salvo que se le deje una segunda vía (ver configuración).

## 3. Configuración

- PC por UTP a un puerto **LAN** del router nuevo. El puerto WAN/Internet
  queda **sin usar** — no conectarlo a la red institucional, para evitar
  conflictos de DHCP entre las dos redes.
- IP fija para la PC (o reserva DHCP en el router), para que la URL del
  web control sea siempre la misma.
- Windows tiene que clasificar esa red como **privada**: si la toma como
  pública, el firewall de Windows bloquea las conexiones entrantes al
  servidor web de REAPER.
- Preferir la banda de **5 GHz**, con canal manual elegido para evitar
  congestión (en una institución, 2,4 GHz suele estar saturada por otras
  redes). Aislamiento de clientes (client isolation) **apagado** — si
  está prendido, un dispositivo conectado al router no puede hablar con
  otro (bloquearía justamente el tráfico celular ↔ PC).
- En los celulares, si la UI no carga o carga a medias, desactivar datos
  móviles durante el ensayo: esa red no tiene salida a internet y algunos
  teléfonos desvían el tráfico a datos automáticamente al no detectarla.
- Si la PC necesita internet durante el ensayo (por ejemplo para MVSEP),
  dejarle una segunda vía (Wi-Fi de la PC a la red institucional) es
  preferible a conectar el router nuevo a la institucional por el puerto
  WAN — evita el riesgo de doble red con comportamiento impredecible.

**Router:** casi cualquiera sirve, siempre que se pueda resetear y
configurar a mano; preferible con 5 GHz. Cable: alcanza con Cat5e/Cat6,
hasta 100 m; si el recorrido pasa por debajo de la puerta, conviene uno
plano. Un travel router chico (tipo GL.iNet) es portátil, útil si el
mismo setup se lleva a otra sala o a un show.

## 4. Estado

Pendiente de armar: falta conseguir un router (evaluar si hay uno viejo
disponible) y un cable UTP con el largo adecuado al recorrido real hasta
la sala.
