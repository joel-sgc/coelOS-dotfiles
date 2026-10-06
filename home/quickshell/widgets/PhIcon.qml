import QtQuick
import "../sysPanel/Phosphor.js" as Phosphor

// One Phosphor glyph by name; `fill` picks the solid weight.
Text {
  property string name
  property bool fill: false
  text: Phosphor.icon(name)
  font.family: fill ? Pal.fillFamily : "Phosphor"
  font.pixelSize: 16
  color: Pal.fg
}
