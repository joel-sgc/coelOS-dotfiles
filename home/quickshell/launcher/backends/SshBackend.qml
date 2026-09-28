import QtQuick
import Quickshell.Io

// ----- ssh hosts (real ~/.ssh/config parse, see scripts/list-ssh-hosts.py) -----
// A real category (chip, browsable with no query), not search-only --
// ssh_config entries are small/hand-curated like launch/toggles/system,
// nothing like clipboard/emoji's render-count concerns. Re-parsed every
// panel open (cheap, local file) rather than loaded once, same timing as
// AppsBackend -- the config can change between opens.
Item {
  id: root

  // Hidden by Host alias, not by IP/hostname -- add names here as wanted.
  // Same "hide by the name you'd actually recognize it by" convention as
  // hiddenDesktopIds in home/desktop-entries.nix.
  readonly property var blacklist: ["proxy", "testing-vm"]
  property var hosts: []
  readonly property string scriptPath: Qt.resolvedUrl("../../scripts/list-ssh-hosts.py").toString().replace("file://", "")
  function refresh() { proc.running = true; }

  Process {
    id: proc
    command: ["python3", root.scriptPath]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.hosts = JSON.parse(text); } catch (e) { root.hosts = []; }
      }
    }
  }

  function categoryItems() {
    return hosts
      .filter(h => blacklist.indexOf(h.name) === -1)
      .map(h => ({
        label: h.name,
        sub: (h.user ? h.user + "@" : "") + h.hostname,
        icon: "hard-drives", right: ":" + h.port,
        sshHost: h.name, sshUser: h.user, sshHostName: h.hostname, sshPort: h.port, sshKey: h.identityFile,
      }));
  }
}
