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
-- PEERS
------------------------------------------------------------

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

    local entry =
        os.date("!%Y-%m-%dT%H:%M:%SZ")
        .. "|"
        .. peer_id()
        .. "|"
        .. repo

    append(REPOS_FILE, entry .. "\n")

    print("announced " .. repo)
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
-- REGISTER PEER
------------------------------------------------------------

local function register(address)
    if not address then
        print("missing address")
        os.exit(1)
    end

    append(PEERS_FILE, address .. "\n")

    print("registered peer " .. address)
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
]])
end

------------------------------------------------------------
-- ROUTER
------------------------------------------------------------

local cmd = arg[1]

if not cmd then
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

print("unknown command")
os.exit(1)