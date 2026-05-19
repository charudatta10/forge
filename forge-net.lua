-- forge-net.lua
--
-- Minimal pure Lua forge networking daemon
--
-- Features:
-- - peer identity
-- - peer registry
-- - repo announcements
-- - local gossip
-- - simple P2P metadata layer
--
-- Future:
-- - libp2p bridge
-- - torrent replication
-- - QUIC
-- - Kademlia
--
-- Usage:
--
-- lua forge-net.lua peer-id
-- lua forge-net.lua peers
-- lua forge-net.lua announce myrepo
-- lua forge-net.lua gossip issues "hello"
-- lua forge-net.lua fetch p2p://peer/repo

math.randomseed(os.time())

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

local HOME =
    os.getenv("HOME")
    or os.getenv("USERPROFILE")
    or "."

local ROOT = HOME .. "/.forge"

local PEERS_FILE = ROOT .. "/peers.db"
local REPOS_FILE = ROOT .. "/repos.db"
local ID_FILE = ROOT .. "/peer.id"

------------------------------------------------------------
-- UTIL
------------------------------------------------------------

local function mkdir(path)
    if package.config:sub(1,1) == "\\" then
        os.execute('mkdir "' .. path .. '" >NUL 2>NUL')
    else
        os.execute('mkdir -p "' .. path .. '" >/dev/null 2>&1')
    end
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

local function read(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end

    local s = f:read("*a")
    f:close()

    return s
end

local function write(path, data)
    local f = assert(io.open(path, "w"))
    f:write(data)
    f:close()
end

local function append(path, data)
    local f = assert(io.open(path, "a"))
    f:write(data)
    f:close()
end

local function split(str, sep)
    local out = {}

    for part in str:gmatch("([^" .. sep .. "]+)") do
        table.insert(out, part)
    end

    return out
end

------------------------------------------------------------
-- INIT
------------------------------------------------------------

mkdir(ROOT)

if not exists(ID_FILE) then
    local id =
        "peer-"
        .. tostring(os.time())
        .. "-"
        .. tostring(math.random(100000, 999999))

    write(ID_FILE, id)
end

------------------------------------------------------------
-- DATABASE
------------------------------------------------------------

local function load_lines(path)
    if not exists(path) then
        return {}
    end

    local lines = {}

    for line in io.lines(path) do
        table.insert(lines, line)
    end

    return lines
end

------------------------------------------------------------
-- PEER ID
------------------------------------------------------------

local function peer_id()
    local id = read(ID_FILE)

    if not id then
        return "unknown"
    end

    return id:gsub("\n", "")
end

------------------------------------------------------------
-- NETWORKING
------------------------------------------------------------

local function net_send(address, message)
    local ip, port = address:match("([^:]+):?(%d*)")
    port = (port ~= "" and port) or "9090"
    
    -- On Windows, use powershell to send the message reliably
    if package.config:sub(1,1) == "\\" then
        -- Use a single-quoted string for PowerShell to avoid escape hell
        local safe_msg = message:gsub("'", "''")
        local ps = string.format([[powershell -NoProfile -ExecutionPolicy Bypass -Command "$m = '%s'; $m | nc %s %s"]], 
            safe_msg, ip, port)
        os.execute(ps)
    else
        local cmd = string.format("echo %s | nc %s %s", 
            string.format("%q", message), ip, port)
        os.execute(cmd)
    end
end

local function broadcast(message)
    local lines = load_lines(PEERS_FILE)
    for _, p in ipairs(lines) do
        if p ~= "" and p:match("^[%d%.]+:%d+$") then
            net_send(p, message)
        end
    end
end

------------------------------------------------------------
-- PEERS
------------------------------------------------------------

local function is_known_peer(address)
    local lines = load_lines(PEERS_FILE)
    for _, p in ipairs(lines) do
        if p == address then return true end
    end
    return false
end

local function register(address, skip_notify)
    if not address or address == "" then return end
    
    -- Clean address (only IP:Port)
    address = address:match("^[%d%.]+:%d+$")
    if not address then return end

    if is_known_peer(address) then
        return
    end

    append(PEERS_FILE, address .. "\n")
    print("registered peer " .. address)

    if not skip_notify then
        net_send(address, "HELLO")
    end
end

local function peers()
    local lines = load_lines(PEERS_FILE)

    if #lines == 0 then
        print("[]")
        return
    end

    for _, p in ipairs(lines) do
        print(p)
    end
end

------------------------------------------------------------
-- ANNOUNCE
------------------------------------------------------------

local function announce(repo)
    if not repo then
        print("missing repo")
        os.exit(1)
    end

    local id = peer_id()
    local ts = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local entry = ts .. "|" .. id .. "|" .. repo

    append(REPOS_FILE, entry .. "\n")
    print("announced " .. repo)

    broadcast("ANNOUNCE|" .. entry)
end

------------------------------------------------------------
-- GOSSIP
------------------------------------------------------------

local function gossip(topic, message)
    if not topic or not message then
        print("usage: gossip <topic> <message>")
        os.exit(1)
    end

    print(
        "[gossip]"
        .. " topic=" .. topic
        .. " msg=" .. message
    )

    broadcast("GOSSIP|" .. topic .. "|" .. message)
end

------------------------------------------------------------
-- DISCOVERY (UDP)
------------------------------------------------------------

local function discovery_broadcast(port)
    port = port or "9090"
    -- Use powershell for UDP broadcast on Windows
    if package.config:sub(1,1) == "\\" then
        local ps = string.format([[powershell -NoProfile -ExecutionPolicy Bypass -Command "$c = New-Object System.Net.Sockets.UdpClient; $e = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Broadcast, 9999); $b = [System.Text.Encoding]::UTF8.GetBytes('FORGE_PEER:%s'); $c.Send($b, $b.Length, $e); $c.Close()"]], port)
        os.execute(ps)
    else
        -- On Linux/Mac, try nc -u -b (if supported)
        os.execute("echo FORGE_PEER:" .. port .. " | nc -u -b 255.255.255.255 9999")
    end
end


local function discovery_listen()
    print("listening for peers...")
    if package.config:sub(1,1) == "\\" then
        -- Force NoProfile and redirect stderr to nul to hide profile errors
        local ps = [[powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'SilentlyContinue'; $c = New-Object System.Net.Sockets.UdpClient(9999); $e = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0); while($true) { try { $b = $c.Receive([ref]$e); $m = [System.Text.Encoding]::UTF8.GetString($b); if($m -match 'FORGE_PEER:(\d+)') { Write-Output \"$($e.Address):$($Matches[1])\" } } catch {} } 2>$null"]]
        local f = io.popen(ps)
        if f then
            for line in f:lines() do
                -- Be extremely strict: only accept lines that ARE just IP:Port
                local clean = line:match("^%s*([%d%.]+:%d+)%s*$")
                if clean then
                    print("discovered peer: " .. clean)
                    register(clean)
                end
            end
            f:close()
        end
    end
end

------------------------------------------------------------
-- DAEMON
------------------------------------------------------------

local function handle_message(msg)
    if not msg or msg == "" then return end
    
    local parts = split(msg, "|")
    local cmd = parts[1]

    if cmd == "HELLO" then
        print("received HELLO")
    elseif cmd == "ANNOUNCE" then
        local entry = table.concat(parts, "|", 2)
        append(REPOS_FILE, entry .. "\n")
        print("received announcement: " .. entry)
    elseif cmd == "GOSSIP" then
        local topic = parts[2]
        local message = parts[3]
        print("[gossip] topic=" .. (topic or "") .. " msg=" .. (message or ""))
    elseif cmd == "PEER" then
        register(parts[2], true)
    end
end

local function daemon(port)
    port = port or "9090"
    print("forge-net daemon listening on port " .. port)
    
    -- Start discovery listener in background
    if package.config:sub(1,1) == "\\" then
        os.execute("start /B lua forge-net.lua discovery-listen")
    end
    
    while true do
        -- Broadcast presence periodically (simplified: just once at start for now)
        discovery_broadcast(port)

        -- Use nc -l to wait for one connection
        local f = io.popen("nc -l -p " .. port)
        if f then
            local msg = f:read("*a")
            f:close()
            if msg and msg ~= "" then
                handle_message(msg:gsub("\n", ""):gsub("\r", ""))
            end
        end
    end
end

------------------------------------------------------------
-- FETCH
------------------------------------------------------------

local function fetch(uri)
    if not uri then
        print("missing uri")
        os.exit(1)
    end

    print("fetching " .. uri)

    local repo = uri:match(".+/(.+)$")

    if repo then
        print("resolved repository: " .. repo)
    end
end

------------------------------------------------------------
-- DISCOVER
------------------------------------------------------------

local function discover()
    local repos = load_lines(REPOS_FILE)

    if #repos == 0 then
        print("no repositories discovered")
        return
    end

    for _, r in ipairs(repos) do
        print(r)
    end
end

------------------------------------------------------------
-- HELP
------------------------------------------------------------

local function help()
    print([[
forge-net.lua

Commands:

  peer-id
  peers
  register <address>
  announce <repo>
  discover
  gossip <topic> <message>
  fetch <uri>
  daemon [--port port]
  discovery-listen
]])
end

------------------------------------------------------------
-- ROUTER
------------------------------------------------------------

local cmd = arg[1]

if not cmd or cmd == "help" then
    help()
    os.exit(0)
end

if cmd == "peer-id" then
    print(peer_id())
    os.exit(0)
end

if cmd == "peers" then
    peers()
    os.exit(0)
end

if cmd == "register" then
    register(arg[2])
    os.exit(0)
end

if cmd == "announce" then
    announce(arg[2])
    os.exit(0)
end

if cmd == "discover" then
    discover()
    os.exit(0)
end

if cmd == "gossip" then
    gossip(arg[2], arg[3])
    os.exit(0)
end

if cmd == "fetch" then
    fetch(arg[2])
    os.exit(0)
end

if cmd == "daemon" then
    local port = "9090"
    if arg[2] == "--port" then
        port = arg[3]
    elseif arg[2] then
        port = arg[2]
    end
    daemon(port)
    os.exit(0)
end

if cmd == "discovery-listen" then
    discovery_listen()
    os.exit(0)
end

print("unknown command")
os.exit(1)