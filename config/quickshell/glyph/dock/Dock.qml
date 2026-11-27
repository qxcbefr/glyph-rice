import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components

// dock: every open app at the bottom center, in the bar's language -- the mark (launcher) on the left, then one tile per app:
// the app's own icon as dots on a grey circle, the focused app white, a dot under it that stretches while it is focused.
// Tiles are sorted by workspace, then name, so nothing shuffles under the cursor when focus moves. Click -- focus that
// app, never close or hide it: another click takes its next window while it has more than one.
// Red -- only the mark's center, only while recording or the microphone is live.
Scope {
    id: root

    signal markClicked

    // the window list from hypr, every 500 ms. Hyprland.toplevels only moves on its event socket, and that socket goes
    // quiet when the shell reloads -- which leaves the dock frozen on whatever was open at that moment. A poll does not
    // care: an app opened now is a tile on the next tick, one closed is gone
    property var wins: []
    property string sig: "" // what the dock shows: a rebuild throws away hover and reloads the icons, so only on a change
    Process {
        id: poll
        running: true
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text);
                    const s = j.map(c => `${c.address} ${c.workspace?.name} ${c.mapped} ${c.focusHistoryID}`).join("|");
                    if (s === root.sig) return;
                    root.sig = s;
                    root.wins = j;
                } catch (e) {}
            }
        }
        onExited: nap.start() // next check in 500 ms -- running = true on a finished process does not launch it again
    }
    Timer {
        id: nap
        interval: 500
        onTriggered: poll.running = true
    }

    // open windows grouped by class. Minimized (special:minimized) windows are not on the dock: they are parked, not open
    readonly property var apps: {
        const by = new Map();
        for (const c of root.wins) {
            if (!c.mapped) continue;
            const ws = c.workspace ?? {};
            if (ws.name === "special:minimized") continue;
            const cls = c.class || c.initialClass || "";
            if (!cls) continue;
            const addr = c.address.startsWith("0x") ? c.address.slice(2) : c.address;
            const g = by.get(cls) ?? { cls: cls, ws: 99, wins: [], focused: false };
            // focus history 0 is the window hypr has focused -- the same answer a fullscreen window gives
            g.wins.push({ address: addr, ws: ws.type === "special" ? 99 : (ws.id ?? 99), active: c.focusHistoryID === 0 });
            by.set(cls, g);
        }
        return [...by.values()].map(g => {
            g.wins.sort((a, b) => a.ws - b.ws);
            g.addresses = g.wins.map(w => w.address);
            g.activeAddress = (g.wins.find(w => w.active) ?? g.wins[0]).address;
            g.focused = g.wins.some(w => w.active);
            g.ws = g.wins[0].ws;
            g.count = g.wins.length;
            const e = DesktopEntries.heuristicLookup(g.cls);
            g.name = e?.name || g.cls;
            g.src = e?.icon ? Quickshell.iconPath(e.icon, true) : "";
            g.letter = g.cls.charAt(0).toUpperCase();
            return g;
        }).sort((a, b) => a.ws - b.ws || a.name.localeCompare(b.name));
    }

    // hypr's window selector wants the address with 0x, quickshell's address comes without it
    function focus(address) {
        const addr = address.startsWith("0x") ? address : "0x" + address;
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:${addr}" })`);
    }
    // a click only ever brings an app forward: nothing here closes, hides or minimizes a window
    function press(a) {
        if (!a || !a.addresses.length) return;
        const i = a.focused ? a.addresses.indexOf(a.activeAddress) : -1;
        focus(a.addresses[(i + 1) % a.count]); // not the focused app -- its first window. Focused -- its next
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property var modelData

            screen: modelData
            anchors.bottom: true
            implicitWidth: Math.ceil(pill.width * Theme.s)
            implicitHeight: Math.ceil((pill.height + 14) * Theme.s)
            color: "transparent"
            WlrLayershell.namespace: "glyph-dock"

            Stage {
                Rectangle {
                    id: pill
                    x: (parent.width - width) / 2
                    y: parent.height - height - 14
                    width: row.width + 36
                    height: 84
                    radius: 42
                    color: Theme.s1
                    border { width: 1; color: Theme.s2 }

                    Row {
                        id: row
                        x: 18
                        y: (pill.height - height) / 2
                        spacing: 6

                        // mark: ring of 16 dots -- launcher, the center red while something is recording
                        Item {
                            width: 40
                            height: 56
                            Ring {
                                anchors.centerIn: parent
                                width: 40
                                height: 40
                                n: 16
                                dot: 2.5
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 9
                                height: 9
                                radius: 4.5
                                color: Sys.live ? Theme.red : Theme.fg
                                Behavior on color { ColorAnimation { duration: Theme.t } }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.markClicked() }
                        }

                        // divider: a line of dots, as between the deck's sections
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

                        Lb {
                            visible: !root.apps.length
                            height: 56
                            verticalAlignment: Text.AlignVCenter
                            text: "no windows"
                            px: 11
                            color: Theme.mute
                        }

                        Repeater {
                            model: root.apps

                            Item {
                                id: tile

                                required property var modelData
                                readonly property bool on: modelData.focused
                                property bool hot: false

                                width: 48
                                height: 56

                                Rectangle {
                                    id: circle
                                    width: 48
                                    height: 48
                                    radius: 24
                                    color: tile.on ? Theme.fg : tile.hot ? Theme.s3 : Theme.s2
                                    Behavior on color { ColorAnimation { duration: Theme.t } }

                                    // drawn 34, rasterized and masked at 2x: a dot takes its tone from the cell center, and at 1x
                                    // one cell is one texel -- the icon smears. Pitch 2.5, as in the launcher
                                    Image {
                                        id: pic
                                        anchors.centerIn: parent
                                        visible: status === Image.Ready
                                        width: 34
                                        height: 34
                                        source: tile.modelData.src
                                        sourceSize: Qt.size(68, 68)
                                        asynchronous: true
                                        retainWhileLoading: true // the app changed -- the old icon while the new one loads
                                        layer.enabled: true
                                        layer.textureSize: Qt.size(68, 68)
                                        layer.effect: Dm { step: 2.5 }
                                    }
                                    // no icon file at all: the class's first letter in Doto, the circle is never empty
                                    Text {
                                        visible: !pic.visible
                                        anchors.centerIn: parent
                                        text: tile.modelData.letter
                                        font { family: Theme.dot; pixelSize: 24; weight: Font.Black; variableAxes: ({ "ROND": 100, "wght": 900 }) }
                                        color: tile.on ? Theme.ink : Theme.fg
                                    }
                                }

                                // running: a dot. Focused: it stretches into a pill, as the workspace dots in the bar
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 52
                                    width: tile.on ? 12 : 4
                                    height: 4
                                    radius: 2
                                    color: tile.on ? Theme.fg : Theme.mute
                                    Behavior on width { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                                    Behavior on color { ColorAnimation { duration: Theme.t } }
                                }

                                // MouseArea, not TapHandler: the click is a press and a release on the tile, nothing else
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.press(tile.modelData)
                                    onEntered: tile.hot = true
                                    onExited: tile.hot = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
