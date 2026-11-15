-- Hyprland configuration (Lua). Deployed as ~/.config/hypr/hyprland.lua by
-- home/hyprland.nix, which fills in the @placeholders@ (store paths, theme
-- colours). Hyprland reads this INSTEAD of a hyprland.conf.
--
-- API reference: <hyprland>/share/hypr/stubs/hl.meta.lua

local mainMod  = "SUPER"
local terminal = "ghostty"
local qs       = "@quickshell@/bin/quickshell ipc -p ~/.nixos/home/quickshell call"

------------------------------------------------------------------ monitors
hl.monitor({ output = "eDP-1", mode = "2256x1504@59.999", position = "0x0", scale = 1 })
-- A wildcard for whatever else is plugged in. auto-center-up stacks it above
-- eDP-1 and centres it horizontally, computed from the connecting monitor's own
-- real size (not a hardcoded offset).
hl.monitor({ output = "", mode = "preferred", position = "auto-center-up", scale = 1 })

------------------------------------------------------------------ environment
-- Also set here (not just home.sessionVariables) so it reaches everything
-- Hyprland starts, however the session environment happened to be inherited.
hl.env("NIXOS_OZONE_WL", "1")
hl.env("MOZ_ENABLE_WAYLAND", "1")
-- Gives Qt6 apps a real colour source instead of stock light Qt defaults
-- (home/qt-theme.nix), and makes qt6ct's plugins findable for apps whose own
-- wrapper bakes in a QT_PLUGIN_PATH.
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_PLUGIN_PATH", "@profileDir@/lib/qt-6/plugins")

------------------------------------------------------------------ look and feel
hl.config({
    -- After suspend/lock the hardware cursor plane sometimes isn't restored,
    -- leaving the lock screen with no pointer until a VT switch re-inits the
    -- display. A software cursor avoids that.
    cursor = { no_hardware_cursors = true },

    general = {
        gaps_in     = 4,
        gaps_out    = { top = 8, right = 12, bottom = 12, left = 12 },
        border_size = 2,
        col = {
            -- Blue -> yellow gradient on focus (theme/onedark.nix); muted
            -- comment-grey when idle. Red is reserved for errors.
            active_border   = { colors = { "rgba(@blue@ee)", "rgba(@yellow@ee)" }, angle = 45 },
            inactive_border = "rgba(@comment@aa)",
        },
    },

    decoration = { rounding = 8 },

    input = {
        touchpad = {
            natural_scroll       = true,
            clickfinger_behavior = true,
        },
    },
})

------------------------------------------------------------------ workspace grid
-- The logic (rows of 100, a remembered column per row, vertical vs sideways slide,
-- one row per swipe) is in grid.lua, a plain module with its own unit tests
-- (grid_test.lua). This only plugs Hyprland into it.
package.path = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr/?.lua;" .. package.path

local grid = require("grid").new({
    active_id = function()
        local ws = hl.get_active_workspace()
        return ws and ws.id
    end,
    focus = function(id) hl.dispatch(hl.dsp.focus({ workspace = id })) end,
    -- Moves the focused window and follows it.
    move = function(id) hl.dispatch(hl.dsp.window.move({ workspace = id })) end,
    animate = function(style)
        hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "default", style = style })
    end,
    after = function(ms, fn) hl.timer(fn, { timeout = ms, type = "oneshot" }) end,
})
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "default", style = "slide" })

-- Every arrival, however it happened (key, swipe, panel click, window carried
-- along), updates the remembered column, so leaving a row always records where
-- you were.
hl.on("workspace.active", grid.arrived)

hl.config({
    gestures = {
        -- Hyprland's own sideways swipe normally steps to the next EXISTING
        -- workspace, which can be one in another row. This makes it step by plain
        -- workspace number (+1/-1), i.e. along the row.
        workspace_swipe_use_r = true,
    },
})

------------------------------------------------------------------ gestures
-- Sideways: Hyprland's own swipe, the workspaces follow your fingers. The
-- built-in swipe tracks one axis only, so up/down cannot be built in: they step
-- one row per swipe (grid.gesture_row ignores repeat events from one swipe).
-- Four fingers are left free for a future overview. If up/down feel backwards,
-- swap the two directions.
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "up",   action = function() grid.gesture_row(1) end })
hl.gesture({ fingers = 3, direction = "down", action = function() grid.gesture_row(-1) end })

------------------------------------------------------------------ autostart
hl.on("hyprland.start", function()
    -- Before the session target starts hypridle: lets `coel-hub lock` know
    -- which session the idle timer belongs to.
    hl.exec_cmd("systemctl --user import-environment XDG_SESSION_ID")
    hl.exec_cmd("systemctl --user start hyprland-session.target")
    -- Quickshell's own Polkit.qml is the authentication agent (only one can
    -- register per session) and its notifications backend is the real
    -- org.freedesktop.Notifications server, so no separate agent/mako here.
    -- Blocks logind's default hardware-power-key handling so the XF86PowerOff
    -- bind below (-> coel-power-menu) is what fires, instead of an immediate
    -- shutdown racing the menu.
    hl.exec_cmd("@systemd@/bin/systemd-inhibit --what=handle-power-key --who=Hyprland --why='Custom power menu' --mode=block sleep infinity")
    -- Random wallpaper on every login (home/wallpaper.nix); the script retries
    -- for a few seconds in case it races the awww daemon's startup.
    hl.exec_cmd("coel-random-wallpaper")
    -- -c straight at this repo (not ~/.config/quickshell) so quickshell
    -- hot-reloads on edit while developing the panel. Normal logins use Qt's
    -- compiled-QML cache; it is wiped on every rebuild (home/hyprland.nix) and
    -- bypassed by the manual restart script (F4).
    hl.exec_cmd("@quickshell@/bin/quickshell -c ~/.nixos/home/quickshell")
end)

------------------------------------------------------------------ keybinds
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))

-- Fn lock OSD. The patched Framework EC taps KEY_F13 when Fn lock turns on and
-- KEY_F14 when it turns off; xkb's us layout maps those keycodes (191/192) to
-- XF86Tools / XF86Launch5, which is what is bound here. The initial state is
-- read at startup from /run/fnlock/state (Osd.qml).
hl.bind("XF86Tools",   hl.dsp.exec_cmd(qs .. " osd fnLockOn"))
hl.bind("XF86Launch5", hl.dsp.exec_cmd(qs .. " osd fnLockOff"))

-- F4: kill any running panel and relaunch it.
hl.bind("F4", hl.dsp.exec_cmd("@restartQuickshell@"))

-- `quickshell ipc call` talks to the IpcHandlers; it needs `-p <path>` to target
-- the instance launched above with `-c` (with no flag it looks for the default
-- ~/.config/quickshell/shell.qml instance and silently no-ops).
hl.bind(mainMod .. " + space",         hl.dsp.exec_cmd(qs .. " launcher toggle"))
-- The laptop's dedicated launcher key (KEY_MEDIA; xkb calls it XF86AudioMedia).
hl.bind("XF86AudioMedia",              hl.dsp.exec_cmd(qs .. " launcher toggle"))
hl.bind(mainMod .. " + SHIFT + space", hl.dsp.exec_cmd(qs .. " launcher toggle"))
-- Launcher restricted to emoji-only search.
hl.bind(mainMod .. " + period",        hl.dsp.exec_cmd(qs .. " launcher openEmoji"))
-- Launcher's own clipboard tab (real preview of text / images).
hl.bind(mainMod .. " + V",             hl.dsp.exec_cmd(qs .. " launcher openClipboard"))
-- Notification dropdown on whichever screen has focus.
hl.bind(mainMod .. " + CTRL + SHIFT + N", hl.dsp.exec_cmd(qs .. " notifications toggle"))

-- Lock this session, then go to the login screen (the session hub,
-- modules/session-hub.nix); the session's own lock screen is not shown.
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("coel-hub lock"))
hl.bind(mainMod .. " + W", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("coel-logout"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("coel-random-wallpaper"))
hl.bind(mainMod .. " + F",           hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + F",   hl.dsp.window.fullscreen())

-- Focus
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Resize the focused window
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.resize({ x = 10,  y = 0,   relative = true }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.resize({ x = -10, y = 0,   relative = true }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.resize({ x = 0,   y = -10, relative = true }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.resize({ x = 0,   y = 10,  relative = true }))

-- Workspace grid: Super+Ctrl+arrows move between workspaces, adding Shift
-- carries the focused window along. Left/right are unbounded; up/down change row.
hl.bind(mainMod .. " + CTRL + left",  function() grid.go_col(-1, false) end)
hl.bind(mainMod .. " + CTRL + right", function() grid.go_col(1, false) end)
hl.bind(mainMod .. " + CTRL + up",    function() grid.go_row(-1, false) end)
hl.bind(mainMod .. " + CTRL + down",  function() grid.go_row(1, false) end)
hl.bind(mainMod .. " + CTRL + SHIFT + left",  function() grid.go_col(-1, true) end)
hl.bind(mainMod .. " + CTRL + SHIFT + right", function() grid.go_col(1, true) end)
hl.bind(mainMod .. " + CTRL + SHIFT + up",    function() grid.go_row(-1, true) end)
hl.bind(mainMod .. " + CTRL + SHIFT + down",  function() grid.go_row(1, true) end)
hl.bind(mainMod .. " + Page_Down",         function() grid.go_row(1, false) end)
hl.bind(mainMod .. " + Page_Up",           function() grid.go_row(-1, false) end)
hl.bind(mainMod .. " + SHIFT + Page_Down", function() grid.go_row(1, true) end)
hl.bind(mainMod .. " + SHIFT + Page_Up",   function() grid.go_row(-1, true) end)

-- Super+1..0: that column of the current row; Shift carries the window.
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,           function() grid.go_number(i, false) end)
    hl.bind(mainMod .. " + SHIFT + " .. key,   function() grid.go_number(i, true) end)
end

-- Move / resize windows with Super + left / right mouse button
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Volume and brightness go through Osd.qml's own IpcHandler (real OSD popup).
hl.bind("XF86AudioRaiseVolume",    hl.dsp.exec_cmd(qs .. " osd volumeUp"))
hl.bind("XF86AudioLowerVolume",    hl.dsp.exec_cmd(qs .. " osd volumeDown"))
hl.bind("XF86AudioMute",           hl.dsp.exec_cmd(qs .. " osd volumeMuteToggle"))
hl.bind("XF86MonBrightnessUp",     hl.dsp.exec_cmd(qs .. " osd brightnessUp"))
hl.bind("XF86MonBrightnessDown",   hl.dsp.exec_cmd(qs .. " osd brightnessDown"))

hl.bind("Print",           hl.dsp.exec_cmd("coel-screenshot"))
hl.bind("XF86PowerOff",    hl.dsp.exec_cmd("coel-power-menu"))
-- The laptop's F9 display key sends Super+P, not an XF86 keysym.
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("coel-displays"))

-- Media keys work while locked. Real MPRIS control via Osd.qml.
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd(qs .. " osd mediaPrevious"),  { locked = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd(qs .. " osd mediaNext"),      { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd(qs .. " osd mediaPlayPause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(qs .. " osd mediaPlayPause"), { locked = true })

-- Caps lock OSD. Non-consuming, so Caps Lock still toggles normally; Osd.qml
-- reads the keyboard LED a moment later to learn the new state.
hl.bind("Caps_Lock", hl.dsp.exec_cmd(qs .. " osd capsLock"), { non_consuming = true })

------------------------------------------------------------------ window rules
-- `ghostty --class=com.joelsgc.floating -e <cmd>` opens a one-off utility
-- terminal (fingerprint enroll/delete, coel-update, pulsemixer, btop, ...)
-- that should float instead of tiling. Sized in pixels (ghostty's own
-- cell-based size is buggy under GTK decorations); 1556x925 is ~140x41 columns
-- at this system's font, comfortable for btop-style panes.
hl.window_rule({
    name  = "float-utility-terminal",
    match = { class = "^com\\.joelsgc\\.floating$" },
    float = true,
    size  = "1556 925",
})

-- Same idea for the fastfetch "About" popup.
hl.window_rule({
    name  = "float-info-terminal",
    match = { class = "^com\\.joelsgc\\.info$" },
    float = true,
    size  = "832 502",
})

-- Ignore maximize requests from all apps.
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Works around an XWayland dragging bug.
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

------------------------------------------------------------------ layer rules
-- See home/quickshell/sysPanel/Popup.qml's WlrLayershell.namespace comment:
-- stops Hyprland's default layer fade from animating this popup's open/close,
-- which could otherwise be caught mid-fade by a screenshot taken right as
-- HyprlandFocusGrab closes it.
hl.layer_rule({
    name    = "quickshell-popup-no-anim",
    match   = { namespace = "coel-sys-popup" },
    no_anim = true,
})
