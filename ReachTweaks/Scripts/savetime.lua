-- Save time in the save slot list: the menu shows the date of each save
-- point but not the time; the time is appended to the date text.
--
-- The slots are Blueprint widgets derived from the native UAtlasSaveSlotWidget
-- (/Script/Atlas, property SaveSlotIndex); in game (2026-10-11) the main menu
-- uses /Game/AtlasProto/Art/UI/FrontendMenu/WBP_Frontend_SaveGameSlot
-- (texts: checkpoint name, date as "10 oct. 2026", slot number). The
-- Blueprint receives an FSaveDisplayInfo (CheckpointName, WorldName,
-- Timestamp) through the interface event SetWidgetSaveDisplayInfo and
-- writes the texts itself.
--
-- Time source: the save file of the slot. UAtlasSaveSubsystem::IterateSaveFiles
-- builds "<ProjectSavedDir>/SaveGames/" + Format("{0}{1}", AutoSaveName, slot)
-- + ".sav" (AutoSaveName = "AtlasAutoSave"), and UAtlasSaveGame::CreateSnapshot
-- stores FDateTime::Now() (local time) in its Timestamp property, which is
-- serialized near the start of the file (~1.7 KB in).
--
-- Finding the widgets: FindAllOf only returns an exact class, and the
-- Blueprint class name is not known in advance. Hooks on the native functions
-- the slot / page Blueprints call (GetLevelDisplayName, GetButtonVisibility,
-- ...) tell that the save list is in use and which class the slots have; the
-- slots are then scanned for a few seconds. If no hook can be registered, a
-- slow scan with FindObjects (any subclass) is the fallback.
--
-- In each slot the text block whose text contains the save's year and day
-- (and no time yet) gets " HH:MM". No UObject is kept across ticks: text
-- blocks are remembered by path (StaticFindObject) to restore them on F7 OFF.
local Util = require("util")

local SaveTime = {}

local SLOT_CLASS = "/Script/Atlas.AtlasSaveSlotWidget"
local PAGE_CLASS = "/Script/Atlas.AtlasSaveGamePageWidget"
local SAVE_PREFIX = "AtlasAutoSave"
local TICKS_PER_SECOND = 10000000
local UNIX_EPOCH_SECONDS = 62135596800   -- 0001-01-01 -> 1970-01-01
local RF_CDO_OR_ARCHETYPE = 0x30         -- RF_ClassDefaultObject | RF_ArchetypeObject

local ACTIVE_MS = 3000       -- scan this long after a hook fired
local ACTIVE_SCAN_MS = 250
local IDLE_SCAN_MS = 3000    -- fallback scan while no hook has fired yet
local FILE_CACHE_MS = 2000

local cfg
local nowMs = 0
local signalAt = nil         -- last time a hook said the save list is in use
local hooksSeen = false
local hooksRegistered = false  -- at least one hook is in place
local learnedKeys = {}       -- widget key -> true (class already learnt)
local lastScan = -1e9
local slotClasses = {}       -- short class name -> true
local pendingClasses = {}    -- short class name -> class path (hook the BP event)
local eventHooked = {}       -- class path -> true
local fileCache = {}         -- slot -> { at, info }
local changed = {}           -- text block path -> { orig, new }
local lastSeen = {}          -- slot -> last texts logged (debug)

local function saveDir()
    local base = os.getenv("LOCALAPPDATA")
    if not base or base == "" then return nil end
    return base .. "\\Atlas\\Saved\\SaveGames\\"
end

-- Plausible FDateTime ticks: years 2000-2200
local MIN_TICKS = 630822816000000000
local MAX_TICKS = 693937152000000000

local function plausible(t) return t ~= nil and t >= MIN_TICKS and t <= MAX_TICKS end

-- Reads the Timestamp ticks of a save file (nil if there is no save)
local function readTicks(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local head = f:read(16384)
    f:close()
    if not head then return nil end
    local i = head:find("Timestamp\0", 1, true)
    if not i then return nil end
    -- UE 5.4 tag: ... "DateTime" ... "/Script/CoreUObject\0", 4 bytes, int32 size (8), flags byte, value
    local j = head:find("/Script/CoreUObject\0", i, true)
    if j and j < i + 200 then
        local p = j + #"/Script/CoreUObject\0" + 9
        if p + 7 <= #head then
            local t = string.unpack("<i8", head, p)
            if plausible(t) then return t end
        end
    end
    -- Other tag layouts: first plausible value after the name
    for p = i, math.min(i + 200, #head - 7) do
        local t = string.unpack("<i8", head, p)
        if plausible(t) then return t end
    end
    return nil
end

local function slotInfo(slot)
    local c = fileCache[slot]
    if c and nowMs - c.at < FILE_CACHE_MS then return c.info end
    local info = nil
    local dir = saveDir()
    local ticks = dir and readTicks(dir .. SAVE_PREFIX .. tostring(slot) .. ".sav")
    if ticks then
        local secs = ticks // TICKS_PER_SECOND - UNIX_EPOCH_SECONDS
        -- The ticks are already local time: "!" formats them without conversion
        local d = os.date("!*t", secs)
        info = { secs = secs, year = d.year, day = d.day }
    end
    fileCache[slot] = { at = nowMs, info = info }
    return info
end

local function timeText(info)
    local ok, s = pcall(os.date, "!" .. (cfg.Format or "%H:%M"), info.secs)
    if ok and type(s) == "string" then return s end
    return os.date("!%H:%M", info.secs)
end

local function textOf(tb)
    local ok, s = pcall(function() return tb:GetText():ToString() end)
    if ok and type(s) == "string" then return s end
    return nil
end

local function setText(tb, s)
    return pcall(function() tb:SetText(FText(s)) end)
end

local function pathOf(obj)
    local ok, full = pcall(function() return obj:GetFullName() end)
    if not ok or not full then return nil end
    return (full:gsub("^%S+%s+", ""))   -- strip the class prefix
end

local function shortClassName(obj)
    local ok, n = pcall(function() return obj:GetClass():GetFName():ToString() end)
    if ok and type(n) == "string" then return n end
    return nil
end

-- Class defaults and the templates inside Blueprint classes are not shown
local function isLiveInstance(w)
    local ok, flagged = pcall(function() return w:HasAnyFlags(RF_CDO_OR_ARCHETYPE) end)
    if ok and flagged then return false end
    local p = pathOf(w)
    if not p then return false end
    return not p:find("Default__", 1, true) and not p:find("_C:WidgetTree", 1, true)
end

-- Text blocks inside a widget (nested user widgets included)
local function collectTexts(widget, out, depth)
    if not Util.IsValid(widget) or depth > 16 or #out > 200 then return end
    if Util.IsA(widget, "/Script/UMG.TextBlock") or Util.IsA(widget, "/Script/UMG.RichTextBlock") then
        out[#out + 1] = widget
        return
    end
    if Util.IsA(widget, "/Script/UMG.UserWidget") then
        local ok, root = pcall(function() return widget.WidgetTree.RootWidget end)
        if ok then collectTexts(root, out, depth + 1) end
        return
    end
    if Util.IsA(widget, "/Script/UMG.PanelWidget") then
        local ok, n = pcall(function() return widget:GetChildrenCount() end)
        if ok and type(n) == "number" then
            for i = 0, n - 1 do
                local okc, child = pcall(function() return widget:GetChildAt(i) end)
                if okc then collectTexts(child, out, depth + 1) end
            end
        end
    end
end

-- Year (4 or 2 digits) and day of the save as separate numbers, no time yet
local function isDateText(s, info)
    if s == nil or s == "" or s:find("%d:%d%d") then return false end
    local y4 = tostring(info.year)
    local y2 = string.format("%02d", info.year % 100)
    local hasYear = s:find("%f[%d]" .. y4 .. "%f[%D]") ~= nil or s:find("%f[%d]" .. y2 .. "%f[%D]") ~= nil
    if not hasYear then return false end
    local d1, d2 = tostring(info.day), string.format("%02d", info.day)
    return s:find("%f[%d]" .. d1 .. "%f[%D]") ~= nil or s:find("%f[%d]" .. d2 .. "%f[%D]") ~= nil
end

local function slotIndex(w)
    local ok, v = pcall(function() return w.SaveSlotIndex end)
    if ok and type(v) == "number" then return v end
    ok, v = pcall(function() return w:GetSaveSlotIndex() end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function updateSlot(w)
    local slot = slotIndex(w)
    if slot == nil or slot < 0 then return end
    local info = slotInfo(slot)
    if not info then return end
    local root = nil
    pcall(function() root = w.WidgetTree.RootWidget end)
    local texts = {}
    collectTexts(root, texts, 0)
    local time = timeText(info)
    local sep = cfg.Separator or " "
    local seen, done = {}, false
    for _, tb in ipairs(texts) do
        local cur = textOf(tb)
        local path = pathOf(tb)
        seen[#seen + 1] = cur or "?"
        if cur and path and not done then
            local mine = changed[path]
            if mine and cur == mine.new then
                -- Ours; refresh it if the format or the save changed
                local want = mine.orig .. sep .. time
                if want ~= mine.new and setText(tb, want) then mine.new = want end
                done = true
            elseif isDateText(cur, info) then
                local want = cur .. sep .. time
                if setText(tb, want) then
                    if mine then Util.DLog("[savetime] slot %d: the game rewrote the date text", slot) end
                    changed[path] = { orig = cur, new = want }
                    Util.DLog("[savetime] slot %d: '%s' -> '%s'", slot, cur, want)
                end
                done = true
            end
        end
    end
    if Util.Debug then
        local all = table.concat(seen, " | ")
        if lastSeen[slot] ~= all and not done then
            Util.Log("[savetime] slot %d (%s): no date text found; texts: %s", slot,
                os.date("!%Y-%m-%d %H:%M", info.secs), all)
        end
        lastSeen[slot] = all
    end
end

local function learnClass(w, how)
    local name = shortClassName(w)
    if not name or slotClasses[name] then return end
    slotClasses[name] = true
    local okc, cls = pcall(function() return w:GetClass() end)
    local path = okc and pathOf(cls) or nil
    if path then pendingClasses[name] = path end
    Util.Log("[savetime] save slot class: %s (%s)", name, how)
end

local function findSlots()
    local out = {}
    if next(slotClasses) == nil then
        -- Any subclass of the native slot widget (slow: whole object list)
        local cls = Util.Class(SLOT_CLASS)
        if cls == nil then return out end
        local ok, list = pcall(function() return FindObjects(64, cls, 0, RF_CDO_OR_ARCHETYPE, false) end)
        if ok and type(list) == "table" then
            for _, w in ipairs(list) do
                if Util.IsValid(w) and isLiveInstance(w) then
                    learnClass(w, "object search")
                    out[#out + 1] = w
                end
            end
        end
        return out
    end
    for name in pairs(slotClasses) do
        for _, w in ipairs(FindAllOf(name) or {}) do
            if Util.IsValid(w) and isLiveInstance(w) then out[#out + 1] = w end
        end
    end
    return out
end

-- The Blueprint event that fills a slot: one more signal, exactly when the
-- texts are written
local function hookPendingEvents()
    for name, path in pairs(pendingClasses) do
        pendingClasses[name] = nil
        local fn = path .. ":SetWidgetSaveDisplayInfo"
        if not eventHooked[fn] and Util.IsValid(StaticFindObject(fn)) then
            eventHooked[fn] = true
            local ok, err = pcall(function()
                RegisterHook(fn, function() signalAt = nowMs end)
            end)
            Util.DLog("[savetime] hook %s: %s", fn, ok and "OK" or tostring(err))
        end
    end
end

function SaveTime.Tick(dtMs)
    nowMs = nowMs + dtMs
    hookPendingEvents()
    local active = signalAt ~= nil and nowMs - signalAt < ACTIVE_MS
    -- List closed: widgets are destroyed and their addresses may be reused
    if not active and next(learnedKeys) ~= nil then learnedKeys = {} end
    -- The slow fallback scan (whole object list) only runs when no hook could
    -- be registered: a registered hook fires as soon as the save list is used.
    -- (Written as "x and nil or IDLE_SCAN_MS" before, which is always
    -- IDLE_SCAN_MS in Lua: the scan ran every 3 s for the whole session.)
    local interval
    if active then
        interval = ACTIVE_SCAN_MS
    elseif not hooksSeen and not hooksRegistered then
        interval = IDLE_SCAN_MS
    end
    if interval == nil or nowMs - lastScan < interval then return end
    lastScan = nowMs
    for _, w in ipairs(findSlots()) do Util.SafeCall(updateSlot, w) end
end

-- F7 OFF: give the texts back their original value
function SaveTime.Stop()
    for path, c in pairs(changed) do
        local tb = StaticFindObject(path)
        if Util.IsValid(tb) and textOf(tb) == c.new then setText(tb, c.orig) end
    end
    changed = {}
    fileCache = {}
end

function SaveTime.Init(config)
    cfg = config
    -- Native functions called by the slot / page Blueprints (game thread)
    local slotFns = { "GetLevelDisplayName", "GetButtonVisibility", "GetSaveSlotIndex" }
    for _, fn in ipairs(slotFns) do
        local path = SLOT_CLASS .. ":" .. fn
        local ok, err = pcall(function()
            RegisterHook(path, function(self)
                signalAt = nowMs
                if not hooksSeen then
                    hooksSeen = true
                    Util.DLog("[savetime] save list in use (%s)", fn)
                end
                -- Called every frame per slot while the list is shown: the
                -- class is only looked at once per widget
                local okw, w = pcall(function() return self:get() end)
                if okw and Util.IsValid(w) then
                    local k = Util.Key(w)
                    if not learnedKeys[k] then
                        learnedKeys[k] = true
                        learnClass(w, fn)
                    end
                end
            end)
        end)
        if ok then hooksRegistered = true end
        Util.DLog("[savetime] hook %s: %s", path, ok and "OK" or tostring(err))
    end
    -- (UAtlasSaveSubsystem:GetSaveSlotDisplayInfos is not found by RegisterHook)
    local otherFns = { PAGE_CLASS .. ":PopulateSaveSlotWidgetArray", PAGE_CLASS .. ":GetWidgetForSaveSlot" }
    for _, path in ipairs(otherFns) do
        local ok, err = pcall(function()
            RegisterHook(path, function()
                signalAt = nowMs
                if not hooksSeen then
                    hooksSeen = true
                    Util.DLog("[savetime] save list in use (%s)", path)
                end
            end)
        end)
        if ok then hooksRegistered = true end
        Util.DLog("[savetime] hook %s: %s", path, ok and "OK" or tostring(err))
    end
end

return SaveTime
