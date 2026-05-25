#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────
# GameBox — bootstrap.sh
# Se ejecuta DENTRO del LXC.
#   - Instala Docker
#   - Construye la imagen GameBox
#   - Arranca el contenedor
# ──────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  GameBox — Bootstrap LXC${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# ── Leer identidad de la instancia ──
if [[ -f /etc/gamebox-instance ]]; then
    source /etc/gamebox-instance
else
    GAMEBOX_INSTANCE="gamebox"
    GAMEBOX_HOSTNAME="gamebox-${GAMEBOX_INSTANCE}"
fi
echo -e "${GREEN}[INFO]${NC} Instancia: ${CYAN}${GAMEBOX_HOSTNAME}${NC}"

# ── Verificar GPU ──
echo ""
echo -e "${YELLOW}[PASO 1/5] Verificando GPU AMD...${NC}"
if ls /dev/dri/render* &>/dev/null; then
    echo -e "${GREEN}[OK]${NC} GPU AMD detectada:"
    ls -la /dev/dri/render*
    # Mostrar información del dispositivo
    if command -v lspci &>/dev/null; then
        lspci -nn 2>/dev/null | grep -i "vga\|display" || true
    fi
else
    echo -e "${RED}[ERROR] /dev/dri no disponible.${NC}"
    echo -e "Asegúrate de que el LXC tenga bind mount de /dev/dri."
    exit 1
fi

# ── Verificar uinput ──
echo ""
echo -e "${YELLOW}[PASO 2/5] Verificando /dev/uinput...${NC}"
if [[ -c /dev/uinput ]]; then
    echo -e "${GREEN}[OK]${NC} /dev/uinput disponible."
else
    echo -e "${YELLOW}[WARN]${NC} /dev/uinput no encontrado. El teclado/ratón virtual puede fallar."
    echo -e "Verifica que el LXC tenga: lxc.cgroup2.devices.allow: c 10:223 rwm"
fi

# ── Detectar renderizador AMD ──
RENDER_DEVICE=""
for dev in /dev/dri/renderD*; do
    if [[ -c "$dev" ]]; then
        RENDER_DEVICE="$dev"
        break
    fi
done

# ── Instalar Docker ──
echo ""
echo -e "${YELLOW}[PASO 3/5] Instalando Docker...${NC}"
if command -v docker &>/dev/null; then
    echo -e "${GREEN}[OK]${NC} Docker ya está instalado: $(docker --version)"
else
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    echo -e "${GREEN}[OK]${NC} Docker instalado: $(docker --version)"
fi

# ── Construir imagen GameBox ──
echo ""
echo -e "${YELLOW}[PASO 4/5] Construyendo imagen GameBox...${NC}"

GAMEBOX_DIR="/root/gamebox"
mkdir -p "${GAMEBOX_DIR}"

# Copiar Dockerfile y entrypoint
cp /root/docker-compose.yml "${GAMEBOX_DIR}/"

# Construir imagen
cd "${GAMEBOX_DIR}"
docker build -t "gamebox:${GAMEBOX_INSTANCE}" -f- . << 'DOCKERFILE'
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV GAMEBOX_INSTANCE=${GAMEBOX_INSTANCE}
ENV RENDER_DEVICE=${RENDER_DEVICE}

# ── Actualizar e instalar dependencias base ──
RUN apt-get update -qq && apt-get install -y -qq \
    # Herramientas de sistema
    curl \
    ca-certificates \
    gnupg \
    sudo \
    dbus \
    systemd \
    # PipeWire para captura de video
    pipewire \
    pipewire-pulse \
    libspa-0.2-bluetooth \
    wireplumber \
    # VAAPI / AMD
    mesa-va-drivers \
    mesa-vulkan-drivers \
    libva-drm2 \
    libva2 \
    # Entorno gráfico mínimo para Gamescope
    libgl1-mesa-dglx \
    libegl1 \
    libgles2 \
    libxkbcommon0 \
    libwayland-client0 \
    libwayland-server0 \
    libwayland-egl1 \
    libinput10 \
    libseat1 \
    # KDE Plasma (escritorio)
    kde-plasma-desktop \
    xserver-xorg-core \
    xserver-xorg-input-all \
    xserver-xorg-video-dummy \
    # Utilidades
    nano \
    htop \
    procps \
    # Supervisor para gestionar procesos
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# ── Steam Flatpak ──
RUN apt-get update -qq && apt-get install -y -qq flatpak && \
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo && \
    flatpak install -y flathub com.valvesoftware.Steam

# ── Sunshine ──
RUN apt-get update -qq && apt-get install -y -qq \
    libboost-all-dev \
    libpulse-dev \
    libopus0 \
    libevdev-dev \
    libavcodec-dev \
    libavutil-dev \
    libavformat-dev \
    libswscale-dev \
    libx11-dev \
    libxfixes-dev \
    libxrandr-dev \
    libglfw3-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libminiupnpc-dev \
    libmfx-dev \
    cmake \
    g++ \
    git \
    && rm -rf /var/lib/apt/lists/*

# Compilar Sunshine desde fuente (última versión estable)
RUN git clone --depth=1 --branch=v0.23.1 https://github.com/LizardByte/Sunshine.git /tmp/sunshine && \
    cd /tmp/sunshine && \
    cmake -B build -DCMAKE_BUILD_TYPE=Release -DSUNSHINE_BUILD_HOME=OFF && \
    cmake --build build -j$(nproc) && \
    cmake --install build && \
    rm -rf /tmp/sunshine

# ── Gamescope ──
RUN apt-get update -qq && apt-get install -y -qq \
    build-essential \
    meson \
    ninja-build \
    libdrm-dev \
    libgbm-dev \
    libxcb-dri3-0-dev \
    libxcb-present-dev \
    libxshmfence-dev \
    libxxf86vm-dev \
    libxdamage-dev \
    libxcomposite-dev \
    libxtst-dev \
    libxcursor-dev \
    libxi-dev \
    libxinerama-dev \
    libxmu-dev \
    libxmuu-dev \
    libcap-dev \
    libwayland-dev \
    libwlroots-dev \
    libpipewire-0.3-dev \
    libspa-0.2-dev \
    libavformat-dev \
    libavcodec-dev \
    libavutil-dev \
    hwdata \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 https://github.com/ValveSoftware/gamescope.git /tmp/gamescope && \
    cd /tmp/gamescope && \
    meson setup build && \
    ninja -C build && \
    ninja -C build install && \
    rm -rf /tmp/gamescope

# ── Configuración ──
COPY supervisord.conf /etc/supervisor/conf.d/gamebox.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Crear usuario steam (para que corran los procesos)
RUN useradd -m -G video,audio,input,render steam && \
    echo "steam ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

ENTRYPOINT ["/entrypoint.sh"]
DOCKERFILE

echo -e "${GREEN}[OK]${NC} Imagen construida."

# ── Arrancar contenedor ──
echo ""
echo -e "${YELLOW}[PASO 5/5] Arrancando GameBox...${NC}"

# Detener contenedor anterior si existe
docker rm -f "gamebox-${GAMEBOX_INSTANCE}" 2>/dev/null || true

docker run -d \
    --name "gamebox-${GAMEBOX_INSTANCE}" \
    --hostname "${GAMEBOX_HOSTNAME}" \
    --privileged \
    --restart unless-stopped \
    --network host \
    -e INSTANCE_NAME="${GAMEBOX_INSTANCE}" \
    -e TZ="UTC" \
    -v /dev/dri:/dev/dri:ro \
    -v /dev/uinput:/dev/uinput \
    -v /dev/input:/dev/input:ro \
    -v gamebox-data-${GAMEBOX_INSTANCE}:/home/steam \
    "gamebox:${GAMEBOX_INSTANCE}"

echo -e "${GREEN}[OK]${NC} Contenedor 'gamebox-${GAMEBOX_INSTANCE}' arrancado."

# ── Información final ──
HOST_IP=$(hostname -I | awk '{print $1}')
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  GameBox listo!${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo -e "  Instancia:   ${CYAN}${GAMEBOX_INSTANCE}${NC}"
echo -e "  Contenedor:  ${CYAN}gamebox-${GAMEBOX_INSTANCE}${NC}"
echo ""
echo -e "  ${YELLOW}Sunshine Web UI:${NC}"
echo -e "    ${CYAN}http://${HOST_IP}:47990${NC}"
echo ""
echo -e "  ${YELLOW}Moonlight:${NC}"
echo -e "    Añade servidor: ${CYAN}${HOST_IP}${NC}"
echo ""
echo -e "  ${YELLOW}Gestión:${NC}"
echo -e "    docker logs -f gamebox-${GAMEBOX_INSTANCE}"
echo -e "    docker exec -it gamebox-${GAMEBOX_INSTANCE} bash"
echo ""
echo -e "${CYAN}============================================${NC}"
