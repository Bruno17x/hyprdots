#!/bin/bash

# Salir inmediatamente si ocurre un error
set -e

echo "=== 1. Actualizando el sistema e instalando herramientas base ==="
sudo pacman -Syu --needed --noconfirm git curl base-devel unzip

echo "=== 2. Instalando dependencias de AUR (yay) si no está instalado ==="
if ! command -v yay &> /dev/null; then
    echo "Clonando e instalando yay..."
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay
    makepkg -si --noconfirm
    cd ~
    rm -rf /tmp/yay
else
    echo "yay ya está instalado."
fi

echo "=== 3. Instalando la lista de aplicaciones solicitadas ==="
# Lista de paquetes que se instalarán mediante yay (incluye powerlevel10k)
APPS=(
    "hyprland"
    "kitty"
    "gtk3"
    "fastfetch"
    "networkmanager"
    "quickshell-git"
    "pulseaudio"
    "pavucontrol"
    "rofi"
    "zsh"
    "zsh-theme-powerlevel10k-git"
    "swaybg"
    "unzip"
    "code"
)

for app in "${APPS[@]}"; do
    echo "Instalando $app..."
    yay -S --needed --noconfirm "$app" || echo "Aviso: No se pudo instalar $app automáticamente, revísalo luego."
done

echo "=== 4. Clonando el repositorio de GitHub con los Dotfiles ==="
REPO_URL="https://github.com/Bruno17x/hyprdots.git"
DEST_DIR="$HOME/.dotfiles_temp"

if [ -d "$DEST_DIR" ]; then
    rm -rf "$DEST_DIR"
fi

echo "Clonando repositorio..."
git clone "$REPO_URL" "$DEST_DIR"

echo "=== 5. Copiando la carpeta /configs a tu directorio personal (~) ==="
if [ -d "$DEST_DIR/configs" ]; then
    # Copia recursiva y forzada manteniendo permisos y ocultos
    cp -rT "$DEST_DIR/configs/" "$HOME/"
    echo "¡Archivos de /configs copiados exitosamente en ~/"
else
    echo "Error: No se encontró la carpeta 'configs' dentro del repositorio clonado."
fi

echo "=== 6. Limpiando archivos temporales ==="
rm -rf "$DEST_DIR"

echo "=== 7. Estableciendo Zsh como shell predeterminada ==="
if [ "$SHELL" != "$(which zsh)" ]; then
    chsh -s "$(which zsh)"
    echo "Shell cambiada a Zsh. Se aplicará al reiniciar sesión."
fi

echo "¡Instalación y configuración completadas con éxito! Reinicia tu sesión para aplicar todos los cambios."
