-- Workspace grid logic. Plain Lua with NO Hyprland calls, so it can be unit
-- tested (home/hyprland/grid_test.lua) against a fake host. hyprland.lua plugs
-- the real Hyprland in.
--
-- Workspaces are a grid in rows of ROW (100): row 0 is 1..100 (so Super+1..0 are
-- the first ten), row 1 is 101..200, and so on. Columns are 0-based inside the
-- code (column 0 is workspace 1 of the row). Sideways has no limit beyond the
-- row; up/down change row. Every row remembers the column you left it on: go
-- down, scroll along, come back up and you are where you were. A row you have
-- not visited opens at the column you are on now.
--
-- The host object supplies everything that touches the compositor:
--   host.active_id()   -> the active workspace id, or nil / <= 0 when there is
--                         none or it is a special workspace (scratchpad)
--   host.focus(id)     -> switch to workspace `id`
--   host.move(id)      -> carry the focused window to `id` and follow it
--   host.animate(s)    -> set the workspace slide style ("slide" | "slidevert")
--   host.after(ms, fn) -> run fn once after ms milliseconds

local M = {}

M.ROW = 100
local ROW = M.ROW

-- Hyprland's own sideways swipe and `workspace +1` both walk consecutive ids,
-- so a row is a run of ids and a column is the id's place in that run.
function M.row_of(id) return math.floor((id - 1) / ROW) end
function M.col_of(id) return (id - 1) % ROW end
function M.id_of(row, col) return row * ROW + col + 1 end

function M.new(host, opts)
    opts = opts or {}
    local restore_ms  = opts.restore_ms or 700           -- put the sideways slide back after this
    local cooldown_ms = opts.gesture_cooldown_ms or 350  -- one row per swipe, however many events

    local last_col = {}   -- row -> column last visited in it
    local style_gen = 0   -- bumped on every move; only the newest restore timer may act
    local cooling = false
    local g = {}

    local function active()
        local id = host.active_id()
        if id and id >= 1 then return id end
        return nil
    end

    -- Every arrival, however it happened (key, swipe, panel click, window carried
    -- along), is recorded here by the host's workspace-changed event.
    function g.arrived()
        local id = active()
        if id then last_col[M.row_of(id)] = M.col_of(id) end
    end

    -- `from` is the active numbered workspace, or nil from a scratchpad.
    local function jump(from, target, carry, style)
        if from then
            if target == from then return false end
            -- Note where we are before leaving, in case the host's arrival event
            -- never reached us.
            last_col[M.row_of(from)] = M.col_of(from)
        end
        style_gen = style_gen + 1
        host.animate(style)
        if carry then host.move(target) else host.focus(target) end
        if style ~= "slide" then
            -- Hyprland has one animation style for workspaces and the built-in
            -- sideways swipe slides whatever is set, so put it back once the
            -- vertical animation has played. A newer move cancels an older
            -- restore, or it would cut the newer animation short.
            local gen = style_gen
            host.after(restore_ms, function()
                if gen == style_gen then host.animate("slide") end
            end)
        end
        return true
    end

    -- Sideways within the row. delta is -1 or +1. Returns true if it moved.
    function g.go_col(delta, carry)
        local id = active()
        if not id then return false end
        local col = M.col_of(id) + delta
        if col < 0 or col >= ROW then return false end
        return jump(id, M.id_of(M.row_of(id), col), carry, "slide")
    end

    -- Up/down a row, landing on the column that row was left on. delta is -1 or +1.
    function g.go_row(delta, carry)
        local id = active()
        if not id then return false end
        local row, col = M.row_of(id), M.col_of(id)
        -- Record where we are before leaving, even if the host's arrival event
        -- did not reach us.
        last_col[row] = col
        local new_row = row + delta
        if new_row < 0 then return false end
        local landing = last_col[new_row]
        if landing == nil then landing = col end
        return jump(id, M.id_of(new_row, landing), carry, "slidevert")
    end

    -- A swipe may deliver more than one event for a single gesture, which would
    -- hop several rows; accept one row move, then ignore the rest for a moment.
    function g.gesture_row(delta)
        if cooling then return false end
        local moved = g.go_row(delta, false)
        if moved then
            cooling = true
            host.after(cooldown_ms, function() cooling = false end)
        end
        return moved
    end

    -- Column n (1..ROW) of the current row (Super+1..0 are 1..10).
    function g.go_number(n, carry)
        if type(n) ~= "number" or n ~= math.floor(n) or n < 1 or n > ROW then return false end
        local id = active()
        -- From a scratchpad there is no current row: use the first.
        return jump(id, M.id_of(M.row_of(id or 1), n - 1), carry, "slide")
    end

    -- For tests and debugging.
    function g.remembered(row) return last_col[row] end

    return g
end

return M
