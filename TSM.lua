-- TradeSkillMaster's groups, queued crafts, prices and owned counts in
-- EasyFind, read through TSM_API; nothing of TSM's is written or copied.
local _, ns = ...
local API = EasyFind and EasyFind.API
if not (API and API.VERSION == 1) then return end

local L = ns.L
local sformat, tconcat, tonumber, tsort = string.format, table.concat, tonumber, table.sort

local function Print(text)
    print(sformat("|cff66ccff%s:|r %s", L["EXT_NAME"], text))
end

-- Loaded beside TradeSkillMaster (OptionalDeps), nothing without it.
local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
if not (IsAddOnLoaded and IsAddOnLoaded("TradeSkillMaster")) then return end
-- Prices on EasyFind's own item rows (RegisterRowDecorator) came in MINOR 4.
if (API.MINOR or 0) < 4 then return Print(L["NEEDS_EASYFIND"]) end
local KEY = "tsm"
local CATEGORY = L["CATEGORY"]
local TAG = "EasyFind_TSM"              -- our name in TSM's callback registries
local ICON = "Interface\\AddOns\\EasyFind_TSM\\icon"
local DEFAULT_SOURCE = "dbmarket"
local FALLBACK_SOURCE = "vendorsell"     -- when the chosen price has none (Era realms have no market data)
local LOAD_RETRY, LOAD_TRIES = 2, 30    -- seconds between, and how many, waits for TSM's data
local PRICE_TTL = 600                   -- seconds a looked-up price is kept
local MAX_MATERIALS = 12                -- material lines in a queue row's tooltip
-- TSM price sources offered in the settings choice, those the installed TSM has.
local SOURCES = { "dbmarket", "dbminbuyout", "dbhistorical", "dbrecent", "dbregionmarketavg",
                  "dbregionhistorical", "dbregionsaleavg", "crafting", "vendorsell", "vendorbuy",
                  "destroy", "disenchant" }
-- Short forms players type for group words ("bs mats").
local SHORT = { blacksmithing = "bs", jewelcrafting = "jc", leatherworking = "lw", materials = "mats",
                ["first aid"] = "fa" }

local C_Item, C_Timer = C_Item, C_Timer
local IsControlKeyDown, IsAltKeyDown = IsControlKeyDown, IsAltKeyDown

-- Module state in one table (upvalue limit).
local S = {
    ready = false,
    sourceLabel = "",
    fallbackLabel = "",
    prices = {},          -- itemString -> copper, false for none
    vendor = {},          -- the same for FALLBACK_SOURCE
    strings = {},         -- link or itemID -> TSM item string, false for none
    refreshPending = false,
}
local scratch = {}

local function DB()
    EasyFindTSMDB = EasyFindTSMDB or {}
    return EasyFindTSMDB
end

-- ==== TSM ===================================================================

local NEED = { "GetGroupPaths", "FormatGroupPath", "SplitGroupPath", "GetGroupPathByItem", "GetGroupItems",
               "RegisterGroupItemCallback", "GetActiveProfile", "GetPriceSourceKeys", "GetPriceSourceDescription",
               "IsCustomPriceValid", "GetCustomPriceValue", "FormatMoneyString", "ToItemString", "GetItemName",
               "GetItemLink", "GetBagQuantity", "GetBankQuantity", "GetMailQuantity", "GetPlayerTotals",
               "GetGuildTotal", "GetWarbankQuantity", "CraftingQueueIterator", "GetCraftingQueueItemMaterials" }

local function Bind()
    local T = TSM_API
    if type(T) ~= "table" then return false end
    for i = 1, #NEED do
        if type(T[NEED[i]]) ~= "function" then return false end
    end
    return true
end

-- TSM's settings load after its files: the active profile answers once
-- they have, and every other call is safe from then on.
local function Loaded()
    local ok, profile = pcall(TSM_API.GetActiveProfile)
    return ok and type(profile) == "string"
end

local function Source()
    local s = DB().source
    if type(s) == "string" and s ~= "" then return s end
    return DEFAULT_SOURCE
end

-- A plain source key shows TSM's name for it; a custom price string itself.
local function SetSourceLabel()
    local ok, label = pcall(TSM_API.GetPriceSourceDescription, Source())
    S.sourceLabel = ok and label or Source()
    S.fallbackLabel = TSM_API.GetPriceSourceDescription(FALLBACK_SOURCE)
end

local function ItemString(link, itemID)
    local key = link or itemID
    if not key then return nil end
    local s = S.strings[key]
    if s == nil then
        s = (link and TSM_API.ToItemString(link)) or (itemID and TSM_API.ToItemString("item:" .. itemID)) or false
        S.strings[key] = s
    end
    return s or nil
end

local function ItemID(itemString)
    return tonumber(itemString:match("^i:(%d+)"))
end

local function ItemName(itemString)
    local name = TSM_API.GetItemName(itemString)
    if name and name ~= "" then return name end
    local id = ItemID(itemString)
    name = id and C_Item.GetItemNameByID(id)
    if name and name ~= "" then return name end
    return sformat("%s %s", ITEM or "Item", itemString)
end

local function ItemIcon(itemString)
    local id = ItemID(itemString)
    return id and C_Item.GetItemIconByID(id) or nil
end

-- A source's value in copper, nil when TSM has none; kept until the
-- source changes or the price cache turns over.
local function Lookup(cache, source, itemString)
    local cached = cache[itemString]
    if cached ~= nil then return cached or nil end
    local value = TSM_API.GetCustomPriceValue(source, itemString)
    cache[itemString] = value or false
    return value
end

-- The chosen price, else the vendor's and true.
local function Price(itemString)
    local value = Lookup(S.prices, Source(), itemString)
    if value or Source() == FALLBACK_SOURCE then return value end
    value = Lookup(S.vendor, FALLBACK_SOURCE, itemString)
    return value, value ~= nil
end

local function Invalidate()
    wipe(S.prices)
    wipe(S.vendor)
    wipe(S.strings)
    API.RefreshRowDecorations()
end

local function LeafName(path)
    local _, name = TSM_API.SplitGroupPath(path)
    return name
end

local function AddWord(out, name)
    out[#out + 1] = name
    local short = SHORT[name:lower()]
    if short then out[#out + 1] = short end
end

-- Every segment of a group path and its short form, the words that find the group.
local function PathWords(path, out)
    local parent, name = TSM_API.SplitGroupPath(path)
    AddWord(out, name)
    while parent do
        parent, name = TSM_API.SplitGroupPath(parent)
        AddWord(out, name)
    end
    return out
end

-- ==== tooltip lines =========================================================

local function AddPriceLine(tt, itemString)
    local value, fallback = Price(itemString)
    if fallback then
        tt:AddLine(S.sourceLabel .. ": " .. L["NO_PRICE"], 1, 1, 1)
        tt:AddLine(sformat(L["FALLBACK_FMT"], S.fallbackLabel, TSM_API.FormatMoneyString(value)), 1, 1, 1)
        return
    end
    tt:AddLine(S.sourceLabel .. ": " .. (value and TSM_API.FormatMoneyString(value) or L["NO_PRICE"]), 1, 1, 1)
end

local function Part(parts, label, n)
    if n > 0 then parts[#parts + 1] = label .. " " .. n end
end

-- Owned counts: this character, other characters, guild banks and the
-- warband bank, zero parts left out.
local function AddCountLines(tt, itemString)
    local player, alts, auctions, altAuctions = TSM_API.GetPlayerTotals(itemString)
    local guild = TSM_API.GetGuildTotal(itemString)
    local warbank = TSM_API.GetWarbankQuantity(itemString)
    local total = player + alts + auctions + altAuctions + guild + warbank
    if total == 0 then return end
    tt:AddLine(sformat(L["OWNED_FMT"], total), 1, 0.82, 0)
    wipe(scratch)
    Part(scratch, L["OWNED_BAGS"], TSM_API.GetBagQuantity(itemString))
    Part(scratch, L["OWNED_BANK"], TSM_API.GetBankQuantity(itemString))
    Part(scratch, L["OWNED_MAIL"], TSM_API.GetMailQuantity(itemString))
    Part(scratch, L["OWNED_AUCTIONS"], auctions)
    if #scratch > 0 then tt:AddLine(tconcat(scratch, ", "), 1, 1, 1) end
    wipe(scratch)
    Part(scratch, L["OWNED_ALTS"], alts)
    Part(scratch, L["OWNED_ALT_AUCTIONS"], altAuctions)
    Part(scratch, L["OWNED_GUILD"], guild)
    Part(scratch, L["OWNED_WARBANK"], warbank)
    if #scratch > 0 then tt:AddLine(tconcat(scratch, ", "), 1, 1, 1) end
end

local function ByName(a, b)
    return a.name < b.name
end

-- A queued craft's materials, have over need for the whole queue entry.
local function AddMaterialLines(tt, row)
    local mats = {}
    TSM_API.GetCraftingQueueItemMaterials(row.recipeString, mats)
    local list = {}
    for itemString, qty in pairs(mats) do
        list[#list + 1] = { name = ItemName(itemString), itemString = itemString, need = qty * row.num }
    end
    if #list == 0 then return end
    tsort(list, ByName)
    tt:AddLine(" ")
    tt:AddLine(L["MATERIALS"])
    for i = 1, math.min(#list, MAX_MATERIALS) do
        local m = list[i]
        local have = TSM_API.GetPlayerTotals(m.itemString)
        local enough = have >= m.need
        tt:AddLine(sformat("%s  %d/%d", m.name, have, m.need), enough and 0.5 or 1, enough and 1 or 0.5, 0.5)
    end
end

-- ==== rows ==================================================================

local function GroupRow(path, out)
    local items = TSM_API.GetGroupItems(path, true, {})
    local words = PathWords(path, {})
    local leaf = words[1]
    words[#words + 1] = "group"
    local count = #items
    out[#out + 1] = {
        name = TSM_API.FormatGroupPath(path), kind = "group", groupPath = path, leaf = leaf,
        icon = items[1] and ItemIcon(items[1]) or nil, keywords = words,
        searchCommandDesc = sformat(count == 1 and L["GROUP_ITEM_FMT"] or L["GROUP_ITEMS_FMT"], count),
    }
end

-- The group's own items (a subgroup's come with the subgroup), each
-- carrying the words of its path.
local function ItemRows(path, out)
    local items = TSM_API.GetGroupItems(path, false, {})
    local words = PathWords(path, {})
    local group = TSM_API.FormatGroupPath(path)
    for i = 1, #items do
        local s = items[i]
        out[#out + 1] = { name = ItemName(s), kind = "item", itemString = s, itemID = ItemID(s),
                          icon = ItemIcon(s), groupPath = path, keywords = words, searchCommandDesc = group }
    end
end

local function QueueRows(out)
    for _, recipeString, itemString, num in TSM_API.CraftingQueueIterator() do
        if itemString ~= "" then
            out[#out + 1] = { name = ItemName(itemString), kind = "queue", itemString = itemString,
                              itemID = ItemID(itemString), icon = ItemIcon(itemString), recipeString = recipeString,
                              num = num, keywords = { "craft", "crafting", "queue" },
                              searchCommandDesc = sformat(L["QUEUE_FMT"], num) }
        end
    end
end

local KIND_ORDER = { group = 1, queue = 2, item = 3 }

-- Groups lead, then the queue, then items, each by name.
local function KindThenName(a, b)
    if a.kind ~= b.kind then return KIND_ORDER[a.kind] < KIND_ORDER[b.kind] end
    return a.name < b.name
end

local function Rows()
    if not (S.ready and Loaded()) then return {} end
    local out = {}
    local paths = TSM_API.GetGroupPaths({})
    for i = 1, #paths do GroupRow(paths[i], out) end
    if DB().queue ~= false then QueueRows(out) end
    for i = 1, #paths do ItemRows(paths[i], out) end
    tsort(out, KindThenName)
    return out
end

local function Refresh()
    if S.refreshPending or not S.ready then return end
    S.refreshPending = true
    C_Timer.After(0.5, function()
        S.refreshPending = false
        API.RefreshSearchProvider(KEY)
    end)
end

local function ShowGroup(path)
    API.ShowScope(KEY, LeafName(path))
end

-- 12.1 moved the chat calls to ChatFrameUtil; older clients keep the globals.
local function InsertChatLink(link)
    local getActive = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow) or ChatEdit_GetActiveWindow
    local active = getActive and getActive()
    if active and active:IsShown() then return active:Insert(link) end
    local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    if insert and insert(link) then return end
    local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
    if open then open(link) end
end

-- A group lists its items; an item links in chat, Ctrl tries it on,
-- Alt lists its group.
local function Select(row)
    if not S.ready then return end
    if row.kind == "group" then return ShowGroup(row.groupPath) end
    local link = TSM_API.GetItemLink(row.itemString)
    if IsControlKeyDown() then return DressUpItemLink(link) end
    if IsAltKeyDown() then
        local path = row.groupPath or TSM_API.GetGroupPathByItem(row.itemString)
        if path then ShowGroup(path) end
        return
    end
    InsertChatLink(link)
end

local function Hint(row)
    if row.kind == "group" then return L["HINT_LIST_ITEMS"] end
    local path = row.groupPath or (S.ready and TSM_API.GetGroupPathByItem(row.itemString))
    return { click = L["HINT_LINK"], ctrl = L["HINT_DRESS"], alt = path and L["HINT_GROUP"] or nil }
end

local function Tooltip(row, tt)
    if not S.ready then return false end
    if row.kind == "group" then
        tt:SetText(row.name)
        tt:AddLine(row.searchCommandDesc, 1, 1, 1)
        return true
    end
    tt:SetHyperlink(TSM_API.GetItemLink(row.itemString))
    tt:AddLine(" ")
    AddPriceLine(tt, row.itemString)
    if DB().counts ~= false then AddCountLines(tt, row.itemString) end
    if row.kind == "queue" then AddMaterialLines(tt, row) end
    return true
end

local function GroupMenu(path)
    if not path then return nil end
    return { { kind = "action", label = L["MENU_SHOW_GROUP"], onClick = function() ShowGroup(path) end } }
end

local function Menu(row)
    if not (S.ready and row.kind == "queue") then return nil end
    return GroupMenu(TSM_API.GetGroupPathByItem(row.itemString))
end

-- ==== EasyFind's own item rows ==============================================

-- The decorator takes our rows too: their tooltip and menu already carry
-- these lines, so only the price at the row's right is added there.
local function Ours(row)
    return row.category == CATEGORY
end

-- A vendor price standing in shows dimmed.
local function RowText(row, link)
    if not S.ready or DB().prices == false then return nil end
    local s = ItemString(link, row.itemID)
    if not s then return nil end
    local value, fallback = Price(s)
    if fallback then return value, "dim" end
    return value
end

-- "TSM: <group>" after the row's own subtext.
local function RowSubtext(row)
    local s = S.ready and not Ours(row) and ItemString(row.bagItemLink, row.itemID)
    local path = s and TSM_API.GetGroupPathByItem(s)
    if not path or path == "" then return nil end
    return sformat(L["GROUP_SUBTEXT_FMT"], TSM_API.FormatGroupPath(path))
end

local function RowTooltip(row, link, tt)
    local s = S.ready and not Ours(row) and ItemString(link, row.itemID)
    if not s then return end
    AddPriceLine(tt, s)
    if DB().counts ~= false then AddCountLines(tt, s) end
end

local function RowMenu(row, link)
    local s = S.ready and not Ours(row) and ItemString(link, row.itemID)
    return s and GroupMenu(TSM_API.GetGroupPathByItem(s)) or nil
end

-- Every item row in EasyFind: the price at its right, its group under
-- its name, the counts under its tooltip, its TSM group on its menu.
local function HookRows()
    API.RegisterRowDecorator({ id = KEY, slot = "price", label = L["DECOR_LABEL"],
                               text = RowText, subtext = RowSubtext, tooltip = RowTooltip, menu = RowMenu })
end

-- ==== settings ==============================================================

local function SetSource(str, quiet)
    if not S.ready then return Print(L["NOT_READY"]) end
    local valid, err = TSM_API.IsCustomPriceValid(str)
    if not valid then return Print(sformat(L["SOURCE_BAD_FMT"], err or str)) end
    DB().source = str
    SetSourceLabel()
    Invalidate()
    Refresh()
    if not quiet then Print(sformat(L["SOURCE_SET_FMT"], S.sourceLabel)) end
end

-- The known sources the installed TSM offers; a custom string in use
-- leads the list so the choice shows it.
local function SourceChoices()
    local out = {}
    local current = Source()
    if not S.ready then return { { label = current, value = current } } end
    local have = {}
    local keys = TSM_API.GetPriceSourceKeys({})
    for i = 1, #keys do have[keys[i]] = true end
    for i = 1, #SOURCES do
        local key = SOURCES[i]
        if have[key] then out[#out + 1] = { label = TSM_API.GetPriceSourceDescription(key), value = key } end
    end
    if not have[current] then table.insert(out, 1, { label = current, value = current }) end
    return out
end

local function Option(key, label, tip)
    return {
        label = label, tooltip = tip,
        get = function() return DB()[key] ~= false end,
        set = function(on)
            if on then DB()[key] = nil else DB()[key] = false end
            Invalidate()
            Refresh()
        end,
    }
end

local function FilterOptions()
    return { Option("prices", L["OPT_PRICES"], L["OPT_PRICES_TIP"]),
             Option("counts", L["OPT_COUNTS"], L["OPT_COUNTS_TIP"]),
             Option("queue", L["OPT_QUEUE"], L["OPT_QUEUE_TIP"]) }
end

local function QueueCount()
    local n = 0
    for _ in TSM_API.CraftingQueueIterator() do n = n + 1 end
    return n
end

SLASH_EASYFINDTSM1 = "/eftsm"
SlashCmdList.EASYFINDTSM = function(msg)
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "source" and rest ~= "" then return SetSource(rest) end
    if not S.ready then return Print(L["NOT_READY"]) end
    Print(sformat(L["STATUS_FMT"], S.sourceLabel, #TSM_API.GetGroupPaths({}), QueueCount()))
    Print(L["USAGE"])
end

-- ==== registration ==========================================================

API.RegisterExtension({
    id = KEY,
    name = L["EXT_NAME"],
    description = L["EXT_DESC"],
    icon = ICON,
    keywords = { "tsm", "tradeskillmaster", "groups", "prices", "gold" },
    scope = KEY,
    settings = function(page, kit)
        local below = kit.Title(page, L["EXT_NAME"], L["SETTINGS_HINT"])
        local choice = kit.Choice(page, L["OPT_SOURCE"], SourceChoices(), Source,
            function(value) SetSource(value, true) end, L["OPT_SOURCE_TIP"], DEFAULT_SOURCE)
        choice:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -8)
        below = choice
        local opts = FilterOptions()
        for i = 1, #opts do
            local box = kit.Checkbox(page, opts[i].label, opts[i].get, opts[i].set, opts[i].tooltip)
            box:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -4)
            below = box
        end
    end,
})

API.RegisterSearchProvider({
    key = KEY,
    label = L["PROVIDER_LABEL"],
    category = CATEGORY,
    extension = KEY,
    words = { "tsm", "group", "groups", "craft", "queue" },
    aliases = { "tsm" },
    lowResults = true,
    options = FilterOptions(),
    rows = Rows,
    select = Select,
    tooltip = Tooltip,
    hint = Hint,
    menu = Menu,
    -- With nothing typed, the scope lists the groups and the queue.
    browse = function(row) return row.kind ~= "item" end,
})

local function Start()
    S.ready = true
    SetSourceLabel()
    TSM_API.RegisterGroupItemCallback(TAG, Refresh)
    -- The queue changes inside TSM's crafting window: read again when it closes.
    if type(TSM_API.RegisterUICallback) == "function" then
        TSM_API.RegisterUICallback("CRAFTING", TAG, function(shown) if not shown then Refresh() end end)
    end
    C_Timer.NewTicker(PRICE_TTL, Invalidate)
    HookRows()
    API.RefreshSearchProvider(KEY)
end

local events = CreateFrame("Frame")

local function WaitForTSM(tries)
    if Loaded() then
        events:RegisterEvent("AUCTION_HOUSE_CLOSED")
        return Start()
    end
    if tries <= 0 then return Print(L["NOT_READY"]) end
    C_Timer.After(LOAD_RETRY, function() WaitForTSM(tries - 1) end)
end

events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if not Bind() then return Print(L["NOT_READY"]) end
        return WaitForTSM(LOAD_TRIES)
    end
    -- The auction house closed: TSM may hold new prices.
    Invalidate()
end)
