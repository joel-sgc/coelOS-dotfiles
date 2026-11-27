import QtQuick
import QtQuick.Layouts
import "../.."
import "../../widgets"
import "../../island"
import ".."
import "../data"

// Pomodoro: L the deep-work hero (big ring, what you're working on, controls),
// C compact, M minimized. Keys: space start/pause, s skip, r reset, t next task.
CardFrame {
  id: card
  property string size: "C"
  property string flavor: ""
  readonly property var pd: PomodoroData

  title: "pomodoro"
  sub: pd.modeName
  tint: size === "L" ? pd.modeColor : Pal.fg
  summary: pd.summary
  minimized: size === "M"

  function handleKey(e) { return pd.handleKey(e); }

  rightData: [
    Mono { visible: card.size === "L"; text: "session " + card.pd.session + " of 4"; color: Pal.muted }
  ]

  readonly property string timeText: pd.fmt(pd.secsLeft)
  readonly property string stateText: (pd.running ? "▶ " : pd.paused ? "❚❚ " : "· ") + pd.modeName

  // The four session dots and today's tally.
  component Dots: RowLayout {
    spacing: 6
    Repeater {
      model: 4
      Rectangle { required property int index; width: 8; height: 8; radius: 4; color: index < card.pd.filled ? Pal.red : Pal.faint }
    }
    Mono { Layout.leftMargin: 4; text: card.pd.todayText; color: Pal.muted }
  }

  // ----- large -----
  RowLayout {
    visible: card.size === "L"
    Layout.fillWidth: true
    Layout.topMargin: 8
    Layout.bottomMargin: 8
    spacing: 28
    BigRing {
      Layout.leftMargin: 6
      size: 210
      value: card.pd.progress * 100
      tint: card.pd.modeColor
      Column {
        spacing: 2
        Mono { anchors.horizontalCenter: parent.horizontalCenter; text: card.timeText; font.pixelSize: 44; font.weight: Font.Medium; font.letterSpacing: -0.9 }
        Mono { anchors.horizontalCenter: parent.horizontalCenter; text: card.stateText; color: card.pd.modeColor }
      }
    }
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 14
      Box {
        Layout.fillWidth: true
        padTop: 14; padSide: 12; padBottom: 12
        legend: "working on"
        rightLegend: "t next"
        Mono {
          Layout.fillWidth: true
          text: card.pd.task ? card.pd.task.title : "nothing picked"
          color: card.pd.task ? Pal.fg : Pal.muted
          font.pixelSize: 17; font.weight: Font.Medium
          elide: Text.ElideRight
        }
        RowLayout {
          visible: !!card.pd.task
          spacing: 10
          Mono { visible: !!(card.pd.task && card.pd.task.tag); text: "#" + (card.pd.task ? card.pd.task.tag : ""); color: Pal.muted; font.pixelSize: 11 }
          Mono { text: "◷ " + (card.pd.task ? (card.pd.task.pomos || 0) : 0) + " pomodoros"; color: Pal.muted }
          Mono { text: "· from kanban"; color: Pal.muted }
        }
      }
      RowLayout {
        spacing: 6
        IslandButton { text: card.pd.btnLabel + " ␣"; onClicked: card.pd.toggle() }
        IslandButton { text: "skip s"; onClicked: card.pd.advance(false) }
        IslandButton { text: "reset r"; tint: Pal.muted; onClicked: card.pd.reset() }
      }
      Dots {}
    }
  }

  // ----- compact -----
  RowLayout {
    visible: card.size !== "L"
    Layout.fillWidth: true
    spacing: 14
    BigRing {
      Layout.leftMargin: 6
      size: 64
      value: card.pd.progress * 100
      tint: card.pd.modeColor
      Mono { text: card.timeText; font.pixelSize: 13; font.weight: Font.Medium }
    }
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 3
      Mono { text: card.stateText + (card.pd.mode === "focus" ? " · session " + card.pd.session + " of 4" : ""); color: card.pd.modeColor }
      Mono { Layout.fillWidth: true; text: card.pd.task ? card.pd.task.title : "nothing picked · t"; color: card.pd.task ? Pal.fg : Pal.muted; elide: Text.ElideRight }
      Dots {}
    }
  }
}
