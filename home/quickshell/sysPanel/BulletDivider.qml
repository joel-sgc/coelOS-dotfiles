import QtQuick
import QtQuick.Layouts

// ===== BULLET DIVIDER =====
// "•" separator between the bar's right-side panel-item chips (bluetooth/
// network/volume/cpu/battery). Not used between the tray and the first
// chip -- Tray.qml already carries its own conditional line divider
// (hidden whenever the tray is empty), which a second divider here would
// only have duplicated.
Text {
  Layout.alignment: Qt.AlignVCenter
  text: "•"
  // mutedColor (#5c6370), not hoverColor (#404754) -- sits between the
  // near-invisible hover-background tone and fgColor's full brightness,
  // same "readable but secondary" role it already plays as the label
  // color throughout every dropdown in this panel.
  color: root.mutedColor
  font.family: "JetBrains Mono"
  font.pixelSize: 10
}
