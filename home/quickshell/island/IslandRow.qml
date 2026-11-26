import QtQuick

// One line of the island: groups 8 px apart, parts within a group 5 px apart.
//
// Repeaters are driven by counts and read their data by index, never by the
// arrays themselves: sources rebuild their chip arrays on every tick (the
// assistant's elapsed time runs at 10 Hz), and an array model makes a Repeater
// destroy and recreate every delegate on each change (flicker, cursor resets).
Row {
  id: rowRoot
  property var groups: []
  spacing: 8
  height: 26

  Repeater {
    model: rowRoot.groups.length
    Row {
      id: group
      required property int index
      readonly property var parts: rowRoot.groups[index] || []
      spacing: 5
      anchors.verticalCenter: parent ? parent.verticalCenter : undefined
      Repeater {
        model: group.parts.length
        IslandPart {
          required property int index
          part: group.parts[index] || ({ k: "space", w: 0 })
          anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        }
      }
    }
  }
}
