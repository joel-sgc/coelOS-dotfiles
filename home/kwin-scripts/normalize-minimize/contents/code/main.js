// A KWin script to provide a "normalize or minimize" action.
// If the active window is maximized, it will be restored to its normal size.
// If the active window is not maximized, it will be minimized.

registerShortcut(
  "NormalizeOrMinimize",
  "Normalize if maximized, else minimize",
  "Meta+Down",
  function () {
    var client = workspace.activeClient; // activeClient is the modern API
    if (client) {
      // client.maximizeMode: 0 is normal, 1 is vertical, 2 is horizontal, 3 is full.
      // We check if it's maximized in any way (horizontal, vertical, or full).
      if (client.maximizeMode > 0) {
        // Un-maximize the window by setting both horizontal and vertical maximize to false.
        client.setMaximize(false, false);
      } else {
        // If not maximized, minimize the window.
        client.minimized = true;
      }
    }
  }
);
