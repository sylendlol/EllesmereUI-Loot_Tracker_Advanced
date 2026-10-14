# EllesmereUI Loot Tracker (Dworak > Loot Tracker)

Standalone addon for EllesmereUI (WoW Forever beta, Interface 16001; built on EllesmereUI 9.5.4).
No EllesmereUI file is modified, so EllesmereUI updates do not overwrite it.

Needs: EllesmereUI, EllesmereUIDworak. Optional: Auctionator (AH prices).

## Pages (EllesmereUI panel > Dworak > Loot Tracker, or /loottracker)
- **Loot Feed** – rows for looted items (vendor + Auctionator price, bag count, item level),
  money (coin icon by largest coin), mailbox money, reputation, currencies, skill ups.
  Styles, per-quality display time, junk merge, shine, valuable-loot alert (pulse, sound, extra time).
- **Farming Session** – panel with money, item value (vendor / AH), total, gold per hour, pause,
  auto reset (login / instance), grey items at vendor price, mailbox money on/off.
- **Loot History** – last N loot (10–500), quality filter chips P C U R E, per-item price choice
  (Vendor / AH / Default / Ignore), Ignored Items window, background, border, text size,
  close with Esc, minimap icon.

## Slash commands
- `/loottracker` (`session`, `history`) – settings
- `/loothistory`, `/lootlog` – loot history window
- `/lootignore` – ignored items window
- `/lootsession` (`reset`, `pause`) – Farming Session on/off

## Data
Account-wide in `EllesmereUILootTrackerDB` (`feed`, `session`). On first load the old Forever
Essentials data (`EllesmereUIDB.lootFeed`, `EllesmereUIDB.lootSession`) is copied over once; the old
data stays as a backup. While the Loot Tracker feed is on, the Forever Essentials Loot Feed is switched off.
Unlock Mode: group "Dworak", elements "Loot Feed" and "Farming Session".
