import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components

// win: window switcher (Ctrl+Super+Tab). Every open window as one row -- a live preview of it, the title, the app in Space Mono
// caps, the workspace in Doto. Nothing OS: black scrim over a dot grid that leaves the card in a spot of light, one card, dots,
// red only for "you are here". Tab / Shift+Tab / arrows move, Enter or a click goes there, Esc closes. The cursor starts on the
// next window, so Ctrl+Super+Tab then Enter is the old "switch to the other one".
PanelWindow {
    id: root

    property bool shown: false
    property real t: shown ? 1 : 0
    property int sel: 0

    visible: t > 0
    onVisibleChanged: if (visible) keys.forceActiveFocus()

    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-win"

    // glide: long, no bounce, a touch of scale -- the panel settles instead of popping
    Behavior on t {
        NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1] }
    }

    // all mapped windows: normal workspaces first (by number), special ones last. Stable order, so the list never
    // shuffles under the cursor. live: whatever the desktop says is mapped right now. tl -- the wl toplevel, the preview's source
    function list() {
        return Hyprland.toplevels.values
            .filter(w => (w.lastIpcObject ?? {}).mapped !== false)
            .map(w => {
                const o = w.lastIpcObject ?? {};
                const cls = o.class ?? "";
                const ws = o.workspace ?? {};
                const special = ws.type === "special";
                const icon = DesktopEntries.heuristicLookup(cls)?.icon ?? "";
                return {
                    address: w.address,
                    title: (w.title ?? "").trim() || cls || "window",
                    cls: cls,
                    special: special,
                    ws: ws.id ?? 0,
                    wsTag: special ? "S" : (ws.id ? String(ws.id).padStart(2, "0") : "—"),
                    wsNote: special ? (ws.name ?? "special").replace("special:", "") : (ws.id ? `ws ${ws.id}` : ""),
                    src: icon ? Quickshell.iconPath(icon, true) : "",
                    letter: (cls || "?").charAt(0).toUpperCase(),
                    tl: w.wayland ?? null,
                    run: () => Hyprland.dispatch(`hl.dsp.focus({ window = "address:${w.address}" })`)
                };
            })
            .sort((a, b) => (a.special - b.special) || a.ws - b.ws || a.cls.localeCompare(b.cls) || a.title.localeCompare(b.title));
    }
    readonly property var wins: shown ? list() : []
    readonly property var cur: wins[sel] ?? null
    // the list, capped at eight rows so the card stays compact and centered
    readonly property real listH: Math.min(Math.max(wins.length, 1) * 90 - 6, 8 * 90 - 6)

    function dbg(m) { Quickshell.execDetached(["sh", "-c", "echo \"$(date +%H:%M:%S.%N) " + m + "\" >> /tmp/glyph-win.log"]) }
    function open() {
        dbg("open");
        const ws = list(); // computed before shown: the binding and the first selection must agree
        const focused = Hyprland.activeToplevel?.address
            ?? Hyprland.toplevels.values.find(w => w.activated)?.address ?? "";
        const i = ws.findIndex(w => w.address === focused);
        sel = ws.length ? (i < 0 ? 0 : (i + 1) % ws.length) : 0;
        flick.contentY = 0;
        shown = true;
    }
    function close() { dbg("close"); shown = false; }
    function toggle() { dbg("toggle shown=" + shown); shown ? close() : open(); }
    function move(d) { if (wins.length) sel = (sel + d + wins.length) % wins.length; }
    function go() {
        const w = cur;
        dbg("go " + (w ? w.address : "none") + " sel=" + sel);
        if (!w) return close();
        close();
        w.run();
    }

    // ---- backdrop: scrim, the wallpaper's dot grid dimmed, a vignette so the card sits in a spot of light ----
    Item {
        id: back
        anchors.fill: parent
        opacity: root.t

        property real pitch: 42 // grid settles in from wide to the theme pitch while the panel glides
        Behavior on pitch { NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1] } }
        onOpacityChanged: if (opacity === 1) pitch = 22

        Rectangle { anchors.fill: parent; color: Theme.scrim }

        // dots: a solid fill read through the dot mask -- the same shader as the wallpaper and the icons
        Rectangle {
            anchors.fill: parent
            color: Theme.fg
            opacity: 0.09
            layer.enabled: true
            layer.effect: Dm { step: back.pitch }
        }

        // vignette: transparent around the card, the scrim's own color at the edges. Stretched radial, no shader
        Image {
            anchors.fill: parent
            fillMode: Image.Stretch
            source: "data:image/svg+xml," + encodeURIComponent(
                `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" preserveAspectRatio="none">
                    <defs><radialGradient id="g" cx="50%" cy="50%" r="64%">
                        <stop offset="0" stop-color="${Theme.hex(Theme.bg)}" stop-opacity="0"/>
                        <stop offset="52%" stop-color="${Theme.hex(Theme.bg)}" stop-opacity="0.28"/>
                        <stop offset="100%" stop-color="${Theme.hex(Theme.bg)}" stop-opacity="0.96"/>
                    </radialGradient></defs>
                    <rect width="100" height="100" fill="url(#g)"/>
                </svg>`)
        }

        MouseArea { anchors.fill: parent; onClicked: { root.dbg("backdrop click"); root.close() } }
    }

    // keys live on the window: the layer holds exclusive keyboard focus while shown
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            const shift = e.modifiers & Qt.ShiftModifier;
            if (e.key === Qt.Key_Escape) root.close();
            else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) root.move(e.key === Qt.Key_Backtab || shift ? -1 : 1);
            else if (e.key === Qt.Key_Down || e.key === Qt.Key_Right) root.move(1);
            else if (e.key === Qt.Key_Up || e.key === Qt.Key_Left) root.move(-1);
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) root.go();
            else return;
            e.accepted = true;
        }
    }

    Stage {
        Rectangle {
            id: panel
            x: (parent.width - width) / 2
            y: (parent.height - height) / 2 + 18 * (1 - root.t)
            width: 720
            height: flick.y + root.listH + 44
            opacity: root.t
            scale: 0.985 + 0.015 * root.t
            radius: 34
            color: Theme.s1
            border { width: 1; color: Theme.s2 }
            MouseArea { anchors.fill: parent }

            // header: dot-matrix count, label, one red dot -- the rice's "live" marker, and the app you are on
            Row {
                id: head
                x: 30
                y: 24
                spacing: 11
                Num { text: String(root.wins.length).padStart(2, "0"); font.pixelSize: 38; color: Theme.fg; anchors.verticalCenter: parent.verticalCenter }
                Lb { text: "windows"; px: 12; color: Theme.grey; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    width: 6; height: 6; radius: 3
                    color: Theme.red
                    visible: !!root.cur
                    anchors.verticalCenter: parent.verticalCenter
                }
                Lb {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.cur ? root.cur.cls : ""
                    px: 10
                    color: Theme.mute
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, panel.width - 230)
                }
            }

            Flickable {
                id: flick
                x: 18
                y: head.y + head.height + 16
                width: parent.width - 36
                height: root.listH
                contentHeight: rows.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                onContentYChanged: {
                    const y = root.sel * 90;
                    if (y < contentY) contentY = y;
                    else if (y + 84 > contentY + height) contentY = y + 84 - height;
                }

                Column {
                    id: rows
                    width: flick.width
                    spacing: 6

                    Repeater {
                        model: root.wins.length
                        Rectangle {
                            id: row
                            required property int index
                            readonly property var w: root.wins[index] ?? ({ title: "", cls: "", wsTag: "—", wsNote: "", src: "", letter: "?", tl: null, run: () => {} })
                            readonly property bool on: root.sel === index
                            width: rows.width
                            height: 84
                            radius: 20
                            color: on ? Theme.fg : Theme.s2
                            // the highlight slides in instead of jumping
                            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            // preview: the window itself, captured once when the switcher opens (decoded as small as it will be
                            // drawn), dotted app icon underneath until the frame lands -- or for good if the capture fails
                            Rectangle {
                                id: thumb
                                x: 10; y: 12; width: 100; height: 60
                                radius: 14
                                clip: true
                                color: row.on ? Theme.s3 : Theme.s1
                                Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                Image {
                                    id: pic
                                    anchors.centerIn: parent
                                    visible: status === Image.Ready
                                    width: 26; height: 26
                                    source: row.w.src
                                    sourceSize: Qt.size(26, 26)
                                    asynchronous: true
                                    retainWhileLoading: true
                                    layer.enabled: true
                                    layer.effect: Dm { step: 2 }
                                    opacity: shot.opacity < 1 ? 1 : 0
                                }
                                Text {
                                    visible: !pic.visible
                                    anchors.centerIn: parent
                                    text: row.w.letter
                                    opacity: shot.opacity < 1 ? 1 : 0
                                    font { family: Theme.dot; pixelSize: 26; weight: Font.Black; variableAxes: ({ "ROND": 100, "wght": 900 }) }
                                    color: row.on ? Theme.ink : Theme.fg
                                }

                                ScreencopyView {
                                    id: shot
                                    // a captured frame is drawn at its own pixel size -- hold the item at that size and
                                    // scale it to cover the box, so the window's aspect is kept. constraintSize caps the
                                    // buffer, so a 4K window is not read at 4K
                                    readonly property size sz: sourceSize
                                    anchors.centerIn: parent
                                    width: Math.max(1, sz.width)
                                    height: Math.max(1, sz.height)
                                    scale: hasContent ? Math.max(thumb.width / width, thumb.height / height) : 1
                                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    captureSource: row.w.tl
                                    live: false
                                    paintCursor: false
                                    constraintSize: Qt.size(360, 226)
                                    opacity: hasContent ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                }
                            }

                            Column {
                                anchors { left: thumb.right; leftMargin: 16; right: tag.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                spacing: 4
                                Text {
                                    width: parent.width
                                    text: row.w.title
                                    elide: Text.ElideRight
                                    font { family: Theme.ui; pixelSize: 17 }
                                    color: row.on ? Theme.ink : Theme.fg
                                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }
                                Row {
                                    spacing: 7
                                    Image {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: status === Image.Ready
                                        width: 13; height: 13
                                        source: row.w.src
                                        sourceSize: Qt.size(13, 13)
                                        asynchronous: true
                                        layer.enabled: true
                                        layer.effect: Dm { step: 1.5 }
                                    }
                                    Lb {
                                        text: row.w.cls
                                        px: 10
                                        color: row.on ? Theme.ink : Theme.grey
                                        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    }
                                    Lb {
                                        visible: !!row.w.wsNote
                                        text: row.w.wsNote
                                        px: 10
                                        color: row.on ? Theme.ink : Theme.mute
                                        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }

                            Num {
                                id: tag
                                anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                                text: row.w.wsTag
                                font.pixelSize: 28
                                color: row.on ? Theme.ink : Theme.mute
                                Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }

                            TapHandler { onTapped: { root.dbg("tap row " + index); root.sel = index; root.go(); } }
                            HoverHandler {
                                cursorShape: Qt.PointingHandCursor
                                onHoveredChanged: if (hovered) { root.dbg("hover " + index); root.sel = index }
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: flick
                visible: !root.wins.length
                text: "no windows"
                font { family: Theme.mono; pixelSize: 11; letterSpacing: 2; capitalization: Font.AllUppercase }
                color: Theme.mute
            }

            // footer: the keys, spelled out; the panel never grows beyond eight rows
            Lb {
                id: hint
                anchors { left: parent.left; leftMargin: 30; bottom: parent.bottom; bottomMargin: 18 }
                text: "tab / shift+tab · enter · esc"
                px: 10
                color: Theme.mute
            }
            Lb {
                anchors { right: parent.right; rightMargin: 30; bottom: parent.bottom; bottomMargin: 18 }
                text: "ctrl+super+tab"
                px: 10
                color: Theme.mute
            }
        }
    }
}
