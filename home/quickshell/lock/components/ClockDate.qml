import QtQuick

// ===== CLOCK + DATE =====
// Bottom-left of the "1a Corner" mockup (sddm-hyprlock/Lockscreen.dc.html):
// small muted date line over a huge 184px/weight-200 clock. Real, live
// time from the start (unlike the auth/media/power state elsewhere in this
// pass) -- same Qt.formatDateTime idiom as sysPanel/buttons/Clock.qml, just
// with no click/active-highlight behavior since this isn't a bar chip.
Column {
  id: clockRoot

  property color fgColor: "#d7dae0"
  property color mutedColor: "#5c6370"

  spacing: 4

  function refresh() {
    const now = new Date();
    dateText.text = Qt.formatDateTime(now, "dddd, d MMMM");
    // "AP" has to be in the same formatDateTime call as "hh" for Qt to
    // switch it to 12-hour -- format both together, then split, rather
    // than a separate 24h-formatted call for the digits.
    const parts = Qt.formatDateTime(now, "hh:mm AP").split(" ");
    timeText.text = parts[0];
    apText.text = parts[1];
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: clockRoot.refresh()
  }

  Text {
    id: dateText
    leftPadding: 10
    color: clockRoot.mutedColor
    font.family: "JetBrains Mono"
    font.pixelSize: 18
  }

  Item {
    width: timeText.width + apText.width + 10
    height: timeText.height

    Text {
      id: timeText
      color: clockRoot.fgColor
      font.family: "JetBrains Mono"
      font.weight: Font.ExtraLight
      font.pixelSize: 184
      font.letterSpacing: -8
    }

    // Baseline-anchored beside the huge digits rather than embedded in
    // the same font size -- same pairing the mock's own "1c" variant uses
    // for its seconds readout next to the main clock, just applied to
    // AM/PM here instead.
    Text {
      id: apText
      anchors.left: timeText.right
      anchors.leftMargin: 10
      anchors.baseline: timeText.baseline
      color: clockRoot.mutedColor
      font.family: "JetBrains Mono"
      font.pixelSize: 22
    }
  }
}
