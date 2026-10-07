import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../widgets"

// ===== SCREEN SHARE PICKER =====
// Replaces hyprland-share-picker, ported from example/Screen Share Picker.dc.html.
// xdg-desktop-portal-hyprland runs the picker configured as
// `screencopy { custom_picker_binary = ... }` (~/.config/hypr/xdph.conf) and
// reads ONE line from its stdout. The contract, verified against 1.3.12:
//   in : env XDPH_WINDOW_SHARING_LIST = "id[HC>]class[HT>]title[HE>]addr[HA>]"*
//          (id = the portal's own handle, valid for THIS portal process only;
//           addr = Hyprland window address, decimal)
//        arg --allow-token only if the portal's allow_token_by_default is on
//          (the stock picker uses it to pre-tick its "restore token" checkbox)
//   out: "[SELECTION]<r?>/screen:NAME\n" | "/window:ID\n" | "/region:NAME@x,y,w,h\n"
//        r = hand the app a restore token (if it asked for one). The trailing newline is REQUIRED
//        (without it the portal blocks forever). Empty output = cancelled.
//        A window ID that isn't in the list also blocks the portal, so only
//        ever answer with IDs we were given.
// Region x,y,w,h are output-local logical pixels. Nothing here is told who is
// asking, so the request box is generic. Quickshell can't print its own
// stdout cleanly, so the answer goes to $COEL_PICKER_OUT and the wrapper
// (coel-share-picker) prints it; $COEL_PICKER_TOKEN=1 mirrors --allow-token.
Scope {
  id: root

  readonly property string outPath: Quickshell.env("COEL_PICKER_OUT")
  readonly property bool allowToken: Quickshell.env("COEL_PICKER_TOKEN") === "1"
  readonly property var screens: Quickshell.screens
  readonly property var accents: [Pal.orange, Pal.green, Pal.blue, Pal.purple, Pal.yellow, Pal.cyan, Pal.red]

  // ----- state -----
  property string tab: "screens"       // screens | windows | region
  property int fi: 0                   // focused card in the current tab
  property string selScreen: ""
  property string selWindow: ""
  property string query: ""
  // --allow-token only pre-ticks this; the checkbox itself is always offered
  // (the portal ignores a restore token the app didn't ask for)
  property bool remember: allowToken
  property string regScreen: screens.length ? screens[0].name : ""
  // region as fractions of the chosen screen
  property real rx: 0.2
  property real ry: 0.18
  property real rw: 0.55
  property real rh: 0.55
  property bool done: false

  readonly property var regionScreen: {
    for (const s of screens) if (s.name === regScreen) return s;
    return screens.length ? screens[0] : null;
  }

  // ----- window list from the portal -----
  readonly property var allWindows: {
    const out = [];
    const re = /(\d+)\[HC>\]([\s\S]*?)\[HT>\]([\s\S]*?)\[HE>\](\d+)\[HA>\]/g;
    const s = Quickshell.env("XDPH_WINDOW_SHARING_LIST") || "";
    let m;
    while ((m = re.exec(s)) !== null) out.push({ id: m[1], cls: m[2], title: m[3], addr: m[4], accent: accents[out.length % accents.length] });
    return out;
  }
  readonly property var windows: {
    const q = query.trim().toLowerCase();
    return allWindows.filter(w => !q || (w.cls + " " + w.title).toLowerCase().indexOf(q) >= 0);
  }
  function toplevelFor(addr) {
    const hex = Number(addr).toString(16);
    for (const t of Hyprland.toplevels.values) {
      if (String(t.address).replace(/^0x/, "").toLowerCase() === hex) return t;
    }
    return null;
  }
  function iconFor(cls) {
    const e = DesktopEntries.heuristicLookup(cls);
    return e && e.icon ? Quickshell.iconPath(e.icon, true) : "";
  }
  function hzFor(name) {
    for (const m of Hyprland.monitors.values) {
      if (m.name === name && m.lastIpcObject && m.lastIpcObject.refreshRate) return Math.round(m.lastIpcObject.refreshRate);
    }
    return 0;
  }

  function screenByName(n) { for (const s of screens) if (s.name === n) return s; return null; }
  function focusedScreen() {
    const mon = Hyprland.focusedMonitor;
    return (mon ? screenByName(mon.name) : null) || (screens.length ? screens[0] : null);
  }

  // ----- selection / output -----
  readonly property int cols: tab === "screens" ? 3 : 4
  function itemIds() { return tab === "screens" ? screens.map(s => s.name) : tab === "windows" ? windows.map(w => w.id) : []; }
  readonly property string regionText: {
    const s = regionScreen;
    if (!s) return "";
    const w = Math.max(1, Math.round(rw * s.width)), h = Math.max(1, Math.round(rh * s.height));
    return s.name + "@" + Math.round(rx * s.width) + "," + Math.round(ry * s.height) + "," + w + "," + h;
  }
  readonly property string selection: {
    if (tab === "screens") return selScreen ? "screen:" + selScreen : "";
    if (tab === "windows") return selWindow ? "window:" + selWindow : "";
    return regionText ? "region:" + regionText : "";
  }
  readonly property string shareLabel: {
    if (!selection) return "share";
    if (tab === "screens") return "share " + selScreen;
    if (tab === "windows") { for (const w of allWindows) if (w.id === selWindow) return "share " + w.cls; return "share"; }
    return "share region";
  }

  function toggle(id) {
    if (tab === "screens") selScreen = selScreen === id ? "" : id;
    else if (tab === "windows") selWindow = selWindow === id ? "" : id;
  }
  function setTab(t) {
    tab = t;
    fi = 0;
    // keep the keys live (1-3, hjkl); "/" is the way into the filter
    Qt.callLater(keys.forceActiveFocus);
  }
  function finish(sel) {
    if (done) return;
    done = true;
    const flag = remember ? "r" : "";
    const text = sel ? "[SELECTION]" + flag + "/" + sel + "\n" : "";
    if (outPath === "") { console.log("picker result:", text.trim() || "(cancelled)"); Qt.quit(); return; }
    outFile.setText(text);
    quitTimer.start();
  }
  function share() { if (selection) finish(selection); }
  function cancel() { finish(""); }

  FileView {
    id: outFile
    path: root.outPath
    preload: false
    printErrors: false
    onSaved: Qt.quit()
    onSaveFailed: Qt.quit()
  }
  Timer { id: quitTimer; interval: 1500; onTriggered: Qt.quit() }   // never leave the portal waiting

  // ----- window -----
  PanelWindow {
    id: win
    screen: root.focusedScreen()
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "coel-share-picker"

    Rectangle { anchors.fill: parent; color: Qt.rgba(24 / 255, 26 / 255, 31 / 255, 0.62) }
    MouseArea { anchors.fill: parent }   // stray clicks don't dismiss; esc / [x] / cancel do

    FocusScope {
      id: keys
      anchors.fill: parent
      focus: true
      Component.onCompleted: forceActiveFocus()

      Keys.onPressed: (e) => {
        const alt = e.modifiers & Qt.AltModifier;
        if (e.key === Qt.Key_Escape) { root.cancel(); e.accepted = true; return; }
        if (alt && e.key === Qt.Key_R) { root.remember = !root.remember; e.accepted = true; return; }
        if (e.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier)) return;
        const t = e.text, ids = root.itemIds();
        let used = true;
        if (t === "1") root.setTab("screens");
        else if (t === "2") root.setTab("windows");
        else if (t === "3") root.setTab("region");
        else if (e.key === Qt.Key_Tab) root.setTab(["screens", "windows", "region"][(["screens", "windows", "region"].indexOf(root.tab) + 1) % 3]);
        else if (e.key === Qt.Key_Backtab) root.setTab(["screens", "windows", "region"][(["screens", "windows", "region"].indexOf(root.tab) + 2) % 3]);
        else if (t === "/" && root.tab === "windows") filterInput.forceActiveFocus();
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
          if (!root.selection && ids[root.fi] !== undefined) root.toggle(ids[root.fi]);
          root.share();
        }
        else if (e.key === Qt.Key_Space && ids[root.fi] !== undefined) root.toggle(ids[root.fi]);
        else if (ids.length && (t === "l" || e.key === Qt.Key_Right)) root.fi = Math.min(ids.length - 1, root.fi + 1);
        else if (ids.length && (t === "h" || e.key === Qt.Key_Left)) root.fi = Math.max(0, root.fi - 1);
        else if (ids.length && (t === "j" || e.key === Qt.Key_Down)) root.fi = Math.min(ids.length - 1, root.fi + root.cols);
        else if (ids.length && (t === "k" || e.key === Qt.Key_Up)) root.fi = Math.max(0, root.fi - root.cols);
        else used = false;
        e.accepted = used;
      }

      Rectangle {
        id: dialog
        width: Math.min(680, keys.width - 32)
        x: (keys.width - width) / 2
        y: Math.max(24, (keys.height - height) / 2)
        height: body.implicitHeight + 20
        radius: 16
        color: Pal.card
        border.width: 1
        border.color: Pal.faint
        MouseArea { anchors.fill: parent }

        ColumnLayout {
          id: body
          anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 10 }
          spacing: 0
          readonly property real innerW: width - 20    // inside a Box (padSide 10)

          // header
          RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            spacing: 8
            PhIcon { name: "screencast"; font.pixelSize: 15; color: Pal.blue }
            Mono { text: "share screen"; font.weight: Font.Medium; color: Pal.blue }
            Mono { text: "─ portal ─"; color: Pal.muted }
            Item { Layout.fillWidth: true }
            TextButton {
              onClicked: root.cancel()
              Mono { text: "[×]"; color: parent.parent.hovered ? Pal.red : Pal.muted }
            }
          }

          // request
          Box {
            Layout.fillWidth: true
            Layout.topMargin: 8
            padTop: 14; padSide: 10; padBottom: 10
            legend: "request"
            rightLegend: "single source"
            rightColor: Pal.orange
            RowLayout {
              Layout.fillWidth: true
              spacing: 10
              Rectangle {
                Layout.preferredWidth: 36; Layout.preferredHeight: 36
                radius: 8
                color: Pal.edge
                PhIcon { anchors.centerIn: parent; name: "screencast"; font.pixelSize: 20; color: Pal.orange }
              }
              ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Mono { text: "An application wants to share your screen" }
                Mono { text: "xdg-desktop-portal-hyprland"; color: Pal.muted }
              }
            }
          }

          // tabs
          Row {
            Layout.topMargin: 14
            spacing: 6
            Repeater {
              model: [
                { id: "screens", key: "1", icon: "monitor", label: "screens" },
                { id: "windows", key: "2", icon: "app-window", label: "windows" },
                { id: "region", key: "3", icon: "selection", label: "region" }
              ]
              delegate: Rectangle {
                required property var modelData
                readonly property bool on: root.tab === modelData.id
                width: tabRow.implicitWidth + 20
                height: tabRow.implicitHeight + 2
                radius: 2
                color: on || tabArea.containsMouse ? Pal.edge : "transparent"
                border.width: 1
                border.color: on ? Pal.blue : "transparent"
                Row {
                  id: tabRow
                  anchors.centerIn: parent
                  spacing: 6
                  Mono { text: modelData.key; color: Pal.yellow }
                  PhIcon { name: modelData.icon; font.pixelSize: 14; color: on ? Pal.fg : Pal.dim }
                  Mono { text: modelData.label; color: on ? Pal.fg : Pal.dim }
                }
                MouseArea { id: tabArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setTab(modelData.id) }
              }
            }
          }

          // pane
          Box {
            Layout.fillWidth: true
            Layout.topMargin: 14
            padTop: 14; padSide: 10; padBottom: 10
            legend: root.tab === "screens" ? "outputs" : root.tab === "windows" ? "toplevels" : "area"
            legendColor: Pal.blue
            rightLegend: root.tab === "screens" ? root.screens.length + " connected"
              : root.tab === "windows" ? root.windows.length + " of " + root.allWindows.length
              : (root.regionScreen ? root.regionScreen.name : "")

            // --- screens ---
            Grid {
              visible: root.tab === "screens"
              Layout.fillWidth: true
              columns: 3
              spacing: 10
              Repeater {
                model: root.screens
                delegate: SourceCard {
                  required property var modelData
                  required property int index
                  width: (body.innerW - 20) / 3
                  thumbAspect: modelData.width / modelData.height
                  selected: root.selScreen === modelData.name
                  focusedCard: root.tab === "screens" && root.fi === index
                  name: modelData.name
                  detail: modelData.width + "×" + modelData.height
                    + (root.hzFor(modelData.name) ? " @ " + root.hzFor(modelData.name) + "hz" : "")
                    + (modelData.devicePixelRatio !== 1 ? " · " + modelData.devicePixelRatio + "×" : "")
                    + (modelData.model ? " · " + modelData.model : "")
                  onPicked: { root.fi = index; root.toggle(modelData.name); }
                  onActivated: { root.selScreen = modelData.name; root.share(); }
                  Thumb {
                    anchors.fill: parent
                    source: modelData
                    live: true
                    glyph: "monitor"
                  }
                }
              }
            }

            // --- windows ---
            RowLayout {
              visible: root.tab === "windows"
              Layout.fillWidth: true
              Layout.bottomMargin: 10
              spacing: 8
              Mono { text: "/"; color: Pal.blue }
              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: filterInput.implicitHeight + 6
                color: filterInput.activeFocus ? Pal.raised : Pal.deep
                Rectangle {
                  anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                  height: 1
                  color: filterInput.activeFocus ? Pal.blue : Pal.faint
                }
                TextInput {
                  id: filterInput
                  anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                  verticalAlignment: TextInput.AlignVCenter
                  font.family: Pal.mono; font.pixelSize: 12
                  color: Pal.fg
                  selectionColor: Pal.blue
                  selectedTextColor: Pal.card
                  clip: true
                  onTextChanged: { root.query = text; root.fi = 0; }
                  Keys.onEscapePressed: (e) => {
                    if (text !== "") text = "";
                    else keys.forceActiveFocus();
                    e.accepted = true;
                  }
                  Keys.onDownPressed: keys.forceActiveFocus()
                  Keys.onReturnPressed: {
                    if (!root.selWindow && root.windows.length) root.selWindow = root.windows[0].id;
                    keys.forceActiveFocus();
                  }
                }
                Mono {
                  visible: filterInput.text === ""
                  anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8 }
                  text: "filter by title or class"
                  color: Pal.muted
                }
              }
            }
            Flickable {
              visible: root.tab === "windows"
              Layout.fillWidth: true
              Layout.preferredHeight: Math.min(300, winGrid.implicitHeight)
              contentWidth: width
              contentHeight: winGrid.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              Grid {
                id: winGrid
                columns: 4
                spacing: 10
                Repeater {
                  model: root.windows
                  delegate: SourceCard {
                    id: wcard
                    required property var modelData
                    required property int index
                    readonly property var tl: root.toplevelFor(modelData.addr)
                    width: (body.innerW - 30) / 4
                    detailLines: 1
                    selected: root.selWindow === modelData.id
                    focusedCard: root.tab === "windows" && root.fi === index
                    name: modelData.cls
                    detail: modelData.title
                    onPicked: { root.fi = index; root.toggle(modelData.id); }
                    onActivated: { root.selWindow = modelData.id; root.share(); }
                    Thumb {
                      anchors.fill: parent
                      source: wcard.tl && wcard.tl.wayland ? wcard.tl.wayland : null
                      live: false
                      glyph: "app-window"
                      accent: modelData.accent
                      iconPath: root.iconFor(modelData.cls)
                      showBar: true
                      badge: wcard.tl && wcard.tl.workspace ? "ws " + wcard.tl.workspace.id : ""
                    }
                  }
                }
              }
            }
            Mono {
              visible: root.tab === "windows" && root.windows.length === 0
              Layout.alignment: Qt.AlignHCenter
              Layout.topMargin: 12; Layout.bottomMargin: 12
              text: root.allWindows.length === 0 ? "no windows to share" : "no windows match “" + root.query + "”"
              color: Pal.muted
            }

            // --- region ---
            Flow {
              visible: root.tab === "region" && root.screens.length > 1
              Layout.fillWidth: true
              Layout.bottomMargin: 10
              spacing: 8
              Mono { text: "on"; color: Pal.muted }
              Repeater {
                model: root.screens
                delegate: TextButton {
                  required property var modelData
                  readonly property bool on: root.regScreen === modelData.name
                  color: on ? Pal.edge : (hovered ? Pal.edge : "transparent")
                  onClicked: root.regScreen = modelData.name
                  Mono { text: on ? "(•)" : "( )"; color: on ? Pal.blue : Pal.muted }
                  Mono { text: modelData.name; color: on ? Pal.fg : Pal.dim }
                }
              }
            }
            Item {
              id: regionArea
              visible: root.tab === "region"
              Layout.fillWidth: true
              readonly property real aspect: root.regionScreen ? root.regionScreen.width / root.regionScreen.height : 16 / 9
              readonly property real boxH: Math.min(300, width / aspect)
              Layout.preferredHeight: boxH
              Item {
                id: regionBox
                anchors.horizontalCenter: parent.horizontalCenter
                height: regionArea.boxH
                width: height * regionArea.aspect
                property real dx: 0
                property real dy: 0
                Thumb {
                  anchors.fill: parent
                  source: root.regionScreen
                  live: true
                  glyph: "monitor"
                }
                // dim everything outside the selection
                Rectangle { color: Qt.rgba(24 / 255, 26 / 255, 31 / 255, 0.62); x: 0; y: 0; width: parent.width; height: sel.y }
                Rectangle { color: Qt.rgba(24 / 255, 26 / 255, 31 / 255, 0.62); x: 0; y: sel.y + sel.height; width: parent.width; height: parent.height - (sel.y + sel.height) }
                Rectangle { color: Qt.rgba(24 / 255, 26 / 255, 31 / 255, 0.62); x: 0; y: sel.y; width: sel.x; height: sel.height }
                Rectangle { color: Qt.rgba(24 / 255, 26 / 255, 31 / 255, 0.62); x: sel.x + sel.width; y: sel.y; width: parent.width - (sel.x + sel.width); height: sel.height }
                Rectangle {
                  id: sel
                  x: root.rx * parent.width
                  y: root.ry * parent.height
                  width: root.rw * parent.width
                  height: root.rh * parent.height
                  color: "transparent"
                  border.width: 1
                  border.color: Pal.blue
                  Repeater {
                    model: [[-3, -3], [1, -3], [-3, 1], [1, 1]]
                    delegate: Rectangle {
                      required property var modelData
                      width: 5; height: 5; color: Pal.blue
                      x: modelData[0] < 0 ? -3 : parent.width + modelData[0]
                      y: modelData[1] < 0 ? -3 : parent.height + modelData[1]
                    }
                  }
                  Rectangle {
                    x: 4; y: 3
                    width: dimsText.implicitWidth + 8; height: dimsText.implicitHeight
                    color: Pal.card
                    Mono { id: dimsText; anchors.centerIn: parent; font.pixelSize: 11; color: Pal.blue
                      text: root.regionScreen ? Math.round(root.rw * root.regionScreen.width) + " × " + Math.round(root.rh * root.regionScreen.height) : "" }
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.CrossCursor
                  onPressed: (m) => { regionBox.dx = m.x / width; regionBox.dy = m.y / height; }
                  onPositionChanged: (m) => {
                    if (!pressed) return;
                    const px = Math.max(0, Math.min(1, m.x / width)), py = Math.max(0, Math.min(1, m.y / height));
                    const w = Math.abs(px - regionBox.dx), h = Math.abs(py - regionBox.dy);
                    if (w < 0.015 && h < 0.015) return;
                    root.rx = Math.min(px, regionBox.dx); root.ry = Math.min(py, regionBox.dy);
                    root.rw = w; root.rh = h;
                  }
                }
              }
            }
            RowLayout {
              visible: root.tab === "region"
              Layout.fillWidth: true
              Layout.topMargin: 8
              Row {
                spacing: 7
                Mono { text: "drag to draw ·"; color: Pal.muted }
                Mono { text: root.regionScreen ? "at " + Math.round(root.rx * root.regionScreen.width) + ", " + Math.round(root.ry * root.regionScreen.height) : ""; color: Pal.dim }
              }
              Item { Layout.fillWidth: true }
              Repeater {
                model: ["full", "16:9", "1080p"]
                delegate: TextButton {
                  required property string modelData
                  hPad: 6
                  onClicked: {
                    const s = root.regionScreen;
                    if (!s) return;
                    if (modelData === "full") { root.rx = 0; root.ry = 0; root.rw = 1; root.rh = 1; }
                    else if (modelData === "16:9") {
                      const w = 0.6, h = Math.min(1, w * (s.width / s.height) * 9 / 16);
                      root.rx = (1 - w) / 2; root.ry = (1 - h) / 2; root.rw = w; root.rh = h;
                    } else {
                      const w = Math.min(1, 1920 / s.width), h = Math.min(1, 1080 / s.height);
                      root.rx = (1 - w) / 2; root.ry = (1 - h) / 2; root.rw = w; root.rh = h;
                    }
                  }
                  Mono { text: "[" + modelData + "]"; color: parent.parent.hovered ? Pal.fg : Pal.dim }
                }
              }
            }
          }

          // options
          Box {
            Layout.fillWidth: true
            Layout.topMargin: 16
            padTop: 12; padSide: 6; padBottom: 6
            legend: "options"
            TextButton {
              onClicked: root.remember = !root.remember
              Mono { text: root.remember ? "[x]" : "[ ]"; color: root.remember ? Pal.green : Pal.muted }
              Mono { text: "remember this choice" }
              Mono { text: "alt r"; color: Pal.muted }
            }
            Mono {
              visible: root.remember
              Layout.leftMargin: 6
              text: "The app can start sharing this source again without asking."
              color: Pal.muted
            }
          }

          // footer
          Hints {
            Layout.fillWidth: true
            Layout.topMargin: 14
            items: {
              const h = [["1-3", "source"], root.tab === "region" ? ["drag", "select"] : ["hjkl", "move"]];
              if (root.tab !== "region") h.push(["space", "pick"]);
              h.push(["⏎", "share"], ["esc", "cancel"]);
              return h;
            }
          }
          RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            spacing: 6
            Item { Layout.fillWidth: true }
            TextButton {
              hPad: 10
              onClicked: root.cancel()
              Mono { text: "< cancel >"; color: parent.parent.hovered ? Pal.fg : Pal.dim }
            }
            Rectangle {
              Layout.preferredWidth: shareText.implicitWidth + 20
              Layout.preferredHeight: shareText.implicitHeight
              radius: 2
              color: root.selection ? Pal.green : Pal.muted
              opacity: root.selection ? 1 : 0.45
              Mono {
                id: shareText
                anchors.centerIn: parent
                text: "< " + root.shareLabel + " >"
                font.weight: Font.Medium
                color: Pal.card
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.share()
              }
            }
          }
        }
      }
    }
  }
}
