-- Loader for settings.toml (the runtime-editable settings file; see the header
-- of that file). A small TOML *subset* parser, so Hyprland needs no external
-- tool at config time:
--
--   [table]  [a.b]  [a."quoted.key"]     tables (dotted, quoted parts allowed)
--   key = "string" | 'literal' | 123 | 1.5 | true | false | [1, "a", ...]
--   # comments
--
-- No inline tables, multi-line strings/arrays or dates. The CLI side
-- (coel-settings) uses Python's full tomllib, and settings_test.lua checks both
-- agree on the real file.
--
-- load() never raises: a missing or broken file gives {} plus an error string,
-- so a typo in settings.toml can't take the session's config down with it.

local M = {}

local function parse_string(s, i)
    local q = s:sub(i, i)
    local j, out = i + 1, {}
    if q == "'" then
        local e = s:find("'", j, true)
        if not e then return nil, "unterminated string" end
        return s:sub(j, e - 1), e + 1
    end
    local esc = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\" }
    while j <= #s do
        local c = s:sub(j, j)
        if c == "\\" then
            local n = s:sub(j + 1, j + 1)
            if not esc[n] then return nil, "bad escape \\" .. n end
            out[#out + 1] = esc[n]
            j = j + 2
        elseif c == '"' then
            return table.concat(out), j + 1
        else
            out[#out + 1] = c
            j = j + 1
        end
    end
    return nil, "unterminated string"
end

local parse_value

local function parse_array(s, i)
    local arr, j = {}, i + 1
    while true do
        j = s:find("%S", j)
        if not j then return nil, "unterminated array" end
        local c = s:sub(j, j)
        if c == "]" then return arr, j + 1 end
        if c == "," then
            j = j + 1
        elseif c == "#" then
            j = (s:find("\n", j, true) or #s) + 1
        else
            local v, nj = parse_value(s, j)
            if nj == nil then return nil, v end
            arr[#arr + 1] = v
            j = nj
        end
    end
end

-- Returns value, next index; or errmsg, nil.
parse_value = function(s, i)
    local c = s:sub(i, i)
    if c == '"' or c == "'" then
        local v, j = parse_string(s, i)
        if type(j) ~= "number" then return j, nil end
        return v, j
    elseif c == "[" then
        local v, j = parse_array(s, i)
        if type(j) ~= "number" then return j, nil end
        return v, j
    end
    local tok = s:match("^[^%s,%]#]+", i)
    if not tok then return "missing value", nil end
    if tok == "true" then return true, i + #tok end
    if tok == "false" then return false, i + #tok end
    local n = tonumber((tok:gsub("_", "")))
    if n and tok:match("^[+-]?%d") then return n, i + #tok end
    return "bad value '" .. tok .. "'", nil
end

-- Splits `a.b."c.d"` into {"a","b","c.d"}.
local function split_path(p)
    local parts, i = {}, 1
    while i <= #p do
        local c = p:sub(i, i)
        if c:match("%s") then
            i = i + 1
        elseif c == '"' or c == "'" then
            local v, j = parse_string(p, i)
            if type(j) ~= "number" then return nil, j end
            parts[#parts + 1] = v
            i = j
        elseif c == "." then
            i = i + 1
        else
            local tok = p:match("^[%w_%-]+", i)
            if not tok then return nil, "bad key '" .. p .. "'" end
            parts[#parts + 1] = tok
            i = i + #tok
        end
    end
    return parts
end
M.split_path = split_path

function M.parse(text)
    local root, cur = {}, nil
    cur = root
    local lineno = 0
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        lineno = lineno + 1
        local function fail(msg) return nil, ("line %d: %s"):format(lineno, msg) end
        local s = line:match("^%s*(.-)%s*$")
        if s ~= "" and s:sub(1, 1) ~= "#" then
            local header = s:match("^%[([^%[].-)%]%s*#?.*$")
            if header and s:sub(1, 1) == "[" then
                local parts, err = split_path(header)
                if not parts then return fail(err) end
                cur = root
                for _, k in ipairs(parts) do
                    if cur[k] == nil then cur[k] = {} end
                    if type(cur[k]) ~= "table" then return fail("'" .. k .. "' is not a table") end
                    cur = cur[k]
                end
            else
                local key, rest
                if s:match("^[\"']") then
                    local k, j = parse_string(s, 1)
                    if type(j) ~= "number" then return fail(j) end
                    key, rest = k, s:sub(j)
                else
                    key, rest = s:match("^([%w_%-]+)%s*(=.*)$")
                end
                local val_text = rest and rest:match("^%s*=%s*(.*)$")
                if not key or not val_text then return fail("expected key = value") end
                if val_text == "" or val_text:sub(1, 1) == "#" then return fail("missing value") end
                local v, j = parse_value(val_text, 1)
                if j == nil then return fail(v) end
                rest = val_text
                local tail = rest:sub(j):match("^%s*(.-)%s*$")
                if tail ~= "" and tail:sub(1, 1) ~= "#" then return fail("junk after value: " .. tail) end
                cur[key] = v
            end
        end
    end
    return root
end

local function expand(path)
    return (path:gsub("^~", os.getenv("HOME") or "~"))
end

M.default_path = function()
    return expand(os.getenv("COEL_SETTINGS") or "~/.nixos/settings.toml")
end

-- -> table, err   (table is always usable)
function M.load(path)
    path = path or M.default_path()
    local f = io.open(path, "r")
    if not f then return {}, "cannot open " .. path end
    local text = f:read("a")
    f:close()
    local ok, t, err = pcall(M.parse, text)
    if not ok then return {}, tostring(t) end
    if not t then return {}, path .. ": " .. tostring(err) end
    return t
end

-- Dotted lookup with a default: get(t, "display.scale", 1).
function M.get(t, path, default)
    local cur = t
    for _, k in ipairs(split_path(path) or {}) do
        if type(cur) ~= "table" then return default end
        cur = cur[k]
    end
    if cur == nil then return default end
    return cur
end

return M
