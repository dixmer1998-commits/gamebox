# GameBox

Streaming gaming auto-contenedorizado sobre Proxmox + Docker o cualquier PC Linux.

## Visión General

GameBox es un proyecto que permite convertir un servidor Proxmox o cualquier PC con Linux y una GPU AMD en una consola de juegos remota de alto rendimiento al estilo SteamOS. Se compone de un único contenedor Docker que ejecuta **Gamescope + Steam Nativo** (Modo Juego) y **KDE Plasma** (Modo Escritorio), transmitiendo la imagen y el sonido de baja latencia a cualquier dispositivo cliente mediante **Sunshine + Moonlight**.

### Objetivo

Que un usuario despliegue un stack Docker unificado y en minutos esté jugando desde cualquier dispositivo (PC, tablet, Steam Deck, móvil, Apple TV) con aceleración gráfica por hardware y una experiencia de consola tipo SteamOS.

### Público objetivo

Usuarios con GPU AMD (incluyendo hardware antiguo/medio como la arquitectura Polaris y la **RX 580**) que desean una consola en la red local sin necesidad de:
* Tener un monitor físico conectado al servidor.
* Configurar PCIe Passthrough exclusivo (permitiendo compartir la GPU con el host y otros contenedores).
* Sufrir problemas de compatibilidad de periféricos (mandos, teclado y ratón).
* Mantener una pesada máquina virtual (VM) con recursos fijos de hardware.

---

## Stack Tecnológico

| Componente | Elección | Motivación |
| :--- | :--- | :--- |
| **Hipervisor (Opcional)** | Proxmox VE 8.x | Hipervisor maduro con soporte para contenedores LXC de bajo overhead. |
| **Contenedor Host (Opcional)**| LXC Privilegiado (Debian/Ubuntu) | Comparte el kernel con el host, recursos dinámicos y GPU compartida vía bind mounts. |
| **Motor de Contenedores** | Docker + Compose | Universal, estándar en la industria y de fácil despliegue local o remoto. |
| **Base de la Imagen** | **Ubuntu 24.04 LTS (Noble)** | Controladores gráficos de Mesa modernos (Mesa 24.x) necesarios para Gamescope. |
| **Modo Juego** | **Gamescope + Steam (Nativo)** | Composición Wayland de Valve. Instalado nativamente (`i386`) para evitar bloqueos de seguridad de `bubblewrap` (Flatpak) dentro de Docker. |
| **Modo Escritorio** | KDE Plasma | Entorno completo e idéntico al modo escritorio de la Steam Deck. |
| **Streaming** | Sunshine v2026.x | Servidor de streaming WebRTC de latencia ultrabaja. |
| **Codificación HW** | **VA-API (AMD)** | Hardware encoding por VA-API para soporte completo de GPUs AMD antiguas (RX 580/Polaris) sin soporte de Vulkan Video. |
| **Captura de video** | PipeWire (Gamescope Headless) | Captura directa de framebuffer nativa y de baja latencia. |
| **Input virtual** | **uinput (Linux nativo)** | Inyección directa de teclado, ratón y gamepads (Xbox 360) sobre `/dev/uinput` del host. |
| **Preview web** | Python3 + FFmpeg (MJPEG) | Servidor web ultra-ligero que sirve una vista previa de la pantalla en `http://ip:48090`. |

---

## Arquitectura del Sistema

```
┌───────────────────────────────────────────────────────────────┐
│                    Linux Host / Proxmox Host                  │
│  Drivers AMD · /dev/dri · /dev/uinput                        │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐     │
│  │  LXC Privilegiado (Si se usa Proxmox) / Host PC     │     │
│  │  Montajes: /dev/dri, /dev/uinput, /dev/input/*      │     │
│  │  IP fija: 192.168.X.Y                               │     │
│  │                                                      │     │
│  │  ┌───────────────────────────────────────────────┐  │     │
│  │  │           Docker                              │  │     │
│  │  │                                                │  │     │
│  │  │  ┌─────────────────────────────────────────┐  │  │     │
│  │  │  │  gamebox (Contenedor Único)             │  │  │     │
│  │  │  │                                          │  │  │     │
│  │  │  │  ┌──────────────┐  ┌──────────────┐    │  │  │     │
│  │  │  │  │  Game Mode   │  │ Desktop Mode │    │  │  │     │
│  │  │  │  │              │  │              │    │  │  │     │
│  │  │  │  │ Gamescope    │  │ KDE Plasma   │    │  │  │     │
│  │  │  │  │ (Headless)   │  │ (Dummy Xorg) │    │  │  │     │
│  │  │  │  │  └→ Steam    │  │              │    │  │  │     │
│  │  │  │  │  (Nativo)    │  │              │    │  │  │     │
│  │  │  │  └──────┬───────┘  └──────┬───────┘    │  │  │     │
│  │  │  │         │ PipeWire        │ X11/XShm   │  │  │     │
│  │  │  │         ▼                 ▼            │  │  │     │
│  │  │  │  ┌──────────────────────────────────┐  │  │  │     │
│  │  │  │  │         Sunshine                 │  │  │  │     │
│  │  │  │  │  App "Juego"      → Gamescope    │  │  │  │     │
│  │  │  │  │  App "Escritorio" → KDE          │  │  │  │     │
│  │  │  │  │  Web UI : http://ip:47990       │  │  │  │     │
│  │  │  │  └──────────────────────────────────┘  │  │  │     │
│  │  │  │                                            │  │     │
│  │  │  │  ┌──────────────────────────────────┐  │  │  │     │
│  │  │  │  │  Preview (ffmpeg + MJPEG)        │  │  │  │     │
│  │  │  │  │  PipeWire → ffmpeg → MJPEG HTTP │  │  │  │     │
│  │  │  │  │  Web UI : http://ip:48090       │  │  │  │     │
│  │  │  │  └──────────────────────────────────┘  │  │  │     │
│  │  │  └─────────────────────────────────────────┘  │  │     │
│  │  └───────────────────────────────────────────────┘  │     │
│  └─────────────────────────────────────────────────────┘     │
│                                                              │
│  Cliente Moonlight ◄─── Red ──── Sunshine :47989             │
│  (PC, tablet, móvil, Steam Deck...)                         │
└───────────────────────────────────────────────────────────────┘
```

---

## Estructura del Repositorio

```
gamebox/
│
├── GAMEBOX.md                   # Este archivo — guía técnica de arquitectura
├── Makefile                     # Atajos de orquestación local (build, up, logs, etc.)
├── README.md                    # README público y guía para GitHub (Docker autónomo)
├── docker-compose.yml           # Archivo de despliegue Compose para PC Linux
│
├── proxmox/                     # Scripts de automatización para Proxmox
│   ├── setup-host.sh            # Prepara el host Proxmox (módulos, IOMMU, drivers)
│   └── create-lxc.sh            # Crea el LXC, inyecta configuraciones y sube el proyecto
│
├── lxc/                         # Archivos para ejecutar dentro de Proxmox LXC
│   ├── bootstrap.sh             # Instala Docker y ejecuta compose en el LXC
│   └── docker-compose.yml       # Stack Compose personalizado para multi-instancia en LXC
│
├── docker/                      # Construcción de la imagen Docker
│   ├── Dockerfile               # Imagen de producción basada en Ubuntu 24.04
│   ├── entrypoint.sh            # Script de arranque (dbus, PipeWire, Sunshine, Steam)
│   └── preview/                 # Servidor de previsualización en vivo
│       ├── server.py            # Servidor HTTP ligero en Python3
│       └── index.html           # Página web con reproducción MJPEG
│
└── config/                      # Archivos de configuración compartidos
    ├── sunshine.conf            # Ajustes optimizados para GPU AMD (VA-API) y uinput
    ├── udev-rules.conf          # Reglas de permisos para dispositivos de entrada en el contenedor
    └── xorg-dummy.conf          # Configuración del monitor virtual para KDE Plasma
```

---

## Decisiones de Diseño Clave

### 1. ¿Por qué Ubuntu 24.04 y no Debian 12 o Arch Linux?
Debian 12 es extremadamente estable, pero sus controladores de Mesa y versiones de Gamescope son demasiado antiguos. Intentar ejecutar Gamescope en Debian 12 requiere forzar compatibilidades obsoletas de X11 o compilar enormes librerías de sistema desde fuentes. Arch Linux es rolling-release y tiende a romper los scripts de construcción del Dockerfile de forma imprevista.
**Ubuntu 24.04 (Noble)** proporciona el balance perfecto: Mesa 24.0+ y Gamescope moderno (compatible con el flag `--headless`) de manera nativa e integrada en repositorios estables de largo soporte (LTS).

### 2. ¿Por qué Steam Nativo (`i386`) y no Steam Flatpak?
Steam Flatpak requiere ejecutar `bubblewrap` (bwrap) para aislar la aplicación. Ejecutar `bwrap` dentro de un contenedor Docker (incluso en modo privilegiado) provoca fallos críticos de seguridad y restricciones de namespaces (`seccomp`), impidiendo que Steam headless arranque bajo Gamescope.
Instalar Steam de forma nativa activando el soporte multiarquitectura de 32 bits dentro de la imagen Docker de Ubuntu elimina por completo la doble contenedorización y garantiza un inicio instantáneo y libre de fallos de permisos.

### 3. ¿Por qué inyección por `uinput` nativo en lugar de `inputtino`?
Aunque `inputtino` es muy robusto, Sunshine v2026.x incluye soporte directo para inyectar mandos de Xbox 360, PlayStation, teclados y ratones mediante la API nativa de **uinput** del kernel de Linux. Al conceder los permisos correctos a `/dev/uinput`, evitamos sobrecargar el contenedor con compilaciones o subprocesos adicionales de `inputtino`, logrando menor latencia en las pulsaciones y mayor compatibilidad de periféricos directamente desde Moonlight.

### 4. ¿Por qué forzar codificación VA-API en lugar de Vulkan Video?
Las GPU AMD Radeon más antiguas de arquitectura Polaris (como la **RX 580**) carecen de decodificación y codificación por hardware a nivel de silicio para la nueva API *Vulkan Video*. Dado que Sunshine moderno intenta inicializar los codificadores de Vulkan de forma prioritaria, esto causaba que la RX 580 se colgara al iniciar el streaming.
Configurando estrictamente `encoder = vaapi` y deshabilitando Vulkan Video durante el build, nos aseguramos de que Sunshine aproveche la madurez del driver `mesa-va-drivers`, transmitiendo en H.264/HEVC a 60 FPS con un rendimiento óptimo y consumo ínfimo de CPU.

### 5. ¿Por qué Gamescope Headless en lugar de monitor virtual Xorg?
Gamescope headless crea su propio compositor virtual Wayland de alto rendimiento directamente en la GPU sin requerir una pantalla física. Al no necesitar un servidor X11 pesado en ejecución (como Xorg Dummy), los juegos corren a mayor velocidad, con menor latencia y con mejor soporte para tasas de refresco variables y re-escalado inteligente de resolución.

---

## Flujo de Instalación (Proxmox LXC)

### Paso 1: Preparar el host Proxmox
Ejecuta el script de preparación para verificar drivers e IOMMU en el host:
```bash
sudo ./proxmox/setup-host.sh
```

### Paso 2: Crear el LXC
Ejecuta el script interactivo. Te pedirá el nombre de la instancia (ej: `retro`), la RAM, CPU, disco e IP, y creará el LXC privilegiado **sin destruir o sobrescribir la configuración del contenedor**:
```bash
sudo ./proxmox/create-lxc.sh
```
*(Este script empaqueta todo el directorio del proyecto en un tarball, lo transfiere al LXC y lo extrae automáticamente en `/root/gamebox/`)*.

### Paso 3: Lanzar el Bootstrap en el LXC
Ingresa al contenedor LXC e inicia la instalación automática:
```bash
pct enter <LXCID>
/root/gamebox/lxc/bootstrap.sh
```
*(El bootstrap instalará Docker y levantará el stack unificado mediante Docker Compose, usando exactamente las mismas imágenes y configuraciones de producción que el despliegue local).*

---

## Dependencias de Compilación de Sunshine

Sunshine v2026.x se compila desde fuente dentro del Dockerfile. Las siguientes dependencias extras fueron necesarias sobre Ubuntu 24.04, identificadas iterativamente durante el build:

| Dependencia | Paquete / Fuente | Propósito |
| :--- | :--- | :--- |
| XCB XFixes | `libxcb-xfixes0-dev` | Captura X11 vía XCB (`x11grab.cpp`) |
| GBM | `libgbm-dev` | Buffer management de gráficos para Wayland (`wayland.cpp`) |
| libcap | `libcap-dev` | Capacidades POSIX (SO_PRIORITY, etc.) |
| PipeWire | `libpipewire-0.3-dev` | Captura de pantalla por PipeWire |
| libnotify | `libnotify-dev` | Notificaciones del sistema tray |
| AppIndicator | `libayatana-appindicator3-dev` | Indicador del system tray |
| Python pip | `python3-pip` | Scripts de build (con `PIP_BREAK_SYSTEM_PACKAGES=1`) |
| Doxygen | `≥1.10` desde binarios oficiales | Doxyconfig (submodulo de `tray`) exige versión ≥1.10, Ubuntu 24.04 solo provee 1.9.8 |
| Node.js | `≥20.12` desde NodeSource 22.x | `@vitejs/plugin-vue` usa `crypto.hash` (no disponible en Node 18) |
| Graphviz | `graphviz` | `dot` requerido por doxyconfig |

### Problemas de Compilación Resueltos

1. **Python externally-managed**: Ubuntu 24.04 bloquea `pip install` fuera de virtualenv. Solución: `PIP_BREAK_SYSTEM_PACKAGES=1`.
2. **Doxygen ≥ 1.10**: Doxyconfig requiere doxygen ≥ 1.10 pero Ubuntu 24.04 empaqueta 1.9.8. Solución: descargar binario estático desde doxygen.nl.
3. **Node.js 18 sin `crypto.hash`**: `@vitejs/plugin-vue` usa `crypto.hash` (Node ≥20.12). Solución: NodeSource setup_22.x que reemplaza Node 18.
4. **Falta `gbm.h`**: Wayland grab requiere GBM. Solución: `libgbm-dev`.
5. **Falta `xcb/xfixes.h`**: x11grab requiere XCB XFixes. Solución: `libxcb-xfixes0-dev`.
6. **Falta `libcap-dev`**: Necesario para capacidades POSIX en socket.
7. **Falta `libpipewire-0.3-dev`**: PipeWire grab requiere el header `pipewire/pipewire.h`.
8. **Falta `libnotify-dev` y `libayatana-appindicator3-dev`**: System tray de tray.c requiere ambos.

## Regla Fundamental para Cualquier IA

**Este documento debe mantenerse siempre actualizado.**

Cada vez que una IA (o desarrollador) trabaje en este repositorio y realice cualquier modificación en el código, configuraciones, flujos de instalación o dependencias:
1. Actualiza la estructura del repositorio si hay archivos nuevos o eliminados.
2. Actualiza la tabla del Stack Tecnológico y la sección de Decisiones de Diseño si cambian las dependencias o enfoques de software.
3. Actualiza el Roadmap marcando las fases completadas.

---

## Roadmap

### Fase 1 — Infraestructura Base (Completada)
- [x] Dockerfile con Ubuntu 24.04, Steam nativo, Gamescope (PPA), KDE Plasma, Sunshine compilado desde fuente
- [x] Dependencias de compilación completas
- [x] FFmpeg pre-compilado integrado

### Fase 2 — Streaming y Captura (Completada)
- [x] Sunshine configurado con VA-API para AMD (RX 580/Polaris)
- [x] PipeWire para captura de pantalla
- [x] System tray con AppIndicator
- [x] Preview web MJPEG con FFmpeg + Python

### Fase 3 — Modo Juego (Pendiente)
- [ ] Verificar que Gamescope headless inicie Steam correctamente
- [ ] Configurar apps de Sunshine: "Juego" → Gamescope + Steam, "Escritorio" → KDE Plasma
- [ ] Probar inyección de mandos vía uinput

### Fase 4 — Despliegue y Documentación (Pendiente)
- [ ] Probar en Proxmox LXC con GPU AMD real
- [ ] Agregar perfiles de Moonlight y guías de conexión remota
- [ ] Documentar scripts de instalación y troubleshooting
