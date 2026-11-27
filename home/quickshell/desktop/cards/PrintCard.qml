import QtQuick
import QtQuick.Layouts
import "../.."
import "../../widgets"
import "../../island"
import "../../services"
import ".."

// The printer (Desktop Board `printer`): S small (every state), L the printing
// hero (camera, progress ring, temps, controls), M minimized. Data: services/Printer.
CardFrame {
  id: card
  property string size: "S"
  property string flavor: ""
  readonly property var pr: Printer

  readonly property string st: pr.shown
  readonly property var stColor: ({ idle: Pal.muted, heating: Pal.orange, printing: Pal.cyan, paused: Pal.orange,
                                    finished: Pal.green, failed: Pal.red, offline: Pal.muted })
  readonly property color tc: stColor[st] || Pal.muted
  readonly property bool big: size === "L"

  title: "printer"
  sub: pr.name.toLowerCase()
  icon: "printer"
  tint: st === "idle" ? Pal.fg : tc
  minimized: size === "M"
  summary: !pr.configured && !pr.mock ? "not set up · coel-bambu-setup"
    : ({ idle: "ready", heating: "heating · " + Math.round(pr.nozzle) + "/" + Math.round(pr.nozzleTarget) + "°",
         printing: pr.pct + "% · " + pr.etaText, paused: "paused · " + pr.pct + "%",
         finished: "finished · clear the plate", failed: "failed · layer " + pr.layer,
         offline: "offline · seen " + pr.hhmm(pr.lastSeen) })[st] || st

  function handleKey(e) { return false; }

  rightData: [
    Mono { text: "● " + card.st; color: card.tc }
  ]

  readonly property bool ended: st === "finished" || st === "failed"
  readonly property bool alarm: st === "failed" || (st === "paused" && pr.fault)

  // ----- controls, per state -----
  component Controls: Flow {
    Layout.fillWidth: true
    spacing: 6
    IslandButton { visible: card.st === "printing"; icon: "pause"; iconFill: true; text: "pause"; onClicked: card.pr.pause() }
    IslandButton { visible: card.st === "paused"; icon: "play"; iconFill: true; text: "resume"; onClicked: card.pr.resume() }
    IslandButton {
      visible: card.st === "printing" || card.st === "paused" || card.st === "heating"
      property bool armed: false
      text: armed ? "really stop?" : "stop"
      tint: Pal.red
      primary: armed
      onClicked: { if (armed) { armed = false; card.pr.stop(); } else { armed = true; disarm.restart(); } }
      Timer { id: disarm; interval: 3000; onTriggered: parent.armed = false }
    }
    IslandButton { visible: card.ended; icon: "broom"; text: "cleared the plate"; onClicked: card.pr.clearPlate() }
    IslandButton { visible: card.big; icon: "arrow-square-out"; text: "Bambu Studio"; tint: Pal.muted; onClicked: card.pr.openStudio() }
  }

  // ===== small =====
  // idle
  ColumnLayout {
    visible: !card.big && card.st === "idle"
    Layout.fillWidth: true
    spacing: 8
    RowLayout {
      spacing: 12
      PhIcon { name: "printer"; color: Pal.muted; font.pixelSize: 30 }
      ColumnLayout {
        spacing: 0
        Mono { text: card.pr.configured || card.pr.mock ? "ready" : "not set up" }
        Mono {
          text: card.pr.configured || card.pr.mock
            ? "bed " + Math.round(card.pr.bed) + "° · nozzle " + Math.round(card.pr.nozzle) + "°" + (card.pr.amsTotal ? " · ams " + card.pr.amsLoaded + "/" + card.pr.amsTotal : "")
            : "run coel-bambu-setup"
          color: Pal.muted
        }
      }
    }
    Mono {
      visible: card.pr.shortFile !== ""
      Layout.fillWidth: true
      text: "last: " + card.pr.shortFile + (card.pr.oldEnd ? " · " + card.pr.status : "") + (card.pr.lastWhen ? " · " + card.pr.lastWhen : "")
      color: Pal.muted
      elide: Text.ElideRight
    }
  }
  // heating
  ColumnLayout {
    visible: !card.big && card.st === "heating"
    Layout.fillWidth: true
    spacing: 6
    Repeater {
      model: [["nozzle", "nozzle", "nozzleTarget"], ["bed", "bed", "bedTarget"]]
      RowLayout {
        required property var modelData
        readonly property real a: card.pr[modelData[1]]
        readonly property real b: card.pr[modelData[2]]
        Layout.fillWidth: true
        spacing: 8
        Mono { Layout.preferredWidth: 52; text: parent.modelData[0]; color: Pal.muted }
        TBar { Layout.fillWidth: true; value: parent.b > 0 ? parent.a / parent.b * 100 : 0; fill: Pal.orange }
        Mono { Layout.preferredWidth: 74; horizontalAlignment: Text.AlignRight; text: Math.round(parent.a) + "/" + Math.round(parent.b) + "°" }
      }
    }
    Mono { Layout.fillWidth: true; text: "starting " + card.pr.shortFile; color: Pal.muted; elide: Text.ElideRight }
  }
  // printing / paused / finished / failed / offline
  ColumnLayout {
    visible: !card.big && card.st !== "idle" && card.st !== "heating"
    Layout.fillWidth: true
    spacing: 10
    RowLayout {
      Layout.fillWidth: true
      spacing: 12
      PlateSnapshot {
        Layout.preferredWidth: 96; Layout.preferredHeight: Math.round(96 / aspect)
        src: card.pr.snapshot
        badge: card.st === "failed" ? "failed" : card.st === "finished" ? "done" : ""
        badgeColor: card.st === "failed" ? Pal.red : Pal.green
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        Mono {
          text: card.st === "finished" ? "✓ done" : card.st === "failed" ? "failed" : card.pr.pct + "%"
          color: card.tc
          font.pixelSize: card.st === "printing" ? 20 : 17; font.weight: Font.Medium
        }
        Mono { Layout.fillWidth: true; text: card.pr.shortFile; elide: Text.ElideRight }
        Mono {
          Layout.fillWidth: true
          color: Pal.muted
          elide: Text.ElideRight
          text: ({ printing: card.pr.etaText + " · " + card.pr.fmtDur(card.pr.remainingMin),
                   paused: (card.pr.fault ? "paused by the printer" : "paused") + " · layer " + card.pr.layer,
                   finished: card.pr.elapsedText, failed: "layer " + card.pr.layer + (card.pr.errorCode ? " · " + card.pr.errorCode : ""),
                   offline: "seen " + card.pr.hhmm(card.pr.lastSeen) + " · " + card.pr.pct + "%" })[card.st] || ""
        }
      }
    }
    TBar { visible: card.st === "printing" || card.st === "paused"; Layout.fillWidth: true; value: card.pr.pct; fill: card.tc }
    Controls { visible: !card.big && (card.ended || card.alarm) }
  }

  // ===== large (hero) =====
  ColumnLayout {
    visible: card.big
    Layout.fillWidth: true
    spacing: 0
    PlateSnapshot {
      Layout.fillWidth: true
      Layout.preferredHeight: Math.round(width / aspect)
      src: card.pr.snapshot
      label: card.pr.snapshotLabel
      badge: card.st === "failed" ? "failed" : card.st === "finished" ? "finished" : ""
      badgeColor: card.st === "failed" ? Pal.red : Pal.green
    }
    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 14
      spacing: 16
      BigRing {
        Layout.leftMargin: 6
        size: 72
        value: card.st === "finished" ? 100 : card.pr.pct
        tint: card.tc
        PhIcon { visible: card.st === "paused" || card.st === "finished" || card.st === "failed"; name: card.st === "paused" ? "pause" : card.st === "finished" ? "check" : "warning-octagon"; fill: card.st !== "finished"; color: card.tc; font.pixelSize: 24 }
        Mono { visible: card.st === "printing" || card.st === "heating" || card.st === "offline"; text: card.st === "heating" ? "…" : card.pr.pct + "%"; font.pixelSize: 20; font.weight: Font.Medium }
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        Mono {
          Layout.fillWidth: true
          font.pixelSize: 16; font.weight: Font.Medium
          color: card.alarm ? Pal.red : Pal.fg
          elide: Text.ElideRight
          text: card.st === "finished" ? card.pr.shortFile + " · finished" + (card.pr.elapsedText ? " in " + card.pr.elapsedText : "")
            : card.alarm ? card.pr.errorText : card.pr.shortFile
        }
        Mono {
          Layout.fillWidth: true
          color: Pal.muted
          elide: Text.ElideRight
          text: card.st === "heating" ? "heating · nozzle " + card.pr.nozzleText + " · bed " + card.pr.bedText
            : card.st === "finished" ? "plate is " + Math.round(card.pr.bed) + "°"
            : card.st === "offline" ? "unreachable · seen " + card.pr.hhmm(card.pr.lastSeen)
            : "layer " + card.pr.layer + " / " + card.pr.totalLayers + (card.st === "printing" ? " · " + card.pr.etaText + " · " + card.pr.remainingText : "")
        }
      }
    }
    Box {
      Layout.fillWidth: true
      Layout.topMargin: 16
      padTop: 12; padSide: 12; padBottom: 8
      legend: "temps"
      GridLayout {
        Layout.fillWidth: true
        columns: 4
        columnSpacing: 10
        rowSpacing: 1
        Mono { text: "nozzle"; color: Pal.muted }
        Mono { Layout.fillWidth: true; text: card.pr.nozzleText }
        Mono { text: "bed"; color: Pal.muted }
        Mono { Layout.fillWidth: true; text: card.pr.bedText }
        Mono { text: "fan"; color: Pal.muted }
        Mono { Layout.fillWidth: true; text: card.pr.fan + "%" }
        Mono { text: "speed"; color: Pal.muted }
        Mono { Layout.fillWidth: true; text: card.pr.speed }
      }
    }
    Controls { Layout.topMargin: 12 }
  }
}
