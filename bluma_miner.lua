-- ============================================================
-- BLUMA MINER AGENT v4
-- Coloque NA TURTLE que possui o programa "miner64".
--
-- Deixe a Turtle LIGADA executando este agente.
-- BLUMA pode iniciar/parar/pausar a MINERACAO.
-- Uma Turtle fisicamente desligada nao recebe Rednet.
-- ============================================================

local MACHINE_ID = "MINER-01"
local PROTOCOL = "BLUMA"
local MINER_PROGRAM = "miner64"
local HEARTBEAT_EVERY = 2

local modem = peripheral.find("modem")
if not modem then error("MINER-01: modem nao encontrado") end

local modemName = peripheral.getName(modem)
if not rednet.isOpen(modemName) then rednet.open(modemName) end

local coreId = nil
local state = "STANDBY"
local minerCo = nil
local paused = false
local heartbeatTimer = os.startTimer(0.2)

local function usedSlots()
    local n = 0
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then n = n + 1 end
    end
    return n
end

local function send(packet)
    packet.id = MACHINE_ID
    packet.state = state
    packet.fuel = turtle.getFuelLevel()
    packet.usedSlots = usedSlots()

    if coreId then
        rednet.send(coreId, packet, PROTOCOL)
    else
        rednet.broadcast(packet, PROTOCOL)
    end
end

local function heartbeat()
    send({ type = "HEARTBEAT" })
end

local function ack(requestId, ok, message)
    send({
        type = "ACK",
        requestId = requestId,
        ok = ok,
        message = message
    })
end

local function startMiner()
    if minerCo and coroutine.status(minerCo) ~= "dead" then
        if paused then
            paused = false
            state = "RUNNING"
            return true, "Mineracao retomada."
        end
        return true, "Mineradora ja esta em execucao."
    end

    if not fs.exists(MINER_PROGRAM) and not fs.exists(MINER_PROGRAM .. ".lua") then
        state = "ERROR"
        return false, "Programa '" .. MINER_PROGRAM .. "' nao encontrado na Turtle."
    end

    minerCo = coroutine.create(function()
        local ok = shell.run(MINER_PROGRAM)
        if ok then
            state = "FINISHED"
        else
            state = "ERROR"
        end
    end)

    paused = false
    state = "STARTING"

    local ok, err = coroutine.resume(minerCo)
    if not ok then
        minerCo = nil
        state = "ERROR"
        return false, tostring(err)
    end

    if coroutine.status(minerCo) == "dead" then
        minerCo = nil
        if state == "FINISHED" then
            return true, "Programa de mineracao finalizou imediatamente."
        end
        return false, "Programa de mineracao terminou ao iniciar."
    end

    state = "RUNNING"
    return true, "Mineradora iniciada e confirmada."
end

local function pauseMiner()
    if not minerCo or coroutine.status(minerCo) == "dead" then
        return false, "Mineradora nao esta rodando."
    end
    paused = true
    state = "PAUSED"
    return true, "Mineradora pausada."
end

local function resumeMiner()
    if not minerCo or coroutine.status(minerCo) == "dead" then
        return startMiner()
    end
    paused = false
    state = "RUNNING"
    return true, "Mineradora retomada."
end

local function stopMiner()
    if not minerCo or coroutine.status(minerCo) == "dead" then
        minerCo = nil
        paused = false
        state = "STANDBY"
        return true, "Mineradora ja estava parada."
    end

    -- Descarta a coroutine atual. Isso para o programa miner64.
    -- Se miner64 mantiver estado apenas em RAM, esse estado e perdido.
    minerCo = nil
    paused = false
    state = "STANDBY"
    return true, "Mineracao interrompida. Agente BLUMA continua online."
end

local function handleCommand(sender, packet)
    if type(packet) ~= "table" or packet.type ~= "COMMAND" then return end
    if packet.id and packet.id ~= MACHINE_ID then return end

    coreId = sender

    local action = string.upper(tostring(packet.action or ""))
    local ok, msg

    if action == "START" then
        ok, msg = startMiner()
    elseif action == "PAUSE" then
        ok, msg = pauseMiner()
    elseif action == "RESUME" then
        ok, msg = resumeMiner()
    elseif action == "STOP" then
        ok, msg = stopMiner()
    elseif action == "STATUS" then
        ok, msg = true, "Status enviado."
    else
        ok, msg = false, "Comando desconhecido: " .. action
    end

    ack(packet.requestId, ok, msg)
end

local function feedMiner(event)
    if not minerCo or paused then return end
    if coroutine.status(minerCo) == "dead" then
        minerCo = nil
        if state == "RUNNING" then state = "FINISHED" end
        return
    end

    local ok, err = coroutine.resume(minerCo, table.unpack(event))
    if not ok then
        print("MINER ERROR: " .. tostring(err))
        minerCo = nil
        state = "ERROR"
        send({ type = "STATUS", message = tostring(err) })
        return
    end

    if coroutine.status(minerCo) == "dead" then
        minerCo = nil
        if state == "RUNNING" then state = "FINISHED" end
        send({ type = "STATUS", message = "miner64 finalizado" })
    end
end

print("BLUMA MINER AGENT v4")
print("ID: " .. MACHINE_ID)
print("Computer ID: " .. os.getComputerID())
print("Aguardando BLUMA CORE...")

heartbeat()

while true do
    local event = { os.pullEventRaw() }
    local name = event[1]

    if name == "terminate" then
        state = "OFFLINE"
        heartbeat()
        return
    end

    if name == "rednet_message" then
        local sender = event[2]
        local packet = event[3]
        local protocol = event[4]

        if protocol == PROTOCOL then
            if type(packet) == "table" and packet.type == "CORE_DISCOVERY" then
                coreId = sender
                heartbeat()
            else
                handleCommand(sender, packet)
            end
        end
    elseif name == "timer" and event[2] == heartbeatTimer then
        heartbeat()
        heartbeatTimer = os.startTimer(HEARTBEAT_EVERY)
    end

    feedMiner(event)
end
