-- ============================================================
-- BLUMA CORE v1
-- CC:Tweaked 1.20.1 + Advanced Peripherals 0.7
-- Chat + Groq + Fish TTS + Monitor + Rednet + Machine control
-- ============================================================

local okConfig, CONFIG = pcall(require, "config")
if not okConfig then error("Nao foi possivel carregar config.lua: " .. tostring(CONFIG), 0) end

CONFIG.GROQ_URL = CONFIG.GROQ_URL or "https://api.groq.com/openai/v1/chat/completions"
CONFIG.FISH_URL = CONFIG.FISH_URL or "https://api.fish.audio/v1/tts"
CONFIG.GROQ_MODEL = CONFIG.GROQ_MODEL or "openai/gpt-oss-20b"
CONFIG.FISH_MODEL = CONFIG.FISH_MODEL or "s2.1-pro-free"
CONFIG.SPEAKER_VOLUME = CONFIG.SPEAKER_VOLUME or 2.25
CONFIG.AUDIO_PEAK = CONFIG.AUDIO_PEAK or 100

local OWNER_CANON = "murillopip"
local MACHINE_PROTOCOL = "bluma.machine.v1"
local LEGACY_MINER_PROTOCOL = "miner64"
local HEARTBEAT_TIMEOUT = 12
local ACK_TIMEOUT = 5
local DEFAULT_VOICE_ID = "933563129e564b19a115bedd57b7406a"
local RUNTIME_FILE = ".bluma_runtime"

local monitor = peripheral.find("monitor")
local speaker = peripheral.find("speaker")
local chatBox = peripheral.find("chatBox")
local modem = peripheral.find("modem")

if not speaker then error("Speaker nao encontrado.", 0) end
if not chatBox then error("Chat Box nao encontrada.", 0) end
if not modem then error("Modem nao encontrado.", 0) end

local modemName = peripheral.getName(modem)
if not rednet.isOpen(modemName) then rednet.open(modemName) end
pcall(function() rednet.host(MACHINE_PROTOCOL, "bluma-core-" .. os.getComputerID()) end)

if monitor then
    monitor.setTextScale(0.5)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()
end

local function normalizeName(name)
    return tostring(name or ""):lower():gsub("%s+", "")
end

local function isOwner(username)
    return normalizeName(username) == OWNER_CANON
end

local repl = {
    ["á"]="a",["à"]="a",["ã"]="a",["â"]="a",["ä"]="a",
    ["é"]="e",["è"]="e",["ê"]="e",["ë"]="e",
    ["í"]="i",["ì"]="i",["î"]="i",["ï"]="i",
    ["ó"]="o",["ò"]="o",["õ"]="o",["ô"]="o",["ö"]="o",
    ["ú"]="u",["ù"]="u",["û"]="u",["ü"]="u",
    ["ç"]="c",["ñ"]="n",
    ["Á"]="A",["À"]="A",["Ã"]="A",["Â"]="A",["Ä"]="A",
    ["É"]="E",["È"]="E",["Ê"]="E",["Ë"]="E",
    ["Í"]="I",["Ì"]="I",["Î"]="I",["Ï"]="I",
    ["Ó"]="O",["Ò"]="O",["Õ"]="O",["Ô"]="O",["Ö"]="O",
    ["Ú"]="U",["Ù"]="U",["Û"]="U",["Ü"]="U",
    ["Ç"]="C",["Ñ"]="N",
}

local function ascii(s)
    s = tostring(s or "")
    for a,b in pairs(repl) do s = s:gsub(a,b) end
    return s
end

local function folded(s)
    return ascii(tostring(s or "")):lower()
end

local runtime = {
    voice_id = DEFAULT_VOICE_ID,
    voice_enabled = true,
}

local function saveRuntime()
    local h = fs.open(RUNTIME_FILE, "w")
    if h then
        h.write(textutils.serialize(runtime))
        h.close()
    end
end

local function loadRuntime()
    if not fs.exists(RUNTIME_FILE) then return end
    local h = fs.open(RUNTIME_FILE, "r")
    if not h then return end
    local raw = h.readAll()
    h.close()
    local t = textutils.unserialize(raw)
    if type(t) == "table" then
        if type(t.voice_id) == "string" and #t.voice_id > 0 then runtime.voice_id = t.voice_id end
        if type(t.voice_enabled) == "boolean" then runtime.voice_enabled = t.voice_enabled end
    end
end
loadRuntime()

local state = {
    thinking = false,
    speaking = false,
    lastUser = nil,
    lastMessage = nil,
    lastResponse = nil,
    lastLegacyMiner = nil,
    machines = {},
    history = {},
    pending = {},
    requestSeq = 0,
}

local function nowMs() return os.epoch("utc") end
local function nowSec() return nowMs() / 1000 end

local function machineOnline(m)
    return m and (nowSec() - (m.lastSeen or 0) <= HEARTBEAT_TIMEOUT)
end

local function inventoryShort(items)
    if type(items) ~= "table" then return nil end
    local parts = {}
    for name,count in pairs(items) do
        parts[#parts+1] = tostring(count) .. "x " .. tostring(name):gsub("minecraft:", "")
        if #parts >= 5 then break end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

local function machineSummary(private)
    local ids = {}
    for id in pairs(state.machines) do ids[#ids+1] = id end
    table.sort(ids)
    if #ids == 0 then return "Nenhuma maquina BLUMA enviou telemetria ainda." end

    local out = {}
    for _,id in ipairs(ids) do
        local m = state.machines[id]
        local online = machineOnline(m)
        local line = id .. " = " .. (online and tostring(m.state or "UNKNOWN") or "OFFLINE")
        if private and online then
            if m.fuel ~= nil then line = line .. " | fuel=" .. tostring(m.fuel) end
            if m.slotsUsed ~= nil then line = line .. " | slots=" .. tostring(m.slotsUsed) .. "/16" end
            if m.position and m.position.x then
                line = line .. (" | xyz=%.0f %.0f %.0f"):format(m.position.x, m.position.y, m.position.z)
            end
            local inv = inventoryShort(m.items)
            if inv then line = line .. " | inv=" .. inv end
            if m.lastError then line = line .. " | erro=" .. tostring(m.lastError) end
        end
        out[#out+1] = line
    end
    return table.concat(out, "\n")
end

local function wrapText(text, width)
    local lines, line = {}, ""
    for word in tostring(text or ""):gmatch("%S+") do
        if #line + #word + (line == "" and 0 or 1) > width then
            if line ~= "" then lines[#lines+1] = line end
            line = word
        else
            line = line == "" and word or (line .. " " .. word)
        end
    end
    if line ~= "" then lines[#lines+1] = line end
    return lines
end

local function redraw()
    if not monitor then return end
    local w,h = monitor.getSize()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    monitor.setTextColor(colors.cyan)
    monitor.setCursorPos(2,1)
    monitor.write("BLUMA // CORE")
    monitor.setTextColor(colors.gray)
    monitor.setCursorPos(2,2)
    monitor.write("AI + TELEMETRY + CONTROL")
    monitor.setCursorPos(1,3)
    monitor.write(string.rep("-", w))

    monitor.setCursorPos(2,5)
    if state.thinking then
        monitor.setTextColor(colors.orange); monitor.write("STATUS: PROCESSANDO")
    elseif state.speaking then
        monitor.setTextColor(colors.lime); monitor.write("STATUS: FALANDO")
    else
        monitor.setTextColor(colors.green); monitor.write("STATUS: ONLINE")
    end

    monitor.setTextColor(colors.lightGray)
    monitor.setCursorPos(2,7)
    monitor.write("OWNER: Murillopip")

    local online,total = 0,0
    for _,m in pairs(state.machines) do total=total+1; if machineOnline(m) then online=online+1 end end
    monitor.setCursorPos(2,8)
    monitor.write(("MAQUINAS: %d ONLINE / %d TOTAL"):format(online,total))

    local y = 10
    for id,m in pairs(state.machines) do
        if y >= h-5 then break end
        monitor.setCursorPos(2,y)
        monitor.setTextColor(machineOnline(m) and colors.lime or colors.red)
        monitor.write(ascii(id .. "  " .. (machineOnline(m) and tostring(m.state) or "OFFLINE")))
        y=y+1
    end

    if state.lastResponse then
        y = math.max(y+1, h-6)
        monitor.setTextColor(colors.cyan)
        monitor.setCursorPos(2,y)
        monitor.write("BLUMA:")
        local lines = wrapText(ascii(state.lastResponse), math.max(10,w-3))
        monitor.setTextColor(colors.white)
        for i=1,math.min(#lines,h-y-1) do
            monitor.setCursorPos(2,y+i)
            monitor.write(lines[i])
        end
    end
end

local function safeSound(name, volume, pitch)
    pcall(function() speaker.playSound(name, volume, pitch) end)
end

local function getHistory(username)
    local key = normalizeName(username)
    state.history[key] = state.history[key] or {}
    return state.history[key]
end

local function addHistory(username, role, content)
    local h = getHistory(username)
    h[#h+1] = {role=role, content=content}
    while #h > 8 do table.remove(h,1) end
end

local function groqRequest(messages, maxTokens, temperature)
    if not CONFIG.GROQ_KEY or CONFIG.GROQ_KEY == "" then return nil, "GROQ_KEY ausente" end
    local body = textutils.serializeJSON({
        model = CONFIG.GROQ_MODEL,
        messages = messages,
        temperature = temperature or 0.35,
        max_tokens = maxTokens or 350,
    })
    local res,err,errRes = http.post(CONFIG.GROQ_URL, body, {
        ["Authorization"] = "Bearer " .. CONFIG.GROQ_KEY,
        ["Content-Type"] = "application/json",
    })
    if not res then
        local detail = tostring(err)
        if errRes then detail = detail .. " | " .. tostring(errRes.readAll()); errRes.close() end
        return nil, detail
    end
    local raw = res.readAll(); res.close()
    local obj = textutils.unserializeJSON(raw)
    if not obj or not obj.choices or not obj.choices[1] or not obj.choices[1].message then
        return nil, "Resposta invalida da Groq: " .. tostring(raw):sub(1,180)
    end
    return obj.choices[1].message.content
end

local function systemPrompt(username)
    local owner = isOwner(username)
    local privacy = owner and [[
O usuario e o operador autorizado Murillopip. Ele pode receber telemetria interna e solicitar acoes permitidas.
]] or [[
O usuario NAO e o operador. Nunca revele coordenadas, inventario, combustivel, recursos, seguranca, chaves, configuracoes ou dados internos da base. Nunca autorize controle de maquinas.
]]
    return [[
Voce e BLUMA, a inteligencia central de uma base Minecraft.
Responda no MESMO idioma usado pelo usuario, a menos que ele peca explicitamente outro idioma.
Seja natural, curta, precisa e tecnica quando necessario.
Nao invente telemetria. Nao invente sensores. Nao invente que uma acao foi executada.
O texto abaixo e a UNICA fonte de verdade sobre maquinas.
Se uma maquina estiver OFFLINE, trate-a como offline.
]] .. privacy .. "\nTELEMETRIA ATUAL:\n" .. machineSummary(owner)
end

local function askGroq(username, message)
    local msgs = {{role="system", content=systemPrompt(username)}}
    for _,m in ipairs(getHistory(username)) do msgs[#msgs+1]=m end
    msgs[#msgs+1] = {role="user", content=message}
    return groqRequest(msgs, 350, 0.45)
end

local function classifyIntent(message)
    local prompt = [[
Classifique o comando do usuario para uma central Minecraft.
Responda SOMENTE JSON valido, sem markdown:
{"action":"START|PAUSE|RESUME|ABORT|STATUS|NONE","target":"MINER-01"}
Regras:
- ligar/iniciar/começar mineracao = START
- desligar/parar temporariamente/pausar = PAUSE
- continuar/retomar = RESUME
- abortar/cancelar definitivamente = ABORT
- pedir estado/status = STATUS
- conversa normal = NONE
Entenda qualquer idioma. Nao invente outros actions ou targets.
]]
    local raw,err = groqRequest({{role="system",content=prompt},{role="user",content=message}}, 80, 0)
    if not raw then return "NONE", nil, err end
    raw = raw:gsub("```json",""):gsub("```","")
    local obj = textutils.unserializeJSON(raw)
    if type(obj) ~= "table" then return "NONE", nil, "intent JSON invalido" end
    local a = tostring(obj.action or "NONE"):upper()
    local allowed = {START=true,PAUSE=true,RESUME=true,ABORT=true,STATUS=true,NONE=true}
    if not allowed[a] then a="NONE" end
    return a, "MINER-01"
end

local function localIntent(message)
    local m = folded(message)
    if m:find("diagnostico",1,true) or m:find("diagnostic",1,true) then return "DIAGNOSTIC" end
    if m:find("voz atual",1,true) or m:find("current voice",1,true) then return "VOICE_STATUS" end
    if m:find("voz desligada",1,true) or m:find("desliga a voz",1,true) or m:find("voice off",1,true) then return "VOICE_OFF" end
    if m:find("voz ligada",1,true) or m:find("liga a voz",1,true) or m:find("voice on",1,true) then return "VOICE_ON" end
    if m:find("limpar voz",1,true) or m:find("reset voice",1,true) then return "VOICE_RESET" end
    local vid = tostring(message):match("[Vv][Oo][Zz]%s+([0-9a-fA-F]+)") or tostring(message):match("[Vv]oice%s+([0-9a-fA-F]+)")
    if vid and #vid >= 24 then return "VOICE_SET", vid end

    if m:find("status da miner",1,true) or m:find("status da maquina",1,true) or m:find("status das maquinas",1,true) or m:find("miner status",1,true) then return "STATUS","MINER-01" end
    if m:find("aborta a miner",1,true) or m:find("abortar miner",1,true) or m:find("cancel miner",1,true) then return "ABORT","MINER-01" end
    if m:find("retoma a miner",1,true) or m:find("continua a miner",1,true) or m:find("resume miner",1,true) then return "RESUME","MINER-01" end
    if m:find("desliga a miner",1,true) or m:find("para a miner",1,true) or m:find("pausa a miner",1,true) or m:find("pause miner",1,true) or m:find("stop miner",1,true) then return "PAUSE","MINER-01" end
    if m:find("liga a miner",1,true) or m:find("inicia a miner",1,true) or m:find("ligar miner",1,true) or m:find("start miner",1,true) or m:find("turn on miner",1,true) then return "START","MINER-01" end
    return "NONE"
end

local function nextRequestId()
    state.requestSeq = state.requestSeq + 1
    return tostring(os.getComputerID()) .. "-" .. tostring(nowMs()) .. "-" .. tostring(state.requestSeq)
end

local function executeMachineAction(action, target)
    target = target or "MINER-01"
    if action == "STATUS" then return true, machineSummary(true) end
    local m = state.machines[target]
    if not m then return false, target .. " ainda nao foi descoberta pela BLUMA." end
    if not machineOnline(m) then return false, target .. " esta OFFLINE ou sem heartbeat." end

    local rid = nextRequestId()
    state.pending[rid] = false
    local sent = rednet.send(m.sender, {
        kind="COMMAND",
        machine_id=target,
        request_id=rid,
        action=action,
        requested_by="Murillopip",
    }, MACHINE_PROTOCOL)
    if not sent then state.pending[rid]=nil; return false, "Rednet nao conseguiu enviar o comando." end

    local deadline = nowSec() + ACK_TIMEOUT
    while nowSec() < deadline do
        local ack = state.pending[rid]
        if type(ack) == "table" then
            state.pending[rid] = nil
            if ack.ok then
                if state.machines[target] then
                    state.machines[target].state = ack.state or state.machines[target].state
                    state.machines[target].lastSeen = nowSec()
                end
                return true, ack.message or (target .. " confirmou " .. tostring(action) .. ".")
            else
                return false, ack.message or (target .. " recusou o comando.")
            end
        end
        sleep(0.1)
    end
    state.pending[rid] = nil
    return false, target .. " nao confirmou o comando em " .. tostring(ACK_TIMEOUT) .. " segundos."
end

local function operationalReply(userMessage, fact)
    local p = [[
Responda em UMA frase curta, no mesmo idioma da mensagem do usuario.
Voce deve preservar exatamente o fato operacional informado. Nao invente detalhes nem resultados extras.
FATO: ]] .. fact
    local r = groqRequest({{role="system",content=p},{role="user",content=userMessage}}, 100, 0.15)
    return r or fact
end

local function sendPrivate(username, text)
    local ok = pcall(function()
        local sent,err = chatBox.sendMessageToPlayer(tostring(text), username, "BLUMA", "[]", "&b", nil, true)
        if not sent then error(err or "falha ChatBox") end
    end)
    if not ok then pcall(function() chatBox.sendMessageToPlayer(ascii(text), username, "BLUMA", "[]", "&b") end) end
end

local function sendPublic(text)
    local ok = pcall(function()
        local sent,err = chatBox.sendMessage(tostring(text), "BLUMA", "[]", "&b", nil, true)
        if not sent then error(err or "falha ChatBox") end
    end)
    if not ok then pcall(function() chatBox.sendMessage(ascii(text), "BLUMA", "[]", "&b") end) end
end

local function wantsPublic(username, message)
    if not isOwner(username) then return true end
    local m = folded(message)
    return m:find("bluma publico",1,true) ~= nil or m:find("bluma public",1,true) ~= nil
end

-- WAV PCM16 -> CC speaker PCM8/48kHz
local function u16(d,p) local a,b=d:byte(p,p+1); return (a or 0)+(b or 0)*256 end
local function u32(d,p) local a,b,c,e=d:byte(p,p+3); return (a or 0)+(b or 0)*256+(c or 0)*65536+(e or 0)*16777216 end
local function s16(d,p) local v=u16(d,p); if v>=32768 then v=v-65536 end; return v end

local function playWav(wav)
    if wav:sub(1,4)~="RIFF" or wav:sub(9,12)~="WAVE" then return false,"Fish nao retornou WAV RIFF." end
    local pos=13
    local fmt,channels,rate,bits,dataStart,dataSize
    while pos+7<=#wav do
        local id=wav:sub(pos,pos+3); local size=u32(wav,pos+4); local st=pos+8
        if id=="fmt " then
            fmt=u16(wav,st); channels=u16(wav,st+2); rate=u32(wav,st+4); bits=u16(wav,st+14)
        elseif id=="data" then dataStart=st; dataSize=math.min(size,#wav-st+1); break end
        pos=st+size+(size%2)
    end
    if not dataStart then return false,"Chunk data ausente." end
    if fmt~=1 or bits~=16 or (channels~=1 and channels~=2) then return false,"WAV nao e PCM16 mono/stereo." end
    local frameSize=channels*2; local frames=math.floor(dataSize/frameSize)
    if frames<=0 then return false,"Audio vazio." end

    local function mono(frame)
        frame=math.max(0,math.min(frames-1,frame))
        local p=dataStart+frame*frameSize
        if channels==1 then return s16(wav,p) end
        return (s16(wav,p)+s16(wav,p+2))/2
    end

    local sum=0
    for i=0,frames-1 do sum=sum+mono(i); if i%24000==0 then sleep(0) end end
    local mean=sum/frames
    local peak=1
    for i=0,frames-1 do local a=math.abs(mono(i)-mean); if a>peak then peak=a end; if i%24000==0 then sleep(0) end end
    local target=CONFIG.AUDIO_PEAK
    local gain=(target*256)/peak
    if gain>2 then gain=2 end

    local outFrames=math.floor(frames*48000/rate)
    local buffer={}
    local function flush()
        if #buffer==0 then return end
        while not speaker.playAudio(buffer,CONFIG.SPEAKER_VOLUME) do os.pullEvent("speaker_audio_empty") end
        buffer={}; sleep(0)
    end
    local function sampled(i)
        if rate==48000 then return mono(i) end
        local src=i*rate/48000; local a=math.floor(src); local b=math.min(a+1,frames-1); local f=src-a
        return mono(a)+(mono(b)-mono(a))*f
    end
    for i=0,outFrames-1 do
        local v=math.floor(((sampled(i)-mean)*gain)/256)
        if v>target then v=target elseif v<(-target) then v=-target end
        buffer[#buffer+1]=v
        if #buffer>=65536 then flush() end
    end
    flush(); return true
end

local function fishSpeak(text)
    if not runtime.voice_enabled then return end
    if not CONFIG.FISH_KEY or CONFIG.FISH_KEY=="" then return end
    text=tostring(text or "")
    if #text>650 then text=text:sub(1,650) end
    state.speaking=true; redraw()
    local body=textutils.serializeJSON({text=text, reference_id=runtime.voice_id, format="wav"})
    local res,err,errRes=http.post(CONFIG.FISH_URL,body,{
        ["Authorization"]="Bearer "..CONFIG.FISH_KEY,
        ["Content-Type"]="application/json",
        ["model"]=CONFIG.FISH_MODEL,
    },true)
    if res then
        local audio=res.readAll(); res.close()
        local ok,playErr=playWav(audio)
        if not ok then printError("TTS play: "..tostring(playErr)) end
    else
        printError("Fish: "..tostring(err))
        if errRes then printError(tostring(errRes.readAll()):sub(1,300)); errRes.close() end
    end
    state.speaking=false; redraw()
end

local function calledBluma(message)
    return folded(message):find("bluma",1,true) ~= nil
end

local function handleAdminLocal(username, action, arg)
    if action=="DIAGNOSTIC" then
        return true, ("ChatBox username='%s' | normalizado='%s' | owner=%s | coreID=%d | voice=%s\n%s"):format(
            tostring(username), normalizeName(username), tostring(isOwner(username)), os.getComputerID(), runtime.voice_id, machineSummary(isOwner(username)))
    end
    if action=="VOICE_STATUS" then return true,"Voz fixa atual: "..runtime.voice_id.." | ativa="..tostring(runtime.voice_enabled) end
    if action=="VOICE_ON" or action=="VOICE_OFF" or action=="VOICE_RESET" or action=="VOICE_SET" then
        if not isOwner(username) then return true,"Esse ajuste e restrito ao operador." end
        if action=="VOICE_ON" then runtime.voice_enabled=true; saveRuntime(); return true,"Voz da BLUMA ativada." end
        if action=="VOICE_OFF" then runtime.voice_enabled=false; saveRuntime(); return true,"Voz da BLUMA desativada." end
        if action=="VOICE_RESET" then runtime.voice_id=DEFAULT_VOICE_ID; saveRuntime(); return true,"Voz restaurada para a referencia fixa padrao." end
        runtime.voice_id=arg; saveRuntime(); return true,"Nova voz fixa salva. Nao e necessario editar config.lua." end
    end
    return false
end

local function processMessage(username, message)
    state.lastUser=username; state.lastMessage=message; state.thinking=true; redraw(); safeSound("minecraft:block.amethyst_block.chime",0.2,1.35)

    local action,arg=localIntent(message)
    local handled,response=false,nil

    local adminHandled,adminResponse=handleAdminLocal(username,action,arg)
    if adminHandled then handled=true; response=adminResponse end

    if not handled and action~="NONE" then
        if not isOwner(username) then
            handled=true; response="Esse comando e restrito ao operador da BLUMA."
        else
            local ok,fact=executeMachineAction(action,arg)
            handled=true; response=operationalReply(message,fact)
        end
    end

    if not handled and isOwner(username) then
        local aiAction,target=classifyIntent(message)
        if aiAction~="NONE" then
            local ok,fact=executeMachineAction(aiAction,target)
            handled=true; response=operationalReply(message,fact)
        end
    end

    if not handled then
        local ai,err=askGroq(username,message)
        response=ai or ("Falha no nucleo de linguagem: "..tostring(err))
    end

    state.thinking=false; state.lastResponse=response; redraw()
    addHistory(username,"user",message); addHistory(username,"assistant",response)

    if wantsPublic(username,message) then sendPublic(response) else sendPrivate(username,response) end
    safeSound("minecraft:block.note_block.pling",0.18,1.25)
    fishSpeak(response)
end

local function rednetLoop()
    while true do
        local _,sender,msg,protocol=os.pullEvent("rednet_message")
        if protocol==MACHINE_PROTOCOL and type(msg)=="table" then
            if msg.kind=="PAIR_REQUEST" and msg.machine_id then
                rednet.send(sender,{kind="PAIR_ACCEPT",core_id=os.getComputerID(),machine_id=msg.machine_id},MACHINE_PROTOCOL)
            elseif (msg.kind=="HEARTBEAT" or msg.kind=="STATE") and msg.machine_id then
                local m=state.machines[msg.machine_id] or {}
                m.sender=sender; m.id=msg.machine_id; m.state=msg.state or m.state or "UNKNOWN"
                m.fuel=msg.fuel; m.slotsUsed=msg.slots_used; m.items=msg.items; m.position=msg.position
                m.program=msg.program; m.lastError=msg.last_error; m.lastSeen=nowSec()
                state.machines[msg.machine_id]=m; redraw()
            elseif msg.kind=="ACK" and msg.request_id then
                state.pending[msg.request_id]=msg
                if msg.machine_id and state.machines[msg.machine_id] then
                    state.machines[msg.machine_id].state=msg.state or state.machines[msg.machine_id].state
                    state.machines[msg.machine_id].lastSeen=nowSec()
                end
                redraw()
            end
        elseif protocol==LEGACY_MINER_PROTOCOL then
            state.lastLegacyMiner=tostring(msg)
        end
    end
end

local function chatLoop()
    while true do
        local _,username,message,uuid,isHidden,messageUtf8=os.pullEvent("chat")
        local text=(messageUtf8 and #messageUtf8>0) and messageUtf8 or message
        if calledBluma(text) then
            local ok,err=pcall(processMessage,username,text)
            if not ok then
                state.thinking=false; state.speaking=false; redraw()
                printError("BLUMA: "..tostring(err))
                sendPrivate(username,"Erro interno da BLUMA: "..ascii(tostring(err)):sub(1,180))
            end
        end
    end
end

local function uiLoop()
    while true do redraw(); sleep(1) end
end

term.clear(); term.setCursorPos(1,1)
print("BLUMA CORE v1")
print("Core ID: "..os.getComputerID())
print("Owner canonico: Murillopip (comparacao sem diferenca de maiusculas/minusculas)")
print("Voice ID: "..runtime.voice_id)
print("Protocolo: "..MACHINE_PROTOCOL)
print("Aguardando chat e maquinas...")
safeSound("minecraft:block.beacon.activate",0.35,1.15)
redraw()

parallel.waitForAny(chatLoop,rednetLoop,uiLoop)
