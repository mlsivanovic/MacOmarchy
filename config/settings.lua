-- One source of truth for MacOmarchy runtime settings.
--
-- Defaults live beside this file in settings.default.json; the user file at
-- ~/.config/mac-omarchy/settings.json stores only changed values. Every module
-- reads through get(), so defaults, validation and live reload stay in one
-- place instead of being scattered as Lua constants.
--
-- Override loading is opt-in: init.lua calls configure({userPath = ...}) once.
-- Tests and plain Lua scripts therefore see defaults only, never the developer's
-- real settings file.
local S = {
    values = nil,
    defaults = nil,
    schema = nil,
    user = {},
    errors = {},
    listeners = {},
    userPath = nil,
}

local source = debug.getinfo(1, "S").source or ""
local dir = source:match("^@(.*)[/\\]") or "."
local json = dofile(dir .. "/json.lua")

S.defaultsPath = dir .. "/settings.default.json"
S.schemaPath = dir .. "/settings.schema.json"

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function readFile(path)
    if not path then return nil end
    local file = io.open(path, "r")
    if not file then return nil end
    local raw = file:read("*a")
    file:close()
    return raw
end

local function readJSON(path)
    local raw = readFile(path)
    if not raw then return nil, path .. ": file not found" end
    local ok, data = pcall(json.decode, raw)
    if not ok then return nil, path .. ": " .. tostring(data) end
    return data, nil
end

local arrayMt = getmetatable(json.array())

local function isArrayValue(value)
    if type(value) ~= "table" then return false end
    if getmetatable(value) == arrayMt then return true end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" then return false end
        count = count + 1
    end
    return count > 0 and count == #value
end
S.isArray = isArrayValue

-- Shortcut strings are canonical: modifiers in cmd+ctrl+alt+shift order and a
-- lowercase key name, for example "ctrl+alt+l". "none" disables a binding.
local SHORTCUT_MODIFIER_ORDER = {"cmd", "ctrl", "alt", "shift"}
local SHORTCUT_MODIFIER_ALIASES = {
    command = "cmd", cmd = "cmd",
    control = "ctrl", ctrl = "ctrl",
    option = "alt", opt = "alt", alt = "alt",
    shift = "shift",
}
local SHORTCUT_KEY_ALIASES = {
    enter = "return", ["return"] = "return",
    esc = "escape", escape = "escape",
    spacebar = "space", space = "space",
    del = "delete", delete = "delete",
    backspace = "backspace", tab = "tab",
    left = "left", right = "right", up = "up", down = "down",
    home = "home", ["end"] = "end",
    pageup = "pageup", pagedown = "pagedown",
    insert = "insert", help = "help",
}
for index = 1, 20 do SHORTCUT_KEY_ALIASES["f" .. index] = "f" .. index end

local function shortcutKey(value)
    local key = tostring(value or ""):lower()
    key = SHORTCUT_KEY_ALIASES[key] or key
    if #key == 1 then
        if key == "+" or key == " " then return nil end
        return key
    end
    return SHORTCUT_KEY_ALIASES[key]
end

function S.isShortcutDisabled(value)
    return type(value) == "string" and value:lower():gsub("%s+", "") == "none"
end

function S.parseShortcut(value)
    if type(value) ~= "string" then return nil end
    local raw = value:lower():gsub("%s+", "")
    if raw == "" or raw == "none" then return nil end
    local modifiers, key = {}, nil
    local seen = {}
    for part in raw:gmatch("[^+]+") do
        local modifier = SHORTCUT_MODIFIER_ALIASES[part]
        if modifier then
            if seen[modifier] then return nil end
            seen[modifier] = true
            modifiers[#modifiers + 1] = modifier
        else
            if key ~= nil then return nil end
            key = shortcutKey(part)
            if not key then return nil end
        end
    end
    if not key then return nil end
    if not seen.cmd and not seen.ctrl and not seen.alt and not key:match("^f%d+$") then return nil end
    local ordered = {}
    for _, modifier in ipairs(SHORTCUT_MODIFIER_ORDER) do
        if seen[modifier] then ordered[#ordered + 1] = modifier end
    end
    return ordered, key
end

function S.formatShortcut(modifiers, key)
    if type(modifiers) ~= "table" then return nil end
    local seen = {}
    for _, modifier in ipairs(modifiers) do
        local canonical = SHORTCUT_MODIFIER_ALIASES[tostring(modifier):lower()]
        if not canonical then return nil end
        seen[canonical] = true
    end
    local normalized = shortcutKey(key)
    if not normalized then return nil end
    if not seen.cmd and not seen.ctrl and not seen.alt and not normalized:match("^f%d+$") then return nil end
    local parts = {}
    for _, modifier in ipairs(SHORTCUT_MODIFIER_ORDER) do
        if seen[modifier] then parts[#parts + 1] = modifier end
    end
    parts[#parts + 1] = normalized
    return table.concat(parts, "+")
end

function S.shortcutLabel(value)
    if S.isShortcutDisabled(value) then return "None" end
    local modifiers, key = S.parseShortcut(value)
    if not modifiers then return "Invalid" end
    local modifierLabels = {cmd = "Cmd", ctrl = "Ctrl", alt = "Option", shift = "Shift"}
    local keyLabels = {
        space = "Space", ["return"] = "Return", escape = "Esc", tab = "Tab",
        backspace = "Backspace", delete = "Delete", home = "Home", ["end"] = "End",
        pageup = "Page Up", pagedown = "Page Down",
        left = "Left", right = "Right", up = "Up", down = "Down",
    }
    local parts = {}
    for _, modifier in ipairs(modifiers) do parts[#parts + 1] = modifierLabels[modifier] end
    parts[#parts + 1] = keyLabels[key] or key:upper()
    return table.concat(parts, " + ")
end

local function deepCopy(value)
    if value == json.null then return json.null end
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = deepCopy(item) end
    if getmetatable(value) == arrayMt then return setmetatable(out, arrayMt) end
    return out
end

local function deepMerge(base, overlay)
    if overlay == json.null then return json.null end
    if base == json.null then return deepCopy(overlay) end
    if type(base) ~= "table" or type(overlay) ~= "table" then
        return deepCopy(overlay)
    end
    if isArrayValue(base) or isArrayValue(overlay) then
        return deepCopy(overlay)
    end
    local out = deepCopy(base)
    for key, value in pairs(overlay) do
        out[key] = deepMerge(base[key], value)
    end
    return out
end
S.merge = deepMerge

local pathParts = {}
local function partsOf(path)
    if pathParts[path] then return pathParts[path] end
    local parts = {}
    for key in tostring(path):gmatch("[^%.]+") do parts[#parts + 1] = key end
    pathParts[path] = parts
    return parts
end

local function getPath(root, path)
    local node = root
    for _, key in ipairs(partsOf(path)) do
        if type(node) ~= "table" then return nil end
        node = node[key]
        if node == nil then return nil end
    end
    return node
end

local function setPath(root, path, value)
    local parts = partsOf(path)
    if #parts == 0 then return false end
    local node = root
    for i = 1, #parts - 1 do
        local key = parts[i]
        if type(node[key]) ~= "table" then node[key] = {} end
        node = node[key]
    end
    node[parts[#parts]] = value
    return true
end

local function unsetPath(node, parts, index)
    local key = parts[index]
    if index == #parts then
        node[key] = nil
        return next(node) == nil
    end
    if type(node[key]) ~= "table" then return false end
    local empty = unsetPath(node[key], parts, index + 1)
    if empty then node[key] = nil end
    return next(node) == nil
end

local function typeName(value)
    if value == nil then return "missing" end
    if value == json.null then return "null" end
    local kind = type(value)
    if kind == "table" then
        return isArrayValue(value) and "array" or "object"
    end
    return kind
end

local function matchesType(value, expected)
    if expected == "number" then
        return type(value) == "number" and value == value
    elseif expected == "integer" then
        return type(value) == "number" and value == value and value % 1 == 0
    elseif expected == "string" then
        return type(value) == "string"
    elseif expected == "boolean" then
        return type(value) == "boolean"
    elseif expected == "object" then
        return type(value) == "table" and not isArrayValue(value)
    elseif expected == "array" then
        return type(value) == "table" and (isArrayValue(value) or next(value) == nil)
    end
    return true
end

local function contains(list, wanted)
    for _, value in ipairs(list) do
        if value == wanted then return true end
    end
    return false
end

local function join(path, key)
    if path == "" or path == nil then return key end
    return path .. "." .. key
end

local function validateNode(value, schema, path, errors)
    if value == json.null then
        local label = (path == "" or path == nil) and "settings" or path
        errors[#errors + 1] = label .. ": null is not allowed"
        return
    end
    local expected = schema.type
    if expected and not matchesType(value, expected) then
        errors[#errors + 1] = string.format("%s: expected %s, got %s", path == "" and "settings" or path, expected, typeName(value))
        return
    end

    if expected == "object" then
        local properties = schema.properties or {}
        for _, key in ipairs(schema.required or {}) do
            if value[key] == nil then
                errors[#errors + 1] = join(path, key) .. ": required setting is missing"
            end
        end
        for key, subschema in pairs(properties) do
            if value[key] ~= nil then
                validateNode(value[key], subschema, join(path, key), errors)
            end
        end
        if schema.additionalProperties == false then
            for key in pairs(value) do
                if properties[key] == nil then
                    errors[#errors + 1] = join(path, key) .. ": unknown setting"
                end
            end
        end
    elseif expected == "array" then
        if schema.minItems and #value < schema.minItems then
            errors[#errors + 1] = string.format("%s: expected at least %d item(s)", path, schema.minItems)
        end
        if schema.maxItems and #value > schema.maxItems then
            errors[#errors + 1] = string.format("%s: expected at most %d item(s)", path, schema.maxItems)
        end
        if schema.uniqueItems then
            local seen = {}
            for _, item in ipairs(value) do
                if seen[item] then
                    errors[#errors + 1] = path .. ": duplicate item " .. tostring(item)
                    break
                end
                seen[item] = true
            end
        end
        if schema.items then
            for index, item in ipairs(value) do
                validateNode(item, schema.items, path .. "[" .. index .. "]", errors)
            end
        end
    else
        if schema.minimum and type(value) == "number" and value < schema.minimum then
            errors[#errors + 1] = string.format("%s: must be at least %s", path, tostring(schema.minimum))
        end
        if schema.maximum and type(value) == "number" and value > schema.maximum then
            errors[#errors + 1] = string.format("%s: must be at most %s", path, tostring(schema.maximum))
        end
        if schema.enum and not contains(schema.enum, value) then
            errors[#errors + 1] = path .. ": must be one of " .. table.concat(schema.enum, ", ")
        end
    end
end

local function crossField(config, errors)
    local tiler = config and config.tiler
    if type(tiler) ~= "table" then return end
    if type(tiler.ratioMin) == "number" and type(tiler.ratioMax) == "number"
        and tiler.ratioMin >= tiler.ratioMax then
        errors[#errors + 1] = "tiler.ratioMin: must be smaller than tiler.ratioMax"
    end
    if type(tiler.ratio) == "number" and type(tiler.ratioMin) == "number"
        and type(tiler.ratioMax) == "number"
        and (tiler.ratio < tiler.ratioMin or tiler.ratio > tiler.ratioMax) then
        errors[#errors + 1] = "tiler.ratio: must be between tiler.ratioMin and tiler.ratioMax"
    end
    if type(tiler.layout) == "string" and type(tiler.layouts) == "table"
        and not contains(tiler.layouts, tiler.layout) then
        errors[#errors + 1] = "tiler.layout: must be one of tiler.layouts"
    end
end

local function crossFieldShortcuts(config, errors)
    local shortcuts = config and config.shortcuts
    if type(shortcuts) ~= "table" then return end
    local seen = {}
    local ids = {}
    for id in pairs(shortcuts) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local value = shortcuts[id]
        if type(value) == "string" and not S.isShortcutDisabled(value) then
            local modifiers, key = S.parseShortcut(value)
            if not modifiers then
                errors[#errors + 1] = "shortcuts." .. id .. ": invalid shortcut (use modifiers+key or none)"
            else
                local canonical = S.formatShortcut(modifiers, key)
                if seen[canonical] then
                    errors[#errors + 1] = "shortcuts." .. id .. ": conflicts with shortcuts."
                        .. seen[canonical] .. " (" .. canonical .. ")"
                else
                    seen[canonical] = id
                end
            end
        end
    end
end

function S.validate(config, schema)
    schema = schema or S.schema
    if not schema then
        local loaded, err = readJSON(S.schemaPath)
        if not loaded then return false, {"settings: " .. (err or "schema unavailable")} end
        schema = loaded
    end
    local errors = {}
    validateNode(config, schema, "", errors)
    crossField(config, errors)
    crossFieldShortcuts(config, errors)
    return #errors == 0, errors
end

function S.defaultUserPath()
    local override = os.getenv("MACOMARCHY_SETTINGS")
    if override and override ~= "" then return override end
    local home = os.getenv("HOME")
    if not home or home == "" then return nil end
    return home .. "/.config/mac-omarchy/settings.json"
end

function S.load()
    local defaults, defaultsError = readJSON(S.defaultsPath)
    if not defaults then error("settings: " .. tostring(defaultsError), 0) end
    local schema, schemaError = readJSON(S.schemaPath)
    if not schema then error("settings: " .. tostring(schemaError), 0) end

    local defaultsOk, defaultErrors = S.validate(defaults, schema)
    if not defaultsOk then
        error("settings: invalid defaults: " .. table.concat(defaultErrors, "; "), 0)
    end

    local user, userErrors = {}, nil
    if S.userPath then
        local raw = readFile(S.userPath)
        if raw and raw:match("%S") then
            local ok, data = pcall(json.decode, raw)
            if not ok then
                userErrors = {"settings: " .. tostring(data)}
            elseif type(data) ~= "table" or isArrayValue(data) then
                userErrors = {"settings: the top-level value must be an object"}
            else
                user = data
            end
        end
    end

    if not userErrors then
        local merged = deepMerge(defaults, user)
        local ok, errors = S.validate(merged, schema)
        if ok then
            S.defaults, S.schema, S.user, S.values = defaults, schema, user, merged
            S.errors = {}
            return true
        end
        userErrors = errors
    end

    -- Keep the last known-good values; on the first load fall back to defaults.
    if not S.values then
        S.defaults, S.schema, S.user = defaults, schema, {}
        S.values = deepCopy(defaults)
    end
    S.errors = userErrors
    return false, userErrors
end

function S.configure(options)
    options = options or {}
    if options.defaultsPath then S.defaultsPath = options.defaultsPath end
    if options.schemaPath then S.schemaPath = options.schemaPath end
    if options.userPath ~= nil then S.userPath = options.userPath end
    return S.load()
end

function S.get(path, fallback)
    if S.values == nil then S.load() end
    if path == nil or path == "" then return S.values end
    local value = getPath(S.values, path)
    if value == nil then return fallback end
    return value
end

-- One notification policy for every module. Modules call this instead of
-- hs.alert.show so "Show notifications" and the duration apply everywhere.
function S.alert(message)
    if S.get("ui.alerts", true) == false then return end
    if hs and hs.alert and type(hs.alert.show) == "function" then
        local duration = S.get("ui.alertDuration", 2)
        pcall(hs.alert.show, tostring(message), duration)
    end
end

local function writeAtomic(path, text)
    local temporary = path .. ".tmp." .. tostring(os.time()) .. "." .. tostring(math.random(100000, 999999))
    local file, openError = io.open(temporary, "w")
    if not file then return false, tostring(openError) end
    local ok, writeError = pcall(function() file:write(text) end)
    file:close()
    if not ok then os.remove(temporary); return false, tostring(writeError) end
    local renamed, renameError = os.rename(temporary, path)
    if not renamed then os.remove(temporary); return false, tostring(renameError) end
    return true
end

function S.saveUser(user)
    if not S.userPath then return false, "settings: no user settings path" end
    local parent = S.userPath:match("^(.*)/")
    if parent and parent ~= "" then
        local ok = os.execute("mkdir -p " .. shellQuote(parent))
        if not ok then return false, "settings: cannot create " .. parent end
    end
    local text = json.encode(user, {indent = 2, sort = true}) .. "\n"
    local ok, err = writeAtomic(S.userPath, text)
    if not ok then return false, "settings: " .. tostring(err) end
    return true
end

function S.set(path, value)
    if S.values == nil then S.load() end
    if #S.errors > 0 then
        return false, {"settings: fix the invalid settings file before changing values"}
    end
    if type(path) ~= "string" or path == "" then return false, {"settings: a setting path is required"} end
    if value == nil then return false, {"settings: use unset to remove a value"} end
    if path:match("^shortcuts%.") and type(value) == "string" then
        if S.isShortcutDisabled(value) then
            value = "none"
        else
            local modifiers, key = S.parseShortcut(value)
            if modifiers then value = S.formatShortcut(modifiers, key) end
        end
    end

    local candidate = deepCopy(S.user)
    if not setPath(candidate, path, value) then
        return false, {"settings: empty setting path"}
    end
    local merged = deepMerge(S.defaults, candidate)
    local ok, errors = S.validate(merged, S.schema)
    if not ok then return false, errors end
    local saved, saveError = S.saveUser(candidate)
    if not saved then return false, {saveError} end

    S.user, S.values, S.errors = candidate, merged, {}
    S.notify()
    return true
end

function S.unset(path)
    if S.values == nil then S.load() end
    if #S.errors > 0 then
        return false, {"settings: fix the invalid settings file before changing values"}
    end
    local parts = partsOf(path)
    if #parts == 0 then return false, {"settings: a setting path is required"} end

    local candidate = deepCopy(S.user)
    unsetPath(candidate, parts, 1)
    local merged = deepMerge(S.defaults, candidate)
    local ok, errors = S.validate(merged, S.schema)
    if not ok then return false, errors end
    local saved, saveError = S.saveUser(candidate)
    if not saved then return false, {saveError} end

    S.user, S.values, S.errors = candidate, merged, {}
    S.notify()
    return true
end

function S.reset()
    if S.values == nil then S.load() end
    local ok, errors = S.validate(S.defaults, S.schema)
    if not ok then return false, errors end
    local saved, saveError = S.saveUser({})
    if not saved then return false, {saveError} end
    S.user, S.values, S.errors = {}, deepCopy(S.defaults), {}
    S.notify()
    return true
end

function S.reload()
    return S.load()
end

function S.onChange(listener)
    if type(listener) ~= "function" then return function() end end
    S.listeners[#S.listeners + 1] = listener
    return function()
        for index = #S.listeners, 1, -1 do
            if S.listeners[index] == listener then table.remove(S.listeners, index) end
        end
    end
end

function S.notify()
    local snapshot = {}
    for index, listener in ipairs(S.listeners) do snapshot[index] = listener end
    for _, listener in ipairs(snapshot) do
        pcall(listener, S.values, S)
    end
end

function S.encode(value)
    return json.encode(value)
end

function S.decode(text)
    return json.decode(text)
end

S.null = json.null
S.path = S.defaultsPath
S.dir = dir

return S
