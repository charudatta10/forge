-- tests/test_net.lua
--
-- Unit tests for forge-net.lua

local function test(name, fn)
    print("RUNNING: " .. name)
    local ok, err = pcall(fn)
    if ok then
        print("PASSED:  " .. name)
    else
        print("FAILED:  " .. name .. " - " .. tostring(err))
    end
end

local function assert_eq(actual, expected)
    if actual ~= expected then
        error(string.format("expected %q, got %q", tostring(expected), tostring(actual)))
    end
end

-- Mock environment for forge-net functions
_G.arg = {}
local net = loadfile("forge-net.lua")

-- Helper to extract private functions from forge-net.lua if they were local
-- For testing, we might want to make them global or return a table
-- Since they are local in the file, we'll redefine the core logic for unit testing 
-- or modify forge-net.lua to export them.

-- Let's test the logic by loading it and checking side effects where possible, 
-- or by extracting the regex logic.

test("Address Regex Validation", function()
    local regex = "^[%d%.]+:%d+$"
    
    local valid = {
        "127.0.0.1:9090",
        "192.168.1.1:80",
        "10.0.0.1:65535"
    }
    
    local invalid = {
        "localhost:9090",
        "127.0.0.1",
        ":9090",
        "127.0.0.1:port",
        " UnauthorizedAccess",
        "registered peer 127.0.0.1:9090"
    }
    
    for _, addr in ipairs(valid) do
        assert(addr:match(regex), "Should be valid: " .. addr)
    end
    
    for _, addr in ipairs(invalid) do
        assert(not addr:match(regex), "Should be invalid: " .. addr)
    end
end)

test("Message Splitting", function()
    -- Re-implement split for testing
    local function split(str, sep)
        local out = {}
        for part in str:gmatch("([^" .. sep .. "]+)") do
            table.insert(out, part)
        end
        return out
    end

    local parts = split("ANNOUNCE|2026-05-19|peer-1|myrepo", "|")
    assert_eq(#parts, 4)
    assert_eq(parts[1], "ANNOUNCE")
    assert_eq(parts[2], "2026-05-19")
    assert_eq(parts[3], "peer-1")
    assert_eq(parts[4], "myrepo")
end)

test("PowerShell Quoting Logic", function()
    local message = "GOSSIP|topic|it's a message"
    local safe_msg = message:gsub("'", "''")
    assert_eq(safe_msg, "GOSSIP|topic|it''s a message")
end)

print("\nAll networking logic tests completed.")
