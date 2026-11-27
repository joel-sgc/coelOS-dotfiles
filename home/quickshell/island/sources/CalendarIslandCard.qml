import QtQuick
import QtQuick.Layouts
import "../../widgets"
import "../../desktop/data"
import ".."

// The pill's calendar card (Pill Board `calCard`): the next few events.
Column {
  id: card
  property var source
  property var engine
  property var screen
  readonly property var nd: NextData
  readonly property var upcoming: nd.events.filter(e => e.end > nd.now).slice(0, 3)

  width: 340
  spacing: 2

  CardHead { width: parent.width; icon: "calendar-blank"; tint: Pal.yellow; title: "Today"; sub: "· " + card.nd.today.length + " events" }
  Item { width: 1; height: 6 }
  Repeater {
    model: card.upcoming.length
    RowLayout {
      required property int index
      readonly property var e: card.upcoming[index] || ({ start: 0, end: 0 })
      readonly property int mins: Math.round((e.start - card.nd.now) / 60000)
      width: card.width
      spacing: 10
      Mono {
        Layout.preferredWidth: 88
        Layout.alignment: Qt.AlignTop
        text: parent.e.start <= card.nd.now ? "now" : parent.mins < 60 ? "in " + parent.mins + " min"
          : card.nd.daysFrom(parent.e.start) === 0 ? card.nd.hhmm(parent.e.start)
          : card.nd.dayWord(parent.e.start) + " " + card.nd.hhmm(parent.e.start)
        color: parent.index === 0 ? Pal.yellow : parent.mins > 24 * 60 ? Pal.muted : Pal.fg
      }
      Column {
        Layout.fillWidth: true
        Mono { width: parent.width; text: parent.parent.e.title || ""; elide: Text.ElideRight }
        Mono {
          width: parent.width
          text: card.nd.hhmm(parent.parent.e.start) + " – " + card.nd.hhmm(parent.parent.e.end) + (parent.parent.e.where ? " · " + parent.parent.e.where : "")
          color: Pal.muted; font.pixelSize: 11; elide: Text.ElideRight
        }
      }
    }
  }
  Mono { visible: card.upcoming.length === 0; text: "nothing coming up"; color: Pal.muted }
}
