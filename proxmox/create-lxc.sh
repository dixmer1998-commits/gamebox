#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────
# GameBox — create-lxc.sh
# Crea un LXC privilegiado en Proxmox con:
#   - GPU AMD bindeada (/dev/dri)
#   - /dev/uinput para dispositivos virtuales
#   - /dev/input/* para input
#   - Docker pre-instalado
#   - Nombre de instancia único (elegido por el usuario)
# ──────────────────────────────────────────────────────────

GAMEBOX_VERSION="1.0.0"

# ── Colores ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  GameBox v${GAMEBOX_VERSION} — Crear Instancia${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# ── Root check ──
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] Este script debe ejecutarse como root en el host Proxmox.${NC}"
    exit 1
fi

# ── Verificar que es Proxmox ──
if ! command -v pct &>/dev/null; then
    echo -e "${RED}[ERROR] Esto no parece ser un host Proxmox (pct no encontrado).${NC}"
    exit 1
fi

# ── Pedir nombre de instancia ──
echo -e "${YELLOW}Cada instancia GameBox necesita un nombre único.${NC}"
echo -e "Este nombre se usará para identificar el LXC, el contenedor Docker"
echo -e "y la instancia en Moonlight."
echo ""
echo -e "Ejemplos: ${CYAN}steamos${NC}, ${CYAN}arcade${NC}, ${CYAN}retro${NC}, ${CYAN}juegos${NC}, ${CYAN}gamebox${NC}"
echo ""

while true; do
    read -r -p "> Nombre de esta instancia: " INSTANCE_NAME
    INSTANCE_NAME="${INSTANCE_NAME,,}"         # minúsculas
    INSTANCE_NAME="${INSTANCE_NAME// /-}"      # espacios → guiones
    INSTANCE_NAME="${INSTANCE_NAME//[^a-z0-9-]/}" # solo alfanumérico + guiones
    if [[ -z "$INSTANCE_NAME" ]]; then
        echo -e "${RED}El nombre no puede estar vacío.${NC}"
        continue
    fi
    if [[ ${#INSTANCE_NAME} -lt 2 ]]; then
        echo -e "${RED}El nombre debe tener al menos 2 caracteres.${NC}"
        continue
    fi
    # Verificar que no exista ya
    EXISTING_CT=$(pct list 2>/dev/null | awk -v name="gamebox-${INSTANCE_NAME}" '$2 == name {print $1}')
    if [[ -n "$EXISTING_CT" ]]; then
        echo -e "${RED}Ya existe un LXC llamado 'gamebox-${INSTANCE_NAME}' (ID: ${EXISTING_CT}).${NC}"
        echo -e "${RED}Elige otro nombre o elimina el existente.${NC}"
        continue
    fi
    break
done

LXCID="$(pvesh get /cluster/nextid 2>/dev/null)"
HOSTNAME="gamebox-${INSTANCE_NAME}"
echo ""
echo -e "${GREEN}[OK]${NC} Instancia: ${CYAN}${HOSTNAME}${NC} (ID LXC: ${LXCID})"

# ── Parámetros configurables ──
echo ""
echo -e "${YELLOW}Configuración de recursos:${NC}"
echo -e "  (deja en blanco para usar el valor por defecto)"
echo ""

read -r -p "> RAM en GB [4]: " RAM_GB
RAM_GB="${RAM_GB:-4}"
RAM_MB=$((RAM_GB * 1024))

read -r -p "> CPUs [4]: " CPU_CORES
CPU_CORES="${CPU_CORES:-4}"

read -r -p "> Disco en GB [32]: " DISK_GB
DISK_GB="${DISK_GB:-32}"

read -r -p "> Swap en GB [2]: " SWAP_GB
SWAP_GB="${SWAP_GB:-2}"
SWAP_MB=$((SWAP_GB * 1024))

# ── Red: preguntar IP o DHCP ──
echo ""
echo -e "${YELLOW}Configuración de red:${NC}"
echo -e "  Puedes asignar una IP fija o usar DHCP."
echo ""
while true; do
    read -r -p "> IP fija (ej: 192.168.1.100) o DHCP [dejar vacío]: " IP_ADDR
    if [[ -z "$IP_ADDR" ]]; then
        NET_CONFIG="dhcp"
        echo -e "${GREEN}[OK]${NC} Usando DHCP"
        break
    fi
    if [[ "$IP_ADDR" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        NET_CONFIG="static"
        # Extraer gateway de la IP
        GATEWAY=$(echo "$IP_ADDR" | sed 's/\.[0-9]*$/.1/')
        read -r -p "> Gateway [$GATEWAY]: " GW_INPUT
        GATEWAY="${GW_INPUT:-$GATEWAY}"
        echo -e "${GREEN}[OK]${NC} IP: ${IP_ADDR} / Gateway: ${GATEWAY}"
        break
    else
        echo -e "${RED}IP no válida. Formato: 192.168.1.100${NC}"
    fi
done

# ── Resumen ──
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Resumen de la instancia${NC}"
echo -e "${CYAN}============================================${NC}"
echo -e "  Nombre:        ${CYAN}${HOSTNAME}${NC}"
echo -e "  ID LXC:        ${LXCID}"
echo -e "  RAM:           ${RAM_GB} GB"
echo -e "  CPUs:          ${CPU_CORES}"
echo -e "  Disco:         ${DISK_GB} GB"
echo -e "  Swap:          ${SWAP_GB} GB"
echo -e "  Red:           ${NET_CONFIG}${IP_ADDR:+ (${IP_ADDR})}"
echo -e "${CYAN}============================================${NC}"
echo ""

read -r -p "> ¿Crear esta instancia? (s/N): " CONFIRM
if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" && "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "${YELLOW}Cancelado por el usuario.${NC}"
    exit 0
fi

# ── Descargar template Debian 12 si no existe ──
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
TEMPLATE_PATH="/var/lib/vz/template/cache/${TEMPLATE}"

if [[ ! -f "$TEMPLATE_PATH" ]]; then
    echo ""
    echo -e "${YELLOW}[PASO 1/4] Descargando template Debian 12...${NC}"
    pveam update 2>/dev/null || true
    pveam download local "$TEMPLATE" 2>/dev/null || {
        echo -e "${RED}[ERROR] No se pudo descargar el template.${NC}"
        echo -e "Prueba: pveam available | grep debian-12"
        exit 1
    }
    echo -e "${GREEN}[OK]${NC} Template descargado."
else
    echo ""
    echo -e "${GREEN}[PASO 1/4]${NC} Template ya existe, saltando."
fi

# ── Crear el LXC ──
echo ""
echo -e "${YELLOW}[PASO 2/4] Creando LXC...${NC}"

# Configuración temporal LXC
cat > /tmp/gamebox-${LXCID}.conf << EOF
arch: amd64
ostype: debian
hostname: ${HOSTNAME}
lxc.apparmor.profile: unconfined
lxc.cgroup2.devices.allow: c 10:223 rwm
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 13:* rwm
lxc.mount.auto: proc sys
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
lxc.mount.entry: /dev/uinput dev/uinput none bind,optional,create=file
lxc.mount.entry: /dev/input dev/input none bind,optional,create=dir
EOF

pct create "${LXCID}" "${TEMPLATE_PATH}" \
    --arch amd64 \
    --hostname "${HOSTNAME}" \
    --cores "${CPU_CORES}" \
    --memory "${RAM_MB}" \
    --swap "${SWAP_MB}" \
    --storage local-lvm \
    --rootfs "local-lvm:${DISK_GB}" \
    --net0 name=eth0,bridge=vmbr0,firewall=1${IP_ADDR:+,ip=${IP_ADDR}/24,gw=${GATEWAY}} \
    --unprivileged 0 \
    --features "nesting=1" \
    --onboot 1 \
    --start 1 \
    --ssh-public-keys ~/.ssh/id_rsa.pub 2>/dev/null || true

pct push "${LXCID}" /tmp/gamebox-${LXCID}.conf /etc/pve/lxc/${LXCID}.conf 2>/dev/null || {
    # Si no funciona push, sobrescribimos directamente
    cp /tmp/gamebox-${LXCID}.conf /etc/pve/lxc/${LXCID}.conf
}

echo -e "${GREEN}[OK]${NC} LXC creado e iniciado."

# ── Esperar a que arranque ──
echo ""
echo -e "${YELLOW}[PASO 3/4] Esperando que el LXC arranque...${NC}"
for i in {1..30}; do
    if pct status "${LXCID}" 2>/dev/null | grep -q "running"; then
        echo -e "${GREEN}[OK]${NC} LXC en ejecución."
        break
    fi
    sleep 2
done

# ── Copiar archivos al LXC ──
echo ""
echo -e "${YELLOW}[PASO 4/4] Copiando archivos de bootstrap al LXC...${NC}"
LXC_DIR="$(dirname "$(dirname "$(realpath "$0")")")/lxc"
pct push "${LXCID}" "${LXC_DIR}/bootstrap.sh" /root/bootstrap.sh
pct push "${LXCID}" "${LXC_DIR}/docker-compose.yml" /root/docker-compose.yml

# Crear archivo de identidad de la instancia
pct exec "${LXCID}" -- bash -c "echo 'GAMEBOX_INSTANCE=${INSTANCE_NAME}' > /etc/gamebox-instance"
pct exec "${LXCID}" -- bash -c "echo 'GAMEBOX_HOSTNAME=${HOSTNAME}' >> /etc/gamebox-instance"

echo -e "${GREEN}[OK]${NC} Archivos copiados."

# ── Instrucciones finales ──
LXC_IP=$(pct exec "${LXCID}" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "$IP_ADDR")
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Instancia creada con éxito${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo -e "  Nombre:    ${CYAN}${HOSTNAME}${NC}"
echo -e "  ID LXC:    ${LXCID}"
echo -e "  IP:        ${CYAN}${LXC_IP:-'(obteniendo...)'}${NC}"
echo -e "  SSH:       ${CYAN}ssh root@${LXC_IP:-'<IP>'}}${NC}"
echo ""
echo -e "  ${YELLOW}Próximo paso:${NC}"
echo -e "  Entra al LXC y ejecuta el bootstrap:"
echo ""
echo -e "    ${CYAN}pct enter ${LXCID}${NC}"
echo -e "    ${CYAN}/root/bootstrap.sh${NC}"
echo ""
echo -e "  O directamente:"
echo -e "    ${CYAN}pct exec ${LXCID} -- /root/bootstrap.sh${NC}"
echo ""
echo -e "${CYAN}============================================${NC}"
