-- Runs every tests/test_*.lua. From the addon's folder: lua tests/Run.lua
-- EasyFind's checkout is read for its API field lists: EASYFIND_ROOT, else
-- the folder beside this repo.
local source = debug.getinfo(1, "S").source:sub(2)
local DIR = source:gsub("[/\\]Run%.lua$", "")
if DIR == source then DIR = "." end
package.path = DIR .. "/?.lua;" .. package.path

local files = {}
local handle = io.popen(string.format([[ls "%s"/test_*.lua 2>/dev/null]], DIR:gsub("\\", "/")))
if handle then
    for line in handle:lines() do files[#files + 1] = line end
    handle:close()
end
table.sort(files)
if #files == 0 then
    print("No test files found in " .. DIR)
    os.exit(1)
end

local pass, fail, failures = 0, 0, {}
for _, file in ipairs(files) do
    local chunk, err = loadfile(file)
    local ok, result = false, err
    if chunk then ok, result = xpcall(chunk, debug.traceback) end
    if ok and type(result) == "table" then
        pass, fail = pass + result.pass, fail + result.fail
        for _, f in ipairs(result.failures) do failures[#failures + 1] = f end
    else
        fail = fail + 1
        failures[#failures + 1] = { name = file, err = result }
        print("ERROR " .. file .. ": " .. tostring(result))
    end
end

print(string.format("\n== Results: %d passed, %d failed ==", pass, fail))
for _, f in ipairs(failures) do print("  FAIL " .. tostring(f.name)) end
os.exit(fail == 0 and 0 or 1)
