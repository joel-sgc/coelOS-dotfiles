import QtQuick
import QtQuick.Layouts
import "../.."
import "../../widgets"
import "../../modes"
import ".."
import "../data"

// Kanban: F full (760 px, three columns), C compact (the doing column, or in
// class the cards tagged with the class's course code), M minimized.
// Keys: h/j/k/l move, H/L move the card, space advance, e/enter edit, a/n new,
// x delete, f filter (cycles tags; in class it clears the class filter).
// Mouse: click a row to select it, click its box to advance, double-click to edit.
CardFrame {
  id: card
  property string size: "C"
  property string flavor: ""
  readonly property var kb: KanbanData

  // ----- filter -----
  // Class flavor: the course code from the class's title ("COMP348 Lecture" ->
  // "comp348"), matched against card tags ignoring case and spaces.
  readonly property string classTag: {
    if (flavor !== "class" || !Modes.classNow) return "";
    const m = String(Modes.classNow.title).match(/([A-Za-z]{2,4})\s?(\d{3})/);
    return m ? (m[1] + m[2]).toLowerCase() : "";
  }
  property string userFilter: ""
  property bool classFilterOff: false
  readonly property string filter: userFilter !== "" ? userFilter : (classFilterOff ? "" : classTag)
  function norm(t) { return String(t || "").toLowerCase().replace(/\s+/g, ""); }
  function rowsOf(col) { return filter === "" ? kb.cardsOf(col) : kb.cardsOf(col).filter(c => norm(c.tag) === filter); }
  readonly property var tags: {
    const out = [];
    for (const col of kb.columns) for (const c of col.cards) { const t = norm(c.tag); if (t && out.indexOf(t) < 0) out.push(t); }
    return out.sort();
  }
  function cycleFilter() {
    if (classTag !== "" && !classFilterOff && userFilter === "") { classFilterOff = true; return; }
    const i = tags.indexOf(userFilter);
    userFilter = i + 1 < tags.length ? tags[i + 1] : "";
  }
  onFlavorChanged: { classFilterOff = false; userFilter = ""; }

  // Compact: doing, or (filtered) doing + todo.
  readonly property var compactRows: {
    const doing = rowsOf(1).map(c => ({ c: c, col: 1 }));
    return filter === "" ? doing : doing.concat(rowsOf(0).map(c => ({ c: c, col: 0 })));
  }

  // ----- selection -----
  property int kcol: size === "F" ? 0 : 1
  property int krow: 0
  function listFor(col) { return size === "F" ? rowsOf(col) : (col === 1 ? compactRows.map(r => r.c) : []); }
  function current() {
    const l = size === "F" ? rowsOf(kcol) : compactRows.map(r => r.c);
    return l.length ? l[Math.min(krow, l.length - 1)] : null;
  }
  function clampRow() {
    const n = size === "F" ? rowsOf(kcol).length : compactRows.length;
    krow = Math.max(0, Math.min(krow, n - 1));
  }

  function handleKey(e) {
    const t = e.text, cur = current();
    if (t === "H" || t === "L") {
      if (cur) { const at = kb.find(kb.columns, cur.id); if (at) kb.moveCard(cur.id, Math.max(0, Math.min(2, at.col + (t === "L" ? 1 : -1))), 1e9); }
    }
    else if (size === "F" && (t === "h" || e.key === Qt.Key_Left)) { kcol = Math.max(0, kcol - 1); clampRow(); }
    else if (size === "F" && (t === "l" || e.key === Qt.Key_Right)) { kcol = Math.min(2, kcol + 1); clampRow(); }
    else if (t === "j" || e.key === Qt.Key_Down) { krow += 1; clampRow(); }
    else if (t === "k" || e.key === Qt.Key_Up) krow = Math.max(0, krow - 1);
    else if (e.key === Qt.Key_Space && cur) kb.advance(cur.id);
    else if (t === "x" && cur) { kb.deleteCard(cur.id); clampRow(); }
    else if (t === "a" || t === "n") kb.openNew(size === "F" ? kcol : 1);
    else if ((t === "e" || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && cur) kb.openEdit(cur);
    else if (t === "f") cycleFilter();
    else return false;
    return true;
  }

  title: "kanban"
  sub: filter !== "" ? "#" + filter : (size === "F" ? "~/dots/shell" : "doing")
  summary: kb.doingCount + " doing · " + kb.doneCount + "/" + kb.total + " done"
  minimized: size === "M"

  rightData: [
    Rectangle {
      Layout.preferredWidth: 70; Layout.preferredHeight: 6
      radius: Globals.eyeCandyOff ? 0 : 1
      color: Pal.track
      clip: true
      Rectangle { width: card.kb.total ? parent.width * card.kb.doneCount / card.kb.total : 0; height: parent.height; color: Pal.green }
      Rectangle {
        x: card.kb.total ? parent.width * card.kb.doneCount / card.kb.total : 0
        width: card.kb.total ? parent.width * card.kb.doingCount / card.kb.total : 0
        height: parent.height; color: Pal.yellow
      }
    },
    Mono { text: card.kb.donePct + "%"; color: Pal.muted }
  ]

  // One task row (Desktop Board `taskRow`).
  component TaskRow: Rectangle {
    id: tr
    property var c: ({})
    property int col: 0
    property bool selected: false
    Layout.fillWidth: true
    implicitHeight: rowL.implicitHeight + 6
    radius: Globals.eyeCandyOff ? 0 : 2
    color: selected && card.focused ? Pal.edge : "transparent"
    readonly property var due: card.kb.dueInfo(c.due)
    RowLayout {
      id: rowL
      anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 6 }
      spacing: 4
      Mono {
        Layout.preferredWidth: 24
        text: tr.col === 2 ? "[x]" : tr.col === 1 ? "[~]" : "[ ]"
        color: tr.col === 2 ? Pal.green : tr.col === 1 ? Pal.yellow : Pal.muted
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: card.kb.advance(tr.c.id) }
      }
      Mono {
        Layout.fillWidth: true
        text: (tr.c.high ? "! " : "") + (tr.c.title || "")
        color: tr.col === 2 ? Pal.muted : tr.c.high ? Pal.red : Pal.fg
        font.strikeout: tr.col === 2
        elide: Text.ElideRight
      }
      Mono { visible: !!tr.due && tr.col !== 2; text: tr.due ? tr.due.text : ""; color: tr.due ? tr.due.color : Pal.muted; font.pixelSize: 11 }
      Mono { visible: !!tr.c.tag; text: "#" + (tr.c.tag || ""); color: Pal.muted; font.pixelSize: 11 }
    }
    MouseArea {
      anchors.fill: parent
      anchors.leftMargin: 30
      onClicked: {
        card.kcol = card.size === "F" ? tr.col : 1;
        const l = card.size === "F" ? card.rowsOf(tr.col) : card.compactRows.map(r => r.c);
        card.krow = Math.max(0, l.findIndex(x => x.id === tr.c.id));
      }
      onDoubleClicked: card.kb.openEdit(tr.c)
    }
  }

  // ----- full -----
  RowLayout {
    visible: card.size === "F"
    Layout.fillWidth: true
    Layout.topMargin: 8
    spacing: 10
    Repeater {
      model: 3
      Box {
        id: colBox
        required property int index
        readonly property var rows: card.rowsOf(index)
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        padTop: 12; padSide: 4; padBottom: 6
        legend: ["todo", "doing", "done"][index]
        legendColor: index === 1 ? Pal.yellow : index === 2 ? Pal.green : Pal.muted
        rightLegend: String(rows.length)
        borderColor: card.focused && card.kcol === index ? Pal.dim : Pal.faint
        Mono { visible: colBox.rows.length === 0; Layout.leftMargin: 6; text: "—"; color: Pal.muted }
        Repeater {
          model: colBox.rows.length
          TaskRow {
            required property int index
            c: colBox.rows[index] || ({})
            col: colBox.index
            selected: card.kcol === colBox.index && card.krow === index
          }
        }
      }
    }
  }
  Hints {
    visible: card.size === "F"
    Layout.fillWidth: true
    Layout.topMargin: 12
    items: [["n", "new"], ["space", "advance"], ["h/l", "column"], ["e", "edit"], ["f", "filter"]]
  }

  // ----- compact -----
  Box {
    visible: card.size !== "F"
    Layout.fillWidth: true
    padTop: 12; padSide: 4; padBottom: 6
    legend: card.filter !== "" ? card.filter : "doing"
    legendColor: Pal.yellow
    rightLegend: String(card.compactRows.length)
    Mono { visible: card.compactRows.length === 0; Layout.leftMargin: 6; text: card.filter !== "" ? "nothing tagged #" + card.filter : "nothing in progress"; color: Pal.muted }
    Repeater {
      model: card.compactRows.length
      TaskRow {
        required property int index
        readonly property var r: card.compactRows[index] || ({ c: {}, col: 1 })
        c: r.c
        col: r.col
        selected: card.krow === index
      }
    }
  }
  Mono {
    visible: card.size !== "F" && card.classTag !== ""
    Layout.topMargin: 8
    text: card.classFilterOff ? "class filter off · f to cycle tags" : "filtered by the class · f clear"
    color: Pal.muted
  }
}
