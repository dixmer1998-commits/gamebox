#!/usr/bin/env bash
set -euo pipefail

GAMEBOX_VERSION="1.0.0"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# ── CLI args ──
while [[ $# -gt 0 ]]; do
    case "$1" in
        --name) INSTANCE_NAME="$2"; shift 2 ;;
        --ram)  RAM_GB="$2"; shift 2 ;;
        --cpus) CPU_CORES="$2"; shift 2 ;;
        --disk) DISK_GB="$2"; shift 2 ;;
        --swap) SWAP_GB="$2"; shift 2 ;;
        --ip)   IP_ADDR="$2"; shift 2 ;;
        --help) echo "Uso: $0 [--name NOMBRE] [--ram GB] [--cpus N] [--disk GB] [--swap GB] [--ip IP]"; exit 0 ;;
        *) echo -e "${RED}Argumento desconocido: $1${NC}"; exit 1 ;;
    esac
done

# ── Root check ──
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] Este script debe ejecutarse como root en el host Proxmox.${NC}"
    exit 1
fi

if ! command -v pct &>/dev/null; then
    echo -e "${RED}[ERROR] pct no encontrado. ¿Es esto Proxmox?${NC}"
    exit 1
fi

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  GameBox v${GAMEBOX_VERSION} — Crear LXC Proxmox${NC}"
echo -e "${CYAN}============================================${NC}"

# ── Nombre de instancia ──
if [[ -z "${INSTANCE_NAME:-}" ]]; then
    echo ""
    echo -e "${YELLOW}Nombre único para la instancia:${NC}"
    while true; do
        read -r -p "> Nombre: " INSTANCE_NAME
        INSTANCE_NAME="${INSTANCE_NAME,,}" && INSTANCE_NAME="${INSTANCE_NAME// /-}"
        INSTANCE_NAME="${INSTANCE_NAME//[^a-z0-9-]/}"
        if [[ ${#INSTANCE_NAME} -lt 2 ]]; then
            echo -e "${RED}Mínimo 2 caracteres.${NC}"; continue
        fi
        EXISTING_CT=$(pct list 2>/dev/null | awk -v n="gamebox-${INSTANCE_NAME}" '$2 == n {print $1}')
        if [[ -n "$EXISTING_CT" ]]; then
            echo -e "${RED}Ya existe gamebox-${INSTANCE_NAME} (LXC $EXISTING_CT).${NC}"; continue
        fi
        break
    done
fi

LXCID="$(pvesh get /cluster/nextid 2>/dev/null)"
HOSTNAME="gamebox-${INSTANCE_NAME}"
echo -e "${GREEN}[OK]${NC} ${CYAN}${HOSTNAME}${NC} (ID: ${LXCID})"

# ── Recursos ──
RAM_GB="${RAM_GB:-4}"
CPU_CORES="${CPU_CORES:-4}"
DISK_GB="${DISK_GB:-32}"
SWAP_GB="${SWAP_GB:-2}"

if [[ -z "${IP_ADDR:-}" ]]; then
    echo ""
    echo -e "${YELLOW}Configuración de red:${NC}"
    read -r -p "> IP fija o DHCP [vacío]: " IP_ADDR
    if [[ -z "$IP_ADDR" ]]; then
        NET_CONFIG="dhcp"
    elif [[ "$IP_ADDR" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        NET_CONFIG="static"
        GATEWAY=$(echo "$IP_ADDR" | sed 's/\.[0-9]*$/.1/')
        read -r -p "> Gateway [$GATEWAY]: " GW_INPUT
        GATEWAY="${GW_INPUT:-$GATEWAY}"
    else
        echo -e "${RED}IP no válida. Usando DHCP.${NC}"
        NET_CONFIG="dhcp"
        IP_ADDR=""
    fi
fi

echo ""
echo -e "${CYAN}Resumen:${NC}"
echo -e "  Nombre: ${CYAN}${HOSTNAME}${NC}  RAM: ${RAM_GB}GB  CPUs: ${CPU_CORES}  Disco: ${DISK_GB}GB  Swap: ${SWAP_GB}GB"
echo -e "  Red: ${NET_CONFIG}${IP_ADDR:+ (${IP_ADDR})}"

read -r -p "> ¿Crear? (s/N): " CONFIRM
if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
    echo -e "${YELLOW}Cancelado.${NC}"; exit 0
fi

# ── Template Debian ──
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
TEMPLATE_PATH="/var/lib/vz/template/cache/${TEMPLATE}"
if [[ ! -f "$TEMPLATE_PATH" ]]; then
    echo -e "${YELLOW}[1/4] Descargando template Debian 12...${NC}"
    pveam update 2>/dev/null || true
    pveam download local "$TEMPLATE" 2>/dev/null || { echo -e "${RED}[ERROR] No se pudo descargar.${NC}"; exit 1; }
else
    echo -e "${GREEN}[1/4]${NC} Template ya existe."
fi

# ── Crear LXC ──
echo -e "${YELLOW}[2/4] Creando LXC...${NC}"
pct create "${LXCID}" "${TEMPLATE_PATH}" \
    --arch amd64 --hostname "${HOSTNAME}" \
    --cores "${CPU_CORES}" --memory $((RAM_GB * 1024)) --swap $((SWAP_GB * 1024)) \
    --storage local-lvm --rootfs "local-lvm:${DISK_GB}" \
    --net0 name=eth0,bridge=vmbr0,firewall=1${IP_ADDR:+,ip=${IP_ADDR}/24,gw=${GATEWAY}} \
    --unprivileged 0 --features "nesting=1" --onboot 1 --start 1 \
    --ssh-public-keys ~/.ssh/id_rsa.pub 2>/dev/null || true

# ── Config LXC ──
echo -e "${GREEN}[OK]${NC} Aplicando configuraciones de GPU..."
cat >> "/etc/pve/lxc/${LXCID}.conf" << EOF

# --- GameBox GPU + Periféricos ---
lxc.apparmor.profile: unconfined
lxc.cgroup2.devices.allow: c 10:223 rwm
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 13:* rwm
lxc.mount.auto: proc sys
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
lxc.mount.entry: /dev/uinput dev/uinput none bind,optional,create=file
lxc.mount.entry: /dev/input dev/input none bind,optional,create=dir
EOF

pct reboot "${LXCID}" 2>/dev/null || true

# ── Esperar arranque ──
echo -e "${YELLOW}[3/4] Esperando reinicio...${NC}"
for i in {1..30}; do
    pct status "${LXCID}" 2>/dev/null | grep -q "running" && break
    sleep 2
done
echo -e "${GREEN}[OK]${NC} LXC en ejecución."

# ── Copiar GameBox ──
echo -e "${YELLOW}[4/4] Copiando GameBox al LXC...${NC}"
PROJECT_ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tar --exclude='.git' --exclude='node_modules' -czf "/tmp/gamebox-${LXCID}.tar.gz" -C "${PROJECT_ROOT}" .
pct push "${LXCID}" "/tmp/gamebox-${LXCID}.tar.gz" /root/gamebox.tar.gz
pct exec "${LXCID}" -- mkdir -p /root/gamebox
pct exec "${LXCID}" -- tar -xzf /root/gamebox.tar.gz -C /root/gamebox/
pct exec "${LXCID}" -- rm -f /root/gamebox.tar.gz
rm -f "/tmp/gamebox-${LXCID}.tar.gz"

pct exec "${LXCID}" -- bash -c "echo 'GAMEBOX_INSTANCE=${INSTANCE_NAME}' > /etc/gamebox-instance"
pct exec "${LXCID}" -- bash -c "echo 'GAMEBOX_HOSTNAME=${HOSTNAME}' >> /etc/gamebox-instance"

# ── Fin ──
LXC_IP=$(pct exec "${LXCID}" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "$IP_ADDR")
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Instancia creada${NC}"
echo -e "${CYAN}============================================${NC}"
echo -e "  Nombre: ${CYAN}${HOSTNAME}${NC}  ID: ${LXCID}  IP: ${CYAN}${LXC_IP:-?}${NC}"
echo ""
echo -e "  ${YELLOW}Siguiente:${NC}"
echo -e "    pct exec ${LXCID} -- /root/gamebox/lxc/bootstrap.sh"
echo -e "${CYAN}============================================${NC}"
