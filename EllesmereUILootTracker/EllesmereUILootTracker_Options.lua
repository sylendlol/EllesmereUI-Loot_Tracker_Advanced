if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUILootTracker_Options.lua
--  The "Loot Tracker" row of the Dworak section (EllesmereUIDworak, through
--  EllesmereUI's Plugin API) with three pages: Loot Feed (live preview in the
--  content header), Farming Session and Loot History.
-------------------------------------------------------------------------------
local _, ns = ...

local PAGE_FEED, PAGE_SESSION, PAGE_HISTORY = "Loot Feed", "Farming Session", "Loot History"

-- The preview surface in the content header (Loot Feed page). Also handed
-- back through getHeaderBuilder so a cached page whose header was dropped
-- rebuilds with it.
local function HeaderBuilder(header, width)
    local building = true
    local view = ns.Feed.CreateSettingsPreview(header, width, function(height)
        if not building and header:IsVisible() and math.abs(header:GetHeight() - height) > 1 then
            EllesmereUI:SetContentHeaderHeightSilent(height)
        end
    end)
    building = false
    return view.previewHeight
end

local STYLES = { BOX = "Box", BAR = "Accent Bar", TRAY = "Icon Tray", TOAST = "Loot Toast" }
local STYLE_ORDER = { "BOX", "BAR", "TRAY", "TOAST" }

local function BuildPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local LF = ns.Feed
    local BLANK = EllesmereUI.BlankRowCfg
    local y = yOffset
    local _, h
    parent._showRowDivider = true

    local prebuilding = EllesmereUI.IsSearchPrebuild and EllesmereUI.IsSearchPrebuild()
    if pageName == PAGE_FEED and not prebuilding then EllesmereUI:SetContentHeader(HeaderBuilder) end

    local function off()
        return not LF.Get("enabled")
    end
    local function itemsOff()
        return off() or not LF.Get("items")
    end
    local function style()
        return LF.Get("style")
    end
    -- Accent Bar draws no border; Loot Toast's frame is always gold.
    local function noBorder()
        return off() or style() == "BAR" or LF.Get("borderSize") == 0
    end
    local function noBorderColor()
        return noBorder() or style() == "TOAST"
    end
    -- Switching a source re-registers the feed's events.
    local function Reapply()
        LF.Apply()
        LF.RefreshPreview()
        EllesmereUI:RefreshPage()
    end
    -- Binds cfg to setting key; apply runs after a change (none: the next row
    -- shown picks it up). Greyed out while the feed is off unless disabled is
    -- given.
    local function Bind(cfg, key, apply, disabled, disabledTooltip)
        cfg.disabled, cfg.disabledTooltip = disabled or off, disabledTooltip or "Loot Feed"
        cfg.getValue = cfg.getValue or function() return LF.Get(key) end
        cfg.setValue = cfg.setValue or function(v)
            LF.Cfg()[key] = v
            if apply then apply() end
        end
        return cfg
    end
    local function Toggle(key, text, tooltip, apply, disabled, disabledTooltip)
        return Bind({ type = "toggle", text = text, tooltip = tooltip }, key, apply, disabled, disabledTooltip)
    end
    local function Slider(key, text, min, max, tooltip, apply)
        return Bind({ type = "slider", text = text, tooltip = tooltip, min = min, max = max, step = 1 },
            key, apply or LF.ApplyStyle)
    end
    -- An inline swatch for the prefix .. "R" / "G" / "B" colour.
    local function Swatch(region, prefix, tooltip, disabled, disabledTooltip)
        EllesmereUI.BuildInlineSwatches(region, { {
            tooltip = tooltip, disabled = disabled, disabledTooltip = disabledTooltip,
            getValue = function() return LF.Get(prefix .. "R"), LF.Get(prefix .. "G"), LF.Get(prefix .. "B"), 1 end,
            setValue = function(r, g, b)
                local c = LF.Cfg()
                c[prefix .. "R"], c[prefix .. "G"], c[prefix .. "B"] = r, g, b
                LF.ApplyStyle()
            end,
        } }, { disabled = off, disabledTooltip = "Loot Feed" })
    end

    local LS = ns.Session
    local function sOff()
        return not LS.Get("enabled")
    end
    local function SBind(cfg, key, apply, disabled)
        cfg.disabled, cfg.disabledTooltip = disabled or sOff, "Farming Session"
        cfg.getValue = cfg.getValue or function() return LS.Get(key) end
        cfg.setValue = cfg.setValue or function(v)
            LS.Cfg()[key] = v
            if apply then apply() end
        end
        return cfg
    end

    if pageName == PAGE_FEED then
        ---------------------------------------------------------------------------
        --  GENERAL
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "LOOT FEED", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Loot Feed",
              tooltip = "Shows what you loot and gain as short-lived rows that fade out. "
                  .. "Switches the Forever Essentials Loot Feed off, so the same loot never shows twice.",
              getValue = function() return not off() end,
              setValue = function(v)
                  LF.Cfg().enabled = v
                  if v then ns.DisableBuiltinFeed(true) end
                  Reapply()
              end },
            { type = "labeledButton", text = "Preview", buttonText = "Show Samples",
              tooltip = "Shows a sample row for every enabled source.",
              disabled = off, disabledTooltip = "Loot Feed",
              onClick = function() LF.Preview() end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Bind({ type = "dropdown", text = "Style", values = STYLES, order = STYLE_ORDER }, "style", function()
                LF.ApplyStyle()
                if ns.IsUnlocked() and EllesmereUI.RepositionBarToMover then
                    EllesmereUI.RepositionBarToMover("EUI_DworakLootFeed")
                end
                EllesmereUI:RefreshPage()
            end),
            Bind({ type = "slider", text = "Accent Bar Width", min = 0, max = 6, step = 1,
                   tooltip = "0 hides the accent bar." }, "barWidth", LF.ApplyStyle,
                function() return off() or style() == "BOX" or style() == "TOAST" end,
                function() return off() and "Loot Feed" or "Style" end)
        );  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        ---------------------------------------------------------------------------
        --  SOURCES
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "SOURCES", y);  y = y - h

        _, h = W:DualRow(parent, y,
            Toggle("items", "Items", "Items you loot or receive.", Reapply),
            Toggle("money", "Money", "Money you loot.", Reapply)
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Toggle("reputation", "Reputation",
                "Reputation gains and losses, with your progress in the current standing.", Reapply),
            Toggle("currency", "Currencies", "Honor, badges and other currencies, with your total.", Reapply)
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Toggle("skills", "Skill Ups", "Weapon and profession skill increases.", Reapply),
            Bind({ type = "dropdown", text = "Currency Icon Format",
                   values = { DYNAMIC = "By Coin (Gold / Silver / Copper)", GOLD = "Always Gold" },
                   order = { "DYNAMIC", "GOLD" },
                   tooltip = "By Coin: the money row shows a copper, silver or gold icon by the largest coin looted." },
                "coinIcon", LF.RefreshPreview,
                function() return off() or not LF.Get("money") end,
                function() return off() and "Loot Feed" or "Money" end)
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Toggle("mailMoney", "Mailbox Money",
                "Money you take from the mailbox, as its own \"Mailbox\" row.", LF.RefreshPreview),
            BLANK()
        );  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        ---------------------------------------------------------------------------
        --  ITEMS
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "ITEMS", y);  y = y - h

        local qualityValues, qualityOrder = {}, {}
        for q = 0, 5 do
            local key, color = tostring(q), ITEM_QUALITY_COLORS[q]
            local label = _G["ITEM_QUALITY" .. q .. "_DESC"] or key
            qualityValues[key] = color and (color.hex .. label .. "|r") or label
            qualityOrder[q + 1] = key
        end

        _, h = W:DualRow(parent, y,
            Bind({ type = "dropdown", text = "Minimum Quality", values = qualityValues, order = qualityOrder,
                   tooltip = "Items below this quality are not shown.",
                   getValue = function() return tostring(LF.Get("minQuality")) end,
                   setValue = function(v)
                       LF.Cfg().minQuality = tonumber(v)
                       LF.RefreshPreview()
                   end }, nil, nil, itemsOff, "Items"),
            Toggle("showIlvl", "Show Item Level", "Shows the item level of weapons and armor.", LF.RefreshPreview,
                itemsOff, "Items")
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Toggle("showPrice", "Show Vendor Price", "Shows what the looted stack sells for at a vendor.",
                LF.RefreshPreview, itemsOff, "Items"),
            Toggle("junkMerge", "Merge Junk", "Grey items share one \"Junk xN\" row with their total vendor value.",
                LF.RefreshPreview, itemsOff, "Items")
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Toggle("showBagCount", "Show Bag Count", "Shows how many of the item you now carry, on the second line.",
                Reapply, itemsOff, "Items"),
            BLANK()
        );  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        ---------------------------------------------------------------------------
        --  EFFECTS
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "EFFECTS", y);  y = y - h

        local shineValues, shineOrder = {}, {}
        for q = 2, 5 do
            local key, color = tostring(q), ITEM_QUALITY_COLORS[q]
            local label = (_G["ITEM_QUALITY" .. q .. "_DESC"] or key) .. "+"
            shineValues[key] = color and (color.hex .. label .. "|r") or label
            shineOrder[#shineOrder + 1] = key
        end

        _, h = W:DualRow(parent, y,
            Toggle("shine", "Shine Effect",
                "A light band sweeps across new item rows of the chosen quality or better, and across valuable loot.",
                function() EllesmereUI:RefreshPage() end, itemsOff, "Items"),
            Bind({ type = "dropdown", text = "Shine Minimum Quality", values = shineValues, order = shineOrder,
                   getValue = function() return tostring(LF.Get("shineMinQuality")) end,
                   setValue = function(v) LF.Cfg().shineMinQuality = tonumber(v) end },
                nil, nil, function() return itemsOff() or not LF.Get("shine") end,
                function() return off() and "Loot Feed" or not LF.Get("items") and "Items" or "Shine Effect" end)
        );  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        ---------------------------------------------------------------------------
        --  VALUABLE LOOT ALERT
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "VALUABLE LOOT ALERT", y);  y = y - h

        local function alertOff()
            return itemsOff() or not LF.Get("alertEnabled")
        end
        local function alertWhy()
            if off() then return "Loot Feed" end
            if not LF.Get("items") then return "Items" end
            return "Valuable Loot Alert"
        end
        local SOUNDS = {
            RAID_WARNING = "Raid Warning", READY_CHECK = "Ready Check",
            IG_QUEST_LIST_COMPLETE = "Quest Complete", AUCTION_WINDOW_OPEN = "Auction House",
            LOOT_WINDOW_COIN_SOUND = "Coins", MAP_PING = "Map Ping",
        }
        local soundValues, soundOrder = {}, {}
        for _, key in ipairs({ "RAID_WARNING", "READY_CHECK", "IG_QUEST_LIST_COMPLETE", "AUCTION_WINDOW_OPEN",
                               "LOOT_WINDOW_COIN_SOUND", "MAP_PING" }) do
            if SOUNDKIT and SOUNDKIT[key] then
                soundValues[key] = SOUNDS[key]
                soundOrder[#soundOrder + 1] = key
            end
        end

        _, h = W:DualRow(parent, y,
            Toggle("alertEnabled", "Valuable Loot Alert",
                "A looted stack worth at least the threshold pulses, plays a sound and stays longer.",
                function() LF.RefreshPreview(); EllesmereUI:RefreshPage() end, itemsOff, "Items"),
            Bind({ type = "dropdown", text = "Price Source",
                   values = { MAX = "Higher of AH / Vendor", AH = "AH Price", VENDOR = "Vendor Price" },
                   order = { "MAX", "AH", "VENDOR" },
                   tooltip = "Which price the threshold is checked against. AH prices come from Auctionator." },
                "alertSource", nil, alertOff, alertWhy)
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Bind({ type = "slider", text = "Threshold Gold", min = 0, max = 1000, step = 1 },
                "alertGold", nil, alertOff, alertWhy),
            Bind({ type = "slider", text = "Threshold Silver", min = 0, max = 99, step = 1 },
                "alertSilver", nil, alertOff, alertWhy)
        );  y = y - h

        local pulseRow
        pulseRow, h = W:DualRow(parent, y,
            Toggle("alertPulse", "Pulse", "The row pulses in the alert color while it is shown.",
                function() LF.ApplyStyle(); EllesmereUI:RefreshPage() end, alertOff, alertWhy),
            Bind({ type = "slider", text = "Extra Display Time", min = 0, max = 30, step = 1,
                   tooltip = "Seconds a valuable row stays on top of its normal display time." },
                "alertExtra", nil, alertOff, alertWhy)
        );  y = y - h
        if not prebuilding then
            Swatch(pulseRow._leftRegion, "alert", "Pulse Color",
                function() return alertOff() or not LF.Get("alertPulse") end, alertWhy)
        end

        _, h = W:DualRow(parent, y,
            Toggle("alertSoundOn", "Play Sound", "Plays a sound when valuable loot comes in.",
                function() EllesmereUI:RefreshPage() end, alertOff, alertWhy),
            Bind({ type = "dropdown", text = "Sound", values = soundValues, order = soundOrder },
                "alertSound", function()
                    local id = SOUNDKIT and SOUNDKIT[LF.Get("alertSound")]
                    if id then PlaySound(id, "Master") end
                end,
                function() return alertOff() or not LF.Get("alertSoundOn") end, alertWhy)
        );  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        ---------------------------------------------------------------------------
        --  AUCTION HOUSE PRICE
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "AUCTION HOUSE PRICE", y);  y = y - h

        local function ahOff()
            return itemsOff() or not LF.Get("showAHPrice")
        end
        local function ahWhy()
            if off() then return "Loot Feed" end
            if not LF.Get("items") then return "Items" end
            return "Show AH Price"
        end
        local function AHApply()
            LF.ApplyStyle()
            EllesmereUI:RefreshPage()
        end

        _, h = W:DualRow(parent, y,
            Toggle("showAHPrice", "Show AH Price",
                "Shows what the looted stack is worth at the auction house, from Auctionator's price data. "
                .. "Items Auctionator has no price for show none."
                .. (LF.HasAH() and "" or "\n\n|cffff4040Auctionator is not loaded.|r"),
                AHApply, itemsOff, "Items"),
            Bind({ type = "dropdown", text = "AH Price Position",
                   values = { RIGHT = "Right Side (under vendor price)", SUB = "Second Line (under name)" },
                   order = { "RIGHT", "SUB" } }, "ahPos", LF.ApplyStyle, ahOff, ahWhy)
        );  y = y - h

        local ahRow
        ahRow, h = W:DualRow(parent, y,
            Bind({ type = "slider", text = "AH Price Text Size", min = 8, max = 24, step = 1 },
                "ahTextSize", LF.ApplyStyle, ahOff, ahWhy),
            Toggle("ahLabel", "Show \"AH\" Label", "Puts \"AH\" in front of the price.", LF.ApplyStyle, ahOff, ahWhy)
        );  y = y - h
        if not prebuilding then
            Swatch(ahRow._leftRegion, "ah", "AH Price Color", ahOff, ahWhy)
        end

        _, h = W:DualRow(parent, y,
            Bind({ type = "slider", text = "AH Price X Offset", min = -60, max = 60, step = 1 },
                "ahOffsetX", LF.ApplyStyle, ahOff, ahWhy),
            Bind({ type = "slider", text = "AH Price Y Offset", min = -20, max = 20, step = 1 },
                "ahOffsetY", LF.ApplyStyle, ahOff, ahWhy)
        );  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        ---------------------------------------------------------------------------
        --  LAYOUT
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "LAYOUT", y);  y = y - h

        _, h = W:DualRow(parent, y,
            Slider("width", "Width", 150, 600),
            Slider("rowHeight", "Row Height", 20, 60, "Tile size in the Icon Tray style.")
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Slider("maxRows", "Max Rows", 1, 12),
            Slider("duration", "Display Time", 1, 30, "Seconds a row stays before it fades out.")
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Bind({ type = "dropdown", text = "Grow Direction",
                   values = { UP = "Up", DOWN = "Down" }, order = { "UP", "DOWN" } }, "grow", LF.ApplyStyle),
            Slider("textSize", "Text Size", 8, 24)
        );  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        ---------------------------------------------------------------------------
        --  DISPLAY TIME BY QUALITY
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "DISPLAY TIME BY QUALITY", y);  y = y - h

        local function durOff()
            return itemsOff() or not LF.Get("qualityDuration")
        end
        local function durWhy()
            if off() then return "Loot Feed" end
            if not LF.Get("items") then return "Items" end
            return "Per-Quality Display Time"
        end
        local function DurSlider(q)
            local color = ITEM_QUALITY_COLORS[q]
            local label = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
            if color then label = color.hex .. label .. "|r" end
            return Bind({ type = "slider", text = label, min = 1, max = 60, step = 1,
                          tooltip = "Seconds this quality's item rows stay before they fade out." },
                "durQ" .. q, nil, durOff, durWhy)
        end

        _, h = W:DualRow(parent, y,
            Toggle("qualityDuration", "Per-Quality Display Time",
                "Item rows stay for the time set for their quality instead of Display Time. "
                .. "Money, reputation, currency and skill rows keep Display Time.",
                function() EllesmereUI:RefreshPage() end, itemsOff, "Items"),
            BLANK()
        );  y = y - h

        for q = 0, 5, 2 do
            _, h = W:DualRow(parent, y, DurSlider(q), DurSlider(q + 1));  y = y - h
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        ---------------------------------------------------------------------------
        --  DISPLAY
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

        local displayRow
        displayRow, h = W:DualRow(parent, y,
            Bind({ type = "slider", text = "Background", min = 0, max = 100, step = 1,
                   tooltip = "Opacity of the row background.",
                   getValue = function() return math.floor(LF.Get("bgA") * 100 + 0.5) end,
                   setValue = function(v)
                       LF.Cfg().bgA = v / 100
                       LF.ApplyStyle()
                   end }),
            Bind({ type = "slider", text = "Border Size", min = 0, max = 4, step = 1,
                   tooltip = "0 hides the border." }, "borderSize", function()
                LF.ApplyStyle()
                EllesmereUI:RefreshPage()
            end, function() return off() or style() == "BAR" end,
                function() return off() and "Loot Feed" or "Style" end)
        );  y = y - h
        if not prebuilding then
            Swatch(displayRow._leftRegion, "bg", "Background Color")
            -- Nothing to colour at size 0 (the slider + inline swatch pattern).
            Swatch(displayRow._rightRegion, "border", "Border Color", noBorderColor,
                function()
                    if off() then return "Loot Feed" end
                    if style() == "BAR" or style() == "TOAST" then return "Style" end
                    return "Border Size"
                end)
        end

        _, h = W:DualRow(parent, y,
            Toggle("qualityBorder", "Quality Borders", "Colors item rows by item quality.", LF.ApplyStyle,
                function()
                    if off() or not LF.Get("items") then return true end
                    return style() ~= "BAR" and style() ~= "TOAST" and LF.Get("borderSize") == 0
                end,
                function() return off() and "Loot Feed" or not LF.Get("items") and "Items" or "Border Size" end),
            BLANK()
        );  y = y - h


    elseif pageName == PAGE_SESSION then
        ---------------------------------------------------------------------------
        --  SESSION TRACKER
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "FARMING SESSION", y);  y = y - h


        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Farming Session",
              tooltip = "A small panel with the money and item value looted since the last reset, and gold per hour. "
                  .. "Works without the Loot Feed too. Drag it to move it. The X on the panel closes it and turns this off; "
                  .. "/lootsession turns it back on (/lootsession reset, /lootsession pause).",
              getValue = function() return not sOff() end,
              setValue = function(v)
                  LS.Cfg().enabled = v
                  LS.Apply()
                  EllesmereUI:RefreshPage()
              end },
            { type = "labeledButton", text = "Session", buttonText = "Reset Session",
              tooltip = "Starts a new session: clears the totals and the timer. Shift+Right-click on the panel does the same.",
              disabled = sOff, disabledTooltip = "Farming Session",
              onClick = function() LS.Reset() end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Pause", buttonText = "Pause / Resume",
              tooltip = "Pauses or resumes the session: while paused the timer stops and loot is not counted "
                  .. "(the history still records it). The button on the panel does the same.",
              disabled = sOff, disabledTooltip = "Farming Session",
              onClick = function() LS.TogglePause() end },
            BLANK()
        );  y = y - h

        _, h = W:DualRow(parent, y,
            SBind({ type = "dropdown", text = "Value Basis",
                    values = { AH = "Money + Items at AH Price", VENDOR = "Money + Items at Vendor Price",
                               MONEY = "Money Only" },
                    order = { "AH", "VENDOR", "MONEY" },
                    tooltip = "What Total and Per Hour count. At AH price, items Auctionator has no price for count at vendor price, "
                        .. "and so do items set to vendor price in the loot history (and grey items, if that option is on)." },
                "basis", LS.ApplyStyle),
            SBind({ type = "dropdown", text = "Auto Reset",
                    values = { NONE = "Never", LOGIN = "On Login", INSTANCE = "On Entering an Instance",
                               BOTH = "Login and Instance" },
                    order = { "NONE", "LOGIN", "INSTANCE", "BOTH" },
                    tooltip = "Instance: entering a different instance, or the same one after 10 minutes outside, starts a new session." },
                "autoReset")
        );  y = y - h

        _, h = W:DualRow(parent, y,
            SBind({ type = "slider", text = "Panel Width", min = 140, max = 400, step = 1 }, "width", LS.Apply),
            SBind({ type = "slider", text = "Panel Text Size", min = 8, max = 20, step = 1 }, "textSize", LS.Apply)
        );  y = y - h

        _, h = W:DualRow(parent, y,
            SBind({ type = "slider", text = "Panel Background", min = 0, max = 100, step = 1,
                    getValue = function() return math.floor(LS.Get("bgA") * 100 + 0.5) end,
                    setValue = function(v)
                        LS.Cfg().bgA = v / 100
                        LS.ApplyStyle()
                    end }),
            SBind({ type = "toggle", text = "Lock Panel",
                    tooltip = "Off: drag the panel with the mouse to move it. Unlock mode moves it either way." },
                "locked")
        );  y = y - h

        _, h = W:DualRow(parent, y,
            SBind({ type = "toggle", text = "Grey Items at Vendor Price",
                    tooltip = "Grey items count at vendor price in the session and the history: their AH prices are "
                        .. "rarely real sales. Click an item in the loot history to pick vendor or AH price for it; "
                        .. "that choice wins over this.",
                    disabled = function() return false end },
                "greyVendor", LS.Refresh, function() return false end),
            SBind({ type = "toggle", text = "Count Mailbox Money",
                    tooltip = "Counts money taken from the mailbox in the session too. Off by default: "
                        .. "auction sales and mail from alts are not farm income." },
                "mailToSession", LS.Refresh)
        );  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h


    elseif pageName == PAGE_HISTORY then
        ---------------------------------------------------------------------------
        --  LOOT HISTORY
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "LOOT HISTORY", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Record History",
              tooltip = "Keeps the items and money you looted (while the Loot Feed or the Farming Session is on). "
                  .. "Open it with /loothistory or by clicking the Farming Session panel.",
              getValue = function() return LS.Get("history") end,
              setValue = function(v)
                  LS.Cfg().history = v
                  LS.Apply()
              end },
            { type = "labeledButton", text = "History", buttonText = "Open History",
              tooltip = "Opens the loot history window.",
              onClick = function() LS.ToggleHistory() end }
        );  y = y - h

        local function hOff()
            return not LS.Get("history")
        end

        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Entries Kept", min = 10, max = 500, step = 10,
              tooltip = "How many entries the history keeps. The oldest are dropped first.",
              disabled = hOff, disabledTooltip = "Record History",
              getValue = function() return LS.Get("historyMax") end,
              setValue = function(v)
                  LS.Cfg().historyMax = v
                  LS.TrimHistory()
              end },
            { type = "toggle", text = "Record Money",
              tooltip = "Records looted money in the history too. Off: money is neither recorded nor listed.",
              disabled = hOff, disabledTooltip = "Record History",
              getValue = function() return LS.Get("historyMoney") end,
              setValue = function(v)
                  LS.Cfg().historyMoney = v
                  LS.RefreshHistory()
              end }
        );  y = y - h

        local qualityShown = {}
        for q = 0, 5 do qualityShown[q] = "histQ" .. q end
        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Clear", buttonText = "Clear History",
              tooltip = "Deletes every recorded entry.",
              onClick = function() LS.ClearHistory() end },
            { type = "labeledButton", text = "Quality Filter", buttonText = "Show All Qualities",
              tooltip = "The history window lists only the qualities switched on with the buttons at its top; "
                  .. "every item is still recorded. This switches them all back on.",
              onClick = function()
                  local c = LS.Cfg()
                  for q = 0, 5 do c[qualityShown[q]] = true end
                  LS.RefreshHistory()
              end }
        );  y = y - h

        local ignRow
        ignRow, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Ignored Items", buttonText = "Manage Ignored Items",
              tooltip = "Lists the items set to Ignore: their vendor and AH value never count in the session. "
                  .. "Remove them or add new ones (item ID, item link or drop an item). Also: /lootignore",
              onClick = function() LS.ToggleIgnored() end },
            { type = "slider", text = "Window Background", min = 0, max = 100, step = 1,
              tooltip = "Opacity of the loot history and ignored items windows. The swatch sets the color.",
              getValue = function() return math.floor(LS.Get("histBgA") * 100 + 0.5) end,
              setValue = function(v)
                  LS.Cfg().histBgA = v / 100
                  LS.ApplyWindowBg()
              end }
        );  y = y - h
        if not prebuilding then
            EllesmereUI.BuildInlineSwatches(ignRow._rightRegion, { {
                tooltip = "Window Background Color",
                getValue = function() return LS.Get("histBgR"), LS.Get("histBgG"), LS.Get("histBgB"), 1 end,
                setValue = function(r, g, b)
                    local c = LS.Cfg()
                    c.histBgR, c.histBgG, c.histBgB = r, g, b
                    LS.ApplyWindowBg()
                end,
            } }, {})
        end

        local textRow
        textRow, h = W:DualRow(parent, y,
            { type = "slider", text = "History Text Size", min = 8, max = 24, step = 1,
              tooltip = "Text size of the loot history rows. The rows grow with it.",
              getValue = function() return LS.Get("histTextSize") end,
              setValue = function(v)
                  LS.Cfg().histTextSize = v
                  LS.RefreshHistory()
              end },
            { type = "slider", text = "Window Border", min = 0, max = 4, step = 1,
              tooltip = "Border size of the loot history and ignored items windows. 0 hides the border. "
                  .. "The swatch sets the color.",
              getValue = function() return LS.Get("histBorderSize") end,
              setValue = function(v)
                  LS.Cfg().histBorderSize = v
                  LS.ApplyWindowBg()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        if not prebuilding then
            EllesmereUI.BuildInlineSwatches(textRow._rightRegion, { {
                tooltip = "Window Border Color",
                disabled = function() return LS.Get("histBorderSize") == 0 end,
                disabledTooltip = "Window Border",
                getValue = function() return LS.Get("histBorderR"), LS.Get("histBorderG"), LS.Get("histBorderB"), 1 end,
                setValue = function(r, g, b)
                    local c = LS.Cfg()
                    c.histBorderR, c.histBorderG, c.histBorderB = r, g, b
                    LS.ApplyWindowBg()
                end,
            } }, {})
        end

        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Close with Esc",
              tooltip = "On: the Esc key closes the loot history and ignored items windows, like Blizzard windows. "
                  .. "Off: only their X button or the slash commands close them.",
              getValue = function() return LS.Get("histEscClose") end,
              setValue = function(v)
                  LS.Cfg().histEscClose = v
                  LS.UpdateEscClose()
              end },
            { type = "toggle", text = "Minimap Icon",
              tooltip = "A minimap icon: Left-click opens the loot history, Right-click the ignored items, "
                  .. "Shift+Left-click turns the Farming Session on / off. Drag it around the minimap.",
              getValue = function() return LS.Get("minimapIcon") end,
              setValue = function(v)
                  LS.Cfg().minimapIcon = v
                  LS.ApplyMinimapIcon()
              end }
        );  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h


    end

    return math.abs(y)
end

-------------------------------------------------------------------------------
--  Registration: the "Loot Tracker" row of the "Dworak" sidebar section. The
--  section itself belongs to EllesmereUIDworak, which registers it at login
--  with every Dworak addon's row.
-------------------------------------------------------------------------------
local DW = EllesmereUIDworak
if not DW then
    ns.Print("EllesmereUI Dworak is not enabled, so the Loot Tracker settings cannot be shown.")
    return
end

DW.AddModule({
    key         = "LootTracker",
    title       = "Loot Tracker",
    order       = 40,
    description = "Loot feed with auction prices, farming session with gold per hour, and a loot history.",
    pages       = { PAGE_FEED, PAGE_SESSION, PAGE_HISTORY },
    buildPage   = BuildPage,
    getHeaderBuilder = function(pageName)
        if pageName == PAGE_FEED then return HeaderBuilder end
    end,
    onPageCacheRestore = function(pageName)
        if pageName == PAGE_FEED then ns.Feed.RefreshPreview() end
    end,
})

-- /loottracker opens the settings (optionally on a page: feed, session, history).
SLASH_EUILOOTTRACKER1 = "/loottracker"
SlashCmdList.EUILOOTTRACKER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    local page = (msg == "session" and PAGE_SESSION) or (msg == "history" and PAGE_HISTORY) or PAGE_FEED
    DW.Open("LootTracker", page)
end
