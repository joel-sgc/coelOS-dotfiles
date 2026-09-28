import QtQuick
import Quickshell.Io

// ----- app search (rofi -show drun replacement) -----
// Real .desktop file parsing via scripts/list-apps.py, not invented data.
// Refreshed every panel open (see LauncherPanel.qml's onPanelOpenChanged),
// same reasoning as SshBackend -- installed apps can change between opens.
Item {
  id: root

  property var installed: []
  readonly property string scriptPath: Qt.resolvedUrl("../../scripts/list-apps.py").toString().replace("file://", "")
  function refresh() { proc.running = true; }

  Process {
    id: proc
    command: ["python3", root.scriptPath]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.installed = JSON.parse(text); } catch (e) { root.installed = []; }
      }
    }
  }
}
