-- Hyprland configuration (Lua). Deployed as ~/.config/hypr/hyprland.lua by
-- home/hyprland.nix, which fills in the @placeholders@ (store paths, theme
-- colours). Hyprland reads this INSTEAD of a hyprland.conf.
--
-- API reference: <hyprland>/share/hypr/stubs/hl.meta.lua

local mainMod  = "SUPER"
local terminal = "ghostty"
local qs       = "@quickshell@/bin/quickshell ipc -p ~/.nixos/home/quickshell call"

------------------------------------------------------------------ monitors

-- Runtime-editable settings (settings.toml in the repo; see its header). Loaded
-- defensively: a missing or broken file gives {} and the built-in defaults in
-- this file apply, so a typo there can't take the session down.
package.path = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr/?.lua;" .. package.path
local Settings = require("settings")
local S, settings_err = Settings.load()
if settings_err then print("settings.toml: " .. settings_err .. " (using built-in defaults)") end

local default_scale = Settings.get(S, "display.scale", 1)

-- One hl.monitor() rule from a [monitors.*] table. output "" is the wildcard.
local function apply_monitor(output, c)
    if c.disabled then
        hl.monitor({ output = output, disabled = true })
        return
    end
    local rule = {
        output   = output,
        mode     = c.mode or "preferred",
        position = c.position or "auto",
        scale    = c.scale or default_scale,
    }
    if c.transform then rule.transform = c.transform end
    if c.mirror then rule.mirror = c.mirror end
    hl.monitor(rule)
end

local mons = type(S.monitors) == "table" and S.monitors or {}
if next(mons) == nil then
    -- No [monitors] in settings.toml: the original rules.
    hl.monitor({ output = "eDP-1", mode = "2256x1504@59.999", position = "0x0", scale = default_scale })
    hl.monitor({ output = "", mode = "preferred", position = "auto-center-up", scale = default_scale })
else
    local names = {}
    for name, c in pairs(mons) do
        if name ~= "default" and type(c) == "table" then names[#names + 1] = name end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local ok, err = pcall(apply_monitor, name, mons[name])
        if not ok then print("settings.toml [monitors." .. name .. "]: " .. tostring(err)) end
    end
    -- The wildcard for whatever else is plugged in. auto-center-up stacks it
    -- above eDP-1 and centres it horizontally, computed from the connecting
    -- monitor's own real size (not a hardcoded offset).
    pcall(apply_monitor, "", type(mons.default) == "table" and mons.default
        or { mode = "preferred", position = "auto-center-up" })
end

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
-- settings.toml [env]: extra or overriding variables.
for k, v in pairs(type(S.env) == "table" and S.env or {}) do hl.env(k, tostring(v)) end

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

-- settings.toml [config.*]: any Hyprland option, layered over the defaults above.
-- Arrays of four for gaps mean top, right, bottom, left.
if type(S.config) == "table" then
    local g = type(S.config.general) == "table" and S.config.general or {}
    for _, k in ipairs({ "gaps_in", "gaps_out" }) do
        local v = g[k]
        if type(v) == "table" and #v == 4 then g[k] = { top = v[1], right = v[2], bottom = v[3], left = v[4] } end
    end
    local ok, err = pcall(hl.config, S.config)
    if not ok then print("settings.toml [config]: " .. tostring(err)) end
end

------------------------------------------------------------------ workspace grid
-- The logic (rows of 100, a remembered column per row, vertical vs sideways slide,
-- one row per swipe) is in grid.lua, a plain module with its own unit tests
-- (grid_test.lua). This only plugs Hyprland into it.
package.path = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr/?.lua;" .. package.path

-- One speed for both slides (sideways and up/down), in tenths of a second, so they
-- always feel the same: 3 is about 300 ms. Lower is snappier.
local SLIDE_SPEED = 3

local Grid = require("grid")

-- The workspaces (five rows of 100) are shared by all monitors: a workspace is shown by
-- one monitor at a time, and every monitor sits on a row (by default all on the same
-- one) and can be moved to another with the swipes, keys or the overview. What a row
-- returns to is remembered per monitor, so each keeps its own grid state (a `Grid`).
local function host_focus(id)
    -- on_current_monitor: the monitor you are on always ends up showing it (if another
    -- monitor was showing it, they swap) instead of focus jumping over to that monitor.
    hl.dispatch(hl.dsp.focus({ workspace = id, on_current_monitor = true }))
end
local grid_host = {
    focus = host_focus,
    -- Moves the focused window and follows it.
    move = function(id) hl.dispatch(hl.dsp.window.move({ workspace = id })) end,
    animate = function(style)
        hl.animation({ leaf = "workspaces", enabled = true, speed = SLIDE_SPEED, bezier = "default", style = style })
    end,
    after = function(ms, fn) hl.timer(fn, { timeout = ms, type = "oneshot" }) end,
}
-- Can this monitor move through workspace `id`? Not when another monitor has it: one that
-- monitor is showing, or holds windows (they are laid out for that monitor, so showing or
-- sliding it here would half-draw them). A workspace that does not exist yet or is empty is
-- free. Stepping, rows and swipes only ever use such workspaces; asking for one by number
-- (Super+1..0, a bar chip, the overview) still takes it over.
local function usable_for(name)
    return function(id)
        local ws = hl.get_workspace(id)
        if not ws then return true end
        local m = ws.monitor
        if not m or m.name == name then return true end
        return ws.windows == 0 and not ws.visible
    end
end
local grids = {}      -- monitor name -> Grid
local function grid_for(name)
    if not grids[name] then
        -- Each grid reads the workspace its own monitor is showing.
        local host = setmetatable({
            active_id = function()
                local m = hl.get_monitor(name)
                local ws = m and m.active_workspace
                return ws and ws.id
            end,
            usable = usable_for(name),
        }, { __index = grid_host })
        grids[name] = Grid.new(host, {
            -- Put the sideways slide back once the up/down one has played: a little longer
            -- than the animation itself (SLIDE_SPEED tenths of a second).
            restore_ms = SLIDE_SPEED * 100 + 150,
        })
    end
    return grids[name]
end
-- The grid of the monitor you are on.
local function grid_now()
    local m = hl.get_active_monitor()
    return grid_for(m and m.name or "")
end
local grid = setmetatable({}, { __index = function(_, k)
    return function(...) local g = grid_now(); return g[k](...) end
end })
hl.animation({ leaf = "workspaces", enabled = true, speed = SLIDE_SPEED, bezier = "default", style = "slide" })

-- Every arrival, however it happened (key, swipe, panel click, window carried
-- along), updates the remembered column, so leaving a row always records where
-- you were.
-- The overview (home/quickshell/Overview.qml) takes you to a row through this...
coel_grid = grid
-- ...and reads which workspace each row returns to from this file, kept up to date
-- on every change of workspace: a line per monitor, "<monitor name>:<five ids>" (see grid.snapshot()).
local rows_file = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/coel-grid-rows"
local function save_rows()
    local f = io.open(rows_file, "w")
    if not f then return end
    for name, g in pairs(grids) do
        if name ~= "" and name ~= "FALLBACK" then f:write(name, ":", g.snapshot(), "\n") end
    end
    f:close()
end
-- The compositor's grid swipe (patches/hyprland-grid-swipe.patch) slides to
-- whichever workspace is named for the swipe's direction, so tell it on every change.
local function publish_targets()
    local t = grid.swipe_targets()
    -- pcall: a Hyprland without the patch (before the rebuild is switched to) does not
    -- know these options; stay quiet rather than raise an error on every change.
    pcall(hl.config, { gestures = {
        workspace_swipe_grid_left = t.left, workspace_swipe_grid_right = t.right,
        workspace_swipe_grid_up = t.up, workspace_swipe_grid_down = t.down,
    } })
end
local function real_monitors()
    local out = {}
    for _, m in ipairs(hl.get_monitors()) do
        if m.name ~= "FALLBACK" then out[#out + 1] = m end
    end
    return out
end

-- When monitors appear (or at login) they should all sit on the same row, each on a
-- workspace of its own: a new monitor starts out on whatever workspace Hyprland picked.
-- The focused monitor stays where it is; the others are moved to the first column of its
-- row that no other monitor is showing. Done a moment after the event, never inside it.
local function place_monitors()
    local here = hl.get_active_monitor()
    local ws0 = here and here.active_workspace
    local id0 = ws0 and ws0.id
    if not id0 or id0 < 1 then return end
    local row = Grid.row_of(id0)
    local chosen = {}
    for _, m in ipairs(real_monitors()) do
        local ws = m.active_workspace
        local id = ws and ws.id
        if m.name ~= here.name and id and id > 0 and (id > Grid.SLOT or Grid.row_of(id) ~= row) then
            local free = usable_for(m.name)
            local col = 0
            while (chosen[Grid.id_of(row, col)] or not free(Grid.id_of(row, col)) or Grid.id_of(row, col) == id0)
                and col < Grid.ROW - 1 do
                col = col + 1
            end
            local target = Grid.id_of(row, col)
            chosen[target] = true
            hl.dispatch(hl.dsp.focus({ monitor = m.name }))
            hl.dispatch(hl.dsp.focus({ workspace = target }))
        end
    end
    hl.dispatch(hl.dsp.focus({ monitor = here.name }))
end
local function place_soon() hl.timer(place_monitors, { timeout = 400, type = "oneshot" }) end

local function sync_now()
    for _, m in ipairs(real_monitors()) do grid_for(m.name).arrived() end
    save_rows()
    publish_targets()
end
-- Events arrive while Hyprland is still in the middle of the change (the focused monitor
-- may not have switched yet), so look again a moment later as well.
local sync_pending = false
local function sync()
    sync_now()
    if not sync_pending then
        sync_pending = true
        hl.timer(function() sync_pending = false; sync_now() end, { timeout = 60, type = "oneshot" })
    end
end
hl.on("workspace.active", sync)
-- At login no workspace is active yet when this file loads and the first one may
-- never raise workspace.active, so the targets would stay empty (no gestures until a
-- keybind changed workspace). These catch the first workspace and any monitor change.
hl.on("hyprland.start", function() sync(); place_soon() end)
hl.on("monitor.added", function() sync(); place_soon() end)
hl.on("monitor.focused", sync)
hl.on("workspace.created", sync)
-- Which workspaces another monitor holds (and so may not be swiped onto) changes with these.
hl.on("workspace.removed", sync)
hl.on("window.open", sync)
hl.on("window.close", sync)
hl.on("window.move_to_workspace", sync)
save_rows()
publish_targets()   -- a fresh session starts with a fresh file, never a stale one

------------------------------------------------------------------ gestures
-- Three fingers, both axes: Hyprland's own swipe, patched (patches/hyprland-grid-swipe.patch)
-- so the workspaces follow your fingers sideways AND up/down. With workspace_swipe_grid
-- on, a sideways swipe slides to the left/right target and a vertical one to the
-- up/down target, as published above by grid.swipe_targets(); a direction with no
-- target (row ends, first/last row) does not move.
pcall(hl.config, { gestures = { workspace_swipe_grid = true } })
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "vertical",   action = "workspace" })
-- Four fingers: up opens the workspace overview (home/quickshell/Overview.qml, in
-- the panel), down closes it, and the overview follows your fingers as they move.
-- "event" is an action of the patched Hyprland: it only reports the swipe's progress
-- as "coelswipe" events, which Overview.qml follows. Escape or a click also close it.
hl.gesture({ fingers = 4, direction = "up",   action = "event", mode = "up" })
hl.gesture({ fingers = 4, direction = "down", action = "event", mode = "down" })

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

-- Super+Ctrl+1..5: carry the focused window to that row (landing on the column the
-- row was last left on) and follow it. Dragging a window in the overview does the
-- same for any workspace.
for r = 1, 5 do
    hl.bind(mainMod .. " + CTRL + " .. r, function() grid.goto_row(r - 1, true) end)
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
