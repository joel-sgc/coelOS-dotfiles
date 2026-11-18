-- Workspace grid logic. Plain Lua with NO Hyprland calls, so it can be unit
-- tested (home/hyprland/grid_test.lua) against a fake host. hyprland.lua plugs
-- the real Hyprland in.
--
-- Workspaces are a grid of ROWS (5) rows of ROW (100) columns: row 0 is 1..100
-- (so Super+1..0 are the first ten), row 1 is 101..200, up to row 4 (401..500).
-- Columns are 0-based inside the code (column 0 is workspace 1 of the row).
-- Sideways stays inside the row; up/down change row. Every row remembers the column you left it on: go
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
--   host.usable(id)    -> (optional) false when workspace `id` belongs to another monitor
--                         (it is showing it, or has windows on it). Moving around the grid
--                         (steps, rows, swipes) never lands on such a workspace; asking for
--                         one by number (go_number) still takes it over.

local M = {}

M.ROW = 100    -- columns per row
M.ROWS = 5     -- rows in the grid; going down from the last one does nothing
local ROW = M.ROW
local ROWS = M.ROWS
local MAX_ID = ROWS * ROW    -- the last workspace of the grid

-- Hyprland's own sideways swipe and `workspace +1` both walk consecutive ids,
-- so a row is a run of ids and a column is the id's place in that run.
function M.row_of(id) return math.floor((id - 1) / ROW) end
function M.col_of(id) return (id - 1) % ROW end
function M.id_of(row, col) return row * ROW + col + 1 end

M.SLOT = ROWS * ROW    -- all the workspaces of the grid

function M.new(host, opts)
    opts = opts or {}
    local restore_ms  = opts.restore_ms or 700           -- put the sideways slide back after this

    local function usable(id) return host.usable == nil or host.usable(id) ~= false end

    -- The column in `row` to land on, as close as possible to `want` (0-based): `want`
    -- itself, else the nearest column whose workspace is usable. nil when there is none.
    local function landing_col(row, want)
        if usable(M.id_of(row, want)) then return want end
        for d = 1, ROW - 1 do
            if want - d >= 0 and usable(M.id_of(row, want - d)) then return want - d end
            if want + d < ROW and usable(M.id_of(row, want + d)) then return want + d end
        end
        return nil
    end

    -- The next usable column from `col` going `dir` (-1 or 1), skipping workspaces that
    -- belong to another monitor. nil at the end of the row.
    local function step_col(row, col, dir)
        local c = col + dir
        while c >= 0 and c < ROW do
            if usable(M.id_of(row, c)) then return c end
            c = c + dir
        end
        return nil
    end

    local last_col = {}   -- row -> column last visited in it
    local style_gen = 0   -- bumped on every move; only the newest restore timer may act
    local g = {}

    -- The active workspace if it is one of the grid's; nil for a scratchpad or
    -- anything outside the grid.
    local function active()
        local id = host.active_id()
        if id and id >= 1 and id <= MAX_ID then return id end
        return nil
    end

    -- Every arrival, however it happened (key, swipe, panel click, window carried
    -- along), is reported here by the host's workspace-changed event. It only
    -- records where we are: it never moves anything.
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
        local row = M.row_of(id)
        local col = step_col(row, M.col_of(id), delta < 0 and -1 or 1)
        if not col then return false end
        return jump(id, M.id_of(row, col), carry, "slide")
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
        if new_row < 0 or new_row >= ROWS then return false end
        local landing = landing_col(new_row, last_col[new_row] == nil and col or last_col[new_row])
        if landing == nil then return false end
        return jump(id, M.id_of(new_row, landing), carry, "slidevert")
    end

    -- Straight to row `row` (0-based), landing on the column that row was left on
    -- (or the column you are on, for a row you have not visited). Used by the
    -- overview and the move-to-row keys (carry: take the focused window along).
    -- Works from a scratchpad too, landing on the row's first column.
    function g.goto_row(row, carry)
        if type(row) ~= "number" or row ~= math.floor(row) or row < 0 or row >= ROWS then return false end
        local id = active()
        local col = 0
        if id then
            col = M.col_of(id)
            last_col[M.row_of(id)] = col
        end
        local landing = landing_col(row, last_col[row] == nil and col or last_col[row])
        if landing == nil then return false end
        return jump(id, M.id_of(row, landing), carry and true or false, "slidevert")
    end

    -- Where a swipe leads from here, for the compositor's grid swipe
    -- (gestures:workspace_swipe_grid): the workspace to slide to on each side, 0 for
    -- none. Sideways stays in the row (and stops at its first and last column);
    -- up/down land on the column each row was last left on, like go_row. Every
    -- left/up target is a lower workspace number than this one and every right/down
    -- target a higher one, which the compositor requires.
    function g.swipe_targets()
        local id = active()
        if not id then return { left = 0, right = 0, up = 0, down = 0 } end
        local row, col = M.row_of(id), M.col_of(id)
        local function other_row(r)
            if r < 0 or r >= ROWS then return 0 end
            local landing = landing_col(r, last_col[r] == nil and col or last_col[r])
            return landing and M.id_of(r, landing) or 0
        end
        local function side(dir)
            local c = step_col(row, col, dir)
            return c and M.id_of(row, c) or 0
        end
        return { left = side(-1), right = side(1), up = other_row(row - 1), down = other_row(row + 1) }
    end

    -- Column n (1..ROW) of the current row (Super+1..0 are 1..10).
    function g.go_number(n, carry)
        if type(n) ~= "number" or n ~= math.floor(n) or n < 1 or n > ROW then return false end
        local id = active()
        -- From a scratchpad there is no current row: use the first.
        return jump(id, M.id_of(M.row_of(id or 1), n - 1), carry, "slide")
    end

    -- The workspace each row would take you back to, as "id,id,id,id,id" (empty
    -- for a row you have not visited). The overview reads this to show every
    -- row as you left it.
    function g.snapshot()
        local ids = {}
        for row = 0, ROWS - 1 do
            local col = last_col[row]
            ids[row + 1] = col and tostring(M.id_of(row, col)) or ""
        end
        return table.concat(ids, ",")
    end

    -- For tests and debugging.
    function g.remembered(row) return last_col[row] end

    return g
end

return M
