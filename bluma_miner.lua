-- ============================================================
-- BLUMA MINER AGENT v1
-- Supervisor para o minerador existente "miner64"
-- Permite START / PAUSE / RESUME / ABORT sem editar miner64.
-- ============================================================

local MACHINE_ID = "MINER-01"
local MINER_PROGRAM = "miner64"
local PROTOCOL = "bluma.machine.v1"
local PAIR_FILE = ".bluma_pair"
local HEARTBEAT_SECONDS = 3
local GPS_EVERY_SECONDS = 15

local modem = peripheral.find("modem")
if not modem then error("A Turtle precisa de Wireless Modem.",0) end
local modemName=peripheral.getName(modem)
if not rednet.isOpen(modemName) then rednet.open(modemName) end

local pairedCore=nil
local function loadPair()
    if not fs.exists(PAIR_FILE) then return end
    local h=fs.open(PAIR_FILE,"r")
    if h then pairedCore=tonumber(h.readAll()); h.close() end
end
local function savePair(id)
    pairedCore=id
    local h=fs.open(PAIR_FILE,"w")
    if h then h.write(tostring(id)); h.close() end
end
loadPair()

local worker=nil
local workerFilter=nil
local paused=false
local pausedEvent=nil
local machineState="STANDBY"
local lastError=nil
local lastPosition=nil
local lastGPS=0

local function getFuel()
    local f=turtle.getFuelLevel()
    if type(f)=="string" then return f end
    return tonumber(f) or 0
end

local function getInventory()
    local used=0
    local items={}
    for i=1,16 do
        local c=turtle.getItemCount(i)
        if c>0 then
            used=used+1
            local d=turtle.getItemDetail(i)
            if d and d.name then items[d.name]=(items[d.name] or 0)+c end
        end
    end
    return used,items
end

local function tryGPS()
    local now=os.epoch("utc")/1000
    if now-lastGPS<GPS_EVERY_SECONDS then return end
    lastGPS=now
    local x,y,z=gps.locate(0.25,false)
    if x then lastPosition={x=x,y=y,z=z} end
end

local function telemetry(kind)
    tryGPS()
    local slots,items=getInventory()
    return {
        kind=kind or "HEARTBEAT",
        machine_id=MACHINE_ID,
        state=machineState,
        fuel=getFuel(),
        slots_used=slots,
        items=items,
        position=lastPosition,
        program=MINER_PROGRAM,
        last_error=lastError,
        computer_id=os.getComputerID(),
    }
end

local function sendHeartbeat()
    local msg=telemetry("HEARTBEAT")
    if pairedCore then
        rednet.send(pairedCore,msg,PROTOCOL)
    else
        rednet.broadcast({kind="PAIR_REQUEST",machine_id=MACHINE_ID,state=machineState,computer_id=os.getComputerID()},PROTOCOL)
    end
end

local function sendAck(request,ok,message)
    if not pairedCore then return end
    rednet.send(pairedCore,{
        kind="ACK",
        machine_id=MACHINE_ID,
        request_id=request.request_id,
        ok=ok,
        action=request.action,
        state=machineState,
        message=message,
    },PROTOCOL)
    rednet.send(pairedCore,telemetry("STATE"),PROTOCOL)
end

local function resumeWorker(...)
    if not worker or paused then return end
    local ev={...}
    if #ev>0 and workerFilter and ev[1]~=workerFilter and ev[1]~="terminate" then return end
    local results={coroutine.resume(worker,table.unpack(ev))}
    local ok=table.remove(results,1)
    if not ok then
        lastError=tostring(results[1])
        worker=nil; workerFilter=nil; machineState="ERROR"
        return
    end
    if coroutine.status(worker)=="dead" then
        local runOk=results[1]
        worker=nil; workerFilter=nil; paused=false; pausedEvent=nil
        if runOk==false then machineState="ERROR"; lastError="miner64 terminou com falha"
        else machineState="STANDBY"; lastError=nil end
    else
        workerFilter=results[1]
    end
end

local function startOrResume()
    if worker then
        if paused then
            paused=false; machineState="RUNNING"
            if pausedEvent then
                local ev=pausedEvent; pausedEvent=nil
                resumeWorker(table.unpack(ev))
            end
            return true,"MINER-01 retomada."
        end
        machineState="RUNNING"
        return true,"MINER-01 ja esta executando."
    end
    if not fs.exists(MINER_PROGRAM) and not fs.exists(MINER_PROGRAM..".lua") then
        machineState="ERROR"; lastError="Arquivo miner64 nao encontrado"
        return false,"Nao encontrei o programa miner64 nesta Turtle."
    end
    lastError=nil; paused=false; pausedEvent=nil; machineState="STARTING"
    worker=coroutine.create(function() return shell.run(MINER_PROGRAM) end)
    resumeWorker()
    if worker and machineState~="ERROR" then machineState="RUNNING" end
    return machineState~="ERROR", machineState=="ERROR" and lastError or "MINER-01 iniciou o miner64."
end

local function pauseWorker()
    if not worker then machineState="STANDBY"; return true,"MINER-01 ja esta parada." end
    if paused then return true,"MINER-01 ja esta pausada." end
    paused=true; machineState="PAUSED"
    return true,"MINER-01 pausada preservando a sessao atual."
end

local function resumeOnly()
    if not worker then return false,"Nao existe sessao miner64 pausada. Use START para iniciar." end
    if not paused then return true,"MINER-01 ja esta executando." end
    paused=false; machineState="RUNNING"
    if pausedEvent then local ev=pausedEvent; pausedEvent=nil; resumeWorker(table.unpack(ev)) end
    return true,"MINER-01 retomada."
end

local function abortWorker()
    if not worker then machineState="STANDBY"; return true,"MINER-01 ja esta parada." end
    worker=nil; workerFilter=nil; paused=false; pausedEvent=nil; machineState="STANDBY"
    return true,"MINER-01 abortada. O proximo START reinicia miner64."
end

local function handleCommand(sender,msg)
    if sender~=pairedCore then return end
    if msg.machine_id and msg.machine_id~=MACHINE_ID then return end
    local action=tostring(msg.action or ""):upper()
    local ok,text
    if action=="START" then ok,text=startOrResume()
    elseif action=="PAUSE" then ok,text=pauseWorker()
    elseif action=="RESUME" then ok,text=resumeOnly()
    elseif action=="ABORT" then ok,text=abortWorker()
    else ok=false; text="Acao nao permitida: "..action end
    sendAck(msg,ok,text)
end

local heartbeatTimer=os.startTimer(0.2)

term.clear(); term.setCursorPos(1,1)
print("BLUMA MINER AGENT")
print("Machine: "..MACHINE_ID)
print("Computer ID: "..os.getComputerID())
print("Miner program: "..MINER_PROGRAM)
print("Pair: "..tostring(pairedCore or "aguardando BLUMA"))
print("O agente fica ligado; a mineracao so inicia por comando START.")

while true do
    local ev={os.pullEventRaw()}
    local name=ev[1]

    if name=="terminate" then
        print("Encerrando agente BLUMA.")
        break
    end

    if name=="timer" and ev[2]==heartbeatTimer then
        sendHeartbeat()
        heartbeatTimer=os.startTimer(HEARTBEAT_SECONDS)
    elseif name=="rednet_message" then
        local sender,msg,protocol=ev[2],ev[3],ev[4]
        if protocol==PROTOCOL and type(msg)=="table" then
            if msg.kind=="PAIR_ACCEPT" and (not pairedCore) and msg.machine_id==MACHINE_ID then
                savePair(sender)
                print("Pareado com BLUMA core #"..sender)
                sendHeartbeat()
            elseif msg.kind=="COMMAND" then
                handleCommand(sender,msg)
            end
        end
    end

    if worker then
        if paused then
            if not pausedEvent and (not workerFilter or workerFilter==name or name=="terminate") then pausedEvent=ev end
        else
            resumeWorker(table.unpack(ev))
        end
    end
end
