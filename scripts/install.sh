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

echo "=== 3. Instalando la lista de aplicaciones, navegador, applet de red y fuentes ==="
APPS=(
    "hyprland"
    "kitty"
    "gtk3"
    "fastfetch"
    "networkmanager"
    "network-manager-applet"
    "quickshell-git"
    "pulseaudio"
    "pavucontrol"
    "rofi"
    "zsh"
    "zsh-theme-powerlevel10k-git"
    "ttf-jetbrains-mono-nerd"
    "helium-browser-bin"
    "swaybg"
    "unzip"
    "code"
    "yazi"
    "hyprmod"
    "hyprshot"
)

for app in "${APPS[@]}"; do
    echo "Instalando $app..."
    yay -S --needed --noconfirm "$app" || echo "Aviso: No se pudo instalar $app automáticamente, revísalo luego."
done

echo "=== 4. Instalando Oh My Zsh y el tema Powerlevel10k ==="
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Instalando Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

if [ ! -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]; then
    echo "Clonando Powerlevel10k para Oh My Zsh..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
fi

echo "=== 5. Clonando el repositorio de GitHub con los Dotfiles ==="
REPO_URL="https://github.com/Bruno17x/hyprdots.git"
DEST_DIR="$HOME/.dotfiles_temp"

if [ -d "$DEST_DIR" ]; then
    rm -rf "$DEST_DIR"
fi

echo "Clonando repositorio..."
git clone "$REPO_URL" "$DEST_DIR"

echo "=== 6. Copiando todo el contenido de configs a tu directorio personal (~) ==="
if [ -d "$DEST_DIR/configs" ]; then
    # Crear la carpeta .config por seguridad si no existe
    mkdir -p "$HOME/.config"

    # Copia todos los archivos y carpetas normales o con punto (ocultas) desde configs/ hacia ~/
    cp -r "$DEST_DIR/configs/"* "$HOME/" 2>/dev/null || true
    cp -r "$DEST_DIR/configs/."* "$HOME/" 2>/dev/null || true

    echo "¡Todo el contenido de configs se ha copiado exitosamente en ~!"
else
    echo "Error: No se encontró la carpeta 'configs' dentro del repositorio clonado."
fi

echo "=== 7. Limpiando archivos temporales ==="
rm -rf "$DEST_DIR"

echo "=== 8. Habilitando servicios necesarios del sistema ==="
sudo systemctl enable NetworkManager

echo "=== 9. Estableciendo Zsh como shell predeterminada ==="
if [ "$SHELL" != "$(which zsh)" ]; then
    chsh -s "$(which zsh)"
    echo "Shell cambiada a Zsh. Se aplicará al reiniciar sesión."
fi

echo "¡Instalación y configuración completadas con éxito! Reinicia tu sesión para aplicar todos los cambios."
