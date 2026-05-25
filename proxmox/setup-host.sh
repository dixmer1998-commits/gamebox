#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────
# GameBox — setup-host.sh
# Prepara el host Proxmox para GameBox:
#   - Drivers AMD
#   - IOMMU (amd_iommu=on)
#   - Módulos del kernel necesarios
#   - Verificación de /dev/dri
# ──────────────────────────────────────────────────────────

GAMEBOX_VERSION="1.0.0"

echo "============================================"
echo "  GameBox v${GAMEBOX_VERSION} — Setup Host"
echo "============================================"
echo ""

# ── Root check ──
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Este script debe ejecutarse como root en el host Proxmox."
    exit 1
fi

# ── Detectar CPU (Intel / AMD) ──
CPU_VENDOR=$(grep -m1 "^vendor_id" /proc/cpuinfo | awk '{print $3}')
if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
    CPU_FAMILY="intel"
    IOMMU_PARAM="intel_iommu=on"
elif [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
    CPU_FAMILY="amd"
    IOMMU_PARAM="amd_iommu=on"
else
    echo "[WARN] No se pudo detectar el fabricante de la CPU. Asumiendo AMD."
    CPU_FAMILY="amd"
    IOMMU_PARAM="amd_iommu=on"
fi
echo "[INFO] CPU detectada: $CPU_FAMILY"

# ── Verificar que es Proxmox ──
if ! command -v pveversion &>/dev/null; then
    echo "[ERROR] Esto no parece ser un host Proxmox (pveversion no encontrado)."
    exit 1
fi
echo "[INFO] Proxmox detectado: $(pveversion 2>/dev/null || echo 'desconocido')"

# ── 1. Instalar firmware AMD y drivers ──
echo ""
echo "[PASO 1/5] Instalando firmware AMD y drivers gráficos..."
apt-get update -qq
apt-get install -y -qq \
    firmware-amd-graphics \
    mesa-va-drivers \
    mesa-vulkan-drivers \
    libva-drm2 \
    libva2 \
    pve-headers \
    build-essential \
    dkms \
    curl \
    jq \
    2>/dev/null

# ── 2. Configurar IOMMU en GRUB ──
echo ""
echo "[PASO 2/5] Configurando IOMMU en GRUB..."
GRUB_FILE="/etc/default/grub"
GRUB_LINE="GRUB_CMDLINE_LINUX_DEFAULT"

if grep -q "amd_iommu=on\|intel_iommu=on" "$GRUB_FILE" 2>/dev/null; then
    echo "[INFO] IOMMU ya está configurado en GRUB."
else
    sed -i "s/^${GRUB_LINE}=\"\(.*\)\"/${GRUB_LINE}=\"\1 ${IOMMU_PARAM} iommu=pt pcie_acs_override=downstream,multifunction nofb nomodeset video=vesafb:off,efifb:off\"/" "$GRUB_FILE"
    echo "[OK] IOMMU configurado. Se aplicará tras reboot."
    GRUB_CHANGED=true
fi

# ── 3. Cargar módulos del kernel ──
echo ""
echo "[PASO 3/5] Configurando módulos del kernel..."
MODULES_FILE="/etc/modules"
for mod in vfio vfio_iommu_type1 vfio_pci vfio_virqfd; do
    if ! grep -q "^${mod}$" "$MODULES_FILE" 2>/dev/null; then
        echo "$mod" >> "$MODULES_FILE"
    fi
done
echo "[OK] Módulos VFIO configurados."

# ── 4. Verificar /dev/dri ──
echo ""
echo "[PASO 4/5] Verificando dispositivos GPU..."
if ls /dev/dri/render* &>/dev/null; then
    echo "[OK] /dev/dri disponible:"
    ls -la /dev/dri/render*
else
    echo "[WARN] /dev/dri no tiene dispositivos de renderizado."
    echo "       Asegúrate de que la GPU AMD esté instalada y los drivers cargados."
fi

# ── 5. Verificar /dev/uinput ──
echo ""
echo "[PASO 5/5] Verificando /dev/uinput..."
if [[ -c /dev/uinput ]]; then
    echo "[OK] /dev/uinput existe."
else
    echo "[WARN] /dev/uinput no existe. Se cargará el módulo..."
    modprobe uinput 2>/dev/null || true
    if [[ -c /dev/uinput ]]; then
        echo "[OK] Módulo uinput cargado."
        echo "uinput" >> /etc/modules 2>/dev/null || true
    else
        echo "[WARN] No se pudo cargar uinput. Se necesita para teclado/ratón virtual."
    fi
fi

# ── Resumen ──
echo ""
echo "============================================"
echo "  Resumen"
echo "============================================"
echo "  CPU:           $CPU_FAMILY"
echo "  IOMMU:         ${GRUB_CHANGED:-PENDIENTE (requiere reboot)}"
echo "  /dev/dri:      $(ls /dev/dri/render* 2>/dev/null || echo 'NO DISPONIBLE')"
echo "  /dev/uinput:   $( [[ -c /dev/uinput ]] && echo 'OK' || echo 'NO DISPONIBLE')"
echo ""
if [[ "${GRUB_CHANGED:-false}" == "true" ]]; then
    echo "[IMPORTANTE] Se modificó GRUB. Debes reiniciar el host para aplicar IOMMU:"
    echo "            # reboot"
    echo ""
fi
echo "[OK] Setup completado. Puedes continuar con create-lxc.sh"
echo "============================================"
