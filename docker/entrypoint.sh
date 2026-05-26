#!/usr/bin/env bash
set -euo pipefail

export INSTANCE_NAME="${INSTANCE_NAME:-gamebox}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
export PULSE_SERVER="${PULSE_SERVER:-unix:${XDG_RUNTIME_DIR}/pulse/native}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

run_as_steam() {
    su - steam -c "
        export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}
        export DBUS_SESSION_BUS_ADDRESS=\${DBUS_SESSION_BUS_ADDRESS:-${DBUS_SESSION_BUS_ADDRESS}}
        export PULSE_SERVER=${PULSE_SERVER}
        export WAYLAND_DISPLAY=${WAYLAND_DISPLAY}
        export XDG_SESSION_TYPE=wayland
        $1
    " 2>&1
}

wait_for_wayland() {
    local socket="${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"
    local i
    for i in $(seq 1 20); do
        [ -e "$socket" ] && return 0
        sleep 0.5
    done
    return 1
}

# ── 1. Permisos ──
chmod 666 /dev/dri/card* /dev/uinput 2>/dev/null || true
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"
chown -R steam:steam /home/steam "${XDG_RUNTIME_DIR}"

# ── 2. D-Bus ──
mkdir -p /run/dbus
dbus-daemon --system --fork 2>&1 || echo "[FAIL] D-Bus system"

export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
run_as_steam "dbus-daemon --session --address=${DBUS_SESSION_BUS_ADDRESS} --fork --nopidfile &>/tmp/dbus-session.log" \
    || echo "[FAIL] D-Bus session — /tmp/dbus-session.log"

# ── 3. labwc (Wayland compositor headless) ──
labwc -c /etc/labwc/rc.xml &>/tmp/labwc.log &
if wait_for_wayland; then
    echo "[OK] labwc en ${WAYLAND_DISPLAY}"
    # libwayland-client rechaza conexiones si el socket es de otro usuario
    chown steam:steam "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}.lock" 2>/dev/null || true
    # Gamescope XWayland necesita crear sockets en /tmp/.X11-unix
    chown steam:steam /tmp/.X11-unix 2>/dev/null || true
else
    echo "[FAIL] labwc — /tmp/labwc.log"
fi

# ── 4. PipeWire ──
run_as_steam "
    pipewire &>/tmp/pipewire.log &
    pipewire-pulse &>/tmp/pipewire-pulse.log &
    wireplumber &>/tmp/wireplumber.log &
" || echo "[FAIL] PipeWire — /tmp/pipewire.log"

wait_for_process() {
    local i
    for i in $(seq 1 "${2:-10}"); do
        pgrep -x "$1" &>/dev/null && return 0
        sleep 0.5
    done
    return 1
}
wait_for_process pipewire 5 || true

# ── 5. Steam (Game Mode dentro de Gamescope) ──
run_as_steam "
    gamescope --backend wayland -W 1920 -H 1080 -r 60 -- steam -steamos3 -gamepadui -pipewire &>/tmp/steam.log &
" || echo "[FAIL] Steam — /tmp/steam.log"

# ── 6. Null sink ──
run_as_steam "
    pactl info &>/dev/null \
        && pactl load-module module-null-sink sink_name=sunshine-stereo format=s16le channels=2 rate=48000 &>/tmp/pulse-null-sink.log
" || echo "[FAIL] PulseAudio null sink — /tmp/pulse-null-sink.log"

# ── 7. Config Sunshine ──
mkdir -p /home/steam/.config/sunshine
cp /etc/sunshine.conf /home/steam/.config/sunshine/sunshine.conf 2>/dev/null || true

SUNSHINE_APPS_JSON='{
  "env": { "WAYLAND_DISPLAY": "wayland-0" },
  "apps": [
    {
      "name": "GameBox (Steam Deck)",
      "cmd": "steam-wrapper.sh",
      "working-directory": "/home/steam/.local/share/Steam"
    }
  ]
}'

echo "${SUNSHINE_APPS_JSON}" > /home/steam/.config/sunshine/apps.json
echo "${SUNSHINE_APPS_JSON}" > /usr/local/assets/apps.json
chown -R steam:steam /home/steam/.config

HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")
if [ -n "$HOST_IP" ]; then
    sed -i '/csrf_allowed_origins/d' /home/steam/.config/sunshine/sunshine.conf
    echo "csrf_allowed_origins = https://${HOST_IP}" >> /home/steam/.config/sunshine/sunshine.conf
fi

# ── 8. Sunshine ──
run_as_steam "
    sunshine /home/steam/.config/sunshine/sunshine.conf &>/tmp/sunshine.log &
" || echo "[FAIL] Sunshine — /tmp/sunshine.log"

# ── 9. Status ──
HOST_IP="${HOST_IP:-$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost')}"
echo ""
echo "============================================"
echo "  GameBox listo!"
echo "  Instancia:   ${INSTANCE_NAME}"
echo "  Sunshine:    http://${HOST_IP}:47990"
echo "============================================"
echo "  1. Abre Sunshine UI y configura tu PIN"
echo "  2. Conecta Moonlight a ${HOST_IP}"
echo "  3. Juega!"
echo "============================================"

exec tail -f /tmp/sunshine.log
