import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import ".."
import "../widgets"

// ===== SSH KEY GENERATOR (modal) =====
// Ported from the "SSH key generator" screen in
// "example/Quickshell Bar.dc.html" -- that mock fakes every command with
// setTimeout and invented fingerprint art; this runs the real
// ssh-keygen/ssh-add/wl-copy and shows ssh-keygen's own real randomart,
// same "real data, not invented" rule the rest of this launcher follows
// (SshBackend.qml, AppsBackend.qml). Two mock features are left out rather
// than faked: "save passphrase to vault" (rbw isn't installed anywhere in
// this config) and auto ssh-add for a passphrase-protected key (doing that
// non-interactively needs an SSH_ASKPASS helper this codebase has no other
// use for -- the done screen just says to run ssh-add by hand instead).
//
// Own top-level PanelWindow, not nested inside Launcher.qml's -- same
// "full-screen Overlay window with exclusive keyboard focus" shape as
// widgets/KanbanEditor.qml, instantiated directly as a plain child of
// LauncherPanel (see `SshKeygenModal { id: sshKeygenModal }` there) rather
// than threading a signal up through Launcher.qml's Scope, since nothing
// else needs to react to this opening/closing.
PanelWindow {
  id: root

  // Existing host aliases (ssh.hosts.map(h => h.name) from LauncherPanel)
  // -- used to reject a ~/.ssh/config alias that's already taken.
  property var existingAliases: []
  readonly property string sshDir: "/home/joelsgc/.ssh/"

  property bool shown: false
  property string phase: "form" // form | run | done
  property bool busy: false

  property string type: "ed25519"
  property int bits: 0
  property string name: ""
  property bool nameTouched: false
  property string comment: ""
  property string pass: ""
  property string pass2: ""
  property bool showPass: false
  property int rounds: 100
  property bool resident: true
  property bool verify: false
  property bool agent: true
  property string life: "until logout"
  property bool copyPub: false
  property bool cfg: false
  property string alias: ""
  property string host: ""
  property string user: ""
  property string port: "22"
  property bool tried: false

  property var existingNames: []
  property var log: []
  property string resPath: ""
  property string resPub: ""
  property string resFingerprint: ""
  property bool resCopied: false

  readonly property var types: [
    { id: "ed25519", note: "fast · small · recommended", bits: null, color: Pal.green },
    { id: "ed25519-sk", note: "hardware key · touch to use", bits: null, color: Pal.cyan },
    { id: "ecdsa", note: "nist curves", bits: [256, 384, 521], color: Pal.yellow },
    { id: "rsa", note: "legacy compatibility", bits: [4096, 3072, 2048], color: Pal.orange },
  ]
  function curType() { return types.find(t => t.id === root.type); }
  function curBits() { const t = curType(); return t.bits ? (root.bits || t.bits[0]) : 0; }
  function deriveName() {
    if (root.nameTouched) return root.name.trim();
    const base = "id_" + root.type.replace(/-/g, "_");
    let n = 2, cand = base;
    while (root.existingNames.indexOf(cand) >= 0) { cand = base + "_" + n; n++; }
    return cand;
  }
  function targetPath() { return root.sshDir + deriveName(); }
  function validate() {
    const errs = {};
    const nm = deriveName();
    if (!nm) errs.name = "name required";
    else if (!/^[\w.-]+$/.test(nm)) errs.name = "letters, digits, . _ - only";
    if (root.pass && root.pass !== root.pass2) errs.pass = root.pass2 ? "passphrases do not match" : "confirm the passphrase";
    if (root.cfg) {
      const a = root.alias.trim();
      if (!a) errs.alias = "alias required";
      else if (root.existingAliases.indexOf(a) >= 0) errs.alias = "alias " + a + " already exists";
      if (!root.host.trim()) errs.host = "host required";
      if (root.port && !/^\d+$/.test(root.port)) errs.host = errs.host || "port must be a number";
    }
    return errs;
  }
  readonly property var errs: validate()
  readonly property bool formOk: Object.keys(errs).length === 0
  readonly property bool nameExists: root.existingNames.indexOf(deriveName()) >= 0

  function logPush(text, color) { root.log = root.log.concat([{ text, color: color || Pal.dim }]); }
  function logOk(text) { root.log = root.log.concat([{ text, color: Pal.green, mark: "✓" }]); }
  function logErr(text) { root.log = root.log.concat([{ text, color: Pal.red, mark: "✗" }]); }

  function reset() {
    phase = "form"; busy = false; tried = false;
    type = "ed25519"; bits = 0; name = ""; nameTouched = false;
    pass = ""; pass2 = ""; showPass = false; rounds = 100;
    resident = true; verify = false; agent = true; life = "until logout";
    copyPub = false; cfg = false; alias = ""; host = ""; user = ""; port = "22";
    log = []; resPath = ""; resPub = ""; resFingerprint = ""; resCopied = false;
  }
  // Not a reactive `text: root.deriveName()` binding on nameInput -- that
  // fed back into itself (typing sets root.name, which deriveName() reads
  // right back out, QML flagged it as a binding loop). Set imperatively
  // instead: once on open, and again on a type change for as long as the
  // user hasn't typed a name of their own (nameTouched) -- settingNameField
  // tells nameInput's own onTextChanged these particular writes aren't the
  // user typing, so they don't themselves flip nameTouched to true.
  property bool settingNameField: false
  function setNameField(v) { settingNameField = true; nameInput.text = v; settingNameField = false; }
  onTypeChanged: if (!nameTouched) setNameField(deriveName())
  function openNew() {
    reset();
    shown = true;
    homeListProc.running = true;
    commentProc.running = true;
    Qt.callLater(() => { setNameField(root.deriveName()); nameInput.forceActiveFocus(); });
  }
  function close() {
    if (root.busy) return;
    shown = false;
  }

  // Real existing ~/.ssh filenames (minus .pub companions), for the
  // default-name/collision logic above -- re-read every open, not cached,
  // same "cheap local file, re-check each time" reasoning as SshBackend.
  Process {
    id: homeListProc
    command: ["sh", "-c", "ls -1 " + root.sshDir + " 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.existingNames = text.split("\n").map(s => s.trim()).filter(s => s && !s.endsWith(".pub") && s !== "config" && s !== "known_hosts" && s !== "authorized_keys");
      }
    }
  }
  Process {
    id: commentProc
    command: ["sh", "-c", "echo \"$(whoami)@$(hostname)\""]
    stdout: StdioCollector {
      onStreamFinished: { if (!root.comment) root.comment = text.trim(); }
    }
  }

  // ----- generate pipeline: keygen -> [ssh-add] -> [append config] ->
  // read pubkey -> [wl-copy] -> fingerprint. A queue of plain command
  // descriptors run one at a time through the same two Process objects
  // (one for argv commands, one for stdin-fed ones), rather than one
  // Process per step -- mirrors how ClipboardBackend reuses its decode
  // Processes instead of spawning a new component per call.
  property var queue: []
  function runQueue() {
    if (root.queue.length === 0) { root.busy = false; root.phase = "done"; return; }
    const step = root.queue[0];
    root.queue = root.queue.slice(1);
    step.run();
  }
  Process {
    id: cmdProc
    property var onDone: null
    onExited: (code) => {
      if (code === 0) onDone(true, "");
      else onDone(false, "exit " + code);
    }
    stderr: StdioCollector {}
  }
  Process {
    id: stdinProc
    property var onDone: null
    property string payload: ""
    stdinEnabled: true
    onStarted: { write(payload); stdinEnabled = false; }
    onExited: (code) => {
      if (code === 0) onDone(true, "");
      else onDone(false, "exit " + code);
    }
    stderr: StdioCollector {}
  }
  // Captured output of the one read-only step (pubkey/fingerprint reads)
  // -- plain StdioCollector text, consumed by whichever queue step asked
  // for it via `captureProc.onRead`.
  Process {
    id: captureProc
    property var onRead: null
    stdout: StdioCollector {
      onStreamFinished: captureProc.onRead(text)
    }
    onExited: (code) => { if (code !== 0) runQueue(); }
  }

  function generate() {
    tried = true;
    if (!formOk) return;
    const path = targetPath();
    const t = curType(), bits = curBits(), sk = root.type === "ed25519-sk";
    const args = ["ssh-keygen", "-t", root.type];
    if (bits) args.push("-b", String(bits));
    args.push("-a", String(root.rounds));
    if (sk && root.resident) args.push("-O", "resident");
    if (sk && root.verify) args.push("-O", "verify-required");
    args.push("-C", root.comment, "-f", path, "-N", root.pass);

    const steps = [];
    steps.push({
      label: "generating " + root.type + (bits ? " " + bits : "") + " key pair",
      run: () => {
        root.logPush((sk ? "touch your security key if it asks … " : "") + "running ssh-keygen…", Pal.yellow);
        cmdProc.onDone = (ok, err) => {
          if (ok) { root.logOk("wrote " + path + " (0600) and " + path + ".pub"); root.resPath = path; runQueue(); }
          else { root.logErr("ssh-keygen failed — " + err); root.busy = false; }
        };
        cmdProc.command = args;
        cmdProc.running = true;
      },
    });
    if (root.agent) {
      if (root.pass) {
        steps.push({ run: () => { root.logPush("skipped ssh-add — passphrase-protected, run `ssh-add " + path + "` yourself", Pal.orange); runQueue(); } });
      } else {
        steps.push({
          run: () => {
            const a = ["ssh-add"];
            if (root.life !== "until logout") a.push("-t", root.life);
            a.push(path);
            cmdProc.onDone = (ok, err) => {
              if (ok) root.logOk("added to ssh-agent" + (root.life !== "until logout" ? " for " + root.life : ""));
              else root.logErr("ssh-add failed — " + err);
              runQueue();
            };
            cmdProc.command = a;
            cmdProc.running = true;
          },
        });
      }
    }
    if (root.cfg) {
      steps.push({
        run: () => {
          const a = root.alias.trim(), h = root.host.trim(), u = root.user.trim() || "joelsgc", p = root.port || "22";
          // Values go in through stdin, never interpolated into a shell
          // command string -- a host/alias containing shell metacharacters
          // can't do anything here, it just ends up as literal file content.
          const block = "\nHost " + a + "\n  HostName " + h + "\n  User " + u + "\n  Port " + p + "\n  IdentityFile " + path + "\n";
          stdinProc.payload = block;
          stdinProc.onDone = (ok, err) => {
            if (ok) root.logOk("host " + a + " added to ~/.ssh/config");
            else root.logErr("writing ~/.ssh/config failed — " + err);
            runQueue();
          };
          stdinProc.command = ["sh", "-c", "cat >> " + root.sshDir + "config"];
          stdinProc.running = true;
        },
      });
    }
    steps.push({
      run: () => {
        captureProc.onRead = (text) => { root.resPub = text.trim(); runQueue(); };
        captureProc.command = ["cat", path + ".pub"];
        captureProc.running = true;
      },
    });
    if (root.copyPub) {
      steps.push({
        run: () => {
          stdinProc.payload = root.resPub;
          stdinProc.onDone = (ok, err) => { if (ok) root.logOk("public key copied"); else root.logErr("wl-copy failed — " + err); runQueue(); };
          stdinProc.command = ["wl-copy"];
          stdinProc.running = true;
        },
      });
    }
    steps.push({
      run: () => {
        captureProc.onRead = (text) => {
          const m = text.match(/\b(SHA256:\S+)/);
          root.resFingerprint = m ? m[1] : "";
          runQueue();
        };
        captureProc.command = ["ssh-keygen", "-lv", "-f", path];
        captureProc.running = true;
      },
    });

    root.phase = "run"; root.busy = true; root.log = [];
    root.queue = steps;
    runQueue();
  }
  function copyPubNow() {
    stdinProc.payload = root.resPub;
    stdinProc.onDone = (ok) => { if (ok) root.resCopied = true; };
    stdinProc.command = ["wl-copy"];
    stdinProc.running = true;
  }

  visible: shown
  onVisibleChanged: if (visible) Qt.callLater(() => nameInput.forceActiveFocus())

  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.namespace: "coel-ssh-keygen"

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(24 / 255, 26 / 255, 31 / 255, 0.62)
    MouseArea { anchors.fill: parent; onClicked: root.close() }
  }

  Rectangle {
    id: dialog
    width: Math.min(580, root.width - 32)
    x: (root.width - width) / 2
    y: Math.max(24, (root.height - height) / 2)
    height: dialogCol.implicitHeight + 20
    radius: Globals.eyeCandyOff ? 0 : 16
    color: Pal.card
    border.width: 1
    border.color: root.phase === "done" ? Pal.green : Pal.faint
    Behavior on border.color { ColorAnimation { duration: 200 } }

    MouseArea { anchors.fill: parent }

    ColumnLayout {
      id: dialogCol
      anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 10 }
      spacing: 0

      RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 8
        spacing: 8
        PhIcon { name: "key"; font.pixelSize: 15; color: Pal.blue }
        Mono { text: "new ssh key"; font.weight: Font.Medium; color: Pal.blue }
        Mono { text: "─ ssh-keygen ─"; color: Pal.muted }
        Item { Layout.fillWidth: true }
        TextButton {
          enabled: !root.busy
          onClicked: root.close()
          Mono { text: "[×]"; color: parent.parent.hovered ? Pal.red : Pal.muted }
        }
      }

      // ----- form -----
      ColumnLayout {
        visible: root.phase === "form"
        Layout.fillWidth: true
        spacing: 0

        Box {
          Layout.fillWidth: true
          Layout.topMargin: 8
          padTop: 14; padSide: 10; padBottom: 10
          legend: "type"; rightLegend: root.curType().note; rightColor: root.curType().color

          Flow {
            Layout.fillWidth: true
            spacing: 2
            Repeater {
              model: root.types
              delegate: TextButton {
                required property var modelData
                readonly property bool picked: root.type === modelData.id
                onClicked: { root.type = modelData.id; root.bits = 0; }
                Mono { text: picked ? "(•)" : "( )"; color: picked ? modelData.color : Pal.muted }
                Mono { text: modelData.id; color: picked ? Pal.fg : Pal.dim }
              }
            }
          }
          Flow {
            visible: !!root.curType().bits
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 2
            Mono { text: "bits"; color: Pal.muted; Layout.alignment: Qt.AlignVCenter }
            Repeater {
              model: root.curType().bits || []
              delegate: TextButton {
                required property var modelData
                readonly property bool picked: root.curBits() === modelData
                onClicked: root.bits = modelData
                Mono { text: picked ? "(•)" : "( )"; color: picked ? Pal.blue : Pal.muted }
                Mono { text: String(modelData); color: picked ? Pal.fg : Pal.dim }
                Mono { visible: modelData === 2048; text: "weak"; color: Pal.orange }
              }
            }
          }
          ColumnLayout {
            visible: root.type === "ed25519-sk"
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 2
            TextButton {
              onClicked: root.resident = !root.resident
              Mono { text: root.resident ? "[x]" : "[ ]"; color: root.resident ? Pal.green : Pal.muted }
              Mono { text: "resident"; color: Pal.fg }
              Mono { text: "stored on the key"; color: Pal.muted }
            }
            TextButton {
              onClicked: root.verify = !root.verify
              Mono { text: root.verify ? "[x]" : "[ ]"; color: root.verify ? Pal.green : Pal.muted }
              Mono { text: "verify-required"; color: Pal.fg }
              Mono { text: "pin + touch"; color: Pal.muted }
            }
          }
        }

        Box {
          Layout.fillWidth: true
          Layout.topMargin: 16
          padTop: 14; padSide: 10; padBottom: 10
          legend: "file"
          rightLegend: root.errs.name || (root.nameExists ? "exists · will overwrite" : "new file")
          rightColor: root.errs.name ? Pal.red : (root.nameExists ? Pal.orange : Pal.muted)

          GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 6
            Mono { text: "name"; color: Pal.muted }
            RowLayout {
              Layout.fillWidth: true
              spacing: 0
              Mono { text: root.sshDir; color: Pal.muted }
              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: nameInput.implicitHeight + 6
                color: nameInput.activeFocus ? Pal.raised : Pal.deep
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: (root.tried && root.errs.name) ? Pal.red : (nameInput.activeFocus ? Pal.blue : Pal.faint) }
                TextInput {
                  id: nameInput
                  anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                  verticalAlignment: TextInput.AlignVCenter
                  font.family: Pal.mono; font.pixelSize: 12
                  color: Pal.fg
                  clip: true
                  onTextChanged: { root.name = text; if (!root.settingNameField) root.nameTouched = true; }
                  KeyNavigation.tab: commentInput
                  Keys.onReturnPressed: root.generate()
                  Keys.onPressed: (e) => { if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; } }
                }
              }
            }
            Mono { text: "comment"; color: Pal.muted }
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: commentInput.implicitHeight + 6
              color: commentInput.activeFocus ? Pal.raised : Pal.deep
              Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: commentInput.activeFocus ? Pal.blue : Pal.faint }
              TextInput {
                id: commentInput
                anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                verticalAlignment: TextInput.AlignVCenter
                font.family: Pal.mono; font.pixelSize: 12
                color: Pal.fg
                text: root.comment
                clip: true
                onTextChanged: root.comment = text
                KeyNavigation.tab: passInput
                Keys.onReturnPressed: root.generate()
                Keys.onPressed: (e) => { if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; } }
              }
            }
          }
        }

        Box {
          Layout.fillWidth: true
          Layout.topMargin: 16
          padTop: 14; padSide: 10; padBottom: 10
          legend: "passphrase"
          rightLegend: !root.pass ? "no passphrase" : root.pass.length < 8 ? "weak" : root.pass.length < 14 ? "fair" : "strong"
          rightColor: !root.pass ? Pal.orange : root.pass.length < 8 ? Pal.red : root.pass.length < 14 ? Pal.yellow : Pal.green

          GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 10
            rowSpacing: 6
            Mono { text: "enter"; color: Pal.muted }
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: passInput.implicitHeight + 6
              color: passInput.activeFocus ? Pal.raised : Pal.deep
              Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: passInput.activeFocus ? Pal.blue : Pal.faint }
              TextInput {
                id: passInput
                anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                verticalAlignment: TextInput.AlignVCenter
                font.family: Pal.mono; font.pixelSize: 12
                color: Pal.fg
                echoMode: root.showPass ? TextInput.Normal : TextInput.Password
                passwordCharacter: "•"
                clip: true
                onTextChanged: { root.pass = text; if (!text) root.copyPub = root.copyPub; }
                KeyNavigation.tab: pass2Input
                Keys.onReturnPressed: root.generate()
                Keys.onPressed: (e) => { if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; } }
              }
              Mono { visible: passInput.text === ""; anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }  text: "empty for none"; color: Pal.muted }
            }
            TextButton {
              onClicked: { root.showPass = !root.showPass; passInput.forceActiveFocus(); }
              Mono { text: root.showPass ? "[hide]" : "[show]"; color: Pal.muted }
            }
            Mono { text: "confirm"; color: Pal.muted }
            Rectangle {
              Layout.fillWidth: true
              Layout.columnSpan: 2
              Layout.preferredHeight: pass2Input.implicitHeight + 6
              color: pass2Input.activeFocus ? Pal.raised : Pal.deep
              Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: (root.tried && root.errs.pass) ? Pal.red : (pass2Input.activeFocus ? Pal.blue : Pal.faint) }
              TextInput {
                id: pass2Input
                anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                verticalAlignment: TextInput.AlignVCenter
                font.family: Pal.mono; font.pixelSize: 12
                color: Pal.fg
                echoMode: root.showPass ? TextInput.Normal : TextInput.Password
                passwordCharacter: "•"
                clip: true
                onTextChanged: root.pass2 = text
                KeyNavigation.tab: nameInput
                Keys.onReturnPressed: root.generate()
                Keys.onPressed: (e) => { if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; } }
              }
            }
            Item {}
            RowLayout {
              Layout.columnSpan: 2
              spacing: 2
              Mono { text: "kdf rounds"; color: Pal.muted; Layout.rightMargin: 4 }
              Repeater {
                model: [16, 32, 64, 100]
                delegate: TextButton {
                  required property var modelData
                  readonly property bool picked: root.rounds === modelData
                  onClicked: root.rounds = modelData
                  Mono { text: picked ? "(•)" : "( )"; color: picked ? Pal.blue : Pal.muted }
                  Mono { text: String(modelData); color: picked ? Pal.fg : Pal.dim }
                }
              }
            }
          }
          Mono {
            visible: root.tried && !!root.errs.pass
            Layout.topMargin: 4
            text: root.errs.pass || ""
            color: Pal.red
          }
        }

        Box {
          Layout.fillWidth: true
          Layout.topMargin: 16
          padTop: 14; padSide: 10; padBottom: 10
          legend: "after"

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            TextButton {
              onClicked: root.agent = !root.agent
              Mono { text: root.agent ? "[x]" : "[ ]"; color: root.agent ? Pal.green : Pal.muted }
              Mono { text: "add to ssh-agent"; color: Pal.fg }
              Mono { text: "ssh-add"; color: Pal.muted }
            }
            RowLayout {
              visible: root.agent
              Layout.leftMargin: 34
              spacing: 2
              Mono { text: "lifetime"; color: Pal.muted; Layout.rightMargin: 4 }
              Repeater {
                model: ["until logout", "1h", "8h", "24h"]
                delegate: TextButton {
                  required property var modelData
                  readonly property bool picked: root.life === modelData
                  onClicked: root.life = modelData
                  Mono { text: picked ? "(•)" : "( )"; color: picked ? Pal.blue : Pal.muted }
                  Mono { text: modelData; color: picked ? Pal.fg : Pal.dim }
                }
              }
            }
            TextButton {
              onClicked: root.copyPub = !root.copyPub
              Mono { text: root.copyPub ? "[x]" : "[ ]"; color: root.copyPub ? Pal.green : Pal.muted }
              Mono { text: "copy public key"; color: Pal.fg }
              Mono { text: "wl-copy"; color: Pal.muted }
            }
            TextButton {
              onClicked: root.cfg = !root.cfg
              Mono { text: root.cfg ? "[x]" : "[ ]"; color: root.cfg ? Pal.green : Pal.muted }
              Mono { text: "add host to ~/.ssh/config"; color: Pal.fg }
              Mono { text: "shows in @ssh"; color: Pal.muted }
            }
            GridLayout {
              visible: root.cfg
              Layout.leftMargin: 34
              Layout.fillWidth: true
              columns: 4
              columnSpacing: 10
              rowSpacing: 4
              Mono { text: "alias"; color: Pal.muted }
              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: aliasInput.implicitHeight + 6
                color: aliasInput.activeFocus ? Pal.raised : Pal.deep
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: (root.tried && root.errs.alias) ? Pal.red : (aliasInput.activeFocus ? Pal.blue : Pal.faint) }
                TextInput {
                  id: aliasInput
                  anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                  verticalAlignment: TextInput.AlignVCenter
                  font.family: Pal.mono; font.pixelSize: 12; color: Pal.fg
                  clip: true
                  onTextChanged: root.alias = text
                  Keys.onReturnPressed: root.generate()
                  Keys.onPressed: (e) => { if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; } }
                }
                Mono { visible: aliasInput.text === ""; anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }  text: "homelab"; color: Pal.muted }
              }
              Mono { text: "host"; color: Pal.muted }
              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: hostInput.implicitHeight + 6
                color: hostInput.activeFocus ? Pal.raised : Pal.deep
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: (root.tried && root.errs.host) ? Pal.red : (hostInput.activeFocus ? Pal.blue : Pal.faint) }
                TextInput {
                  id: hostInput
                  anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                  verticalAlignment: TextInput.AlignVCenter
                  font.family: Pal.mono; font.pixelSize: 12; color: Pal.fg
                  clip: true
                  onTextChanged: root.host = text
                  Keys.onReturnPressed: root.generate()
                  Keys.onPressed: (e) => { if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; } }
                }
                Mono { visible: hostInput.text === ""; anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }  text: "10.0.0.2"; color: Pal.muted }
              }
              Mono { text: "user"; color: Pal.muted }
              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: userInput.implicitHeight + 6
                color: userInput.activeFocus ? Pal.raised : Pal.deep
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: userInput.activeFocus ? Pal.blue : Pal.faint }
                TextInput {
                  id: userInput
                  anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                  verticalAlignment: TextInput.AlignVCenter
                  font.family: Pal.mono; font.pixelSize: 12; color: Pal.fg
                  clip: true
                  onTextChanged: root.user = text
                  Keys.onReturnPressed: root.generate()
                  Keys.onPressed: (e) => { if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; } }
                }
                Mono { visible: userInput.text === ""; anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }  text: "joelsgc"; color: Pal.muted }
              }
              Mono { text: "port"; color: Pal.muted }
              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: portInput.implicitHeight + 6
                color: portInput.activeFocus ? Pal.raised : Pal.deep
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: portInput.activeFocus ? Pal.blue : Pal.faint }
                TextInput {
                  id: portInput
                  anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                  verticalAlignment: TextInput.AlignVCenter
                  font.family: Pal.mono; font.pixelSize: 12; color: Pal.fg
                  clip: true
                  text: root.port
                  onTextChanged: root.port = text
                  Keys.onReturnPressed: root.generate()
                  Keys.onPressed: (e) => { if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; } }
                }
              }
              Mono { visible: root.tried && (!!root.errs.alias || !!root.errs.host); Layout.columnSpan: 4; text: root.errs.alias || root.errs.host || ""; color: Pal.red }
            }
          }
        }
      }

      // ----- run -----
      Box {
        visible: root.phase === "run"
        Layout.fillWidth: true
        Layout.topMargin: 8
        padTop: 14; padSide: 10; padBottom: 10
        legend: "generating"

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2
          Repeater {
            model: root.log
            delegate: RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: 8
              Mono { text: modelData.mark || "·"; color: modelData.color }
              Mono { Layout.fillWidth: true; wrapMode: Text.Wrap; text: modelData.text; color: modelData.mark ? Pal.dim : Pal.fg }
            }
          }
        }
      }

      // ----- done -----
      ColumnLayout {
        visible: root.phase === "done"
        Layout.fillWidth: true
        spacing: 0
        Box {
          Layout.fillWidth: true
          Layout.topMargin: 8
          padTop: 14; padSide: 10; padBottom: 10
          legend: "key"; rightLegend: root.resFingerprint; rightColor: Pal.dim

          GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 2
            Mono { text: "private"; color: Pal.muted }
            Mono { Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; text: root.resPath; color: Pal.fg }
            Mono { text: "public"; color: Pal.muted }
            Mono { Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; text: root.resPath + ".pub"; color: Pal.fg }
          }
        }
        Box {
          Layout.fillWidth: true
          Layout.topMargin: 16
          padTop: 14; padSide: 10; padBottom: 10
          legend: "public key"
          rightData: [
            TextButton {
              onClicked: root.copyPubNow()
              Mono { text: root.resCopied ? "[copied ✓]" : "[copy]"; color: root.resCopied ? Pal.green : Pal.muted }
            }
          ]

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(84, pubText.implicitHeight + 12)
            color: Pal.deep
            Flickable {
              anchors.fill: parent
              anchors.margins: 6
              contentHeight: pubText.implicitHeight
              clip: true
              Mono { id: pubText; width: parent.width; wrapMode: Text.WrapAnywhere; text: root.resPub; font.pixelSize: 12 }
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 14
        spacing: 12
        Hints {
          Layout.fillWidth: true
          items: root.phase === "form" ? [["tab", "field"], ["⏎", "generate"], ["esc", "cancel"]] : root.phase === "run" ? [] : [["esc", "close"]]
        }
        TextButton {
          visible: root.phase !== "run"
          hPad: 10
          onClicked: root.close()
          Mono { text: root.phase === "done" ? "< close >" : "< cancel >"; color: parent.parent.hovered ? Pal.fg : Pal.dim }
        }
        Rectangle {
          visible: root.phase !== "run"
          Layout.preferredWidth: primaryText.implicitWidth + 20
          Layout.preferredHeight: primaryText.implicitHeight
          radius: Globals.eyeCandyOff ? 0 : 2
          color: root.phase === "done" ? Pal.blue : (!root.formOk ? Pal.muted : (root.nameExists ? Pal.orange : Pal.green))
          opacity: root.phase === "done" || root.formOk ? 1 : 0.5
          Mono {
            id: primaryText
            anchors.centerIn: parent
            text: root.phase === "done" ? "done" : (root.nameExists ? "overwrite" : "generate")
            font.weight: Font.Medium
            color: Pal.card
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.phase === "done" ? root.close() : root.generate()
          }
        }
      }
    }
  }
}
