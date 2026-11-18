-- Tests for settings.lua:   lua home/hyprland/settings_test.lua
-- With COEL_TEST_JSON=<file.json> it also compares the parse of the real
-- settings.toml against Python's tomllib (see tests in coel_settings_test.py).
package.path = (arg and arg[0] and arg[0]:match("(.*/)") or "./") .. "?.lua;" .. package.path
local S = require("settings")

local passed, failed = 0, 0
local function eq(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not eq(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function test(name, got, want)
    if eq(got, want) then passed = passed + 1 else
        failed = failed + 1
        io.stderr:write("FAIL " .. name .. "\n")
    end
end

local t = S.parse([[
# comment
[display]
scale = 1.25   # trailing
name = "a # not a comment"

[monitors."desc:Dell Inc. DELL P2219H 74GVXS2"]
mode = "1920x1080@60.000"
position = '168x-1080'
disabled = false
margins = [8, 12, 12, 12]

[config.input.touchpad]
natural_scroll = true
"quoted key" = 3
]])
test("float", t.display.scale, 1.25)
test("hash in string", t.display.name, "a # not a comment")
test("quoted table w/ dots", t.monitors["desc:Dell Inc. DELL P2219H 74GVXS2"].mode, "1920x1080@60.000")
test("literal string", t.monitors["desc:Dell Inc. DELL P2219H 74GVXS2"].position, "168x-1080")
test("bool", t.monitors["desc:Dell Inc. DELL P2219H 74GVXS2"].disabled, false)
test("array", t.monitors["desc:Dell Inc. DELL P2219H 74GVXS2"].margins, { 8, 12, 12, 12 })
test("nested", t.config.input.touchpad.natural_scroll, true)
test("quoted key", t.config.input.touchpad["quoted key"], 3)
test("get default", S.get(t, "display.nope", 7), 7)
test("get dotted", S.get(t, "display.scale"), 1.25)
test("get quoted", S.get(t, 'monitors."desc:Dell Inc. DELL P2219H 74GVXS2".mode'), "1920x1080@60.000")
test("escapes", S.parse('a = "x\\"y\\\\z"').a, 'x"y\\z')
test("multiline array is rejected, not mis-parsed", select(2, S.parse("a = [1,\n 2,\n 3]\n")) ~= nil, true)
local _, err = S.parse("a = oops")
test("bad value reports", err ~= nil, true)
test("missing file", select(2, S.load("/nonexistent/x.toml")) ~= nil, true)
test("missing file is usable", S.load("/nonexistent/x.toml"), {})

if os.getenv("COEL_TEST_JSON") then
    local json = io.open(os.getenv("COEL_TEST_JSON")):read("a")
    -- tiny JSON reader sufficient for the settings tree
    local pos = 1
    local function ws() pos = json:find("%S", pos) or #json + 1 end
    local val
    local function str()
        local s = pos + 1
        local out = {}
        while true do
            local c = json:sub(s, s)
            if c == "\\" then
                local n = json:sub(s + 1, s + 1)
                local map = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
                out[#out + 1] = map[n]; s = s + 2
            elseif c == '"' then pos = s + 1; return table.concat(out)
            else out[#out + 1] = c; s = s + 1 end
        end
    end
    val = function()
        ws()
        local c = json:sub(pos, pos)
        if c == "{" then
            pos = pos + 1; local o = {}
            ws()
            if json:sub(pos, pos) == "}" then pos = pos + 1; return o end
            while true do
                ws(); local k = str(); ws(); pos = pos + 1
                o[k] = val(); ws()
                local d = json:sub(pos, pos); pos = pos + 1
                if d == "}" then return o end
            end
        elseif c == "[" then
            pos = pos + 1; local a = {}
            ws()
            if json:sub(pos, pos) == "]" then pos = pos + 1; return a end
            while true do
                a[#a + 1] = val(); ws()
                local d = json:sub(pos, pos); pos = pos + 1
                if d == "]" then return a end
            end
        elseif c == '"' then return str()
        else
            local tok = json:match("^[^,%]}%s]+", pos); pos = pos + #tok
            if tok == "true" then return true elseif tok == "false" then return false end
            return tonumber(tok)
        end
    end
    local want = val()
    local got, err2 = S.load(os.getenv("COEL_TEST_FILE"))
    test("real file agrees with tomllib" .. (err2 and (": " .. err2) or ""), got, want)
end

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
