import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    property bool wifiEnabled: true

    property bool confirmDeleteOpen: false
    property string targetDeleteName: ""
    property string targetDeleteType: "interface"

    property bool ethernetConnected: false
    property var interfacesList: []
    property var wifiList: []
    property var vpnList: []

    property int audioVolumeInt: 0
    property bool audioMuted: false
    property var audioSinksList: []

    property int micVolumeInt: 0
    property bool micMuted: false
    property var audioSourcesList: []

    Process {
        id: initWallpaperProc
        running: true
        command: [
            "sh", "-c",
            "if [ -f ~/.config/quickshell/current_wallpaper.txt ]; then " +
            "  bg=$(cat ~/.config/quickshell/current_wallpaper.txt | tr -d '\\n'); " +
            "else " +
            "  bg=\"$HOME/wallpapers/default.jpeg\"; " +
            "fi; " +
            "pkill swaybg 2>/dev/null || true; " +
            "swaybg -o '*' -i \"$bg\" -m fill &"
        ]
    }

    Process {
        id: ethProc
        running: true
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE device 2>/dev/null | grep '^ethernet:' | grep -q 'connected' && echo 'yes' || echo 'no'"]
        stdout: SplitParser {
            onRead: line => root.ethernetConnected = (line.trim() === "yes")
        }
    }

    Process {
        id: wifiRadioProc
        running: true
        command: ["sh", "-c", "nmcli radio wifi 2>/dev/null"]
        stdout: SplitParser {
            onRead: line => root.wifiEnabled = (line.trim() === "enabled")
        }
    }

    Process {
        id: ifaceScanProc
        running: true
        command: [
            "sh", "-c",
            "nmcli -t -f NAME,TYPE,DEVICE,STATE connection show 2>/dev/null | awk -F: '$2 ~ /ethernet|wireless|802-3-ethernet|802-11-wireless/ { " +
            "  name=$1; " +
            "  type=($2 ~ /wireless|802-11-wireless/ ? \"wifi\" : \"ethernet\"); " +
            "  state=($4 == \"activated\" ? \"connected\" : \"disconnected\"); " +
            "  dev=($3 != \"\" ? $3 : \"waiting\"); " +
            "  print name \"|\" type \"|\" state \"|\" dev \"|\" ($4 == \"activated\" ? \"Connected\" : \"Saved\"); " +
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
                        security: parts[3] || "Open"
                    });
                    root.wifiList = l;
                }
            }
        }
    }

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

    Process {
        id: audioSinksProc
        command: [
            "sh", "-c",
            "def=\"$(pactl get-default-sink 2>/dev/null)\"; pactl list sinks 2>/dev/null | awk -v def=\"$def\" 'BEGIN{RS=\"Sink #\"; FS=\"\\n\"} NR>1 {name=\"\"; desc=\"\"; for(i=1;i<=NF;i++){ if($i ~ /^[[:blank:]]*Name:/){ sub(/^[[:blank:]]*Name:[[:blank:]]*/, \"\", $i); name=$i } if($i ~ /^[[:blank:]]*Description:/){ sub(/^[[:blank:]]*Description:[[:blank:]]*/, \"\", $i); desc=$i } } if(name!=\"\"){ print name \"|\" (desc!=\"\"?desc:name) \"|\" (name==def?1:0) } }'"
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
                        id: parts[0].trim(),
                        name: parts[1].trim(),
                        active: parts[2].trim() === "1"
                    });
                    root.audioSinksList = currentList;
                }
            }
        }
    }

    Process {
        id: audioSourcesProc
        command: [
            "sh", "-c",
            "def=\"$(pactl get-default-source 2>/dev/null)\"; pactl list sources 2>/dev/null | awk -v def=\"$def\" 'BEGIN{RS=\"Source #\"; FS=\"\\n\"} NR>1 {name=\"\"; desc=\"\"; for(i=1;i<=NF;i++){ if($i ~ /^[[:blank:]]*Name:/){ sub(/^[[:blank:]]*Name:[[:blank:]]*/, \"\", $i); name=$i } if($i ~ /^[[:blank:]]*Description:/){ sub(/^[[:blank:]]*Description:[[:blank:]]*/, \"\", $i); desc=$i } } if(name!=\"\" && name !~ /\\.monitor$/){ print name \"|\" (desc!=\"\"?desc:name) \"|\" (name==def?1:0) } }'"
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
                        id: parts[0].trim(),
                        name: parts[1].trim(),
                        active: parts[2].trim() === "1"
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
        audioSinksProc.running = false;
        audioSinksProc.running = true;
    }

    function refreshMic() {
        root.audioSourcesList = [];
        audioSourcesProc.running = false;
        audioSourcesProc.running = true;
    }

    Process {
        id: execCmdProc
        property string targetCmd: ""
        command: ["sh", "-c", targetCmd]
        onExited: root.refreshAllNetworks()
    }

    Process {
        id: editConnProc
        property string targetName: ""
        command: [
            "sh", "-c",
            "uuid=$(nmcli -f NAME,UUID connection show | grep -F '" + targetName + "' | awk '{print $NF}' | head -n1); " +
            "if [ -n \"$uuid\" ]; then " +
            "  nm-connection-editor --edit \"$uuid\" & " +
            "else " +
            "  nm-connection-editor & " +
            "fi"
        ]
    }

    Process {
        id: execAudioCmdProc
        property string targetCmd: ""
        command: ["sh", "-c", targetCmd]
    }

    Process {
        id: execMicCmdProc
        property string targetCmd: ""
        command: ["sh", "-c", targetCmd]
    }

    Process {
        id: addConnProc
        command: ["sh", "-c", "nm-connection-editor --create"]
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
        id: hyprmodProc
        command: ["sh", "-c", "hyprmod"]
    }

    Process {
        id: sessionLogoutProc
        command: ["hyprctl", "dispatch", "exit"]
    }

    Process {
        id: wallpaperExec
        property string targetPath: ""
        command: ["swaybg", "-o", "*", "-i", targetPath, "-m", "fill"]
    }

    Process {
        id: saveWallpaperConfigExec
        property string targetPath: ""
        command: ["sh", "-c", "mkdir -p ~/.config/quickshell && printf '%s' " + JSON.stringify(targetPath) + " > ~/.config/quickshell/current_wallpaper.txt"]
    }

    Process {
        id: extractorExec
        property string targetPath: ""
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/extractor.py", targetPath]
        onExited: {
            Theme.reloadColors();
        }
    }

    // --- DIÁLOGOS MODALES Y MENÚS POR MONITOR ---
    Variants {
        model: Quickshell.screens
        delegate: Component {
            Item {
                id: monitorRoot
                required property var modelData

                property bool netMenuOpen: false
                property bool audioMenuOpen: false
                property bool micMenuOpen: false
                property bool themeMenuOpen: false
                property bool sessionMenuOpen: false
                property bool spotifyMenuOpen: false
                property bool calendarMenuOpen: false
                property var wallpapersList: []
                
                // Variables para la optimización de fondos
                property bool hasScannedWallpapers: false
                property var tempWallpapersList: []

                Process {
                    id: scanWallpapersProc
                    running: monitorRoot.themeMenuOpen && !monitorRoot.hasScannedWallpapers
                    command: ["sh", "-c", "find \"$HOME/wallpapers\" -type f \\( -name '*.jpeg' -o -name '*.jpg' -o -name '*.png' \\) 2>/dev/null"]
                    
                    onStarted: {
                        monitorRoot.tempWallpapersList = [];
                    }

                    stdout: SplitParser {
                        onRead: line => {
                            var path = line.trim();
                            if (path.length > 0) {
                                monitorRoot.tempWallpapersList.push(path);
                            }
                        }
                    }

                    onExited: {
                        monitorRoot.wallpapersList = monitorRoot.tempWallpapersList;
                        monitorRoot.hasScannedWallpapers = true;
                    }
                }

                PanelWindow {
                    id: dismissLayer
                    screen: monitorRoot.modelData
                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }
                    visible: monitorRoot.netMenuOpen || monitorRoot.audioMenuOpen || monitorRoot.micMenuOpen || monitorRoot.themeMenuOpen || monitorRoot.sessionMenuOpen || monitorRoot.spotifyMenuOpen || root.confirmDeleteOpen
                    color: "transparent"

                    WlrLayershell.layer: WlrLayer.Top
                    WlrLayershell.namespace: "quickshell-dismiss-catcher"

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (root.confirmDeleteOpen) {
                                root.confirmDeleteOpen = false;
                            } else {
                                monitorRoot.netMenuOpen = false;
                                monitorRoot.audioMenuOpen = false;
                                monitorRoot.micMenuOpen = false;
                                monitorRoot.themeMenuOpen = false;
                                monitorRoot.sessionMenuOpen = false;
                                monitorRoot.spotifyMenuOpen = false;
                            }
                        }
                    }
                }

                // --- MENÚ DESPLEGABLE: SESIÓN / APAGADO ---
                PanelWindow {
                    id: sessionDropdown
                    screen: monitorRoot.modelData
                    anchors {
                        top: true
                        right: true
                    }
                    width: 200
                    height: 155
                    visible: monitorRoot.sessionMenuOpen
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
                            y: monitorRoot.sessionMenuOpen ? 0 : -sessionMenuContainer.height
                            Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }

                        opacity: monitorRoot.sessionMenuOpen ? 1.0 : 0.0
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
                                        text: "Shut down"
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
                                        monitorRoot.sessionMenuOpen = false;
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
                                        text: "Reboot"
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
                                        monitorRoot.sessionMenuOpen = false;
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
                                        text: "Log out"
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
                                        monitorRoot.sessionMenuOpen = false;
                                        sessionLogoutProc.running = false;
                                        sessionLogoutProc.running = true;
                                    }
                                }
                            }
                        }
                    }
                }

                // --- MENÚ DE CALENDARIO ---
                PanelWindow {
                    id: calendarDropdown
                    screen: monitorRoot.modelData
                    anchors {
                        top: true
                        left: true
                        right: true
                        bottom: true
                    }
                    visible: monitorRoot.calendarMenuOpen
                    color: "transparent"

                    WlrLayershell.layer: WlrLayer.Top
                    WlrLayershell.namespace: "quickshell-bar"

                    Item {
                        anchors.fill: parent
                        MouseArea {
                            anchors.fill: parent
                            onClicked: monitorRoot.calendarMenuOpen = false
                        }

                        Rectangle {
                            id: calendarMenuContainer
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 360
                            height: 395
                            color: Theme.bg
                            border.width: 0
                            bottomLeftRadius: 10
                            bottomRightRadius: 10
                            clip: true

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                onClicked: mouse => mouse.accepted = true
                            }

                            transform: Translate {
                                y: monitorRoot.calendarMenuOpen ? 0 : -calendarMenuContainer.height
                                Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }

                            opacity: monitorRoot.calendarMenuOpen ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 130 } }

                            property var currentDate: new Date()
                            property int displayYear: currentDate.getFullYear()
                            property int displayMonth: currentDate.getMonth()

                            function getMonthName(m) {
                                var names = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
                                return names[m];
                            }

                            function getCalendarDays(year, month) {
                                var firstDay = new Date(year, month, 1).getDay();
                                firstDay = (firstDay + 6) % 7; 
                                var totalDays = new Date(year, month + 1, 0).getDate();
                                var daysArray = [];
                                for (var i = 0; i < firstDay; i++) daysArray.push({ day: "", isCurrent: false });
                                for (var d = 1; d <= totalDays; d++) daysArray.push({ day: d, isCurrent: true });
                                return daysArray;
                            }

                            function isToday(dayNum) {
                                var today = new Date();
                                return dayNum !== "" && dayNum === today.getDate() && displayMonth === today.getMonth() && displayYear === today.getFullYear();
                            }

                            Item {
                                anchors.fill: parent
                                anchors.topMargin: 20
                                anchors.bottomMargin: 20
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                z: 2

                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 12

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: "‹"
                                            color: Theme.primary
                                            font.pixelSize: 20
                                            font.bold: true
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (calendarMenuContainer.displayMonth === 0) {
                                                        calendarMenuContainer.displayMonth = 11;
                                                        calendarMenuContainer.displayYear -= 1;
                                                    } else {
                                                        calendarMenuContainer.displayMonth -= 1;
                                                    }
                                                }
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: calendarMenuContainer.getMonthName(calendarMenuContainer.displayMonth) + " " + calendarMenuContainer.displayYear
                                            color: Theme.text
                                            font.pixelSize: 15
                                            font.bold: true
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: "›"
                                            color: Theme.primary
                                            font.pixelSize: 20
                                            font.bold: true
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (calendarMenuContainer.displayMonth === 11) {
                                                        calendarMenuContainer.displayMonth = 0;
                                                        calendarMenuContainer.displayYear += 1;
                                                    } else {
                                                        calendarMenuContainer.displayMonth += 1;
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // --- CABECERA DE DÍAS DE LA SEMANA (GridLayout de 7 columnas) ---
                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 7
                                        rowSpacing: 0
                                        columnSpacing: 0

                                        Repeater {
                                            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                                            Item {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 24
                                                Layout.preferredWidth: (parent.width / 7)

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData 
                                                    color: Theme.subtext
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                }
                                            }
                                        }
                                    }

                                    // --- GRILLA DE DÍAS ---
                                    GridView {
                                        id: calendarGrid
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        model: calendarMenuContainer.getCalendarDays(calendarMenuContainer.displayYear, calendarMenuContainer.displayMonth)
                                        cellWidth: width / 7
                                        cellHeight: height / 6
                                        interactive: false

                                        delegate: Item {
                                            required property var modelData
                                            width: GridView.view.cellWidth
                                            height: GridView.view.cellHeight

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 36
                                                height: 36
                                                radius: 8
                                                color: calendarMenuContainer.isToday(modelData.day) ? Theme.primary : "transparent"
                                                border.width: modelData.day !== "" ? 1 : 0
                                                border.color: calendarMenuContainer.isToday(modelData.day) ? Theme.primary : Theme.border

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.day
                                                    color: calendarMenuContainer.isToday(modelData.day) ? Theme.bg : Theme.text
                                                    font.pixelSize: 13
                                                    font.bold: calendarMenuContainer.isToday(modelData.day) || modelData.day !== ""
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // --- MENÚ DE WALLPAPERS (3 COLUMNAS, 540x480) ---
                PanelWindow {
                    id: themeDropdown
                    screen: monitorRoot.modelData
                    anchors {
                        top: true
                        right: true
                    }
                    width: 540
                    height: 480
                    visible: monitorRoot.themeMenuOpen
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
                            y: monitorRoot.themeMenuOpen ? 0 : -themeMenuContainer.height
                            Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }

                        opacity: monitorRoot.themeMenuOpen ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 130 } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12

                            Text {
                                text: "Select Wallpaper"
                                color: Theme.text
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 14
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }

                            GridView {
                                id: wallGrid
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                model: monitorRoot.wallpapersList
                                cellWidth: Math.floor(width / 3)
                                cellHeight: Math.round((cellWidth - 12) * 9 / 16) + 12
                                clip: true

                                delegate: Item {
                                    required property var modelData
                                    width: GridView.view.cellWidth
                                    height: GridView.view.cellHeight

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        radius: 6
                                        color: Theme.surface
                                        border.color: Theme.border
                                        border.width: 1
                                        clip: true

                                        Image {
                                            anchors.fill: parent
                                            anchors.margins: 2
                                            source: "file://" + modelData
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            sourceSize.width: 180
                                            sourceSize.height: 100
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                wallpaperExec.targetPath = modelData;
                                                wallpaperExec.running = false;
                                                wallpaperExec.running = true;

                                                saveWallpaperConfigExec.targetPath = modelData;
                                                saveWallpaperConfigExec.running = false;
                                                saveWallpaperConfigExec.running = true;

                                                extractorExec.targetPath = modelData;
                                                extractorExec.running = false;
                                                extractorExec.running = true;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // 2. Menú de Red
                PanelWindow {
                    id: networkDropdown
                    screen: monitorRoot.modelData
                    anchors {
                        top: true
                        right: true
                    }
                    width: 360
                    height: 490
                    visible: monitorRoot.netMenuOpen
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
                            y: monitorRoot.netMenuOpen ? 0 : -menuContainer.height
                            Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }

                        opacity: monitorRoot.netMenuOpen ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 130 } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: "Network Connections"
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
                                            monitorRoot.netMenuOpen = false;
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
                                    text: "Interfaces & Profiles"
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
                                                text: modelData.type === "ethernet" ? "󰈀" : "󰤨"
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
                                                        text: "(" + modelData.connection + ")"
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
                                                    color: Theme.primary
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 13
                                                }

                                                MouseArea {
                                                    id: editMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        monitorRoot.netMenuOpen = false;
                                                        editConnProc.targetName = modelData.device;
                                                        editConnProc.running = false;
                                                        editConnProc.running = true;
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
                                                execCmdProc.targetCmd = "nmcli connection up id '" + modelData.device + "'";
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
                                    text: "Wi-Fi Networks"
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
                                            text: modelData.security !== "Open" && modelData.security !== "" ? "󰤪" : "󰤨"
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
                                            monitorRoot.netMenuOpen = false;
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
                                text: "VPN / WireGuard Tunnels"
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
                                                text: modelData.active ? "Active" : "Connect"
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

                // 3. Menú de Salida de Audio
                PanelWindow {
                    id: audioDropdown
                    screen: monitorRoot.modelData
                    anchors {
                        top: true
                        right: true
                    }
                    width: 340
                    height: 380
                    visible: monitorRoot.audioMenuOpen
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
                            y: monitorRoot.audioMenuOpen ? 0 : -audioMenuContainer.height
                            Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }

                        opacity: monitorRoot.audioMenuOpen ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 130 } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: "Output Control"
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
                                            monitorRoot.audioMenuOpen = false;
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
                                            text: root.audioMuted ? "󰝟" : (root.audioVolumeInt === 0 ? "󰕿" : (root.audioVolumeInt < 50 ? "󰕿" : "󰕾"))
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
                                            text: "Output Volume"
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
                                text: "Output Devices"
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
                                    color: modelData.active ? Theme.surfaceAlt : (sinkMouse.containsMouse ? Theme.surface : "transparent")
                                    border.color: modelData.active ? Theme.primary : "transparent"
                                    border.width: modelData.active ? 1 : 0
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

                // 4. Menú de Entrada de Audio / Micrófono
                PanelWindow {
                    id: micDropdown
                    screen: monitorRoot.modelData
                    anchors {
                        top: true
                        right: true
                    }
                    width: 340
                    height: 380
                    visible: monitorRoot.micMenuOpen
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
                            y: monitorRoot.micMenuOpen ? 0 : -micMenuContainer.height
                            Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }

                        opacity: monitorRoot.micMenuOpen ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 130 } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: "Input Control"
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
                                            monitorRoot.micMenuOpen = false;
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
                                            text: "Input Gain"
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
                                text: "Input Devices"
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
                                    color: modelData.active ? Theme.surfaceAlt : (sinkMouse.containsMouse ? Theme.surface : "transparent")
                                    border.color: modelData.active ? Theme.primary : "transparent"
                                    border.width: modelData.active ? 1 : 0
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

                // 5. Barra Principal de este monitor específico
                PanelWindow {
                    id: bar
                    screen: monitorRoot.modelData

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
                        command: ["sh", "-c", "if which nvidia-smi >/dev/null 2>&1; then nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -n1 | awk '{print $1\"%\"}'; elif [ -f /sys/class/drm/card1/device/gpu_busy_percent ]; then cat /sys/class/drm/card1/device/gpu_busy_percent | awk '{print $1\"%\"}'; else echo '0%'; fi"]
                        stdout: SplitParser {
                            onRead: line => {
                                var val = line.trim();
                                if (val.length > 0) bar.gpuUsage = val.includes("%") ? val : val + "%";
                            }
                        }
                    }

                    property string fpsValue: "0"
                    Process {
                        id: fpsProc
                        command: ["sh", "-c", "[ -f /tmp/quickshell_fps.txt ] && cat /tmp/quickshell_fps.txt || echo '0'"]
                        stdout: SplitParser {
                            onRead: line => {
                                var f = line.trim();
                                if (f.length > 0) bar.fpsValue = f;
                            }
                        }
                    }

                    // --- METADATOS DE SPOTIFY ---
                    property string spotifyTrack: ""
                    property bool spotifyPlaying: false
                    property bool spotifyMenuOpen: false
                    property string spotifyArtUrl: ""
                    property real spotifyPosition: 0
                    property real spotifyLength: 0
                    property string spotifyLoopMode: "None"
                    property bool spotifyShuffle: false

                    Process {
                        id: spotifyControlProc
                        property string targetCmd: ""
                        command: ["sh", "-c", targetCmd]
                        onExited: (exitCode, exitStatus) => {
                            spotifyModesProc.running = false;
                            spotifyModesProc.running = true;
                        }
                    }
                    Process {
                        id: spotifyArtProc
                        command: ["sh", "-c", "playerctl -p spotify metadata mpris:artUrl 2>/dev/null || true"]
                        stdout: SplitParser { onRead: line => bar.spotifyArtUrl = line.trim() }
                    }
                    Process {
                        id: spotifyModesProc
                        command: ["sh", "-c", "s=$(playerctl -p spotify shuffle 2>/dev/null || echo Off); l=$(playerctl -p spotify loop 2>/dev/null || echo None); printf '%s|%s\\n' \"$s\" \"$l\""]
                        stdout: SplitParser {
                            onRead: line => {
                                var modes = line.trim().split("|");
                                if (modes.length >= 2) {
                                    bar.spotifyShuffle = modes[0].toLowerCase() === "on" || modes[0].toLowerCase() === "true";
                                    var loop = modes[1].trim().toLowerCase();
                                    bar.spotifyLoopMode = loop === "track" ? "Track" : (loop === "playlist" ? "Playlist" : "None");
                                }
                            }
                        }
                    }
                    Process {
                        id: spotifyPositionProc
                        command: ["sh", "-c", "p=$(playerctl -p spotify position 2>/dev/null || echo 0); d=$(playerctl -p spotify metadata mpris:length 2>/dev/null || echo 0); printf \"%s|%s\\n\" \"$p\" \"$((d/1000000))\""]
                        stdout: SplitParser {
                            onRead: line => {
                                var values = line.trim().split("|")
                                if (values.length >= 2) { bar.spotifyPosition = parseFloat(values[0]) || 0; bar.spotifyLength = parseFloat(values[1]) || 0 }
                            }
                        }
                    }

                    Process {
                        id: spotifyProc
                        command: ["sh", "-c", "playerctl -p spotify metadata --format '{{status}}|{{title}} — {{artist}}' 2>/dev/null || true"]
                        stdout: SplitParser {
                            onRead: line => {
                                var value = line.trim();
                                var splitAt = value.indexOf("|");
                                if (splitAt >= 0) {
                                    bar.spotifyPlaying = value.substring(0, splitAt).toLowerCase() === "playing";
                                    bar.spotifyTrack = value.substring(splitAt + 1).trim();
                                    spotifyArtProc.running = false;
                                    spotifyArtProc.running = true;
                                } else {
                                    bar.spotifyPlaying = false;
                                    bar.spotifyTrack = "";
                                }
                            }
                        }
                    }

                    Timer {
                        interval: 1500
                        running: true
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: {
                            spotifyProc.running = false;
                            spotifyProc.running = true;
                            spotifyPositionProc.running = false;
                            spotifyPositionProc.running = true;
                            spotifyModesProc.running = false;
                            spotifyModesProc.running = true;
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
                            if (!fpsProc.running) fpsProc.running = true;
                            if (!ethProc.running) ethProc.running = true;
                        }
                    }

                    Process {
                        id: appMenuProc
                        command: ["sh", "-c", "pkill rofi || rofi -show drun"]
                    }

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 4

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

                            // --- SPOTIFY: canción actual + visualizador animado ---
                            Rectangle {
                                id: spotifyWidget
                                visible: bar.spotifyTrack.length > 0
                                height: 24
                                Layout.preferredWidth: visible ? spotifyRow.implicitWidth + 14 : 0
                                color: Theme.surface
                                border.width: 0
                                radius: 6
                                clip: true

                                RowLayout {
                                    id: spotifyRow
                                    anchors.fill: parent
                                    anchors.leftMargin: 7
                                    anchors.rightMargin: 7
                                    spacing: 6

                                    Text {
                                        text: "󰓇"
                                        color: Theme.primary
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 12
                                    }

                                    Text {
                                        text: bar.spotifyTrack
                                        color: Theme.text
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: 220
                                        Layout.preferredWidth: Math.min(implicitWidth, 220)
                                    }

                                    Row {
                                        id: spotifyVisualizer
                                        spacing: 2
                                        Layout.alignment: Qt.AlignVCenter

                                        Repeater {
                                            model: [0, 1, 2, 3, 4]

                                            delegate: Rectangle {
                                                required property int modelData
                                                width: 3
                                                height: 5
                                                radius: 1.5
                                                color: Theme.primary
                                                anchors.verticalCenter: parent.verticalCenter

                                                SequentialAnimation on height {
                                                    running: bar.spotifyPlaying
                                                    loops: Animation.Infinite
                                                    NumberAnimation {
                                                        to: [9, 6, 11, 7, 10][modelData]
                                                        duration: 180 + modelData * 65
                                                        easing.type: Easing.InOutSine
                                                    }
                                                    NumberAnimation {
                                                        to: [4, 8, 5, 10, 4][modelData]
                                                        duration: 210 + modelData * 45
                                                        easing.type: Easing.InOutSine
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: monitorRoot.spotifyMenuOpen = !monitorRoot.spotifyMenuOpen
                                }

                                Behavior on Layout.preferredWidth {
                                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        // --- MENÚ DE CONTROLES DE SPOTIFY ---
                        PanelWindow {
                            id: spotifyDropdown
                            screen: monitorRoot.modelData
                            anchors { top: true; left: true }
                            width: 280
                            height: 250
                            visible: monitorRoot.spotifyMenuOpen
                            color: "transparent"
                            WlrLayershell.layer: WlrLayer.Overlay
                            WlrLayershell.namespace: "quickshell-bar"
                            Rectangle {
                                anchors.fill: parent
                                color: Theme.bg
                                radius: 10
                                border.width: 0
                                // Cuadrar las esquinas superiores del menú.
                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 10
                                    color: Theme.bg
                                }
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 9
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        Image {
                                            source: bar.spotifyArtUrl
                                            Layout.preferredWidth: 64
                                            Layout.preferredHeight: 64
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            sourceSize.width: 128
                                            sourceSize.height: 128
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            Text {
                                                text: "Spotify"
                                                color: Theme.primary
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 10
                                                font.bold: true
                                            }
                                            Text {
                                                text: bar.spotifyTrack || "No hay canción"
                                                color: Theme.text
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 10
                                                wrapMode: Text.Wrap
                                                maximumLineCount: 3
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: bar.spotifyPlaying ? "Reproduciendo" : "En pausa"
                                                color: Theme.subtext
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 9
                                            }
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        Rectangle {
                                            id: spotifySeekTrack
                                            Layout.fillWidth: true
                                            height: 5
                                            radius: 3
                                            color: Theme.surfaceAlt
                                            Rectangle {
                                                width: bar.spotifyLength > 0 ? Math.max(0, Math.min(parent.width, parent.width * bar.spotifyPosition / bar.spotifyLength)) : 0
                                                height: parent.height
                                                radius: 3
                                                color: Theme.primary
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: mouse => {
                                                    if (bar.spotifyLength > 0) {
                                                        var seekTo = Math.max(0, Math.min(bar.spotifyLength, mouse.x / width * bar.spotifyLength))
                                                        spotifyControlProc.targetCmd = "playerctl -p spotify position " + seekTo.toFixed(2)
                                                        spotifyControlProc.running = false
                                                        spotifyControlProc.running = true
                                                        bar.spotifyPosition = seekTo
                                                    }
                                                }
                                            }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: Math.floor(bar.spotifyPosition / 60) + ":" + ("0" + Math.floor(bar.spotifyPosition % 60)).slice(-2)
                                                color: Theme.subtext
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 8
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: "-" + Math.floor(Math.max(0, bar.spotifyLength - bar.spotifyPosition) / 60) + ":" + ("0" + Math.floor(Math.max(0, bar.spotifyLength - bar.spotifyPosition) % 60)).slice(-2)
                                                color: Theme.subtext
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 8
                                            }
                                        }
                                    }
                                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5
                                        // Bucle de playlist, anterior, reproducir/pausa, siguiente, repetir.
                                        Repeater {
                                            model: [
                                                { label: "⇄", action: "shuffle" },
                                                { label: "󰒮", action: "previous" },
                                                { label: bar.spotifyPlaying ? "󰏤" : "󰐊", action: "play-pause" },
                                                { label: "󰒭", action: "next" },
                                                { label: "󰑖", action: "repeat" }
                                            ]
                                            delegate: Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                height: 34
                                                radius: 6
                                                color: spotifyControlMouse.containsMouse ? Theme.surfaceAlt : Theme.surface
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.label
                                                    color: ((modelData.action === "shuffle" && bar.spotifyShuffle) || (modelData.action === "repeat" && bar.spotifyLoopMode !== "None")) ? "#1DB954" : Theme.text
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 15
                                                }
                                                Text {
                                                    visible: modelData.action === "repeat" && bar.spotifyLoopMode === "Track"
                                                    text: "1"
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.rightMargin: 7
                                                    anchors.topMargin: 5
                                                    color: "#1DB954"
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 8
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    id: spotifyControlMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (modelData.action === "shuffle") {
                                                            // Actualización optimista para que la interfaz responda al instante.
                                                            var enableShuffle = !bar.spotifyShuffle;
                                                            bar.spotifyShuffle = enableShuffle;
                                                            spotifyControlProc.targetCmd = "playerctl -p spotify shuffle " + (enableShuffle ? "On" : "Off")
                                                        } else if (modelData.action === "repeat") {
                                                            // Orden de Spotify: repetir playlist, repetir canción (1), desactivado.
                                                            var nextLoop = bar.spotifyLoopMode === "None" ? "Playlist" : (bar.spotifyLoopMode === "Playlist" ? "Track" : "None")
                                                            bar.spotifyLoopMode = nextLoop;
                                                            spotifyControlProc.targetCmd = "playerctl -p spotify loop " + nextLoop
                                                        } else {
                                                            spotifyControlProc.targetCmd = "playerctl -p spotify " + modelData.action
                                                        }
                                                        // No reiniciar un proceso activo: cambiar el comando y lanzar al terminar.
                                                        spotifyControlProc.running = false
                                                        spotifyControlProc.running = true
                                                        // El estado real se verifica al terminar el comando.
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // --- CENTRO ---
                        Item {
                            anchors.centerIn: parent
                            width: centerLayout.implicitWidth
                            height: parent.height

                            RowLayout {
                                id: centerLayout
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

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    monitorRoot.netMenuOpen = false;
                                    monitorRoot.audioMenuOpen = false;
                                    monitorRoot.micMenuOpen = false;
                                    monitorRoot.themeMenuOpen = false;
                                    monitorRoot.sessionMenuOpen = false;
                                    monitorRoot.calendarMenuOpen = !monitorRoot.calendarMenuOpen;
                                }
                            }
                        }

                        // --- DERECHA ---
                        RowLayout {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            // 1. MÓDULO DE HARDWARE (FPS, GPU, CPU)
                            Rectangle {
                                id: hwRect
                                height: 24
                                Layout.preferredWidth: hwMouse.containsMouse ? hwLayout.implicitWidth + 16 : hwLayout.implicitWidth + 12
                                color: hwMouse.containsMouse ? Theme.surfaceAlt : Theme.surface
                                border.color: hwMouse.containsMouse ? Theme.primary : Theme.border
                                border.width: 1
                                radius: 6
                                clip: true
                                visible: parseInt(bar.fpsValue) > 0

                                Behavior on Layout.preferredWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                RowLayout {
                                    id: hwLayout
                                    anchors.centerIn: parent
                                    spacing: hwMouse.containsMouse ? 10 : 6
                                    Behavior on spacing { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                                    // FPS
                                    Row {
                                        spacing: 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        Item {
                                            width: hwMouse.containsMouse ? fpsTxt.implicitWidth + 4 : 0
                                            height: fpsTxt.implicitHeight
                                            clip: true
                                            anchors.verticalCenter: parent.verticalCenter
                                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                            Text {
                                                id: fpsTxt
                                                text: bar.fpsValue
                                                color: Theme.text
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 10
                                                opacity: hwMouse.containsMouse ? 1.0 : 0.0
                                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                            }
                                        }
                                        Text {
                                            text: "󰓅"
                                            color: Theme.primary
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    // GPU
                                    Row {
                                        spacing: 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        Item {
                                            width: hwMouse.containsMouse ? gpuTxt.implicitWidth + 4 : 0
                                            height: gpuTxt.implicitHeight
                                            clip: true
                                            anchors.verticalCenter: parent.verticalCenter
                                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                            Text {
                                                id: gpuTxt
                                                text: bar.gpuUsage
                                                color: Theme.text
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 10
                                                opacity: hwMouse.containsMouse ? 1.0 : 0.0
                                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                            }
                                        }
                                        Text {
                                            text: "\udb82\udcb6"
                                            color: Theme.primary
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    // CPU
                                    Row {
                                        spacing: 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        Item {
                                            width: hwMouse.containsMouse ? cpuTxt.implicitWidth + 4 : 0
                                            height: cpuTxt.implicitHeight
                                            clip: true
                                            anchors.verticalCenter: parent.verticalCenter
                                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                            Text {
                                                id: cpuTxt
                                                text: bar.cpuUsage
                                                color: Theme.text
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 10
                                                opacity: hwMouse.containsMouse ? 1.0 : 0.0
                                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                            }
                                        }
                                        Text {
                                            text: "\uf2db"
                                            color: Theme.primary
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                MouseArea {
                                    id: hwMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                }
                            }
                            // 1.5 BANDEJA DE APLICACIONES EN SEGUNDO PLANO (SystemTray)
                            Rectangle {
                                id: trayRect
                                height: 24
                                visible: SystemTray.items.values.length > 0
                                Layout.preferredWidth: visible ? trayRow.implicitWidth + 12 : 0
                                color: Theme.surface
                                border.color: Theme.border
                                border.width: 1
                                radius: 6
                                clip: true

                                Behavior on Layout.preferredWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                                Row {
                                    id: trayRow
                                    spacing: 6
                                    anchors.centerIn: parent

                                    Repeater {
                                        model: SystemTray.items.values

                                        delegate: Rectangle {
                                            required property var modelData
                                            width: 18
                                            height: 18
                                            radius: 4
                                            color: trayItemMouse.containsMouse ? Theme.surfaceAlt : "transparent"

                                            Image {
                                                anchors.centerIn: parent
                                                width: 14
                                                height: 14
                                                source: modelData.icon
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                            }

                                            MouseArea {
                                                id: trayItemMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                                                onClicked: mouse => {
                                                    if (mouse.button === Qt.LeftButton) {
                                                        modelData.activate();
                                                    } else if (mouse.button === Qt.MiddleButton) {
                                                        modelData.secondaryActivate();
                                                    } else if (mouse.button === Qt.RightButton) {
                                                        if (modelData.hasMenu) {
                                                            var pos = trayItemMouse.mapToItem(bar.contentItem, 0, trayRect.height);
                                                            modelData.display(bar, pos.x, pos.y);
                                                        } else {
                                                            modelData.activate();
                                                        }
                                                    }
                                                }

                                                onWheel: wheel => {
                                                    modelData.scroll(wheel.angleDelta.y, false);
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // 2. MÓDULO DE RED (Velocidades + Icono perfectamente centrado)
                            Rectangle {
                                id: netRect
                                property bool expanded: netMouse.containsMouse || monitorRoot.netMenuOpen
                                height: 24
                                Layout.preferredWidth: expanded ? netContentRow.implicitWidth + 10 : 28
                                color: expanded ? Theme.surfaceAlt : Theme.surface
                                border.color: netMouse.containsMouse ? Theme.primary : Theme.border
                                border.width: 1
                                radius: 6
                                clip: true

                                Behavior on Layout.preferredWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                Row {
                                    id: netContentRow
                                    spacing: 0
                                    anchors.centerIn: parent

                                    Item {
                                        width: netRect.expanded ? netSpeedsRow.implicitWidth + 6 : 0
                                        height: 24
                                        clip: true
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                                        Row {
                                            id: netSpeedsRow
                                            spacing: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            anchors.leftMargin: 6
                                            opacity: netRect.expanded ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 150 } }

                                            Row {
                                                spacing: 3
                                                anchors.verticalCenter: parent.verticalCenter
                                                Text {
                                                    text: "↓"
                                                    color: Theme.primary
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                }
                                                Text {
                                                    text: bar.downSpeed
                                                    color: Theme.text
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 10
                                                }
                                            }

                                            Row {
                                                spacing: 3
                                                anchors.verticalCenter: parent.verticalCenter
                                                Text {
                                                    text: "↑"
                                                    color: Theme.primary
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                }
                                                Text {
                                                    text: bar.upSpeed
                                                    color: Theme.text
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 10
                                                }
                                            }
                                        }
                                    }

                                    // Contenedor fijo de 28x24 para centrar el icono de forma exacta
                                    Item {
                                        width: 28
                                        height: 24
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            // compensación de -1px horizontal para glifos Nerd Font de doble ancho
                                            anchors.horizontalCenterOffset: -1.8
                                            text: root.ethernetConnected ? "󰈀" : "󰤨"
                                            color: monitorRoot.netMenuOpen ? Theme.primaryHover : Theme.primary
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 13
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }

                                MouseArea {
                                    id: netMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        monitorRoot.audioMenuOpen = false;
                                        monitorRoot.micMenuOpen = false;
                                        monitorRoot.themeMenuOpen = false;
                                        monitorRoot.sessionMenuOpen = false;
                                        monitorRoot.calendarMenuOpen = false;
                                        monitorRoot.netMenuOpen = !monitorRoot.netMenuOpen;
                                        if (monitorRoot.netMenuOpen) {
                                            root.refreshAllNetworks();
                                        }
                                    }
                                }
                            }
                            // 3. MÓDULO DE AUDIO (Volumen + Icono)
                            Rectangle {
                                id: audioRect
                                property bool expanded: audioMouse.containsMouse || monitorRoot.audioMenuOpen
                                height: 24
                                Layout.preferredWidth: expanded ? audioRow.implicitWidth + 16 : 28
                                color: expanded ? Theme.surfaceAlt : Theme.surface
                                border.color: audioMouse.containsMouse ? Theme.primary : Theme.border
                                border.width: 1
                                radius: 6
                                clip: true
                                Layout.alignment: Qt.AlignVCenter

                                Behavior on Layout.preferredWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                Row {
                                    id: audioRow
                                    spacing: 0
                                    anchors.centerIn: parent

                                    Item {
                                        width: audioRect.expanded ? audioVolTxt.implicitWidth + 6 : 0
                                        height: audioVolTxt.implicitHeight
                                        clip: true
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                                        Text {
                                            id: audioVolTxt
                                            text: root.audioMuted ? "0%" : root.audioVolumeInt + "%"
                                            color: Theme.text
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            opacity: audioRect.expanded ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 150 } }
                                        }
                                    }

                                    Text {
                                        text: root.audioMuted ? "󰝟" : (root.audioVolumeInt === 0 ? "󰕿" : (root.audioVolumeInt < 50 ? "󰖀" : "󰕾"))
                                        color: monitorRoot.audioMenuOpen ? Theme.primaryHover : (root.audioMuted ? Theme.danger : Theme.primary)
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    id: audioMouse
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
                                            monitorRoot.netMenuOpen = false;
                                            monitorRoot.micMenuOpen = false;
                                            monitorRoot.themeMenuOpen = false;
                                            monitorRoot.sessionMenuOpen = false;
                                            monitorRoot.calendarMenuOpen = false;
                                            monitorRoot.audioMenuOpen = !monitorRoot.audioMenuOpen;
                                            if (monitorRoot.audioMenuOpen) {
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

                            // 4. MÓDULO DE MICRÓFONO (Ganancia + Icono)
                            Rectangle {
                                id: micRect
                                property bool expanded: micMouse.containsMouse || monitorRoot.micMenuOpen
                                height: 24
                                Layout.preferredWidth: expanded ? micRow.implicitWidth + 16 : 28
                                color: expanded ? Theme.surfaceAlt : Theme.surface
                                border.color: micMouse.containsMouse ? Theme.primary : Theme.border
                                border.width: 1
                                radius: 6
                                clip: true
                                Layout.alignment: Qt.AlignVCenter

                                Behavior on Layout.preferredWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                Row {
                                    id: micRow
                                    spacing: 0
                                    anchors.centerIn: parent

                                    Item {
                                        width: micRect.expanded ? micVolTxt.implicitWidth + 6 : 0
                                        height: micVolTxt.implicitHeight
                                        clip: true
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                                        Text {
                                            id: micVolTxt
                                            text: root.micMuted ? "0%" : root.micVolumeInt + "%"
                                            color: Theme.text
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            opacity: micRect.expanded ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 150 } }
                                        }
                                    }

                                    Text {
                                        text: root.micMuted ? "󰍭" : "󰍬"
                                        color: monitorRoot.micMenuOpen ? Theme.primaryHover : (root.micMuted ? Theme.danger : Theme.primary)
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    id: micMouse
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
                                            monitorRoot.netMenuOpen = false;
                                            monitorRoot.audioMenuOpen = false;
                                            monitorRoot.themeMenuOpen = false;
                                            monitorRoot.sessionMenuOpen = false;
                                            monitorRoot.calendarMenuOpen = false;
                                            monitorRoot.micMenuOpen = !monitorRoot.micMenuOpen;
                                            if (monitorRoot.micMenuOpen) {
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

                            // 5. WALLPAPERS
                            Rectangle {
                                height: 24
                                width: 28
                                color: monitorRoot.themeMenuOpen || themeMouse.containsMouse ? Theme.surfaceAlt : Theme.surface
                                border.color: themeMouse.containsMouse ? Theme.primary : Theme.border
                                border.width: 1
                                radius: 6

                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                Text {
                                    text: "󰸉"
                                    color: monitorRoot.themeMenuOpen ? Theme.primaryHover : Theme.primary
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                    anchors.centerIn: parent
                                }

                                MouseArea {
                                    id: themeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        monitorRoot.netMenuOpen = false;
                                        monitorRoot.audioMenuOpen = false;
                                        monitorRoot.micMenuOpen = false;
                                        monitorRoot.sessionMenuOpen = false;
                                        monitorRoot.calendarMenuOpen = false;
                                        monitorRoot.themeMenuOpen = !monitorRoot.themeMenuOpen;
                                    }
                                }
                            }

                            // 6. HYPRMOD
                            Rectangle {
                                height: 24
                                width: 28
                                color: hyprmodMouse.containsMouse ? Theme.surfaceAlt : Theme.surface
                                border.color: hyprmodMouse.containsMouse ? Theme.primary : Theme.border
                                border.width: 1
                                radius: 6

                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                Text {
                                    text: "󰒓"
                                    color: Theme.primary
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                    anchors.centerIn: parent
                                }

                                MouseArea {
                                    id: hyprmodMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        hyprmodProc.running = false;
                                        hyprmodProc.running = true;
                                    }
                                }
                            }

                            // 7. SESIÓN
                            Rectangle {
                                height: 24
                                width: 28
                                color: monitorRoot.sessionMenuOpen || sessionMouse.containsMouse ? Theme.surfaceAlt : Theme.surface
                                border.color: sessionMouse.containsMouse ? Theme.primary : Theme.border
                                border.width: 1
                                radius: 6

                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                Text {
                                    text: "⏻"
                                    color: monitorRoot.sessionMenuOpen ? Theme.primaryHover : Theme.primary
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                    anchors.centerIn: parent
                                }

                                MouseArea {
                                    id: sessionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        monitorRoot.netMenuOpen = false;
                                        monitorRoot.audioMenuOpen = false;
                                        monitorRoot.micMenuOpen = false;
                                        monitorRoot.themeMenuOpen = false;
                                        monitorRoot.calendarMenuOpen = false;
                                        monitorRoot.sessionMenuOpen = !monitorRoot.sessionMenuOpen;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
