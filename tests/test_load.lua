-- The addon loaded offline: with EasyFind and TradeSkillMaster, without
-- either, on an older EasyFind, and while TSM's data is still loading.
local H = require("Harness")
local tests = {}

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function Printed(w, text)
    for _, line in ipairs(w.printed) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

function tests.toc_requiresOnlyEasyFind_loadsBesideTSM()
    local f = H.Toc()
    H.assertEq(f.Dependencies, "EasyFind", "Dependencies")
    H.assertEq(f.OptionalDeps, "TradeSkillMaster", "OptionalDeps")
    H.assertNil(f.LoadWith, "LoadWith loads nothing for a third-party addon")
    H.assertNil(f.LoadOnDemand, "LoadOnDemand")
    H.assertEq(f.SavedVariables, "EasyFindTSMDB", "SavedVariables")
end

-- TradeSkillMaster's own toc lists retail, Mists, TBC, Era and, since 4.15, Forever.
function tests.toc_interfaceLines_areTSMsClients()
    local f = H.Toc()
    H.assertEq(f.Interface, "120105, 50504, 20506, 11509, 16001", "Interface")
end

function tests.easyFindApi_isFoundForTheFieldChecks()
    local api = H.EasyFindApi()
    H.assertTrue(api ~= nil, "EasyFind's Core/API.lua at " .. H.EASYFIND_ROOT .. " (set EASYFIND_ROOT)")
    H.assertTrue(api.minor and api.minor >= 4, "EasyFind's API MINOR holds RegisterRowDecorator: " .. tostring(api.minor))
    H.assertEq(api.decorator.text, "function", "a decorator's text")
    H.assertEq(api.provider.browse, "function", "a provider's browse")
end

function tests.registers_extensionProviderAndDecorator()
    local w = H.load():login()
    local ext, p = w:extension(), w:provider()
    H.assertTrue(ext and ext.name == "TSM" and ext.icon == "Interface\\AddOns\\EasyFind_TSM\\icon", "the extension")
    H.assertEq(ext.scope, "tsm", "its scope")
    H.assertTrue(p and p.extension == "tsm", "its provider")
    H.assertEq(p.aliases[1], "tsm", "@tsm")
    for _, fn in ipairs({ "rows", "select", "tooltip", "hint", "menu", "browse" }) do
        H.assertEq(type(p[fn]), "function", "provider." .. fn)
    end
    H.assertEq(#p.options, 2, "two switches on its filter row")
    local d = w:decorator()
    H.assertTrue(d and d.id == "tsm" and d.slot == "price", "the row decorator, price slot")
    -- @tsm alone listed every priced item row (Forever, no groups, 2026-11-18).
    H.assertEq(d.browse and d.browse({ itemID = 3857, category = "fishing" }), false,
        "an empty @tsm lists none of EasyFind's item rows")
    H.assertEq(table.concat(w.api.bad, "; "), "", "every field one EasyFind knows, of its type")
end

function tests.settingsPage_builds()
    local w = H.load():login()
    local kit = H.Kit()
    w:extension().settings({}, kit)
    local kinds = {}
    for _, c in ipairs(kit.made) do kinds[#kinds + 1] = c.kind end
    H.assertEq(table.concat(kinds, ","), "title,choice,checkbox,checkbox", "title, source, two switches")
end

function tests.noEasyFind_nothingRegistered_noError()
    local w = H.load({ api = false })
    H.assertEq(#w.frames, 0, "no frames")
    H.assertEq(#w.printed, 0, "nothing said")
    H.assertNil(w.env.SlashCmdList.EASYFINDTSM, "no slash command")
end

function tests.noTSM_nothingRegistered_nothingSaid()
    local w = H.load({ tsm = false })
    H.assertEq(Count(w.api.extensions), 0, "no extension")
    H.assertEq(Count(w.api.providers), 0, "no provider")
    H.assertEq(#w.printed, 0, "a player without TSM hears nothing")
    H.assertEq(#w.frames, 0, "no frames")
end

function tests.olderEasyFind_saysToUpdate_registersNothing()
    local w = H.load({ minor = 3 })
    H.assertEq(Count(w.api.extensions), 0, "no extension")
    H.assertTrue(Printed(w, "newer EasyFind"), "says EasyFind needs an update")
    H.assertEq(#w.frames, 0, "no frames")
end

function tests.tsmLacksAFunction_saysSo_staysOff()
    local w = H.load({ strip = { "CraftingQueueIterator" } }):login(120)
    H.assertTrue(Printed(w, "not available"), "one line in chat")
    H.assertEq(#w.api.decorators, 0, "no row prices")
    H.assertEq(#w:rows(), 0, "no rows")
end

function tests.waitsForTSMsData_thenStarts()
    local data = H.TsmData()
    data.loaded = false
    local w = H.load({ tsmData = data }):login(5)
    H.assertEq(#w:rows(), 0, "no rows before TSM's settings load")
    H.assertEq(#w.api.decorators, 0, "no decorator yet")
    data.loaded = true
    w:advance(2)
    H.assertTrue(#w:rows() > 0, "rows once loaded")
    H.assertEq(#w.api.decorators, 1, "the decorator registered")
    H.assertEq(type(data.callbacks.EasyFind_TSM), "function", "listens for group changes")
    H.assertEq(type(data.uiCallbacks.EasyFind_TSM), "function", "listens for the crafting window")
    H.assertEq(w.api.refreshedKey, "tsm", "its rows rebuilt")
end

function tests.tsmNeverLoads_givesUpWithOneLine()
    local data = H.TsmData()
    data.loaded = false
    local w = H.load({ tsmData = data }):login(120)
    local n = 0
    for _, line in ipairs(w.printed) do if line:find("not available", 1, true) then n = n + 1 end end
    H.assertEq(n, 1, "one line after the last try")
    H.assertEq(#w.timers, 0, "no timer left running")
end

function tests.events_runWithoutError()
    local w = H.load():login()
    w:fire("AUCTION_HOUSE_CLOSED")
    w:fire("PLAYER_ENTERING_WORLD", false, true)
    w:advance(1200)
end

return H.runSuite("Load", tests)
