import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// ===== KANBAN WIDGET =====
// Three-column board (todo / doing / done) persisted as JSON at
// ~/.local/share/coel/kanban.json (hand-editable; edits made while running
// are picked up). Cards: { id, title, notes, tag, high, due("YYYY-MM-DD") }.
//
//  - Drag a card to move/reorder it. The drag is hand-rolled (a ghost item
//    plus hit-testing) rather than Qt's Drag/DropArea: it needs no reparenting
//    and keeps the card in its column until the drop lands.
//  - Click a card to select it, double-click (or e / Enter) to edit; the
//    [ ] / [~] / [x] box advances it; x deletes. Title text understands
//    "!high", "#tag" and "@today|tomorrow|fri|2026-10-20" (see parseTitle).
//  - The editor is KanbanEditor.qml, a modal Overlay window.
Scope {
  id: kb

  property var screen: null
  property alias shown: board.shown
  property alias marginTop: board.marginTop
  property alias marginLeft: board.marginLeft
  property bool showHints: true
  readonly property bool focused: board.focused

  // ----- data -----
  property var columns: defaultColumns()
  property int nextId: 1
  property bool loaded: false
  property bool saveBlocked: false
  property string lastSaved: ""
  property int kcol: 0
  property int krow: 0

  readonly property var meta: [
    { box: "[ ]", boxColor: Pal.muted, legendOn: Pal.fg },
    { box: "[~]", boxColor: Pal.yellow, legendOn: Pal.yellow },
    { box: "[x]", boxColor: Pal.green, legendOn: Pal.green }
  ]

  function defaultColumns() {
    return [
      { id: "todo", title: "todo", cards: [] },
      { id: "doing", title: "doing", cards: [] },
      { id: "done", title: "done", cards: [] }
    ];
  }
  readonly property int total: {
    let n = 0;
    for (const c of columns) n += c.cards.length;
    return n;
  }
  readonly property int doneCount: columns.length > 2 ? columns[2].cards.length : 0
  readonly property int doingCount: columns.length > 1 ? columns[1].cards.length : 0

  function clone(v) { return JSON.parse(JSON.stringify(v)); }
  function find(cols, cardId) {
    for (let c = 0; c < cols.length; c++)
      for (let i = 0; i < cols[c].cards.length; i++)
        if (cols[c].cards[i].id === cardId) return { col: c, idx: i };
    return null;
  }
  function current() {
    const list = columns[kcol].cards;
    return list.length === 0 ? null : list[Math.min(krow, list.length - 1)];
  }

  // ----- title syntax -----
  function dkey(d) {
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  }
  function parseDue(v) {
    v = v.toLowerCase();
    const now = new Date();
    const at = n => dkey(new Date(now.getFullYear(), now.getMonth(), now.getDate() + n));
    if (v === "today") return at(0);
    if (v === "tom" || v === "tomorrow") return at(1);
    if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
    const i = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"].indexOf(v.slice(0, 3));
    if (i >= 0) return at(((i - now.getDay()) + 7) % 7 || 7);
    return "";
  }
  function parseTitle(raw) {
    let high = false, tag = "", due = "", m;
    if ((m = raw.match(/(^|\s)!high\b/))) { high = true; raw = raw.replace(m[0], " "); }
    if ((m = raw.match(/(^|\s)#(\S+)/))) { tag = m[2]; raw = raw.replace(m[0], " "); }
    if ((m = raw.match(/(^|\s)@(\S+)/))) {
      const d = parseDue(m[2]);
      if (d) { due = d; raw = raw.replace(m[0], " "); }
    }
    return { title: raw.replace(/\s+/g, " ").trim(), high: high, tag: tag, due: due };
  }
  function composeTitle(c) {
    return c.title + (c.high ? " !high" : "") + (c.tag ? " #" + c.tag : "") + (c.due ? " @" + c.due : "");
  }
  function dueInfo(due) {
    if (!due) return null;
    const d = new Date(due + "T12:00:00");
    const now = new Date();
    const diff = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(now.getFullYear(), now.getMonth(), now.getDate())) / 864e5);
    if (diff === 0) return { text: "@today", color: Pal.red };
    if (diff === 1) return { text: "@tomorrow", color: Pal.orange };
    if (diff < 0) return { text: "@" + Qt.formatDate(d, "MMM d").toLowerCase(), color: Pal.red };
    if (diff < 7) return { text: "@" + Qt.formatDate(d, "ddd").toLowerCase(), color: Pal.muted };
    return { text: "@" + Qt.formatDate(d, "MMM d").toLowerCase(), color: Pal.muted };
  }

  // ----- persistence -----
  function save() {
    if (!loaded || saveBlocked) return;
    const text = JSON.stringify({ nextId: nextId, columns: columns }, null, 2);
    lastSaved = text;
    file.setText(text);
  }
  function applyText(text) {
    let j;
    try { j = JSON.parse(text); } catch (e) {
      console.warn("kanban: kanban.json is not valid JSON, leaving it untouched:", e);
      saveBlocked = true;
      return;
    }
    if (!j || !Array.isArray(j.columns) || j.columns.length !== 3) {
      console.warn("kanban: kanban.json needs exactly 3 columns, leaving it untouched");
      saveBlocked = true;
      return;
    }
    saveBlocked = false;
    columns = j.columns;
    nextId = j.nextId || 1;
    loaded = true;
  }

  // COEL_DATA_DIR overrides the location (used for testing against throwaway data)
  readonly property string dataDir: Quickshell.env("COEL_DATA_DIR") || (Quickshell.env("HOME") + "/.local/share/coel")
  property bool dirReady: false
  Process {
    running: true
    command: ["mkdir", "-p", kb.dataDir]
    onExited: kb.dirReady = true
  }
  FileView {
    id: file
    path: kb.dirReady ? kb.dataDir + "/kanban.json" : ""
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      const t = text();
      // our own write echoing back through the file watcher
      if (t === kb.lastSaved || kb.dragId !== -1) return;
      kb.applyText(t);
    }
    onLoadFailed: {
      // first run (no file yet): start empty and write it out
      if (!kb.loaded) { kb.loaded = true; kb.save(); }
    }
  }

  // ----- mutations -----
  function select(col, id) {
    kcol = col;
    const i = columns[col].cards.findIndex(c => c.id === id);
    krow = Math.max(0, i);
  }
  function addCard(col, p, notes) {
    const cols = clone(columns);
    const id = nextId;
    cols[col].cards.push({ id: id, title: p.title, notes: notes, tag: p.tag, high: p.high, due: p.due });
    nextId += 1;
    columns = cols;
    save();
    select(col, id);
  }
  function updateCard(cardId, p, notes, col) {
    const cols = clone(columns);
    const at = find(cols, cardId);
    if (!at) return;
    const card = cols[at.col].cards.splice(at.idx, 1)[0];
    card.title = p.title; card.notes = notes; card.tag = p.tag; card.high = p.high; card.due = p.due;
    // staying put keeps its slot; changing column appends
    if (col === at.col) cols[col].cards.splice(at.idx, 0, card);
    else cols[col].cards.push(card);
    columns = cols;
    save();
    select(col, cardId);
  }
  function deleteCard(cardId) {
    const cols = clone(columns);
    const at = find(cols, cardId);
    if (!at) return;
    cols[at.col].cards.splice(at.idx, 1);
    columns = cols;
    save();
    krow = Math.max(0, Math.min(krow, cols[kcol].cards.length - 1));
  }
  function moveCard(cardId, toCol, toIdx) {
    const cols = clone(columns);
    const at = find(cols, cardId);
    if (!at) return;
    const card = cols[at.col].cards.splice(at.idx, 1)[0];
    if (at.col === toCol && at.idx < toIdx) toIdx -= 1;
    cols[toCol].cards.splice(Math.max(0, Math.min(toIdx, cols[toCol].cards.length)), 0, card);
    columns = cols;
    save();
    select(toCol, cardId);
  }
  // todo -> doing -> done -> back to todo
  function advance(cardId) {
    const at = find(columns, cardId);
    if (at) moveCard(cardId, at.col === 2 ? 0 : at.col + 1, 1e9);
  }

  // ----- drag state -----
  property int dragId: -1
  property var dragCard: null
  property real dragW: 0
  property real dragH: 0
  property real dragX: 0
  property real dragY: 0
  property real grabX: 0
  property real grabY: 0
  property var drop: null   // {col, idx, lineX, lineY, lineW}

  function beginDrag(card, w, h, gx, gy) {
    dragId = card.id; dragCard = card; dragW = w; dragH = h; grabX = gx; grabY = gy;
  }
  function updateDrag(px, py) {
    dragX = px; dragY = py;
    drop = locate(px, py);
  }
  function endDrag() {
    const d = drop, id = dragId;
    dragId = -1; dragCard = null; drop = null;
    if (d) moveCard(id, d.col, d.idx);
  }
  function cancelDrag() { dragId = -1; dragCard = null; drop = null; }

  // Which column + slot is the pointer (boardArea coordinates) over?
  function locate(px, py) {
    if (px < -24 || px > boardArea.width + 24 || py < -24 || py > boardArea.height + 24) return null;
    let best = -1, bestDist = 1e9;
    for (let i = 0; i < colRepeater.count; i++) {
      const col = colRepeater.itemAt(i);
      const p = col.mapFromItem(boardArea, px, 0);
      const dist = p.x < 0 ? -p.x : (p.x > col.width ? p.x - col.width : 0);
      if (dist < bestDist) { bestDist = dist; best = i; }
    }
    if (best < 0) return null;
    const col = colRepeater.itemAt(best);
    const p = col.mapFromItem(boardArea, px, py);
    const s = col.slotAt(p.y);
    const line = boardArea.mapFromItem(col, 0, s.y);
    return { col: best, idx: s.idx, lineX: line.x, lineY: line.y, lineW: col.width };
  }

  // ----- keyboard -----
  function clampRow(c) { return Math.max(0, Math.min(krow, columns[c].cards.length - 1)); }
  function handleKey(e) {
    const t = e.text, cur = current();
    let used = true;
    if (t === "H" || t === "L") {
      const c = Math.max(0, Math.min(2, kcol + (t === "L" ? 1 : -1)));
      if (cur && c !== kcol) moveCard(cur.id, c, 1e9);
    }
    else if (t === "h" || e.key === Qt.Key_Left) { kcol = Math.max(0, kcol - 1); krow = clampRow(kcol); }
    else if (t === "l" || e.key === Qt.Key_Right) { kcol = Math.min(2, kcol + 1); krow = clampRow(kcol); }
    else if (t === "j" || e.key === Qt.Key_Down) krow = Math.max(0, Math.min(columns[kcol].cards.length - 1, krow + 1));
    else if (t === "k" || e.key === Qt.Key_Up) krow = Math.max(0, krow - 1);
    else if (e.key === Qt.Key_Space && cur) advance(cur.id);
    else if (t === "x" && cur) deleteCard(cur.id);
    else if (t === "a" || t === "n") openNew(kcol);
    else if ((t === "e" || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && cur) openEdit(cur);
    else used = false;
    e.accepted = used;
  }

  // ----- editor -----
  property int editingId: -1
  function openNew(col) {
    editingId = -1;
    editor.openNew(col);
  }
  function openEdit(card) {
    const at = find(columns, card.id);
    if (!at) return;
    editingId = card.id;
    editor.openEdit(card, composeTitle(card), at.col);
  }
  KanbanEditor {
    id: editor
    screen: kb.screen
    onSaved: (raw, notes, col) => {
      const p = kb.parseTitle(raw);
      if (p.title === "") return;
      if (kb.editingId === -1) kb.addCard(col, p, notes);
      else kb.updateCard(kb.editingId, p, notes, col);
      editor.close();
    }
    onDeleted: { kb.deleteCard(kb.editingId); editor.close(); }
    onCancelled: editor.close()
  }

  // ----- board -----
  DesktopWidget {
    id: board
    screen: kb.screen
    cardWidth: 860
    onKeyPressed: (e) => kb.handleKey(e)

    // header
    RowLayout {
      Layout.fillWidth: true
      Layout.bottomMargin: 8
      spacing: 8
      Mono { text: "kanban"; font.weight: Font.Medium; color: board.focused ? Pal.blue : Pal.dim }
      Mono { text: "─ ~/dots/shell ─"; color: Pal.muted }
      Mono { text: kb.doneCount + "/" + kb.total + " done"; color: Pal.green }
      Item { Layout.fillWidth: true }
      Rectangle {
        Layout.preferredWidth: 90; Layout.preferredHeight: 6
        radius: 1
        color: Pal.track
        clip: true
        Rectangle {
          width: kb.total ? parent.width * kb.doneCount / kb.total : 0
          height: parent.height
          color: Pal.green
        }
        Rectangle {
          x: kb.total ? parent.width * kb.doneCount / kb.total : 0
          width: kb.total ? parent.width * kb.doingCount / kb.total : 0
          height: parent.height
          color: Pal.yellow
        }
      }
      Mono { text: (kb.total ? Math.round(kb.doneCount / kb.total * 100) : 0) + "%"; color: Pal.muted }
    }

    Item {
      id: boardArea
      Layout.fillWidth: true
      Layout.topMargin: 8
      Layout.preferredHeight: colGrid.implicitHeight

      GridLayout {
        id: colGrid
        anchors { left: parent.left; right: parent.right; top: parent.top }
        columns: 3
        uniformCellWidths: true
        columnSpacing: 10
        rowSpacing: 0

        Repeater {
          id: colRepeater
          model: kb.columns
          delegate: Rectangle {
            id: col
            required property var modelData
            required property int index
            readonly property bool active: board.focused && kb.kcol === index
            readonly property bool hot: kb.drop !== null && kb.drop.col === index
            readonly property var m: kb.meta[index]

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: Math.max(300, cardCol.implicitHeight + 22)
            radius: 2
            color: hot ? Pal.raised : "transparent"
            border.width: 1
            border.color: hot ? Pal.green : active ? Pal.blue : Pal.faint

            // Insertion slot for a y in this column's coordinates.
            function slotAt(y) {
              const n = cardRep.count;
              for (let j = 0; j < n; j++) {
                const c = cardRep.itemAt(j);
                const q = c.mapFromItem(col, 0, y);
                if (q.y < c.height / 2) return { idx: j, y: col.mapFromItem(c, 0, -2).y };
              }
              if (n === 0) return { idx: 0, y: 14 };
              const last = cardRep.itemAt(n - 1);
              return { idx: n, y: col.mapFromItem(last, 0, last.height + 2).y };
            }

            // legends cut into the top border
            Rectangle {
              x: 8; y: -height / 2
              width: legendText.implicitWidth + 12; height: legendText.implicitHeight
              color: Pal.card
              Mono {
                id: legendText
                anchors.centerIn: parent
                text: col.modelData.title.toLowerCase()
                color: col.hot || col.active ? col.m.legendOn : Pal.muted
              }
            }
            Rectangle {
              anchors.right: parent.right; anchors.rightMargin: 8
              y: -height / 2
              width: countRow.implicitWidth + 8; height: countRow.implicitHeight
              color: Pal.card
              Row {
                id: countRow
                anchors.centerIn: parent
                spacing: 6
                Mono { text: col.modelData.cards.length; color: Pal.muted }
                Item {
                  width: plus.implicitWidth + 4; height: plus.implicitHeight
                  Mono { id: plus; anchors.centerIn: parent; text: "+"; color: plusArea.containsMouse ? Pal.green : Pal.muted }
                  MouseArea {
                    id: plusArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: kb.openNew(col.index)
                  }
                }
              }
            }

            Mono {
              visible: col.modelData.cards.length === 0
              x: 8; y: 16
              text: "─ empty ─"; color: Pal.faint
            }

            Column {
              id: cardCol
              anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 4; rightMargin: 4; topMargin: 14 }
              spacing: 4

              Repeater {
                id: cardRep
                model: col.modelData.cards
                delegate: Rectangle {
                  id: card
                  required property var modelData
                  required property int index
                  readonly property bool selected: col.active && Math.min(kb.krow, col.modelData.cards.length - 1) === index
                  readonly property var due: col.index === 2 ? null : kb.dueInfo(modelData.due)
                  readonly property bool high: !!modelData.high && col.index !== 2
                  width: cardCol.width
                  height: cardRow.implicitHeight + 10
                  radius: 2
                  color: selected || (cardArea.containsMouse && kb.dragId === -1) ? Pal.edge : "transparent"
                  opacity: kb.dragId === modelData.id ? 0.35 : 1

                  RowLayout {
                    id: cardRow
                    anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 6; rightMargin: 6; topMargin: 5 }
                    spacing: 4

                    Mono { Layout.preferredWidth: 8; Layout.alignment: Qt.AlignTop; text: card.selected ? "▌" : ""; color: Pal.blue }
                    Item {
                      Layout.preferredWidth: 24; Layout.preferredHeight: boxText.implicitHeight; Layout.alignment: Qt.AlignTop
                      Mono { id: boxText; text: col.m.box; color: boxArea.containsMouse ? Pal.green : col.m.boxColor }
                      MouseArea {
                        id: boxArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: kb.advance(card.modelData.id)
                      }
                    }
                    ColumnLayout {
                      Layout.fillWidth: true
                      Layout.alignment: Qt.AlignTop
                      spacing: 2
                      Mono {
                        Layout.fillWidth: true
                        text: card.modelData.title
                        wrapMode: Text.Wrap
                        font.strikeout: col.index === 2
                        color: col.index === 2 ? Pal.muted : Pal.fg
                      }
                      Mono {
                        visible: !!card.modelData.notes
                        Layout.fillWidth: true
                        text: card.modelData.notes || ""
                        wrapMode: Text.Wrap
                        font.pixelSize: 11
                        color: Pal.muted
                      }
                      Flow {
                        visible: card.high || !!card.modelData.tag || card.due !== null
                        Layout.fillWidth: true
                        spacing: 8
                        Mono { visible: card.high; text: "!high"; font.pixelSize: 11; color: Pal.red }
                        Mono { visible: !!card.modelData.tag; text: "#" + card.modelData.tag; font.pixelSize: 11; color: Pal.cyan }
                        Mono { visible: card.due !== null; text: card.due ? card.due.text : ""; font.pixelSize: 11; color: card.due ? card.due.color : Pal.muted }
                      }
                    }
                    Item {
                      Layout.preferredWidth: 12; Layout.preferredHeight: delText.implicitHeight; Layout.alignment: Qt.AlignTop
                      Mono {
                        id: delText
                        text: "×"
                        color: delArea.containsMouse ? Pal.red : card.selected ? Pal.dim : Pal.faint
                      }
                      MouseArea {
                        id: delArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: kb.deleteCard(card.modelData.id)
                      }
                    }
                  }

                  // Sits under the box/delete areas (declared first within the
                  // card's hit area via z), so those still get their own clicks.
                  MouseArea {
                    id: cardArea
                    z: -1
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                    property real pressX: 0
                    property real pressY: 0
                    property bool dragging: false
                    onPressed: (m) => { pressX = m.x; pressY = m.y; dragging = false; }
                    onPositionChanged: (m) => {
                      if (!pressed) return;
                      if (!dragging && Math.hypot(m.x - pressX, m.y - pressY) > 8) {
                        dragging = true;
                        kb.beginDrag(card.modelData, card.width, card.height, pressX, pressY);
                      }
                      if (dragging) {
                        const p = cardArea.mapToItem(boardArea, m.x, m.y);
                        kb.updateDrag(p.x, p.y);
                      }
                    }
                    onReleased: {
                      if (dragging) { dragging = false; kb.endDrag(); }
                      else if (containsMouse) kb.select(col.index, card.modelData.id);
                    }
                    onDoubleClicked: kb.openEdit(card.modelData)
                    onCanceled: { if (dragging) { dragging = false; kb.cancelDrag(); } }
                  }
                }
              }
            }
          }
        }
      }

      // drop position marker
      Rectangle {
        visible: kb.drop !== null
        x: kb.drop ? kb.drop.lineX + 6 : 0
        y: kb.drop ? kb.drop.lineY - 1 : 0
        width: kb.drop ? kb.drop.lineW - 12 : 0
        height: 2
        radius: 1
        color: Pal.green
        z: 50
      }

      // card following the pointer
      Rectangle {
        visible: kb.dragId !== -1
        x: kb.dragX - kb.grabX
        y: kb.dragY - kb.grabY
        width: kb.dragW
        height: kb.dragH
        radius: 2
        color: Pal.faint
        border.width: 1
        border.color: Pal.blue
        opacity: 0.92
        z: 100
        Mono {
          anchors { fill: parent; margins: 6; leftMargin: 40 }
          text: kb.dragCard ? kb.dragCard.title : ""
          wrapMode: Text.Wrap
          elide: Text.ElideRight
        }
      }
    }

    DashedLine {
      Layout.fillWidth: true
      Layout.topMargin: 12
    }
    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 8
      TextButton {
        onClicked: kb.openNew(kb.kcol)
        Mono { text: "+"; color: Pal.green }
        Mono { text: "new card"; color: Pal.muted }
        Mono { text: "a"; color: Pal.yellow }
      }
      Item { Layout.fillWidth: true }
    }
    Hints {
      visible: kb.showHints
      Layout.fillWidth: true
      Layout.topMargin: 12
      items: [["h/l", "column"], ["j/k", "card"], ["H/L", "move"], ["space", "advance"], ["x", "delete"], ["a", "new card"], ["drag", "reorder"]]
    }
  }
}
