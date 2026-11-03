-- TSM.lua's own logic against the fake TSM_API: rows, clicks, hints,
-- tooltips, the row prices on EasyFind's rows, the price source, switches.
local H = require("Harness")
local tests = {}

local LINEN_LINK = "|cffffffff|Hitem:2589::::::::70:::::|h[Linen Cloth]|h|r"

local function Names(rows)
    local out = {}
    for i, row in ipairs(rows) do out[i] = row.name end
    return table.concat(out, ", ")
end

local function Option(w, label)
    for _, o in ipairs(w:provider().options) do
        if o.label == label then return o end
    end
end

-- An item row EasyFind owns, as the decorator gets it.
local function BagRow(itemID, link)
    return { name = "bag item", itemID = itemID, category = "Bag", bagItemLink = link }
end

-- ==== rows ==================================================================

function tests.rows_groupsThenQueueThenItems_eachByName()
    local w = H.load():login()
    H.assertEq(Names(w:rows()), "Gear, Mats, Mats->Cloth, Crafting materials, Copper Bar, Copper Ore, Linen Cloth, Wool Cloth")
end

function tests.groupRow_pathWords_itemCount_noPathField()
    local w = H.load():login()
    local row = w:row("Mats->Cloth")
    H.assertEq(row.kind, "group")
    H.assertEq(row.groupPath, "Mats`Cloth", "TSM's own path kept")
    H.assertNil(row.path, "EasyFind reads a row's path as a list")
    H.assertEq(table.concat(row.keywords, " "), "Cloth Mats group", "every segment finds it")
    H.assertEq(row.searchCommandDesc, "2 items")
    H.assertEq(row.icon, 102592, "its first item's icon")
    H.assertEq(w:row("Mats").searchCommandDesc, "3 items", "a subgroup's items count")
    H.assertEq(w:row("Gear").searchCommandDesc, "0 items")
end

function tests.itemRows_onceEach_underTheirOwnGroup()
    local w = H.load():login()
    local n = 0
    for _, row in ipairs(w:rows()) do if row.name == "Linen Cloth" then n = n + 1 end end
    H.assertEq(n, 1, "a subgroup's item is not repeated under its parent")
    local row = w:row("Linen Cloth")
    H.assertEq(row.itemID, 2589)
    H.assertEq(row.groupPath, "Mats`Cloth")
    H.assertEq(row.searchCommandDesc, "Mats->Cloth")
    H.assertNil(row.path, "no path field on item rows")
end

function tests.itemRows_nameOnlyUnderTheScope_fromMinor7()
    local w = H.load({ minor = 7 }):login()
    H.assertEq(w:row("Linen Cloth").scopedName, true, "EasyFind's own row is the one its name finds")
    H.assertNil(w:row("Mats->Cloth").scopedName, "groups found by name everywhere")
    H.assertNil(w:row("Copper Bar").scopedName, "and the queue")
    H.assertNil(H.load({ minor = 6 }):login():row("Linen Cloth").scopedName, "an older EasyFind: as before")
end

function tests.groupWords_shortForms_bsMats()
    local data = H.TsmData()
    data.groups[#data.groups + 1] = "Blacksmithing"
    data.groups[#data.groups + 1] = "Blacksmithing`Materials"
    data.items["Blacksmithing`Materials"] = { "i:2835" }
    local w = H.load({ tsmData = data }):login()
    H.assertEq(table.concat(w:row("Blacksmithing->Materials").keywords, " "), "Materials mats Blacksmithing bs group")
    H.assertEq(table.concat(w:row("Rough Stone").keywords, " "), "Materials mats Blacksmithing bs",
        "its items found by them too")
    H.assertEq(table.concat(w:row("Mats->Cloth").keywords, " "), "Cloth Mats group", "other words as they are")
end

function tests.queueRows_craftCount_skipsEnchants()
    local w = H.load():login()
    local row = w:row("Copper Bar")
    H.assertEq(row.kind, "queue")
    H.assertEq(row.searchCommandDesc, "Craft x5")
    H.assertEq(row.recipeString, "r:2840")
    local queued = 0
    for _, r in ipairs(w:rows()) do if r.kind == "queue" then queued = queued + 1 end end
    H.assertEq(queued, 1, "a craft with no item has no row")
end

function tests.browse_listsGroupsAndQueue()
    local w = H.load():login()
    local p = w:provider()
    H.assertTrue(p.browse(w:row("Mats")), "a group")
    H.assertTrue(p.browse(w:row("Copper Bar")), "a queued craft")
    H.assertTrue(not p.browse(w:row("Linen Cloth")), "not an item")
end

function tests.queueSwitchOff_noQueueRows()
    local w = H.load({ saved = { queue = false } }):login()
    H.assertNil(w:row("Copper Bar"))
    H.assertEq(#w:rows(), 6)
end

-- ==== clicks, hints, menu ===================================================

function tests.groupClick_listsItsItems()
    local w = H.load():login()
    w:provider().select(w:row("Mats->Cloth"))
    H.assertEq(w.api.scopes[1].key, "tsm")
    H.assertEq(w.api.scopes[1].text, "Cloth", "the group's own name searched")
end

function tests.itemClick_linksInChat()
    local w = H.load():login()
    w:provider().select(w:row("Linen Cloth"))
    H.assertTrue(w.chat.inserted and w.chat.inserted:find("[Linen Cloth]", 1, true), "into the chat box")
    w.chat.inserted, w.chat.insertWorks = nil, false
    w:provider().select(w:row("Wool Cloth"))
    H.assertTrue(w.chat.opened and w.chat.opened:find("[Wool Cloth]", 1, true), "no chat box open: one opens with it")
    local typed = {}
    w.chat.active = { IsShown = function() return true end, Insert = function(_, link) typed[#typed + 1] = link end }
    w:provider().select(w:row("Copper Ore"))
    H.assertTrue(typed[1] and typed[1]:find("[Copper Ore]", 1, true), "into the box being typed in")
end

function tests.ctrlClick_triesOn_altClick_listsItsGroup()
    local w = H.load():login()
    w.keys.ctrl = true
    w:provider().select(w:row("Linen Cloth"))
    H.assertTrue(w.dressed[1] and w.dressed[1]:find("Hitem:2589", 1, true), "Ctrl tries it on")
    w.keys.ctrl, w.keys.alt = false, true
    w:provider().select(w:row("Linen Cloth"))
    H.assertEq(w.api.scopes[1].text, "Cloth", "Alt lists its group")
    w:provider().select(w:row("Copper Bar"))
    H.assertEq(#w.api.scopes, 1, "a craft in no group: Alt does nothing")
end

function tests.hints_sayWhatEachClickDoes()
    local w = H.load():login()
    local p = w:provider()
    H.assertEq(p.hint(w:row("Mats")), "List its items")
    local h = p.hint(w:row("Linen Cloth"))
    H.assertEq(h.click, "Link in chat")
    H.assertEq(h.ctrl, "Try on")
    H.assertEq(h.alt, "Its group")
    H.assertNil(p.hint(w:row("Copper Bar")).alt, "no Alt word for an item in no group")
end

function tests.queueRowMenu_showsItsGroup()
    local data = H.TsmData()
    data.queue[#data.queue + 1] = { "r:3000", "i:2592", 2 }
    local w = H.load({ tsmData = data }):login()
    local queued
    for _, r in ipairs(w:rows()) do if r.kind == "queue" and r.name == "Wool Cloth" then queued = r end end
    local menu = w:provider().menu(queued)
    H.assertEq(#menu, 1)
    H.assertEq(menu[1].label, "Show its TSM group")
    menu[1].onClick()
    H.assertEq(w.api.scopes[1].text, "Cloth")
    H.assertNil(w:provider().menu(w:row("Copper Bar")), "in no group: no menu")
end

-- ==== tooltips ==============================================================

-- TSM writes its prices and counts on every item tooltip: none of ours.
function tests.itemTooltip_theItemAlone_TSMAddsItsOwnLines()
    local w = H.load():login()
    local tt = H.Tooltip()
    H.assertTrue(w:provider().tooltip(w:row("Linen Cloth"), tt), "shown")
    H.assertTrue(tt.link:find("Hitem:2589", 1, true), "the item's own tooltip")
    H.assertEq(#tt.lines, 1, "no price or count lines of ours")
end

function tests.queueTooltip_materialsHaveOverNeed()
    local w = H.load():login()
    local tt = H.Tooltip()
    w:provider().tooltip(w:row("Copper Bar"), tt)
    local head = tt:Has("Materials")
    H.assertTrue(head, "a materials list")
    H.assertEq(tt.lines[head + 1], "Copper Ore  4/5", "have over need for the whole entry")
    H.assertEq(tt.lines[head + 2], "Rough Stone  0/10")
    H.assertEq(tt.colors[head + 1][1], 1, "short of it: reddish")
end

function tests.groupTooltip_nameAndCount()
    local w = H.load():login()
    local tt = H.Tooltip()
    w:provider().tooltip(w:row("Mats->Cloth"), tt)
    H.assertEq(tt.lines[1], "Mats->Cloth")
    H.assertEq(tt.lines[2], "2 items")
end

-- ==== prices on EasyFind's own rows =========================================

function tests.decorator_pricesEasyFindsItemRows()
    local w = H.load():login()
    local d = w:decorator()
    H.assertEq(d.text(BagRow(2589, LINEN_LINK), LINEN_LINK), 120, "by the row's link")
    H.assertEq(d.text(BagRow(2770), "item:2770"), 45, "by its id")
    H.assertNil(d.text(BagRow(2840), "item:2840"), "nothing TSM has no price for")
    Option(w, "Prices on item rows").set(false)
    H.assertNil(d.text(BagRow(2589), "item:2589"), "the switch turns them off")
end

function tests.decorator_noTooltipLines_menuShowsTheGroup()
    local w = H.load():login()
    local d = w:decorator()
    local tt = H.Tooltip()
    d.tooltip(BagRow(2589, LINEN_LINK), LINEN_LINK, tt)
    H.assertEq(#tt.lines, 0, "TSM's own tooltip lines are there already")
    local menu = d.menu(BagRow(2589), "item:2589")
    H.assertEq(menu and menu[1].label, "Show its TSM group", "an item in a group")
    menu[1].onClick()
    H.assertEq(w.api.scopes[1].text, "Cloth")
    H.assertNil(d.menu(BagRow(7005), "item:7005"), "in no group: no entry")
end

-- The decorator takes TSM's own rows too (they carry an itemID).
function tests.decorator_ownRows_priceOnly_noDoubledLines()
    local w = H.load():login()
    local d, row = w:decorator(), w:row("Linen Cloth")
    H.assertEq(d.text(row, "item:2589"), 120, "the price at the row's right")
    local tt = H.Tooltip()
    w:provider().tooltip(row, tt)
    local before = #tt.lines
    d.tooltip(row, "item:2589", tt)
    H.assertEq(#tt.lines, before, "no second price and counts")
    H.assertNil(d.menu(row, "item:2589"), "no second group entry")
end

-- An Era realm: TSM's app has no market data, the vendor's price stands in.
function tests.noMarketPrice_vendorPriceDimmed_tooltipSaysSo()
    local w = H.load():login()
    w.tsm.prices.dbmarket["i:2589"] = nil
    local d = w:decorator()
    local value, word = d.text(BagRow(2589), "item:2589")
    H.assertEq(value, 13, "the vendor's price")
    H.assertEq(word, "dim", "dimmed: not the chosen price")
    H.assertEq(select("#", d.text(BagRow(2770), "item:2770")), 1, "the chosen price as it was")
    local tt = H.Tooltip()
    d.tooltip(BagRow(2589), "item:2589", tt)
    H.assertEq(tt.lines[1], "No AuctionDB - Market Value here, so the row shows the Vendor Sell Price.",
        "why the row's price is dim")
    H.assertEq(#tt.lines, 1)
    H.assertNil(d.text(BagRow(2840), "item:2840"), "neither: nothing")
end

function tests.vendorPriceChosen_notDimmed_noLine()
    local w = H.load():login()
    w:slash("source vendorsell")
    local d = w:decorator()
    H.assertEq(select("#", d.text(BagRow(2589), "item:2589")), 1, "not dimmed")
    local tt = H.Tooltip()
    d.tooltip(BagRow(2770), "item:2770", tt)
    H.assertEq(#tt.lines, 0)
end

function tests.subtext_itsTSMGroup_onEasyFindsRows()
    local w = H.load():login()
    local d = w:decorator()
    H.assertEq(d.subtext(BagRow(2589, LINEN_LINK)), "TSM: Mats->Cloth")
    H.assertEq(d.subtext(BagRow(2770)), "TSM: Mats", "by its id")
    H.assertNil(d.subtext(BagRow(7005)), "in no group")
    H.assertNil(d.subtext(w:row("Linen Cloth")), "TSM's own row shows its group already")
end

function tests.prices_keptUntilTheAuctionHouseCloses()
    local w = H.load():login()
    local d = w:decorator()
    H.assertEq(d.text(BagRow(2589), "item:2589"), 120)
    w.tsm.prices.dbmarket["i:2589"] = 200
    H.assertEq(d.text(BagRow(2589), "item:2589"), 120, "cached")
    local repaints = w.api.decorRefreshes
    w:fire("AUCTION_HOUSE_CLOSED")
    H.assertEq(d.text(BagRow(2589), "item:2589"), 200, "read again")
    H.assertTrue(w.api.decorRefreshes > repaints, "shown rows repaint")
    w.tsm.prices.dbmarket["i:2589"] = 250
    w:advance(600)
    H.assertEq(d.text(BagRow(2589), "item:2589"), 250, "and every ten minutes")
end

-- ==== price source ==========================================================

function tests.slashSource_takesAKeyOrACustomPrice()
    local w = H.load():login()
    local d = w:decorator()
    w:slash("source dbminbuyout")
    H.assertEq(w.printed[#w.printed], "|cff66ccffTSM:|r Price source: AuctionDB - Minimum Buyout.")
    H.assertEq(d.text(BagRow(2589), "item:2589"), 99)
    H.assertEq(w.env.EasyFindTSMDB.source, "dbminbuyout", "saved")
    w:slash("source max(dbminbuyout, vendorsell)")
    H.assertTrue(w.printed[#w.printed]:find("Price source: max(dbminbuyout, vendorsell).", 1, true), "a custom price shows itself")
    H.assertEq(d.text(BagRow(2589), "item:2589"), 99, "its value on the rows")
end

function tests.slashSource_badPrice_saysWhy_keepsTheOld()
    local w = H.load():login()
    w:slash("source bogus")
    H.assertTrue(w.printed[#w.printed]:find("TSM rejects that price: Unknown word: bogus", 1, true), "TSM's reason")
    H.assertNil(w.env.EasyFindTSMDB and w.env.EasyFindTSMDB.source, "nothing saved")
end

function tests.slashStatus_groupsAndQueue()
    local w = H.load():login()
    w:slash("")
    H.assertTrue(w.printed[#w.printed - 1]:find("Price source AuctionDB - Market Value. 3 groups, 2 crafts queued.", 1, true))
    H.assertTrue(w.printed[#w.printed]:find("/eftsm source", 1, true), "how to set one")
end

function tests.settingsChoice_theSourcesTSMHas()
    local w = H.load():login()
    local kit = H.Kit()
    w:extension().settings({}, kit)
    local choice = kit.made[2]
    local values = {}
    for i, c in ipairs(choice.choices) do values[i] = c.value end
    H.assertEq(table.concat(values, ","), "dbmarket,dbminbuyout,crafting,vendorsell", "known keys this TSM offers")
    H.assertEq(choice.choices[1].label, "AuctionDB - Market Value", "TSM's own names")
    H.assertEq(choice.default, "dbmarket")
    H.assertEq(choice.get(), "dbmarket")
    local said = #w.printed
    choice.set("vendorsell")
    H.assertEq(w.env.EasyFindTSMDB.source, "vendorsell")
    H.assertEq(#w.printed, said, "picked on the page: nothing said in chat")
end

function tests.settingsChoice_aCustomPriceLeads()
    local w = H.load({ saved = { source = "avg(dbmarket, dbminbuyout)" } }):login()
    local kit = H.Kit()
    w:extension().settings({}, kit)
    H.assertEq(kit.made[2].choices[1].value, "avg(dbmarket, dbminbuyout)")
end

-- ==== switches and refreshes ================================================

function tests.switches_onUnlessFalse()
    local w = H.load():login()
    local o = Option(w, "Crafting queue rows")
    H.assertTrue(o.get(), "on by default")
    o.set(false)
    H.assertEq(w.env.EasyFindTSMDB.queue, false)
    o.set(true)
    H.assertNil(w.env.EasyFindTSMDB.queue, "on is nil: the saved table stays small")
    H.assertNil(Option(w, "Owned counts in tooltips"), "TSM's own tooltip has the counts")
end

function tests.groupChanges_oneRebuild()
    local w = H.load():login()
    local before = w.api.refreshes
    w.tsm.callbacks.EasyFind_TSM()
    w.tsm.callbacks.EasyFind_TSM()
    w:advance(1)
    H.assertEq(w.api.refreshes, before + 1, "changes in a burst rebuild once")
end

function tests.craftingWindowCloses_queueReadAgain()
    local w = H.load():login()
    local before = w.api.refreshes
    w.tsm.uiCallbacks.EasyFind_TSM(true, {})
    w:advance(1)
    H.assertEq(w.api.refreshes, before, "opening reads nothing")
    w.tsm.uiCallbacks.EasyFind_TSM(false)
    w:advance(1)
    H.assertEq(w.api.refreshes, before + 1, "closing reads the queue again")
end

-- ==== the shopping list =====================================================

local function Entries(note)
    local out = {}
    for i, e in ipairs(note.entries) do
        local l = e.line
        out[i] = string.format("%s %s x%d", e.ref, tostring(l.item or l.text), l.target)
    end
    return table.concat(out, ", ")
end

function tests.shoppingList_oneRow_theWholeQueuesMaterials()
    local w = H.load():login()
    local row = w:row("Crafting materials")
    H.assertEq(row.kind, "list")
    H.assertEq(row.searchCommandDesc, "2 materials for TSM's crafting queue")
    H.assertTrue(table.concat(row.keywords, " "):find("need", 1, true), "found by need")
    H.assertEq(w:provider().hint(row), "Open in Notes")
    local tt = H.Tooltip()
    w:provider().tooltip(row, tt)
    H.assertTrue(tt:Has("Copper Ore  4/5"), "have over need")
    H.assertTrue(tt:Has("Rough Stone  0/10"))
end

function tests.shoppingList_opensAsAChecklistNote()
    local w = H.load():login()
    w:provider().select(w:row("Crafting materials"))
    local note = w.api.notes["tsm:queue"]
    H.assertEq(note and note.title, "Crafting materials")
    H.assertEq(Entries(note), "i:2770 2770 x5, i:2835 2835 x10", "items counted toward what the queue needs, by name")
    H.assertEq(note.entries[1].line.link, "item", "counted from the bags")
    H.assertEq(w.api.opened[1], note.id, "opened in Notes")
    local cat = w.api.checklists.handlers.category
    H.assertEq(cat.window, "auctionhouse", "tagged for the auction house")
end

function tests.shoppingList_followsTheQueue()
    local w = H.load():login()
    w.tsm.uiCallbacks.EasyFind_TSM(false)
    H.assertNil(w.api.notes["tsm:queue"], "no note made unasked")
    w:provider().select(w:row("Crafting materials"))
    local note = w.api.notes["tsm:queue"]
    w.tsm.queue[1][3] = 2
    w.tsm.uiCallbacks.EasyFind_TSM(false)
    H.assertEq(Entries(note), "i:2770 2770 x2, i:2835 2835 x4", "the crafting window closed")
    w.tsm.queue[1][3] = 1
    w.api.checklists.handlers.shown(note.id, "queue")
    H.assertEq(Entries(note), "i:2770 2770 x1, i:2835 2835 x2", "opened in Notes")
end

function tests.shoppingList_none_whenNothingNeeded_orQueueOff()
    local data = H.TsmData()
    data.queue = { { "r:7421", "", 2 } }
    H.assertNil(H.load({ tsmData = data }):login():row("Crafting materials"), "a queue needing nothing")
    H.assertNil(H.load({ saved = { queue = false } }):login():row("Crafting materials"), "queue rows off")
end

-- ==== Notes' shopping list prices and auction searches (MINOR 7) =============

local function Keys(list)
    local out = {}
    for i, s in ipairs(list) do out[i] = s.key end
    return table.concat(out, ",")
end

function tests.notesPrices_everyMoneySource_theCommonOnesFirst()
    local w = H.load({ minor = 7 }):login()
    local def = w.api.priceSources.tsm
    H.assertEq(def and def.label, "TSM", "picked by the extension's name")
    local kinds = def.sources()
    H.assertEq(Keys(kinds), "dbmarket,dbminbuyout,crafting,vendorsell,matprice", "no Sale Rate: it is no money")
    H.assertEq(kinds[1].label, "AuctionDB - Market Value", "TSM's own names")
end

function tests.notesPrices_bySourceKey_noTSMReasonAsANote()
    local w = H.load({ minor = 7 }):login()
    local price = w.api.priceSources.tsm.price
    H.assertEq(price("dbmarket", 2589), 120, "by the item id")
    H.assertEq(price("dbminbuyout", 2589, LINEN_LINK), 99, "by the link")
    H.assertEq(select("#", price("dbmarket", 2835)), 1, "none: nil alone, not TSM's reason")
    H.assertNil(price("dbmarket", 2835))
end

function tests.notesPrices_redrawnWhenTheAuctionHouseCloses()
    local w = H.load({ minor = 7 }):login()
    local before = w.api.priceRefreshes
    w:fire("AUCTION_HOUSE_CLOSED")
    H.assertEq(w.api.priceRefreshes, before + 1)
end

function tests.auctionSearch_onlyAtTSMsAuctionWindow()
    local w = H.load({ minor = 7 }):login()
    local search = w.api.auctionSearches.tsm
    H.assertEq(search(LINEN_LINK, "Linen Cloth"), false, "TSM's window is not up: the house's own box")
    H.assertNil(w.chat.legacy)
    w.tsm.shown.AUCTION = true
    H.assertEq(search(LINEN_LINK, "Linen Cloth"), true)
    H.assertEq(w.chat.legacy, LINEN_LINK, "linked through the global TSM wraps")
    H.assertNil(w.chat.inserted, "not through ChatFrameUtil, which TSM never sees")
end

function tests.auctionSearch_aTypedLine_linkedByName()
    local w = H.load({ minor = 7 }):login()
    local search = w.api.auctionSearches.tsm
    w.tsm.shown.AUCTION = true
    H.assertEq(search(nil, "Wool Cloth"), true)
    H.assertTrue(w.chat.legacy:find("Hitem:2592:", 1, true), "the item's link")
    w.chat.legacy = nil
    H.assertEq(search(nil, "Mystery Thing"), false, "an unknown name: no link to give TSM")
    H.assertNil(w.chat.legacy)
end

function tests.auctionSearch_notWhileAChatBoxIsOpen()
    local w = H.load({ minor = 7 }):login()
    w.tsm.shown.AUCTION = true
    w.chat.active = { IsShown = function() return true end, Insert = function() end }
    H.assertEq(w.api.auctionSearches.tsm(LINEN_LINK, "Linen Cloth"), false, "the link would land in chat")
    H.assertNil(w.chat.legacy)
end

function tests.olderEasyFind_noNotesHooks()
    local w = H.load({ minor = 6 }):login()
    H.assertNil(w.api.priceSources.tsm)
    H.assertNil(w.api.auctionSearches.tsm)
    w:fire("AUCTION_HOUSE_CLOSED")
    H.assertEq(#w.api.bad, 0)
end

return H.runSuite("TSM", tests)
