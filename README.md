# EllesmereUI-Loot_Tracker_Advanced with farming session and loot history (last 500 loot)
<img width="2450" height="1101" alt="{C85879B0-A9B7-41AF-8DA4-0D47F68B4533}" src="https://github.com/user-attachments/assets/d2edaed0-47f4-49a7-b2b3-b1f3fcc5091f" />

A loot feed, farming session tracker and loot history for WoW Forever, built as a plugin for EllesmereUI. It lives in the Dworak section of the EllesmereUI settings panel and matches the look of the rest of the suite.

It is a standalone addon: no EllesmereUI file is changed, so EllesmereUI updates never overwrite it.

Features
Loot Feed

Short-lived rows that show what you gain. A new loot of something already on screen adds to its row instead of opening a new one.

Sources: looted items, money, money taken from the mailbox, reputation (with progress in the current standing), currencies (with your total) and skill ups. Each can be turned on or off.
Prices: vendor price of the looted stack, and the auction house price from Auctionator. You can set the AH price's position (right side or second line), text size, color, an "AH" label and X/Y offsets.
Item details: item level for weapons and armor, and how many you now carry ("12 in bags").
Currency icon format: the money row shows a gold, silver or copper icon depending on the largest coin looted, or always gold.
Junk merge: grey items share one "Junk xN" row with their total vendor value.
Display time per quality: separate display time for Poor, Common, Uncommon, Rare, Epic and Legendary items.
Effects: a shine sweep across new items of a chosen quality or better.
Valuable loot alert: a stack worth at least your threshold (gold + silver, checked against the AH price, the vendor price or the higher of the two) pulses, plays a sound and stays longer.
Styles: Box, Accent Bar, Icon Tray and Loot Toast. Width, row height, max rows, grow direction, text size, background, border and quality-colored borders are all adjustable.
A live preview at the top of the settings page shows every change as you make it.
Farming Session

A small panel that shows what the current session earned:

Money, items at vendor price, items at AH price, total and gold per hour.
Pause / Resume: while paused, the clock stops and loot is not counted.
Reset with Shift+right-click on the panel, from the settings or with /lootsession reset.
Auto reset on login, when entering an instance, or both. Re-entering the same instance within 10 minutes (after a wipe, for example) keeps the session.
Value basis: money + items at AH price, money + items at vendor price, or money only.
Grey items at vendor price (on by default): their AH prices are rarely real sales.
Mailbox money is counted only if you turn it on, so auction sales and mail from alts do not inflate your gold per hour.
Drag the panel to move it, or lock it. The X closes it and turns the session off; the totals are kept.
Loot History

A window with the items and money you looted:

Keeps the last 10–500 entries (50 by default). Recording money is optional.
Quality filter: P C U R E buttons (Poor to Epic) in their quality colors. The filter only changes what is listed: every item is still recorded. Legendary items are always listed.
Per-item price choice: click an item to count it at its vendor price, its AH price, the default, or to ignore it. The choice applies to every loot of that item, in the history and in the current session, and is remembered.
Ignored Items window: list, remove, or add items by item ID, by Shift-clicking an item link, or by dropping an item from your bags.
Hover a row for the item tooltip; Shift-click to link it in chat.
Clear button (click twice to confirm).
Resizable and movable. Background color and opacity, border size and color, row text size and "close with Esc" are adjustable.
Other
Minimap icon: left-click opens the loot history, right-click the ignored items, Shift+left-click turns the Farming Session on or off. Uses LibDBIcon if another addon loaded it, otherwise its own button; EllesmereUI's minimap button bar collects either one. Also available as a LibDataBroker launcher.
Unlock Mode: the Loot Feed and the Farming Session panel can be placed in EllesmereUI's Unlock Mode, in the "Dworak" group.
Buttons and titles follow EllesmereUI's UI Accent Color, live.
Chat lines are matched against the client's own localized strings, so it works in every client language.
Requirements
WoW Forever (Interface 16001)
EllesmereUI (built against 9.5.4)
EllesmereUI Dworak (EllesmereUIDworak), which provides the "Dworak" section of the EllesmereUI panel
Optional: Auctionator for auction house prices. Without it everything works, but no AH prices are shown.
Installation
Download the latest release.
Copy the EllesmereUILootTracker folder into World of Warcraft\_classic_beta_\Interface\AddOns\ (the same place as your other EllesmereUI folders).
Make sure EllesmereUIDworak is installed as well.
Log in, or type /reload.
Open the settings with /loottracker, or in the EllesmereUI panel under Dworak > Loot Tracker.

The folder must be named exactly EllesmereUILootTracker.

Coming from the Forever Essentials Loot Feed

On first load, Loot Tracker copies your existing data once:

your Loot Feed settings and position,
your loot history, ignored items and vendor / AH choices,
your current farming session.

The old data is left in place as a backup.

While the Loot Tracker feed is on, the built-in Forever Essentials Loot Feed is switched off, so the same loot never shows twice. A chat message tells you when this happens.

Slash commands
Command	Action
/loottracker	Open the settings (/loottracker session or /loottracker history for that page)
/loothistory, /lootlog	Open or close the loot history
/lootignore	Open or close the ignored items window
/lootsession	Turn the Farming Session on or off
/lootsession reset	Start a new session
/lootsession pause	Pause or resume the session
Settings and saved data

Settings are account-wide and saved in EllesmereUILootTrackerDB (WTF\Account\<account>\SavedVariables\EllesmereUILootTracker.lua).

Files
File	Contents
EllesmereUILootTracker.toc	Addon manifest
EllesmereUILootTracker.lua	Settings store, Unlock Mode elements, import from the Forever Essentials Loot Feed
EllesmereUILootTracker_Core.lua	Loot Feed, Farming Session, Loot History, Ignored Items, minimap icon
EllesmereUILootTracker_Options.lua	Settings pages (Loot Feed, Farming Session, Loot History)
Credits
Based on the Loot Feed of EllesmereUI's Forever Essentials module by Ellesmere.
Auction house prices from Auctionator.
Author: Dworak
