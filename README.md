# EasyFind: TSM Extension

TradeSkillMaster's groups, prices and item counts in EasyFind's search bar. Type `@tsm` and your groups are listed; type a group's name for the items in it, or an item's name to find the group it is in. Hovering an item shows the TSM price you picked and how many you own, across your characters, guild banks and the warband bank. The crafts queued in TSM are rows too, with their materials in the tooltip.

Requires TradeSkillMaster and EasyFind.

## What it adds

- Group rows and the items in them in EasyFind's search results, and an `@tsm` scope that lists your groups.
- A click on a group lists its items. A click on an item links it in chat, Ctrl-click tries it on, Alt-click lists its group.
- Crafting queue rows, found by typing `craft`, each with the count queued and its materials in the tooltip.
- A TSM row in the filter menu with three toggles: Prices on item rows, Owned counts in tooltips, Crafting queue rows.
- A TSM tile in the extensions menu, with the same toggles and the price source choice in Options > Extensions. `/eftsm source <price string>` takes any TSM custom price string.

## Dependencies

- EasyFind, with its extension API (EasyFind.API version 1).
- TradeSkillMaster, whose groups, prices and counts this addon reads at runtime through its public `TSM_API`. Nothing of TradeSkillMaster's is copied into this addon.

## How it reads TradeSkillMaster

Once the character is in the world the addon waits for TradeSkillMaster's data to finish loading, then reads its groups and listens for group changes. Prices come from the price source you pick (TSM's Market Value by default) and need the data TradeSkillMaster's desktop app provides; without it, the sources that work in game alone (vendor prices, crafting cost) still do. TradeSkillMaster's groups and settings are never written. If a function it needs is missing in the installed version, the extension turns itself off with one line in chat and nothing else changes.
