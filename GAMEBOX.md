# GameBox

Streaming gaming auto-contenedorizado sobre Docker. Convierte cualquier PC con Linux y GPU AMD en una consola remota estilo Steam Deck.

## Visión General

GameBox ejecuta un único contenedor Docker con **Steam Nativo** en modo SteamOS (Game Mode) sobre un display virtual Wayland proporcionado por **labwc**, con **Gamescope** como compositor de juegos y **Sunshine** para streaming vía Moonlight.

### Objetivo

Que un usuario despliegue un stack Docker y en minutos esté jugando desde cualquier dispositivo (PC, tablet, Steam Deck, móvil, Apple TV) con aceleración gráfica por hardware y una experiencia de consola tipo SteamOS.

### Público objetivo

Usuarios con GPU AMD (incluyendo arquitectura Polaris / RX 580) que desean una consola en la red local sin necesidad de:
- Monitor físico conectado al servidor.
- PCIe Passthrough exclusivo (GPU compartida con el host).
- Máquina virtual (VM) con recursos fijos.

---

## Stack Tecnológico

| Componente | Elección | Motivación |
| :--- | :--- | :--- |
| **Motor** | Docker + Compose | Universal, estándar, despliegue simple. |
| **Base** | Fedora 42 | Mesa/Núcleo actualizado, Gamescope empaquetado. |
| **Modo Juego** | Steam Nativo (SteamOS Game Mode) | Experiencia Steam Deck vía `-steamos3` dentro de Gamescope. |
| **Compositor** | labwc + Gamescope | labwc como Wayland headless, Gamescope como cliente anidado. |
| **Streaming** | Sunshine v2026.x (compilado) | Latencia ultrabaja, Moonlight-compatible. |
| **Codificación HW** | VA-API (AMD) | H.264/HEVC por hardware para RX 580/Polaris. |
| **Captura** | Wayland (wlr-screencopy) | Captura directa del compositor labwc vía wlroots. |
| **Audio** | PipeWire + PulseAudio compat | Loopback de audio para streaming. |
| **Input virtual** | uinput (Linux nativo) | Teclado, ratón, gamepad (Xbox 360). |

---

## Arquitectura del Sistema

```
┌──────────────────────────────────────────────────────────┐
│                    Linux Host                            │
│  /dev/dri · /dev/uinput · network_mode: host            │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  gamebox (Contenedor Docker)                     │   │
│  │                                                   │   │
│  │  labwc (Wayland compositor headless)              │   │
│  │     │                                              │   │
│  │     ├── Gamescope (cliente Wayland, anidado)      │   │
│  │     │     └── Steam (SteamOS Game Mode)            │   │
│  │     │                                              │   │
│  │     └── Sunshine (wlr-screencopy, captura Wayland) │   │
│  │           ├── H.264 VA-API                        │   │
│  │           ├── RTSP :48010                         │   │
│  │           └── HTTPS :47989                        │   │
│  │                                                   │   │
│  │  PipeWire + WirePlumber (audio)                   │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  Cliente Moonlight ◄─── Red ──── Sunshine :47989        │
│  (PC, tablet, móvil, Steam Deck...)                     │
└──────────────────────────────────────────────────────────┘
```

### Flujo de arranque

```
entrypoint.sh
│
├── 1. Permisos /dev/dri, /dev/uinput
├── 2. D-Bus (system + session)
├── 3. labwc (Wayland headless)     [wait_for_wayland 10s]
├── 4. PipeWire + WirePlumber       [wait_for_process 5s]
├── 5. Gamescope + Steam (-steamos3) [background]
├── 6. Null sink PulseAudio (sunshine-stereo)
├── 7. Config Sunshine (apps.json, CSRF)
├── 8. Sunshine (capture = wlr)      [wait_for_process 5s]
└── 9. Tail logs (mantiene vivo el contenedor)
```

Cuando el usuario conecta desde Moonlight:
1. Sunshine ya captura la salida de labwc vía wlr-screencopy.
2. Gamescope + Steam están corriendo en el display virtual.
3. El usuario selecciona "GameBox (Steam Deck)" → Sunshine ejecuta `steam-wrapper.sh`.
4. `steam-wrapper.sh` mantiene el proceso vivo mientras Gamescope/Steam corran.
5. El stream comienza inmediatamente.

---

## Estructura del Repositorio

```
gamebox/
│
├── GAMEBOX.md                   # Este archivo — guía técnica de arquitectura
├── README.md                    # README público
├── Makefile                     # Atajos de orquestación (build, up, logs, etc.)
├── docker-compose.yml           # Despliegue Compose (parametrizado vía GAMEBOX_INSTANCE)
│
├── docker/                      # Construcción de la imagen
│   ├── Dockerfile               # Imagen basada en Fedora 42
│   ├── entrypoint.sh            # Script de arranque (labwc + Gamescope + Sunshine)
│   └── steam-wrapper.sh         # Wrapper persistente (evita auto_detach)
│
├── config/                      # Configuraciones
│   ├── sunshine.conf            # Streaming VA-API + Wayland capture
│   ├── labwc/                   # Configuración de labwc compositor
│   │   ├── rc.xml               # Sin decoraciones, fullscreen
│   │   └── environment          # WLR_BACKENDS=headless
│   └── udev-rules.conf          # Permisos uinput para el host
│
├── proxmox/                     # Scripts para Proxmox LXC
│   ├── setup-host.sh
│   └── create-lxc.sh            # Args CLI (--name, --ram, --cpus, etc.)
│
└── lxc/
    └── bootstrap.sh              # Usa docker-compose.yml raíz con GAMEBOX_INSTANCE
```

---

## Decisiones de Diseño Clave

### 1. ¿Por qué Fedora en vez de Ubuntu?

Fedora 42 tiene paquetes más actualizados de Mesa, Gamescope, y Wayland que Ubuntu 24.04 LTS. Gamescope está disponible directamente desde los repositorios oficiales de Fedora, eliminando la necesidad de compilarlo desde fuente o usar PPAs de terceros. Además, el soporte de Steam para VA-API en GPUs AMD Polaris (RX 580) es más estable con pilas gráficas recientes.

### 2. ¿Por qué labwc + Gamescope en vez de Xorg + Steam Big Picture?

labwc es un compositor Wayland mínimo basado en wlroots, ideal para entornos headless. Al ejecutarse con `WLR_BACKENDS=headless`, crea un display virtual sin necesidad de monitor físico. Gamescope corre como cliente Wayland anidado dentro de labwc, proporcionando:
- SteamOS Game Mode (interfaz tipo Steam Deck, no Big Picture)
- FSR (FidelityFX Super Resolution) para upscaling
- Performance overlay (mangoapp)
- XWayland interno para apps que lo requieran

Sunshine captura la salida de labwc vía wlr-screencopy, capturando lo que labwc muestra (Gamescope + Steam).

### 3. ¿Por qué no Gamescope directo sin labwc?

Gamescope con `--backend headless` renderiza a memoria de GPU pero no expone una salida que Sunshine pueda capturar (no hay socket Wayland ni display X11). Al ejecutar Gamescope como cliente Wayland de labwc, su salida se renderiza en una ventana que labwc gestiona, y Sunshine puede capturar el output completo del compositor.

### 4. ¿Por qué Steam Nativo (`i386`) y no Steam Flatpak?

Steam Flatpak requiere `bubblewrap` (bwrap) para aislar la aplicación. Ejecutar bwrap dentro de Docker (incluso privilegiado) provoca fallos de seguridad y restricciones de namespaces (seccomp). Steam nativo multiarquitectura (i386 + amd64) elimina la doble contenedorización y garantiza inicio rápido.

### 5. ¿Por qué pre-lanzar Steam antes que Sunshine?

El wrapper `steam.sh` de Steam sale inmediatamente después de lanzar el proceso real (el launcher 32-bit fork+exit). Si Sunshine lanza steam.sh como "app", detecta que el proceso hijo salió en <1s y activa "auto_detach". Para evitarlo:
- El entrypoint **pre-lanza** Gamescope + Steam en background.
- Sunshine captura la salida de labwc directamente cuando Moonlight conecta.
- La app "GameBox (Steam Deck)" usa `steam-wrapper.sh` para mantener un proceso vivo.

### 6. ¿Por qué parchear Sunshine para evitar SIGTRAP?

Cuando una sesión de streaming falla (timeout de PING de Moonlight) y los hilos no terminan en 10s, Sunshine llama `lifetime::debug_trap()` que ejecuta `std::raise(SIGTRAP)`. Sunshine **no tiene handler** para SIGTRAP, por lo que el proceso muere.

**Solución**: El Dockerfile aplica `sed` al source de Sunshine antes de compilar, reemplazando `debug_trap()` por un log. Sunshine se mantiene vivo incluso si una sesión se cuelga.

### 7. ¿Por qué los parches a `nvhttp.cpp`?

Se necesitan tres parches para permitir el pairing inicial con Moonlight:
1. **SSL verify flags**: Se elimina `verify_fail_if_no_peer_cert` para que clientes sin certificado puedan conectar durante el pairing.
2. **Return 1 en verify callback**: Se cambia `return 0` por `return 1` cuando el cliente no tiene certificado conocido — así el handshake SSL continúa y el cliente puede solicitar un PIN.
3. **Session management**: Se corrige un bug donde sessions con el mismo `uniqueID` colisionaban, y se previene un dangling pointer crash post-pairing.

### 8. ¿Por qué forzar VA-API en lugar de Vulkan Video?

GPUs AMD Polaris (RX 580) no soportan codificación Vulkan Video. Sunshine intenta inicializar codificadores Vulkan primero, lo que causa crashes en estas GPUs. Configurando `encoder = vaapi` y deshabilitando Vulkan durante el build, usamos la madurez de `mesa-va-drivers` para H.264/HEVC estable.

### 9. ¿Por qué `uinput` nativo en lugar de `inputtino`?

Sunshine v2026.x incluye soporte directo para inyección de input vía `uinput` (Xbox 360, PS, teclado, ratón). Concediendo permisos a `/dev/uinput` del host, evitamos compilar o ejecutar `inputtino`, logrando menor latencia y mayor compatibilidad.

### 10. ¿Por qué el `env` de `apps.json` debe coincidir con el entorno de Sunshine?

Sunshine lee `apps.json` (`src/process.cpp:627-632`) y aplica el contenido de `"env"` al entorno del **propio proceso** Sunshine vía `boost::this_process::environment()`. Esto ocurre en `proc::refresh()`, antes de `platf::init()`.

Si `apps.json` define `"WAYLAND_DISPLAY": "wayland-1"`, Sunshine sobrescribe su propia variable de entorno antes de conectar a Wayland, causando que `wl_display_connect()` busque un socket inexistente.

**Regla**: El `env` global de `apps.json` debe reflejar el entorno real del compositor. Cualquier variable definida allí afecta a Sunshine mismo, no solo a los procesos hijo de las apps.

Sunshine v2026.x incluye soporte directo para inyección de input vía `uinput` (Xbox 360, PS, teclado, ratón). Concediendo permisos a `/dev/uinput` del host, evitamos compilar o ejecutar `inputtino`, logrando menor latencia y mayor compatibilidad.

---

## Dependencias de Compilación de Sunshine

Sunshine v2026.x se compila desde fuente en el Dockerfile. Dependencias sobre Fedora 42:

| Dependencia | Paquete Fedora | Propósito |
| :--- | :--- | :--- |
| Compilación | `gcc gcc-c++ make cmake` | Toolchain |
| Boost | `boost-devel` | Biblioteca de soporte |
| PulseAudio | `pulseaudio-libs-devel` | Captura de audio |
| Opus | `opus-devel` | Códec de audio |
| libevdev | `libevdev-devel` | Input devices |
| FFmpeg | `ffmpeg-devel` (RPM Fusion) | Encoding |
| X11 | `libX11-devel libxcb-devel` | XWayland capture |
| GBM | `mesa-libgbm-devel` | Buffer management |
| cURL | `libcurl-devel` | HTTP requests |
| OpenSSL | `openssl-devel` | TLS/SSL |
| miniupnpc | `miniupnpc-devel` | UPnP |
| VA-API | `libva-devel` | HW encoding (decode-only en Fedora) |
| VA-API encode | `mesa-va-drivers-freeworld` (RPM Fusion) | H.264/HEVC encoding via VA-API |
| libdrm | `libdrm-devel` | DRM interface |
| JSON | `nlohmann-json-devel` | JSON parsing |
| libcap | `libcap-devel` | Capacidades POSIX |
| PipeWire | `pipewire-devel` | Captura Wayland |
| libnotify | `libnotify-devel` | Notificaciones |
| AppIndicator | `libappindicator-gtk3-devel` | System tray |
| Node.js | `nodejs` (dnf) | Build de UI |
| Graphviz | `graphviz` | `dot` para doxyconfig |

---

## Errores de Compilación Conocidos (Sunshine v2026.x)

> ⚠️ **IMPORTANTE**: Cualquier IA que trabaje en este repositorio debe leer esta sección antes de modificar el Dockerfile.

### E1 — Linker: `cannot find -lnuma`

```
ld: cannot find -lnuma: No such file or directory
```

- **Causa**: El enlazador necesita `libnuma` para NUMA (Non-Uniform Memory Access) support en Boost o FFmpeg.
- **Fix**: Instalar `numactl-devel`:
  ```bash
  dnf install -y numactl-devel
  ```
- **Referencia**: `docker/Dockerfile:53`

### E2 — Linker: `cannot find -lstdc++` (static)

```
ld: cannot find -lstdc++: No such file or directory
  /usr/bin/ld: maybe the static version of the standard C++ library is not installed
```

- **Causa**: Sunshine enlaza contra `libstdc++.a` (estática) en ciertas configuraciones de build.
- **Fix**: Instalar `libstdc++-static`:
  ```bash
  dnf install -y libstdc++-static
  ```
- **Nota**: `gcc-c++` instala `libstdc++-devel` (solo `.so`), la versión `.a` es un paquete separado.
- **Referencia**: `docker/Dockerfile:53`

### E3 — Doxygen docs target: `Error 1`

```
Error: Error 1
  (target 'docs' failed)
```

- **Síntoma**: Doxygen corre y genera la documentación exitosamente, pero el target `docs` de CMake reporta `Error 1`. [Se genera el HTML, pero doxygen retorna exit code 1](https://github.com/doxygen/doxygen/issues/10732) por warnings o por salida a stderr en versiones recientes.
- **Fix**: Eliminar la línea `add_subdirectory(third-party/doxyconfig docs)` de `cmake/targets/common.cmake` **antes** de cmake configure:
  ```bash
  sed -i '/add_subdirectory(third-party\/doxyconfig docs)/d' cmake/targets/common.cmake
  ```
- **Alternativa**: `rm -rf build/docs` después de cmake configure, pero el sed es más limpio.
- **Origen**: Este submodule es traído por `third-party/tray` y `third-party/libdisplaydevice`. No es necesario para el build de Sunshine.
- **Referencia**: `docker/Dockerfile:80`

### E4 — CMake: `Could NOT find Doxygen`

```
Could NOT find Doxygen (missing: DOXYGEN_EXECUTABLE)
```

- **Causa**: El submodule `third-party/doxyconfig` requiere Doxygen ≥ 1.10 pero no está instalado.
- **Fix**: Instalar `doxygen` y `graphviz` (para `dot`):
  ```bash
  dnf install -y graphviz doxygen
  ```
- **Referencia**: `docker/Dockerfile:54`

### E5 — CMake: `Manually-specified variables were not used by the project`

```
Manually-specified variables were not used by the project:
  SUNSHINE_BUILD_HOME
  SUNSHINE_BUILD_DOCS
  SUNSHINE_BUILD_TESTS
```

- **Causa**: Esas opciones CMake no existen en el CMakeLists.txt de Sunshine v2026.x (posiblemente renombradas o eliminadas).
- **Fix**: Quitarlas de la línea de cmake — son ignoradas silenciosamente y no afectan el build. El mensaje es solo un warning.

### E6 — `libappindicator-gtk3-devel` no es `ayatana-appindicator`

- **Causa**: El build de Sunshine busca `appindicator3-0.1` (`pkg-config`), no `ayatana-appindicator`.
- **Fix**: Usar `libappindicator-gtk3-devel` (Fedora), no `libayatana-appindicator-devel`.
- **Verificación**: CMake output confirma `Found appindicator3-0.1`.

---

## Errores de Runtime Conocidos

> Estos son problemas actuales que requieren solución. Se documentan para que futuras IAs no pierdan tiempo diagnosticando lo mismo.

### R1 — labwc: Vulkan renderer falla en GPU Polaris (RX 580)

```
00:00:00.126 [ERROR] [render/vulkan/vulkan.c:480]
  vulkan: required device extension VK_EXT_image_drm_format_modifier not found
00:00:00.126 [ERROR] [render/vulkan/renderer.c:2522] Failed to create vulkan device
00:00:00.127 [ERROR] [render/wlr_renderer.c:199] Failed to create a Vulkan renderer
```

- **Causa**: El driver AMD Vulkan (RADV) en el contenedor no expone `VK_EXT_image_drm_format_modifier` para Polaris. Posiblemente falta el driver de kernel correcto o la versión de Mesa no es compatible con el kernel host.
- **Fix aplicado**: Cambiar `WLR_RENDERER=vulkan` → `WLR_RENDERER=gles2` en:
  - `config/labwc/environment` (line 2)
  - `docker/Dockerfile` (line 10, `ENV WLR_RENDERER=`)
- **Estado**: Comprobado — labwc arranca con gles2 en Polaris sin errores de render.

### R2 — D-Bus session: XDG_RUNTIME_DIR ownership mismatch

```
dbus[44]: Unable to set up transient service directory:
  XDG_RUNTIME_DIR "/run/user/1000" is owned by uid 0, not our uid 1000
dbus-daemon[44]: Failed to start message bus:
  Failed to bind socket "/run/user/1000/bus": Permission denied
```

- **Causa**: En `docker/entrypoint.sh:32`, `chown` se ejecuta ANTES de `mkdir` (line 33). Como `/run/user/1000` no existe aún, `chown` falla (error oculto por `|| true`). Luego `mkdir` crea el directorio como root, y nunca se cambia el owner a `steam`.
- **Fix aplicado**: Reordenar a:
  1. `mkdir -p "${XDG_RUNTIME_DIR}"`
  2. `chmod 700 "${XDG_RUNTIME_DIR}"`
  3. `chown -R steam:steam /home/steam "${XDG_RUNTIME_DIR}"`
- **Estado**: Comprobado — D-Bus session arranca sin error de permisos, socket `bus` aparece en `/run/user/1000/`.

### R3 — PipeWire: Permission denied on /run/user/1000

```
[E] mod.rt | Failed to connect to session bus:
  Failed to connect to socket /run/user/1000/bus: Permission denied
[E] mod.protocol-native | unable to open lockfile '/run/user/1000/pipewire-0.lock':
  Permission denied
```

- **Causa**: Misma causa raíz que R2 — `XDG_RUNTIME_DIR` con owner incorrecto.
- **Fix**: El mismo que R2 (reordenar chown después de mkdir).
- **Estado**: Comprobado — PipeWire arranca y crea sockets `pipewire-0` sin errores de permisos.

### R4 — Sunshine: `Unable to initialize capture method` (Resuelto)

```
[2026-05-26 14:13:42.825] Error: Unable to initialize capture method
[2026-05-26 14:13:42.825] Error: Platform failed to initialize
...
[2026-05-26 14:13:44.026] Fatal: Unable to find display or encoder during startup.
```

- **Causa Raíz Original**: labwc no arranca (R1) → no hay socket Wayland → Sunshine no puede capturar.
- **Segunda Causa (no obvia)**: Incluso con labwc funcionando, Sunshine intentaba conectar a `/run/user/1000/wayland-1` (ver R7) en vez de `wayland-0`. Esto bloqueaba `wl_display_connect()`.
- **Fix**: Resolver R1, luego R7 (apps.json env corrompe WAYLAND_DISPLAY).
- **Estado**: Resuelto. Sunshine conecta correctamente a `wayland-0` y captura vía wlr-screencopy.

### R5 — Sunshine: VA-API encoder failure (Resuelto)

```
Info: Trying encoder [vaapi]
Info: Encoder [vaapi] failed
```

- **Causa Raíz**: Fedora 42 empaqueta `mesa-va-drivers` solo con decodificación (VLD). La codificación (EncSlice) requiere `mesa-va-drivers-freeworld` desde RPM Fusion.
- **Causa secundaria**: El error `amdgpu: amdgpu_cs_ctx_create2 failed. (-13)` en los logs es un **falso positivo** — es solo amdgpu rechazando crear un contexto de alta prioridad; cae gracefully a prioridad normal. No afecta la funcionalidad.
- **Fix**: Agregar `mesa-va-drivers-freeworld` a la lista de `dnf install` en `docker/Dockerfile:25`.
- **Verificación**: `vainfo` dentro del contenedor confirma `VAEntrypointEncSlice` para H.264 y HEVC.
- **Estado**: Resuelto. Sunshine encuentra y usa `h264_vaapi [vaapi]` correctamente.

### R6 — Gamescope: `Failed to connect to wayland socket: wayland-0` (Resuelto)

```
Failed to connect to wayland socket: wayland-0.
```

- **Causa**: En `entrypoint.sh:71`, Gamescope busca el socket Wayland pero labwc no ha arrancado (R1). El `wait_for_wayland` falla antes de que Gamescope intente conectar.
- **Fix**: El mismo que R1 (WLR_RENDERER=gles2). Además se agregó `--backend wayland` al comando de gamescope.
- **Estado**: Resuelto. Gamescope crea socket `gamescope-0` en `/run/user/1000/`.

### R7 — `apps.json:env` modifica el entorno del proceso Sunshine

**Síntoma**: A pesar de exportar `WAYLAND_DISPLAY=wayland-0` en `entrypoint.sh`, Sunshine reporta `[wayland] Couldn't connect to Wayland display: wayland-1`.

```
strace: connect(7, {sun_path="/run/user/1000/wayland-1"}, 27) = -1 ENOENT
ltrace: sunshine->getenv("WAYLAND_DISPLAY") = "wayland-1"
```

- **Causa Raíz**: Sunshine lee `apps.json` en `proc::refresh()` (`src/process.cpp:627-632`) y aplica el contenido de `"env": { ... }` al entorno del **propio proceso** Sunshine vía `boost::this_process::environment()`, **antes** de `platf::init()`. El `apps.json` generado por `entrypoint.sh:87` tenía `"WAYLAND_DISPLAY": "wayland-1"`, lo que sobrescribía la variable de entorno antes de que Sunshine consultara `getenv("WAYLAND_DISPLAY")` para conectar a Wayland.
- **Fix**: Cambiar `"WAYLAND_DISPLAY": "wayland-1"` → `"wayland-0"` en el JSON de `entrypoint.sh:87`.
- **Diagnóstico con LD_PRELOAD**: Se interceptó `getenv("WAYLAND_DISPLAY")` para confirmar que retornaba `"wayland-1"` dentro del proceso; forzándolo a `"wayland-0"` resolvía el problema inmediatamente.
- **Lección**: El campo `env` en `apps.json` no es solo para procesos hijo — Sunshine lo aplica a sí mismo. Cualquier variable definida allí afecta al proceso principal de Sunshine.
- **Estado**: Resuelto.

### R8 — `mesa-va-drivers-freeworld` faltante en Fedora

**Síntoma**: `vainfo` solo muestra `VAEntrypointVLD` (decodificación), ningún `VAEntrypointEncSlice`. Sunshine reporta `[h264_vaapi] No usable encoding profile found`.

```
VAProfileH264High: VAEntrypointVLD   ← solo decode
VAProfileH264High: VAEntrypointEncSlice ← ausente
```

- **Causa**: Fedora 42 (y Fedora en general) empaqueta `mesa-va-drivers` con soporte exclusivamente de decodificación por política de patentes de códecs. El soporte de codificación (H.264, HEVC, AV1) está en el paquete `mesa-va-drivers-freeworld` del repositorio RPM Fusion nonfree.
- **Fix**: Agregar `mesa-va-drivers-freeworld` a la lista de paquetes en `docker/Dockerfile:25`. RPM Fusion ya está configurado en el Dockerfile (líneas 19-20), solo faltaba instalar el paquete.
- **Verificación**: `vainfo` post-instalación muestra `VAEntrypointEncSlice` para H.264 y HEVC.
- **Falso positivo asociado**: El mensaje `amdgpu: amdgpu_cs_ctx_create2 failed. (-13)` en stderr es un **falso positivo** — es el driver AMDGPU rechazando crear un contexto compute de alta prioridad, y cae gracefulmente a prioridad normal. No afecta ni VA-API ni Sunshine.
- **Estado**: Resuelto.

### R9 — PIN de emparejamiento Moonlight no da feedback, Sunshine crashea al recargar Web UI

**Síntoma**: Tras ingresar el PIN en la Web UI (puerto 47990), la página no muestra retroalimentación. Al recargar la Web UI, Sunshine crashea.

- **Causa raíz — Referencia colgante en `nvhttp.cpp::pin()`**:
  - `pin()` (`src/nvhttp.cpp:635`) obtiene una referencia `sess` al primer elemento de `map_id_sess`.
  - Llama a `getservercert()` que, si encuentra `last_phase != NONE` (en reintentos), o si el salt es muy corto, llama a `fail_pair()` → `remove_session()`.
  - `remove_session()` borra el elemento del `unordered_map`, lo que invalida la referencia `sess`.
  - Las líneas posteriores (`sess.client.name = name`, `sess.async_insert_pin.response`) son **undefined behavior** — típicamente crashean o corrompen memoria.
- **Causa secundaria — `last_phase` no se resetea en reintentos**: Si el PIN se ingresó una vez (y `getservercert` seteó `last_phase = GETSERVERCERT`), un segundo intento de PIN sobre la misma sesión falla con `"Out of order call to getservercert"`, llamando a `fail_pair`.
- **Fix aplicado**:
  1. `async_response` se mueve (`std::move`) fuera de la sesión **antes** de llamar a `getservercert`, previniendo la referencia colgante.
  2. `last_phase` se resetea a `PAIR_PHASE::NONE` antes de `getservercert`, permitiendo reintentos.
  3. Después de `getservercert`, se re-busca la sesión por `unique_id` (puede haber sido eliminada por `fail_pair`). Si existe, se asigna `client.name`.
  4. Se eliminó el parche `std::prev(map_id_sess.end())` (era frágil con begin() == end() y no solucionaba el problema de fondo).
- **Verificación**: Ingresar PIN en Web UI, confirmar `{"status": true}`. Recargar Web UI, re-ingresar PIN — no debe crashear.
- **Estado**: Resuelto (pendiente rebuild y test).

---

## Regla de Diagnóstico

Cuando el contenedor arranque y algo falle, verificar en este orden:

```
1. D-Bus session → /tmp/dbus-session.log
2. labwc / Wayland → /tmp/labwc.log + /run/user/1000/wayland-*
3. PipeWire → /tmp/pipewire.log
4. Gamescope → /tmp/steam.log (líneas iniciales)
5. Sunshine → /tmp/sunshine.log
```

Cada error downstream es consecuencia del anterior. Siempre resolver en orden ascendente.

---

## Solución de Problemas

### Sunshine no arranca
```bash
docker compose logs gamebox | grep Sunshine
```
Verificar que el puerto 47989 esté LISTEN:
```bash
docker exec gamebox bash -c "ss -tlnp | grep 47989"
```

### SteamOS Game Mode no se ve
```bash
docker exec gamebox bash -c "pgrep -ax gamescope; pgrep -ax steam; pgrep -ax steamwebhelper"
docker exec gamebox bash -c "cat /tmp/steam.log | tail -50"
```

### labwc / Wayland no arranca
```bash
docker exec gamebox bash -c "cat /tmp/labwc.log | tail -20"
docker exec gamebox bash -c "ls -la /run/user/1000/wayland-*"
```

### Sunshine muere tras sesión
```bash
docker exec gamebox bash -c "ps aux | grep sunshine | grep -v grep"
```
Si Sunshine no está corriendo, revisar `/tmp/sunshine.log`.

### No hay audio en el stream
```bash
docker exec gamebox bash -c "pactl list sinks short | grep sunshine"
```
Si no aparece el sink, recrearlo manualmente:
```bash
docker exec gamebox bash -c "su - steam -c 'pactl load-module module-null-sink sink_name=sunshine-stereo format=s16le channels=2 rate=48000'"
```

---

## Regla Fundamental para Cualquier IA

**Este documento debe mantenerse siempre actualizado.**

Cada vez que una IA o desarrollador trabaje en este repositorio y realice modificaciones:
1. Actualiza la estructura del repositorio si hay archivos nuevos o eliminados.
2. Actualiza la tabla del Stack Tecnológico y Decisiones de Diseño si cambian dependencias o enfoques.
3. Actualiza el Roadmap marcando fases completadas.

---

## Roadmap

### Fase 1 — Infraestructura Base (Completada)
- [x] Dockerfile con Fedora 42, Steam nativo, Gamescope, labwc
- [x] Sunshine compilado con soporte Wayland
- [x] PipeWire para captura de audio

### Fase 2 — Streaming y Captura (Completada)
- [x] Sunshine configurado con VA-API + Wayland capture (wlr-screencopy)
- [x] Null sink PulseAudio para captura de audio
- [x] Parches a Sunshine: pairing + SIGTRAP + session management

### Fase 3 — Modo SteamOS (Completada)
- [x] Gamescope como compositor anidado con Steam en modo SteamOS (`-steamos3`)
- [x] labwc como Wayland compositor headless
- [x] Wrapper persistente (evita auto_detach de Sunshine)
- [x] Pre-lanzamiento de Gamescope + Steam en entrypoint

### Fase 4 — Correcciones de Runtime (Completada)
- [x] Fix: apps.json env contaminaba WAYLAND_DISPLAY del proceso Sunshine (R7)
- [x] Fix: Falta mesa-va-drivers-freeworld para VA-API encoding (R8)
- [x] Fix: Referencia colgante en pin() + last_phase no reseteado (R9)
- [x] Fix: WLR_RENDERER=vulkan → gles2 para Polaris (R1)
- [x] Fix: chown ordering en entrypoint.sh (R2/R3)
- [x] Fix: gamescope --backend wayland + socket chown (R6)
- [x] Fix: WAYLAND_DISPLAY default wayland-1 → wayland-0 en docker-compose.yml
- [x] Fix: std::prev(map_id_sess.end()) revertido a std::begin

### Fase 5 — Próximos Pasos (Pendiente)
- [ ] Probar en Proxmox LXC con GPU AMD real
- [ ] **Rebuild + test pairing Moonlight (PIN vía web UI)**
- [ ] Probar streaming real (video + audio + input)
- [ ] Agregar modo escritorio (KDE Plasma opcional)
- [ ] Decky Loader integrado
- [ ] Agregar perfiles de Moonlight y guías de conexión remota
- [ ] Documentar scripts de instalación y troubleshooting
