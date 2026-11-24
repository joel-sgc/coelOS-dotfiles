-- Unit tests for grid.lua (the workspace grid logic). No Hyprland needed:
--
--   python3 tests/run.py hyprland-grid       (or directly: lua tests/hyprland/grid_test.lua; Hyprland embeds Lua 5.5)
--
-- Loading this file with dofile() runs the tests and RETURNS the results as a table (it does not print or
-- exit); running it as a script prints a summary and sets the exit code.
--
-- The tests drive the real grid.lua against a fake host that behaves like the
-- parts of Hyprland the grid relies on: focusing a workspace makes it active and
-- fires the "workspace changed" event, moving a window follows it, timers run
-- when the test clock advances.

local SELF = debug.getinfo(1, "S").source:sub(2)       -- this file, also when loaded with dofile()
local HERE = SELF:match("(.*/)") or "./"
package.path = HERE .. "../../home/hyprland/?.lua;" .. package.path
local Grid = require("grid")
local ROW = Grid.ROW

---------------------------------------------------------------- tiny harness
local passed, failed, failures, results = 0, 0, {}, {}

local function fmt(v)
    if type(v) == "table" then
        local parts = {}
        for i, x in ipairs(v) do parts[i] = tostring(x) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(v)
end

local function eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "values differ", fmt(expected), fmt(actual)), 2)
    end
end

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        results[#results + 1] = { name = name, ok = true }
    else
        failed = failed + 1
        failures[#failures + 1] = "  FAIL  " .. name .. "\n        " .. tostring(err)
        results[#results + 1] = { name = name, ok = false, error = tostring(err) }
    end
end

---------------------------------------------------------------- fake Hyprland
local function new_world(opts)
    opts = opts or {}
    local w = {
        active = opts.start or 1,
        special = false,          -- a scratchpad is up: no numbered workspace is active
        style = "slide",
        styles = {},              -- every style set, in order
        now = 0,
        timers = {},
        seq = 0,
        window_on = opts.start or 1,
        focus_calls = 0,
        move_calls = 0,
        events = opts.events ~= false,
    }
    local grid
    local host = {}

    local function arrive(id)
        w.active = id
        if w.events and grid then grid.arrived() end
    end
    function host.active_id() if w.special then return -98 end return w.active end
    function host.focus(id) w.focus_calls = w.focus_calls + 1; arrive(id) end
    function host.move(id) w.move_calls = w.move_calls + 1; w.window_on = id; arrive(id) end
    function host.animate(s) w.style = s; w.styles[#w.styles + 1] = s end
    if opts.usable then host.usable = opts.usable end
    function host.after(ms, fn)
        w.seq = w.seq + 1
        w.timers[#w.timers + 1] = { at = w.now + ms, fn = fn, seq = w.seq }
    end

    -- Run every timer that comes due, in time order, including ones they add.
    function w.advance(ms)
        local target = w.now + ms
        while true do
            local best, bi
            for i, t in ipairs(w.timers) do
                if t.at <= target and (not best or t.at < best.at or (t.at == best.at and t.seq < best.seq)) then
                    best, bi = t, i
                end
            end
            if not best then break end
            table.remove(w.timers, bi)
            w.now = math.max(w.now, best.at)
            best.fn()
        end
        w.now = target
    end

    -- Switch workspace by something other than the grid: a built-in swipe, a
    -- panel click, `workspace N`. The grid only hears about it via the event.
    function w.click(id) arrive(id) end

    w.grid = Grid.new(host, opts.grid)
    grid = w.grid
    if w.events then grid.arrived() end   -- Hyprland announces the starting workspace
    return w
end

local function at(row, col) return Grid.id_of(row, col) end

---------------------------------------------------------------- id arithmetic
test("ids map to rows and columns", function()
    eq(Grid.row_of(1), 0); eq(Grid.col_of(1), 0)
    eq(Grid.row_of(10), 0); eq(Grid.col_of(10), 9)
    eq(Grid.row_of(100), 0); eq(Grid.col_of(100), 99, "last column of row 0")
    eq(Grid.row_of(101), 1); eq(Grid.col_of(101), 0, "first column of row 1")
    eq(Grid.row_of(200), 1); eq(Grid.col_of(200), 99)
    eq(Grid.row_of(1001), 10); eq(Grid.col_of(1001), 0)
end)

test("id_of is the inverse of row_of/col_of for every id in 20 rows", function()
    for id = 1, 20 * ROW do
        eq(Grid.id_of(Grid.row_of(id), Grid.col_of(id)), id, "round trip of " .. id)
    end
end)

---------------------------------------------------------------- sideways
test("go_col moves one column along the row", function()
    local w = new_world({ start = 3 })
    eq(w.grid.go_col(1, false), true)
    eq(w.active, 4)
    w.grid.go_col(-1, false); w.grid.go_col(-1, false)
    eq(w.active, 2)
end)

test("go_col stops at column 1 and does not wrap into the row above", function()
    local w = new_world({ start = 1 })
    eq(w.grid.go_col(-1, false), false)
    eq(w.active, 1)
    local v = new_world({ start = 101 })   -- first column of row 1
    eq(v.grid.go_col(-1, false), false)
    eq(v.active, 101, "must not fall back into row 0")
end)

test("go_col stops at the last column and does not spill into the next row", function()
    local w = new_world({ start = 99 })
    eq(w.grid.go_col(1, false), true); eq(w.active, 100)
    eq(w.grid.go_col(1, false), false, "100 -> 101 would change row")
    eq(w.active, 100)
    local v = new_world({ start = 200 })
    eq(v.grid.go_col(1, false), false); eq(v.active, 200)
end)

test("go_col far along a row keeps going (unbounded in practice)", function()
    local w = new_world({ start = 1 })
    for _ = 1, 99 do w.grid.go_col(1, false) end
    eq(w.active, 100)
end)

test("go_col uses the sideways slide and no restore timer", function()
    local w = new_world({ start = 5 })
    w.grid.go_col(1, false)
    eq(w.style, "slide")
    eq(#w.timers, 0, "nothing to restore for a sideways move")
end)

test("go_col with carry moves the window and follows it", function()
    local w = new_world({ start = 5 })
    w.grid.go_col(1, true)
    eq(w.window_on, 6); eq(w.active, 6)
    eq(w.move_calls, 1); eq(w.focus_calls, 0)
end)

---------------------------------------------------------------- rows
test("go_row down from row 0 lands on the same column of row 1", function()
    local w = new_world({ start = 4 })
    eq(w.grid.go_row(1, false), true)
    eq(w.active, 104)
end)

test("go_row up from row 0 does nothing", function()
    local w = new_world({ start = 4 })
    eq(w.grid.go_row(-1, false), false)
    eq(w.active, 4)
    eq(#w.styles, 0, "no animation change for a move that did not happen")
end)

test("rows remember their column (the example: row 1 on column 2, row 2 on column 4)", function()
    local w = new_world({ start = 1 })
    w.grid.go_col(1, false)                 -- row 0, column 2
    eq(w.active, 2)
    w.grid.go_row(1, false)                 -- row 1 opens on the same column (2)
    eq(w.active, 102)
    w.grid.go_col(1, false); w.grid.go_col(1, false)   -- row 1, column 4
    eq(w.active, 104)
    w.grid.go_row(-1, false)                -- back up: row 0 column 2
    eq(w.active, 2)
    w.grid.go_row(1, false)                 -- down: row 1 column 4
    eq(w.active, 104)
end)

test("column 0 is remembered too (0 is a real value, not 'unset')", function()
    local w = new_world({ start = 1 })      -- row 0, column 0
    w.grid.go_col(1, false); w.grid.go_col(1, false)   -- column 2
    w.grid.go_row(1, false)                 -- row 1, column 2
    w.click(101)                            -- row 1, column 0
    w.grid.go_row(-1, false)                -- row 0 column 2
    eq(w.active, 3)
    w.grid.go_row(1, false)                 -- row 1 must return to column 0, not column 2
    eq(w.active, 101)
end)

test("a never-visited row opens on the column you are on", function()
    local w = new_world({ start = 7 })
    w.grid.go_row(1, false); eq(w.active, 107)
    w.grid.go_row(1, false); eq(w.active, 207)
    w.grid.go_row(1, false); eq(w.active, 307)
end)

test("three rows each keep their own column", function()
    local w = new_world({ start = 1 })
    w.grid.go_row(1, false); w.grid.go_col(1, false)                   -- row 1, col 1
    w.grid.go_row(1, false); w.grid.go_col(1, false); w.grid.go_col(1, false)  -- row 2, col 3
    eq(w.active, at(2, 3))
    w.grid.go_row(-1, false); eq(w.active, at(1, 1))
    w.grid.go_row(-1, false); eq(w.active, at(0, 0))
    w.grid.go_row(1, false);  eq(w.active, at(1, 1))
    w.grid.go_row(1, false);  eq(w.active, at(2, 3))
end)

test("moves made by a swipe or a click are remembered (arrival event)", function()
    local w = new_world({ start = 1 })
    w.click(107)                            -- native jump into row 1 column 6
    w.grid.go_row(-1, false)
    eq(w.active, 1)
    w.grid.go_row(1, false)
    eq(w.active, 107, "row 1 should remember the column the click landed on")
end)

---------------------------------------------------------------- arrivals the grid did not make
test("even if the arrival event never comes, nothing moves from a workspace off the grid", function()
    local w = new_world({ start = 2147483647, events = false })
    eq(w.grid.go_col(1, false), false)
    eq(w.grid.go_col(-1, true), false)
    eq(w.grid.go_row(1, false), false)
    local t = w.grid.swipe_targets()
    eq(t.left + t.right + t.up + t.down, 0, "no swipe targets either")
    eq(w.active, 2147483647, "left exactly as it was: no arithmetic on a nonsense id")
    eq(w.focus_calls + w.move_calls, 0)
end)

test("the grid never moves anything by itself when told about an arrival", function()
    for _, landing in ipairs({ 0, 2147483647, 501, 101, 7 }) do
        local w = new_world({ start = 100 })
        w.click(landing)
        eq(w.focus_calls + w.move_calls, 0, "arrival at " .. landing)
        eq(w.active, landing, "it must not be pulled anywhere")
    end
end)

test("the column is recorded before leaving even if the arrival event was missed", function()
    local w = new_world({ start = 1, events = false })
    w.grid.go_col(1, false); w.grid.go_col(1, false)   -- column 2 (no events fired)
    w.grid.go_row(1, false)                 -- row 1 column 2
    w.grid.go_col(1, false)                 -- row 1 column 3
    w.grid.go_row(-1, false)                -- row 0: must come back to column 2
    eq(w.active, 3)
    w.grid.go_row(1, false)
    eq(w.active, 104, "row 1 must come back to column 3")
end)

test("go_row uses the vertical slide and puts the sideways slide back", function()
    local w = new_world({ start = 3 })
    w.grid.go_row(1, false)
    eq(w.style, "slidevert")
    w.advance(699)
    eq(w.style, "slidevert", "still playing")
    w.advance(1)
    eq(w.style, "slide", "restored once the animation has played")
end)

test("a sideways move straight after a vertical one cancels the pending restore", function()
    local w = new_world({ start = 3 })
    w.grid.go_row(1, false)
    w.advance(100)
    w.grid.go_col(1, false)                 -- sets "slide" now
    eq(w.style, "slide")
    local n = #w.styles
    w.advance(1000)
    eq(#w.styles, n, "the old restore must not fire a second time")
end)

test("two quick row moves: only the later restore acts (no cutting the second animation short)", function()
    local w = new_world({ start = 3 })
    w.grid.go_row(1, false)
    w.advance(400)
    w.grid.go_row(1, false)                 -- second animation starts at t=400
    w.advance(350)                          -- t=750: first restore (t=700) is past
    eq(w.style, "slidevert", "the first restore must not end the second animation")
    w.advance(350)                          -- t=1100: second restore (t=1100)
    eq(w.style, "slide")
end)

test("go_row with carry moves the window and follows it", function()
    local w = new_world({ start = 3 })
    w.grid.go_row(1, true)
    eq(w.window_on, 103); eq(w.active, 103)
    eq(w.move_calls, 1)
    w.grid.go_row(-1, true)
    eq(w.window_on, 3); eq(w.active, 3)
end)

test("carrying a window into a row you have visited lands on that row's column", function()
    local w = new_world({ start = 1 })
    w.grid.go_row(1, false); w.grid.go_col(1, false); w.grid.go_col(1, false)  -- row 1, column 2
    w.grid.go_row(-1, false)                -- back to row 0 column 0
    w.grid.go_row(1, true)                  -- carry down: lands on row 1's remembered column
    eq(w.active, 103)
    eq(w.window_on, 103)
end)

test("the grid has five rows", function()
    eq(Grid.ROWS, 5)
end)

test("going down stops at the fifth row and back up returns to the first", function()
    local w = new_world({ start = 5 })
    for _ = 1, 4 do eq(w.grid.go_row(1, false), true) end
    eq(w.active, at(4, 4), "row 5, same column")
    for _ = 1, 20 do w.grid.go_row(1, false) end
    eq(w.active, at(4, 4), "no sixth row")
    for _ = 1, 20 do w.grid.go_row(-1, false) end
    eq(w.active, 5, "back on the first row, same column")
end)

test("nothing below the fifth row: no move, no animation, no carry", function()
    local w = new_world({ start = at(4, 7) })
    local styles = #w.styles
    eq(w.grid.go_row(1, false), false)
    eq(w.grid.go_row(1, true), false)
    eq(w.active, at(4, 7)); eq(#w.styles, styles, "no animation change"); eq(w.move_calls, 0)
    eq(#w.timers, 0, "and no restore timers")
end)

test("the fifth row remembers its column like any other", function()
    local w = new_world({ start = 1 })
    for _ = 1, 4 do w.grid.go_row(1, false) end        -- row 5 (index 4), column 1
    w.grid.go_col(1, false); w.grid.go_col(1, false)   -- column 3
    w.grid.go_row(-1, false)
    w.grid.go_row(1, false)
    eq(w.active, at(4, 2))
end)

test("carrying a window down to the fifth row and no further", function()
    local w = new_world({ start = at(3, 2) })
    eq(w.grid.go_row(1, true), true)
    eq(w.window_on, at(4, 2))
    eq(w.grid.go_row(1, true), false)
    eq(w.window_on, at(4, 2), "the window stays put")
end)

---------------------------------------------------------------- goto_row (the overview)
test("goto_row jumps straight to a row, on the same column the first time", function()
    local w = new_world({ start = 4 })
    eq(w.grid.goto_row(3), true)
    eq(w.active, at(3, 3))
end)

test("goto_row returns to the column a row was left on", function()
    local w = new_world({ start = 1 })
    w.grid.go_row(1, false); w.grid.go_col(1, false); w.grid.go_col(1, false)   -- row 1, column 3
    w.grid.go_row(-1, false); w.grid.go_col(1, false)                           -- row 0, column 2
    eq(w.grid.goto_row(1), true); eq(w.active, at(1, 2))
    eq(w.grid.goto_row(0), true); eq(w.active, at(0, 1))
end)

test("goto_row skips rows in between and remembers where it left", function()
    local w = new_world({ start = 1 })
    w.grid.go_col(1, false)                    -- row 0, column 2
    w.grid.goto_row(4)                         -- row 4, column 2 (first visit)
    w.grid.go_col(1, false)                    -- row 4, column 3
    w.grid.goto_row(0)
    eq(w.active, at(0, 1))
    w.grid.goto_row(4)
    eq(w.active, at(4, 2))
end)

test("goto_row to the row you are on does nothing", function()
    local w = new_world({ start = 105 })
    eq(w.grid.goto_row(1), false)
    eq(w.focus_calls, 0); eq(#w.styles, 0)
end)

test("goto_row rejects anything that is not a row of the grid", function()
    local w = new_world({ start = 3 })
    for _, bad in ipairs({ -1, 5, 6, 1.5 }) do eq(w.grid.goto_row(bad), false, "row " .. tostring(bad)) end
    eq(w.grid.goto_row(nil), false); eq(w.grid.goto_row("2"), false)
    eq(w.active, 3)
end)

test("goto_row uses the vertical slide and then puts the sideways slide back", function()
    local w = new_world({ start = 3 })
    w.grid.goto_row(2)
    eq(w.style, "slidevert")
    w.advance(700)
    eq(w.style, "slide")
end)

test("goto_row from a scratchpad lands on that row's remembered column, else the first", function()
    local w = new_world({ start = 1 })
    w.grid.go_row(1, false); w.grid.go_col(1, false); w.grid.go_col(1, false)   -- row 1, column 3
    w.grid.go_row(-1, false)
    w.special = true
    w.grid.goto_row(1); eq(w.active, at(1, 2), "remembered column")
    local v = new_world({ start = 1 })
    v.special = true
    v.grid.goto_row(3); eq(v.active, at(3, 0), "first column of a new row")
end)

---------------------------------------------------------------- snapshot (for the overview)
test("snapshot lists each row's remembered workspace, empty for unvisited rows", function()
    local w = new_world({ start = 3 })
    eq(w.grid.snapshot(), "3,,,,")
    w.grid.go_row(1, false); w.grid.go_col(1, false)       -- row 1, column 4
    eq(w.grid.snapshot(), "3,104,,,")
    w.grid.goto_row(4)                                     -- row 4 opens on column 4
    eq(w.grid.snapshot(), "3,104,,,404")
end)

test("snapshot always has five entries", function()
    local w = new_world({ start = 250 })
    local _, commas = w.grid.snapshot():gsub(",", ",")
    eq(commas, 4)
end)

test("snapshot follows moves made outside the grid", function()
    local w = new_world({ start = 1 })
    w.click(307)
    eq(w.grid.snapshot(), "1,,,307,")
end)

test("a scratchpad does not change the snapshot", function()
    local w = new_world({ start = 105 })
    w.special = true; w.grid.arrived()
    eq(w.grid.snapshot(), ",105,,,")
end)

---------------------------------------------------------------- numbers
test("go_number picks column n of the current row", function()
    local w = new_world({ start = 1 })
    w.grid.go_number(7, false); eq(w.active, 7)
    w.grid.go_row(1, false)
    w.grid.go_number(3, false); eq(w.active, 103)
    w.grid.go_number(10, false); eq(w.active, 110)
end)

test("go_number to the column you are already on does nothing", function()
    local w = new_world({ start = 3 })
    eq(w.grid.go_number(3, false), false)
    eq(w.focus_calls, 0); eq(#w.styles, 0)
end)

test("go_number rejects values that are not a column", function()
    local w = new_world({ start = 3 })
    for _, bad in ipairs({ 0, -1, ROW + 1, 2.5 }) do
        eq(w.grid.go_number(bad, false), false, "n=" .. tostring(bad))
    end
    eq(w.grid.go_number(nil, false), false, "nil")
    eq(w.grid.go_number("4", false), false, "string")
    eq(w.active, 3)
end)

test("go_number carry sends the window to that column", function()
    local w = new_world({ start = 4 })
    w.grid.go_row(1, false)
    w.grid.go_number(9, true)
    eq(w.window_on, 109); eq(w.active, 109)
end)

test("go_number from a special workspace falls back to row 0", function()
    local w = new_world({ start = 250 })
    w.special = true
    w.grid.go_number(4, false)
    eq(w.active, 4)
end)

---------------------------------------------------------------- special workspaces
test("nothing moves while a special workspace (scratchpad) is active", function()
    local w = new_world({ start = 105 })
    w.special = true
    eq(w.grid.go_col(1, false), false)
    eq(w.grid.go_col(-1, true), false)
    eq(w.grid.go_row(1, false), false)
    eq(w.grid.go_row(-1, true), false)
    local t = w.grid.swipe_targets()
    eq(t.left + t.right + t.up + t.down, 0)
    eq(w.focus_calls + w.move_calls, 0)
    eq(w.active, 105, "the underlying workspace is untouched")
end)

test("a special workspace never overwrites a row's remembered column", function()
    local w = new_world({ start = 105 })    -- row 1, column 4
    eq(w.grid.remembered(1), 4)
    w.special = true
    w.grid.arrived()                        -- the event fires for the scratchpad too
    eq(w.grid.remembered(1), 4)
    eq(w.grid.remembered(-1), nil, "id -98 must not create a bogus row")
end)

---------------------------------------------------------------- workspaces that belong to another monitor
local function taken(set) return function(id) return not set[id] end end

test("stepping sideways skips workspaces the other monitor has", function()
    local w = new_world({ start = 5, usable = taken({ [6] = true, [7] = true }) })
    eq(w.grid.go_col(1, false), true); eq(w.active, 8, "6 and 7 are skipped")
    eq(w.grid.go_col(-1, false), true); eq(w.active, 5)
end)

test("no step at all when everything that way is taken", function()
    local set = {}
    for i = 6, 100 do set[i] = true end
    local w = new_world({ start = 5, usable = taken(set) })
    eq(w.grid.go_col(1, false), false); eq(w.active, 5)
    eq(w.grid.swipe_targets().right, 0)
end)

test("swipe targets skip taken workspaces too", function()
    local w = new_world({ start = 5, usable = taken({ [4] = true, [6] = true }) })
    local t = w.grid.swipe_targets()
    eq(t.left, 3); eq(t.right, 7)
end)

test("changing row lands on the nearest column that is free", function()
    local w = new_world({ start = 5, usable = taken({ [105] = true, [104] = true }) })   -- row 1, columns 5 and 4 taken
    eq(w.grid.go_row(1, false), true); eq(w.active, 106, "columns 5 and 4 are taken: the nearest free one is 6")
    eq(w.grid.swipe_targets().up, 5, "and back up to the column it left")
end)

test("a whole row taken: no way into it", function()
    local set = {}
    for i = 101, 200 do set[i] = true end
    local w = new_world({ start = 5, usable = taken(set) })
    eq(w.grid.go_row(1, false), false); eq(w.active, 5)
    eq(w.grid.swipe_targets().down, 0)
    eq(w.grid.goto_row(1), false)
end)

test("asking for a workspace by number still takes it", function()
    local w = new_world({ start = 5, usable = taken({ [7] = true }) })
    eq(w.grid.go_number(7, false), true); eq(w.active, 7)
end)

---------------------------------------------------------------- goto_row, carrying a window
test("goto_row with carry takes the window and lands on the row's remembered column", function()
    local w = new_world({ start = at(0, 2) })
    w.grid.goto_row(2)                       -- visit row 2 (column 2), then back
    w.grid.go_col(1, false)                  -- row 2, column 3
    w.grid.goto_row(0)
    local focus, move = w.focus_calls, w.move_calls
    eq(w.grid.goto_row(2, true), true)
    eq(w.active, at(2, 3))
    eq(w.move_calls, move + 1); eq(w.focus_calls, focus, "carried, not just focused")
end)

test("goto_row to the row you are on does nothing, carrying or not", function()
    local w = new_world({ start = at(1, 4) })
    eq(w.grid.goto_row(1, true), false)
    eq(w.move_calls, 0)
end)

test("goto_row refuses nonsense rows even when carrying", function()
    local w = new_world({ start = 3 })
    for _, bad in ipairs({ -1, 5, 2.5, "x" }) do eq(w.grid.goto_row(bad, true), false) end
    eq(w.move_calls + w.focus_calls, 0)
end)

---------------------------------------------------------------- swipe targets
test("a swipe's targets: neighbours in the row, other rows on the same column", function()
    local w = new_world({ start = 3 })
    local t = w.grid.swipe_targets()
    eq(t.left, 2); eq(t.right, 4); eq(t.up, 0, "no row above the first"); eq(t.down, 103)
end)

test("the row's ends have no sideways target", function()
    local w = new_world({ start = at(2, 0) })
    eq(w.grid.swipe_targets().left, 0)
    eq(w.grid.swipe_targets().right, at(2, 1))
    local w2 = new_world({ start = at(2, 99) })
    eq(w2.grid.swipe_targets().right, 0)
    eq(w2.grid.swipe_targets().left, at(2, 98))
end)

test("the last row has no target below", function()
    local w = new_world({ start = at(4, 7) })
    eq(w.grid.swipe_targets().down, 0)
    eq(w.grid.swipe_targets().up, at(3, 7))
end)

test("up and down land on the column each row was left on", function()
    local w = new_world({ start = at(1, 20) })
    w.grid.go_row(1, false)             -- row 2 at column 20
    w.grid.go_col(1, false)             -- column 21 in row 2
    local t = w.grid.swipe_targets()
    eq(t.up, at(1, 20), "row 1 remembered column 20")
    eq(t.down, at(3, 21), "unvisited row opens on the current column")
end)

test("lower targets are lower ids and higher targets higher (the compositor needs this)", function()
    for _, start in ipairs({ 1, 50, 100, 101, 250, 399, 500 }) do
        local w = new_world({ start = start })
        local t = w.grid.swipe_targets()
        for _, k in ipairs({ "left", "up" }) do assert(t[k] == 0 or t[k] < start, k .. " from " .. start) end
        for _, k in ipairs({ "right", "down" }) do assert(t[k] == 0 or t[k] > start, k .. " from " .. start) end
    end
end)

test("nothing to swipe to from a scratchpad", function()
    local w = new_world({ start = 105 })
    w.special = true
    local t = w.grid.swipe_targets()
    eq(t.left + t.right + t.up + t.down, 0)
end)

---------------------------------------------------------------- fuzz
-- Random sequences of every operation, checked against what the rules say must
-- happen. Deterministic (fixed seed) so a failure is reproducible.
local function fuzz(seed, steps, events)
    math.randomseed(seed)
    local w = new_world({ start = math.random(1, 350), events = events })
    local ref = {}                          -- row -> column last seen in it
    local last_vertical = -1e9
    local trace = {}

    local function observe()
        if not w.special then ref[Grid.row_of(w.active)] = Grid.col_of(w.active) end
    end
    observe()

    for step = 1, steps do
        local before, special = w.active, w.special
        local row, col = Grid.row_of(before), Grid.col_of(before)
        local op = math.random(1, 13)
        local expect = before
        local note

        if op <= 2 then
            local d = (math.random() < 0.5) and -1 or 1
            local carry = math.random() < 0.3
            note = ("go_col(%d,%s)"):format(d, tostring(carry))
            w.grid.go_col(d, carry)
            if not special and col + d >= 0 and col + d < ROW then expect = Grid.id_of(row, col + d) end
        elseif op <= 5 then
            local d = (math.random() < 0.5) and -1 or 1
            local carry = math.random() < 0.3
            note = ("go_row(%d,%s)"):format(d, tostring(carry))
            ref[row] = (not special) and col or ref[row]     -- recorded before leaving
            local moved = w.grid.go_row(d, carry)
            if not special and row + d >= 0 and row + d < Grid.ROWS then
                local landing = ref[row + d]
                if landing == nil then landing = col end
                expect = Grid.id_of(row + d, landing)
            end
            if moved then last_vertical = w.now end
        elseif op <= 7 then
            note = "swipe_targets"
            local t = w.grid.swipe_targets()
            for _, k in ipairs({ "left", "up" }) do assert(t[k] == 0 or (not special and t[k] < w.active), note) end
            for _, k in ipairs({ "right", "down" }) do assert(t[k] == 0 or (not special and t[k] > w.active), note) end
        elseif op == 8 then
            local n = math.random(-2, ROW + 3)
            local carry = math.random() < 0.3
            note = ("go_number(%d,%s)"):format(n, tostring(carry))
            w.grid.go_number(n, carry)
            if n >= 1 and n <= ROW then
                local base = special and 1 or before
                expect = Grid.id_of(Grid.row_of(base), n - 1)
            end
            if special and not (n >= 1 and n <= ROW) then expect = before end
        elseif op == 9 and events and not special then
            -- a swipe / click / `workspace N` that bypasses the grid
            local target = math.random(1, 450)
            note = ("click(%d)"):format(target)
            w.click(target)
            expect = target
        elseif op == 13 then
            local r = math.random(-1, Grid.ROWS + 1)
            note = ("goto_row(%d)"):format(r)
            ref[row] = (not special) and col or ref[row]
            local moved = w.grid.goto_row(r)
            if not special and r >= 0 and r < Grid.ROWS and r ~= row then
                local landing = ref[r]
                if landing == nil then landing = col end
                expect = Grid.id_of(r, landing)
            end
            if moved then last_vertical = w.now end
        elseif op == 10 and events then
            -- (Only with arrival events: with a scratchpad up the grid cannot see
            -- which numbered workspace is underneath, so without the event it has
            -- no way to learn what the workspace beneath was.)
            w.special = not w.special
            note = "toggle special -> " .. tostring(w.special)
            if events then w.grid.arrived() end
            expect = before
        else
            local ms = math.random(0, 900)
            note = ("advance(%d)"):format(ms)
            w.advance(ms)
            expect = before
        end

        trace[#trace + 1] = note
        if #trace > 8 then table.remove(trace, 1) end
        observe()

        local where = function() return ("seed %d step %d after %s (last 8: %s)"):format(seed, step, note, table.concat(trace, " | ")) end
        if w.special then
            -- no numbered workspace is active; the underlying one must be untouched
            if not special then eq(w.active, before, where() .. " special toggle changed the workspace") end
        else
            eq(w.active, expect, where() .. " active workspace")
        end
        if not w.special then
            assert(w.active >= 1, where() .. " went below workspace 1")
            if events then
                eq(w.grid.remembered(Grid.row_of(w.active)), Grid.col_of(w.active), where() .. " remembered column")
            end
        end
        if w.style == "slidevert" then
            assert(w.now - last_vertical < 700, where() .. " sideways slide never put back")
        end
    end

    -- left alone, the sideways slide always comes back
    w.advance(5000)
    eq(w.style, "slide", ("seed %d: style after settling"):format(seed))
    eq(#w.timers, 0, ("seed %d: timers left over"):format(seed))
end

test("fuzz: 8 seeds x 4000 random operations with arrival events", function()
    for seed = 1, 8 do fuzz(seed, 4000, true) end
end)

test("fuzz: 8 seeds x 4000 random operations when the arrival event is missed", function()
    for seed = 101, 108 do fuzz(seed, 4000, false) end
end)

---------------------------------------------------------------- report
local summary = { passed = passed, failed = failed, results = results }
if arg ~= nil and arg[0] ~= nil and arg[0]:match("grid_test%.lua$") then
    for _, f in ipairs(failures) do print(f) end
    print(("%d passed, %d failed"):format(passed, failed))
    os.exit(failed == 0 and 0 or 1)
end
return summary
