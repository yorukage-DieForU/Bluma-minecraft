-- ============================================================
-- BLUMA MINER BRIDGE v6
--
-- Este programa NAO substitui o seu miner64.
-- Ele executa miner64 e, ao mesmo tempo:
--   - mantem Rednet aberto
--   - envia heartbeat
--   - envia fuel/inventario real
--   - recebe START/PAUSE/RESUME/STOP
--
-- IMPORTANTE:
-- Se o miner64 ja esta rodando DIRETAMENTE agora, deixe ele
-- terminar. Depois passe a iniciar por este arquivo.
-- ============================================================

local MACHINE_ID = "MINER-01"
local PROTOCOL = "BLUMA"
local MINER_PROGRAM = "miner64"
local HEARTBEAT_SECONDS = 2

local modem = peripheral.find("modem")

if not modem then
    error("BLUMA MINER: modem nao encontrado")
end

local modemName = peripheral.getName(modem)

if not rednet.isOpen(modemName) then
    rednet.open(modemName)
end

local machineState = "STANDBY"
local coreId = nil
local minerCo = nil
local minerFilter = nil
local paused = false
local heartbeatTimer = os.startTimer(0.2)

local function minerExists()
    return fs.exists(MINER_PROGRAM) or fs.exists(MINER_PROGRAM .. ".lua")
end

local function usedSlots()
    local count = 0

    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
            count = count + 1
        end
    end

    return count
end

local function telemetry(packet)
    packet.id = MACHINE_ID
    packet.state = machineState
    packet.fuel = turtle.getFuelLevel()
    packet.usedSlots = usedSlots()

    return packet
end

local function send(packet)
    telemetry(packet)

    if coreId then
        rednet.send(coreId, packet, PROTOCOL)
    else
        rednet.broadcast(packet, PROTOCOL)
    end
end

local function heartbeat(message)
    send({
        type = "HEARTBEAT",
        message = message
    })
end

local function ack(requestId, ok, message)
    send({
        type = "ACK",
        requestId = requestId,
        ok = ok,
        message = message
    })
end

local function clearMiner()
    minerCo = nil
    minerFilter = nil
    paused = false
end

local function resumeMiner(event)
    if not minerCo then return end
    if paused then return end

    if coroutine.status(minerCo) == "dead" then
        clearMiner()

        if machineState == "RUNNING" then
            machineState = "FINISHED"
        end

        heartbeat("miner64 finished")
        return
    end

    if minerFilter and event and event[1] ~= minerFilter then
        return
    end

    local ok, yielded = coroutine.resume(minerCo, table.unpack(event or {}))

    if not ok then
        machineState = "ERROR"
        local err = tostring(yielded)
        clearMiner()
        send({
            type = "STATUS",
            message = err
        })
        return
    end

    minerFilter = yielded

    if coroutine.status(minerCo) == "dead" then
        clearMiner()
        machineState = "FINISHED"

        send({
            type = "STATUS",
            message = "miner64 finished"
        })
    end
end

local function startMiner()
    if minerCo and coroutine.status(minerCo) ~= "dead" then
        paused = false
        machineState = "RUNNING"

        return true, "Mineradora ja esta rodando."
    end

    if not minerExists() then
        machineState = "ERROR"

        return false, "Programa miner64 nao encontrado."
    end

    machineState = "STARTING"
    paused = false

    minerCo = coroutine.create(function()
        shell.run(MINER_PROGRAM)
    end)

    resumeMiner({})

    if not minerCo then
        if machineState == "FINISHED" then
            return true, "miner64 terminou imediatamente."
        end

        return false, "miner64 falhou ao iniciar."
    end

    machineState = "RUNNING"

    heartbeat("miner64 running")

    return true, "Mineradora iniciada e confirmada."
end

local function pauseMiner()
    if not minerCo then
        return false, "Mineradora nao esta rodando."
    end

    paused = true
    machineState = "PAUSED"

    heartbeat("miner64 paused")

    return true, "Mineradora pausada."
end

local function resumeMinerCommand()
    if not minerCo then
        return startMiner()
    end

    paused = false
    machineState = "RUNNING"

    heartbeat("miner64 resumed")

    return true, "Mineradora retomada."
end

local function stopMiner()
    clearMiner()
    machineState = "STANDBY"

    heartbeat("miner64 stopped")

    return true, "Mineracao interrompida. Bridge continua online."
end

local function handleCommand(sender, packet)
    if type(packet) ~= "table" then return end
    if packet.type ~= "COMMAND" then return end
    if packet.id and packet.id ~= MACHINE_ID then return end

    coreId = sender

    local action = string.upper(tostring(packet.action or ""))

    local ok = false
    local message = "Comando desconhecido."

    if action == "START" then
        ok, message = startMiner()

    elseif action == "PAUSE" then
        ok, message = pauseMiner()

    elseif action == "RESUME" then
        ok, message = resumeMinerCommand()

    elseif action == "STOP" then
        ok, message = stopMiner()

    elseif action == "STATUS" then
        ok = true
        message = "Status enviado."
    end

    ack(packet.requestId, ok, message)
end

term.clear()
term.setCursorPos(1, 1)

print("BLUMA MINER BRIDGE v6")
print("Machine: " .. MACHINE_ID)
print("Computer ID: " .. tostring(os.getComputerID()))
print("Program: " .. MINER_PROGRAM)
print("")
print("Bridge online.")

heartbeat("bridge online")

while true do
    local event = { os.pullEventRaw() }
    local name = event[1]

    if name == "terminate" then
        machineState = "OFFLINE"
        heartbeat("bridge terminated")
        return
    end

    if name == "rednet_message" then
        local sender = event[2]
        local packet = event[3]
        local protocol = event[4]

        if protocol == PROTOCOL then
            handleCommand(sender, packet)
        end

    elseif name == "timer" and event[2] == heartbeatTimer then
        heartbeatTimer = os.startTimer(HEARTBEAT_SECONDS)

        if minerCo and not paused then
            heartbeat("miner64 active")
        elseif paused then
            heartbeat("miner64 paused")
        else
            heartbeat("bridge ready")
        end
    end

    resumeMiner(event)
end
