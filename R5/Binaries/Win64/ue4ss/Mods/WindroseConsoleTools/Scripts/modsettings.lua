--[[
 Windrose Console Tools / modsettings.lua
 Optional R5ModSettings integration: lets any rf* console command be bound to a key via
 Settings > Mods. NOTHING is bound by default -- every entry starts as "None" in the panel, and
 stays console-only unless a key is actually picked. This file only handles the manifest write /
 saved-value read; main.lua is the one that actually calls RegisterKeyBind, once, at mod load.

 Entirely optional: every function here first checks whether the "R5ModSettings" UE4SS mod is
 actually installed (IsInstalled(), memoized) and no-ops harmlessly if not. Deliberately does NOT
 require("R5ModSettings") -- UE4SS mods aren't guaranteed to see each other's Scripts folder on
 the Lua path, and R5ModSettings' own example integration mod ships self-contained file I/O for
 that same reason. This only reads/writes the same plain Lua-table files (registrations/*.lua,
 saved/*.lua) R5ModSettings itself reads/writes -- same approach Living Base Enhanced's own
 modsettings.lua uses, duplicated here rather than shared since this mod is meant to be standalone.
]]

local M = {}

M.MOD_ID = "WindroseConsoleTools"
local RS_ROOTS = { "ue4ss/Mods/R5ModSettings/", "Mods/R5ModSettings/" }

-- Memoized: which relative root R5ModSettings actually lives at, or nil if it isn't installed.
local rsRootChecked, rsRoot = false, nil
function M.IsInstalled()
    if not rsRootChecked then
        rsRootChecked = true
        for _, root in ipairs(RS_ROOTS) do
            local f = io.open(root .. "enabled.txt", "r")
            if f then f:close(); rsRoot = root; break end
        end
    end
    return rsRoot
end

-- R5ModSettings' in-game keybind picker is the game's own native key-binding widget, so it reads
-- and saves standard Unreal FKey names -- a different naming convention from this UE4SS build's
-- own Key[] table. Translate both directions. Single letters (A-Z) and F1-F12 need no entry --
-- Epic's FKey name for those IS the bare name, which already matches Key[]/VK_FALLBACK too.
local LOCAL_TO_UE = {
    NUM_ONE = "NumPadOne", NUM_TWO = "NumPadTwo", NUM_THREE = "NumPadThree", NUM_FOUR = "NumPadFour",
    NUM_FIVE = "NumPadFive", NUM_SIX = "NumPadSix", NUM_SEVEN = "NumPadSeven", NUM_EIGHT = "NumPadEight",
    NUM_NINE = "NumPadNine", NUM_ZERO = "NumPadZero",
    NUM_ADD = "Add", NUM_SUBTRACT = "Subtract", NUM_MULTIPLY = "Multiply", NUM_DIVIDE = "Divide",
    NUM_DECIMAL = "Decimal",
    INS = "Insert", DEL = "Delete", PAGE_UP = "PageUp", PAGE_DOWN = "PageDown",
    OEM_COMMA = "Comma", OEM_PERIOD = "Period", OEM_FIVE = "Backslash",
    UP = "Up", DOWN = "Down", LEFT = "Left", RIGHT = "Right",
    HOME = "Home", END = "End", BACKSPACE = "BackSpace",
    DIGIT_0 = "Zero", DIGIT_1 = "One", DIGIT_2 = "Two", DIGIT_3 = "Three", DIGIT_4 = "Four",
    DIGIT_5 = "Five", DIGIT_6 = "Six", DIGIT_7 = "Seven", DIGIT_8 = "Eight", DIGIT_9 = "Nine",
    TAB = "Tab", ENTER = "Enter", ESCAPE = "Escape", SPACE = "SpaceBar",
    CAPS_LOCK = "CapsLock", NUM_LOCK = "NumLock", SCROLL_LOCK = "ScrollLock",
    PRINT_SCREEN = "PrintScreen", PAUSE = "Pause",
    LEFT_SHIFT = "LeftShift", RIGHT_SHIFT = "RightShift",
    LEFT_CONTROL = "LeftControl", RIGHT_CONTROL = "RightControl",
    LEFT_ALT = "LeftAlt", RIGHT_ALT = "RightAlt",
    OEM_SEMICOLON = "Semicolon", OEM_EQUALS = "Equals", OEM_MINUS = "Hyphen", OEM_SLASH = "Slash",
    OEM_TILDE = "Tilde", OEM_LEFT_BRACKET = "LeftBracket", OEM_RIGHT_BRACKET = "RightBracket",
    OEM_QUOTE = "Quote",
    MOUSE_LEFT = "LeftMouseButton", MOUSE_RIGHT = "RightMouseButton", MOUSE_MIDDLE = "MiddleMouseButton",
    MOUSE_THUMB1 = "ThumbMouseButton", MOUSE_THUMB2 = "ThumbMouseButton2",
}
local UE_TO_LOCAL = {}
for local_, ue in pairs(LOCAL_TO_UE) do UE_TO_LOCAL[ue] = local_ end

function M.ToUnreal(localName) return LOCAL_TO_UE[localName] or localName end
function M.ToLocal(ueName) return UE_TO_LOCAL[ueName] or ueName end

local function is_identifier(s)
    return type(s) == "string" and s:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

local function serialize(value, indent)
    indent = indent or "    "
    local vt = type(value)
    if vt == "number" or vt == "boolean" then return tostring(value) end
    if vt == "string" then return string.format("%q", value) end
    if vt ~= "table" then return "nil" end
    local parts = { "{\n" }
    -- Numeric keys sort numerically (preserves the settings array's intended display order);
    -- string keys sort alphabetically (just for deterministic, readable output).
    local numericKeys, stringKeys = {}, {}
    for k in pairs(value) do
        if type(k) == "number" then numericKeys[#numericKeys + 1] = k
        else stringKeys[#stringKeys + 1] = k end
    end
    table.sort(numericKeys, function(a, b) return a < b end)
    table.sort(stringKeys, function(a, b) return a < b end)
    local keys = numericKeys
    for _, k in ipairs(stringKeys) do keys[#keys + 1] = k end
    for _, k in ipairs(keys) do
        local kt = is_identifier(k) and k or ("[" .. serialize(k, indent .. "    ") .. "]")
        parts[#parts + 1] = indent .. kt .. " = " .. serialize(value[k], indent .. "    ") .. ",\n"
    end
    parts[#parts + 1] = indent:sub(1, math.max(#indent - 4, 0)) .. "}"
    return table.concat(parts)
end

function M.ReadSavedFile()
    local root = M.IsInstalled()
    if not root then return nil end
    local f = io.open(root .. "saved/" .. M.MOD_ID .. ".lua", "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    if not content or content == "" then return nil end
    if content:sub(1, 3) == "\239\187\191" then content = content:sub(4) end
    local loader = load(content)
    if not loader then return nil end
    local ok, data = pcall(loader)
    return (ok and type(data) == "table") and data or nil
end

-- Writes the Settings > Mods manifest -- one keybind row per def ({key, title, description}),
-- EVERY one defaulting to "None" (never a real key) since none of this mod's commands should be
-- bound without the player explicitly choosing to.
function M.WriteManifest(defs)
    local root = M.IsInstalled()
    if not root then return false end

    local settings = {}
    for _, def in ipairs(defs) do
        settings[#settings + 1] = {
            key = def.key, title = def.title, description = def.description, type = "keybind",
            default = { primary = "None", secondary = "None" },
        }
    end
    local manifest = {
        name = M.MOD_ID, display = "Windrose Console Tools", version = "1.1.0",
        settings = settings,
    }
    local body = "-- Generated by WindroseConsoleTools (modsettings.lua). Do not edit; regenerated on every mod load.\nreturn "
        .. serialize(manifest, "    ") .. "\n"

    local dir = root .. "registrations/"
    os.execute('mkdir "' .. dir:gsub("/", "\\") .. '" 2>nul')
    local path = dir .. M.MOD_ID .. ".lua"
    local existingF = io.open(path, "r")
    if existingF then
        local existingBody = existingF:read("*all")
        existingF:close()
        if existingBody == body then return true end
    end
    local f = io.open(path, "w")
    if not f then return false end
    f:write(body)
    f:close()
    return true
end

return M
