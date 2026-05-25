# GameBox — Dockerfile (Refactorizado para Docker Autónomo)
# Contenedor único con:
#   - Gamescope + Steam Nativo (Modo Juego)
#   - KDE Plasma (Modo Escritorio)
#   - Sunshine (Streaming con soporte VA-API forzado para AMD Polaris/RX 580)
#   - PipeWire (Captura de video/audio)
#
# Base: Ubuntu 24.04 (Noble Numbat) para Mesa drivers actualizados

FROM ubuntu:24.04

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
    python3 \
    && rm -rf /var/lib/apt/lists/*

# ── PipeWire (captura de video/audio) ──
RUN apt-get update -qq && apt-get install -y -qq \
    pipewire \
    pipewire-pulse \
    libspa-0.2-bluetooth \
    wireplumber \
    && rm -rf /var/lib/apt/lists/*

# ── AMD / VAAPI y Vulkan ──
RUN apt-get update -qq && apt-get install -y -qq \
    mesa-va-drivers \
    mesa-vulkan-drivers \
    libva-drm2 \
    libva2 \
    vainfo \
    vulkan-tools \
    && rm -rf /var/lib/apt/lists/*

# ── Dependencias gráficas, Wayland y Xwayland ──
RUN apt-get update -qq && apt-get install -y -qq \
    libgl1 \
    libegl1 \
    libgles2 \
    libxkbcommon0 \
    libwayland-client0 \
    libwayland-server0 \
    libwayland-egl1 \
    libinput10 \
    libseat1 \
    libdrm2 \
    xwayland \
    && rm -rf /var/lib/apt/lists/*

# ── Gamescope (desde repos oficiales de Ubuntu 24.04) ──
RUN apt-get update -qq && apt-get install -y -qq \
    gamescope \
    && rm -rf /var/lib/apt/lists/*

# ── Steam Nativo (Instalación limpia de 32/64 bits) ──
# Habilitar soporte multiarquitectura i386 para los binarios de 32 bits de Steam/juegos
RUN dpkg --add-architecture i386 && \
    apt-get update -qq && \
    apt-get install -y -qq software-properties-common && \
    add-apt-repository -y multiverse && \
    apt-get update -qq && \
    # Pre-aceptar la licencia de Steam para evitar bloqueos interactivos en el build
    echo "steam steam/question select I AGREE" | debconf-set-selections && \
    echo "steam steam/license note ''" | debconf-set-selections && \
    # Descargar e instalar el paquete oficial de Steam de Valve (resuelve udev rules y dependencias)
    curl -sqL -o /tmp/steam.deb https://media.steampowered.com/client/installer/steam.deb && \
    apt-get install -y -qq /tmp/steam.deb && \
    rm /tmp/steam.deb && \
    rm -rf /var/lib/apt/lists/*

# ── KDE Plasma (escritorio) ──
RUN apt-get update -qq && apt-get install -y -qq \
    kde-plasma-desktop \
    xserver-xorg-core \
    xserver-xorg-video-dummy \
    xinit \
    && rm -rf /var/lib/apt/lists/*

# ── Compilación de Sunshine (v2026.516.143833) ──
RUN apt-get update -qq && apt-get install -y -qq \
    build-essential \
    cmake \
    git \
    libboost-all-dev \
    libpulse-dev \
    libopus-dev \
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
    libva-dev \
    libdrm-dev \
    nlohmann-json3-dev \
    libglx0 \
    libnuma1 \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Descargar FFmpeg pre-compilado (build-deps) antes de cmake usando curl (arreglado wget bug)
RUN curl -sqL -o /tmp/ffmpeg.tar.gz \
    "https://github.com/LizardByte/build-deps/releases/download/v2026.516.30821/Linux-x86_64-ffmpeg.tar.gz" \
    && mkdir -p /tmp/ffmpeg \
    && tar xzf /tmp/ffmpeg.tar.gz -C /tmp/ffmpeg \
    && rm /tmp/ffmpeg.tar.gz

# Clonar Sunshine con submodulos y construir deshabilitando Vulkan Video e inyecciones de CUDA
RUN git clone --depth=1 --branch=v2026.516.143833 \
    https://github.com/LizardByte/Sunshine.git /tmp/sunshine \
    && cd /tmp/sunshine \
    && git submodule init \
    && git -c submodule.third-party/build-deps.update=none \
       submodule update --init --depth=1 --recursive \
    && cmake -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DSUNSHINE_BUILD_HOME=OFF \
        -DSUNSHINE_BUILD_DOCS=OFF \
        -DSUNSHINE_BUILD_TESTS=OFF \
        -DSUNSHINE_ENABLE_WAYLAND=ON \
        -DSUNSHINE_ENABLE_VULKAN=OFF \
        -DSUNSHINE_ENABLE_CUDA=OFF \
        -DCUDA_FAIL_ON_MISSING=OFF \
        -DFFMPEG_PREPARED_BINARIES=/tmp/ffmpeg/ffmpeg \
    && cmake --build build -j$(nproc) \
    && cmake --install build \
    && rm -rf /tmp/sunshine /tmp/ffmpeg

# ── Crear usuario steam (video, audio, input, render) ──
RUN useradd -m -G video,audio,input,render steam \
    && echo "steam ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ── ffmpeg (para preview MJPEG) ──
RUN apt-get update -qq && apt-get install -y -qq \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# ── Configuración de Xorg para display virtual (modo escritorio) ──
COPY config/xorg-dummy.conf /etc/X11/xorg.conf.d/00-dummy.conf

# ── Preview web ──
COPY docker/preview/server.py /app/preview/server.py
COPY docker/preview/index.html /app/preview/index.html

# ── Config Sunshine ──
COPY config/sunshine.conf /etc/sunshine.conf

# ── Entrypoint ──
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
