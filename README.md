# GameBox 🎮

[![Docker](https://img.shields.io/badge/Docker-24.0.0+-blue?logo=docker&logoColor=white&style=for-the-badge)](https://www.docker.com/)
[![Linux](https://img.shields.io/badge/Linux-Any_Distro-FCC624?logo=linux&logoColor=black&style=for-the-badge)](https://kernel.org/)
[![GPU](https://img.shields.io/badge/GPU-AMD_Radeon-FF5252?logo=amd&logoColor=white&style=for-the-badge)](https://www.amd.com/)
[![Wayland](https://img.shields.io/badge/Wayland-Gamescope-00b0ff?style=for-the-badge)](https://github.com/ValveSoftware/gamescope)

**Streaming gaming auto-contenedorizado sobre cualquier PC con Linux y GPU AMD.**

GameBox convierte cualquier ordenador con Linux y una GPU AMD en una consola de juegos remota de alto rendimiento al estilo SteamOS. Todo el stack gráfico necesario corre de manera aislada y dinámica dentro de un único contenedor Docker.

---

## 🚀 ¿Qué hace especial a GameBox?

* **Recursos dinámicos:** A diferencia de una Máquina Virtual (VM) pesada, Docker comparte la CPU y la RAM de forma dinámica con el host.
* **GPU Compartida:** La GPU AMD se comparte mediante bind mount (`/dev/dri`), lo que permite al host y a otros contenedores usar la aceleración gráfica simultáneamente.
* **Steam Nativo integrado:** Instalado directamente en el contenedor (sin el aislamiento Flatpak/bubblewrap tradicional que suele romperse al correr headless en Docker).
* **Compatibilidad amplia:** Optimizada específicamente para soportar codificación **VA-API** en GPUs AMD antiguas y modernas (incluyendo arquitecturas Polaris como la **RX 580**, que no disponen de codificación Vulkan Video).

---

## 🛠️ Stack Tecnológico

| Componente | Elección | Motivación |
| :--- | :--- | :--- |
| **Base del Contenedor** | Ubuntu 24.04 (Noble) | Versión de Mesa moderna (Mesa 24.0+) ideal para Gamescope y drivers AMD estables. |
| **Modo Juego** | Gamescope + Steam | Composición Wayland de Valve para la experiencia real de SteamOS (Gamepad UI). |
| **Modo Escritorio** | KDE Plasma | Escritorio familiar e idéntico al modo escritorio de la Steam Deck. |
| **Streaming** | Sunshine | Servidor de streaming de latencia ultrabaja compatible con Moonlight. |
| **Codificación HW** | VA-API (Mesa) | Hardware encoding de alta velocidad para H.264/HEVC, ideal para GPUs Polaris (RX 580) y RDNA. |
| **Audio y Captura** | PipeWire + WirePlumber | Captura de audio y video unificada y de muy baja latencia. |
| **Input Virtual** | uinput (Linux nativo) | Inyección directa de teclado, ratón y mandos emulados (Xbox 360). |
| **Vista Previa** | Python3 + FFmpeg | Servidor HTTP minimalista que sirve un MJPEG en tiempo real para previsualizar la pantalla desde cualquier navegador. |

---

## 📋 Requisitos de Hardware y Software

* **CPU:** Cualquiera con soporte para virtualización / contenedores.
* **GPU:** AMD Radeon RX 400 series o superior ( Polaris / Vega / RDNA 1-2-3 ).
* **Host OS:** Cualquier distribución Linux moderna (Ubuntu, Debian, Arch, Fedora, etc.).
* **Docker:** Versión 24.0 o superior con Docker Compose instalado.

---

## ⚙️ Guía de Instalación Rápida

### 1. Preparar el Host (Permisos de Input)
Para que Sunshine pueda crear periféricos virtuales (como mandos de juego y ratones), necesitas dar permisos de escritura al dispositivo virtual `/dev/uinput` del host.

Puedes automatizar esto ejecutando:
```bash
make host-setup
```
*(Este comando crea una regla udev para `/dev/uinput` y carga el módulo del kernel correspondiente).*

Asegúrate de agregar tu usuario de Linux actual al grupo `input`:
```bash
sudo usermod -aG input $USER
```
*(Reinicia tu sesión de usuario para aplicar el grupo).*

### 2. Clonar y Desplegar
Clona el repositorio en tu PC Linux:
```bash
git clone https://github.com/TU-USUARIO/gamebox.git
cd gamebox
```

Construye la imagen Docker personalizada (este proceso descargará Steam de Valve y compilará la última versión estable de Sunshine):
```bash
make build
```

Una vez construida la imagen con éxito, levanta el contenedor en segundo plano:
```bash
make up
```

### 3. Verificar el Estado
Comprueba si el contenedor está en ejecución y visualiza los logs de Sunshine:
```bash
make status
make logs
```

---

## 🎮 Conectarse a Jugar

1. **Vincular Sunshine Web UI:**
   Abre en tu navegador la consola de administración de Sunshine:
   👉 `http://localhost:47990`
   *(Acepta la advertencia de certificado auto-firmado, crea tu usuario/contraseña y entra a la pestaña 'Configuration' o 'PIN' si es necesario).*

2. **Abrir la Vista Previa (Preview):**
   Puedes verificar que Steam se ha iniciado correctamente abriendo el servidor de vista previa en tu navegador:
   👉 `http://localhost:48090`
   Aquí verás la salida exacta de Gamescope a unos 10-15 FPS, ideal para confirmar que todo funciona antes de iniciar el streaming.

3. **Vincular Moonlight:**
   * Abre **Moonlight** en tu dispositivo cliente (PC, tablet, móvil, Steam Deck, Apple TV).
   * Añade la IP de tu PC Linux de forma manual o deja que lo auto-detecte.
   * Introduce el código PIN que te muestra Moonlight dentro de la Web UI de Sunshine (`http://localhost:47990` pestaña PIN).
   * ¡Selecciona **🎮 Modo Juego (Steam)** o **🖥️ Modo Escritorio (KDE)** y comienza a jugar!

---

## 🎛️ Comandos Rápidos (Makefile)

El archivo `Makefile` incluido facilita enormemente la gestión del stack:

* `make build` : Reconstruye la imagen del contenedor.
* `make up` : Levanta el contenedor de streaming.
* `make down` : Detiene el contenedor y libera la GPU.
* `make logs` : Muestra los logs en tiempo real para depuración.
* `make shell` : Abre una consola bash interactiva dentro del contenedor como root.
* `make clean` : Elimina volúmenes y limpia imágenes antiguas del disco.

---

## 📝 Personalización

Puedes editar el archivo [docker-compose.yml](file:///home/deck/proyectos/gamebox/docker-compose.yml) para adaptar las opciones:

* **Zona Horaria (`TZ`):** Ajusta la variable `TZ` a tu zona local (ej: `America/Bogota`, `Europe/Madrid`) para que la hora en el modo escritorio sea correcta.
* **Auto-Arranque de Steam (`AUTO_STEAM`):** Si cambias esta variable a `true`, Steam nativo se iniciará inmediatamente al arrancar el contenedor sin necesidad de llamar a la app desde Moonlight.

---

## 🗺️ Roadmap de Contribución

GameBox se encuentra en fase activa de desarrollo autónomo. Las siguientes características están planificadas para las próximas versiones:
- [x] Contenedor base moderno en Ubuntu 24.04 y Mesa drivers.
- [x] Ejecución de Steam de forma nativa (sin sandbox nested Flatpak).
- [x] Forzado de VA-API en Sunshine para GPUs AMD legacy (RX 580).
- [x] Integración de inyección de mandos mediante `uinput` directo.
- [ ] Implementación de un script instalador automático todo-en-uno (`curl | bash`).
- [ ] Añadir audio surround de 5.1/7.1 canales en Pipewire.

¡Cualquier Pull Request es bienvenido! Por favor abre un Issue para discutir los cambios que te gustaría proponer.
