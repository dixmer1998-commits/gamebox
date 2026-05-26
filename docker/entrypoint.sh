#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────
# GameBox — entrypoint.sh (Refactorizado para Docker Autónomo)
# Arranca los servicios en segundo plano:
#   - dbus (esencial para PipeWire/Steam/KDE)
#   - Xorg Dummy (display virtual para KDE)
#   - PipeWire + WirePlumber (captura audio/video Wayland)
#   - Sunshine (servidor de streaming con VA-API AMD)
#   - Servidor de Preview MJPEG (Python3 + FFmpeg)
# ──────────────────────────────────────────────────────────

echo "============================================"
echo "  GameBox — Iniciando Servicios Autónomos"
echo "  Instancia: ${INSTANCE_NAME:-gamebox}"
echo "============================================"

export INSTANCE_NAME="${INSTANCE_NAME:-gamebox}"
export TZ="${TZ:-UTC}"
export DISPLAY="${DISPLAY:-:10}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
export PULSE_SERVER="${PULSE_SERVER:-unix:${XDG_RUNTIME_DIR}/pulse/native}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"

# ── 1. Asegurar permisos de /home/steam y directorios de runtime ──
echo "[OK] Configurando permisos de usuario y volumen..."

# Fix device permissions: los GIDs de grupos del host (video=983, kvm=992, etc.)
# no coinciden con los del contenedor al usar bind mounts con network_mode: host
chmod 666 /dev/dri/card* 2>/dev/null || true
chmod 666 /dev/uinput 2>/dev/null || true

chown -R steam:steam /home/steam || true

mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"
chown -R steam:steam "${XDG_RUNTIME_DIR}"

# ── 2. Iniciar D-Bus (Sistema y Sesión) ──
echo "[OK] Iniciando D-Bus daemon..."
mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true

# Crear D-Bus de sesión para el usuario steam
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
su - steam -c "dbus-daemon --session --address=${DBUS_SESSION_BUS_ADDRESS} --fork --nopidfile &>/dev/null" || true

# ── 3. Iniciar Xorg Dummy (Display Virtual para KDE) ──
echo "[OK] Iniciando display virtual Xorg Dummy (${DISPLAY})..."
pkill -9 X 2>/dev/null || true
rm -f /tmp/.X*-lock /tmp/.X11-unix/X* 2>/dev/null || true
X "${DISPLAY}" -config /etc/X11/xorg.conf.d/00-dummy.conf &>/tmp/xorg.log &
sleep 2

# ── 4. Iniciar KDE Plasma en modo escritorio ──
echo "[OK] Iniciando KDE Plasma en ${DISPLAY}..."
su - steam -c "
    export DISPLAY=${DISPLAY}
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}
    export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS}
    startplasma-x11 &>/tmp/plasma.log &
" 2>/dev/null || true
sleep 3

# ── 5. Iniciar PipeWire y WirePlumber (Captura) ──
echo "[OK] Iniciando PipeWire y WirePlumber..."
su - steam -c "
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}
    export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS}
    pipewire &>/dev/null &
    pipewire-pulse &>/dev/null &
    wireplumber &>/dev/null &
" 2>/dev/null || true
sleep 2

# ── 6. Iniciar Gamescope Headless (Modo Juego permanente) ──
# Crea un compositor virtual para la preview web y para Sunshine.
echo "[OK] Iniciando Gamescope..."
GAMESCOPE_WIDTH="${GAMESCOPE_WIDTH:-1920}"
GAMESCOPE_HEIGHT="${GAMESCOPE_HEIGHT:-1080}"
su - steam -c "
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}
    export DISPLAY=${DISPLAY}
    if [[ \"${AUTO_STEAM:-false}\" == \"true\" ]]; then
        gamescope --backend headless --steam -- \
            steam -steamos -pipewire -fulldesktopres -gamepadui \
            &>/tmp/gamescope.log &
    else
        gamescope --backend headless \
            -W ${GAMESCOPE_WIDTH} -H ${GAMESCOPE_HEIGHT} -r 60 \
            &>/tmp/gamescope.log &
    fi
" 2>/dev/null || true
sleep 2

# ── 7. Preparar configuración de Sunshine ──
echo "[OK] Preparando configuración de Sunshine..."
mkdir -p /home/steam/.config/sunshine
if [[ ! -f /home/steam/.config/sunshine/sunshine.conf ]]; then
    cp /etc/sunshine.conf /home/steam/.config/sunshine/sunshine.conf 2>/dev/null || true
fi
chown -R steam:steam /home/steam/.config

# Configurar aplicaciones en Sunshine (Modo Juego con Steam Nativo y Modo Escritorio con KDE)
SUNSHINE_APPS="/home/steam/.config/sunshine/apps.json"
if [[ ! -f "${SUNSHINE_APPS}" ]]; then
    cat > "${SUNSHINE_APPS}" << EOF
{
  "apps": [
    {
      "name": "🎮 Modo Juego (Steam)",
      "cmd": "gamescope --backend headless --steam -- steam -steamos -pipewire -fulldesktopres -gamepadui",
      "exclude-display": true,
      "output-name": "gamescope"
    },
    {
      "name": "🖥️ Modo Escritorio (KDE)",
      "cmd": "startplasma-x11 &",
      "exclude-display": false
    }
  ]
}
EOF
    chown steam:steam "${SUNSHINE_APPS}"
fi

# ── 8. Iniciar Sunshine ──
echo "[OK] Iniciando Sunshine Server..."
su - steam -c "
    export DISPLAY=${DISPLAY}
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}
    export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS}
    export QT_QPA_PLATFORM=offscreen
    sunshine /home/steam/.config/sunshine/sunshine.conf &>/tmp/sunshine.log &
" 2>/dev/null || true
sleep 2

# ── 9. Iniciar Servidor de Vista Previa (MJPEG) ──
echo "[OK] Iniciando Preview Server (puerto 48090)..."
PREVIEW_PORT="${PREVIEW_PORT:-48090}"
nohup python3 /app/preview/server.py &>/tmp/preview-server.log &
sleep 1

# ── 10. Mostrar Resumen de Estado ──
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
echo ""
echo "=================================================="
echo "  🚀 ¡GameBox está listo para jugar!"
echo "=================================================="
echo "  Instancia:   ${INSTANCE_NAME}"
echo "  Sunshine UI:  http://${HOST_IP}:47990"
echo "  Preview Web:  http://${HOST_IP}:${PREVIEW_PORT}"
echo "=================================================="
echo "  Instrucciones rápidas:"
echo "  1. Entra a Sunshine UI (47990) y configura tu PIN."
echo "  2. Abre Moonlight en tu cliente y añade la IP: ${HOST_IP}"
echo "  3. Selecciona 'Modo Juego' para Steam o 'Modo Escritorio'."
echo "=================================================="
echo ""

# ── 11. Lanzamiento Automático (Opcional) ──
echo "[OK] AUTO_STEAM=${AUTO_STEAM:-false} — Gamescope ya se inició en el paso 6."

# Mantener vivo el contenedor inspeccionando los logs de Sunshine
echo "[OK] Contenedor activo. Monitoreando Sunshine..."
exec tail -f /tmp/sunshine.log
