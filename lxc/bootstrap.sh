#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────
# GameBox — bootstrap.sh (Refactorizado para Opción 1)
# Se ejecuta DENTRO del LXC.
#   - Instala Docker
#   - Levanta el stack usando el Dockerfile real y docker compose
# ──────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  GameBox — Bootstrap LXC Proxmox${NC}"
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
echo -e "${YELLOW}[PASO 1/4] Verificando GPU AMD...${NC}"
if ls /dev/dri/render* &>/dev/null; then
    echo -e "${GREEN}[OK]${NC} GPU AMD detectada:"
    ls -la /dev/dri/render*
else
    echo -e "${RED}[ERROR] /dev/dri no disponible.${NC}"
    echo -e "Asegúrate de que el LXC tenga bind mount de /dev/dri."
    exit 1
fi

# ── Verificar uinput ──
echo ""
echo -e "${YELLOW}[PASO 2/4] Verificando /dev/uinput...${NC}"
if [[ -c /dev/uinput ]]; then
    echo -e "${GREEN}[OK]${NC} /dev/uinput disponible."
else
    echo -e "${RED}[ERROR] /dev/uinput no encontrado. Deteniendo instalación.${NC}"
    echo -e "Verifica la configuración del LXC en el host Proxmox."
    exit 1
fi

# ── Instalar Docker ──
echo ""
echo -e "${YELLOW}[PASO 3/4] Instalando Docker en el LXC...${NC}"
if command -v docker &>/dev/null; then
    echo -e "${GREEN}[OK]${NC} Docker ya está instalado: $(docker --version)"
else
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    echo -e "${GREEN}[OK]${NC} Docker instalado: $(docker --version)"
fi

# ── Construir y Levantar con Docker Compose (Fix Bug Fatal 2) ──
echo ""
echo -e "${YELLOW}[PASO 4/4] Levantando GameBox mediante Docker Compose...${NC}"

cd /root/gamebox

export GAMEBOX_INSTANCE="${GAMEBOX_INSTANCE}"
docker compose down || true

# Construir y levantar el contenedor usando los archivos de producción reales
docker compose up --build -d

echo -e "${GREEN}[OK]${NC} Contenedor 'gamebox-${GAMEBOX_INSTANCE}' en ejecución."

# ── Información final ──
HOST_IP=$(hostname -I | awk '{print $1}' || echo "localhost")
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  GameBox listo en tu LXC!${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo -e "  Instancia:   ${CYAN}${GAMEBOX_INSTANCE}${NC}"
echo -e "  Contenedor:  ${CYAN}gamebox-${GAMEBOX_INSTANCE}${NC}"
echo ""
echo -e "  ${YELLOW}Sunshine Web UI:${NC}"
echo -e "    ${CYAN}http://${HOST_IP}:47990${NC}"
echo ""
echo -e "  ${YELLOW}Preview Web (Vista previa en vivo):${NC}"
echo -e "    ${CYAN}http://${HOST_IP}:48090${NC}"
echo ""
echo -e "  ${YELLOW}Moonlight:${NC}"
echo -e "    Añade servidor: ${CYAN}${HOST_IP}${NC}"
echo ""
echo -e "  ${YELLOW}Depuración:${NC}"
echo -e "    docker logs -f gamebox-${GAMEBOX_INSTANCE}"
echo ""
echo -e "${CYAN}============================================${NC}"
