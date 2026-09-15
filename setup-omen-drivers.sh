#!/usr/bin/env bash
# Punto de entrada único para configurar drivers en este HP OMEN 16 (AMD + NVIDIA híbrido).
# Pensado para ejecutarse justo después de una instalación limpia de Manjaro (funciona
# desde una TTY sin sesión gráfica), y también para reparar/repetir la configuración en el
# sistema actual sin miedo: cada paso comprueba el estado antes de tocar nada.
# Autocontenido: no depende de ningún otro fichero de este directorio.
#
# Ver omen-nvidia-manjaro-fix.md para el porqué de cada paso.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Ejecuta este script con sudo: sudo ./setup-omen-drivers.sh" >&2
    exit 1
fi

CHANGED=0

write_if_different() {
    # write_if_different <ruta_destino> <contenido>
    local dest=$1 content=$2
    if [[ ! -f "$dest" ]] || ! diff -q <(printf '%s' "$content") "$dest" >/dev/null 2>&1; then
        echo "    Escribiendo $dest"
        mkdir -p "$(dirname "$dest")"
        printf '%s' "$content" > "$dest"
        CHANGED=1
    else
        echo "    $dest ya está correcto"
    fi
}

echo "==> [1/5] Driver NVIDIA (linux71-nvidia-open) + utilidades"
pacman -S --needed --noconfirm \
    linux71-nvidia-open nvidia-utils lib32-nvidia-utils nvidia-settings qt6-wayland

echo "==> [2/5] KMS moderno para NVIDIA (evita crashes de Qt6/Plasma con GPU híbrida)"
write_if_different /etc/modprobe.d/nvidia-drm-modeset.conf \
'options nvidia_drm modeset=1 fbdev=1
'

echo "==> [4/5] SDDM: greeter en Wayland con kwin_wayland (fix real del pantallazo en negro)"
write_if_different /etc/sddm.conf.d/10-wayland-greeter.conf \
'[General]
DisplayServer=wayland

[Wayland]
CompositorCommand=kwin_wayland --drm --no-lockscreen --no-global-shortcuts --locale1
'

echo
if [[ "$CHANGED" -eq 1 ]]; then
    echo "==> Cambios detectados, regenerando initramfs (mkinitcpio -P)"
    mkinitcpio -P
    echo "==> Hecho. Reinicia para que surtan efecto el driver de red y el modeset de NVIDIA:"
    echo "      sudo reboot"
else
    echo "==> Ya estaba todo configurado, no se ha tocado nada."
fi

echo
echo "AVISO: no ejecutes 'mhwd -r' ni 'mhwd -a' sobre el dispositivo NVIDIA (05:00.0) ni"
echo "sobre el driver de red r8168 en este equipo. mhwd solo conoce la rama NVIDIA 580xx"
echo "(cerrada) y reinstalarla rompería este setup (rama 610xx open ya instalada aquí)."
echo "Para reparar o repetir esta configuración, vuelve a ejecutar este mismo script."
