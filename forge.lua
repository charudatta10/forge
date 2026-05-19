local json_ok, json = pcall(require, "dkjson")

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

local CONFIG = {
    version = "0.1.0",
    forge_home = os.getenv("FORGE_HOME")
        or ((os.getenv("HOME") or ".") .. "/.forge"),

    fossil_bin = os.getenv("FOSSIL_BIN") or "fossil",
    net_bin = os.getenv("FORGE_NET_BIN") or "lua forge-net.lua",
    rqbit_bin = os.getenv("RQBIT_BIN") or "rqbit",

    api_port = tonumber(os.getenv("FORGE_API_PORT") or "9090"),
    ui_port = tonumber(os.getenv("FORGE_UI_PORT") or "8080"),

    repositories_dir = "repos",
    peer_key = "peer.key",
}

------------------------------------------------------------
-- UTILITIES
------------------------------------------------------------

local function log(level, msg)
    io.stderr:write(string.format("[%s] %s\n", level, msg))
end

local function info(msg)
    log("INFO", msg)
end

local function warn(msg)
    log("WARN", msg)
end

local function fatal(msg)
    log("ERROR", msg)
    os.exit(1)
end

local function mkdir_p(path)
    if package.config:sub(1,1) == "\\" then
        os.execute(string.format('mkdir "%s" >NUL 2>NUL', path))
    else
        os.execute(string.format('mkdir -p "%s" >/dev/null 2>&1', path))
    end
end

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

local function shell_escape(s)
    if package.config:sub(1,1) == "\\" then
        s = s:gsub('"', '\\"')
        return '"' .. s .. '"'
    end

    s = s:gsub("'", "'\\''")
    return "'" .. s .. "'"
end

local function exec(cmd, args)
    args = args or {}

    local parts = { cmd }

    for _, a in ipairs(args) do
        table.insert(parts, shell_escape(a))
    end

    local full = table.concat(parts, " ")

    info(full)

    local ok, _, code = os.execute(full)

    if not ok then
        fatal("command failed: " .. tostring(code))
    end

    return code
end

local function capture(cmd)
    local f = io.popen(cmd)

    if not f then
        return nil
    end

    local out = f:read("*a")
    f:close()

    return out
end

------------------------------------------------------------
-- PATHS
------------------------------------------------------------

local function forge_path(...)
    local parts = { CONFIG.forge_home }

    for _, p in ipairs({...}) do
        table.insert(parts, p)
    end

    return table.concat(parts, "/")
end

------------------------------------------------------------
-- ENVIRONMENT
------------------------------------------------------------

local function ensure_environment()
    mkdir_p(CONFIG.forge_home)
    mkdir_p(forge_path(CONFIG.repositories_dir))

    local peer_key = forge_path(CONFIG.peer_key)

    if not file_exists(peer_key) then
        info("generating peer key")

        local key = tostring(os.time()) .. tostring(math.random())

        local f = io.open(peer_key, "w")
        f:write(key)
        f:close()
    end
end

------------------------------------------------------------
-- FOSSIL
------------------------------------------------------------

local function fossil(args)
    return exec(CONFIG.fossil_bin, args)
end

------------------------------------------------------------
-- NETWORK API
------------------------------------------------------------

local NET = {}

function NET.start()
    info("starting forge-net daemon")

    local cmd = string.format(
        "%s daemon --port %d > /dev/null 2>&1 &",
        CONFIG.net_bin,
        CONFIG.api_port
    )

    if package.config:sub(1,1) == "\\" then
        cmd = string.format(
            'start /B %s daemon --port %d',
            CONFIG.net_bin,
            CONFIG.api_port
        )
    end

    os.execute(cmd)
end

function NET.peer_id()
    local out = capture(
        string.format(
            "%s peer-id",
            CONFIG.net_bin
        )
    )

    return out and out:gsub("\n", "") or "unknown"
end

function NET.peers()
    exec(CONFIG.net_bin, {
        "peers"
    })
end

function NET.announce(repo)
    exec(CONFIG.net_bin, {
        "announce",
        repo
    })
end

function NET.fetch(uri)
    exec(CONFIG.net_bin, {
        "fetch",
        uri
    })
end

function NET.gossip(topic, message)
    exec(CONFIG.net_bin, {
        "gossip",
        topic,
        message
    })
end

------------------------------------------------------------
-- TORRENT
------------------------------------------------------------

local TORRENT = {}

function TORRENT.seed(path)
    exec(CONFIG.rqbit_bin, {
        "seed",
        path
    })
end

function TORRENT.download(magnet)
    exec(CONFIG.rqbit_bin, {
        "download",
        magnet
    })
end

------------------------------------------------------------
-- REPOSITORIES
------------------------------------------------------------

local function repo_file(name)
    return forge_path(CONFIG.repositories_dir, name .. ".fossil")
end

local function repo_dir(name)
    return forge_path(CONFIG.repositories_dir, name)
end

------------------------------------------------------------
-- COMMANDS
------------------------------------------------------------

local CMD = {}

function CMD.version()
    print(CONFIG.version)
end

function CMD.peerid()
    print(NET.peer_id())
end

function CMD.init(name)
    if not name then
        fatal("missing repository name")
    end

    local rf = repo_file(name)
    local rd = repo_dir(name)

    if file_exists(rf) then
        fatal("repository already exists")
    end

    mkdir_p(rd)

    fossil({
        "init",
        rf
    })

    local cwd = lfs and lfs.currentdir() or "."

    fossil({
        "open",
        rf,
        "--workdir",
        rd
    })

    info("repository initialized")

    NET.announce(name)
end

function CMD.clone(uri)
    if not uri then
        fatal("missing URI")
    end

    if uri:match("^p2p://") then
        NET.fetch(uri)
        return
    end

    fossil({
        "clone",
        uri,
        "repo.fossil"
    })

    fossil({
        "open",
        "repo.fossil"
    })
end

function CMD.sync(repo)
    if not repo then
        fatal("missing repository")
    end

    local rf = repo_file(repo)

    fossil({
        "sync",
        rf
    })

    NET.announce(repo)

    TORRENT.seed(rf)

    info("repository synchronized")
end

function CMD.serve(repo)
    if not repo then
        fatal("missing repository")
    end

    local rf = repo_file(repo)

    fossil({
        "server",
        rf,
        "--localhost",
        "--port",
        tostring(CONFIG.ui_port)
    })
end

function CMD.peers()
    NET.peers()
end

function CMD.announce(repo)
    NET.announce(repo)
end

function CMD.gossip(topic, message)
    if not topic or not message then
        fatal("usage: gossip <topic> <message>")
    end

    NET.gossip(topic, message)
end

function CMD.seed(repo)
    if not repo then
        fatal("missing repository")
    end

    TORRENT.seed(repo_file(repo))
end

function CMD.download(magnet)
    if not magnet then
        fatal("missing magnet link")
    end

    TORRENT.download(magnet)
end

function CMD.issue(repo, title)
    if not repo or not title then
        fatal("usage: issue <repo> <title>")
    end

    local rf = repo_file(repo)

    fossil({
        "ticket",
        "add",
        "title",
        title,
        "--repository",
        rf
    })

    NET.gossip(
        "issues",
        repo .. ":" .. title
    )
end

function CMD.status(repo)
    if not repo then
        fatal("missing repository")
    end

    local rf = repo_file(repo)

    fossil({
        "changes",
        "--repository",
        rf
    })
end

function CMD.startnet()
    NET.start()
end

------------------------------------------------------------
-- ROUTER
------------------------------------------------------------

local function usage()
    print([[
forge.lua - decentralized Fossil forge

Commands:
  version
  peerid
  startnet
  init <repo>
  clone <uri>
  sync <repo>
  serve <repo>
  peers
  announce <repo>
  gossip <topic> <message>
  seed <repo>
  download <magnet>
  issue <repo> <title>
  status <repo>
]])
end

------------------------------------------------------------
-- MAIN
------------------------------------------------------------

ensure_environment()

local command = arg[1]

if not command then
    usage()
    os.exit(0)
end

local fn = CMD[command]

if not fn then
    fatal("unknown command: " .. tostring(command))
end

fn(arg[2], arg[3], arg[4], arg[5])





