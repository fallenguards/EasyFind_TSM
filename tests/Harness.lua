-- Offline harness: loads the toc's files into a sandbox with a stubbed
-- game, a fake TSM_API and a recording EasyFind.API.
--   local H = require("Harness")
--   local w = H.load()            -- EasyFind 1.5, TSM loaded and ready
--   w:fire("PLAYER_ENTERING_WORLD")
local H = {}

local source = debug.getinfo(1, "S").source:sub(2)
local ROOT = source:gsub("[/\\]?tests[/\\]Harness%.lua$", "")
if ROOT == "" or ROOT == source then ROOT = "." end
H.ROOT = ROOT
-- EasyFind's checkout, for its API's field lists: EASYFIND_ROOT, else beside this repo.
H.EASYFIND_ROOT = os.getenv("EASYFIND_ROOT") or (ROOT .. "/../EasyFind")
H.TOC = "EasyFind_TSM.toc"
H.ADDON = "EasyFind_TSM"

local function Read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("a")
    f:close()
    return s
end
H.Read = Read

-- The toc's fields and its Lua files in load order.
function H.Toc()
    local text = assert(Read(ROOT .. "/" .. H.TOC), "no " .. H.TOC)
    local fields, files = {}, {}
    for line in text:gmatch("[^\r\n]+") do
        local k, v = line:match("^## ([%w%-]+):%s*(.-)%s*$")
        if k then
            fields[k] = v
        elseif not line:match("^#") and line:match("%.lua$") then
            files[#files + 1] = line:gsub("\\", "/")
        end
    end
    return fields, files
end

-- EasyFind's own field lists and MINOR, read from its Core/API.lua; nil
-- when no checkout is found.
function H.EasyFindApi()
    local src = Read(H.EASYFIND_ROOT .. "/Core/API.lua")
    if not src then return nil end
    local function Fields(name)
        local body = assert(src:match("\nlocal " .. name .. " = (%b{})"), name .. " not found in Core/API.lua")
        local t = {}
        for k, v in body:gmatch('([%w_]+)%s*=%s*"(%w+)"') do t[k] = v end
        return t
    end
    return {
        minor = tonumber(src:match("local API = { VERSION = 1, MINOR = (%d+) }")),
        extension = Fields("FIELDS"),
        provider = Fields("PROVIDER_FIELDS"),
        decorator = Fields("DECORATOR_FIELDS"),
    }
end

-- ==== fake TradeSkillMaster =================================================
-- TSM_API's shape and argument checks (Core/API.lua of TSM 4.14): group
-- paths joined by a backtick, item strings "i:<id>", recipe strings "r:<id>".

local SEP = "`"

function H.TsmData()
    return {
        loaded = true,
        groups = { "Mats", "Mats`Cloth", "Gear" },
        items = { Mats = { "i:2770" }, ["Mats`Cloth"] = { "i:2592", "i:2589" }, Gear = {} },
        names = { ["i:2589"] = "Linen Cloth", ["i:2592"] = "Wool Cloth", ["i:2770"] = "Copper Ore",
                  ["i:2840"] = "Copper Bar", ["i:2835"] = "Rough Stone", ["i:7005"] = "Skinning Knife" },
        sources = { dbmarket = "AuctionDB - Market Value", dbminbuyout = "AuctionDB - Minimum Buyout",
                    vendorsell = "Vendor Sell Price", crafting = "Crafting Cost", matprice = "Material Price" },
        prices = { dbmarket = { ["i:2589"] = 120, ["i:2592"] = 300, ["i:2770"] = 45, ["i:7005"] = 900 },
                   dbminbuyout = { ["i:2589"] = 99 }, vendorsell = { ["i:2589"] = 13 } },
        bags = { ["i:2589"] = 20, ["i:2770"] = 4 }, bank = { ["i:2589"] = 5 }, mail = {}, auctions = { ["i:2589"] = 40 },
        alts = { ["i:2589"] = 7 }, altAuctions = {}, guild = { ["i:2589"] = 100 }, warbank = { ["i:2592"] = 3 },
        -- A queued enchant crafts no item: its item string is "".
        queue = { { "r:2840", "i:2840", 5 }, { "r:7421", "", 2 } },
        mats = { ["r:2840"] = { ["i:2770"] = 1, ["i:2835"] = 2 } },
        callbacks = {}, uiCallbacks = {},
    }
end

local function FakeTSM(d)
    local T = {}
    local function Check(cond, msg) if not cond then error(msg, 3) end end
    local function ItemString(s)
        Check(type(s) == "string" and s:match("^[ip]:%d+"), "Invalid 'itemString' argument type (must be a TSM item string): " .. tostring(s))
        return s
    end
    local function Path(p) Check(type(p) == "string" and p ~= "", "Invalid 'path' argument: " .. tostring(p)) end
    local function Owns(tbl, s) return tbl[ItemString(s)] or 0 end
    local function Value(str, s)
        if d.prices[str] then return d.prices[str][s] end
        local best
        for key in str:gmatch("[%a_]+") do
            local v = d.prices[key] and d.prices[key][s]
            if v and (not best or v > best) then best = v end
        end
        return best
    end

    function T.GetActiveProfile()
        if not d.loaded then error("attempt to index a nil value (field 'settingsDB')") end
        return "Default"
    end
    function T.GetGroupPaths(result)
        Check(type(result) == "table", "Invalid 'result' argument")
        for i = 1, #d.groups do result[#result + 1] = d.groups[i] end
        return result
    end
    function T.FormatGroupPath(p) Path(p) return (p:gsub(SEP, "->")) end
    function T.SplitGroupPath(p)
        Path(p)
        local parent, name = p:match("^(.*)" .. SEP .. "([^" .. SEP .. "]+)$")
        if parent then return parent, name end
        return nil, p
    end
    function T.GetGroupPathByItem(s)
        ItemString(s)
        for path, list in pairs(d.items) do
            for i = 1, #list do if list[i] == s then return path end end
        end
        return nil
    end
    function T.GetGroupItems(p, includeSubGroups, result)
        Path(p)
        Check(type(includeSubGroups) == "boolean", "Invalid 'includeSubGroups' argument")
        Check(type(result) == "table", "Invalid 'result' argument")
        for path, list in pairs(d.items) do
            if path == p or (includeSubGroups and path:sub(1, #p + 1) == p .. SEP) then
                for i = 1, #list do result[#result + 1] = list[i] end
            end
        end
        return result
    end
    function T.RegisterGroupItemCallback(tag, fn)
        Check(type(tag) == "string" and tag ~= "" and type(fn) == "function", "Invalid callback arguments")
        Check(not d.callbacks[tag], "Callback already registered for addonTag: " .. tag)
        d.callbacks[tag] = fn
    end
    function T.RegisterUICallback(ui, tag, fn)
        Check(ui == "CRAFTING", "Invalid uiName: " .. tostring(ui))
        Check(type(tag) == "string" and tag ~= "" and type(fn) == "function", "Invalid callback arguments")
        d.uiCallbacks[tag] = fn
    end
    function T.GetPriceSourceKeys(result)
        Check(type(result) == "table", "Invalid 'result' argument")
        local keys = {}
        for k in pairs(d.sources) do keys[#keys + 1] = k end
        table.sort(keys)
        for i = 1, #keys do result[#result + 1] = keys[i] end
        return result
    end
    function T.GetPriceSourceDescription(key)
        Check(type(key) == "string", "Invalid 'key' argument")
        Check(d.sources[key], "Unknown price source key: " .. key)
        return d.sources[key]
    end
    function T.IsCustomPriceValid(str)
        Check(type(str) == "string", "Invalid 'customPriceStr' argument")
        for key in str:gmatch("[%a_]+") do
            if not (d.sources[key] or key == "max" or key == "min" or key == "avg") then
                return false, "Unknown word: " .. key
            end
        end
        return true
    end
    function T.GetCustomPriceValue(str, s)
        Check(type(str) == "string", "Invalid 'customPriceStr' argument")
        return Value(str, ItemString(s))
    end
    function T.FormatMoneyString(v)
        Check(type(v) == "number", "Invalid 'value' argument")
        return v .. "c"
    end
    function T.ToItemString(item)
        Check(type(item) == "string", "Invalid 'item' argument")
        local id = item:match("item:(%d+)")
        if id then return "i:" .. id end
        return item:match("^[ip]:%d+")
    end
    function T.GetItemName(s) return d.names[ItemString(s)] end
    function T.GetItemLink(s)
        local id = ItemString(s):match("%d+")
        return "|cffffffff|Hitem:" .. id .. "::|h[" .. (d.names[s] or "Unknown Item") .. "]|h|r"
    end
    function T.GetBagQuantity(s) return Owns(d.bags, s) end
    function T.GetBankQuantity(s) return Owns(d.bank, s) end
    function T.GetMailQuantity(s) return Owns(d.mail, s) end
    function T.GetGuildTotal(s) return Owns(d.guild, s) end
    function T.GetWarbankQuantity(s) return Owns(d.warbank, s) end
    function T.GetPlayerTotals(s)
        return Owns(d.bags, s) + Owns(d.bank, s) + Owns(d.mail, s), Owns(d.alts, s), Owns(d.auctions, s), Owns(d.altAuctions, s)
    end
    function T.CraftingQueueIterator()
        local flat = {}
        for i = 1, #d.queue do
            local q = d.queue[i]
            flat[#flat + 1], flat[#flat + 2], flat[#flat + 3] = q[1], q[2], q[3]
        end
        return function(tbl, index)
            index = index + 3
            if index > #tbl then return end
            return index, tbl[index - 2], tbl[index - 1], tbl[index]
        end, flat, 0
    end
    function T.GetCraftingQueueItemMaterials(recipe, result)
        Check(type(recipe) == "string" and recipe:match("^r:%d+"), "Invalid 'recipeString' argument: " .. tostring(recipe))
        Check(type(result) == "table", "Invalid 'result' argument")
        for s, n in pairs(d.mats[recipe] or {}) do result[s] = n end
    end

    -- TSM refuses a colon call (its CheckCallMethod).
    local api = {}
    for name, fn in pairs(T) do
        api[name] = function(first, ...)
            if first == api then error("Invalid usage of colon operator to call TSM_API function", 2) end
            return fn(first, ...)
        end
    end
    return api
end

-- ==== recording EasyFind.API ================================================
-- Fields checked against EasyFind's own lists: an unknown field, or one of
-- the wrong type, is recorded in w.api.bad.

local function NewAPI(w, minor, fields)
    local rec = { extensions = {}, providers = {}, decorators = {}, bad = {}, scopes = {},
                  refreshes = 0, decorRefreshes = 0 }
    local API = { VERSION = 1, MINOR = minor }
    local function Check(what, list, def)
        if not list then return end
        for k, v in pairs(def) do
            local want = list[k]
            local ok = want == "any" or (want == "texture" and (type(v) == "string" or type(v) == "number"))
                       or type(v) == want
            if not ok then rec.bad[#rec.bad + 1] = string.format("%s.%s (%s, wants %s)", what, k, type(v), tostring(want)) end
        end
    end
    function API.RegisterExtension(def)
        Check("RegisterExtension", fields and fields.extension, def)
        assert(type(def.id) == "string" and def.name and def.icon, "RegisterExtension: id, name and icon")
        rec.extensions[def.id] = def
        return true
    end
    function API.RegisterSearchProvider(def)
        Check("RegisterSearchProvider", fields and fields.provider, def)
        assert(type(def.label) == "string", "RegisterSearchProvider: label is required")
        assert(rec.extensions[def.extension], "RegisterSearchProvider: extension must be registered first")
        rec.providers[def.key] = def
        return true
    end
    function API.RegisterRowDecorator(def)
        assert(minor >= 4, "RegisterRowDecorator came in MINOR 4")
        Check("RegisterRowDecorator", fields and fields.decorator, def)
        local owner = rec.extensions[def.extension or def.id]
        assert(owner and owner.icon, "RegisterRowDecorator: extension must be registered first, with its icon")
        rec.decorators[#rec.decorators + 1] = def
        return true
    end
    function API.RefreshRowDecorations() rec.decorRefreshes = rec.decorRefreshes + 1 end
    function API.RefreshSearchProvider(key) rec.refreshes = rec.refreshes + 1 rec.refreshedKey = key end
    function API.ShowScope(key, text) rec.scopes[#rec.scopes + 1] = { key = key, text = text } end
    w.api = rec
    return API
end

-- ==== the game ==============================================================

local World = {}
World.__index = World

-- Runs every timer due within the next `seconds`, earliest first; tickers re-arm.
function World:advance(seconds)
    local stop = self.now + (seconds or 0)
    while true do
        local due, at
        for i = 1, #self.timers do
            local t = self.timers[i]
            if not t.cancelled and t.at <= stop and (not at or t.at < at) then due, at = i, t.at end
        end
        if not due then break end
        local t = table.remove(self.timers, due)
        self.now = t.at
        if t.every then
            t.at = t.at + t.every
            self.timers[#self.timers + 1] = t
        end
        t.fn()
    end
    self.now = stop
end

function World:fire(event, ...)
    for i = 1, #self.frames do
        local f = self.frames[i]
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

-- Logs in: the entering-world event, then up to `seconds` of waiting.
function World:login(seconds)
    self:fire("PLAYER_ENTERING_WORLD", true, false)
    self:advance(seconds or 0)
    return self
end

function World:provider() return self.api.providers.tsm end
function World:extension() return self.api.extensions.tsm end
function World:decorator() return self.api.decorators[1] end
function World:slash(msg) return self.env.SlashCmdList.EASYFINDTSM(msg) end

-- The provider's rows as EasyFind keeps them: each carrying its category.
function World:rows()
    local p = self:provider()
    local rows = p.rows()
    for i = 1, #rows do rows[i].category = p.category end
    return rows
end

function World:row(name)
    for _, row in ipairs(self:rows()) do
        if row.name == name then return row end
    end
end

local function NewFrame(w)
    local f = { scripts = {}, events = {} }
    function f:SetScript(which, fn) self.scripts[which] = fn end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:IsEventRegistered(e) return self.events[e] == true end
    w.frames[#w.frames + 1] = f
    return f
end

-- A GameTooltip that keeps its lines.
function H.Tooltip()
    local tt = { lines = {}, colors = {} }
    function tt:SetText(text) self.lines = { text } end
    function tt:SetHyperlink(link) self.link = link self.lines = { link } end
    function tt:AddLine(text, r, g, b)
        self.lines[#self.lines + 1] = text
        self.colors[#self.lines] = { r, g, b }
    end
    function tt:Has(pattern)
        for i = 1, #self.lines do
            if tostring(self.lines[i]):find(pattern, 1, true) then return i end
        end
    end
    return tt
end

-- A settings kit that records the controls made.
function H.Kit()
    local kit = { made = {} }
    local function Control(kind, fields)
        fields.kind = kind
        function fields:SetPoint() end
        kit.made[#kit.made + 1] = fields
        return fields
    end
    function kit.Title(_, title, hint) return Control("title", { title = title, hint = hint }) end
    function kit.Choice(_, label, choices, get, set, tooltip, default)
        return Control("choice", { label = label, choices = choices, get = get, set = set, tooltip = tooltip, default = default })
    end
    function kit.Checkbox(_, label, get, set, tooltip)
        return Control("checkbox", { label = label, get = get, set = set, tooltip = tooltip })
    end
    return kit
end

-- opts: api = false (no EasyFind), minor (EasyFind's API MINOR, 5),
-- tsm = false (TradeSkillMaster not loaded), tsmData (H.TsmData() changed),
-- strip = { names } (TSM_API functions left out), saved (EasyFindTSMDB).
function H.load(opts)
    opts = opts or {}
    local w = setmetatable({ printed = {}, timers = {}, frames = {}, now = 0, keys = {},
                             chat = { insertWorks = true }, dressed = {} }, World)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    w.env = env

    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
        w.printed[#w.printed + 1] = table.concat(parts, " ")
    end
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.GetLocale = function() return "enUS" end
    env.CreateFrame = function() return NewFrame(w) end
    env.SlashCmdList = {}
    env.C_Timer = {
        After = function(sec, fn) w.timers[#w.timers + 1] = { at = w.now + sec, fn = fn } end,
        NewTicker = function(sec, fn)
            local t = { at = w.now + sec, every = sec, fn = fn }
            function t:Cancel() self.cancelled = true end
            w.timers[#w.timers + 1] = t
            return t
        end,
    }
    env.IsControlKeyDown = function() return w.keys.ctrl == true end
    env.IsAltKeyDown = function() return w.keys.alt == true end
    env.DressUpItemLink = function(link) w.dressed[#w.dressed + 1] = link end
    env.ChatFrameUtil = {
        GetActiveWindow = function() return w.chat.active end,
        InsertLink = function(link)
            if w.chat.insertWorks then w.chat.inserted = link end
            return w.chat.insertWorks
        end,
        OpenChat = function(text) w.chat.opened = text end,
    }

    local tsm = opts.tsmData or H.TsmData()
    w.tsm = tsm
    env.C_Item = {
        GetItemNameByID = function(id) return tsm.names["i:" .. id] end,
        GetItemIconByID = function(id) return 100000 + id end,
    }
    local tsmLoaded = opts.tsm ~= false
    env.C_AddOns = { IsAddOnLoaded = function(name) return name == "TradeSkillMaster" and tsmLoaded end }
    if tsmLoaded then
        env.TSM_API = FakeTSM(tsm)
        for _, name in ipairs(opts.strip or {}) do env.TSM_API[name] = nil end
    end
    if opts.api ~= false then
        env.EasyFind = { API = NewAPI(w, opts.minor or 5, H.EasyFindApi()) }
    else
        w.api = { extensions = {}, providers = {}, decorators = {}, bad = {} }
    end
    env.EasyFindTSMDB = opts.saved

    local ns = {}
    w.ns = ns
    local _, files = H.Toc()
    for _, rel in ipairs(files) do
        local chunk = assert(loadfile(ROOT .. "/" .. rel, "t", env))
        chunk(H.ADDON, ns)
    end
    return w
end

-- ==== assertions and the runner =============================================

local function fmt(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function H.assertEq(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label or "assertEq", fmt(expected), fmt(actual)), 2)
    end
end

function H.assertTrue(cond, label)
    if not cond then error((label or "assertTrue") .. ": expected truthy, got " .. fmt(cond), 2) end
end

function H.assertNil(v, label)
    if v ~= nil then error((label or "assertNil") .. ": expected nil, got " .. fmt(v), 2) end
end

function H.runSuite(name, tests)
    print("== " .. name .. " ==")
    local names = {}
    for testName in pairs(tests) do names[#names + 1] = testName end
    table.sort(names)
    local pass, fail, failures = 0, 0, {}
    for _, testName in ipairs(names) do
        local ok, err = xpcall(tests[testName], debug.traceback)
        if ok then
            pass = pass + 1
            print("  ok   " .. testName)
        else
            fail = fail + 1
            failures[#failures + 1] = { name = testName, err = err }
            print("  FAIL " .. testName .. "\n       " .. tostring(err):gsub("\n", "\n       "))
        end
    end
    return { pass = pass, fail = fail, failures = failures }
end

return H
