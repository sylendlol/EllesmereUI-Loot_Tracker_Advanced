if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUILootTracker.lua
--  Loot Tracker (Dworak > Loot Tracker): a loot feed with auction prices,
--  a farming session tracker and a loot history, as a standalone addon so an
--  EllesmereUI update never overwrites it. No EllesmereUI file is changed.
--
--  This file: the settings store, the feature kit (settings + login boot +
--  Unlock Mode element) and the one-time import from the old Forever
--  Essentials Loot Feed.
--
--  Files:
--    EllesmereUILootTracker.lua          this file
--    EllesmereUILootTracker_Core.lua     feed, farming session, loot history,
--                                        ignored items, minimap icon
--    EllesmereUILootTracker_Options.lua  Dworak > Loot Tracker pages
--
--  Settings are account-wide in EllesmereUILootTrackerDB:
--    .feed     Loot Feed settings (+ pos)
--    .session  Farming Session / Loot History settings and data (session
--              numbers, history list, price choices, window spots)
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

ns.FOLDER = ADDON_NAME                 -- "EllesmereUILootTracker"
ns.UNLOCK_GROUP = "Dworak"             -- group in EllesmereUI Unlock Mode

-- Public handle (the options file and slash commands use it).
EllesmereUILootTracker = EllesmereUILootTracker or {}
ns.API = EllesmereUILootTracker

local SV_NAME = "EllesmereUILootTrackerDB"

-- Chat line in the suite's style.
function ns.Print(msg)
    local brand = (EllesmereUI.COLOR_CODES and EllesmereUI.COLOR_CODES.BRAND) or "|cff0cd29d"
    EllesmereUI.Print(brand .. "Loot Tracker:|r " .. msg)
end

local function Root(create)
    local root = _G[SV_NAME]
    if type(root) ~= "table" then
        if not create then return nil end
        root = {}
        _G[SV_NAME] = root
    end
    return root
end

local function IsUnlocked()
    return EllesmereUI.IsUnlockModeActive and EllesmereUI.IsUnlockModeActive() or false
end
ns.IsUnlocked = IsUnlocked

-------------------------------------------------------------------------------
--  Feature kit: settings and the login boot for a feature, plus placement and
--  the Unlock Mode element for the ones drawn on one frame of ours.
--  Read() never creates the table, so a feature nobody touches saves nothing;
--  Cfg() is the write accessor and Get() falls back to defaults. pos (point,
--  relPoint, x, y) is where Unlock Mode put the frame; defaultPos until then.
-------------------------------------------------------------------------------
function ns.Feature(dbKey, defaults, defaultPos)
    local F, none = {}, {}
    local function Read()
        local root = Root(false)
        return root and root[dbKey] or none
    end
    local function Cfg()
        local root = Root(true)
        local c = root[dbKey]
        if not c then
            c = {}
            root[dbKey] = c
        end
        return c
    end
    local function Get(key)
        local v = Read()[key]
        if v == nil then return defaults[key] end
        return v
    end
    local function Enabled()
        return Get("enabled") == true
    end
    local function SavedPos()
        local pos = Read().pos
        return pos and pos.point and pos or defaultPos
    end
    local function Place(frame)
        if not frame then return end
        local pos = SavedPos()
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    end
    F.Read, F.Cfg, F.Get, F.Enabled, F.Place = Read, Cfg, Get, Enabled, Place

    -- At login: apply(), then the Unlock Mode element when the feature has a
    -- frame. Its height follows its settings, so Unlock Mode sizes the width.
    --   u.key, u.label, u.order, u.minWidth
    --   u.frame(build)   the frame (nil until built); build builds it first
    --   u.height()       the frame's height
    --   u.applyStyle()   lays the frame out again after a width change
    function F.Start(apply, u)
        local boot = CreateFrame("Frame")
        boot:RegisterEvent("PLAYER_LOGIN")
        boot:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            apply()
            if not (u and EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
            EllesmereUI:RegisterUnlockElements({
                EllesmereUI.MakeUnlockElement({
                    key      = u.key,
                    label    = u.label,
                    group    = ns.UNLOCK_GROUP,
                    order    = u.order,
                    isHidden = function() return not Enabled() end,
                    getFrame = function()
                        return Enabled() and u.frame(true) or nil
                    end,
                    getSize = function() return Get("width"), u.height() end,
                    setWidth = function(_, w)
                        Cfg().width = math.max(u.minWidth, EllesmereUI.PP.Snap(w))
                        u.applyStyle()
                        if IsUnlocked() and EllesmereUI.RepositionBarToMover then
                            EllesmereUI.RepositionBarToMover(u.key)
                        end
                    end,
                    savePos = function(_, point, relPoint, x, y)
                        if not point then return end
                        Cfg().pos = { point = point, relPoint = relPoint, x = x, y = y }
                        if not IsUnlocked() then Place(u.frame()) end
                    end,
                    loadPos = SavedPos,
                    clearPos = function()
                        Cfg().pos = nil
                        Place(u.frame())
                    end,
                    applyPos = function()
                        if Enabled() then Place(u.frame(true)) end
                    end,
                }),
            }, ns.FOLDER)
        end)
    end
    return F
end

-------------------------------------------------------------------------------
--  Import from the Forever Essentials Loot Feed and the built-in feed switch
--  Runs at ADDON_LOADED, before any PLAYER_LOGIN handler:
--   * once: EllesmereUIDB.lootFeed -> .feed and EllesmereUIDB.lootSession ->
--     .session (settings, history, ignored items, price choices, session),
--     plus the Unlock Mode anchors / size matches of the old elements. The old
--     data is left in place as a backup.
--   * every login while our feed is on: the built-in Loot Feed is switched
--     off, so the same loot never shows twice.
-------------------------------------------------------------------------------
local OLD_KEYS = { EUI_LootFeed = "EUI_DworakLootFeed", EUI_LootSession = "EUI_DworakLootSession" }

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = DeepCopy(x) end
    return t
end

local function Import(root)
    local old = EllesmereUIDB
    if type(old) ~= "table" then return end
    local imported = false
    if type(old.lootFeed) == "table" and root.feed == nil then
        root.feed = DeepCopy(old.lootFeed)
        imported = true
    end
    if type(old.lootSession) == "table" and root.session == nil then
        root.session = DeepCopy(old.lootSession)
        imported = true
    end
    -- Unlock Mode keeps anchors and size matches per element key.
    for _, store in ipairs({ "unlockAnchors", "unlockWidthMatch", "unlockHeightMatch",
                             "unlockWidthMatchExtra", "unlockHeightMatchExtra" }) do
        local t = old[store]
        if type(t) == "table" then
            for oldKey, newKey in pairs(OLD_KEYS) do
                if t[oldKey] ~= nil and t[newKey] == nil then t[newKey] = DeepCopy(t[oldKey]) end
            end
        end
    end
    return imported
end

local function DisableBuiltinFeed(root)
    local old = EllesmereUIDB
    if type(old) ~= "table" or type(old.lootFeed) ~= "table" then return end
    local ours = root.feed and root.feed.enabled == true
    if ours and old.lootFeed.enabled == true then
        old.lootFeed.enabled = false
        ns.builtinSwitchedOff = true
        return true
    end
end

-- From the options (our feed just switched on): the built-in feed's setting
-- goes off now; it stops drawing after a /reload.
function ns.DisableBuiltinFeed(live)
    if DisableBuiltinFeed(Root(true)) and live then
        ns.Print("switched off the Forever Essentials Loot Feed. |cffffd100/reload|r to remove its rows now.")
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON_NAME then return end
    self:UnregisterAllEvents()
    local root = Root(true)
    if not root.imported then
        root.imported = true
        ns.imported = Import(root)
    end
    DisableBuiltinFeed(root)
end)

-- Tell the player once the chat is up.
local notice = CreateFrame("Frame")
notice:RegisterEvent("PLAYER_LOGIN")
notice:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(3, function()
        if ns.imported then
            ns.Print("imported your Loot Feed settings, loot history, ignored items and farming session.")
        end
        if ns.builtinSwitchedOff then
            ns.Print("switched off the Forever Essentials Loot Feed, so loot does not show twice. "
                .. "Settings: Dworak > Loot Tracker (|cffffd100/loottracker|r).")
        end
    end)
end)
