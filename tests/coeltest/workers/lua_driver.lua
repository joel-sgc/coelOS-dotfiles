-- Loads one Lua test file with dofile() and prints the table it returns as JSON.
--   lua lua_driver.lua <file.lua>
-- The test file returns { passed, failed, results = { {name, ok, error?}, ... } } and does not print or exit
-- when loaded this way. Last line: @@COELTEST@@{json}
local function esc(s)
    return (tostring(s):gsub('[%c"\\]', function(c)
        local m = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
        return m[c] or string.format("\\u%04x", c:byte())
    end))
end
local function enc(v)
    local t = type(v)
    if t == "table" then
        if #v > 0 or next(v) == nil then
            local out = {}
            for i, x in ipairs(v) do out[i] = enc(x) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        local out = {}
        for k, x in pairs(v) do out[#out + 1] = '"' .. esc(k) .. '":' .. enc(x) end
        return "{" .. table.concat(out, ",") .. "}"
    elseif t == "string" then return '"' .. esc(v) .. '"'
    elseif t == "number" or t == "boolean" then return tostring(v)
    end
    return "null"
end

local file = arg[1]
local ok, res = pcall(dofile, file)
if not ok then
    res = { results = { { name = "load", ok = false, error = tostring(res) } }, passed = 0, failed = 1 }
end
print("@@COELTEST@@" .. enc(res))
