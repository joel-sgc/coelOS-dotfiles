registerShortcut("NormalizeOrMinimize", "Normalize if maximized, else minimize", "Meta+Down", function() {
    let client = workspace.activeWindow;
    if (client) {
        if ((client.maximizeMode && client.maximizeMode !== 0) || client.maximized) {
            if (client.setMaximize) {
                client.setMaximize(false, false);
            } else {
                client.maximized = false;
            }
        } else {
            client.minimized = true;
        }
    }
});
