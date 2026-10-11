pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: theme

    property string currentTheme: "dynamic"

    // Usamos FileView con una señal de recarga o forzando el reload
    property FileView colorFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/colors.json"
        watchChanges: true
    }

    // Cada vez que el proceso de extracción termine o queramos refrescar, forzamos la lectura
    function reloadColors() {
        colorFile.reload();
    }

    property var parsedColors: {
        try {
            // Añadimos colorFile.text aquí para que QML sepa que depende de él
            var rawText = colorFile.text();
            if (rawText !== "") {
                var json = JSON.parse(rawText);
                if (json.colors && json.colors.dark) {
                    return json.colors.dark;
                }
            }
        } catch(e) {
            console.log("Error parseando colors.json: " + e);
        }
        return null;
    }

    // Colores reactivos
    readonly property color bg: parsedColors && parsedColors.background ? parsedColors.background : "#d9161616"
    readonly property color surface: parsedColors && parsedColors.surface ? parsedColors.surface : "#59242424"
    readonly property color surfaceAlt: parsedColors && parsedColors.surface_bright ? parsedColors.surface_bright : "#40313244"
    readonly property color border: parsedColors && parsedColors.outline ? parsedColors.outline : "#313244"
    readonly property color primary: parsedColors && parsedColors.primary ? parsedColors.primary : "#cba6f7"
    readonly property color primaryHover: parsedColors && parsedColors.primary_container ? parsedColors.primary_container : "#b4befe"
    readonly property color text: parsedColors && parsedColors.on_background ? parsedColors.on_background : "#cdd6f4"
    readonly property color subtext: parsedColors && parsedColors.on_surface_variant ? parsedColors.on_surface_variant : "#a6adc8"
    readonly property color muted: "#6c7086"
    readonly property color danger: parsedColors && parsedColors.error ? parsedColors.error : "#f38ba8"
    readonly property string wallpaper: ""
}
