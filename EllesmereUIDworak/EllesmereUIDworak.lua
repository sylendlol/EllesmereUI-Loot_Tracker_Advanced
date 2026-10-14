if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIDworak.lua
--  Owns the "Dworak" sidebar section of the EllesmereUI panel. The Plugin API
--  (EllesmereUI\PLUGINS_API.md) gives one section per plugin and takes its
--  module list as a snapshot, so every Dworak addon hands its module spec to
--  this one, and the section is registered once, at login, with all of them.
--  Each Dworak addon stays independent: switch one off and only its row goes.
--
--  A Dworak addon:
--    ## Dependencies: EllesmereUI, EllesmereUIDworak
--    EllesmereUIDworak.AddModule({ key = "...", title = "...", order = 10, pages = {...},
--        buildPage = function(pageName, parent, yOffset) ... end, ... })
--    EllesmereUIDworak.Open("<key>")      -- from its slash command
--  The spec is a Plugin API module spec; order (lower first) sorts the rows.
-------------------------------------------------------------------------------
local PLUGIN_ID = "EllesmereUIDworak"

EllesmereUIDworak = EllesmereUIDworak or {}
local D = EllesmereUIDworak

D.ID            = PLUGIN_ID
D.SECTION_LABEL = "Dworak"   -- EllesmereUI sidebar section
D.POSITION      = "top"      -- "top": above EUI's own sections, "bottom": below
D.UNLOCK_GROUP  = "Dworak"   -- group in EllesmereUI Unlock Mode

local specs, registered = {}, false

function D.AddModule(spec)
    if registered then
        geterrorhandler()("EllesmereUIDworak.AddModule(" .. tostring(spec and spec.key)
            .. "): too late, the Dworak section is registered at login.")
        return false
    end
    specs[#specs + 1] = spec
    return true
end

function D.Open(moduleKey, pageName)
    if InCombatLockdown() then
        EllesmereUI.Print((EllesmereUI.COLOR_CODES and EllesmereUI.COLOR_CODES.BRAND or "|cff0cd29d")
            .. "Dworak:|r the settings open after combat.")
        return false
    end
    return EllesmereUI.OpenPlugin and EllesmereUI.OpenPlugin(PLUGIN_ID, moduleKey, pageName) or false
end

local function Register()
    registered = true
    if #specs == 0 then return end
    if not EllesmereUI.RegisterPlugin then
        EllesmereUI.Print("|cff0cd29dDworak:|r this EllesmereUI version has no plugin support, so the Dworak settings cannot be shown.")
        return
    end
    -- Stable sort by order, then by the order the addons added themselves.
    for i, s in ipairs(specs) do s._dworakIndex = i end
    table.sort(specs, function(a, b)
        local oa, ob = a.order or 100, b.order or 100
        if oa ~= ob then return oa < ob end
        return a._dworakIndex < b._dworakIndex
    end)
    local modules = {}
    for i, s in ipairs(specs) do
        local m = {}
        for k, v in pairs(s) do
            if k ~= "order" and k ~= "_dworakIndex" then m[k] = v end
        end
        modules[i] = m
    end
    EllesmereUI.RegisterPlugin(PLUGIN_ID, {
        label    = D.SECTION_LABEL,
        position = D.POSITION,
        modules  = modules,
    })
end

-- PLAYER_LOGIN: every addon has loaded by then, so every module is in.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Register()
end)
