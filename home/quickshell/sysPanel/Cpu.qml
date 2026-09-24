import QtQuick
import Quickshell.Io
import "./Phosphor.js" as Phosphor

// ===== CPU =====
// Ported from home/waybar.nix's cpu module -- same on-click (btop)/
// on-click-right (plain ghostty) split, but a real live usage percentage
// instead of waybar's static "" glyph-only button, since Quickshell has no
// built-in cpu module to lean on the way UPower covers battery. Sampled by
// reading /proc/stat's aggregate line twice 0.3s apart and diffing --
// same technique waybar/most minimal cpu widgets use -- via a plain `sh -c`
// one-liner rather than a new packaged script, since this is the one thing
// here that isn't just an existing coel-* command.
Button {
  id: cpuRoot

  property int usage: 0

  icon: Phosphor.icon("cpu")
  label: usage + "%"
  // Right-aligned, reserved-width label -- matches the mock's
  // min-width:3ch so the row doesn't jitter as usage crosses a digit
  // boundary (9% -> 10%, 99% -> 100%).
  labelMinWidth: 24
  command: [ "ghostty", "--class=com.joelsgc.floating", "-e", "btop" ]
  rightCommand: [ "ghostty" ]

  Process {
    id: sampler
    command: [
      "sh", "-c",
      "read -r _ u1 n1 s1 i1 _ < /proc/stat; sleep 0.3; read -r _ u2 n2 s2 i2 _ < /proc/stat; t1=$((u1+n1+s1+i1)); t2=$((u2+n2+s2+i2)); echo $(( 100 - (100 * (i2-i1)) / (t2-t1) ))"
    ]
    stdout: StdioCollector {
      onStreamFinished: cpuRoot.usage = parseInt(text.trim()) || 0
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: sampler.running = true
  }
}
