--- QuickStack: Lightweight client→host networking module
--- Uses ServerExecRPC (client→host) and ClientMessage (host→client)
--- for operations that require server authority (battery terminal swap,
--- locker label setting).

local UEHelpers = require("UEHelpers")
local network = {}

local PREFIX = "QS_"
local handlers = {}  -- msgType -> function(senderPC, payload)

--- Check if this instance is the host (only host has UWESaveGame)
function network.isHost()
    local save = FindFirstOf("UWESaveGame")
    return save ~= nil and save:IsValid()
end

--- Register a handler for incoming messages from clients (host-side)
--- handler(senderPC, payload) where payload is the string after "QS_TYPE|"
function network.onMessage(msgType, handler)
    handlers[msgType] = handler
end

--- Send a message to the host via ServerExecRPC
--- On the host, this calls back into the local hook (self-send)
function network.sendToHost(msgType, payload)
    local pc = UEHelpers:GetPlayerController()
    if not pc or not pc:IsValid() then
        print(string.format("[QuickStack] network.sendToHost(%s): no valid PC\n", msgType))
        return
    end
    local msg = PREFIX .. msgType
    if payload and payload ~= "" then
        msg = msg .. "|" .. payload
    end
    print(string.format("[QuickStack] network.sendToHost: %s (isHost=%s)\n", msg, tostring(network.isHost())))
    pc:ServerExecRPC(msg)
end

--- Send a message to a specific client via ClientMessage
function network.sendToClient(clientPC, msgType, payload)
    if not clientPC or not clientPC:IsValid() then return end
    local msg = PREFIX .. msgType
    if payload and payload ~= "" then
        msg = msg .. "|" .. payload
    end
    clientPC:ClientMessage(msg, FName("Event"), 10.0)
end

-- Hook ServerExecRPC to receive client messages on the host
RegisterHook("/Script/Engine.PlayerController:ServerExecRPC", function(ctx, msgParam)
    local ok, raw = pcall(function() return msgParam:get():ToString() end)
    if not ok or not raw then return end
    if raw:sub(1, #PREFIX) ~= PREFIX then return end

    local body = raw:sub(#PREFIX + 1)
    local msgType, payload = body:match("^([^|]+)|?(.*)")
    if msgType and handlers[msgType] then
        local senderPC = ctx:get()
        handlers[msgType](senderPC, payload)
    end
end)

-- Hook ClientMessage to receive host messages on clients
RegisterHook("/Script/Engine.PlayerController:ClientMessage", function(_, sParam)
    local ok, raw = pcall(function() return sParam:get():ToString() end)
    if not ok or not raw then return end
    if raw:sub(1, #PREFIX) ~= PREFIX then return end

    local body = raw:sub(#PREFIX + 1)
    local msgType, payload = body:match("^([^|]+)|?(.*)")
    if msgType and handlers[msgType] then
        handlers[msgType](nil, payload)
    end
end)

print("[QuickStack] Network module loaded\n")

return network
