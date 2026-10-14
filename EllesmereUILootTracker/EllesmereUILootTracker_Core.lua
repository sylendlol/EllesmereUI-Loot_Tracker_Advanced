if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUILootTracker_Core.lua
--  The Loot Tracker itself (ported from the Forever Essentials Loot Feed and
--  its additions): a stack of short-lived rows for what the player gains --
--  looted items (vendor + Auctionator price), money, mailbox money,
--  reputation, currencies and skill ups -- plus the Farming Session panel,
--  the Loot History and Ignored Items windows and the minimap icon.
--  Chat lines are matched against the client's own localized format strings,
--  so this works in every client language.
-------------------------------------------------------------------------------
local _, ns = ...

local GAP = 2
local FADE_IN = 0.35
local FADE_OUT = 0.8
local SLIDE = 24 -- px a new row glides in from the left
local CALLOUT_GAP = 6 -- Icon Tray: space between the name row and the tiles
local MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_02"
-- Currency Icon Format "By Coin": the row icon follows the largest coin.
local COIN_ICONS = {
    gold = "Interface\\Icons\\INV_Misc_Coin_02",
    silver = "Interface\\Icons\\INV_Misc_Coin_04",
    copper = "Interface\\Icons\\INV_Misc_Coin_06",
}
local REP_ICON = "Interface\\Icons\\INV_Misc_Note_02"
local SKILL_ICON = "Interface\\Icons\\INV_Misc_Book_08"

-- Settings live in EllesmereUILootTrackerDB.feed; unset keys read these.
local DEFAULTS = {
    enabled = false,
    items = true, money = true, reputation = true, currency = true, skills = true,
    minQuality = 0, showIlvl = true, showPrice = true,
    -- Auction house price (from Auctionator) of the looted stack.
    -- ahPos: SUB = second line under the name, RIGHT = right side under the
    -- vendor price.
    showAHPrice = false, ahPos = "RIGHT", ahTextSize = 11, ahLabel = true,
    ahR = 0.40, ahG = 0.78, ahB = 1.00, ahOffsetX = 0, ahOffsetY = 0,
    -- Money row icon: DYNAMIC = gold / silver / copper by the largest coin,
    -- GOLD = always the gold coins.
    coinIcon = "DYNAMIC",
    -- Money taken from the mailbox (read from the money change while the
    -- mailbox is open: the client's chat line has no coin names to match).
    mailMoney = true,
    -- Per-quality display time for item rows (durQ0 = Poor .. durQ5 =
    -- Legendary); off: every row uses duration.
    qualityDuration = false,
    durQ0 = 3, durQ1 = 4, durQ2 = 5, durQ3 = 8, durQ4 = 12, durQ5 = 20,
    -- Grey items share one "Junk xN" row; bag count on the second line.
    junkMerge = false, showBagCount = false,
    -- Shine: a light band sweeps across new item rows of this quality or better.
    shine = true, shineMinQuality = 3,
    -- Valuable loot: a stack worth at least alertGold g alertSilver s (by
    -- alertSource: MAX = the higher of AH and vendor, AH, VENDOR) pulses,
    -- plays alertSound and stays alertExtra seconds longer.
    alertEnabled = false, alertSource = "MAX", alertGold = 5, alertSilver = 0,
    alertPulse = true, alertR = 1, alertG = 0.82, alertB = 0,
    alertSoundOn = true, alertSound = "RAID_WARNING", alertExtra = 5,
    -- BOX: bordered rows, BAR: accent bar on a fading background, TRAY: icon
    -- tiles with a name row, TOAST: framed plates.
    style = "BAR",
    width = 300, rowHeight = 36, maxRows = 6, duration = 5, grow = "UP",
    textSize = 13, barWidth = 3,
    bgR = 0.05, bgG = 0.05, bgB = 0.05, bgA = 0.3,
    borderSize = 1, borderR = 0, borderG = 0, borderB = 0, qualityBorder = true,
}
local F = ns.Feature("feed", DEFAULTS,
    { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -320, y = 260 })
local Get, Cfg, Enabled = F.Get, F.Cfg, F.Enabled

-- Farming Session and Loot History: their own settings (EllesmereUILootTrackerDB.session)
-- and unlock element. data holds the running session, history the last loot.
local SDEFAULTS = {
    enabled = false, width = 220, textSize = 12, bgA = 0.6,
    -- Per-hour and total basis: AH = items at AH price (vendor when AH has
    -- none), VENDOR = items at vendor price, MONEY = looted money only.
    basis = "AH",
    -- NONE, LOGIN, INSTANCE (entering a different instance, or the same one
    -- after 10 minutes outside), BOTH.
    autoReset = "NONE",
    locked = false, -- true: the panel cannot be dragged (unlock mode still moves it)
    history = true,
    -- Grey items count at vendor price in the session (their AH prices are
    -- rarely real sales). A choice made in the history window wins.
    greyVendor = true,
    mailToSession = false, -- count mailbox money in the session (AH sales etc. are not farm income)
    -- Entries kept (oldest dropped), whether money is recorded, and which
    -- qualities the window lists (every item is still recorded).
    historyMax = 50, historyMoney = true,
    histQ0 = true, histQ1 = true, histQ2 = true, histQ3 = true, histQ4 = true, histQ5 = true,
    histW = 380, histH = 380,
    -- Background of the loot history and ignored items windows.
    histBgR = 0.05, histBgG = 0.05, histBgB = 0.05, histBgA = 0.94,
    -- Border of the loot history and ignored items windows; size 0 = none.
    histBorderSize = 1, histBorderR = 0, histBorderG = 0, histBorderB = 0,
    histTextSize = 12,
    histEscClose = false,
    minimapIcon = true, -- minimap icon for the loot history (minimapAngle: its spot) -- Esc closes the loot history and ignored items windows -- text size of the loot history rows (row height follows)
}
local S = ns.Feature("session", SDEFAULTS,
    { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -320, y = 520 })

local anchor, events
local active = {} -- shown rows, newest first
local pool = {}
-- A row set: the frame its rows are laid out in, its rows (newest first) and
-- the Icon Tray name row. The live feed and the options preview are one each.
local feed = { rows = active }

-- v when it is a readable value of type kind (never a secret one).
local function Plain(v, kind)
    if not issecretvalue(v) and type(v) == kind then return v end
end

-------------------------------------------------------------------------------
--  Chat line matching
-------------------------------------------------------------------------------
-- A Blizzard format string as a Lua pattern with one capture per %s / %d.
-- swap marks a format that puts its second argument first (%2$d before %1$s);
-- the formats read here have at most two.
local function Compile(fmt, anchored)
    local parts, i, first = {}, 1, nil
    while true do
        local s, e, pos, kind = fmt:find("%%(%d?)%$?([sd])", i)
        parts[#parts + 1] = (fmt:sub(i, s and s - 1):gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"))
        if not s then break end
        first = first or tonumber(pos)
        parts[#parts + 1] = kind == "d" and "(%d+)" or "(.-)"
        i = e + 1
    end
    local p = table.concat(parts)
    return { pat = anchored and "^" .. p .. "$" or p, swap = first == 2 }
end

-- The captures of text against the global format string key, in argument
-- order: the whole line, or anywhere in it when loose. Compiled once per key;
-- a key the client lacks never matches.
local compiled = {}
local function Match(key, text, loose)
    local c = compiled[key]
    if c == nil then
        local fmt = _G[key]
        c = type(fmt) == "string" and fmt ~= "" and Compile(fmt, not loose) or false
        compiled[key] = c
    end
    if not c then return end
    local a, b = text:match(c.pat)
    if c.swap then return b, a end
    return a, b
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
local function StyleFont(fs, size)
    EllesmereUI.ApplyModuleFont(fs, nil, size)
end

-- Toast plates draw a frame 1 px outside the row, so they need more space.
local function Gap()
    return Get("style") == "TOAST" and GAP + 2 or GAP
end

-- Icon Tray: tiles per line and lines needed for n tiles.
local function TrayGrid(n)
    local step = Get("rowHeight") + GAP
    local cols = math.max(1, math.floor((Get("width") + GAP) / step))
    return cols, math.ceil(n / cols)
end

-- Height of a set with n rows, Max Rows when n is nil.
local function AnchorHeight(n)
    local h = Get("rowHeight")
    n = n or Get("maxRows")
    if Get("style") == "TRAY" then
        local _, lines = TrayGrid(n)
        return h + CALLOUT_GAP + lines * (h + GAP) - GAP
    end
    local gap = Gap()
    return n * (h + gap) - gap
end

local function Accent()
    local c = EllesmereUI.ELLESMERE_GREEN
    if c then return c.r, c.g, c.b end
    return 0.05, 0.82, 0.62
end

-- Gradient end colours, refilled for each paint (SetGradient copies them).
local gradFrom, gradTo = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0)

-- Solid, or a two-colour fade to transparent (BAR).
local function PaintBackground(tex, fade)
    local r, g, b, a = Get("bgR"), Get("bgG"), Get("bgB"), Get("bgA")
    tex:SetColorTexture(1, 1, 1, 1)
    gradFrom:SetRGBA(r, g, b, a)
    gradTo:SetRGBA(r, g, b, fade and 0 or a)
    tex:SetGradient("HORIZONTAL", gradFrom, gradTo)
end

-- Item rows take their quality colour when quality colouring is on;
-- everything else the accent (BAR, the Icon Tray name row) or the border colour.
local function RowColor(d, accent)
    if d.border and Get("qualityBorder") then return d.border.r, d.border.g, d.border.b end
    if accent then return Accent() end
    return Get("borderR"), Get("borderG"), Get("borderB")
end

-- Loot Toast colours; EDGE: icon frame of rows without a quality.
local TOAST = {
    GOLD = { 0.69, 0.54, 0.23 }, EDGE = { 0.35, 0.27, 0.14 },
    TOP = { 0.19, 0.14, 0.09 }, BOTTOM = { 0.055, 0.04, 0.024 },
}

-- TOAST: a black 1 px frame around the gold one, with a gold stud at each
-- end. Made the first time a row is drawn as a toast.
local function ToastChrome(r)
    if r.outer then return r.outer end
    local o = CreateFrame("Frame", nil, r)
    o:SetPoint("TOPLEFT", -1, 1)
    o:SetPoint("BOTTOMRIGHT", 1, -1)
    EllesmereUI.PP.CreateBorder(o, 0, 0, 0, 1, 1, "OVERLAY", 1)
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local edge = o:CreateTexture(nil, "OVERLAY", nil, 3)
        edge:SetColorTexture(0, 0, 0, 1)
        edge:SetSize(8, 8)
        edge:SetRotation(math.rad(45))
        edge:SetPoint("CENTER", o, side)
        local stud = o:CreateTexture(nil, "OVERLAY", nil, 4)
        stud:SetColorTexture(0.85, 0.70, 0.34, 1)
        stud:SetSize(6, 6)
        stud:SetRotation(math.rad(45))
        stud:SetPoint("CENTER", edge)
    end
    r.outer = o
    return o
end

local function StyleRow(r)
    local h, size, style = Get("rowHeight"), Get("textSize"), Get("style")
    local tray, bar, toast = style == "TRAY", style == "BAR", style == "TOAST"
    r:SetSize(tray and h or Get("width"), h)
    r.icon:ClearAllPoints()
    if bar then
        local bw = Get("barWidth")
        r.bar:SetWidth(math.max(bw, 1))
        r.bar:SetShown(bw > 0)
        r.icon:SetSize(h - 8, h - 8)
        r.icon:SetPoint("LEFT", bw > 0 and bw + 5 or 4, 0)
    elseif toast then
        r.bar:Hide()
        r.icon:SetSize(h - 10, h - 10)
        r.icon:SetPoint("LEFT", 6, 0)
    else
        r.bar:Hide()
        r.icon:SetSize(h, h)
        r.icon:SetPoint("LEFT")
    end
    -- Icon frame: 1 px black (BAR) or 2 px quality colour (TOAST, set by Fill).
    local edge = toast and 2 or 1
    r.iconBg:ClearAllPoints()
    r.iconBg:SetPoint("TOPLEFT", r.icon, "TOPLEFT", -edge, edge)
    r.iconBg:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", edge, -edge)
    if bar then r.iconBg:SetColorTexture(0, 0, 0, 1) end
    r.iconBg:SetShown(bar or toast)
    if toast then
        ToastChrome(r):SetShown(Get("borderSize") > 0)
        local a = Get("bgA")
        r.bg:SetColorTexture(1, 1, 1, 1)
        gradFrom:SetRGBA(TOAST.BOTTOM[1], TOAST.BOTTOM[2], TOAST.BOTTOM[3], a)
        gradTo:SetRGBA(TOAST.TOP[1], TOAST.TOP[2], TOAST.TOP[3], a)
        r.bg:SetGradient("VERTICAL", gradFrom, gradTo)
    else
        if r.outer then r.outer:Hide() end
        if not tray then PaintBackground(r.bg, bar) end
    end
    r.bg:SetShown(not tray)
    r.name:SetShown(not tray)
    r.value:SetShown(not tray)
    r.badge:SetShown(tray)
    -- Second line: game gold on toasts, a quiet grey on bars.
    if toast then
        r.sub:SetTextColor(1, 0.82, 0)
    elseif bar then
        r.sub:SetTextColor(0.7, 0.7, 0.7)
    else
        r.sub:SetTextColor(1, 1, 1)
    end
    StyleFont(r.name, size)
    StyleFont(r.value, size)
    StyleFont(r.sub, size - 2)
    StyleFont(r.badge, size - 1)
    StyleFont(r.ah, Get("ahTextSize"))
    r.ah:SetTextColor(Get("ahR"), Get("ahG"), Get("ahB"))
    r.fade.alpha:SetStartDelay(Get("duration"))
end

local function Text(r)
    local fs = r:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Icon Tray: the newest gain's name row above the tiles (on top with grow
-- Down). It is a child of that gain's tile, so it fades with it.
local function ShowCallout(set)
    local c = set.callout
    if not c then
        c = CreateFrame("Frame", nil, set.frame)
        c.bg = c:CreateTexture(nil, "BACKGROUND")
        c.bg:SetAllPoints()
        c.bar = c:CreateTexture(nil, "ARTWORK")
        c.bar:SetPoint("TOPRIGHT")
        c.bar:SetPoint("BOTTOMRIGHT")
        c.name, c.sub, c.value = Text(c), Text(c), Text(c)
        c.value:SetJustifyH("RIGHT")
        set.callout = c
    end
    local r = set.rows[1]
    local d = r.data
    local h, bw, size = Get("rowHeight"), Get("barWidth"), Get("textSize")
    c:SetParent(r)
    c:SetSize(Get("width"), h)
    c:ClearAllPoints()
    if Get("grow") == "UP" then
        local _, lines = TrayGrid(#set.rows)
        c:SetPoint("BOTTOMRIGHT", set.frame, "BOTTOMRIGHT", 0, lines * (h + GAP) - GAP + CALLOUT_GAP)
    else
        c:SetPoint("TOPRIGHT", set.frame, "TOPRIGHT", 0, 0)
    end
    PaintBackground(c.bg, false)
    c.bar:SetWidth(math.max(bw, 1))
    c.bar:SetShown(bw > 0)
    c.bar:SetColorTexture(RowColor(d, true))
    StyleFont(c.name, size)
    StyleFont(c.value, size)
    StyleFont(c.sub, size - 2)
    c.name:SetText(d.text)
    local cv = d.value or ""
    if d.ah then
        local ah = string.format("|cff%02x%02x%02x%s|r", math.floor(Get("ahR") * 255 + 0.5),
            math.floor(Get("ahG") * 255 + 0.5), math.floor(Get("ahB") * 255 + 0.5), d.ah)
        cv = cv ~= "" and (cv .. "  " .. ah) or ah
    end
    c.value:SetText(cv)
    c.sub:SetText(d.sub or "")
    c.sub:SetShown(d.sub ~= nil)
    c.name:ClearAllPoints()
    c.sub:ClearAllPoints()
    c.value:ClearAllPoints()
    local right = -(bw + 8)
    if d.sub then
        -- Name across the top, progress and value below it.
        c.name:SetPoint("BOTTOMLEFT", c, "LEFT", 8, 1)
        c.name:SetPoint("RIGHT", c, "RIGHT", right, 0)
        c.value:SetPoint("TOPRIGHT", c, "RIGHT", right, -1)
        c.sub:SetPoint("TOPLEFT", c, "LEFT", 8, -1)
        c.sub:SetPoint("RIGHT", c.value, "LEFT", -8, 0)
    else
        c.value:SetPoint("RIGHT", c, "RIGHT", right, 0)
        c.name:SetPoint("LEFT", c, "LEFT", 8, 0)
        c.name:SetPoint("RIGHT", c.value, "LEFT", -8, 0)
    end
    c:Show()
end

local function Layout(set)
    set = set or feed
    local frame = set.frame
    local up = Get("grow") == "UP"
    local tray = Get("style") == "TRAY"
    local step = Get("rowHeight") + (tray and GAP or Gap())
    local cols = TrayGrid(1)
    local below = Get("rowHeight") + CALLOUT_GAP -- grow Down: tiles start under the name row
    for i, r in ipairs(set.rows) do
        r:ClearAllPoints()
        if tray then
            local col, line = (i - 1) % cols, math.floor((i - 1) / cols)
            if up then
                r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -col * step, line * step)
            else
                r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -col * step, -(below + line * step))
            end
        elseif up then
            r:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, (i - 1) * step)
        else
            r:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(i - 1) * step)
        end
    end
    if tray and set.rows[1] then
        ShowCallout(set)
    elseif set.callout then
        set.callout:Hide()
    end
end

local function Unlist(r)
    for i = #active, 1, -1 do
        if active[i] == r then table.remove(active, i) end
    end
end

-------------------------------------------------------------------------------
--  Row effects: the shine sweep and the valuable-loot pulse
-------------------------------------------------------------------------------
local SHINE_W, SHINE_TIME = 48, 0.9

local function StopPulse(r)
    if not r.pulse then return end
    r.pulse.anim:Stop()
    r.pulse:Hide()
end

local function StartPulse(r)
    if r.pulse.anim:IsPlaying() then return end
    r.pulse:SetColorTexture(Get("alertR"), Get("alertG"), Get("alertB"), 1)
    r.pulse:Show()
    r.pulse.anim:Play()
end

-- A light band in the item's quality colour crossing the row once.
local function PlayShine(r, color)
    local s = r.shine
    local cr, cg, cb = 1, 1, 1
    if color then
        -- Lighten the quality colour so the band reads on dark backgrounds.
        cr, cg, cb = (color.r + 1) / 2, (color.g + 1) / 2, (color.b + 1) / 2
    end
    gradFrom:SetRGBA(cr, cg, cb, 0)
    gradTo:SetRGBA(cr, cg, cb, 0.65)
    s.l:SetGradient("HORIZONTAL", gradFrom, gradTo)
    s.r:SetGradient("HORIZONTAL", gradTo, gradFrom)
    s.anim:Stop()
    s.move:SetOffset(r:GetWidth() + SHINE_W, 0)
    s:Show()
    s.anim:Play()
end

local function ShouldShine(d)
    if not Get("shine") then return false end
    return (d.quality and d.quality >= Get("shineMinQuality")) or d.alert == true
end

local function Release(r)
    Unlist(r)
    r.show:Stop()
    r.fade:Stop()
    r.shine.anim:Stop()
    r.shine:Hide()
    StopPulse(r)
    r:Hide()
    r.key, r.data = nil, nil
    pool[#pool + 1] = r
    Layout()
end

-- Starts the wait-then-fade-out, unless the row is still fading in (its
-- end starts it) or hovered (leaving starts it).
-- Preview rows never fade.
-- Seconds a row stays: by item quality when Per-Quality Display Time is on,
-- plus the valuable-loot extra.
local function RowDuration(d)
    local q = d and d.quality
    local secs = Get("duration")
    if q and Get("qualityDuration") then
        secs = Get("durQ" .. math.min(math.max(q, 0), 5)) or secs
    end
    if d and d.alert then secs = secs + Get("alertExtra") end
    return secs
end

local function ArmFade(r)
    if r.preview or r.show:IsPlaying() then return end
    r.fade:Stop()
    r.fade.alpha:SetStartDelay(RowDuration(r.data))
    r:SetAlpha(1)
    if not r:IsMouseOver() then r.fade:Play() end
end

-- Hover shows the item tooltip and holds the fade. Icon Tray tiles show no
-- text, so for them the tooltip carries it.
local function RowEnter(r)
    if not r.show:IsPlaying() then
        r.fade:Stop()
        r:SetAlpha(1)
    end
    local d = r.data
    if not d then return end
    if d.link then
        GameTooltip:SetOwner(r, "ANCHOR_LEFT")
        GameTooltip:SetHyperlink(d.link)
        GameTooltip:Show()
    elseif Get("style") == "TRAY" then
        local text = d.text
        if d.sub then text = text .. "\n" .. EllesmereUI.COLOR_CODES.DIM .. d.sub .. "|r" end
        if d.value then text = text .. "\n" .. d.value end
        r.tip = true
        EllesmereUI.ShowWidgetTooltip(r, text, { anchor = "left" })
    end
end

local function RowLeave(r)
    if GameTooltip:IsOwned(r) then GameTooltip:Hide() end
    if r.tip then
        r.tip = nil
        EllesmereUI.HideWidgetTooltip()
    end
    ArmFade(r)
end

local function ShowDone(g) ArmFade(g:GetParent()) end
local function FadeDone(g) Release(g:GetParent()) end

-- One animation of group g: step order, seconds, easing.
local function Anim(g, kind, order, secs, smoothing)
    local a = g:CreateAnimation(kind)
    a:SetOrder(order)
    a:SetDuration(secs)
    if smoothing then a:SetSmoothing(smoothing) end
    return a
end

local function NewRow(parent)
    local r = CreateFrame("Frame", nil, parent or anchor)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetPoint("TOPLEFT")
    r.bar:SetPoint("BOTTOMLEFT")
    r.icon = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon frame
    r.iconBg = r:CreateTexture(nil, "ARTWORK")
    r.badge = r:CreateFontString(nil, "OVERLAY")
    r.badge:SetPoint("BOTTOMRIGHT", -2, 2)
    r.name, r.sub, r.value = Text(r), Text(r), Text(r)
    r.value:SetJustifyH("RIGHT")
    r.value:SetPoint("RIGHT", -6, 0)
    r.sub:SetPoint("TOPLEFT", r.icon, "RIGHT", 6, -1)
    r.sub:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
    r.ah = Text(r) -- auction house price, own size and colour; placed by Fill
    r.ah:Hide()
    -- Effects layer above the text, clipped to the row so the shine band
    -- never shows outside it (the Toast frame sits outside the row, so the
    -- row itself cannot clip).
    local fx = CreateFrame("Frame", nil, r)
    fx:SetAllPoints()
    fx:SetClipsChildren(true)
    fx:SetFrameLevel(r:GetFrameLevel() + 3)
    r.fx = fx
    local s = CreateFrame("Frame", nil, fx)
    s:SetWidth(SHINE_W)
    s:SetPoint("TOPRIGHT", fx, "TOPLEFT")
    s:SetPoint("BOTTOMRIGHT", fx, "BOTTOMLEFT")
    s.l = s:CreateTexture(nil, "OVERLAY")
    s.l:SetPoint("TOPLEFT")
    s.l:SetPoint("BOTTOMRIGHT", s, "BOTTOM")
    s.r = s:CreateTexture(nil, "OVERLAY")
    s.r:SetPoint("TOPLEFT", s, "TOP")
    s.r:SetPoint("BOTTOMRIGHT")
    for _, t in ipairs({ s.l, s.r }) do
        t:SetColorTexture(1, 1, 1, 1)
        t:SetBlendMode("ADD")
    end
    s.anim = s:CreateAnimationGroup()
    s.move = s.anim:CreateAnimation("Translation")
    s.move:SetDuration(SHINE_TIME)
    s.move:SetStartDelay(FADE_IN * 0.5)
    s.move:SetSmoothing("IN_OUT")
    s.anim:SetScript("OnFinished", function() s:Hide() end)
    s:Hide()
    r.shine = s
    local p = fx:CreateTexture(nil, "ARTWORK")
    p:SetAllPoints()
    p:SetBlendMode("ADD")
    p:Hide()
    p.anim = p:CreateAnimationGroup()
    p.anim:SetLooping("BOUNCE")
    local pa = p.anim:CreateAnimation("Alpha")
    pa:SetFromAlpha(0)
    pa:SetToAlpha(0.28)
    pa:SetDuration(0.55)
    pa:SetSmoothing("IN_OUT")
    r.pulse = p
    EllesmereUI.PP.CreateBorder(r, 0, 0, 0, 1, 1, "OVERLAY", 2)
    -- Hover only: clicks pass through.
    r:EnableMouseMotion(true)
    r:SetScript("OnEnter", RowEnter)
    r:SetScript("OnLeave", RowLeave)
    -- Fade in while gliding in: a zero-length jump left, then the way back.
    r.show = r:CreateAnimationGroup()
    Anim(r.show, "Translation", 1, 0):SetOffset(-SLIDE, 0)
    Anim(r.show, "Translation", 2, FADE_IN, "OUT"):SetOffset(SLIDE, 0)
    local appear = Anim(r.show, "Alpha", 2, FADE_IN, "OUT")
    appear:SetFromAlpha(0)
    appear:SetToAlpha(1)
    r.show:SetScript("OnFinished", ShowDone)
    -- Wait (the start delay, set by StyleRow), fade out, free the row.
    r.fade = r:CreateAnimationGroup()
    r.fade.alpha = Anim(r.fade, "Alpha", 1, FADE_OUT, "IN_OUT")
    r.fade.alpha:SetFromAlpha(1)
    r.fade.alpha:SetToAlpha(0)
    r.fade:SetScript("OnFinished", FadeDone)
    return r
end

-- Fills a row from its data: icon, text (first line), sub (second line,
-- optional), value (right side, optional), badge (Icon Tray tile text),
-- border (quality colour, optional). Box rows keep their one-line form
-- (flat) and show no quest line.
local function Fill(r)
    local d, PP, style = r.data, EllesmereUI.PP, Get("style")
    local text, sub, value = d.text, d.sub or d.questSub, d.value
    if style == "BOX" then
        sub = not d.flat and d.sub or nil
        if d.flat then text, value = d.flat, nil end
    elseif style == "TRAY" then
        sub = nil
    end
    r.icon:SetTexture(d.icon)
    r.name:SetText(text)
    r.sub:SetText(sub or "")
    r.sub:SetShown(sub ~= nil)
    r.value:SetText(value or "")
    r.badge:SetText(d.badge or "")

    -- Auction house price: on the second line (SUB) or on the right side,
    -- under the vendor price (RIGHT). Tray tiles carry it in the name row.
    local ah = style ~= "TRAY" and d.ah or nil
    local ahPos, ox, oy = Get("ahPos"), Get("ahOffsetX"), Get("ahOffsetY")
    r.ah:SetText(ah or "")
    r.ah:SetShown(ah ~= nil)
    r.ah:ClearAllPoints()
    r.value:ClearAllPoints()
    local right = r.value -- what the name (and second line) stop short of
    if ah and ahPos == "RIGHT" then
        if value then
            r.value:SetPoint("BOTTOMRIGHT", r, "RIGHT", -6, 1)
            r.ah:SetPoint("TOPRIGHT", r, "RIGHT", -6 + ox, -1 + oy)
            if r.ah:GetStringWidth() > r.value:GetStringWidth() then right = r.ah end
        else
            r.value:SetPoint("RIGHT", -6, 0)
            r.ah:SetPoint("RIGHT", r, "RIGHT", -6 + ox, oy)
            right = r.ah
        end
    else
        r.value:SetPoint("RIGHT", -6, 0)
    end
    r.sub:ClearAllPoints()
    r.sub:SetPoint("TOPLEFT", r.icon, "RIGHT", 6, -1)
    local subLine = ah and ahPos == "SUB"
    if subLine then
        if sub then
            -- Item level first, the price after it on the same line.
            r.ah:SetPoint("LEFT", r.sub, "RIGHT", 8 + ox, oy)
        else
            r.ah:SetPoint("TOPLEFT", r.icon, "RIGHT", 6 + ox, -1 + oy)
        end
        r.ah:SetPoint("RIGHT", right, "LEFT", -8, 0)
    else
        r.sub:SetPoint("RIGHT", right, "LEFT", -8, 0)
    end
    r.name:ClearAllPoints()
    r.name:SetPoint("RIGHT", right, "LEFT", -8, 0)
    if sub or subLine then
        r.name:SetPoint("BOTTOMLEFT", r.icon, "RIGHT", 6, 1)
    else
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    end
    if style == "BAR" then r.bar:SetColorTexture(RowColor(d, true)) end
    if style == "TOAST" then
        if d.border and Get("qualityBorder") then
            r.iconBg:SetColorTexture(d.border.r, d.border.g, d.border.b, 1)
        else
            r.iconBg:SetColorTexture(TOAST.EDGE[1], TOAST.EDGE[2], TOAST.EDGE[3], 1)
        end
    end
    local size = Get("borderSize")
    if size > 0 and style ~= "BAR" then
        local br, bg, bb
        if style == "TOAST" then
            br, bg, bb = TOAST.GOLD[1], TOAST.GOLD[2], TOAST.GOLD[3]
        else
            br, bg, bb = RowColor(d, false)
        end
        PP.UpdateBorder(r, size, br, bg, bb, 1)
        PP.ShowBorder(r)
    else
        PP.HideBorder(r)
    end
    if d.alert and Get("alertPulse") and not r.preview then
        StartPulse(r)
    else
        StopPulse(r)
    end
end

local function FindRow(key)
    for _, r in ipairs(active) do
        if r.key == key then return r end
    end
end

-- While the options preview collects its samples, the Show functions add
-- their rows to this list (newest first) instead of the feed.
local collect

-- amount plus what the row showing key already adds up to.
local function Total(key, amount)
    if collect then return amount end
    local r = FindRow(key)
    return amount + (r and r.data.amount or 0)
end

-- Shows data under key: the row already showing key is refilled, moved to the
-- front and its fade restarted; otherwise a row is taken (the oldest one when
-- all maxRows are in use) and fades in.
local function Push(key, data)
    local r = FindRow(key)
    local fresh = not r
    if r then
        Unlist(r)
    else
        while #active >= Get("maxRows") do Release(active[#active]) end
        r = table.remove(pool) or NewRow()
        StyleRow(r)
    end
    table.insert(active, 1, r)
    r.key, r.data = key, data
    Fill(r)
    Layout()
    local wasAlert = r.alertShown
    r.alertShown = data.alert
    if fresh then
        r.fade:Stop()
        r:SetAlpha(0)
        r:Show()
        r.show:Play()
        if ShouldShine(data) then PlayShine(r, data.border) end
    else
        ArmFade(r)
        -- A stack that just became valuable gets its sweep now.
        if data.alert and not wasAlert and ShouldShine(data) then PlayShine(r, data.border) end
    end
end

local function Emit(key, data)
    if collect then
        collect[#collect + 1] = data
    else
        Push(key, data)
    end
end

-------------------------------------------------------------------------------
--  Sources
-------------------------------------------------------------------------------
local function Money(copper, size)
    return C_CurrencyInfo.GetCoinTextureString(copper, size or Get("textSize"))
end

-- The money row icon: by the largest coin, or always gold.
local function MoneyIcon(copper)
    if Get("coinIcon") ~= "DYNAMIC" then return MONEY_ICON end
    if copper >= 10000 then return COIN_ICONS.gold end
    if copper >= 100 then return COIN_ICONS.silver end
    return COIN_ICONS.copper
end

-- Auction house price of one item, from Auctionator; nil without it or
-- without a price seen. Never lets an Auctionator error reach the feed.
local AH_CALLER = "EllesmereUI"
local function HasAH()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    return api and api.GetAuctionPriceByItemLink and true or false
end
local function AHPrice(link)
    if not HasAH() then return end
    local api = Auctionator.API.v1
    local ok, price
    if link:find("|H", 1, true) then
        ok, price = pcall(api.GetAuctionPriceByItemLink, AH_CALLER, link)
    end
    if not (ok and type(price) == "number" and price > 0) then
        local id = C_Item.GetItemInfoInstant(link)
        if id and api.GetAuctionPriceByItemID then
            ok, price = pcall(api.GetAuctionPriceByItemID, AH_CALLER, id)
        end
    end
    if ok and type(price) == "number" and price > 0 then return price end
end

-- The largest coin only, for an Icon Tray badge.
local function ShortMoney(copper)
    local unit = copper >= 10000 and 10000 or copper >= 100 and 100 or 1
    return Money(copper - copper % unit)
end

-------------------------------------------------------------------------------
--  Session tracker data and loot history
--  Fed by real loot only (never the previews). Both are saved, so a /reload
--  keeps the running session and the list.
-------------------------------------------------------------------------------
local OnSessionChanged, OnHistoryChanged -- set by the panel / window below

local function SessionData()
    local c = S.Cfg()
    local d = c.data
    if not d then
        d = { start = time(), money = 0, vendor = 0, ah = 0, items = 0, agg = {} }
        c.data = d
    end
    if not d.agg then
        -- A session from before per-item prices: its item value stays as is.
        d.legacy, d.best, d.agg = d.best, nil, {}
    end
    return d
end

-------------------------------------------------------------------------------
--  Vendor or AH price per item
--  priceChoice[itemID] = "V" or "AH", set from the history window; without
--  one, grey items count at vendor price (Grey Items at Vendor Price) and the
--  rest at AH price (vendor when the AH has none).
-------------------------------------------------------------------------------
local function PriceChoice(id)
    local t = id and S.Read().priceChoice
    return t and t[id]
end

local function SetPriceChoice(id, mode)
    if not id then return end
    local c = S.Cfg()
    c.priceChoice = c.priceChoice or {}
    c.priceChoice[id] = mode
end

local function UsesVendor(id, quality)
    local choice = PriceChoice(id)
    if choice then return choice == "V" end
    return quality == 0 and S.Get("greyVendor") and true or false
end

-- Ignored items ("IGNORE") count for nothing in the session.
local function Ignored(id)
    return PriceChoice(id) == "IGNORE"
end

-- What the ignored items took off the session's raw sums.
local function IgnoredSums(d)
    local v, ah, n = 0, 0, 0
    for id, a in pairs(d.agg or {}) do
        if Ignored(id) then
            v, ah, n = v + a.v, ah + (a.a or 0), n + (a.n or 0)
        end
    end
    return v, ah, n
end

local function SessionVendor(d)
    local v = IgnoredSums(d)
    return math.max(0, d.vendor - v)
end

local function SessionAH(d)
    local _, ah = IgnoredSums(d)
    return math.max(0, d.ah - ah)
end

-- The session's items at their chosen price.
local function SessionItemsValue(d)
    local sum = d.legacy or 0
    for id, a in pairs(d.agg or {}) do
        if not Ignored(id) then
            sum = sum + (UsesVendor(id, a.q) and a.v or a.av)
        end
    end
    return sum
end

-- Paused: the clock stops and loot is not counted (the history still records).
local function SessionPaused()
    local d = S.Read().data
    return d and d.pausedAt ~= nil
end

local function TogglePause()
    local d = SessionData()
    if d.pausedAt then
        d.paused = (d.paused or 0) + (time() - d.pausedAt)
        d.pausedAt = nil
    else
        d.pausedAt = time()
    end
    if OnSessionChanged then OnSessionChanged() end
end

local function ResetSession()
    S.Cfg().data = nil
    SessionData()
    if OnSessionChanged then OnSessionChanged() end
end

-- History entries, newest first: t (time), icon, text, link, value (copper).
local function AddHistory(e)
    if not S.Get("history") then return end
    local c = S.Cfg()
    local list = c.historyList
    if not list then
        list = {}
        c.historyList = list
    end
    e.t = time()
    table.insert(list, 1, e)
    for i = #list, S.Get("historyMax") + 1, -1 do list[i] = nil end
    if OnHistoryChanged then OnHistoryChanged() end
end

-- Drops the entries over the limit (after the limit is lowered).
local function TrimHistory()
    local list = S.Read().historyList
    if not list then return end
    for i = #list, S.Get("historyMax") + 1, -1 do list[i] = nil end
    if OnHistoryChanged then OnHistoryChanged() end
end

local function ClearHistory()
    S.Cfg().historyList = nil
    if OnHistoryChanged then OnHistoryChanged() end
end

-- Whether real loot needs reading even when the feed would not show it.
local function Tracking()
    return S.Enabled() or (S.Get("history") and Enabled())
end

local function TrackItem(link, text, icon, count, vendorTotal, ahTotal, quality)
    if S.Enabled() and not SessionPaused() then
        local d = SessionData()
        d.items = d.items + count
        d.vendor = d.vendor + vendorTotal
        d.ah = d.ah + (ahTotal or 0)
        -- Per item: vendor total, and AH total with vendor standing in for
        -- loot the AH had no price for.
        local id = C_Item.GetItemInfoInstant(link) or ("?" .. link)
        local a = d.agg[id] or { v = 0, av = 0, a = 0, n = 0 }
        a.v, a.av, a.q = a.v + vendorTotal, a.av + (ahTotal or vendorTotal), quality
        a.a, a.n = (a.a or 0) + (ahTotal or 0), (a.n or 0) + count
        d.agg[id] = a
        if OnSessionChanged then OnSessionChanged() end
    end
    if count > 1 then text = count .. "x " .. text end
    AddHistory({ icon = icon, text = text, link = link, quality = quality, id = C_Item.GetItemInfoInstant(link),
        vendor = vendorTotal, ah = ahTotal })
end

local function TrackMoney(copper)
    if S.Enabled() and not SessionPaused() then
        local d = SessionData()
        d.money = d.money + copper
        if OnSessionChanged then OnSessionChanged() end
    end
    if S.Get("historyMoney") then
        AddHistory({ icon = MoneyIcon(copper), text = EllesmereUI.L("Money"), value = copper, money = true })
    end
end

-------------------------------------------------------------------------------
--  Item extras: bag count, valuable-loot alert
-------------------------------------------------------------------------------
local function BagCount(link)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not fn then return 0 end
    local ok, n = pcall(fn, link)
    return ok and type(n) == "number" and n or 0
end

-- base (item level or quest line) plus "N in bags" when Show Bag Count is on.
-- sample: a stand-in count for previews of items the player does not carry.
local function ItemSub(base, link, sample)
    if not (link and Get("showBagCount")) then return base end
    local n = BagCount(link)
    if n <= 0 then n = sample or 0 end
    if n <= 0 then return base end
    local bags = string.format("%d in bags", n)
    return base and (base .. ",  " .. bags) or bags
end

local function AlertThreshold()
    return Get("alertGold") * 10000 + Get("alertSilver") * 100
end

-- Whether a stack worth vendorTotal / ahTotal counts as valuable.
local function IsValuable(vendorTotal, ahTotal)
    if not Get("alertEnabled") then return false end
    local src, worth = Get("alertSource"), 0
    if src == "AH" then
        worth = ahTotal or 0
    elseif src == "VENDOR" then
        worth = vendorTotal
    else
        worth = math.max(ahTotal or 0, vendorTotal)
    end
    local limit = AlertThreshold()
    return limit > 0 and worth >= limit
end

local function PlayAlertSound()
    if not Get("alertSoundOn") then return end
    local id = SOUNDKIT and SOUNDKIT[Get("alertSound")]
    if id then PlaySound(id, "Master") end
end

-- Grey items in one row: count and vendor value add up.
local function ShowJunk(icon, count, unitVendor)
    local prev = not collect and FindRow("junk")
    local n = count + (prev and prev.data.amount or 0)
    local copper = unitVendor * count + (prev and prev.data.copper or 0)
    local c = ITEM_QUALITY_COLORS[0] or ITEM_QUALITY_COLORS[1]
    Emit("junk", { icon = icon, text = c.hex .. "Junk|r x" .. n, value = copper > 0 and Money(copper) or nil,
        amount = n, copper = copper, border = c, quality = 0, badge = n })
end

-- track: real loot (counted in the session and history); otherwise a sample.
local function ShowItem(link, count, retried, track)
    local name, fullLink, quality, itemLevel, _, _, _, _, _, icon, sellPrice, classID = C_Item.GetItemInfo(link)
    if not name then
        -- Not cached yet: try again once the client has it. Only once: the
        -- client also calls back when the item fails to load.
        if not retried then
            Item:CreateFromItemLink(link):ContinueOnItemLoad(function() ShowItem(link, count, true, track) end)
        end
        return
    end
    quality = quality or 1
    local itemLink = fullLink or link
    local unitVendor = sellPrice or 0
    local unitAH = AHPrice(itemLink)
    local color = ITEM_QUALITY_COLORS[quality] or ITEM_QUALITY_COLORS[1]
    if track then
        TrackItem(itemLink, color.hex .. name .. "|r", icon, count, unitVendor * count, unitAH and unitAH * count,
            quality)
        if not (Enabled() and Get("items")) then return end
    end
    if quality < Get("minQuality") then return end
    if quality == 0 and Get("junkMerge") then return ShowJunk(icon, count, unitVendor) end
    local key = "item:" .. link
    local prev = not collect and FindRow(key)
    count = Total(key, count)
    local text = color.hex .. name .. "|r"
    if count > 1 then text = count .. "x " .. text end
    local base, questSub
    if Get("showIlvl") and (classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor) then
        local ilvl = C_Item.GetDetailedItemLevelInfo(link) or itemLevel
        if ilvl and ilvl > 0 then base = EllesmereUI.Lf("ilvl: %d", ilvl) end
    elseif classID == Enum.ItemClass.Questitem and ITEM_BIND_QUEST then
        questSub = "|cffffd100" .. ITEM_BIND_QUEST .. "|r"
    end
    local bagBase = base
    if questSub and Get("showBagCount") then
        bagBase, questSub = questSub, nil
    end
    -- Samples (previews) show a made-up bag count so the setting is visible.
    local sub = ItemSub(bagBase, itemLink, not track and (count + 7) or nil)
    local vendorTotal = unitVendor * count
    local ahTotal = unitAH and unitAH * count
    local value = Get("showPrice") and vendorTotal > 0 and Money(vendorTotal) or nil
    local ah
    if Get("showAHPrice") and ahTotal then
        ah = Money(ahTotal, Get("ahTextSize"))
        if Get("ahLabel") then ah = "AH " .. ah end
    end
    -- Items set to vendor price (grey ones by default) never alert on an AH price.
    local itemID = C_Item.GetItemInfoInstant(itemLink)
    local alert = not Ignored(itemID) and IsValuable(vendorTotal,
        not UsesVendor(itemID, quality) and ahTotal or nil)
    if alert and track and not (prev and prev.data.alert) then PlayAlertSound() end
    Emit(key, { icon = icon, text = text, sub = sub, questSub = questSub, value = value, border = color, link = link,
        amount = count, badge = count > 1 and count or nil, ah = ah, quality = quality, alert = alert,
        bagBase = bagBase, bagLink = track and itemLink or nil })
end

-- After the bags settle the counts include what was just looted.
local function RefreshBagCounts()
    for _, r in ipairs(active) do
        local d = r.data
        if d and d.bagLink then
            d.sub = ItemSub(d.bagBase, d.bagLink)
            Fill(r)
        end
    end
end

local function ShowMoney(copper, track)
    if track then
        TrackMoney(copper)
        if not (Enabled() and Get("money")) then return end
    end
    copper = Total("money", copper)
    Emit("money", { icon = MoneyIcon(copper), text = EllesmereUI.L("Money"), value = Money(copper), amount = copper,
        badge = ShortMoney(copper) })
end

-- A faction's or skill line's data by name. ids keeps the id a scan of the
-- (expanded) list found, so later lookups go straight to it.
local factionIDs, skillIDs = {}, {}
local function Lookup(ids, name, byID, count, byIndex, idKey)
    local id = ids[name]
    if id then return byID(id) end
    for i = 1, count() do
        local d = byIndex(i)
        if d and d.name == name then
            ids[name] = d[idKey]
            return d
        end
    end
end

-- With the progress within the current standing.
local function ShowReputation(faction, delta)
    local key = "rep:" .. faction
    delta = Total(key, delta)
    local change = (delta >= 0 and "|cff00ff00+" or "|cffff4040") .. delta .. "|r"
    local flat = change .. " " .. faction
    local d = Lookup(factionIDs, faction, C_Reputation.GetFactionDataByID, C_Reputation.GetNumFactions,
        C_Reputation.GetFactionDataByIndex, "factionID")
    local progress
    if d then
        progress = string.format("%s / %s", BreakUpLargeNumbers(d.currentStanding - d.currentReactionThreshold),
            BreakUpLargeNumbers(d.nextReactionThreshold - d.currentReactionThreshold))
        flat = flat .. " (" .. progress .. ")"
    end
    Emit(key, { icon = REP_ICON, text = faction, sub = progress, value = change, flat = flat, badge = change,
        amount = delta })
end

-- With the total held, red at the cap.
local function ShowCurrency(id, change)
    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    if not (info and info.name) then return end
    local key = "currency:" .. id
    change = Total(key, change)
    local total = BreakUpLargeNumbers(info.quantity)
    if info.maxQuantity > 0 then
        total = total .. " / " .. BreakUpLargeNumbers(info.maxQuantity)
        if info.quantity >= info.maxQuantity then total = "|cffff4040" .. total .. "|r" end
    end
    local text = change .. "x " .. info.name
    Emit(key, { icon = info.iconFileID, text = text, sub = total, flat = text .. " (" .. total .. ")", badge = change,
        amount = change })
end

local function ShowSkill(skill, rank)
    local d = Lookup(skillIDs, skill, C_SkillInfo.GetSkillLineInfoByID, C_SkillInfo.GetNumSkillLines,
        C_SkillInfo.GetSkillLineInfo, "skillID")
    local max = d and d.maxRank > 0 and (" / " .. d.maxRank) or ""
    Emit("skill:" .. skill, { icon = SKILL_ICON, text = skill, value = rank .. max, badge = rank,
        flat = skill .. " " .. EllesmereUI.COLOR_CODES.WHITE .. rank .. max .. "|r" })
end

-- Own loot only: the *_SELF lines, the multiple-item formats (link and count)
-- first, since the single-item ones match their lines too.
local ITEM_KEYS = {
    "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF",
    "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF",
    "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "LOOT_ITEM_BONUS_ROLL_SELF",
}

local function OnLoot(text)
    for _, key in ipairs(ITEM_KEYS) do
        local link, count = Match(key, text)
        if link then
            if link:find("|Hitem:", 1, true) then ShowItem(link, tonumber(count) or 1, false, true) end
            return
        end
    end
end

-- Money lines spell out each coin with the client's own "%d Gold" etc.
local COIN_KEYS = { GOLD_AMOUNT = 10000, SILVER_AMOUNT = 100, COPPER_AMOUNT = 1 }
-- Coin icons instead of coin names ("3 [gold] 27 [silver] 40 [copper]").
local COIN_ICON_KEYS = { gold = 10000, silver = 100, copper = 1 }
local function CoinsFromIcons(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local copper = 0
    for coin, mult in pairs(COIN_ICON_KEYS) do
        local n = text:match("(%d+)%s*|[TA][^|]-" .. coin) or text:match("(%d+)%s*|[TA][^|]-" .. coin:gsub("^%l", string.upper))
        if n then copper = copper + tonumber(n) * mult end
    end
    return copper
end

local mailOpen -- while the mailbox is open its money comes from the money change

local function OnMoney(text)
    if mailOpen then return end
    local copper = 0
    for key, mult in pairs(COIN_KEYS) do
        local n = Match(key, text, true)
        if n then copper = copper + tonumber(n) * mult end
    end
    if copper == 0 then copper = CoinsFromIcons(text) end
    if copper > 0 then ShowMoney(copper, true) end
end

-- Mailbox money: the feed row "Mailbox", the history, and the session only
-- when Count Mailbox Money is on.
local function ShowMailMoney(copper)
    if S.Enabled() and S.Get("mailToSession") and not SessionPaused() then
        local d = SessionData()
        d.money = d.money + copper
        if OnSessionChanged then OnSessionChanged() end
    end
    if S.Get("historyMoney") then
        AddHistory({ icon = MoneyIcon(copper), text = "Mailbox", value = copper, money = true })
    end
    if not (Enabled() and Get("mailMoney")) then return end
    copper = Total("mailmoney", copper)
    Emit("mailmoney", { icon = MoneyIcon(copper), text = "Mailbox", value = Money(copper), amount = copper,
        badge = ShortMoney(copper) })
end

local lastMoney
local mailWatch = CreateFrame("Frame")
mailWatch:RegisterEvent("MAIL_SHOW")
mailWatch:RegisterEvent("MAIL_CLOSED")
mailWatch:RegisterEvent("PLAYER_MONEY")
mailWatch:SetScript("OnEvent", function(_, event)
    if event == "MAIL_SHOW" then
        mailOpen, lastMoney = true, GetMoney()
    elseif event == "MAIL_CLOSED" then
        mailOpen = nil
    elseif mailOpen then
        local now = GetMoney()
        local delta = now - (lastMoney or now)
        lastMoney = now
        -- Postage and COD payments lower the money: not a gain.
        if delta > 0 then ShowMailMoney(delta) end
    end
end)

local function OnFaction(text)
    local faction, amount = Match("FACTION_STANDING_INCREASED", text)
    if faction then return ShowReputation(faction, tonumber(amount)) end
    faction, amount = Match("FACTION_STANDING_DECREASED", text)
    if faction then return ShowReputation(faction, -tonumber(amount)) end
end

local function OnSkill(text)
    local skill, rank = Match("SKILL_RANK_UP", text)
    if skill then ShowSkill(skill, tonumber(rank)) end
end

local CHAT_EVENTS = {
    CHAT_MSG_LOOT = { setting = "items", handler = OnLoot },
    CHAT_MSG_MONEY = { setting = "money", handler = OnMoney },
    CHAT_MSG_COMBAT_FACTION_CHANGE = { setting = "reputation", handler = OnFaction },
    CHAT_MSG_SKILL = { setting = "skills", handler = OnSkill },
}

local function OnEvent(_, event, ...)
    local chat = CHAT_EVENTS[event]
    if chat then
        local text = Plain((...), "string")
        if text then chat.handler(text) end
    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        local id, _, change = ...
        id, change = Plain(id, "number"), Plain(change, "number")
        if id and change and change > 0 then ShowCurrency(id, change) end
    elseif event == "BAG_UPDATE_DELAYED" then
        RefreshBagCounts()
    end
end

-------------------------------------------------------------------------------
--  Setup
-------------------------------------------------------------------------------
local RefreshPreview

local function ApplyStyle()
    RefreshPreview()
    if not anchor then return end
    anchor:SetSize(Get("width"), AnchorHeight())
    -- Pooled rows are styled when Push takes them.
    for _, r in ipairs(active) do
        StyleRow(r)
        Fill(r)
    end
    while #active > Get("maxRows") do Release(active[#active]) end
    Layout()
end

local function CreateAnchor()
    if anchor then return end
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetFrameStrata("MEDIUM")
    feed.frame = anchor
    ApplyStyle()
    F.Place(anchor)
end

local function ClearRows()
    while active[1] do Release(active[1]) end
end

local function Apply()
    if events then events:UnregisterAllEvents() end
    local feedOn, track = Enabled(), Tracking()
    if not feedOn then ClearRows() end
    if not (feedOn or track) then return end
    if feedOn then CreateAnchor() end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    if feedOn then
        for event, chat in pairs(CHAT_EVENTS) do
            if Get(chat.setting) then events:RegisterEvent(event) end
        end
        if Get("currency") then events:RegisterEvent("CURRENCY_DISPLAY_UPDATE") end
        if Get("showBagCount") then events:RegisterEvent("BAG_UPDATE_DELAYED") end
    end
    -- The session and the history count loot the feed may not show.
    if track then
        events:RegisterEvent("CHAT_MSG_LOOT")
        events:RegisterEvent("CHAT_MSG_MONEY")
    end
end

-- A sample of every enabled source: the player's capital for reputation and
-- classic items of three qualities (item id / count pairs). The rows fade like
-- real ones.
-- Legendary, epic, rare, uncommon, two common stacks and a grey item.
local PREVIEW_ITEMS = { 19019, 1, 12640, 1, 273643, 1, 7909, 2, 14047, 12, 4306, 5, 4865, 3 } -- rare: Worgenbane Talisman
local function Preview()
    if not Enabled() then return end
    CreateAnchor()
    ClearRows()
    if Get("skills") then ShowSkill(EllesmereUI.L("Swords"), 42) end
    if Get("reputation") then
        local capital = C_Reputation.GetFactionDataByID(UnitFactionGroup("player") == "Horde" and 76 or 72)
        if capital then ShowReputation(capital.name, 250) end
    end
    if Get("money") then ShowMoney(12345) end
    if Get("items") then
        for i = 1, #PREVIEW_ITEMS, 2 do ShowItem("item:" .. PREVIEW_ITEMS[i], PREVIEW_ITEMS[i + 1]) end
    end
end

-------------------------------------------------------------------------------
--  Options preview: the same rows with a sample of every enabled source,
--  drawn in the options content header. Built when the Loot page first
--  opens; it never fades and listens to no events.
-------------------------------------------------------------------------------
local preview -- row set plus its view and every row frame made so far

local requested = {} -- preview items asked of the client, once each

-- The Preview samples, newest first, as data. An item the client has not
-- cached yet is asked for once a session and redraws the preview when its
-- load ends; the client also calls back when the load fails, so asking again
-- from the redraw would never stop.
local function PreviewSamples()
    local list, items = {}, Get("items")
    collect = list
    if items then
        for i = 1, #PREVIEW_ITEMS, 2 do
            local link = "item:" .. PREVIEW_ITEMS[i]
            if C_Item.GetItemInfo(link) then ShowItem(link, PREVIEW_ITEMS[i + 1]) end
        end
    end
    if Get("money") then ShowMoney(12345) end
    if Get("reputation") then
        local capital = C_Reputation.GetFactionDataByID(UnitFactionGroup("player") == "Horde" and 76 or 72)
        if capital then ShowReputation(capital.name, 250) end
    end
    if Get("skills") then ShowSkill(EllesmereUI.L("Swords"), 42) end
    collect = nil
    -- Asked for once the samples are in: the callback can run right away.
    if items then
        for i = 1, #PREVIEW_ITEMS, 2 do
            local id = PREVIEW_ITEMS[i]
            if not requested[id] and not C_Item.GetItemInfo(id) then
                requested[id] = true
                Item:CreateFromItemID(id):ContinueOnItemLoad(function() RefreshPreview() end)
            end
        end
    end
    return list
end

-- force: draw while the header is still being built (not shown yet).
RefreshPreview = function(force)
    local v = preview
    if not (v and (force or v.view:IsVisible())) then return end
    local samples = PreviewSamples()
    local n = math.min(#samples, Get("maxRows"))
    for i = 1, n do
        local r = v.all[i]
        if not r then
            r = NewRow(v.frame)
            r.preview = true
            v.all[i] = r
        end
        r.data = samples[i]
        StyleRow(r)
        Fill(r)
        r:SetAlpha(1)
        r:Show()
        v.rows[i] = r
    end
    for i = n + 1, #v.all do
        v.all[i]:Hide()
        v.rows[i] = nil
    end
    local w = Get("width")
    local h = n > 0 and AnchorHeight(n) or Get("rowHeight")
    local pw = v.view:GetParent():GetWidth()
    local available = (pw > 0 and pw) or v.availableWidth or w + 40
    local scale = math.min(1, math.max(100, available - 40) / w)
    v.frame:SetSize(w, h)
    v.frame:SetScale(scale)
    Layout(v)
    v.previewHeight = h * scale + 30
    v.view:SetHeight(v.previewHeight)
    if v.onHeightChanged then v.onHeightChanged(v.previewHeight) end
end

local hookedParents = {}
local function CreateSettingsPreview(parent, availableWidth, onHeightChanged)
    local v = preview
    if not v then
        v = { rows = {}, all = {} }
        v.view = CreateFrame("Frame", nil, parent)
        v.frame = CreateFrame("Frame", nil, v.view)
        v.frame:SetPoint("CENTER")
        v.view:SetScript("OnShow", function() RefreshPreview() end)
        preview = v
    end
    -- Frames outlive a page rebuild, so the view is reused.
    v.availableWidth, v.onHeightChanged = availableWidth, onHeightChanged
    v.view:SetParent(parent)
    v.view:ClearAllPoints()
    v.view:SetPoint("TOPLEFT")
    v.view:SetPoint("TOPRIGHT")
    if not hookedParents[parent] then
        hookedParents[parent] = true
        local lastWidth
        parent:HookScript("OnSizeChanged", function(_, width)
            if width == lastWidth then return end
            lastWidth = width
            if v.view:GetParent() == parent then RefreshPreview() end
        end)
    end
    v.view:Show()
    RefreshPreview(true)
    return v
end

-------------------------------------------------------------------------------
--  Session panel: money, item values, total and per hour since the last
--  reset. Left-click opens the loot history, Shift+Right-click resets.
-------------------------------------------------------------------------------
local panel, ticker
local SESSION_LINES = { "Money", "Items (Vendor)", "Items (AH)", "Total", "Per Hour" }
local PAD = 6

local function PanelLineHeight()
    return S.Get("textSize") + 6
end

local function PanelHeight()
    return PAD * 2 + (#SESSION_LINES + 1) * PanelLineHeight()
end

local function SMoney(copper)
    return C_CurrencyInfo.GetCoinTextureString(math.max(0, math.floor(copper)), S.Get("textSize"))
end

-- Running time without the paused stretches.
local function Elapsed(d)
    local now = d.pausedAt or time()
    return math.max(0, now - (d.start or now) - (d.paused or 0))
end

local function Clock(secs)
    return string.format("%d:%02d:%02d", math.floor(secs / 3600), math.floor(secs / 60) % 60, secs % 60)
end

local function SessionTotal(d)
    local basis = S.Get("basis")
    if basis == "VENDOR" then return d.money + SessionVendor(d) end
    if basis == "MONEY" then return d.money end
    return d.money + SessionItemsValue(d)
end

local function UpdatePanel()
    if not (panel and panel:IsShown()) then return end
    local d = SessionData()
    local secs = Elapsed(d)
    local total = SessionTotal(d)
    local paused = d.pausedAt ~= nil
    -- Short title: the clock and the Pause / X buttons share the row.
    panel.title:SetText(paused and "Session |cffff9933(paused)|r" or "Session")
    panel.clock:SetText(paused and ("|cff808080" .. Clock(secs) .. "|r") or Clock(secs))
    panel.pause.label:SetText(paused and "Resume" or "Pause")
    panel.pause:SetWidth(panel.pause.label:GetStringWidth() + 10)
    local vals = panel.vals
    vals[1]:SetText(SMoney(d.money))
    vals[2]:SetText(SMoney(SessionVendor(d)))
    vals[3]:SetText(HasAH() and SMoney(SessionAH(d)) or "|cff808080n/a|r")
    vals[4]:SetText(SMoney(total))
    if secs >= 60 then
        local per = total * 3600 / secs
        vals[5]:SetText(SMoney(per - per % 100)) -- to the silver
    else
        vals[5]:SetText("|cff808080...|r")
    end
end

local ToggleHistory -- defined with the window below
local SetSessionEnabled -- defined with the session setup below

local function StylePanel()
    if not panel then return end
    local size, lh = S.Get("textSize"), PanelLineHeight()
    panel:SetSize(S.Get("width"), PanelHeight())
    panel.bg:SetColorTexture(0.05, 0.05, 0.05, S.Get("bgA"))
    StyleFont(panel.title, size)
    StyleFont(panel.clock, size)
    panel.title:SetTextColor(Accent())
    panel.pause.bg:SetVertexColor(Accent())
    panel.close.bg:SetVertexColor(Accent())
    panel.title:ClearAllPoints()
    panel.title:SetPoint("TOPLEFT", PAD + 2, -PAD - 3)
    StyleFont(panel.pause.label, size - 2)
    panel.pause:SetHeight(size + 4)
    StyleFont(panel.close.label, size - 2)
    panel.close:SetSize(size + 4, size + 4)
    panel.close:ClearAllPoints()
    panel.close:SetPoint("TOPRIGHT", -PAD, -PAD - 1)
    panel.pause:ClearAllPoints()
    panel.pause:SetPoint("RIGHT", panel.close, "LEFT", -3, 0)
    panel.clock:ClearAllPoints()
    panel.clock:SetPoint("RIGHT", panel.pause, "LEFT", -6, 0)
    for i = 1, #SESSION_LINES do
        local l, v = panel.labels[i], panel.vals[i]
        StyleFont(l, size - 1)
        StyleFont(v, size)
        l:ClearAllPoints()
        v:ClearAllPoints()
        local y = -PAD - 3 - i * lh
        l:SetPoint("TOPLEFT", PAD + 2, y)
        v:SetPoint("TOPRIGHT", -PAD - 2, y)
        l:SetTextColor(0.75, 0.75, 0.75)
        -- Total and Per Hour stand out.
        if i >= 4 then v:SetTextColor(1, 1, 1) else v:SetTextColor(0.9, 0.9, 0.9) end
    end
    UpdatePanel()
end

local function CreatePanel()
    if panel then return end
    panel = CreateFrame("Frame", nil, UIParent)
    panel:SetFrameStrata("MEDIUM")
    panel.bg = panel:CreateTexture(nil, "BACKGROUND")
    panel.bg:SetAllPoints()
    EllesmereUI.PP.CreateBorder(panel, 0, 0, 0, 1, 1, "OVERLAY", 1)
    panel.title = panel:CreateFontString(nil, "OVERLAY")
    panel.clock = panel:CreateFontString(nil, "OVERLAY")
    panel.labels, panel.vals = {}, {}
    for i, label in ipairs(SESSION_LINES) do
        -- A font comes first: SetText on a font string without one errors.
        local l = panel:CreateFontString(nil, "OVERLAY")
        local v = panel:CreateFontString(nil, "OVERLAY")
        StyleFont(l, S.Get("textSize") - 1)
        StyleFont(v, S.Get("textSize"))
        l:SetText(label)
        panel.labels[i] = l
        panel.vals[i] = v
    end
    StyleFont(panel.title, S.Get("textSize"))
    StyleFont(panel.clock, S.Get("textSize"))
    -- Pause / Resume button in the title row.
    local pb = CreateFrame("Button", nil, panel)
    pb.bg = pb:CreateTexture(nil, "BACKGROUND")
    pb.bg:SetAllPoints()
    pb.bg:SetColorTexture(1, 1, 1, 1)
    pb.bg:SetVertexColor(Accent())
    pb.bg:SetAlpha(0.18)
    pb.label = pb:CreateFontString(nil, "OVERLAY")
    StyleFont(pb.label, S.Get("textSize") - 2)
    pb.label:SetPoint("CENTER")
    pb.label:SetText("Pause")
    pb:SetSize(pb.label:GetStringWidth() + 10, S.Get("textSize") + 4)
    pb:SetScript("OnClick", function() TogglePause() end)
    pb:SetScript("OnEnter", function(self)
        self.bg:SetAlpha(0.35)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(SessionPaused() and "Resume the session" or "Pause the session")
        GameTooltip:AddLine("While paused the timer stops and loot is not counted.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    pb:SetScript("OnLeave", function(self)
        self.bg:SetAlpha(0.18)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    panel.pause = pb
    -- Close: hides the panel and turns the Farming Session off.
    local cb = CreateFrame("Button", nil, panel)
    cb.bg = cb:CreateTexture(nil, "BACKGROUND")
    cb.bg:SetAllPoints()
    cb.bg:SetColorTexture(1, 1, 1, 1)
    cb.bg:SetVertexColor(Accent())
    cb.bg:SetAlpha(0.18)
    cb.label = cb:CreateFontString(nil, "OVERLAY")
    StyleFont(cb.label, S.Get("textSize") - 2)
    cb.label:SetPoint("CENTER", 0, 0)
    cb.label:SetText("X")
    cb:SetSize(S.Get("textSize") + 4, S.Get("textSize") + 4)
    cb:SetScript("OnClick", function() SetSessionEnabled(false) end)
    cb:SetScript("OnEnter", function(self)
        -- Red on hover: closing also turns the tracker off.
        self.bg:SetVertexColor(0.8, 0.2, 0.2)
        self.bg:SetAlpha(0.6)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Close and turn off the Farming Session")
        GameTooltip:AddLine("The totals are kept. Turn it back on with /lootsession or in Dworak > Loot Tracker.",
            0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function(self)
        self.bg:SetVertexColor(Accent())
        self.bg:SetAlpha(0.18)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    panel.close = cb
    panel:EnableMouse(true)
    -- Drag to move (unless locked); the spot is saved where unlock mode keeps
    -- it, so both agree. A drag is not a click.
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self)
        if S.Get("locked") or ns.IsUnlocked() then return end
        self.dragging = true
        self:StartMoving()
    end)
    panel:SetScript("OnDragStop", function(self)
        if not self.dragging then return end
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        S.Cfg().pos = { point = point, relPoint = relPoint, x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
        S.Place(self)
        C_Timer.After(0, function() self.dragging = nil end)
    end)
    panel:SetScript("OnMouseUp", function(self, button)
        if self.dragging then return end
        if button == "LeftButton" then
            ToggleHistory()
        elseif button == "RightButton" and IsShiftKeyDown() then
            ResetSession()
        end
    end)
    panel:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Farming Session")
        local d = SessionData()
        local _, _, ignoredCount = IgnoredSums(d)
        GameTooltip:AddDoubleLine("Items looted", d.items - ignoredCount, 0.8, 0.8, 0.8, 1, 1, 1)
        if ignoredCount > 0 then
            GameTooltip:AddDoubleLine("Ignored items", ignoredCount, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: loot history", 0.6, 0.6, 0.6)
        if not S.Get("locked") then GameTooltip:AddLine("Drag: move", 0.6, 0.6, 0.6) end
        GameTooltip:AddLine("Shift+Right-click: reset session", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    panel:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    StylePanel()
end

OnSessionChanged = UpdatePanel

-------------------------------------------------------------------------------
--  Loot history window: the last loot, newest on top. Hover for the item
--  tooltip, Shift+click to link it in chat. Esc or the X closes it.
-------------------------------------------------------------------------------
local hist

-- Row height follows the History Text Size.
local function HistLine()
    return S.Get("histTextSize") + 10
end

-- Sizes and places row i for the current text size; skipped when nothing changed.
local function StyleHistoryLine(b, i)
    local size = S.Get("histTextSize")
    if b.styledSize == size and b.styledIndex == i then return end
    b.styledSize, b.styledIndex = size, i
    local lh = size + 10
    b:SetHeight(lh)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 0, -(i - 1) * lh)
    b:SetPoint("TOPRIGHT", 0, -(i - 1) * lh)
    b.icon:SetSize(lh - 4, lh - 4)
    b.time:SetWidth(math.ceil(size * 3.3))
    StyleFont(b.time, size - 1)
    StyleFont(b.text, size)
    StyleFont(b.value, size)
    b.time:SetTextColor(0.6, 0.6, 0.6)
end

local ShowPricePopup -- vendor / AH choice for a history entry, below
local RefreshIgnored = function() end -- the ignored items window, below
local ToggleIgnored -- opens / closes it, below

local function WindowBg(tex)
    tex:SetColorTexture(S.Get("histBgR"), S.Get("histBgG"), S.Get("histBgB"), S.Get("histBgA"))
end

-- Close with Esc: the windows are in UISpecialFrames only while it is on.
local ESC_FRAMES = { "EUI_LootHistoryFrame", "EUI_LootIgnoredFrame" }
local function UpdateEscClose()
    local on = S.Get("histEscClose")
    for _, name in ipairs(ESC_FRAMES) do
        local at
        for i, n in ipairs(UISpecialFrames) do
            if n == name then at = i break end
        end
        if on and not at and _G[name] then
            tinsert(UISpecialFrames, name)
        elseif not on and at then
            table.remove(UISpecialFrames, at)
        end
    end
end

-- The window border: size and colour from the settings, hidden at size 0.
local function WindowBorder(frame)
    local PP, size = EllesmereUI.PP, S.Get("histBorderSize")
    if size > 0 then
        PP.UpdateBorder(frame, size, S.Get("histBorderR"), S.Get("histBorderG"), S.Get("histBorderB"), 1)
        PP.ShowBorder(frame)
    else
        PP.HideBorder(frame)
    end
end

local function HistoryLine(i)
    local b = hist.lines[i]
    if b then return b end
    b = CreateFrame("Button", nil, hist.content)
    b:SetHeight(HistLine())
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 1)
    b.hl:SetVertexColor(Accent())
    b.hl:SetAlpha(0.10)
    b.hl:Hide()
    b.time = b:CreateFontString(nil, "OVERLAY")
    b.time:SetPoint("LEFT", 2, 0)
    b.time:SetWidth(38)
    b.time:SetJustifyH("LEFT")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(HistLine() - 4, HistLine() - 4)
    b.icon:SetPoint("LEFT", b.time, "RIGHT", 2, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.value = b:CreateFontString(nil, "OVERLAY")
    b.value:SetPoint("RIGHT", -4, 0)
    b.value:SetJustifyH("RIGHT")
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.text:SetPoint("RIGHT", b.value, "LEFT", -8, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    StyleHistoryLine(b, i)
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnEnter", function(self)
        self.hl:Show()
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            if self.entry and self.entry.id and (self.entry.vendor or self.entry.ah) then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Click: vendor or AH price, or ignore", 0.4, 0.78, 1)
                GameTooltip:AddLine("Shift+click: link in chat", 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.hl:Hide()
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    b:SetScript("OnClick", function(self)
        if self.link and IsModifiedClick("CHATLINK") then
            ChatEdit_InsertLink(self.link)
        elseif self.entry and self.entry.id and (self.entry.vendor or self.entry.ah) then
            ShowPricePopup(self, self.entry)
        end
    end)
    hist.lines[i] = b
    return b
end

-- An entry's value at its item's chosen price, tagged V (vendor) or AH.
local TAG_V, TAG_AH = " |cffa0a0a0V|r", " |cff66c7ffAH|r"
local function EntryValueText(e)
    if e.id and Ignored(e.id) then return "|cff808080ignored|r" end
    if e.vendor or e.ah then
        local useVendor = not e.ah or UsesVendor(e.id, e.quality)
        local v = useVendor and e.vendor or e.ah
        if not v or v <= 0 then return useVendor and "|cff808080no value|r" or "" end
        return C_CurrencyInfo.GetCoinTextureString(v, S.Get("histTextSize")) .. (useVendor and TAG_V or TAG_AH)
    end
    -- Money, and entries recorded before vendor / AH were kept apart.
    return e.value and e.value > 0 and C_CurrencyInfo.GetCoinTextureString(e.value, S.Get("histTextSize")) or ""
end

local function Shown(e)
    if e.money then return S.Get("historyMoney") end
    local q = e.quality
    if q == nil then return true end -- recorded before qualities were kept
    if q >= 5 then return true end -- Legendary+ has no filter chip
    return S.Get("histQ" .. math.max(q, 0)) ~= false
end

local function RefreshHistory()
    if not (hist and hist:IsShown()) then return end
    local list = S.Read().historyList or {}
    local n = 0
    for _, e in ipairs(list) do
        if Shown(e) then
            n = n + 1
            local b = HistoryLine(n)
            StyleHistoryLine(b, n)
            b.link, b.entry = e.link, e
            b.time:SetText(date("%H:%M", e.t or time()))
            b.icon:SetTexture(e.icon)
            b.text:SetText(e.text or "")
            b.value:SetText(EntryValueText(e))
            local ignored = e.id and Ignored(e.id)
            b.icon:SetDesaturated(ignored and true or false)
            b.text:SetAlpha(ignored and 0.45 or 1)
            b:Show()
        end
    end
    for i = n + 1, #hist.lines do hist.lines[i]:Hide() end
    hist.title:SetText(string.format("Loot History  |cff808080%d / %d|r", n, #list))
    hist.empty:SetText(#list == 0 and "No loot recorded yet." or "Nothing matches the filter.")
    hist.empty:SetShown(n == 0)
    hist.content:SetHeight(math.max(1, n * HistLine()))
    local max = math.max(0, hist.content:GetHeight() - hist.scroll:GetHeight())
    if hist.scroll:GetVerticalScroll() > max then hist.scroll:SetVerticalScroll(max) end
    for _, chip in ipairs(hist.chips) do chip:Update() end
end

-- Price choice popup: Vendor, AH or the default rule for the clicked item.
-- The choice is per item, so every entry of it and the session follow.
local popup
local function PopupButton(key, label)
    local btn = CreateFrame("Button", nil, popup)
    btn:SetHeight(20)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.label = btn:CreateFontString(nil, "OVERLAY")
    StyleFont(btn.label, 12)
    btn.label:SetPoint("LEFT", 8, 0)
    btn.label:SetPoint("RIGHT", -8, 0)
    btn.label:SetJustifyH("LEFT")
    btn.key = key
    btn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            local r, g, b = Accent()
            self.bg:SetColorTexture(r, g, b, 0.30)
        end
    end)
    btn:SetScript("OnLeave", function(self) self:Update() end)
    btn:SetScript("OnClick", function(self)
        SetPriceChoice(popup.id, self.key ~= "DEFAULT" and self.key or nil)
        popup:Hide()
        if OnSessionChanged then OnSessionChanged() end
        RefreshHistory()
        RefreshIgnored()
    end)
    function btn:Update()
        local choice = PriceChoice(popup.id)
        local selected = (self.key == "DEFAULT" and choice == nil) or self.key == choice
        local r, g, b = Accent()
        self.bg:SetColorTexture(r, g, b, selected and 0.20 or 0)
    end
    return btn
end

ShowPricePopup = function(line, e)
    if not popup then
        popup = CreateFrame("Frame", nil, hist)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetClampedToScreen(true)
        popup:SetWidth(250)
        popup:EnableMouse(true)
        popup.bg = popup:CreateTexture(nil, "BACKGROUND")
        popup.bg:SetAllPoints()
        popup.bg:SetColorTexture(0.08, 0.08, 0.08, 0.98)
        EllesmereUI.PP.CreateBorder(popup, 0.3, 0.3, 0.3, 1, 1, "OVERLAY", 1)
        popup.title = popup:CreateFontString(nil, "OVERLAY")
        StyleFont(popup.title, 12)
        popup.title:SetPoint("TOPLEFT", 8, -7)
        popup.title:SetPoint("TOPRIGHT", -8, -7)
        popup.title:SetJustifyH("LEFT")
        popup.title:SetWordWrap(false)
        popup.note = popup:CreateFontString(nil, "OVERLAY")
        StyleFont(popup.note, 10)
        popup.note:SetPoint("TOPLEFT", popup.title, "BOTTOMLEFT", 0, -3)
        popup.note:SetTextColor(0.6, 0.6, 0.6)
        popup.note:SetText("Counted for every loot of this item.")
        popup.vendor = PopupButton("V")
        popup.ah = PopupButton("AH")
        popup.default = PopupButton("DEFAULT")
        popup.ignore = PopupButton("IGNORE")
        popup.vendor:SetPoint("TOPLEFT", 2, -40)
        popup.vendor:SetPoint("TOPRIGHT", -2, -40)
        popup.ah:SetPoint("TOPLEFT", popup.vendor, "BOTTOMLEFT", 0, -1)
        popup.ah:SetPoint("TOPRIGHT", popup.vendor, "BOTTOMRIGHT", 0, -1)
        popup.default:SetPoint("TOPLEFT", popup.ah, "BOTTOMLEFT", 0, -1)
        popup.default:SetPoint("TOPRIGHT", popup.ah, "BOTTOMRIGHT", 0, -1)
        popup.ignore:SetPoint("TOPLEFT", popup.default, "BOTTOMLEFT", 0, -1)
        popup.ignore:SetPoint("TOPRIGHT", popup.default, "BOTTOMRIGHT", 0, -1)
        popup:SetHeight(40 + 4 * 21 + 4)
        popup:SetScript("OnHide", function(self) self.id = nil end)
    end
    if popup:IsShown() and popup.id == e.id then
        popup:Hide()
        return
    end
    popup.id = e.id
    popup.title:SetText(e.text or "")
    local function money(v)
        return v and v > 0 and C_CurrencyInfo.GetCoinTextureString(v, 12) or "|cff808080none|r"
    end
    popup.vendor.label:SetText("Vendor price:  " .. money(e.vendor))
    popup.ah.label:SetText("AH price:  " .. money(e.ah))
    popup.ah:SetEnabled(e.ah ~= nil)
    popup.ah.label:SetAlpha(e.ah and 1 or 0.4)
    local grey = e.quality == 0 and S.Get("greyVendor")
    popup.default.label:SetText("|cffa0a0a0Default (" .. (grey and "vendor, grey item" or "AH, vendor if none") .. ")|r")
    popup.vendor:Update()
    popup.ah:Update()
    popup.default:Update()
    popup.ignore.label:SetText("|cffff7070Ignore|r  |cff808080(not counted in the session)|r")
    popup.ignore:Update()
    popup:ClearAllPoints()
    popup:SetPoint("TOPRIGHT", line, "BOTTOMRIGHT", 0, -2)
    popup:Show()
end

-- Filter chips: one per quality, click to show or hide it in the list.
-- Filter chips P C U R E (Poor..Epic): square tiles in the quality's own
-- colour (deliberately NOT the UI accent), dimmed when that quality is hidden.
local CHIP_LETTERS = { [0] = "P", "C", "U", "R", "E" }
local CHIP_SIZE = 20
local function MakeChip(q, prev)
    local chip = CreateFrame("Button", nil, hist)
    chip:SetSize(CHIP_SIZE, CHIP_SIZE - 2)
    chip.bg = chip:CreateTexture(nil, "BACKGROUND")
    chip.bg:SetAllPoints()
    chip.label = chip:CreateFontString(nil, "OVERLAY")
    StyleFont(chip.label, 11)
    chip.label:SetPoint("CENTER", 0, 0)
    chip.label:SetText(CHIP_LETTERS[q])
    chip.label:SetShadowOffset(1, -1)
    chip.label:SetShadowColor(0, 0, 0, 1)
    local color = ITEM_QUALITY_COLORS[q] or ITEM_QUALITY_COLORS[1]
    local name = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
    if prev then
        chip:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    else
        chip:SetPoint("TOPLEFT", hist, "TOPLEFT", 8, -28)
    end
    function chip:Update()
        local on = S.Get("histQ" .. q) ~= false
        self.bg:SetColorTexture(color.r, color.g, color.b, on and 0.85 or 0.15)
        -- Light tiles (Poor grey, Common white) take dark text.
        local light = (color.r + color.g + color.b) / 3 > 0.6
        if light and on then
            self.label:SetTextColor(0.05, 0.05, 0.05)
            self.label:SetShadowColor(0, 0, 0, 0)
        else
            self.label:SetTextColor(1, 1, 1)
            self.label:SetShadowColor(0, 0, 0, 1)
        end
        self.label:SetAlpha(on and 1 or 0.45)
    end
    chip:SetScript("OnClick", function()
        S.Cfg()["histQ" .. q] = not (S.Get("histQ" .. q) ~= false)
        RefreshHistory()
    end)
    chip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(color.hex .. name .. "|r")
        GameTooltip:AddLine("Click to show or hide these items.", 1, 1, 1)
        GameTooltip:AddLine("Every item is still recorded.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    chip:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    return chip
end

local function SaveHistoryFrame()
    local c = S.Cfg()
    c.histW, c.histH = math.floor(hist:GetWidth() + 0.5), math.floor(hist:GetHeight() + 0.5)
    local point, _, relPoint, x, y = hist:GetPoint(1)
    c.histPos = { point = point, relPoint = relPoint, x = x, y = y }
end

local function CreateHistory()
    if hist then return end
    hist = CreateFrame("Frame", "EUI_LootHistoryFrame", UIParent)
    hist:SetSize(S.Get("histW"), S.Get("histH"))
    local pos = S.Read().histPos
    if pos and pos.point then
        hist:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        hist:SetPoint("CENTER")
    end
    hist:SetFrameStrata("DIALOG")
    hist:SetClampedToScreen(true)
    hist:SetMovable(true)
    hist:SetResizable(true)
    if hist.SetResizeBounds then
        hist:SetResizeBounds(260, 160, 900, 1200)
    elseif hist.SetMinResize then
        hist:SetMinResize(260, 160)
        hist:SetMaxResize(900, 1200)
    end
    hist:EnableMouse(true)
    hist:RegisterForDrag("LeftButton")
    hist:SetScript("OnDragStart", hist.StartMoving)
    hist:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveHistoryFrame()
    end)
    hist.bg = hist:CreateTexture(nil, "BACKGROUND")
    hist.bg:SetAllPoints()
    WindowBg(hist.bg)
    EllesmereUI.PP.CreateBorder(hist, 0, 0, 0, 1, 1, "OVERLAY", 1)
    WindowBorder(hist)
    hist.title = hist:CreateFontString(nil, "OVERLAY")
    hist.title:SetPoint("TOPLEFT", 10, -9)
    StyleFont(hist.title, 13)
    hist.title:SetTextColor(Accent())
    hist.accentLine = hist:CreateTexture(nil, "ARTWORK")
    hist.accentLine:SetPoint("TOPLEFT", 1, -1)
    hist.accentLine:SetPoint("TOPRIGHT", -1, -1)
    hist.accentLine:SetHeight(2)
    hist.accentLine:SetColorTexture(Accent())
    local close = CreateFrame("Button", nil, hist, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetFrameLevel(hist:GetFrameLevel() + 10)
    -- The template's own handler goes through HideUIPanel, which ignores
    -- frames that are not Blizzard UI panels.
    close:SetScript("OnClick", function() hist:Hide() end)
    hist.chips = {}
    local prev
    for q = 0, 4 do
        prev = MakeChip(q, prev)
        hist.chips[#hist.chips + 1] = prev
    end
    -- Clear button in the filter row: the first click asks, a second click
    -- within 3 seconds clears the whole history.
    local clr = CreateFrame("Button", nil, hist)
    clr:SetHeight(CHIP_SIZE - 2)
    clr:SetPoint("TOPRIGHT", hist, "TOPRIGHT", -8, -28)
    clr.bg = clr:CreateTexture(nil, "BACKGROUND")
    clr.bg:SetAllPoints()
    clr.bg:SetColorTexture(1, 1, 1, 1)
    clr.bg:SetVertexColor(Accent())
    clr.bg:SetAlpha(0.18)
    clr.label = clr:CreateFontString(nil, "OVERLAY")
    StyleFont(clr.label, 11)
    clr.label:SetPoint("CENTER")
    local function ClrIdle()
        clr.armed = nil
        clr.label:SetText("Clear")
        clr.label:SetTextColor(1, 1, 1)
        clr:SetWidth(clr.label:GetStringWidth() + 14)
        clr.bg:SetVertexColor(Accent())
        clr.bg:SetAlpha(clr:IsMouseOver() and 0.35 or 0.18)
    end
    clr.Idle = ClrIdle
    clr:SetScript("OnClick", function(self)
        if self.armed then
            ClearHistory()
            ClrIdle()
            return
        end
        self.armed = true
        self.label:SetText("Clear all?")
        self.label:SetTextColor(1, 0.85, 0.85)
        self:SetWidth(self.label:GetStringWidth() + 14)
        self.bg:SetVertexColor(0.8, 0.2, 0.2)
        self.bg:SetAlpha(0.6)
        C_Timer.After(3, function() if clr.armed then ClrIdle() end end)
    end)
    clr:SetScript("OnEnter", function(self)
        if not self.armed then self.bg:SetAlpha(0.35) end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Clear the loot history")
        GameTooltip:AddLine("Click twice to confirm. The session totals and the price choices are kept.",
            0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    clr:SetScript("OnLeave", function(self)
        if not self.armed then self.bg:SetAlpha(0.18) end
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    hist:HookScript("OnHide", ClrIdle)
    ClrIdle()
    hist.clear = clr
    -- Ignored items button, left of Clear: opens the ignored items window.
    local ib = CreateFrame("Button", nil, hist)
    ib:SetHeight(CHIP_SIZE - 2)
    ib:SetPoint("RIGHT", clr, "LEFT", -4, 0)
    ib.bg = ib:CreateTexture(nil, "BACKGROUND")
    ib.bg:SetAllPoints()
    ib.bg:SetColorTexture(1, 1, 1, 1)
    ib.bg:SetVertexColor(Accent())
    ib.bg:SetAlpha(0.18)
    ib.label = ib:CreateFontString(nil, "OVERLAY")
    StyleFont(ib.label, 11)
    ib.label:SetPoint("CENTER")
    ib.label:SetText("Ignored")
    ib:SetWidth(ib.label:GetStringWidth() + 14)
    ib:SetScript("OnClick", function() ToggleIgnored() end)
    ib:SetScript("OnEnter", function(self)
        self.bg:SetAlpha(0.35)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Manage ignored items")
        GameTooltip:AddLine("Items whose vendor and AH value never count in the session.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    ib:SetScript("OnLeave", function(self)
        self.bg:SetAlpha(0.18)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    hist.ignored = ib
    hist.scroll = CreateFrame("ScrollFrame", nil, hist)
    hist.scroll:SetPoint("TOPLEFT", 8, -52)
    hist.scroll:SetPoint("BOTTOMRIGHT", -8, 18)
    hist.content = CreateFrame("Frame", nil, hist.scroll)
    hist.content:SetSize(S.Get("histW") - 16, 1)
    hist.scroll:SetScrollChild(hist.content)
    hist.scroll:EnableMouseWheel(true)
    hist.scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, hist.content:GetHeight() - self:GetHeight())
        local y = math.min(max, math.max(0, self:GetVerticalScroll() - delta * HistLine() * 3))
        self:SetVerticalScroll(y)
    end)
    -- The list follows the window width.
    hist.scroll:SetScript("OnSizeChanged", function(self, w)
        hist.content:SetWidth(w)
    end)
    hist.empty = hist:CreateFontString(nil, "OVERLAY")
    hist.empty:SetPoint("CENTER", hist.scroll)
    StyleFont(hist.empty, 12)
    hist.empty:SetTextColor(0.6, 0.6, 0.6)
    hist.empty:SetText("No loot recorded yet.")
    -- Resize grip in the bottom-right corner.
    local grip = CreateFrame("Button", nil, hist)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() hist:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        hist:StopMovingOrSizing()
        SaveHistoryFrame()
        RefreshHistory()
    end)
    hist.lines = {}
    hist:SetScript("OnShow", RefreshHistory)
    UpdateEscClose() -- Esc closes it when Close with Esc is on
    hist:Hide()
end

ToggleHistory = function()
    CreateHistory()
    hist:SetShown(not hist:IsShown())
end

OnHistoryChanged = RefreshHistory

-------------------------------------------------------------------------------
--  Ignored items window: every item set to Ignore (not counted in the
--  session). Remove one with its X; add one by item ID, item link
--  (Shift+click an item while the box has focus) or by dropping an item
--  from the bags on the box.
-------------------------------------------------------------------------------
local ign
local IGN_W, IGN_H, IGN_LINE = 340, 380, 24

local function IgnoredIDs()
    local ids = {}
    for id, mode in pairs(S.Read().priceChoice or {}) do
        if mode == "IGNORE" and type(id) == "number" then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b)
        local na, nb = C_Item.GetItemInfo(a) or "", C_Item.GetItemInfo(b) or ""
        if na == nb then return a < b end
        return na < nb
    end)
    return ids
end

local function IgnoreChanged()
    if OnSessionChanged then OnSessionChanged() end
    RefreshHistory()
    RefreshIgnored()
end

local function IgnoreLine(i)
    local b = ign.lines[i]
    if b then return b end
    b = CreateFrame("Button", nil, ign.content)
    b:SetHeight(IGN_LINE)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * IGN_LINE)
    b:SetPoint("TOPRIGHT", 0, -(i - 1) * IGN_LINE)
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 1)
    b.hl:SetVertexColor(Accent())
    b.hl:SetAlpha(0.10)
    b.hl:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(IGN_LINE - 4, IGN_LINE - 4)
    b.icon:SetPoint("LEFT", 2, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.remove = CreateFrame("Button", nil, b)
    b.remove:SetSize(IGN_LINE - 6, IGN_LINE - 6)
    b.remove:SetPoint("RIGHT", -2, 0)
    b.remove.bg = b.remove:CreateTexture(nil, "BACKGROUND")
    b.remove.bg:SetAllPoints()
    b.remove.bg:SetColorTexture(1, 1, 1, 1)
    b.remove.bg:SetVertexColor(Accent())
    b.remove.bg:SetAlpha(0.18)
    b.remove.label = b.remove:CreateFontString(nil, "OVERLAY")
    StyleFont(b.remove.label, 11)
    b.remove.label:SetPoint("CENTER")
    b.remove.label:SetText("X")
    b.remove:SetScript("OnEnter", function(self)
        self.bg:SetVertexColor(0.8, 0.2, 0.2)
        self.bg:SetAlpha(0.6)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Remove from ignored items")
        GameTooltip:AddLine("It counts in the session again (default price).", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b.remove:SetScript("OnLeave", function(self)
        self.bg:SetVertexColor(Accent())
        self.bg:SetAlpha(0.18)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    b.remove:SetScript("OnClick", function(self)
        local id = self:GetParent().itemID
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        if id then
            SetPriceChoice(id, nil)
            IgnoreChanged()
        end
    end)
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.text:SetPoint("RIGHT", b.remove, "LEFT", -6, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    StyleFont(b.text, 12)
    b:SetScript("OnEnter", function(self)
        self.hl:Show()
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.hl:Hide()
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    ign.lines[i] = b
    return b
end

local ignRequested = {}
RefreshIgnored = function()
    if not (ign and ign:IsShown()) then return end
    local ids = IgnoredIDs()
    for i, id in ipairs(ids) do
        local b = IgnoreLine(i)
        b.itemID = id
        local name, _, quality = C_Item.GetItemInfo(id)
        b.icon:SetTexture(C_Item.GetItemIconByID(id))
        if name then
            local c = ITEM_QUALITY_COLORS[quality or 1] or ITEM_QUALITY_COLORS[1]
            b.text:SetText(c.hex .. name .. "|r")
        else
            b.text:SetText("|cff808080item " .. id .. "|r")
            if not ignRequested[id] then
                ignRequested[id] = true
                Item:CreateFromItemID(id):ContinueOnItemLoad(function() RefreshIgnored() end)
            end
        end
        b:Show()
    end
    for i = #ids + 1, #ign.lines do ign.lines[i]:Hide() end
    ign.title:SetText(string.format("Ignored Items  |cff808080%d|r", #ids))
    ign.empty:SetShown(#ids == 0)
    ign.content:SetHeight(math.max(1, #ids * IGN_LINE))
    local max = math.max(0, ign.content:GetHeight() - ign.scroll:GetHeight())
    if ign.scroll:GetVerticalScroll() > max then ign.scroll:SetVerticalScroll(max) end
end

-- An item ID from a number, an item link or a (cached) item name.
local function ParseItem(text)
    text = (text or ""):match("^%s*(.-)%s*$")
    if text == "" then return end
    local id = tonumber(text) or tonumber(text:match("|Hitem:(%d+)") or "") or tonumber(text:match("item:(%d+)") or "")
    if not id then id = C_Item.GetItemInfoInstant(text) end
    return id
end

local function AddIgnored(id)
    if not id then
        print("|cff0cd29fEllesmereUI|r: unknown item. Use an item ID, an item link or drop an item on the box.")
        return
    end
    SetPriceChoice(id, "IGNORE")
    IgnoreChanged()
end

local function AddFromCursor()
    local kind, id, link = GetCursorInfo()
    if kind == "item" then
        ClearCursor()
        AddIgnored(tonumber(id) or ParseItem(link))
        return true
    end
end

local function CreateIgnored()
    if ign then return end
    ign = CreateFrame("Frame", "EUI_LootIgnoredFrame", UIParent)
    ign:SetSize(IGN_W, IGN_H)
    local pos = S.Read().ignPos
    if pos and pos.point then
        ign:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        ign:SetPoint("CENTER", 200, 0)
    end
    ign:SetFrameStrata("DIALOG")
    ign:SetClampedToScreen(true)
    ign:SetMovable(true)
    ign:EnableMouse(true)
    ign:RegisterForDrag("LeftButton")
    ign:SetScript("OnDragStart", ign.StartMoving)
    ign:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        S.Cfg().ignPos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    ign.bg = ign:CreateTexture(nil, "BACKGROUND")
    ign.bg:SetAllPoints()
    WindowBg(ign.bg)
    EllesmereUI.PP.CreateBorder(ign, 0, 0, 0, 1, 1, "OVERLAY", 1)
    WindowBorder(ign)
    ign.accentLine = ign:CreateTexture(nil, "ARTWORK")
    ign.accentLine:SetPoint("TOPLEFT", 1, -1)
    ign.accentLine:SetPoint("TOPRIGHT", -1, -1)
    ign.accentLine:SetHeight(2)
    ign.accentLine:SetColorTexture(Accent())
    ign.title = ign:CreateFontString(nil, "OVERLAY")
    ign.title:SetPoint("TOPLEFT", 10, -9)
    StyleFont(ign.title, 13)
    ign.title:SetTextColor(Accent())
    local close = CreateFrame("Button", nil, ign, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetFrameLevel(ign:GetFrameLevel() + 10)
    close:SetScript("OnClick", function() ign:Hide() end)

    -- Add row: input box (ID, link or drop) and an Add button.
    local box = CreateFrame("EditBox", nil, ign)
    box:SetHeight(20)
    box:SetPoint("TOPLEFT", 10, -32)
    box:SetPoint("TOPRIGHT", -70, -32)
    box:SetAutoFocus(false)
    box:SetTextInsets(6, 6, 0, 0)
    -- An edit box needs a font before it takes text; fall back to the chat font.
    pcall(StyleFont, box, 12)
    if not box:GetFont() then box:SetFontObject(ChatFontNormal) end
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    box.bg:SetColorTexture(0, 0, 0, 0.6)
    EllesmereUI.PP.CreateBorder(box, 0.3, 0.3, 0.3, 1, 1, "OVERLAY", 1)
    box.hint = box:CreateFontString(nil, "OVERLAY")
    StyleFont(box.hint, 11)
    box.hint:SetPoint("LEFT", 6, 0)
    box.hint:SetTextColor(0.5, 0.5, 0.5)
    box.hint:SetText("Item ID, Shift+click an item, or drop one here")
    local function UpdateHint() box.hint:SetShown(box:GetText() == "" and not box:HasFocus()) end
    box:SetScript("OnEditFocusGained", UpdateHint)
    box:SetScript("OnEditFocusLost", UpdateHint)
    box:SetScript("OnTextChanged", UpdateHint)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local function Submit()
        local id = ParseItem(box:GetText())
        AddIgnored(id)
        if id then box:SetText("") end
        box:ClearFocus()
    end
    box:SetScript("OnEnterPressed", Submit)
    box:SetScript("OnReceiveDrag", AddFromCursor)
    box:SetScript("OnMouseDown", function() AddFromCursor() end)
    ign.box = box
    -- Shift+click on an item puts its link in the box while it has focus.
    if ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            if ign and ign:IsShown() and box:HasFocus() and link then box:SetText(link) end
        end)
    end

    local add = CreateFrame("Button", nil, ign)
    add:SetSize(54, 20)
    add:SetPoint("LEFT", box, "RIGHT", 6, 0)
    add.bg = add:CreateTexture(nil, "BACKGROUND")
    add.bg:SetAllPoints()
    add.bg:SetColorTexture(1, 1, 1, 1)
    add.bg:SetVertexColor(Accent())
    add.bg:SetAlpha(0.25)
    add.label = add:CreateFontString(nil, "OVERLAY")
    StyleFont(add.label, 12)
    add.label:SetPoint("CENTER")
    add.label:SetText("Add")
    add:SetScript("OnClick", function()
        if not AddFromCursor() then Submit() end
    end)
    add:SetScript("OnReceiveDrag", AddFromCursor)
    add:SetScript("OnEnter", function(self) self.bg:SetAlpha(0.45) end)
    add:SetScript("OnLeave", function(self) self.bg:SetAlpha(0.25) end)
    ign.add = add

    ign.scroll = CreateFrame("ScrollFrame", nil, ign)
    ign.scroll:SetPoint("TOPLEFT", 8, -60)
    ign.scroll:SetPoint("BOTTOMRIGHT", -8, 8)
    ign.content = CreateFrame("Frame", nil, ign.scroll)
    ign.content:SetSize(IGN_W - 16, 1)
    ign.scroll:SetScrollChild(ign.content)
    ign.scroll:EnableMouseWheel(true)
    ign.scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, ign.content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * IGN_LINE * 3)))
    end)
    ign.empty = ign:CreateFontString(nil, "OVERLAY")
    ign.empty:SetPoint("CENTER", ign.scroll)
    StyleFont(ign.empty, 12)
    ign.empty:SetTextColor(0.6, 0.6, 0.6)
    ign.empty:SetText("No ignored items.\nIgnore one here or from the loot history.")
    ign.lines = {}
    ign:SetScript("OnShow", RefreshIgnored)
    UpdateEscClose() -- Esc closes it when Close with Esc is on
    ign:Hide()
end

ToggleIgnored = function()
    CreateIgnored()
    ign:SetShown(not ign:IsShown())
end

SLASH_EUILOOTIGNORE1 = "/lootignore"
SlashCmdList.EUILOOTIGNORE = function() ToggleIgnored() end

SLASH_EUILOOTHISTORY1 = "/loothistory"
SLASH_EUILOOTHISTORY2 = "/lootlog"
SlashCmdList.EUILOOTHISTORY = function() ToggleHistory() end

-------------------------------------------------------------------------------
--  Session setup and auto reset
-------------------------------------------------------------------------------
local function ApplySession()
    Apply() -- the feed's events follow whether the session needs loot
    if S.Enabled() then
        CreatePanel()
        StylePanel()
        S.Place(panel)
        panel:Show()
        SessionData()
        UpdatePanel()
        if not ticker then ticker = C_Timer.NewTicker(1, UpdatePanel) end
    else
        if panel then panel:Hide() end
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
    end
end

SetSessionEnabled = function(on)
    S.Cfg().enabled = on and true or false
    ApplySession()
    -- An open options page shows the new state.
    if EllesmereUI.RefreshPage then pcall(EllesmereUI.RefreshPage, EllesmereUI) end
    if not on then
        ns.Print("Farming Session off. |cffffd100/lootsession|r turns it back on.")
    end
end

SLASH_EUILOOTSESSION1 = "/lootsession"
SlashCmdList.EUILOOTSESSION = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "reset" then
        ResetSession()
    elseif msg == "pause" then
        TogglePause()
    else
        SetSessionEnabled(not S.Enabled())
    end
end

local REENTER_RESET = 600 -- seconds outside after which the same instance counts as a new run
local worldWatch = CreateFrame("Frame")
worldWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
worldWatch:SetScript("OnEvent", function(_, _, isLogin)
    if not S.Enabled() then return end
    local mode, c = S.Get("autoReset"), S.Cfg()
    local inInstance = IsInInstance()
    local instanceID = select(8, GetInstanceInfo())
    if isLogin and (mode == "LOGIN" or mode == "BOTH") then
        ResetSession()
    elseif inInstance and (mode == "INSTANCE" or mode == "BOTH") then
        local away = c.leftAt and (time() - c.leftAt) or math.huge
        if c.lastInstance ~= instanceID or away > REENTER_RESET then ResetSession() end
    end
    if inInstance then
        c.lastInstance, c.leftAt = instanceID, nil
    elseif c.lastInstance and not c.leftAt then
        c.leftAt = time()
    end
end)

-------------------------------------------------------------------------------
--  Minimap icon: Left-click loot history, Right-click ignored items,
--  Shift+Left-click Farming Session on / off. Uses LibDBIcon when another
--  addon has loaded it, otherwise its own button on the minimap edge (drag to
--  move). Both are named minimap buttons, so EllesmereUI's minimap button bar
--  collects them. Also a LibDataBroker launcher for broker displays.
-------------------------------------------------------------------------------
local MM_NAME = "Loot Tracker"
local MM_ICON = "Interface\\Icons\\INV_Misc_Bag_10"

local function MinimapClick(button)
    if button == "RightButton" then
        ToggleIgnored()
    elseif IsShiftKeyDown() then
        SetSessionEnabled(not S.Enabled())
    else
        ToggleHistory()
    end
end

local function MinimapTooltip(tt)
    tt:AddLine("Loot Tracker")
    tt:AddLine("Left-click: loot history", 0.8, 0.8, 0.8)
    tt:AddLine("Right-click: ignored items", 0.8, 0.8, 0.8)
    tt:AddLine("Shift+Left-click: Farming Session " .. (S.Enabled() and "off" or "on"), 0.8, 0.8, 0.8)
end

local ldbObject, dbIcon, mmButton

-- Own button, when LibDBIcon is not around.
local function PlaceMinimapButton()
    local angle = math.rad(S.Get("minimapAngle") or 200)
    local r = (Minimap:GetWidth() / 2) + 5
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function CreateMinimapButton()
    if mmButton or not Minimap then return end
    local b = CreateFrame("Button", "EUI_LootHistoryMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(MM_ICON)
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon = icon
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    b:SetScript("OnClick", function(_, button) MinimapClick(button) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        MinimapTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    -- Drag around the minimap edge; the angle is saved.
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            S.Cfg().minimapAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
            PlaceMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mmButton = b
    PlaceMinimapButton()
end

local function ApplyMinimapIcon()
    local show = S.Get("minimapIcon")
    if dbIcon then
        local c = S.Cfg()
        c.minimapDB = c.minimapDB or {}
        c.minimapDB.hide = not show
        if show then dbIcon:Show(MM_NAME) else dbIcon:Hide(MM_NAME) end
        return
    end
    if show then
        CreateMinimapButton()
        if mmButton then mmButton:Show() end
    elseif mmButton then
        mmButton:Hide()
    end
end

local mmBoot = CreateFrame("Frame")
mmBoot:RegisterEvent("PLAYER_LOGIN")
mmBoot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    if LDB then
        ldbObject = LDB:NewDataObject(MM_NAME, {
            type = "launcher", label = "Loot History", icon = MM_ICON,
            OnClick = function(_, button) MinimapClick(button) end,
            OnTooltipShow = MinimapTooltip,
        })
    end
    local lib = LibStub and LibStub("LibDBIcon-1.0", true)
    if lib and ldbObject then
        local c = S.Cfg()
        c.minimapDB = c.minimapDB or {}
        c.minimapDB.hide = not S.Get("minimapIcon")
        lib:Register(MM_NAME, ldbObject, c.minimapDB)
        dbIcon = lib
    end
    ApplyMinimapIcon()
end)

ns.Session = {
    ApplyMinimapIcon = function() ApplyMinimapIcon() end,
    Get = S.Get,
    Cfg = S.Cfg,
    Apply = ApplySession,
    ApplyStyle = function() StylePanel() end,
    Reset = ResetSession,
    Refresh = function()
        if OnSessionChanged then OnSessionChanged() end
        if OnHistoryChanged then OnHistoryChanged() end
    end,
    TogglePause = TogglePause,
    IsPaused = SessionPaused,
    ToggleHistory = function() ToggleHistory() end,
    ClearHistory = ClearHistory,
    ToggleIgnored = function() ToggleIgnored() end,
    UpdateEscClose = function() UpdateEscClose() end,
    ApplyWindowBg = function()
        if hist then WindowBg(hist.bg); WindowBorder(hist) end
        if ign then WindowBg(ign.bg); WindowBorder(ign) end
    end,
    TrimHistory = TrimHistory,
    RefreshHistory = function() RefreshHistory() end,
}

S.Start(ApplySession, {
    key = "EUI_DworakLootSession", label = "Farming Session", order = 910, minWidth = 140,
    frame = function(build)
        if build then CreatePanel() end
        return panel
    end,
    height = PanelHeight,
    applyStyle = StylePanel,
})

-- Options-page entry points.
ns.Feed = {
    Get = Get,
    Cfg = Cfg,
    Apply = Apply,
    ApplyStyle = ApplyStyle,
    ApplyPosition = function() F.Place(anchor) end,
    Preview = Preview,
    CreateSettingsPreview = CreateSettingsPreview,
    RefreshPreview = function() RefreshPreview() end,
    HasAH = HasAH,
}

-- The UI Accent Color (Global Settings) repaints live: the feed's accent
-- bars, the session title and pause button, and the loot history window.
-- KEEP THIS BLOCK when editing this file: without it nothing here follows
-- an accent change until /reload.
if EllesmereUI.RegAccent then
    EllesmereUI.RegAccent({ type = "callback", fn = function()
        if anchor then ApplyStyle() else RefreshPreview() end
        if panel then StylePanel() end
        if hist then
            hist.title:SetTextColor(Accent())
            hist.accentLine:SetColorTexture(Accent())
            for _, line in ipairs(hist.lines) do line.hl:SetVertexColor(Accent()) end
            for _, chip in ipairs(hist.chips) do chip:Update() end
            if not hist.clear.armed then hist.clear.bg:SetVertexColor(Accent()) end
            hist.ignored.bg:SetVertexColor(Accent())
        end
        if popup and popup:IsShown() then
            popup.vendor:Update()
            popup.ah:Update()
            popup.default:Update()
            popup.ignore:Update()
        end
        if ign then
            ign.title:SetTextColor(Accent())
            ign.accentLine:SetColorTexture(Accent())
            ign.add.bg:SetVertexColor(Accent())
            for _, line in ipairs(ign.lines) do
                line.hl:SetVertexColor(Accent())
                line.remove.bg:SetVertexColor(Accent())
            end
        end
    end })
end

F.Start(Apply, {
    key = "EUI_DworakLootFeed", label = "Loot Feed", order = 905, minWidth = 150,
    frame = function(build)
        if build then CreateAnchor() end
        return anchor
    end,
    -- Follows Max Rows and Row Height.
    height = AnchorHeight,
    applyStyle = ApplyStyle,
})
