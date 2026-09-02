import QtQuick

// ===== CLOCK =====
// Same format as waybar's clock module ({:L%A @ %I:%M %p}) -- Qt's own
// format tokens (dddd/hh/mm/AP) do this natively via Qt.formatDateTime,
// no manual strftime-style parsing needed. Re-reads Date.now() every 30s;
// no seconds shown, so that's plenty granular without a 1s timer running
// forever. Plain Text rather than Button -- nothing to click here, waybar's
// clock only pops its own tooltip calendar, which isn't ported (that's a
// real popup, out of scope for "a few buttons").
Text {
  id: clockRoot

  function refresh() {
    text = Qt.formatDateTime(new Date(), "dddd @ hh:mm AP");
  }

  color: root.fgColor
  font.family: "FiraCode Nerd Font Mono"
  font.pixelSize: 16

  Component.onCompleted: refresh()

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: clockRoot.refresh()
  }
}
