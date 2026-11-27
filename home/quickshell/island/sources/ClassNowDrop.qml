import QtQuick
import "../../widgets"
import ".."

// Detail under the "starts now" interrupt (Pill Board `cal-now`): times, place,
// snooze 5 min or dismiss.
Column {
  id: drop
  property var source   // CalendarSource
  property var engine
  property var screen
  property var entry    // the interrupt, with .event
  readonly property var e: entry && entry.event ? entry.event : ({ start: 0, end: 0, where: "" })

  width: 360
  spacing: 8
  Mono {
    text: Qt.formatDateTime(new Date(drop.e.start), "hh:mm") + " – " + Qt.formatDateTime(new Date(drop.e.end), "hh:mm") + (drop.e.where ? " · " + drop.e.where : "")
  }
  Row {
    spacing: 6
    IslandButton { text: "snooze 5 min"; onClicked: drop.source.snooze(drop.e) }
    IslandButton { text: "dismiss"; tint: Pal.muted; onClicked: drop.source.dismiss() }
  }
}
