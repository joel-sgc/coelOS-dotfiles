import QtQuick
import QtQuick.Layouts
import "../.."
import "../../widgets"
import ".."
import "../data"

// Next up (Desktop Board `nextUp` / `windDown`): events merged with due dates.
// Sizes: L hero (760), R regular, C compact, M minimized. Flavors:
//   ""        morning/default: countdown to the next event, today's timeline, coming up
//             (with nothing on the calendar today it turns into the free-day card)
//   class     the class you're in: time left, progress, what comes after
//   winddown  tomorrow first thing, what's still open (`>` moves it to tomorrow), today
CardFrame {
  id: card
  property string size: "L"
  property string flavor: ""
  readonly property var nd: NextData

  // Moved off today (here or on the calendar card): that day's agenda.
  readonly property var cd: CalendarData
  readonly property var dayEvents: nd.eventsOn(cd.selKey)
  readonly property var dayRows: nd.rowsOn(cd.selKey)
  readonly property string kind: !cd.viewingToday ? "day"
    : flavor === "class" && nd.current ? "class"
    : flavor === "winddown" ? "winddown" : nd.free ? "free" : "morning"
  readonly property bool big: size === "L"
  readonly property bool full: size === "L" || size === "R"

  title: "next up"
  sub: kind === "day" ? cd.selLabel : kind === "class" ? "in class" : kind === "winddown" ? "wind-down"
    : Qt.formatDate(new Date(nd.now), "dddd").toLowerCase()
  tint: kind === "class" ? Pal.yellow : kind === "winddown" ? Pal.purple : Pal.fg
  summary: kind === "day" ? cd.selLabel + " · " + dayEvents.length + (dayEvents.length === 1 ? " event" : " events")
    : nd.summaryFor(kind === "class" ? "class" : kind === "winddown" ? "winddown" : "")
  minimized: size === "M"

  function handleKey(e) {
    if (kind === "winddown" && e.text === ">") { nd.moveOpenToTomorrow(); return true; }
    return cd.handleDayKey(e);   // h/l day, [ ] week, t today
  }

  rightData: [
    TextButton { onClicked: card.cd.shift(-1); Mono { text: "‹"; color: Pal.muted } },
    TextButton {
      visible: !card.cd.viewingToday
      onClicked: card.cd.goToday()
      Mono { text: "t"; color: Pal.yellow }
      Mono { text: "today"; color: Pal.muted }
    },
    TextButton { onClicked: card.cd.shift(1); Mono { text: "›"; color: Pal.muted } }
  ]

  function span(e) { return nd.hhmm(e.start) + " – " + nd.hhmm(e.end) + (e.where ? " · " + e.where : ""); }

  // ----- shared pieces -----
  component Big: RowLayout {   // label / title / sub on the left, number + unit on the right
    property string label: ""
    property string head: ""
    property color headColor: Pal.fg
    property string detail: ""
    property string num: ""
    property string unit: ""
    property color numColor: Pal.blue
    property string glyph: ""
    Layout.fillWidth: true
    spacing: 16
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 2
      Mono { text: parent.parent.label; color: Pal.muted }
      Mono {
        Layout.fillWidth: true
        text: parent.parent.head; color: parent.parent.headColor
        font.pixelSize: card.big ? 34 : 22; font.weight: Font.Medium; font.letterSpacing: -0.6
        elide: Text.ElideRight
      }
      Mono { Layout.fillWidth: true; visible: text !== ""; text: parent.parent.detail; color: Pal.muted; elide: Text.ElideRight }
    }
    Row {
      Layout.alignment: Qt.AlignBottom | Qt.AlignRight
      visible: parent.num !== ""
      Mono { text: parent.parent.num; color: parent.parent.numColor; font.pixelSize: card.big ? 40 : 26; font.weight: Font.Medium }
      Mono { anchors.baseline: parent.children[0].baseline; text: parent.parent.unit; color: Pal.muted }
    }
    PhIcon { Layout.alignment: Qt.AlignBottom | Qt.AlignRight; visible: parent.glyph !== ""; name: parent.glyph || "coffee"; color: Pal.green; font.pixelSize: 40 }
  }

  component Rows: ColumnLayout {   // Desktop Board `upRows`
    property var rows: []
    Layout.fillWidth: true
    spacing: 0
    Mono { visible: parent.rows.length === 0; text: "nothing"; color: Pal.muted }
    Repeater {
      model: parent.rows.length
      RowLayout {
        required property int index
        readonly property var r: parent.rows[index] || ({})
        Layout.fillWidth: true
        Layout.preferredHeight: 22
        spacing: 8
        Mono { Layout.preferredWidth: 58; text: parent.r.when || ""; color: parent.r.whenColor || Pal.fg }
        PhIcon { Layout.preferredWidth: 14; name: parent.r.icon || "calendar-blank"; color: parent.r.iconColor || Pal.fg; font.pixelSize: 13 }
        Mono { Layout.fillWidth: true; text: parent.r.title || ""; elide: Text.ElideRight }
        Mono { visible: !!parent.r.meta; text: parent.r.meta || ""; color: Pal.muted }
        Mono { visible: !!parent.r.tag; text: "#" + (parent.r.tag || ""); color: Pal.muted; font.pixelSize: 11 }
      }
    }
  }

  // ===== morning / default =====
  Big {
    visible: card.full && card.kind === "morning"
    label: card.nd.next ? (card.nd.current ? "after " + card.nd.current.title : "next") : "today"
    head: card.nd.next && card.nd.daysFrom(card.nd.next.start) === 0 ? card.nd.next.title : "Nothing else today"
    headColor: card.nd.next && card.nd.daysFrom(card.nd.next.start) === 0 ? Pal.fg : Pal.muted
    detail: card.nd.next ? (card.nd.daysFrom(card.nd.next.start) === 0 ? card.span(card.nd.next)
      : "next: " + card.nd.dayWord(card.nd.next.start) + " " + card.nd.hhmm(card.nd.next.start) + " · " + card.nd.next.title) : ""
    num: card.nd.next && card.nd.daysFrom(card.nd.next.start) === 0 ? card.nd.untilNext.n : ""
    unit: card.nd.untilNext.unit
    numColor: card.nd.next ? card.nd.next.color : Pal.blue
  }
  Box {
    visible: card.big && card.kind === "morning"
    Layout.fillWidth: true
    Layout.topMargin: 16
    padTop: 14; padSide: 12; padBottom: 16
    legend: "today"
    Timeline { Layout.fillWidth: true; events: card.nd.today; now: card.nd.now }
  }
  Box {
    visible: card.full && card.kind === "morning"
    Layout.fillWidth: true
    Layout.topMargin: 16
    padTop: 14; padSide: 12; padBottom: 10
    legend: "coming up"
    rightLegend: card.big ? card.nd.today.length + (card.nd.today.length === 1 ? " event · " : " events · ") + card.nd.dues.length + " due" : ""
    Rows { rows: card.big ? card.nd.comingUp.slice(0, 6) : card.nd.comingUp.slice(0, 3) }
  }

  // ===== free day =====
  Big {
    visible: card.big && card.kind === "free"
    label: "today"
    head: "Nothing scheduled"
    headColor: Pal.green
    detail: card.nd.next ? "next event " + Qt.formatDateTime(new Date(card.nd.next.start), "dddd hh:mm") + " · " + card.nd.next.title : "nothing on the calendar"
    glyph: "coffee"
  }
  Box {
    visible: card.big && card.kind === "free"
    Layout.fillWidth: true
    Layout.topMargin: 16
    padTop: 14; padSide: 12; padBottom: 16
    legend: "due soon"
    rightLegend: card.nd.dues.length + " due · " + card.nd.dueToday + " today"
    Rows { rows: card.nd.dueSoon }
  }
  Box {
    visible: card.big && card.kind === "free"
    Layout.fillWidth: true
    Layout.topMargin: 16
    padTop: 14; padSide: 12; padBottom: 10
    legend: "the day"
    Flow {
      Layout.fillWidth: true
      spacing: 18
      Mono { visible: WeatherData.loaded; text: WeatherData.cv(WeatherData.tempC) + "° " + WeatherData.label(WeatherData.code); color: Pal.yellow }
      Mono { visible: WeatherData.loaded; text: "· high " + WeatherData.cv(WeatherData.hiC) + "°"; color: Pal.muted }
      Mono { text: KanbanData.doneCount + "/" + KanbanData.total + " done"; color: Pal.green }
      Mono { text: "on the kanban"; color: Pal.muted }
    }
  }

  // ===== class =====
  Big {
    visible: card.kind === "class" && card.size !== "M"
    label: "now"
    head: card.nd.current ? card.nd.current.title : ""
    headColor: Pal.yellow
    detail: card.nd.current ? card.span(card.nd.current) : ""
    num: String(card.nd.classLeftMin)
    unit: " min left"
    numColor: Pal.fg
  }
  TBar {
    visible: card.kind === "class" && card.size !== "M"
    Layout.fillWidth: true
    Layout.topMargin: 14
    implicitHeight: card.big ? 8 : 6
    value: card.nd.classProgress
    fill: Pal.yellow
  }
  RowLayout {
    visible: card.kind === "class" && card.size !== "M"
    Layout.fillWidth: true
    Layout.topMargin: 4
    Mono { text: card.nd.current ? card.nd.hhmm(card.nd.current.start) : ""; color: Pal.muted; font.pixelSize: 11 }
    Item { Layout.fillWidth: true }
    Mono { text: card.nd.current ? card.nd.hhmm(card.nd.current.end) : ""; color: Pal.muted; font.pixelSize: 11 }
  }
  Box {
    visible: card.kind === "class" && card.size !== "M"
    Layout.fillWidth: true
    Layout.topMargin: 16
    padTop: 14; padSide: 12; padBottom: 10
    legend: "after this"
    Rows { rows: card.nd.afterClass.slice(0, card.big ? 5 : 3) }
  }

  // ===== wind-down =====
  Big {
    visible: card.big && card.kind === "winddown"
    label: card.nd.lateNight ? "later today, first thing" : "tomorrow, first thing"
    head: card.nd.tomorrowFirst ? card.nd.tomorrowFirst.title : (card.nd.lateNight ? "Nothing today" : "Nothing tomorrow")
    headColor: card.nd.tomorrowFirst ? Pal.fg : Pal.muted
    detail: card.nd.tomorrowFirst ? card.span(card.nd.tomorrowFirst) : ""
    num: card.nd.tomorrowFirst ? card.nd.untilText(card.nd.tomorrowFirst.start).n : ""
    unit: card.nd.tomorrowFirst ? card.nd.untilText(card.nd.tomorrowFirst.start).unit : ""
    numColor: Pal.purple
  }
  Box {
    visible: card.big && card.kind === "winddown"
    Layout.fillWidth: true
    Layout.topMargin: 16
    padTop: 12; padSide: 4; padBottom: 6
    legend: "left open"
    rightLegend: card.nd.leftOpen.length + " · move to tomorrow >"
    Mono { visible: card.nd.leftOpen.length === 0; Layout.leftMargin: 6; text: "nothing open"; color: Pal.muted }
    Repeater {
      model: card.nd.leftOpen.length
      RowLayout {
        required property int index
        readonly property var lo: card.nd.leftOpen[index] || ({ c: {}, col: 0 })
        Layout.fillWidth: true
        Layout.leftMargin: 6; Layout.rightMargin: 6
        Layout.preferredHeight: 22
        spacing: 4
        Mono { Layout.preferredWidth: 24; text: parent.lo.col === 1 ? "[~]" : "[ ]"; color: parent.lo.col === 1 ? Pal.yellow : Pal.muted }
        Mono { Layout.fillWidth: true; text: parent.lo.c.title || ""; elide: Text.ElideRight }
        Mono { visible: !!parent.lo.c.tag; text: "#" + (parent.lo.c.tag || ""); color: Pal.muted; font.pixelSize: 11 }
      }
    }
  }
  Box {
    visible: card.big && card.kind === "winddown"
    Layout.fillWidth: true
    Layout.topMargin: 16
    padTop: 12; padSide: 12; padBottom: 10
    legend: "today"
    RowLayout {
      spacing: 5
      Repeater {
        model: Math.min(8, PomodoroData.doneToday)
        Rectangle { width: 8; height: 8; radius: 4; color: Pal.red }
      }
      Mono { Layout.leftMargin: 4; text: PomodoroData.doneToday + " pomodoros · " + PomodoroData.todayText.split(" · ")[1]; color: Pal.muted }
    }
    Mono { Layout.fillWidth: true; Layout.topMargin: 6; text: card.nd.todayLine; elide: Text.ElideRight }
  }

  // ===== another day =====
  Big {
    visible: card.kind === "day" && card.size !== "M"
    label: card.cd.selLabel
    head: card.dayEvents.length ? card.dayEvents[0].title : "Nothing scheduled"
    headColor: card.dayEvents.length ? Pal.fg : Pal.muted
    detail: card.dayEvents.length ? card.span(card.dayEvents[0]) + (card.dayEvents.length > 1 ? " · first of " + card.dayEvents.length : "")
      : (card.nd.duesOn(card.cd.selKey).length ? card.nd.duesOn(card.cd.selKey).length + " due" : "")
    num: card.cd.selOffset > 0 ? String(card.cd.selOffset) : ""
    unit: card.cd.selOffset === 1 ? " day away" : " days away"
    numColor: Pal.yellow
  }
  Box {
    visible: card.big && card.kind === "day"
    Layout.fillWidth: true
    Layout.topMargin: 16
    padTop: 14; padSide: 12; padBottom: 16
    legend: "the day"
    Timeline { Layout.fillWidth: true; events: card.dayEvents; now: card.cd.viewingToday ? card.nd.now : 0 }
  }
  Box {
    visible: card.kind === "day" && card.size !== "M"
    Layout.fillWidth: true
    Layout.topMargin: 16
    padTop: 14; padSide: 12; padBottom: 10
    legend: "events & due"
    rightLegend: card.dayEvents.length + (card.dayEvents.length === 1 ? " event · " : " events · ") + card.nd.duesOn(card.cd.selKey).length + " due"
    Rows { rows: card.big ? card.dayRows : card.dayRows.slice(0, 4) }
  }

  // ===== compact (every flavor except class, which reuses the big layout) =====
  ColumnLayout {
    visible: card.size === "C" && card.kind !== "class" && card.kind !== "day"
    Layout.fillWidth: true
    spacing: 6
    RowLayout {
      Layout.fillWidth: true
      spacing: 10
      PhIcon {
        name: card.kind === "free" ? "coffee" : card.kind === "winddown" ? "moon-stars" : (card.nd.next && card.nd.next.isClass ? "chalkboard-teacher" : "calendar-blank")
        color: card.kind === "free" ? Pal.green : card.kind === "winddown" ? Pal.purple : (card.nd.next ? card.nd.next.color : Pal.blue)
        font.pixelSize: 15
      }
      Mono {
        text: card.kind === "free" ? "free day" : card.kind === "winddown" ? (card.nd.tomorrowFirst ? card.nd.hhmm(card.nd.tomorrowFirst.start) : "tomorrow")
          : (card.nd.next ? card.nd.untilNext.n + card.nd.untilNext.unit.trim().charAt(0) : "done")
        color: card.kind === "free" ? Pal.green : card.kind === "winddown" ? Pal.purple : (card.nd.next ? card.nd.next.color : Pal.muted)
        font.pixelSize: 20; font.weight: Font.Medium
      }
      Mono {
        Layout.fillWidth: true
        text: card.kind === "free" ? "· nothing on the calendar"
          : card.kind === "winddown" ? (card.nd.tomorrowFirst ? card.nd.tomorrowFirst.title : "nothing tomorrow")
          : (card.nd.next ? card.nd.next.title + (card.nd.next.where ? " · " + card.nd.next.where : "") : "nothing else today")
        color: card.kind === "free" ? Pal.muted : Pal.fg
        elide: Text.ElideRight
      }
    }
    Mono {
      Layout.fillWidth: true
      color: Pal.muted
      elide: Text.ElideRight
      text: {
        const nd = card.nd, due = nd.dues.find(d => nd.daysFrom(d.at) <= 0);
        if (card.kind === "winddown") return nd.leftOpen.length + " left open · " + PomodoroData.doneToday + " pomodoros today";
        const then = card.kind === "free" ? (nd.next ? "next " + nd.dayWord(nd.next.start) + " " + nd.hhmm(nd.next.start) + " " + nd.next.title : "")
          : (nd.later.length > 1 && nd.daysFrom(nd.later[1].start) === 0 ? "then " + nd.hhmm(nd.later[1].start) + " " + nd.later[1].title : "");
        return [then, due ? "due today: " + due.title : ""].filter(s => s).join(" · ") || "nothing due today";
      }
    }
  }
}
