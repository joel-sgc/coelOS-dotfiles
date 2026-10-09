import QtQuick
import "../.."
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

// ===== TRAY DROPDOWN =====
// Renders a right-clicked tray item's real DBusMenu ourselves, in this
// panel's own dropdown style, instead of Qt's native platform QMenu
// (QsMenuAnchor.open() -- tried first, but that needs `//@ pragma
// UseQApplication` in shell.qml plus a full quickshell restart just to
// call .open(), and even then looks/behaves nothing like every other
// dropdown here, and opened flush against the top of the screen with no
// regard for the bar). QsMenuOpener resolves a QsMenuHandle
// (SystemTrayItem's own `.menu`) into a live list of QsMenuEntry objects
// (`.children`) -- text/icon/enabled/checkState/hasChildren, no rendering
// of its own -- so the rows below are ordinary Rectangle rows matching
// every other dropdown, and clicking one emits `triggered()` on that
// specific entry -- QsMenuEntry's own signal, not DBusMenuItem's
// sendTriggered() method, which turned out not to be QML-invokable at all
// (confirmed live: "TypeError: ... sendTriggered is not a function",
// despite qmltypes listing it as a real Method -- likely an internal
// implementation detail the metadata scan picked up regardless).
// Quickshell's DBusMenu backend listens for `triggered` internally and is
// what actually sends the real D-Bus Event call from it.
//
// One level of submenu support: a QsMenuEntry is itself a QsMenuHandle
// (see its prototype chain), so a second QsMenuOpener (subOpener) bound to
// whichever entry is expanded resolves its children the same way --
// flattened into the same row list, indented, right under their parent.
// Real tray menus rarely nest deeper than that; not handled if they do
// (the › chevron still shows, it just won't expand a *third* level).
Item {
  id: dropdownRoot

  property color fgColor: "#abb2bf"
  property color mutedColor: "#5c6370"
  property color hoverColor: "#404754"
  property var colors: ["#61afef", "#ef596f", "#e5c07b", "#89ca78", "#d55fde"]
  // The SystemTrayItem (Quickshell.Services.SystemTray) that was
  // right-clicked -- set by Tray.qml via Panel.qml's shared
  // root.trayMenuItem, not owned here.
  property var trayItem: null

  signal closeRequested()

  property var expandedEntry: null
  // Always start collapsed on a fresh open, and forget an expanded
  // submenu the moment this dropdown starts pointing at a *different*
  // tray item -- otherwise expandedEntry (an object living on the last
  // item's own menu handle) would silently keep pointing at nothing
  // useful the next time this same dropdown reopens for a different icon.
  onTrayItemChanged: expandedEntry = null
  onVisibleChanged: if (!visible) expandedEntry = null

  QsMenuOpener {
    id: opener
    menu: dropdownRoot.trayItem ? dropdownRoot.trayItem.menu : null
  }
  QsMenuOpener {
    id: subOpener
    menu: dropdownRoot.expandedEntry
  }

  readonly property var flatRows: {
    const out = [];
    const top = opener.children ? opener.children.values : [];
    for (const e of top) {
      out.push({ entry: e, indent: false });
      if (e === dropdownRoot.expandedEntry) {
        const kids = subOpener.children ? subOpener.children.values : [];
        for (const k of kids) out.push({ entry: k, indent: true });
      }
    }
    return out;
  }

  function activate(entry) {
    if (entry.hasChildren) {
      expandedEntry = expandedEntry === entry ? null : entry;
      return;
    }
    entry.triggered();
    closeRequested();
  }

  // Matches Panel.qml's Popup contentWidth (340) minus its fixed 32px
  // side padding.
  implicitWidth: 308
  implicitHeight: col.implicitHeight

  Column {
    id: col
    width: parent.width
    spacing: 0

    RowLayout {
      width: parent.width
      height: 24
      Text {
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: dropdownRoot.trayItem ? (dropdownRoot.trayItem.title || dropdownRoot.trayItem.id || "menu") : "menu"
        color: dropdownRoot.colors[0]
        font.family: "JetBrains Mono"
        font.weight: Font.DemiBold
        font.pixelSize: 13
      }
      Text {
        text: "[×]"
        color: dropdownRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 13
        MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.closeRequested() }
      }
    }

    Item { width: 1; height: 6 }

    Repeater {
      model: dropdownRoot.flatRows
      delegate: Loader {
        id: rowLoader
        required property var modelData
        width: col.width
        sourceComponent: modelData.entry.isSeparator ? sepComp : rowComp
        onLoaded: { item.entry = modelData.entry; item.indent = modelData.indent; }
      }
    }

    Text {
      visible: dropdownRoot.flatRows.length === 0
      x: 8
      text: "no menu items"
      color: dropdownRoot.mutedColor
      font.family: "JetBrains Mono"
      font.pixelSize: 13
    }

    Item { width: 1; height: 2 }
  }

  Component {
    id: sepComp
    Item {
      property var entry: null
      property bool indent: false
      width: col.width
      height: 9
      Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: dropdownRoot.hoverColor }
    }
  }

  Component {
    id: rowComp
    Rectangle {
      id: menuRow
      property var entry: null
      property bool indent: false
      readonly property bool expanded: entry && dropdownRoot.expandedEntry === entry

      width: col.width
      height: 22
      radius: Globals.eyeCandyOff ? 0 : 2
      color: (entry && entry.enabled && rMouse.containsMouse) ? "#2f343e" : "transparent"

      MouseArea {
        id: rMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: menuRow.entry ? menuRow.entry.enabled : false
        cursorShape: (menuRow.entry && menuRow.entry.enabled) ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (menuRow.entry) dropdownRoot.activate(menuRow.entry)
      }

      Text {
        id: checkMark
        x: menuRow.indent ? 22 : 8
        width: 14
        anchors.verticalCenter: parent.verticalCenter
        visible: menuRow.entry && menuRow.entry.buttonType !== QsMenuButtonType.None
        text: !menuRow.entry ? "" : menuRow.entry.buttonType === QsMenuButtonType.RadioButton
          ? (menuRow.entry.checkState === Qt.Checked ? "(•)" : "( )")
          : (menuRow.entry.checkState === Qt.Checked ? "[x]" : "[ ]")
        color: dropdownRoot.colors[3]
        font.family: "JetBrains Mono"
        font.pixelSize: 12
      }

      IconImage {
        id: menuIcon
        x: checkMark.visible ? checkMark.x + checkMark.width + 4 : (menuRow.indent ? 22 : 8)
        width: 14
        height: 14
        anchors.verticalCenter: parent.verticalCenter
        visible: !!(menuRow.entry && menuRow.entry.icon)
        source: (menuRow.entry && menuRow.entry.icon) || ""
      }

      Text {
        x: menuIcon.visible ? menuIcon.x + menuIcon.width + 6 : checkMark.x + (checkMark.visible ? checkMark.width + 4 : 0)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, parent.width - x - (menuRow.entry && menuRow.entry.hasChildren ? 20 : 8))
        elide: Text.ElideRight
        text: menuRow.entry ? menuRow.entry.text : ""
        color: (menuRow.entry && menuRow.entry.enabled) ? dropdownRoot.fgColor : dropdownRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 13
      }

      Text {
        visible: menuRow.entry && menuRow.entry.hasChildren
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: menuRow.expanded ? "⌄" : "›"
        color: dropdownRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 13
      }
    }
  }
}
