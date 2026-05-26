# GameBox — Dockerfile
# SteamOS en Docker con Fedora + Gamescope + Sunshine + Wayland
# GPU AMD con VA-API

FROM fedora:42

ENV TZ=UTC
ENV XDG_RUNTIME_DIR=/run/user/1000
ENV WLR_BACKENDS=headless
ENV WLR_RENDERER=gles2

# ── Sistema base ──
RUN dnf install -y \
    curl ca-certificates gnupg sudo nano htop procps-ng python3 \
    && dnf clean all

# ── RPM Fusion (ffmpeg, steam, VA-API) ──
RUN dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm \
    && dnf clean all

# ── Mesa / VA-API / Vulkan ──
RUN dnf install -y \
    mesa-va-drivers mesa-va-drivers-freeworld mesa-vulkan-drivers mesa-dri-drivers \
    libva libva-utils vainfo vulkan-tools \
    && dnf clean all

# ── Wayland + Compositor ──
RUN dnf install -y \
    labwc gamescope \
    wayland-devel wayland-protocols-devel \
    xdg-desktop-portal-wlr \
    && dnf clean all

# ── PipeWire ──
RUN dnf install -y \
    pipewire pipewire-pulseaudio pipewire-utils wireplumber \
    && dnf clean all

# ── Steam ──
RUN dnf install -y steam && dnf clean all

# ── Dependencias de compilación de Sunshine ──
RUN dnf install -y \
    gcc gcc-c++ make cmake git \
    boost-devel pulseaudio-libs-devel opus-devel libevdev-devel \
    xorg-x11-server-Xwayland \
    libX11-devel libxcb-devel libXfixes-devel libXrandr-devel \
    mesa-libgbm-devel libcurl-devel openssl-devel miniupnpc-devel \
    libva-devel libdrm-devel nlohmann-json-devel libcap-devel \
    pipewire-devel libnotify-devel libappindicator-gtk3-devel \
    numactl-devel libstdc++-static \
    graphviz doxygen \
    && dnf clean all

# ── Node.js (para UI de Sunshine) ──
RUN dnf install -y nodejs && dnf clean all

# ── FFmpeg pre-compilado (build-deps de Sunshine) ──
RUN curl -sqL -o /tmp/ffmpeg.tar.gz \
    "https://github.com/LizardByte/build-deps/releases/download/v2026.516.30821/Linux-x86_64-ffmpeg.tar.gz" \
    && mkdir -p /tmp/ffmpeg \
    && tar xzf /tmp/ffmpeg.tar.gz -C /tmp/ffmpeg \
    && rm /tmp/ffmpeg.tar.gz

# ── Compilar Sunshine ──
RUN git clone --depth=1 --branch=v2026.516.143833 \
    https://github.com/LizardByte/Sunshine.git /tmp/sunshine \
    && cd /tmp/sunshine \
    && git submodule init \
    && git -c submodule.third-party/build-deps.update=none \
       submodule update --init --depth=1 --recursive \
    && sed -i 's/lifetime::debug_trap();/BOOST_LOG(fatal) << "[GameBox] Session cleanup timeout - continuing";/' src/stream.cpp \
    && sed -i 's/boost::asio::ssl::verify_peer | boost::asio::ssl::verify_fail_if_no_peer_cert | boost::asio::ssl::verify_client_once/boost::asio::ssl::verify_peer | boost::asio::ssl::verify_client_once/' src/nvhttp.cpp \
    && sed -i 's/<< "unknown -- denied"sv;/<< "unknown -- continuing without client cert"sv;/' src/nvhttp.cpp \
    && sed -i '/continuing without client cert/{n;s/return 0;/return 1;/}' src/nvhttp.cpp \
    && sed -i 's|auto ptr = map_id_sess.emplace(sess.client.uniqueID, std::move(sess)).first;|map_id_sess.erase(sess.client.uniqueID);\n        auto ptr = map_id_sess.emplace(sess.client.uniqueID, std::move(sess)).first;|' src/nvhttp.cpp \
    && python3 -c "content = open('src/nvhttp.cpp').read(); content = content.replace('    auto &sess = std::begin(map_id_sess)->second;\n    getservercert(sess, tree, pin);\n    sess.client.name = name;\n\n    // response to the request for pin\n    std::ostringstream data;\n    pt::write_xml(data, tree);\n\n    auto &async_response = sess.async_insert_pin.response;\n    if (async_response.has_left() && async_response.left()) {\n      async_response.left()->write(data.str());\n    } else if (async_response.has_right() && async_response.right()) {\n      async_response.right()->write(data.str());\n    } else {\n      return false;\n    }\n\n    // reset async_response\n    async_response = std::decay_t<decltype(async_response.left())>();\n    // response to the current request\n    return true;', '    auto sess_it = std::begin(map_id_sess);\n    auto unique_id = sess_it->first;\n\n    // Reset last_phase to allow retries if getservercert was already called\n    sess_it->second.last_phase = PAIR_PHASE::NONE;\n\n    // Move async_response out before getservercert to avoid dangling ref\n    auto async_response = std::move(sess_it->second.async_insert_pin.response);\n\n    getservercert(sess_it->second, tree, pin);\n\n    // Session may have been removed by fail_pair -> remove_session\n    auto it = map_id_sess.find(unique_id);\n    if (it != map_id_sess.end()) {\n      it->second.client.name = name;\n    }\n\n    // response to the request for pin\n    std::ostringstream data;\n    pt::write_xml(data, tree);\n\n    if (async_response.has_left() && async_response.left()) {\n      async_response.left()->write(data.str());\n    } else if (async_response.has_right() && async_response.right()) {\n      async_response.right()->write(data.str());\n    } else {\n      return false;\n    }\n\n    // response to the current request\n    return true;'); open('src/nvhttp.cpp', 'w').write(content)" \
    && sed -i '/add_subdirectory(third-party\/doxyconfig docs)/d' cmake/targets/common.cmake \
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

# ── Crear usuario steam ──
RUN useradd -m -G video,audio,input,render,kvm steam \
    && echo "steam ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ── labwc config ──
COPY config/labwc/rc.xml /etc/labwc/rc.xml
COPY config/labwc/environment /etc/labwc/environment

# ── Config Sunshine ──
COPY config/sunshine.conf /etc/sunshine.conf

# ── Steam wrapper ──
COPY docker/steam-wrapper.sh /usr/local/bin/steam-wrapper.sh
RUN chmod +x /usr/local/bin/steam-wrapper.sh

# ── Entrypoint ──
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
