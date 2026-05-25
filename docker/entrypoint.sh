#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────
# GameBox — entrypoint.sh
# Arranca los servicios del contenedor GameBox:
#   - PipeWire + WirePlumber (captura de video/audio)
#   - dbus (necesario para PipeWire/KDE)
#   - Sunshine (streaming server)
#   - Gamescope + Steam (Modo Juego)
# ──────────────────────────────────────────────────────────

echo "============================================"
echo "  GameBox — Iniciando servicios"
echo "  Instancia: ${INSTANCE_NAME:-gamebox}"
echo "============================================"

export INSTANCE_NAME="${INSTANCE_NAME:-gamebox}"
export TZ="${TZ:-UTC}"
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
export PULSE_SERVER="${PULSE_SERVER:-unix:${XDG_RUNTIME_DIR}/pulse/native}"

# ── Crear directorios runtime ──
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"
chown steam:steam "${XDG_RUNTIME_DIR}"

# ── dbus ──
echo "[OK] Iniciando dbus..."
mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true

# ── PipeWire ──
echo "[OK] Iniciando PipeWire..."
su - steam -c "
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}
    pipewire &>/dev/null &
    pipewire-pulse &>/dev/null &
    wireplumber &>/dev/null &
" 2>/dev/null || true
sleep 2

# ── Crear directorio de configuración de Sunshine ──
mkdir -p /home/steam/.config/sunshine
if [[ ! -f /home/steam/.config/sunshine/sunshine.conf ]]; then
    cp /etc/sunshine.conf /home/steam/.config/sunshine/sunshine.conf 2>/dev/null || true
fi
chown -R steam:steam /home/steam/.config

# ── Sunshine ──
echo "[OK] Iniciando Sunshine..."
su - steam -c "
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}
    sunshine --config /home/steam/.config/sunshine/sunshine.conf &>/tmp/sunshine.log &
" 2>/dev/null || true
sleep 2

# ── Configurar apps de Sunshine ──
# Esto permite que Moonlight muestre "Game Mode" y "Desktop"
SUNSHINE_APPS="/home/steam/.config/sunshine/apps.json"
if [[ ! -f "${SUNSHINE_APPS}" ]]; then
    cat > "${SUNSHINE_APPS}" << EOF
{
  "apps": [
    {
      "name": "🎮 Modo Juego",
      "cmd": "sudo -u steam gamescope --headless --steam -- steam -steamos -pipewire -fulldesktopres -gamepadui",
      "exclude-display": true,
      "output-name": "gamescope-output"
    },
    {
      "name": "🖥️ Modo Escritorio",
      "cmd": "startplasma-x11 &",
      "exclude-display": false
    }
  ]
}
EOF
    chown steam:steam "${SUNSHINE_APPS}"
fi

# ── Mostrar estado ──
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "N/A")
echo ""
echo "============================================"
echo "  GameBox listo!"
echo "  Instancia: ${INSTANCE_NAME}"
echo "  Sunshine:  http://${HOST_IP}:47990"
echo "============================================"
echo ""
echo "  Conecta Moonlight a: ${HOST_IP}"
echo "  Apps disponibles: Modo Juego, Modo Escritorio"
echo ""

# ── Mantener el contenedor vivo ──
# Si solo queremos el modo juego, arrancamos gamescope+steam directamente
if [[ "${AUTO_STEAM:-true}" == "true" ]]; then
    echo "[OK] Arrancando Gamescope + Steam..."
    exec sudo -u steam gamescope \
        --headless \
        --steam \
        -- \
        steam \
        -steamos \
        -pipewire \
        -fulldesktopres \
        -gamepadui
fi

# Fallback: mantener vivo
tail -f /dev/null
