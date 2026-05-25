# GameBox — Dockerfile
# Contenedor único con:
#   - Gamescope + Steam (Modo Juego)
#   - KDE Plasma (Modo Escritorio)
#   - Sunshine (Streaming)
#   - PipeWire (Captura de video)
#
# Base: Debian 12 (Bookworm)

ARG GAMEBOX_INSTANCE=gamebox

FROM debian:bookworm-slim

ARG GAMEBOX_INSTANCE
ENV GAMEBOX_INSTANCE=${GAMEBOX_INSTANCE}
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV DISPLAY=:0
ENV XDG_RUNTIME_DIR=/run/user/1000

# ── Sistema base ──
RUN apt-get update -qq && apt-get install -y -qq \
    curl \
    ca-certificates \
    gnupg \
    sudo \
    dbus \
    systemd \
    nano \
    htop \
    procps \
    neofetch \
    && rm -rf /var/lib/apt/lists/*

# ── PipeWire (captura de video/audio) ──
RUN apt-get update -qq && apt-get install -y -qq \
    pipewire \
    pipewire-pulse \
    libspa-0.2-bluetooth \
    wireplumber \
    && rm -rf /var/lib/apt/lists/*

# ── AMD / VAAPI ──
RUN apt-get update -qq && apt-get install -y -qq \
    mesa-va-drivers \
    mesa-vulkan-drivers \
    libva-drm2 \
    libva2 \
    vainfo \
    && rm -rf /var/lib/apt/lists/*

# ── Dependencias gráficas ──
RUN apt-get update -qq && apt-get install -y -qq \
    libgl1-mesa-dglx \
    libegl1 \
    libgles2 \
    libxkbcommon0 \
    libwayland-client0 \
    libwayland-server0 \
    libwayland-egl1 \
    libinput10 \
    libseat1 \
    libdrm2 \
    && rm -rf /var/lib/apt/lists/*

# ── Flatpak + Steam ──
RUN apt-get update -qq && apt-get install -y -qq \
    flatpak \
    && flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo \
    && flatpak install -y flathub com.valvesoftware.Steam \
    && rm -rf /var/lib/apt/lists/*

# ── KDE Plasma (escritorio minimalista) ──
RUN apt-get update -qq && apt-get install -y -qq \
    kde-plasma-desktop \
    xserver-xorg-core \
    xserver-xorg-video-dummy \
    xinit \
    && rm -rf /var/lib/apt/lists/*

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
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 https://github.com/ValveSoftware/gamescope.git /tmp/gamescope \
    && cd /tmp/gamescope \
    && meson setup build \
    && ninja -C build \
    && ninja -C build install \
    && rm -rf /tmp/gamescope

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
    libcurl4-openssl-dev \
    libssl-dev \
    libminiupnpc-dev \
    cmake \
    g++ \
    git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 --branch=v0.23.1 https://github.com/LizardByte/Sunshine.git /tmp/sunshine \
    && cd /tmp/sunshine \
    && cmake -B build -DCMAKE_BUILD_TYPE=Release -DSUNSHINE_BUILD_HOME=OFF \
    && cmake --build build -j$(nproc) \
    && cmake --install build \
    && rm -rf /tmp/sunshine

# ── Crear usuario ──
RUN useradd -m -G video,audio,input,render steam \
    && echo "steam ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ── Configuración de Xorg para display virtual (modo escritorio) ──
COPY docker/xorg-dummy.conf /etc/X11/xorg.conf.d/00-dummy.conf

# ── Supervisor ──
RUN apt-get update -qq && apt-get install -y -qq supervisor && rm -rf /var/lib/apt/lists/*
COPY docker/supervisord.conf /etc/supervisor/conf.d/gamebox.conf

# ── Config Sunshine ──
COPY config/sunshine.conf /etc/sunshine.conf

# ── Entrypoint ──
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
