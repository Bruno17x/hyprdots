pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: theme

    property string currentTheme: "purple"

    property var themes: {
        "purple": {
            name: "Morado",
            bg: "#d9161616",
            surface: "#59242424",
            surfaceAlt: "#40313244",
            border: "#313244",
            primary: "#cba6f7",
            primaryHover: "#b4befe",
            text: "#cdd6f4",
            subtext: "#a6adc8",
            muted: "#6c7086",
            danger: "#f38ba8",
            wallpaper: Quickshell.env("HOME") + "/wallpapers/purple.jpeg"
        },
        "red": {
            name: "Rojo",
            bg: "#d9161616",
            surface: "#59312424",
            surfaceAlt: "#40443131",
            border: "#443131",
            primary: "#f38ba8",
            primaryHover: "#eba0ac",
            text: "#cdd6f4",
            subtext: "#a6adc8",
            muted: "#6c7086",
            danger: "#f38ba8",
            wallpaper: Quickshell.env("HOME") + "/wallpapers/red.jpeg"
        },
        "blue": {
            name: "Azul",
            bg: "#d9161616",
            surface: "#59242a34",
            surfaceAlt: "#40313a44",
            border: "#313a44",
            primary: "#89b4fa",
            primaryHover: "#b4befe",
            text: "#cdd6f4",
            subtext: "#a6adc8",
            muted: "#6c7086",
            danger: "#f38ba8",
            wallpaper: Quickshell.env("HOME") + "/wallpapers/blue.jpeg"
        },
        "white": {
            name: "Blanco",
            bg: "#d9161616",
            surface: "#59454545",
            surfaceAlt: "#40585858",
            border: "#585858",
            primary: "#d0d0d0",
            primaryHover: "#ffffff",
            text: "#cdd6f4",
            subtext: "#a6adc8",
            muted: "#6c7086",
            danger: "#f38ba8",
            wallpaper: Quickshell.env("HOME") + "/wallpapers/white.jpeg"
        }
    }

    readonly property color bg: themes[currentTheme] ? themes[currentTheme].bg : "#d9161616"
    readonly property color surface: themes[currentTheme] ? themes[currentTheme].surface : "#59242424"
    readonly property color surfaceAlt: themes[currentTheme] ? themes[currentTheme].surfaceAlt : "#40313244"
    readonly property color border: themes[currentTheme] ? themes[currentTheme].border : "#313244"
    readonly property color primary: themes[currentTheme] ? themes[currentTheme].primary : "#cba6f7"
    readonly property color primaryHover: themes[currentTheme] ? themes[currentTheme].primaryHover : "#b4befe"
    readonly property color text: themes[currentTheme] ? themes[currentTheme].text : "#cdd6f4"
    readonly property color subtext: themes[currentTheme] ? themes[currentTheme].subtext : "#a6adc8"
    readonly property color muted: themes[currentTheme] ? themes[currentTheme].muted : "#6c7086"
    readonly property color danger: themes[currentTheme] ? themes[currentTheme].danger : "#f38ba8"
    readonly property string wallpaper: themes[currentTheme] ? themes[currentTheme].wallpaper : ""

    property Process rofiSyncProcess: Process {
        id: rofiSync
    }

    onCurrentThemeChanged: {
        let activeColor = themes[currentTheme] ? themes[currentTheme].primary : "#cba6f7";
        rofiSync.command = ["sh", "-c", "sed -i 's/^[[:space:]]*accent:[[:space:]]*#[a-fA-F0-9]*;/    accent:    " + activeColor + ";/' " + Quickshell.env("HOME") + "/.config/rofi/config.rasi"];
        rofiSync.running = true;
    }
}
