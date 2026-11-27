import QtQuick
import QtMultimedia

// One preloaded SoundEffect per sound, so playback starts with no delay.
// Loaded by Sounds.qml with Qt.createComponent: the only file that imports
// QtMultimedia, so a Quickshell without it (see the overlay in
// configuration.nix) falls back to pw-play instead of failing to load.
Item {
  id: bank
  property var urls: ({})      // name -> file URL
  property real volume: 0.5
  property var effects: ({})

  Component { id: effect; SoundEffect {} }

  onUrlsChanged: {
    for (const n in effects) effects[n].destroy();
    const next = {};
    for (const n in urls) next[n] = effect.createObject(bank, { source: urls[n], volume: bank.volume });
    effects = next;
  }
  onVolumeChanged: { for (const n in effects) effects[n].volume = volume; }

  function play(name) {
    const e = effects[name];
    if (!e) return false;
    e.play();   // restarts if it is still playing (rapid volume ticks)
    return true;
  }
}
