import sys
import json
import os
from PIL import Image
import colorsys
import subprocess
import re

def hex_to_rgb(hex_code):
    """Convierte un código hex (#RRGGBB) a una tupla RGB (0-255)."""
    hex_code = hex_code.lstrip('#')
    return tuple(int(hex_code[i:i+2], 16) for i in (0, 2, 4))

def rgb_to_hsv(r, g, b):
    """Convierte valores RGB (0-255) a HSV (H: 0-360, S: 0-255, V: 0-255)."""
    r, g, b = r/255.0, g/255.0, b/255.0
    max_c = max(r, g, b)
    min_c = min(r, g, b)
    diff = max_c - min_c
    
    if diff == 0:
        h = 0
    elif max_c == r:
        h = (60 * ((g - b) / diff) + 360) % 360
    elif max_c == g:
        h = (60 * ((b - r) / diff) + 120) % 360
    else:
        h = (60 * ((r - g) / diff) + 240) % 360
        
    s = 0 if max_c == 0 else diff / max_c
    v = max_c
    
    return h, s * 255, v * 255

def es_blanquecino(hex_code, umbral_saturacion=15, umbral_valor=230):
    """Determina si el color hex es blanquecino."""
    r, g, b = hex_to_rgb(hex_code)
    h, s, v = rgb_to_hsv(r, g, b)
    if s < umbral_saturacion and v > umbral_valor:
        return True
    return False

def get_brightest_vibrant_color(image_path):
    try:
        img = Image.open(image_path).convert('RGB')
        img.thumbnail((150, 150))
        
        pixels = list(img.getdata())
        candidates = []

        for r, g, b in pixels:
            rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
            h, l, s = colorsys.rgb_to_hls(rf, gf, bf)
            
            if l < 0.20 or s < 0.25:
                continue
                
            score = (l * 3.0) + (s * 2.0)
            candidates.append((score, (rf, gf, bf)))

        if candidates:
            candidates.sort(key=lambda x: x[0], reverse=True)
            _, best_rgb = candidates[0]
            r_adj, g_adj, b_adj = best_rgb
        else:
            r_adj, g_adj, b_adj = (0.7, 0.7, 0.75)

        h, l, s = colorsys.rgb_to_hls(r_adj, g_adj, b_adj)
        
        final_l = max(l, 0.75)
        final_s = max(s, 0.85)
        
        r_final, g_final, b_final = colorsys.hls_to_rgb(h, final_l, final_s)
        
        return '#{:02x}{:02x}{:02x}'.format(
            int(r_final * 255),
            int(g_final * 255),
            int(b_final * 255)
        )
        
    except Exception as e:
        print("Error analizando brillo:", e)
        return "#cba6f7"

def generate_colors(image_path):
    try:
        primary_hex = get_brightest_vibrant_color(image_path)
        
        # 1. Guardar JSON para Quickshell
        colors_data = {
            "colors": {
                "dark": {
                    "background": "#d9161616",
                    "surface": "#59242424",
                    "surface_bright": "#40313244",
                    "outline": "#313244",
                    "primary": primary_hex,
                    "primary_container": "#b4befe",
                    "on_background": "#cdd6f4",
                    "on_surface_variant": "#a6adc8",
                    "error": "#f38ba8"
                }
            }
        }
        
        quickshell_path = os.path.expanduser("~/.config/quickshell/colors.json")
        os.makedirs(os.path.dirname(quickshell_path), exist_ok=True)
        with open(quickshell_path, 'w') as f:
            json.dump(colors_data, f, indent=4)

        # 2. Guardar configuración para Kitty
        kitty_theme_content = f"""# Tema dinámico generado por extractor.py
background           #161616
foreground           #cdd6f4

color0               #282828
color1               {primary_hex}
color2               #a6e3a1
color3               #f9e2af
color4               {primary_hex}
color5               #f5c2e7
color6               #b4befe
color7               #ffffff

color8               #383838
color9               {primary_hex}
color10              #a6e3a1
color11              #f9e2af
color12              {primary_hex}
color13              #f5c2e7
color14              #b4befe
color15              #ffffff

cursor               {primary_hex}
cursor_text_color    #161616
selection_background {primary_hex}
selection_foreground #161616
"""

        kitty_path = os.path.expanduser("~/.config/kitty/current-theme.conf")
        os.makedirs(os.path.dirname(kitty_path), exist_ok=True)
        with open(kitty_path, 'w') as f:
            f.write(kitty_theme_content)

        # 3. Guardar colores dinámicos para Rofi (.rasi)
        rofi_colors_content = f"""* {{
    accent: {primary_hex};
    bg:        #161616cc;
    bg-alt:    #242424;
    fg:        #cdd6f4;
    muted:     #6c7086;
    subtle:    #45475a;

    background-color: transparent;
    text-color:       @fg;
}}
"""
        rofi_colors_path = os.path.expanduser("~/.config/rofi/colors.rasi")
        os.makedirs(os.path.dirname(rofi_colors_path), exist_ok=True)
        with open(rofi_colors_path, 'w') as f:
            f.write(rofi_colors_content)

        # 4. Adaptar GTK CSS
        core_theme_path = os.path.expanduser("~/.local/share/themes/core/gtk-3.0/gtk.css")
        if os.path.exists(core_theme_path):
            with open(core_theme_path, 'r') as f:
                gtk_css_content = f.read()
            gtk_css_content = gtk_css_content.replace("#cba6f7", primary_hex)
            gtk_css_content = gtk_css_content.replace("#CBA6F7", primary_hex)
        else:
            gtk_css_content = f"/* Tema base core no encontrado */\n* {{ color: {primary_hex}; }}"

        gtk_dir = os.path.expanduser("~/.config/gtk-3.0")
        os.makedirs(gtk_dir, exist_ok=True)
        gtk_path = os.path.join(gtk_dir, "gtk.css")
        with open(gtk_path, 'w') as f:
            f.write(gtk_css_content)

        # 5. Adaptar ~/.p10k.zsh (Ruta y OS Icon)
        p10k_path = os.path.expanduser("~/.p10k.zsh")
        if os.path.exists(p10k_path):
            with open(p10k_path, 'r') as f:
                p10k_content = f.read()

            if es_blanquecino(primary_hex):
                fg_color = "0"       # Texto ruta a negro
                short_color = "0"    # Directorios acortados a negro
                anchor_color = "0"   # Anclas a negro
                os_fg = "7"          # Icono de Arch en blanco
                os_bg = "0"          # Fondo del icono de Arch a negro
            else:
                fg_color = "254"     # Valor original
                short_color = "250"  # Valor original
                anchor_color = "255" # Valor original
                os_fg = "232"        # Valor original del icono
                os_bg = "7"          # Valor original del fondo del icono

            # Reemplazar variables de la ruta
            p10k_content = re.sub(
                r'(typeset\s+-g\s+POWERLEVEL9K_DIR_FOREGROUND=)\S+',
                rf'\g<1>{fg_color}',
                p10k_content
            )
            p10k_content = re.sub(
                r'(typeset\s+-g\s+POWERLEVEL9K_DIR_SHORTENED_FOREGROUND=)\S+',
                rf'\g<1>{short_color}',
                p10k_content
            )
            p10k_content = re.sub(
                r'(typeset\s+-g\s+POWERLEVEL9K_DIR_ANCHOR_FOREGROUND=)\S+',
                rf'\g<1>{anchor_color}',
                p10k_content
            )

            # Reemplazar variables del icono de Arch Linux (os_icon)
            p10k_content = re.sub(
                r'(typeset\s+-g\s+POWERLEVEL9K_OS_ICON_FOREGROUND=)\S+',
                rf'\g<1>{os_fg}',
                p10k_content
            )
            p10k_content = re.sub(
                r'(typeset\s+-g\s+POWERLEVEL9K_OS_ICON_BACKGROUND=)\S+',
                rf'\g<1>{os_bg}',
                p10k_content
            )

            with open(p10k_path, 'w') as f:
                f.write(p10k_content)

        # 6. Recargar Kitty en caliente
        subprocess.run(["pkill", "-SIGUSR1", "kitty"], capture_output=True)

    except Exception as e:
        print("Error:", e)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        generate_colors(sys.argv[1])
