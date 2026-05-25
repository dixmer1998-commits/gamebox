# GameBox

Streaming gaming auto-contenedorizado sobre Proxmox + Docker.

## Visión General

GameBox es un proyecto que permite convertir un servidor Proxmox con GPU AMD
en una consola de juegos remota al estilo SteamOS. Se compone de un stack
Docker que ejecuta Gamescope + Steam (Modo Juego) y KDE Plasma (Modo Escritorio),
transmitiendo la imagen a cualquier dispositivo via Sunshine + Moonlight.

### Objetivo

Que un usuario ejecute **un script** en su Proxmox y en minutos esté jugando
desde cualquier dispositivo (PC, tablet, Steam Deck, móvil) con aceleración
gráfica por hardware y una experiencia tipo SteamOS.

### Público objetivo

Usuarios con nivel básico/medio de Linux y Docker que tienen un servidor
Proxmox con GPU AMD y quieren usarlo para jugar sin necesidad de:
- Tener un monitor físico conectado
- Configurar manualmente GPU passthrough
- Lidiar con problemas de input (teclado/ratón)
- Mantener una VM pesada con recursos fijos

## Stack Tecnológico

| Componente | Elección | Motivación |
|------------|----------|------------|
| Hipervisor | Proxmox VE | Maduro, estable, comunidad grande |
| Contenedor sistema | LXC privilegiado | Comparte kernel con host, recursos dinámicos, GPU compartida via bind mount |
| Motor contenedores | Docker | Universal, fácil de usar, ecosistema enorme |
| Base imágenes | Debian 12 (Bookworm) slim | Estable, ligero, predecible, poco mantenimiento |
| Modo Juego | Gamescope + Steam (Flatpak) | Experiencia SteamOS real, no solo Big Picture |
| Modo Escritorio | KDE Plasma | Completo, familiar, similar a SteamOS Desktop |
| Streaming | Sunshine | Open source, maduro, web UI incluida |
| Captura de video | PipeWire desde Gamescope | Baja latencia, integración nativa |
| Codificación HW | VAAPI (AMD) | Hardware encoding sin NVIDIA |
| Input virtual | inputtino (via Sunshine) | Soporte de teclado, ratón, gamepad |
| Web UI | Sunshine web UI + panel Go minimalista | Gestión del servidor, pares Moonlight |

## Arquitectura

```
┌───────────────────────────────────────────────────────────────┐
│                    Proxmox Host                               │
│  Drivers AMD · /dev/dri · /dev/uinput                        │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐     │
│  │  LXC Privilegiado "gamebox-{nombre}" (Debian 12)   │     │
│  │  Montajes: /dev/dri, /dev/uinput, /dev/input/*      │     │
│  │  Cgroups: uinput, evdev, render                     │     │
│  │  IP fija: 192.168.X.Y                               │     │
│  │                                                      │     │
│  │  ┌───────────────────────────────────────────────┐  │     │
│  │  │           Docker                               │  │     │
│  │  │                                                │  │     │
│  │  │  ┌─────────────────────────────────────────┐  │  │     │
│  │  │  │  gamebox (contenedor único)              │  │  │     │
│  │  │  │                                          │  │  │     │
│  │  │  │  ┌──────────────┐  ┌──────────────┐    │  │  │     │
│  │  │  │  │  Game Mode   │  │ Desktop Mode │    │  │  │     │
│  │  │  │  │              │  │              │    │  │  │     │
│  │  │  │  │ Gamescope    │  │ KDE Plasma   │    │  │  │     │
│  │  │  │  │  └→ Steam    │  │              │    │  │  │     │
│  │  │  │  │  (Flatpak)   │  │              │    │  │  │     │
│  │  │  │  └──────┬───────┘  └──────┬───────┘    │  │  │     │
│  │  │  │         │ PipeWire        │ PipeWire   │  │  │     │
│  │  │  │         ▼                 ▼            │  │  │     │
│  │  │  │  ┌──────────────────────────────────┐  │  │  │     │
│  │  │  │  │         Sunshine                 │  │  │  │     │
│  │  │  │  │  App "Juego"  → Gamescope       │  │  │  │     │
│  │  │  │  │  App "Escritorio" → KDE         │  │  │  │     │
│  │  │  │  │  Web UI : http://ip:47990       │  │  │  │     │
│  │  │  │  └──────────────────────────────────┘  │  │  │     │
│  │  │  └─────────────────────────────────────────┘  │  │     │
│  │  └───────────────────────────────────────────────┘  │     │
│  └─────────────────────────────────────────────────────┘     │
│                                                              │
│  Cliente Moonlight ◄─── Red ──── Sunshine :47989             │
│  (PC, tablet, móvil, Steam Deck...)                         │
└───────────────────────────────────────────────────────────────┘
```

## Estructura del Repositorio

```
gamebox/
│
├── GAMEBOX.md                   # Este archivo — guía completa del proyecto
├── Makefile                     # Comandos de orquestación
├── README.md                    # README público (instrucciones rápidas)
│
├── proxmox/                     # Scripts para el host Proxmox
│   ├── setup-host.sh            # Configura drivers AMD, IOMMU, módulos
│   └── create-lxc.sh            # Crea LXC privilegiado con GPU bind + uinput
│                                # Pregunta nombre de instancia (ej: "steamos", "arcade")
│                                # Usa el nombre para: hostname LXC, nombre contenedor, IP
│
├── lxc/                         # Archivos para dentro del LXC
│   ├── bootstrap.sh             # Instala Docker + dependencias + construye imagen
│   └── docker-compose.yml       # Stack (un solo contenedor gamebox)
│
├── docker/                      # Dockerfile del contenedor único
│   ├── Dockerfile               # Debian 12 + Gamescope + Steam (Flatpak) + KDE + Sunshine
│   ├── entrypoint.sh            # Arranque de gamescope-session + sunshine + pipewire
│   └── supervisord.conf         # Supervisor de procesos (Gamescope, Sunshine, PipeWire)
│
├── config/                      # Configuraciones predefinidas
│   ├── sunshine.conf            # Sunshine optimizado para AMD + PipeWire
│   ├── udev-rules.conf          # Reglas udev para dispositivos virtuales
│   ├── inputtino.conf           # Configuración de input virtual
│   └── gamescope.conf           # Parámetros de Gamescope (resolución, FPS, upscaling)
│
└── docs/                        # Documentación adicional
    ├── multi-instancia.md       # Cómo crear una segunda instancia de juego
    └── troubleshooting.md       # Problemas comunes y soluciones
```

## Requisitos de Hardware

| Componente | Requisito Mínimo | Recomendado |
|------------|-----------------|-------------|
| CPU | Cualquiera con IOMMU (Intel VT-d / AMD-Vi) | 4+ cores |
| RAM | 8 GB | 16 GB+ |
| GPU | AMD RX 400 series o superior (GCN 4+) | AMD RX 5000+ o RX 6000+ |
| Almacenamiento | 64 GB SSD | 256 GB+ SSD (para juegos) |
| Red | Gigabit Ethernet | Gigabit Ethernet (WiFi 5GHz aceptable) |
| Proxmox | VE 8.x | VE 8.x+ |

### Notas sobre GPU AMD

- Se requiere GPU AMD con soporte VAAPI para hardware encoding.
- La GPU **no se pasa por VFIO** — se comparte via bind mount `/dev/dri`.
- Esto permite que el host y otros contenedores usen la GPU simultáneamente.
- Modelos recomendados: RX 6600, RX 6700 XT, RX 6800, RX 7600, RX 7700 XT.

## Flujo de Instalación

### Paso 1: Preparar el host Proxmox

```bash
# El script setup-host.sh:
# 1. Instala drivers AMD (firmware-amd-graphics, mesa)
# 2. Habilita IOMMU en GRUB (amd_iommu=on)
# 3. Configura módulos VFIO (si se necesita passthrough completo)
# 4. Instala dependencias (pve-headers, build-essential, etc.)
# 5. Verifica que /dev/dri esté disponible
```

### Paso 2: Crear el LXC

```bash
# El script create-lxc.sh:
#
# 1. PREGUNTA: "¿Nombre de esta instancia?" (ej: "steamos", "arcade", "retro")
#    - Se usa como: hostname del LXC, nombre del contenedor Docker, 
#      nombre en Moonlight, subdominio DNS, etc.
#    - Si el usuario crea otra instancia, debe elegir otro nombre.
#
# 2. Descarga template Debian 12 de Proxmox (si no existe)
# 3. Crea LXC con:
#    - Nombre: gamebox-{nombre}
#    - Privilegiado (necesario para /dev/uinput)
#    - Bind mounts de /dev/dri, /dev/uinput, /dev/input/*
#    - Cgroup allows para uinput (c 10:223 rwm)
#    - Cgroup allows para DRI (c 226:* rwm)
#    - Cgroup allows para input (c 13:* rwm)
#    - Acceso a /sys (necesario para udev)
# 4. Asigna recursos (CPU, RAM, swap) — pregunta si default está bien
# 5. Asigna IP fija (DHCP reservado o estática)
# 6. Inicia el LXC y copia bootstrap.sh + docker-compose.yml
```

### Paso 3: Bootstrap dentro del LXC

```bash
# El script bootstrap.sh (se ejecuta dentro del LXC):
# 1. Instala Docker (via script oficial get.docker.com)
# 2. Configura Docker para usar AMD GPU
# 3. Crea red Docker gamebox-net
# 4. Ejecuta docker-compose up -d
```

### Paso 4: Usar

```bash
# 1. Abre Moonlight en tu cliente
# 2. Añade servidor (IP del Proxmox o del LXC)
# 3. Introduce el PIN de Sunshine (web UI :47990)
# 4. Selecciona "Game Mode" o "Desktop"
# 5. ¡A jugar!
```

## Problemas Conocidos y Soluciones

### 1. Teclado/ratón no funcionan en Sunshine

**Causa:** El contenedor no tiene acceso a `/dev/uinput`.

**Solución (automatizada en create-lxc.sh):**
```bash
# Bind mount en la config del LXC:
lxc.mount.entry: /dev/uinput dev/uinput none bind,optional,create=file 0 0
lxc.cgroup2.devices.allow: c 10:223 rwm
```

### 2. Cursor invisible en streaming

**Causa:** El display virtual no tiene plano de cursor.

**Solución:** Usar Gamescope con `--cursor` y configurar Sunshine para
usar cursor software.

### 3. Sin dispositivo de renderizado AMD

**Causa:** `/dev/dri/renderD128` no está montado en el LXC.

**Solución:**
```bash
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir 0 0
lxc.cgroup2.devices.allow: c 226:* rwm
```

### 4. Sunshine no captura la pantalla

**Causa:** PipeWire no está corriendo o Gamescope no expone su salida.

**Solución:**
- Asegurar que PipeWire se inicia antes que Sunshine
- Gamescope debe ejecutarse con `--headless --pipewire`

### 5. Bajo rendimiento en encoding

**Causa:** VAAPI no está usando la GPU correcta.

**Solución:** Verificar que el dispositivo de renderizado correcto
esté disponible y configurar Sunshine para usar VAAPI.

## Roadmap

### Fase 1 — Estructura Base (actual)

- [x] Directorio del proyecto creado
- [x] Este archivo GAMEBOX.md creado
- [x] `proxmox/setup-host.sh` — Script de preparación del host
- [x] `proxmox/create-lxc.sh` — Script de creación del LXC (pregunta nombre instancia)
- [x] `lxc/bootstrap.sh` — Script de bootstrap
- [x] `lxc/docker-compose.yml` — Stack Docker
- [x] `docker/Dockerfile` — Contenedor único (Gamescope + Steam + KDE + Sunshine)
- [x] `docker/entrypoint.sh` — Arranque de servicios
- [x] `docker/supervisord.conf` — Supervisor de procesos
- [x] `config/sunshine.conf` — Config base
- [x] `config/udev-rules.conf` — Reglas udev
- [x] `config/inputtino.conf` — Config input

### Fase 2 — Funcionalidad Completa

- [ ] Integración Sunshine + Gamescope + PipeWire funcional
- [ ] Modo Escritorio (KDE Plasma) como segunda app en Sunshine
- [ ] Testeo con Moonlight (input, video, audio)

### Fase 3 — Pulido

- [ ] Documentación completa (README, troubleshooting, multi-instancia)
- [ ] Panel web minimalista (estado, QR, pairing)
- [ ] Testeo en diferentes GPUs AMD
- [ ] Optimización de rendimiento
- [ ] Script todo-en-uno (`curl | bash`)

### Fase 4 — Release

- [ ] Repositorio público
- [ ] Guía de contribución

## Decisiones de Diseño

Cada decisión importante documentada para que cualquier IA que retome el
proyecto entienda el razonamiento sin tener que cuestionarlo.

### ¿Por qué Debian 12 y no Arch Linux?

Arch tiene paquetes más frescos (Gamescope más reciente, drivers más nuevos)
pero es rolling release. En un Dockerfile, las imágenes de Arch se rompen
con frecuencia porque los paquetes se actualizan constantemente. Debian 12
es predecible: una vez que funciona, sigue funcionando. Para un usuario
básico/medio, la estabilidad es prioritaria.

### ¿Por qué LXC y no VM?

- LXC comparte el kernel del host → los recursos (RAM, CPU) no están
  reservados fijamente, el LXC usa lo que necesita del pool del host.
- GPU AMD se puede compartir via bind mount de `/dev/dri`, no necesita
  PCIe passthrough completo (que reservaría la GPU para una sola VM).
- Menos overhead que KVM.
- Docker funciona nativamente dentro de LXC.

### ¿Por qué Sunshine y no Wolf?

Wolf es el servidor de streaming de Games On Whales. Es más moderno y
tiene mejor soporte multi-usuario, pero:
- No necesitamos multi-usuario (1 LXC = 1 instancia de juego)
- Wolf añade complejidad innecesaria para un solo usuario
- Sunshine es más simple, más documentado y tiene web UI propia
- Sunshine soporta PipeWire capture desde Gamescope

### ¿Por qué un solo contenedor Docker en lugar de múltiples (GOW)?

GameBox prioriza la simplicidad sobre la modularidad:
- Un solo contenedor con Gamescope + Steam + KDE + Sunshine + PipeWire
- Gestionado por supervisor (supervisord) para mantener todo corriendo
- El usuario solo interactúa con Moonlight → Sunshine → Gamescope/Steam
- Si se necesita más aislamiento, se crea otro LXC independiente

### ¿Por qué Steam via Flatpak y no nativo?

Flatpak proporciona aislamiento y no contamina el sistema base con
dependencias de Steam. Además, Flatpak recibe actualizaciones regulares
y funciona bien en contenedores. Steam nativo requeriría bibliotecas de
32 bits y podria generar conflictos con el sistema base mínimo.

### ¿Por qué Gamescope headless + PipeWire y no KMS/DRM directo?

KMS/DRM requiere que el proceso sea DRM master, lo cual es problemático
cuando la GPU está compartida (bind mount en LXC). Gamescope en modo
headless + PipeWire permite capturar el framebuffer sin tomar control
exclusivo de la GPU.

### ¿Por qué no multi-usuario (Wolf/GOW)?

El usuario dueño del proyecto decidió explícitamente que no necesita
multi-usuario. La filosofía es: **un LXC = una instancia de juego**.

Si quiere otra instancia (ej: una para juegos AAA y otra para emuladores
retro), crea otro LXC ejecutando el script de nuevo con otro nombre.
Esto simplifica enormemente la arquitectura:
- No orquestación de sesiones
- No balanceo entre usuarios
- Cada instancia es independiente y aislada
- Se puede eliminar sin afectar a otras

### ¿Por qué el script pregunta un nombre de instancia?

Cuando el usuario ejecuta `create-lxc.sh`, el script pregunta:

```
> ¿Nombre de esta instancia? (ej: steamos, arcade, retro)
```

Este nombre se usa para:
- **Hostname del LXC**: `gamebox-steamos`, `gamebox-arcade`
- **Nombre del contenedor Docker**: `gamebox-steamos`
- **Nombre en Moonlight**: Aparece como "GameBox - steamos"
- **IP**: Asigna IP fija con el nombre como referencia
- **Red**: Facilita gestionar múltiples instancias enrutando a cada LXC

Si el usuario quiere otra instancia, ejecuta el script otra vez con
un nombre diferente.

### ¿Por qué no dockur/windows?

dockur/windows ejecuta Windows en QEMU dentro de Docker. Sigue siendo
una VM con recursos fijos (RAM, CPU, disco asignados). No ofrece la
flexibilidad de recursos dinámicos que busca el usuario. Además, el
GPU passthrough a Docker es experimental y problemático.

## Regla Fundamental para Cualquier IA

**Este documento debe mantenerse siempre actualizado.**

Cada vez que una IA (o persona) trabaje en este proyecto y realice cualquier
cambio —añadir un archivo, modificar la arquitectura, cambiar una decisión
de diseño, alterar el flujo de instalación— **debe actualizar este documento
para reflejarlo**.

Reglas concretas:
- Si añades un nuevo directorio o archivo, actualiza la sección "Estructura del Repositorio".
- Si cambias una tecnología del stack, actualiza la tabla "Stack Tecnológico" y la sección "Decisiones de Diseño" explicando el motivo del cambio.
- Si modificas el flujo de instalación, actualiza los pasos en "Flujo de Instalación".
- Si descubres un problema nuevo, añádelo a "Problemas Conocidos y Soluciones".
- Si completas una fase del roadmap, marcala como [x].
- Si cambia la arquitectura, actualiza el diagrama ASCII.

**Un documento desactualizado es peor que ningún documento.** Si una IA
futura encuentra información incorrecta aquí, tomará malas decisiones.

Cuando termines tu sesión de trabajo, verifica que GAMEBOX.md refleje
todo lo que hiciste.

## Referencias

- [Games on Whales](https://games-on-whales.github.io/) — Inspiración original
- [Wolf](https://github.com/games-on-whales/wolf) — Streaming server multi-usuario
- [GOW](https://github.com/games-on-whales/gow) — Docker images gaming
- [Sunshine](https://github.com/LizardByte/Sunshine) — Streaming server
- [Moonlight](https://moonlight-stream.org/) — Cliente de streaming
- [dockur/windows](https://github.com/dockur/windows) — Windows en Docker (alternativa descartada)
- [Bazzite](https://bazzite.gg/) — SO gaming basado en Fedora (inspiración de UX)
- [Gamescope](https://github.com/ValveSoftware/gamescope) — Compositor de Valve
