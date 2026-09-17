import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    property bool netMenuOpen: false
    property bool audioMenuOpen: false
    property bool micMenuOpen: false
    property bool sessionMenuOpen: false
    property bool themeMenuOpen: false
    property bool wifiEnabled: true

    // Estado del diálogo de confirmación para eliminar interfaz o VPN
    property bool confirmDeleteOpen: false
    property string targetDeleteName: ""
    property string targetDeleteType: "interface" // "interface" o "vpn"

    // --- DATOS DEL SISTEMA DE RED ---
    property bool ethernetConnected: false
    property var interfacesList: []
    property var wifiList: []
    property var vpnList: []

    // --- DATOS DEL SISTEMA DE AUDIO (PulseAudio) ---
    property int audioVolumeInt: 0
    property bool audioMuted: false
    property var audioSinksList: []

    property int micVolumeInt: 0
    property bool micMuted: false
    property var audioSourcesList: []

    // Cargar el tema guardado al arrancar Quickshell
    Process {
        id: loadSavedThemeProc
        running: true
        command: ["sh", "-c", "[ -f ~/.config/quickshell/current_theme.txt ] && cat ~/.config/quickshell/current_theme.txt | tr -d '\\n' || echo 'purple'"]
        stdout: SplitParser {
            onRead: line => {
                var t = line.trim();
                if (Theme.themes[t]) {
                    Theme.currentTheme = t;
                }
            }
        }
    }

    // Aplicar el wallpaper guardado automáticamente al arrancar Quickshell
    Process {
        id: initWallpaperProc
        running: true
        command: [
            "sh", "-c",
            "[ -f ~/.config/quickshell/current_theme.txt ] && theme=$(cat ~/.config/quickshell/current_theme.txt | tr -d '\\n') || theme='purple'; " +
            "pkill swaybg; swaybg -o '*' -i \"$HOME/wallpapers/$theme.jpeg\" -m fill &"
        ]
    }

    // 1. Estado Ethernet general
    Process {
        id: ethProc
        running: true
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE device 2>/dev/null | grep '^ethernet:' | grep -q 'connected' && echo 'yes' || echo 'no'"]
        stdout: SplitParser {
            onRead: line => root.ethernetConnected = (line.trim() === "yes")
        }
    }

    // 2. Estado Wi-Fi
    Process {
        id: wifiRadioProc
        running: true
        command: ["sh", "-c", "nmcli radio wifi 2>/dev/null"]
        stdout: SplitParser {
            onRead: line => root.wifiEnabled = (line.trim() === "enabled")
        }
    }

    // 3. Lista de Interfaces de Red
    Process {
        id: ifaceScanProc
        running: true
        command: [
            "sh", "-c",
            "ip -br addr show 2>/dev/null | awk '$1 !~ /^lo$/ { " +
            "  dev=$1; state=($2==\"UP\"?\"connected\":\"disconnected\"); " +
            "  split($3, a, \"/\"); ip=(a[1]!=\"\"?a[1]:\"Sin IP\"); " +
            "  type=(dev ~ /^wl/?\"wifi\":(dev ~ /^e/?\"ethernet\":\"virtual\")); " +
            "  print dev \"|\" type \"|\" state \"|\" dev \"|\" ip; " +
            "}'"
        ]
        stdout: SplitParser {
            onRead: line => {
                var l = line.trim();
                if (l.length === 0) return;
                var p = l.split("|");
                if (p.length >= 5) {
                    var current = [];
                    for (var i = 0; i < root.interfacesList.length; i++) current.push(root.interfacesList[i]);
                    current.push({
                        device: p[0],
                        type: p[1],
                        state: p[2],
                        connection: p[3],
                        ip: p[4]
                    });
                    root.interfacesList = current;
                }
            }
        }
    }

    // 4. Redes Wi-Fi
    Process {
        id: wifiScanProc
        command: ["sh", "-c", "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list 2>/dev/null | awk -F: '!seen[$2]++ && $2 != \"\" {print $1\":\"$2\":\"$3\":\"$4}' | head -n 6"]
        stdout: SplitParser {
            onRead: line => {
                var parts = line.trim().split(":");
                if (parts.length >= 3) {
                    var l = [];
                    for (var i = 0; i < root.wifiList.length; i++) l.push(root.wifiList[i]);
                    l.push({
                        inUse: parts[0] === "*",
                        ssid: parts[1],
                        signal: parts[2],
                        security: parts[3] || "Abierta"
                    });
                    root.wifiList = l;
                }
            }
        }
    }

    // 5. VPNs
    Process {
        id: vpnScanProc
        command: ["sh", "-c", "nmcli -t -f NAME,TYPE,STATE connection show 2>/dev/null | awk -F: '$2 ~ /vpn|wireguard/ {print $1\":\"$2\":\"$3}'"]
        stdout: SplitParser {
            onRead: line => {
                var parts = line.trim().split(":");
                if (parts.length >= 2) {
                    var l = [];
                    for (var i = 0; i < root.vpnList.length; i++) l.push(root.vpnList[i]);
                    l.push({
                        name: parts[0],
                        type: parts[1],
                        active: parts[2] === "activated"
                    });
                    root.vpnList = l;
                }
            }
        }
    }

    // 6. Salidas de Audio (PulseAudio Sinks)
    Process {
        id: audioSinksProc
        command: [
            "sh", "-c",
            "pactl list sinks 2>/dev/null | awk -v def=\"$(pactl get-default-sink 2>/dev/null)\" 'BEGIN{RS=\"Sink #\"; FS=\"\\n\"} NR>1 {name=\"\"; desc=\"\"; for(i=1;i<=NF;i++){ if($i ~ /^[[:blank:]]*Name:/){ sub(/^[[:blank:]]*Name:[[:blank:]]*/, \"\", $i); name=$i } if($i ~ /^[[:blank:]]*Description:/){ sub(/^[[:blank:]]*Description:[[:blank:]]*/, \"\", $i); desc=$i } } if(name!=\"\"){ print name \"|\" (desc!=\"\"?desc:name) \"|\" (name==def?1:0) } }'"
        ]
        stdout: SplitParser {
            onRead: line => {
                var l = line.trim();
                if (l.length === 0) return;
                var parts = l.split("|");
                if (parts.length >= 3) {
                    var currentList = [];
                    for (var i = 0; i < root.audioSinksList.length; i++) currentList.push(root.audioSinksList[i]);
                    currentList.push({
                        id: parts[0],
                        name: parts[1],
                        active: parts[2] === "1"
                    });
                    root.audioSinksList = currentList;
                }
            }
        }
    }

    // 7. Entradas de Audio (PulseAudio Sources)
    Process {
        id: audioSourcesProc
        command: [
            "sh", "-c",
            "pactl list sources 2>/dev/null | awk -v def=\"$(pactl get-default-source 2>/dev/null)\" 'BEGIN{RS=\"Source #\"; FS=\"\\n\"} NR>1 {name=\"\"; desc=\"\"; for(i=1;i<=NF;i++){ if($i ~ /^[[:blank:]]*Name:/){ sub(/^[[:blank:]]*Name:[[:blank:]]*/, \"\", $i); name=$i } if($i ~ /^[[:blank:]]*Description:/){ sub(/^[[:blank:]]*Description:[[:blank:]]*/, \"\", $i); desc=$i } } if(name!=\"\" && name !~ /\\.monitor$/){ print name \"|\" (desc!=\"\"?desc:name) \"|\" (name==def?1:0) } }'"
        ]
        stdout: SplitParser {
            onRead: line => {
                var l = line.trim();
                if (l.length === 0) return;
                var parts = l.split("|");
                if (parts.length >= 3) {
                    var currentList = [];
                    for (var i = 0; i < root.audioSourcesList.length; i++) currentList.push(root.audioSourcesList[i]);
                    currentList.push({
                        id: parts[0],
                        name: parts[1],
                        active: parts[2] === "1"
                    });
                    root.audioSourcesList = currentList;
                }
            }
        }
    }

    function refreshAllNetworks() {
        root.interfacesList = [];
        root.wifiList = [];
        root.vpnList = [];
        ethProc.running = true;
        wifiRadioProc.running = true;
        ifaceScanProc.running = true;
        wifiScanProc.running = true;
        vpnScanProc.running = true;
    }

    function refreshAudio() {
        root.audioSinksList = [];
        volProc.running = false;
        volProc.running = true;
        audioSinksProc.running = false;
        audioSinksProc.running = true;
    }

    function refreshMic() {
        root.audioSourcesList = [];
        micProc.running = false;
        micProc.running = true;
        audioSourcesProc.running = false;
        audioSourcesProc.running = true;
    }

    Process {
        id: execCmdProc
        property string targetCmd: ""
        // Se asegura de inyectar GTK_THEME en cualquier comando de red lanzado desde la barra
        command: ["sh", "-c", "GTK_THEME=" + Theme.currentTheme + " " + targetCmd]
        onExited: root.refreshAllNetworks()
    }

    Process {
        id: execAudioCmdProc
        property string targetCmd: ""
        command: ["sh", "-c", targetCmd]
        onExited: {
            volProc.running = false;
            volProc.running = true;
        }
    }

    Process {
        id: execMicCmdProc
        property string targetCmd: ""
        command: ["sh", "-c", targetCmd]
        onExited: {
            micProc.running = false;
            micProc.running = true;
        }
    }

    // Inyecta el tema actual al crear conexiones de red
    Process {
        id: addConnProc
        command: ["sh", "-c", "GTK_THEME=" + Theme.currentTheme + " nm-connection-editor --create"]
    }

    Process {
        id: sessionPoweroffProc
        command: ["systemctl", "poweroff"]
    }

    Process {
        id: sessionRebootProc
        command: ["systemctl", "reboot"]
    }

    Process {
        id: sessionLogoutProc
        command: ["hyprctl", "dispatch", "exit"]
    }

    Process {
        id: themeExec
    }

    // --- CAPA PARA DETECTAR CLICS FUERA ---
    PanelWindow {
        id: dismissLayer
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        visible: root.netMenuOpen || root.audioMenuOpen || root.micMenuOpen || root.sessionMenuOpen || root.themeMenuOpen || root.confirmDeleteOpen
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-dismiss-catcher"

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (root.confirmDeleteOpen) {
                    root.confirmDeleteOpen = false;
                } else {
                    root.netMenuOpen = false;
                    root.audioMenuOpen = false;
                    root.micMenuOpen = false;
                    root.sessionMenuOpen = false;
                    root.themeMenuOpen = false;
                }
            }
        }
    }

    // --- MENÚ DESPLEGABLE: SELECTOR DE TEMAS ---
    PanelWindow {
        id: themeDropdown
        anchors {
            top: true
            right: true
        }
        width: 250
        height: 230
        visible: root.themeMenuOpen
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-bar"

        Rectangle {
            id: themeMenuContainer
            anchors.fill: parent
            color: Theme.bg
            border.width: 0
            bottomLeftRadius: 10
            clip: true

            transform: Translate {
                y: root.themeMenuOpen ? 0 : -themeMenuContainer.height
                Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }

            opacity: root.themeMenuOpen ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 130 } }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Text {
                    text: "Seleccionar Tema"
                    color: Theme.text
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                Grid {
                    id: themeGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 2
                    spacing: 8

                    Repeater {
                        model: ["purple", "red", "blue", "white"]

                        delegate: Rectangle {
                            required property var modelData
                            width: 108
                            height: 80
                            radius: 6
                            color: Theme.currentTheme === modelData ? Theme.surfaceAlt : Theme.surface
                            border.color: Theme.currentTheme === modelData ? Theme.primary : Theme.border
                            border.width: Theme.currentTheme === modelData ? 2 : 1
                            clip: true

                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                source: "file://" + Theme.themes[modelData].wallpaper
                                fillMode: Image.PreserveAspectCrop
                                opacity: 0.65
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 22
                                color: "#99000000"
                                bottomLeftRadius: 6
                                bottomRightRadius: 6

                                Text {
                                    anchors.centerIn: parent
                                    text: Theme.themes[modelData].name
                                    color: Theme.text
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                id: themeItemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.themeMenuOpen = false;
                                    Theme.currentTheme = modelData;
                                    themeExec.command = [
                                        "sh", "-c",
                                        "mkdir -p ~/.config/quickshell && echo -n '" + modelData + "' > ~/.config/quickshell/current_theme.txt && " +
                                        "gsettings set org.gnome.desktop.interface gtk-theme '" + modelData + "' && " +
                                        "gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' && " +
                                        "pkill swaybg; swaybg -o '*' -i \"$HOME/wallpapers/" + modelData + ".jpeg\" -m fill & " +
                                        "[ -f ~/.config/kitty/themes/" + modelData + ".conf ] && cp ~/.config/kitty/themes/" + modelData + ".conf ~/.config/kitty/current-theme.conf && pkill -SIGUSR1 kitty"
                                    ];
                                    themeExec.running = false;
                                    themeExec.running = true;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- MENÚ DESPLEGABLE: SESIÓN / APAGADO ---
    PanelWindow {
        id: sessionDropdown
        anchors {
            top: true
            right: true
        }
        width: 200
        height: 155
        visible: root.sessionMenuOpen
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-bar"

        Rectangle {
            id: sessionMenuContainer
            anchors.fill: parent
            color: Theme.bg
            border.width: 0
            bottomLeftRadius: 10
            clip: true

            transform: Translate {
                y: root.sessionMenuOpen ? 0 : -sessionMenuContainer.height
                Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }

            opacity: root.sessionMenuOpen ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 130 } }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    height: 38
                    radius: 6
                    color: pwrBtnMouse.containsMouse ? Theme.surfaceAlt : Theme.surface

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        spacing: 10

                        Text {
                            text: "⏻"
                            color: pwrBtnMouse.containsMouse ? Theme.primaryHover : Theme.primary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                        }

                        Text {
                            text: "Apagar"
                            color: Theme.text
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: pwrBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.sessionMenuOpen = false;
                            sessionPoweroffProc.running = false;
                            sessionPoweroffProc.running = true;
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 38
                    radius: 6
                    color: rbtBtnMouse.containsMouse ? Theme.surfaceAlt : Theme.surface

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        spacing: 10

                        Text {
                            text: "󰑐"
                            color: rbtBtnMouse.containsMouse ? Theme.primaryHover : Theme.primary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                        }

                        Text {
                            text: "Reiniciar"
                            color: Theme.text
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: rbtBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.sessionMenuOpen = false;
                            sessionRebootProc.running = false;
                            sessionRebootProc.running = true;
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 38
                    radius: 6
                    color: lgtBtnMouse.containsMouse ? Theme.surfaceAlt : Theme.surface

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        spacing: 10

                        Text {
                            text: "󰗼"
                            color: lgtBtnMouse.containsMouse ? Theme.primaryHover : Theme.primary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                        }

                        Text {
                            text: "Cerrar sesión"
                            color: Theme.text
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: lgtBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.sessionMenuOpen = false;
                            sessionLogoutProc.running = false;
                            sessionLogoutProc.running = true;
                        }
                    }
                }
            }
        }
    }

    // --- DIÁLOGO MODAL DE CONFIRMACIÓN PARA ELIMINAR ---
    PanelWindow {
        id: confirmDialogWindow
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        visible: root.confirmDeleteOpen
        color: "#66000000"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-modal"

        Rectangle {
            anchors.centerIn: parent
            width: 300
            height: 140
            color: "#181825"
            radius: 8
            border.color: Theme.border
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                Text {
                    text: root.targetDeleteType === "vpn"
                          ? "¿Eliminar VPN '" + root.targetDeleteName + "'?"
                          : "¿Borrar conexión de " + root.targetDeleteName + "?"
                    color: Theme.text
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.maximumWidth: 270
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: root.targetDeleteType === "vpn"
                          ? "Se eliminará permanentemente la configuración de esta VPN."
                          : "Se eliminará el perfil de NetworkManager asignado a esta interfaz."
                    color: Theme.subtext
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        Layout.fillWidth: true
                        height: 30
                        radius: 5
                        color: cancelMouse.containsMouse ? Theme.surfaceAlt : Theme.surface

                        Text {
                            anchors.centerIn: parent
                            text: "Cancelar"
                            color: Theme.text
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.confirmDeleteOpen = false
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 30
                        radius: 5
                        color: deleteMouse.containsMouse ? Theme.primaryHover : Theme.primary

                        Text {
                            anchors.centerIn: parent
                            text: "Eliminar"
                            color: "#11111b"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            font.bold: true
                        }

                        MouseArea {
                            id: deleteMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.confirmDeleteOpen = false;
                                if (root.targetDeleteType === "vpn") {
                                    execCmdProc.targetCmd = "nmcli connection delete id '" + root.targetDeleteName + "'";
                                } else {
                                    execCmdProc.targetCmd = "uuid=$(nmcli -g UUID,DEVICE connection show --active 2>/dev/null | awk -F: -v d='" + root.targetDeleteName + "' '$2==d{print $1; exit}'); [ -z \"$uuid\" ] && uuid=$(nmcli -g UUID,DEVICE connection show 2>/dev/null | awk -F: -v d='" + root.targetDeleteName + "' '$2==d{print $1; exit}'); if [ -n \"$uuid\" ]; then nmcli connection delete uuid \"$uuid\"; else nmcli device delete '" + root.targetDeleteName + "' 2>/dev/null || nmcli device disconnect '" + root.targetDeleteName + "'; fi";
                                }
                                execCmdProc.running = false;
                                execCmdProc.running = true;
                            }
                        }
                    }
                }
            }
        }
    }

    // --- MENÚ DESPLEGABLE: RED ---
    PanelWindow {
        id: networkDropdown
        anchors {
            top: true
            right: true
        }
        width: 360
        height: 490
        visible: root.netMenuOpen
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-bar"

        Rectangle {
            id: menuContainer
            anchors.fill: parent
            color: Theme.bg
            border.width: 0
            bottomLeftRadius: 10
            clip: true

            transform: Translate {
                y: root.netMenuOpen ? 0 : -menuContainer.height
                Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }

            opacity: root.netMenuOpen ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 130 } }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Conexiones de Red"
                        color: Theme.text
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        width: 24
                        height: 24
                        radius: 4
                        color: addMouse.containsMouse ? Theme.surfaceAlt : Theme.surface

                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            color: Theme.primary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            font.bold: true
                        }

                        MouseArea {
                            id: addMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.netMenuOpen = false;
                                addConnProc.running = false;
                                addConnProc.running = true;
                            }
                        }
                    }

                    Text {
                        text: "󰑐"
                        color: reloadMouse.containsMouse ? Theme.primaryHover : Theme.primary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13

                        MouseArea {
                            id: reloadMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refreshAllNetworks()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "Interfaces del Sistema"
                        color: Theme.subtext
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        font.bold: true
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 120
                    model: root.interfacesList
                    spacing: 4
                    clip: true

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 38
                        color: ifaceMouse.containsMouse ? Theme.surface : "transparent"
                        radius: 5

                        Item {
                            anchors.fill: parent

                            RowLayout {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.right: buttonsRow.left
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                Text {
                                    text: modelData.type === "ethernet" ? "󰈀" : (modelData.type === "wifi" ? "󰤨" : "󰛳")
                                    color: modelData.state === "connected" ? Theme.primary : Theme.muted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 14
                                }

                                ColumnLayout {
                                    spacing: 1
                                    Layout.fillWidth: true

                                    RowLayout {
                                        spacing: 6
                                        Layout.fillWidth: true

                                        Text {
                                            text: modelData.device
                                            color: Theme.text
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            font.bold: true
                                        }

                                        Text {
                                            text: "(" + (modelData.state === "connected" ? modelData.connection : "Inactiva") + ")"
                                            color: Theme.muted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    Text {
                                        text: modelData.ip
                                        color: Theme.subtext
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                    }
                                }
                            }

                            Row {
                                id: buttonsRow
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Rectangle {
                                    width: 24
                                    height: 24
                                    radius: 4
                                    color: editMouse.containsMouse ? Theme.surfaceAlt : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰏫"
                                        color: modelData.state === "connected" ? Theme.primary : Theme.muted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 13
                                    }

                                    MouseArea {
                                        id: editMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.netMenuOpen = false;
                                            execCmdProc.targetCmd = "uuid=$(nmcli -g UUID,DEVICE connection show --active 2>/dev/null | awk -F: -v d='" + modelData.device + "' '$2==d{print $1; exit}'); [ -z \"$uuid\" ] && uuid=$(nmcli -g UUID,DEVICE connection show 2>/dev/null | awk -F: -v d='" + modelData.device + "' '$2==d{print $1; exit}'); if [ -n \"$uuid\" ]; then nm-connection-editor --edit=\"$uuid\"; else nm-connection-editor; fi";
                                            execCmdProc.running = false;
                                            execCmdProc.running = true;
                                        }
                                    }
                                }

                                Rectangle {
                                    width: 24
                                    height: 24
                                    radius: 4
                                    color: trashMouse.containsMouse ? Theme.surfaceAlt : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰆴"
                                        color: trashMouse.containsMouse ? Theme.primaryHover : Theme.subtext
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 13
                                    }

                                    MouseArea {
                                        id: trashMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.targetDeleteName = modelData.device;
                                            root.targetDeleteType = "interface";
                                            root.confirmDeleteOpen = true;
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: ifaceMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            z: -1
                            onClicked: {
                                if (modelData.state !== "connected") {
                                    execCmdProc.targetCmd = "nmcli device connect " + modelData.device;
                                    execCmdProc.running = false;
                                    execCmdProc.running = true;
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.border
                }

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "Redes Wi-Fi"
                        color: Theme.subtext
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        width: 28
                        height: 16
                        radius: 8
                        color: root.wifiEnabled ? Theme.primary : Theme.surfaceAlt

                        Rectangle {
                            width: 12
                            height: 12
                            radius: 6
                            color: "#11111b"
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.wifiEnabled ? 14 : 2
                            Behavior on x { NumberAnimation { duration: 130 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                execCmdProc.targetCmd = root.wifiEnabled ? "nmcli radio wifi off" : "nmcli radio wifi on";
                                execCmdProc.running = false;
                                execCmdProc.running = true;
                            }
                        }
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 100
                    model: root.wifiList
                    spacing: 2
                    clip: true

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 28
                        color: wifiItemMouse.containsMouse ? Theme.surface : "transparent"
                        radius: 4

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: modelData.security !== "Abierta" && modelData.security !== "" ? "󰤪" : "󰤨"
                                color: modelData.inUse ? Theme.primary : Theme.primaryHover
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                            }

                            Text {
                                text: modelData.ssid
                                color: modelData.inUse ? Theme.primary : Theme.text
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                font.bold: modelData.inUse
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: modelData.signal + "%"
                                color: Theme.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            id: wifiItemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                execCmdProc.targetCmd = "nmcli device wifi connect '" + modelData.ssid + "'";
                                execCmdProc.running = false;
                                execCmdProc.running = true;
                                root.netMenuOpen = false;
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.border
                }

                Text {
                    text: "Túneles VPN / WireGuard"
                    color: Theme.subtext
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.bold: true
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 80
                    model: root.vpnList
                    spacing: 3
                    clip: true

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 32
                        color: vpnItemMouse.containsMouse ? Theme.surface : "transparent"
                        radius: 4

                        Item {
                            anchors.fill: parent

                            RowLayout {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.right: vpnTrashBtn.left
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                Text {
                                    text: "󰌾"
                                    color: modelData.active ? Theme.primary : Theme.muted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                }

                                Text {
                                    text: modelData.name
                                    color: modelData.active ? Theme.primary : Theme.text
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    font.bold: modelData.active
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: modelData.active ? "Activo" : "Conectar"
                                    color: modelData.active ? Theme.primary : Theme.primaryHover
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                }
                            }

                            Rectangle {
                                id: vpnTrashBtn
                                width: 22
                                height: 22
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                radius: 4
                                color: vpnTrashMouse.containsMouse ? Theme.surfaceAlt : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰆴"
                                    color: vpnTrashMouse.containsMouse ? Theme.primaryHover : Theme.subtext
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                }

                                MouseArea {
                                    id: vpnTrashMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.targetDeleteName = modelData.name;
                                        root.targetDeleteType = "vpn";
                                        root.confirmDeleteOpen = true;
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: vpnItemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            z: -1
                            onClicked: {
                                if (modelData.active) {
                                    execCmdProc.targetCmd = "nmcli connection down id '" + modelData.name + "'";
                                } else {
                                    execCmdProc.targetCmd = "nmcli connection up id '" + modelData.name + "'";
                                }
                                execCmdProc.running = false;
                                execCmdProc.running = true;
                            }
                        }
                    }
                }
            }
        }
    }

    // --- MENÚ DESPLEGABLE: AUDIO SALIDA ---
    PanelWindow {
        id: audioDropdown
        anchors {
            top: true
            right: true
        }
        width: 340
        height: 380
        visible: root.audioMenuOpen
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-bar"

        Rectangle {
            id: audioMenuContainer
            anchors.fill: parent
            color: Theme.bg
            border.width: 0
            bottomLeftRadius: 10
            clip: true

            transform: Translate {
                y: root.audioMenuOpen ? 0 : -audioMenuContainer.height
                Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }

            opacity: root.audioMenuOpen ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 130 } }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Control de Salida"
                        color: Theme.text
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        width: 24
                        height: 24
                        radius: 4
                        color: pavuMouse.containsMouse ? Theme.surfaceAlt : Theme.surface

                        Text {
                            anchors.centerIn: parent
                            text: "󰓃"
                            color: Theme.primary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: pavuMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.audioMenuOpen = false;
                                audioProc.running = false;
                                audioProc.running = true;
                            }
                        }
                    }

                    Text {
                        text: "󰑐"
                        color: reloadAudioMouse.containsMouse ? Theme.primaryHover : Theme.primary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13

                        MouseArea {
                            id: reloadAudioMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refreshAudio()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 80
                    color: Theme.surface
                    radius: 6

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: root.audioMuted ? "󰝟" : (root.audioVolumeInt === 0 ? "󰕿" : (root.audioVolumeInt < 50 ? "󰖀" : "󰕾"))
                                color: root.audioMuted ? Theme.danger : Theme.primary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 16

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        execAudioCmdProc.targetCmd = "pactl set-sink-mute @DEFAULT_SINK@ toggle";
                                        execAudioCmdProc.running = false;
                                        execAudioCmdProc.running = true;
                                    }
                                }
                            }

                            Text {
                                text: "Volumen Salida"
                                color: Theme.text
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                font.bold: true
                                Layout.fillWidth: true
                            }

                            Text {
                                text: root.audioMuted ? "MUTE" : root.audioVolumeInt + "%"
                                color: root.audioMuted ? Theme.danger : Theme.primary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }

                        Rectangle {
                            id: volumeTrack
                            Layout.fillWidth: true
                            height: 8
                            radius: 4
                            color: Theme.surfaceAlt

                            Rectangle {
                                width: Math.max(0, Math.min(volumeTrack.width, (root.audioVolumeInt / 100.0) * volumeTrack.width))
                                height: parent.height
                                radius: 4
                                color: root.audioMuted ? Theme.muted : Theme.primary
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor

                                function updateVol(mouse) {
                                    var percent = Math.round(Math.max(0, Math.min(100, (mouse.x / volumeTrack.width) * 100)));
                                    root.audioVolumeInt = percent;
                                    execAudioCmdProc.targetCmd = "pactl set-sink-volume @DEFAULT_SINK@ " + percent + "%";
                                    execAudioCmdProc.running = false;
                                    execAudioCmdProc.running = true;
                                }

                                onClicked: mouse => updateVol(mouse)
                                onPressed: mouse => updateVol(mouse)
                                onPositionChanged: mouse => { if (pressed) updateVol(mouse); }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.border
                }

                Text {
                    text: "Dispositivos de Salida"
                    color: Theme.subtext
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.bold: true
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: root.audioSinksList
                    spacing: 4
                    clip: true

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 36
                        color: sinkMouse.containsMouse ? Theme.surface : "transparent"
                        radius: 5

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: modelData.name.toLowerCase().indexOf("headphone") !== -1 ? "󰋋" : (modelData.name.toLowerCase().indexOf("hdmi") !== -1 ? "󰡁" : "󰓃")
                                color: modelData.active ? Theme.primary : Theme.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 14
                            }

                            Text {
                                text: modelData.name
                                color: modelData.active ? Theme.primary : Theme.text
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                font.bold: modelData.active
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                width: 6
                                height: 6
                                radius: 3
                                color: modelData.active ? Theme.primary : "transparent"
                            }
                        }

                        MouseArea {
                            id: sinkMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                execAudioCmdProc.targetCmd = "pactl set-default-sink '" + modelData.id + "'";
                                execAudioCmdProc.running = false;
                                execAudioCmdProc.running = true;
                                root.refreshAudio();
                            }
                        }
                    }
                }
            }
        }
    }

    // --- MENÚ DESPLEGABLE: AUDIO ENTRADA (MICRÓFONO) ---
    PanelWindow {
        id: micDropdown
        anchors {
            top: true
            right: true
        }
        width: 340
        height: 380
        visible: root.micMenuOpen
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-bar"

        Rectangle {
            id: micMenuContainer
            anchors.fill: parent
            color: Theme.bg
            border.width: 0
            bottomLeftRadius: 10
            clip: true

            transform: Translate {
                y: root.micMenuOpen ? 0 : -micMenuContainer.height
                Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }

            opacity: root.micMenuOpen ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 130 } }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Control de Entrada"
                        color: Theme.text
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        width: 24
                        height: 24
                        radius: 4
                        color: pavuMicMouse.containsMouse ? Theme.surfaceAlt : Theme.surface

                        Text {
                            anchors.centerIn: parent
                            text: "󰓃"
                            color: Theme.primary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: pavuMicMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.micMenuOpen = false;
                                audioProc.running = false;
                                audioProc.running = true;
                            }
                        }
                    }

                    Text {
                        text: "󰑐"
                        color: reloadMicMouse.containsMouse ? Theme.primaryHover : Theme.primary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13

                        MouseArea {
                            id: reloadMicMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refreshMic()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 80
                    color: Theme.surface
                    radius: 6

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: root.micMuted ? "󰍭" : "󰍬"
                                color: root.micMuted ? Theme.danger : Theme.primary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 16

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        execMicCmdProc.targetCmd = "pactl set-source-mute @DEFAULT_SOURCE@ toggle";
                                        execMicCmdProc.running = false;
                                        execMicCmdProc.running = true;
                                    }
                                }
                            }

                            Text {
                                text: "Ganancia de Entrada"
                                color: Theme.text
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                font.bold: true
                                Layout.fillWidth: true
                            }

                            Text {
                                text: root.micMuted ? "MUTE" : root.micVolumeInt + "%"
                                color: root.micMuted ? Theme.danger : Theme.primary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }

                        Rectangle {
                            id: micTrack
                            Layout.fillWidth: true
                            height: 8
                            radius: 4
                            color: Theme.surfaceAlt

                            Rectangle {
                                width: Math.max(0, Math.min(micTrack.width, (root.micVolumeInt / 100.0) * micTrack.width))
                                height: parent.height
                                radius: 4
                                color: root.micMuted ? Theme.muted : Theme.primary
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor

                                function updateMic(mouse) {
                                    var percent = Math.round(Math.max(0, Math.min(100, (mouse.x / micTrack.width) * 100)));
                                    root.micVolumeInt = percent;
                                    execMicCmdProc.targetCmd = "pactl set-source-volume @DEFAULT_SOURCE@ " + percent + "%";
                                    execMicCmdProc.running = false;
                                    execMicCmdProc.running = true;
                                }

                                onClicked: mouse => updateMic(mouse)
                                onPressed: mouse => updateMic(mouse)
                                onPositionChanged: mouse => { if (pressed) updateMic(mouse); }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.border
                }

                Text {
                    text: "Dispositivos de Entrada"
                    color: Theme.subtext
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.bold: true
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: root.audioSourcesList
                    spacing: 4
                    clip: true

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 36
                        color: sourceMouse.containsMouse ? Theme.surface : "transparent"
                        radius: 5

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: "󰍬"
                                color: modelData.active ? Theme.primary : Theme.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 14
                            }

                            Text {
                                text: modelData.name
                                color: modelData.active ? Theme.primary : Theme.text
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                font.bold: modelData.active
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                width: 6
                                height: 6
                                radius: 3
                                color: modelData.active ? Theme.primary : "transparent"
                            }
                        }

                        MouseArea {
                            id: sourceMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                execMicCmdProc.targetCmd = "pactl set-default-source '" + modelData.id + "'";
                                execMicCmdProc.running = false;
                                execMicCmdProc.running = true;
                                root.refreshMic();
                            }
                        }
                    }
                }
            }
        }
    }

    // --- BARRA PRINCIPAL ---
    PanelWindow {
        id: bar
        anchors {
            top: true
            left: true
            right: true
        }
        height: 32
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-bar"

        Rectangle {
            anchors.fill: parent
            color: Theme.bg
        }

        property string cpuUsage: "0%"
        property real prevTotalCpu: 0
        property real prevIdleCpu: 0

        Process {
            id: cpuProc
            command: ["sh", "-c", "head -n1 /proc/stat"]
            stdout: SplitParser {
                onRead: line => {
                    var parts = line.trim().split(/\s+/);
                    if (parts.length >= 5) {
                        var user = parseFloat(parts[1]) || 0;
                        var nice = parseFloat(parts[2]) || 0;
                        var system = parseFloat(parts[3]) || 0;
                        var idle = parseFloat(parts[4]) || 0;
                        var iowait = parseFloat(parts[5]) || 0;

                        var currentIdle = idle + iowait;
                        var currentTotal = user + nice + system + idle + iowait;

                        if (bar.prevTotalCpu > 0) {
                            var totalDiff = currentTotal - bar.prevTotalCpu;
                            var idleDiff = currentIdle - bar.prevIdleCpu;
                            if (totalDiff > 0) {
                                var usage = Math.round(((totalDiff - idleDiff) / totalDiff) * 100);
                                bar.cpuUsage = usage + "%";
                            }
                        }

                        bar.prevTotalCpu = currentTotal;
                        bar.prevIdleCpu = currentIdle;
                    }
                }
            }
        }

        property string gpuUsage: "0%"
        Process {
            id: gpuProc
            command: ["sh", "-c", "if which nvidia-smi >/dev/null 2>&1; then nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -n1 | awk '{print $1\"%\"}'; elif [ -f /sys/class/drm/card0/device/gpu_busy_percent ]; then awk '{print $1\"%\"}' /sys/class/drm/card0/device/gpu_busy_percent; elif [ -f /sys/class/drm/card1/device/gpu_busy_percent ]; then awk '{print $1\"%\"}' /sys/class/drm/card1/device/gpu_busy_percent; else echo '0%'; fi"]
            stdout: SplitParser {
                onRead: line => {
                    var val = line.trim();
                    if (val.length > 0) bar.gpuUsage = val;
                }
            }
        }

        property string downSpeed: "0 KB/s"
        property string upSpeed: "0 KB/s"
        property real prevRx: 0
        property real prevTx: 0

        function formatSpeed(bytes) {
            var kb = bytes / 1024;
            if (kb >= 1024) return (kb / 1024).toFixed(1) + " MB/s";
            return Math.round(kb) + " KB/s";
        }

        Process {
            id: netProc
            command: ["sh", "-c", "awk 'NR>2 && $1 !~ /lo:/ {rx+=$2; tx+=$10} END {print rx, tx}' /proc/net/dev"]
            stdout: SplitParser {
                onRead: line => {
                    var parts = line.trim().split(/\s+/);
                    if (parts.length >= 2) {
                        var totalRx = parseFloat(parts[0]) || 0;
                        var totalTx = parseFloat(parts[1]) || 0;

                        if (bar.prevRx > 0 && bar.prevTx > 0) {
                            var rxDiff = Math.max(0, totalRx - bar.prevRx);
                            var txDiff = Math.max(0, totalTx - bar.prevTx);
                            bar.downSpeed = bar.formatSpeed(rxDiff);
                            bar.upSpeed = bar.formatSpeed(txDiff);
                        }

                        bar.prevRx = totalRx;
                        bar.prevTx = totalTx;
                    }
                }
            }
        }

        Process {
            id: volProc
            command: ["sh", "-c", "mute=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{print $2}'); vol=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | head -n1 | grep -o '[0-9]\\+%' | head -n1 | tr -d '%'); echo \"$mute:$vol\""]
            stdout: SplitParser {
                onRead: line => {
                    var parts = line.trim().split(":");
                    if (parts.length >= 2) {
                        root.audioMuted = (parts[0] === "yes");
                        root.audioVolumeInt = parseInt(parts[1]) || 0;
                    }
                }
            }
        }

        Process {
            id: micProc
            command: ["sh", "-c", "mute=$(pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | awk '{print $2}'); vol=$(pactl get-source-volume @DEFAULT_SOURCE@ 2>/dev/null | head -n1 | grep -o '[0-9]\\+%' | head -n1 | tr -d '%'); echo \"$mute:$vol\""]
            stdout: SplitParser {
                onRead: line => {
                    var parts = line.trim().split(":");
                    if (parts.length >= 2) {
                        root.micMuted = (parts[0] === "yes");
                        root.micVolumeInt = parseInt(parts[1]) || 0;
                    }
                }
            }
        }

        Timer {
            interval: 1000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                if (!netProc.running) netProc.running = true;
                if (!volProc.running) volProc.running = true;
                if (!micProc.running) micProc.running = true;
                if (!cpuProc.running) cpuProc.running = true;
                if (!gpuProc.running) gpuProc.running = true;
                if (!ethProc.running) ethProc.running = true;
            }
        }

        Process {
            id: appMenuProc
            command: ["sh", "-c", "pkill rofi || rofi -show drun"]
        }

        // Inyecta el tema actual al abrir pavucontrol desde la barra
        Process {
            id: audioProc
            command: ["sh", "-c", "GTK_THEME=" + Theme.currentTheme + " pavucontrol"]
        }

        Item {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16

            // --- IZQUIERDA ---
            RowLayout {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Text {
                    text: "\uf303"
                    color: Theme.primary
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 15

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            appMenuProc.running = false;
                            appMenuProc.running = true;
                        }
                    }
                }

                Rectangle {
                    width: 1
                    height: 12
                    color: Theme.border
                }

                Row {
                    spacing: 8

                    Repeater {
                        model: Hyprland.workspaces.values.filter(ws => ws.id > 0)

                        delegate: Text {
                            required property var modelData

                            text: modelData.id
                            color: (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === modelData.id)
                                   ? Theme.primary
                                   : Theme.muted

                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            font.bold: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === modelData.id

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Hyprland.dispatch("workspace " + modelData.id)
                            }
                        }
                    }
                }

                Rectangle {
                    width: 1
                    height: 12
                    color: Theme.border
                }

                Text {
                    text: (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id < 0)
                          ? "Special"
                          : "Desktop"
                    color: Theme.subtext
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                }
            }

            // --- CENTRO ---
            RowLayout {
                anchors.centerIn: parent
                spacing: 8

                property var date: new Date()

                Timer {
                    interval: 1000
                    running: true
                    repeat: true
                    onTriggered: parent.date = new Date()
                }

                Text {
                    text: Qt.formatDateTime(parent.date, "dd MMM")
                    color: Theme.subtext
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                }

                Text {
                    text: Qt.formatDateTime(parent.date, "hh:mm AP")
                    color: Theme.text
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.bold: true
                }
            }

            // --- DERECHA ---
            RowLayout {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14

                // Red
                Row {
                    spacing: 6

                    Row {
                        spacing: 8
                        anchors.verticalCenter: parent.verticalCenter

                        Row {
                            spacing: 3
                            Text {
                                text: "↓"
                                color: Theme.primary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                font.bold: true
                            }
                            Text {
                                text: bar.downSpeed
                                color: Theme.text
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                            }
                        }

                        Row {
                            spacing: 3
                            Text {
                                text: "↑"
                                color: Theme.primary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                font.bold: true
                            }
                            Text {
                                text: bar.upSpeed
                                color: Theme.text
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                            }
                        }
                    }

                    Text {
                        text: root.ethernetConnected ? "\uf0e8" : "\uf1eb"
                        color: root.netMenuOpen ? Theme.primaryHover : Theme.primary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.audioMenuOpen = false;
                                root.micMenuOpen = false;
                                root.sessionMenuOpen = false;
                                root.themeMenuOpen = false;
                                root.netMenuOpen = !root.netMenuOpen;
                                if (root.netMenuOpen) {
                                    root.refreshAllNetworks();
                                }
                            }
                        }
                    }
                }

                // 1. Audio Salida
                Rectangle {
                    width: audioRow.width + 12
                    height: 28
                    color: "transparent"
                    Layout.alignment: Qt.AlignVCenter

                    Row {
                        id: audioRow
                        spacing: 6
                        anchors.centerIn: parent

                        Text {
                            text: root.audioMuted ? "0%" : root.audioVolumeInt + "%"
                            color: Theme.text
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: root.audioMuted ? "󰝟" : (root.audioVolumeInt === 0 ? "󰕿" : (root.audioVolumeInt < 50 ? "󰖀" : "󰕾"))
                            color: root.audioMenuOpen ? Theme.primaryHover : (root.audioMuted ? Theme.danger : Theme.primary)
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton

                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                execAudioCmdProc.targetCmd = "pactl set-sink-mute @DEFAULT_SINK@ toggle";
                                execAudioCmdProc.running = false;
                                execAudioCmdProc.running = true;
                            } else {
                                root.netMenuOpen = false;
                                root.micMenuOpen = false;
                                root.sessionMenuOpen = false;
                                root.themeMenuOpen = false;
                                root.audioMenuOpen = !root.audioMenuOpen;
                                if (root.audioMenuOpen) {
                                    root.refreshAudio();
                                }
                            }
                        }

                        onWheel: wheel => {
                            wheel.accepted = true;
                            var targetVol = root.audioVolumeInt;
                            if (wheel.angleDelta.y > 0) {
                                targetVol = Math.min(100, targetVol + 5);
                            } else {
                                targetVol = Math.max(0, targetVol - 5);
                            }
                            root.audioVolumeInt = targetVol;
                            execAudioCmdProc.targetCmd = "pactl set-sink-volume @DEFAULT_SINK@ " + targetVol + "%";
                            execAudioCmdProc.running = false;
                            execAudioCmdProc.running = true;
                        }
                    }
                }

                // 2. Audio Entrada (Micrófono)
                Rectangle {
                    width: micRow.width + 12
                    height: 28
                    color: "transparent"
                    Layout.alignment: Qt.AlignVCenter

                    Row {
                        id: micRow
                        spacing: 6
                        anchors.centerIn: parent

                        Text {
                            text: root.micMuted ? "0%" : root.micVolumeInt + "%"
                            color: Theme.text
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: root.micMuted ? "󰍭" : "󰍬"
                            color: root.micMenuOpen ? Theme.primaryHover : (root.micMuted ? Theme.danger : Theme.primary)
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton

                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                execMicCmdProc.targetCmd = "pactl set-source-mute @DEFAULT_SOURCE@ toggle";
                                execMicCmdProc.running = false;
                                execMicCmdProc.running = true;
                            } else {
                                root.netMenuOpen = false;
                                root.audioMenuOpen = false;
                                root.sessionMenuOpen = false;
                                root.themeMenuOpen = false;
                                root.micMenuOpen = !root.micMenuOpen;
                                if (root.micMenuOpen) {
                                    root.refreshMic();
                                }
                            }
                        }

                        onWheel: wheel => {
                            wheel.accepted = true;
                            var targetMic = root.micVolumeInt;
                            if (wheel.angleDelta.y > 0) {
                                targetMic = Math.min(100, targetMic + 5);
                            } else {
                                targetMic = Math.max(0, targetMic - 5);
                            }
                            root.micVolumeInt = targetMic;
                            execMicCmdProc.targetCmd = "pactl set-source-volume @DEFAULT_SOURCE@ " + targetMic + "%";
                            execMicCmdProc.running = false;
                            execMicCmdProc.running = true;
                        }
                    }
                }

                // GPU
                Row {
                    spacing: 6

                    Text {
                        text: bar.gpuUsage
                        color: Theme.text
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "\udb82\udcb6"
                        color: Theme.primary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                    }
                }

                // CPU
                Row {
                    spacing: 6

                    Text {
                        text: bar.cpuUsage
                        color: Theme.text
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "\uf2db"
                        color: Theme.primary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                    }
                }

                // Botón de Selector de Temas
                Text {
                    text: "󰸉"
                    color: root.themeMenuOpen ? Theme.primaryHover : Theme.primary
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 14

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.netMenuOpen = false;
                            root.audioMenuOpen = false;
                            root.micMenuOpen = false;
                            root.sessionMenuOpen = false;
                            root.themeMenuOpen = !root.themeMenuOpen;
                        }
                    }
                }

                // Botón de Apagado / Sesión
                Text {
                    text: "⏻"
                    color: root.sessionMenuOpen ? Theme.primaryHover : Theme.primary
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 14

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.netMenuOpen = false;
                            root.audioMenuOpen = false;
                            root.micMenuOpen = false;
                            root.themeMenuOpen = false;
                            root.sessionMenuOpen = !root.sessionMenuOpen;
                        }
                    }
                }
            }
        }
    }
}
