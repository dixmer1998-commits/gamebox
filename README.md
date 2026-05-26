# GameBox 🎮

[![Docker](https://img.shields.io/badge/Docker-24.0.0+-blue?logo=docker&logoColor=white&style=for-the-badge)](https://www.docker.com/)
[![Linux](https://img.shields.io/badge/Linux-Any_Distro-FCC624?logo=linux&logoColor=black&style=for-the-badge)](https://kernel.org/)
[![GPU](https://img.shields.io/badge/GPU-AMD_Radeon-FF5252?logo=amd&logoColor=white&style=for-the-badge)](https://www.amd.com/)
[![Sunshine](https://img.shields.io/badge/Sunshine-Streaming-e65e2b?style=for-the-badge)](https://github.com/LizardByte/Sunshine)

**Streaming gaming auto-contenedorizado.** Convierte cualquier PC con Linux y GPU AMD en una consola remota estilo Steam Deck.

```bash
git clone https://github.com/TU-USUARIO/gamebox.git
cd gamebox
make build && make up
```

Luego conecta **Moonlight** a la IP del servidor y juega desde cualquier dispositivo (PC, tablet, móvil, Steam Deck, Apple TV).

## Stack

| Componente | Elección |
|---|---|---|
| Motor | Docker + Compose |
| Base | Fedora 42 |
| Modo Juego | SteamOS Game Mode (Gamescope) |
| Streaming | Sunshine (VA-API AMD, Wayland capture) |
| Display | labwc + Gamescope (Wayland headless) |
| Audio | PipeWire + PulseAudio |
| Input | uinput (Linux nativo) |

## Comandos

- `make build` — Construye la imagen
- `make up/down` — Levanta/detiene el contenedor
- `make logs` — Logs en tiempo real
- `make shell` — Bash dentro del contenedor
- `make host-setup` — Configura udev para /dev/uinput

## Documentación técnica

Ver [GAMEBOX.md](GAMEBOX.md) para arquitectura, decisiones de diseño, troubleshooting y roadmap.
