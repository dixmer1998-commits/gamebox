#!/bin/bash
# GameBox — Steam Wrapper para Sunshine
# Mantiene un proceso vivo mientras Steam/Gamescope corra.
# Previene auto_detach de Sunshine.

while true; do
    if ! pgrep -x gamescope >/dev/null 2>&1 && ! pgrep -x steam >/dev/null 2>&1; then
        echo "[steam-wrapper] Gamescope/Steam ya no está corriendo. Saliendo..."
        exit 1
    fi
    sleep 10
done
