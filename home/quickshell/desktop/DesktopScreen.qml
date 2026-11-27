import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."
import "../widgets"
import "../modes"
import "../services"
import "cards"
import "data"
import "Layout.js" as L

// One monitor's desktop (Desktop Board "hero + rail"): a transparent, full-screen
// Bottom-layer surface (under every window, over the wallpaper) holding the mode
// chip and every card. One surface rather than a window per card, so cards can
// glide between hero, rail and shelf. The input mask is just the visible cards,
// the chip and the menu: clicks anywhere else fall through.
PanelWindow {
  id: win
  property bool shown: true
  // Where windows sit: {top, left, right, bottom, gap} (Desktop.qml, from gaps_out).
  property var edges: ({ top: 44, left: 12, right: 12, bottom: 12, gap: 12 })

  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  visible: shown
  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.namespace: "coel-desktop"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

  // Cards that have something to show. Music comes and goes with Mpris (Layout.js).
  readonly property var available: ({
    next: true, weather: true, kanban: true, pomo: true, server: true, calendar: true, music: true,
    printer: Printer.configured || Printer.mock, phone: Phone.paired
  })

  readonly property var lay: L.layout({
    mode: Modes.mode,
    available: available,
    printerActive: Modes.printingNow,
    musicActive: Music.active,
    modePinned: Modes.pinnedCards,
    user: { min: DeskState.min, pin: DeskState.pin }
  })
  readonly property var heights: ({
    weather: weatherSlot.cardHeight, kanban: kanbanSlot.cardHeight, pomo: pomoSlot.cardHeight,
    server: serverSlot.cardHeight, calendar: calendarSlot.cardHeight,
    next: nextSlot.cardHeight, printer: printerSlot.cardHeight, music: musicSlot.cardHeight, phone: phoneSlot.cardHeight
  })
  readonly property var placed: L.place(lay, width, height, heights, edges)

  // Tell the pill which cards this desktop has open, and where (DeskState.openRects).
  readonly property var openRects: {
    const o = {};
    if (!shown) return o;
    for (const id in placed) {
      const p = placed[id];
      if (p.slot !== "shelf") o[id] = { x: p.x, y: p.y, w: p.w, h: heights[id] || 0 };
    }
    return o;
  }
  onOpenRectsChanged: if (screen) DeskState.publish(screen.name, openRects)
  Component.onCompleted: if (screen) DeskState.publish(screen.name, openRects)

  mask: Region {
    Region { item: chip }
    Region { item: menuLoader.item ? menuLoader : null }
    Region { item: weatherSlot.visible ? weatherSlot : null }
    Region { item: kanbanSlot.visible ? kanbanSlot : null }
    Region { item: pomoSlot.visible ? pomoSlot : null }
    Region { item: serverSlot.visible ? serverSlot : null }
    Region { item: calendarSlot.visible ? calendarSlot : null }
    Region { item: nextSlot.visible ? nextSlot : null }
    Region { item: printerSlot.visible ? printerSlot : null }
    Region { item: musicSlot.visible ? musicSlot : null }
    Region { item: phoneSlot.visible ? phoneSlot : null }
  }

  // Everything sits in one focus scope: keys a card doesn't use bubble up here,
  // so M (mode menu) and esc work wherever focus is on this desktop, and focus
  // comes back here when the menu closes (it used to be left on nothing).
  FocusScope {
    id: rootScope
    anchors.fill: parent
    focus: true
    Keys.onPressed: (e) => {
      if (e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return;
      if (e.text === "M") { Modes.menuOpen = !Modes.menuOpen; e.accepted = true; }
      else if (e.key === Qt.Key_Escape && Modes.menuOpen) { Modes.menuOpen = false; e.accepted = true; }
    }
    Connections {
      target: Modes
      function onMenuOpenChanged() { if (!Modes.menuOpen) rootScope.forceActiveFocus(); }
    }

    ModeChip {
      id: chip
      z: 10   // over the cards: the menu may drop over the shelf
      opacity: DeskState.greetPhase === 1 || DeskState.greetPhase === 2 ? 0 : 1
      Behavior on opacity { enabled: !Globals.eyeCandyOff; NumberAnimation { duration: 160 } }
      // Under the hero (Layout.js chipY), gliding with it as the hero changes.
      x: win.edges.left; y: L.chipY(win.lay, win.heights, win.edges)
      Behavior on y { enabled: !Globals.eyeCandyOff; NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] } }
      open: Modes.menuOpen
      onClicked: Modes.menuOpen = !Modes.menuOpen
    }
    Loader {
      id: menuLoader
      z: 10
      x: win.edges.left; y: chip.y + chip.height + win.edges.gap
      active: Modes.menuOpen
      focus: active
      sourceComponent: FocusScope {
        implicitWidth: m.implicitWidth
        implicitHeight: m.implicitHeight
        width: implicitWidth; height: implicitHeight
        focus: true
        Component.onCompleted: forceActiveFocus()
        ModeMenu {
          id: m
          width: implicitWidth
          onCloseRequested: Modes.menuOpen = false
        }
        Keys.onPressed: (e) => { if (m.handleKey(e)) e.accepted = true; }
      }
    }

    CardSlot {
      id: weatherSlot
      cardId: "weather"
      p: win.placed.weather || null
      greetDelay: win.placed.weather ? (win.placed.weather.slot === "hero" ? 0 : 40 + 40 * win.lay.rail.findIndex(r => r.id === "weather")) : 0
      card: Component { WeatherCard {} }
    }
    CardSlot {
      id: kanbanSlot
      cardId: "kanban"
      p: win.placed.kanban || null
      greetDelay: win.placed.kanban ? (win.placed.kanban.slot === "hero" ? 0 : 40 + 40 * win.lay.rail.findIndex(r => r.id === "kanban")) : 0
      card: Component { KanbanCard {} }
    }
    CardSlot {
      id: pomoSlot
      cardId: "pomo"
      p: win.placed.pomo || null
      greetDelay: win.placed.pomo ? (win.placed.pomo.slot === "hero" ? 0 : 40 + 40 * win.lay.rail.findIndex(r => r.id === "pomo")) : 0
      card: Component { PomoCard {} }
    }
    CardSlot {
      id: serverSlot
      cardId: "server"
      p: win.placed.server || null
      greetDelay: win.placed.server ? (win.placed.server.slot === "hero" ? 0 : 40 + 40 * win.lay.rail.findIndex(r => r.id === "server")) : 0
      card: Component { ServerCard {} }
    }
    CardSlot {
      id: calendarSlot
      cardId: "calendar"
      p: win.placed.calendar || null
      greetDelay: win.placed.calendar ? (win.placed.calendar.slot === "hero" ? 0 : 40 + 40 * win.lay.rail.findIndex(r => r.id === "calendar")) : 0
      card: Component { CalendarCard {} }
    }
    CardSlot {
      id: nextSlot
      cardId: "next"
      p: win.placed.next || null
      greetDelay: win.placed.next ? (win.placed.next.slot === "hero" ? 0 : 40 + 40 * win.lay.rail.findIndex(r => r.id === "next")) : 0
      card: Component { NextCard {} }
    }
    CardSlot {
      id: printerSlot
      cardId: "printer"
      p: win.placed.printer || null
      greetDelay: win.placed.printer ? (win.placed.printer.slot === "hero" ? 0 : 40 + 40 * win.lay.rail.findIndex(r => r.id === "printer")) : 0
      card: Component { PrintCard {} }
    }
    CardSlot {
      id: musicSlot
      cardId: "music"
      p: win.placed.music || null
      greetDelay: win.placed.music ? (win.placed.music.slot === "hero" ? 0 : 40 + 40 * win.lay.rail.findIndex(r => r.id === "music")) : 0
      card: Component { MusicCard {} }
    }
    CardSlot {
      id: phoneSlot
      cardId: "phone"
      p: win.placed.phone || null
      greetDelay: win.placed.phone ? (win.placed.phone.slot === "hero" ? 0 : 40 + 40 * win.lay.rail.findIndex(r => r.id === "phone")) : 0
      card: Component { PhoneCard {} }
    }
  }
}
