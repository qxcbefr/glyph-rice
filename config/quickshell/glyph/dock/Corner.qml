import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs
import qs.components

// tray: the bottom right corner, a second pill beside the dock -- the services first (tray icons of the apps that
// have one, then network, bluetooth, sound, battery), the clock last. A click -- quick settings, the panel from Super+A,
// as the bar's tray does. The strip under the dock is already reserved, so this pill takes no zone of its own
Scope {
    id: root

    signal quickClicked

    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var bat: UPower.displayDevice

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // a service's icon. Quickshell already resolves most of them to a url -- a pixmap the app handed over
    // (image://qspixmap/...), a themed icon with its theme path (image://icon/name?path=...), or a file; a bare name is looked
    // up in the theme, and nothing at all falls back to the app's desktop entry. Empty -- the letter of what it calls itself
    function icon(it) {
        const i = it.icon ?? "";
        if (!i) {
            const e = DesktopEntries.heuristicLookup(it.id ?? "") ?? DesktopEntries.heuristicLookup(it.title ?? "");
            return e?.icon ? Quickshell.iconPath(e.icon, true) : "";
        }
        if (i.startsWith("image:") || i.startsWith("file:")) return i;
        if (i.startsWith("/")) return "file://" + i;
        const p = Quickshell.iconPath(i, true);
        if (p) return p;
        const e = DesktopEntries.heuristicLookup(it.id ?? "") ?? DesktopEntries.heuristicLookup(it.title ?? "");
        return e?.icon ? Quickshell.iconPath(e.icon, true) : "";
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property var modelData

            screen: modelData
            anchors { bottom: true; right: true }
            margins.right: 14
            exclusionMode: ExclusionMode.Ignore
            implicitWidth: Math.ceil(pill.width * Theme.s)
            implicitHeight: Math.ceil((pill.height + 14) * Theme.s)
            color: "transparent"
            WlrLayershell.namespace: "glyph-tray"

            Stage {
                Rectangle {
                    id: pill
                    y: 0
                    width: row.width + 36
                    height: 84
                    radius: 42
                    color: Theme.s1
                    border { width: 1; color: Theme.s2 }

                    Row {
                        id: row
                        x: 18
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        // services: an app that put an icon in the tray. Click -- its own action, right click -- its menu
                        Repeater {
                            model: SystemTray.items.values

                            Item {
                                id: svc

                                required property var modelData
                                readonly property string src: root.icon(modelData)

                                width: 34
                                height: 56 // as tall as the row: a shorter item would be pinned to its top, not centered

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 34
                                    height: 34
                                    radius: 17
                                    color: svcHot.hovered ? Theme.s3 : Theme.s2
                                    Behavior on color { ColorAnimation { duration: Theme.t } }

                                    // the app's own icon as it hands it over, crisp and at 2x, drained of color so nothing but the
                                    // rice's red shows: a masked dot icon needs a big shape -- at 22 px the dots would be the icon
                                    Image {
                                        id: spic
                                        anchors.centerIn: parent
                                        width: 22
                                        height: 22
                                        visible: false
                                        source: svc.src
                                        sourceSize: Qt.size(44, 44)
                                        asynchronous: true
                                        retainWhileLoading: true
                                    }
                                    MultiEffect {
                                        anchors.fill: spic
                                        visible: spic.status === Image.Ready
                                        source: spic
                                        saturation: -1
                                    }
                                    // no icon at all -- the first letter, the circle is never empty
                                    Text {
                                        visible: spic.status !== Image.Ready
                                        anchors.centerIn: parent
                                        text: (svc.modelData.title || svc.modelData.id || "?").charAt(0).toUpperCase()
                                        font { family: Theme.dot; pixelSize: 16; weight: Font.Black; variableAxes: ({ "ROND": 100, "wght": 900 }) }
                                        color: Theme.fg
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.RightButton || svc.modelData.onlyMenu) svc.modelData.display(win, 0, 0);
                                        else svc.modelData.activate();
                                    }
                                }
                                HoverHandler { id: svcHot }
                            }
                        }

                        // divider: a line of dots, when there is a service to divide
                        Item {
                            width: 10
                            height: 56
                            visible: SystemTray.items.values.length > 0
                            Image {
                                anchors.centerIn: parent
                                width: 4
                                height: 40
                                fillMode: Image.TileVertically
                                source: "data:image/svg+xml," + encodeURIComponent(
                                    `<svg xmlns="http://www.w3.org/2000/svg" width="4" height="10">
                                        <circle cx="2" cy="5" r="1.5" fill="#${Theme.hex(Theme.s3)}"/></svg>`)
                            }
                        }

                        // the system's own: network, bluetooth, sound (wheel -- volume), battery. Click -- quick settings
                        Item {
                            width: 30
                            height: 56
                            Icon {
                                anchors.centerIn: parent
                                text: Networking.wifiEnabled ? "\u{F05A9}" : "\u{F05AA}"
                                color: root.wifi?.connected ? Theme.fg : Theme.grey
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.quickClicked() }
                        }
                        Item {
                            width: 30
                            height: 56
                            Icon {
                                anchors.centerIn: parent
                                text: Bluetooth.defaultAdapter?.enabled ? "\u{F00AF}" : "\u{F00B2}"
                                color: Bluetooth.devices.values.some(d => d.connected) ? Theme.fg : Theme.grey
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.quickClicked() }
                        }
                        Item {
                            width: 30
                            height: 56
                            Icon {
                                anchors.centerIn: parent
                                text: Sys.muted ? "\u{F075F}" : "\u{F057E}"
                                color: Sys.muted ? Theme.grey : Theme.fg
                            }
                            WheelHandler { onWheel: e => Sys.setVol(Sys.vol + (e.angleDelta.y > 0 ? 0.05 : -0.05)) }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.quickClicked() }
                        }
                        // a laptop -- the charge as a capsule filling to the right, red when it is low. Red -- the one accent of the rice
                        Item {
                            width: 34
                            height: 56
                            visible: root.bat.isLaptopBattery
                            Rectangle {
                                anchors.centerIn: parent
                                width: 24
                                height: 12
                                radius: 6
                                color: "transparent"
                                border { width: 1.2; color: Theme.grey }
                                Rectangle {
                                    x: 2.5
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(0, (parent.width - 5) * root.bat.percentage)
                                    height: parent.height - 5
                                    radius: 3.5
                                    color: UPower.onBattery && root.bat.percentage < 0.15 ? Theme.red : Theme.fg
                                }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.quickClicked() }
                        }

                        // divider
                        Item {
                            width: 10
                            height: 56
                            Image {
                                anchors.centerIn: parent
                                width: 4
                                height: 40
                                fillMode: Image.TileVertically
                                source: "data:image/svg+xml," + encodeURIComponent(
                                    `<svg xmlns="http://www.w3.org/2000/svg" width="4" height="10">
                                        <circle cx="2" cy="5" r="1.5" fill="#${Theme.hex(Theme.s3)}"/></svg>`)
                            }
                        }

                        // the time in Doto, the day of the week and the date under it. Click -- quick settings
                        Item {
                            width: clk.width + 14
                            height: 56
                            Column {
                                id: clk
                                anchors.centerIn: parent
                                spacing: 2
                                // same clock as the bar: follows the 12/24 setting, and in 12-hour the meridiem rides along
                                Num {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Theme.hh(clock.date) + ":" + Qt.formatTime(clock.date, "mm")
                                        + (Theme.state.clock24 ? "" : " " + Qt.formatTime(clock.date, "AP"))
                                    font.pixelSize: 26
                                }
                                Lb {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Qt.formatDate(clock.date, "ddd d MMM")
                                    px: 9
                                }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.quickClicked() }
                        }
                    }
                }
            }
        }
    }
}
