import sys
import json
import os
from PIL import Image
import colorsys
import subprocess

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
            r_adj, g_adj, b_adj = (1.0, 0.2, 0.2)

        h, l, s = colorsys.rgb_to_hls(r_adj, g_adj, b_adj)
        
        if h < 0.08 or h > 0.92:
            h = 0.0
            
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
        return "#ff5555"

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
        with open(kitty_path, 'w') as f:
            f.write(kitty_theme_content)

        # 3. Generar el tema GTK3 totalmente OPACA (sin transparencias)
        gtk_css_content = f"""/* Tema dinámico generado por extractor.py (Opaco) */

- {{
    font-family: "JetBrainsMono Nerd Font";
    font-size: 10pt;
    outline: none;
    -gtk-secondary-caret-color: {primary_hex};
}}

window, dialog, assistant, .background, messagedialog {{
    background-color: #161616;
    color: #cdd6f4;
}}

scrolledwindow, viewport, box, grid {{
    background-color: transparent;
    color: #cdd6f4;
}}

headerbar, .titlebar {{
    background-color: #161616;
    border-bottom: 1px solid #313244;
    box-shadow: none;
    color: #cdd6f4;
    padding: 4px 8px;
}}

headerbar .title {{
    color: #cdd6f4;
    font-weight: bold;
}}

headerbar button {{
    background-color: #242424;
    border: 1px solid #313244;
    border-radius: 6px;
    color: #cdd6f4;
}}

headerbar button:hover {{
    background-color: #313244;
    color: {primary_hex};
    border-color: {primary_hex};
}}

treeview.view, list, listview {{
    background-color: #242424;
    color: #cdd6f4;
    border: 1px solid #313244;
    border-radius: 6px;
}}

treeview.view:hover, list row:hover {{
    background-color: #313244;
}}

treeview.view:selected, list row:selected {{
    background-color: {primary_hex};
    color: #11111b;
}}

entry {{
    background-color: #242424;
    color: #cdd6f4;
    border: 1px solid #313244;
    border-radius: 6px;
    padding: 6px 10px;
}}

entry:focus {{
    border-color: {primary_hex};
    box-shadow: none;
}}

combobox button.combo {{
    background-color: #242424;
    color: #cdd6f4;
    border: 1px solid #313244;
    border-radius: 6px;
    padding: 4px 8px;
}}

combobox menu, popover.menu {{
    background-color: #161616;
    border: 1px solid #313244;
    color: #cdd6f4;
}}

button {{
    background-color: #242424;
    color: #cdd6f4;
    border: 1px solid #313244;
    border-radius: 6px;
    padding: 6px 14px;
}}

button:hover {{
    background-color: #313244;
    border-color: {primary_hex};
    color: {primary_hex};
}}

button:active, button.suggested-action, button:checked {{
    background-color: {primary_hex};
    border-color: {primary_hex};
    color: #11111b;
}}

notebook {{
    background-color: transparent;
    border: none;
}}

notebook > stack {{
    background-color: transparent;
}}

notebook > header {{
    background-color: #161616;
    border-bottom: 1px solid #313244;
}}

notebook > header tab {{
    background-color: transparent;
    color: #6c7086;
    border: none;
    padding: 6px 12px;
}}

notebook > header tab:hover {{
    color: #cdd6f4;
}}

notebook > header tab:checked {{
    color: {primary_hex};
    border-bottom: 2px solid {primary_hex};
}}

scrollbar slider {{
    background-color: #313244;
    border-radius: 4px;
    min-width: 4px;
}}

scrollbar slider:hover {{
    background-color: #45475a;
}}
"""

        gtk_dir = os.path.expanduser("~/.config/gtk-3.0")
        os.makedirs(gtk_dir, exist_ok=True)
        gtk_path = os.path.join(gtk_dir, "gtk.css")
        with open(gtk_path, 'w') as f:
            f.write(gtk_css_content)

        # 4. Recargar Kitty en caliente
        subprocess.run(["pkill", "-SIGUSR1", "kitty"], capture_output=True)

    except Exception as e:
        print("Error:", e)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        generate_colors(sys.argv[1])