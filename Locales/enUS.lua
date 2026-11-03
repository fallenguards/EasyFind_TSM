local _, ns = ...

-- Every string the player sees. Other locales override keys in files of
-- their own; a missing key falls back to this one.
local L = setmetatable({}, { __index = function(t, k) return k end })
ns.L = L

L["EXT_NAME"] = "TSM"
L["EXT_DESC"] = "TradeSkillMaster's groups, prices and crafting queue."
L["PROVIDER_LABEL"] = "TSM"
L["CATEGORY"] = "TSM"
L["DECOR_LABEL"] = "TSM price"
L["SETTINGS_HINT"] = "Which TSM price the rows show. Type @tsm in EasyFind for your groups."

L["OPT_SOURCE"] = "Price source"
L["OPT_SOURCE_TIP"] = "Any TSM custom price works too: /eftsm source <price>."
L["OPT_PRICES"] = "Prices on item rows"
L["OPT_PRICES_TIP"] = "On every item in EasyFind's results, not only TSM's."
L["OPT_QUEUE"] = "Crafting queue rows"
L["OPT_QUEUE_TIP"] = "The crafts queued in TSM, found by typing craft."

L["GROUP_ITEMS_FMT"] = "%d items"
L["GROUP_ITEM_FMT"] = "%d item"
L["QUEUE_FMT"] = "Craft x%d"
L["MATERIALS"] = "Materials"
L["FALLBACK_FMT"] = "No %s here, so the row shows the %s."
L["GROUP_SUBTEXT_FMT"] = "TSM: %s"

L["HINT_LIST_ITEMS"] = "List its items"
L["HINT_LINK"] = "Link in chat"
L["HINT_DRESS"] = "Try on"
L["HINT_GROUP"] = "Its group"
L["MENU_SHOW_GROUP"] = "Show its TSM group"

L["SOURCE_SET_FMT"] = "Price source: %s."
L["SOURCE_BAD_FMT"] = "TSM rejects that price: %s"
L["STATUS_FMT"] = "Price source %s. %d groups, %d crafts queued."
L["USAGE"] = "/eftsm source <TSM price string>"
L["NEEDS_EASYFIND"] = "Needs a newer EasyFind for TSM search: update EasyFind."
L["NOT_READY"] = "TSM's data is not available in this version, so its groups and prices are off."
