-- ============================================================
-- BLUMA CORE v4
-- CC:Tweaked 1.20.1 + Advanced Peripherals Chat Box
--
-- Recursos:
--   - Owner case-insensitive: Murillopip
--   - Groq (conversa)
--   - Fish Audio (voz)
--   - Voz fixa por reference_id persistente
--   - Responde no idioma da mensagem
--   - Chat privado do owner por padrao
--   - Modo publico explicito
--   - Rednet + heartbeat real
--   - START / STOP / PAUSE / RESUME da mineradora
--   - ACK real: nao inventa que executou
--   - Dashboard animado no Advanced Monitor
--   - Boot/login animation
--   - ASCII/portrait CC-native
--   - Watchdog de maquinas
--   - Historico por jogador
--   - Runtime persistente sem editar config.lua
-- ============================================================

local CONFIG = require("config")

-- ---------------------------
-- IDENTIDADE
-- ---------------------------

local OWNER = "Murillopip"
local CORE_PROTOCOL = "BLUMA"
local MACHINE_ID = "MINER-01"
local HEARTBEAT_TIMEOUT = 12

local GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
local GROQ_MODEL = "openai/gpt-oss-20b"

local FISH_URL = "https://api.fish.audio/v1/tts"
local FISH_MODEL = "s2.1-pro-free"

-- Voz fixa publica mostrada na documentacao da Fish.
-- Pode ser trocada PELO CHAT e fica salva em .bluma_runtime.
-- Ex.: "Bluma voz 0123456789abcdef..."
local DEFAULT_VOICE_ID = "933563129e564b19a115bedd57b7406a"

-- ---------------------------
-- PERIFERICOS
-- ---------------------------

local monitor = peripheral.find("monitor")
local speaker = peripheral.find("speaker")
local chatBox = peripheral.find("chatBox")
local modem = peripheral.find("modem")

if not monitor then error("BLUMA: monitor nao encontrado") end
if not speaker then error("BLUMA: speaker nao encontrado") end
if not chatBox then error("BLUMA: chatBox nao encontrada") end
if not modem then error("BLUMA: modem nao encontrado") end

local modemName = peripheral.getName(modem)
if not rednet.isOpen(modemName) then
    rednet.open(modemName)
end

monitor.setTextScale(0.5)

-- ---------------------------
-- RUNTIME
-- ---------------------------

local RUNTIME_FILE = ".bluma_runtime"

local runtime = {
    voice_enabled = true,
    voice_id = DEFAULT_VOICE_ID,
    volume = 2.15
}

local function loadRuntime()
    if not fs.exists(RUNTIME_FILE) then return end
    local h = fs.open(RUNTIME_FILE, "r")
    if not h then return end
    local raw = h.readAll()
    h.close()
    local data = textutils.unserializeJSON(raw)
    if type(data) == "table" then
        if type(data.voice_enabled) == "boolean" then runtime.voice_enabled = data.voice_enabled end
        if type(data.voice_id) == "string" and data.voice_id ~= "" then runtime.voice_id = data.voice_id end
        if type(data.volume) == "number" then runtime.volume = data.volume end
    end
end

local function saveRuntime()
    local h = fs.open(RUNTIME_FILE, "w")
    if not h then return false end
    h.write(textutils.serializeJSON(runtime))
    h.close()
    return true
end

loadRuntime()

-- ---------------------------
-- ESTADO
-- ---------------------------

local state = {
    mode = "BOOT",
    lastUser = "-",
    lastMessage = "",
    lastResponse = "",
    machines = {},
    history = {},
    pending = {},
    ttsQueue = {},
    bootedAt = os.epoch("utc"),
    spinner = 1,
    activity = "INITIALIZING",
    requestCounter = 0,
    error = nil
}

-- ---------------------------
-- UTIL
-- ---------------------------

local function trim(s)
    s = tostring(s or "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalizeName(s)
    return string.lower(trim(s))
end

local function isOwner(username)
    return normalizeName(username) == normalizeName(OWNER)
end

local function nowSeconds()
    return os.epoch("utc") / 1000
end

local function safeCall(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil, a end
    return a, b, c
end

local function contains(haystack, needle)
    return string.find(string.lower(tostring(haystack or "")), string.lower(needle), 1, true) ~= nil
end

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

local function padRight(s, n)
    s = tostring(s or "")
    if #s >= n then return s:sub(1, n) end
    return s .. string.rep(" ", n - #s)
end

local function centerText(s, w)
    s = tostring(s or "")
    if #s >= w then return s:sub(1, w) end
    local left = math.floor((w - #s) / 2)
    return string.rep(" ", left) .. s
end

local function sanitizeDisplay(s)
    s = tostring(s or "")
    local map = {
        ["á"]="a",["à"]="a",["ã"]="a",["â"]="a",["ä"]="a",
        ["é"]="e",["è"]="e",["ê"]="e",["ë"]="e",
        ["í"]="i",["ì"]="i",["î"]="i",["ï"]="i",
        ["ó"]="o",["ò"]="o",["õ"]="o",["ô"]="o",["ö"]="o",
        ["ú"]="u",["ù"]="u",["û"]="u",["ü"]="u",
        ["ç"]="c",
        ["Á"]="A",["À"]="A",["Ã"]="A",["Â"]="A",["Ä"]="A",
        ["É"]="E",["È"]="E",["Ê"]="E",["Ë"]="E",
        ["Í"]="I",["Ì"]="I",["Î"]="I",["Ï"]="I",
        ["Ó"]="O",["Ò"]="O",["Õ"]="O",["Ô"]="O",["Ö"]="O",
        ["Ú"]="U",["Ù"]="U",["Û"]="U",["Ü"]="U",
        ["Ç"]="C"
    }
    for a, b in pairs(map) do s = s:gsub(a, b) end
    s = s:gsub("[^\32-\126\n]", "?")
    return s
end

local function wrapText(text, width)
    text = sanitizeDisplay(text)
    local out = {}
    for paragraph in (text .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in paragraph:gmatch("%S+") do
            if #line == 0 then
                line = word
            elseif #line + #word + 1 <= width then
                line = line .. " " .. word
            else
                table.insert(out, line)
                line = word
            end
        end
        if line ~= "" then table.insert(out, line) end
        if paragraph == "" then table.insert(out, "") end
    end
    return out
end

local function safeSound(name, volume, pitch)
    pcall(function()
        speaker.playSound(name, volume or 0.2, pitch or 1)
    end)
end

-- ---------------------------
-- ASCII / PORTRAIT
-- ---------------------------
-- O asset Unicode original enviado pelo usuario fica no pacote como:
-- bluma_ascii_01.txt
--
-- Advanced Monitor do CC:Tweaked nao renderiza Unicode/Braille completo.
-- O monitor usa esta versao CC-native para nao virar bytes quebrados.

local PORTRAIT = {
    "          .::::::::::.          ",
    "       .::------------::.       ",
    "     .:---..        ..---:.     ",
    "    :--.                .--:    ",
    "   :-.      .------.      .-:   ",
    "  :-.     .-========-.     .-:  ",
    "  :-     /==  ____  ==\\     -:  ",
    "  :-    |==  / __ \\  ==|    -:  ",
    "  :-    |== | /  \\ | ==|    -:  ",
    "  :-    |== | \\__/ | ==|    -:  ",
    "  :-     \\== \\____/ ==/     -:  ",
    "   :-.     '-======-'     .-:   ",
    "    :--.      /\\        .--:    ",
    "     ':---.  /  \\   .---:'      ",
    "       '::---____---::'          ",
    "          '::::::::'             "
}

local function portraitLine(index, width)
    local line = PORTRAIT[index] or ""
    if #line > width then
        line = line:sub(1, width)
    end
    return line
end

-- ---------------------------
-- MONITOR DRAW
-- ---------------------------

local function clearMonitor(bg)
    monitor.setBackgroundColor(bg or colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()
    monitor.setCursorPos(1, 1)
end

local function writeAt(x, y, text, fg, bg)
    if bg then monitor.setBackgroundColor(bg) end
    if fg then monitor.setTextColor(fg) end
    monitor.setCursorPos(x, y)
    monitor.write(tostring(text or ""))
end

local function drawBox(x, y, w, h, title)
    if w < 4 or h < 3 then return end
    monitor.setTextColor(colors.gray)
    writeAt(x, y, "+" .. string.rep("-", w - 2) .. "+", colors.gray, colors.black)
    for yy = y + 1, y + h - 2 do
        writeAt(x, yy, "|", colors.gray, colors.black)
        writeAt(x + w - 1, yy, "|", colors.gray, colors.black)
    end
    writeAt(x, y + h - 1, "+" .. string.rep("-", w - 2) .. "+", colors.gray, colors.black)
    if title and #title > 0 then
        local t = " " .. title .. " "
        writeAt(x + 2, y, t:sub(1, math.max(0, w - 4)), colors.cyan, colors.black)
    end
end

local function machineOnline(m)
    return m and (nowSeconds() - (m.lastSeen or 0) <= HEARTBEAT_TIMEOUT)
end

local function getMachine(id)
    return state.machines[id]
end

local function statusWord()
    if state.error then return "ERROR" end
    if state.mode == "THINKING" then return "THINKING" end
    if state.mode == "SPEAKING" then return "SPEAKING" end
    return "ONLINE"
end

local function drawDashboard()
    local w, h = monitor.getSize()
    clearMonitor(colors.black)

    writeAt(2, 1, "BLUMA // CENTRAL INTELLIGENCE", colors.cyan, colors.black)
    writeAt(math.max(2, w - 18), 1, "[" .. statusWord() .. "]", state.error and colors.red or colors.lime, colors.black)
    writeAt(1, 2, string.rep("-", w), colors.gray, colors.black)

    local split = math.floor(w * 0.56)
    if split < 28 then split = math.floor(w * 0.65) end
    local leftW = split - 2
    local rightX = split + 1
    local rightW = w - rightX

    drawBox(2, 4, leftW, math.max(11, h - 7), "CORE")
    drawBox(rightX, 4, math.max(4, rightW), math.max(11, h - 7), "BLUMA")

    local y = 6
    writeAt(4, y, "OWNER", colors.gray)
    writeAt(15, y, OWNER, colors.white)
    y = y + 2

    writeAt(4, y, "ACTIVITY", colors.gray)
    writeAt(15, y, sanitizeDisplay(state.activity), colors.yellow)
    y = y + 2

    local miner = getMachine(MACHINE_ID)
    writeAt(4, y, "MINER-01", colors.gray)
    if machineOnline(miner) then
        local ms = tostring(miner.state or "UNKNOWN")
        writeAt(15, y, ms, ms == "RUNNING" and colors.lime or colors.orange)
    else
        writeAt(15, y, "OFFLINE", colors.red)
    end
    y = y + 1

    if miner and machineOnline(miner) then
        writeAt(6, y, "fuel: " .. tostring(miner.fuel or "?"), colors.lightGray)
        y = y + 1
        writeAt(6, y, "slots: " .. tostring(miner.usedSlots or "?") .. "/16", colors.lightGray)
        y = y + 1
        if miner.progress ~= nil then
            writeAt(6, y, "progress: " .. tostring(miner.progress), colors.lightGray)
            y = y + 1
        end
    end

    y = y + 1
    writeAt(4, y, "LAST USER", colors.gray)
    writeAt(15, y, sanitizeDisplay(state.lastUser), colors.white)
    y = y + 2

    if state.lastResponse ~= "" then
        writeAt(4, y, "BLUMA", colors.cyan)
        y = y + 1
        local lines = wrapText(state.lastResponse, math.max(10, leftW - 6))
        local maxLines = math.max(0, h - y - 3)
        for i = 1, math.min(#lines, maxLines) do
            writeAt(4, y, lines[i], colors.white)
            y = y + 1
        end
    end

    local artWidth = math.max(1, rightW - 4)
    local artY = 6
    local scan = (state.spinner % #PORTRAIT) + 1
    for i = 1, math.min(#PORTRAIT, h - 10) do
        local color = colors.lightGray
        if i == scan then color = colors.cyan end
        writeAt(rightX + 2, artY + i - 1, portraitLine(i, artWidth), color, colors.black)
    end

    local footerY = h - 2
    if footerY > 3 then
        writeAt(2, footerY, "CHAT: diga 'Bluma ...' | ADMIN: status / voz / mineradora", colors.gray, colors.black)
        local tick = ({".", "..", "...", "...."})[((state.spinner - 1) % 4) + 1]
        writeAt(math.max(2, w - 14), footerY, "CORE" .. tick, colors.cyan, colors.black)
    end
end

local function bootLine(y, label, delay)
    local w = monitor.getSize()
    writeAt(3, y, padRight(label, math.max(10, w - 12)), colors.lightGray, colors.black)
    sleep(delay or 0.10)
    writeAt(math.max(3, w - 6), y, "OK", colors.lime, colors.black)
    safeSound("minecraft:block.note_block.hat", 0.08, 1.6)
end

local function bootAnimation()
    state.mode = "BOOT"
    clearMonitor(colors.black)
    local w, h = monitor.getSize()

    writeAt(1, 2, centerText("BLUMA", w), colors.cyan, colors.black)
    writeAt(1, 3, centerText("CENTRAL INTELLIGENCE SYSTEM", w), colors.gray, colors.black)

    local startY = 6
    local steps = {
        "LOADING CORE",
        "LOADING CONFIG",
        "OPENING REDNET",
        "CHECKING MONITOR",
        "CHECKING SPEAKER",
        "CHECKING CHAT LINK",
        "CHECKING LANGUAGE MODEL",
        "CHECKING VOICE ENGINE",
        "INITIALIZING INTERFACE"
    }

    for i = 1, #steps do
        if startY + i - 1 < h - 4 then
            bootLine(startY + i - 1, steps[i], 0.08)
        end
    end

    sleep(0.2)
    clearMonitor(colors.black)
    writeAt(1, math.max(2, math.floor(h / 2) - 2), centerText("> USUARIO DETECTADO <", w), colors.yellow)
    sleep(0.25)
    writeAt(1, math.max(3, math.floor(h / 2)), centerText("AUTHENTICATING: " .. string.upper(OWNER), w), colors.white)
    sleep(0.25)
    writeAt(1, math.max(4, math.floor(h / 2) + 2), centerText("ACCESS GRANTED", w), colors.lime)
    safeSound("minecraft:block.beacon.activate", 0.25, 1.1)
    sleep(0.45)

    state.mode = "ONLINE"
    state.activity = "IDLE"
    drawDashboard()
end

-- ---------------------------
-- HISTORICO
-- ---------------------------

local function getHistory(username)
    local key = normalizeName(username)
    if not state.history[key] then state.history[key] = {} end
    return state.history[key]
end

local function addHistory(username, role, content)
    local h = getHistory(username)
    table.insert(h, { role = role, content = content })
    while #h > 10 do table.remove(h, 1) end
end

-- ---------------------------
-- MAQUINAS / REDNET
-- ---------------------------

local function updateMachine(sender, packet)
    if type(packet) ~= "table" then return end
    local id = packet.id
    if not id then return end

    state.machines[id] = {
        id = id,
        sender = sender,
        state = packet.state or "UNKNOWN",
        fuel = packet.fuel,
        usedSlots = packet.usedSlots,
        progress = packet.progress,
        message = packet.message,
        lastSeen = nowSeconds()
    }
end

local function machineSummary(private)
    local items = {}
    for id, m in pairs(state.machines) do
        local line = id .. "=" .. (machineOnline(m) and tostring(m.state or "UNKNOWN") or "OFFLINE")
        if private and machineOnline(m) then
            if m.fuel ~= nil then line = line .. " fuel=" .. tostring(m.fuel) end
            if m.usedSlots ~= nil then line = line .. " slots=" .. tostring(m.usedSlots) .. "/16" end
            if m.progress ~= nil then line = line .. " progress=" .. tostring(m.progress) end
        end
        table.insert(items, line)
    end
    if #items == 0 then return "Nenhuma maquina enviou telemetria." end
    return table.concat(items, " | ")
end

local function newRequestId()
    state.requestCounter = state.requestCounter + 1
    return tostring(os.getComputerID()) .. "-" .. tostring(os.epoch("utc")) .. "-" .. tostring(state.requestCounter)
end

local function sendMachineCommand(username, action)
    if not isOwner(username) then
        return false, "Acesso negado. Controle de maquinas e restrito ao operador."
    end

    local machine = state.machines[MACHINE_ID]
    if not machine or not machineOnline(machine) then
        return false, "MINER-01 esta offline ou sem heartbeat. Nao vou fingir que o comando foi executado."
    end

    local requestId = newRequestId()
    state.pending[requestId] = false

    rednet.send(machine.sender, {
        type = "COMMAND",
        id = MACHINE_ID,
        action = action,
        requestId = requestId,
        requestedBy = username
    }, CORE_PROTOCOL)

    local deadline = nowSeconds() + 4
    while nowSeconds() < deadline do
        local result = state.pending[requestId]
        if type(result) == "table" then
            state.pending[requestId] = nil
            if result.ok then
                return true, result.message or ("Comando " .. action .. " confirmado por MINER-01.")
            end
            return false, result.message or ("MINER-01 rejeitou " .. action .. ".")
        end
        sleep(0.1)
    end

    state.pending[requestId] = nil
    return false, "MINER-01 nao confirmou o comando dentro do tempo limite."
end

local function rednetLoop()
    while true do
        local event, sender, packet, protocol = os.pullEvent("rednet_message")
        if protocol == CORE_PROTOCOL and type(packet) == "table" then
            if packet.type == "HEARTBEAT" or packet.type == "STATUS" then
                updateMachine(sender, packet)
            elseif packet.type == "ACK" and packet.requestId then
                state.pending[packet.requestId] = {
                    ok = packet.ok ~= false,
                    message = packet.message
                }
                updateMachine(sender, packet)
            end
            drawDashboard()
        end
    end
end

-- ---------------------------
-- GROQ
-- ---------------------------

local function systemPrompt(username)
    local permission
    if isOwner(username) then
        permission = [[
O usuario e o proprietario Murillopip.
Ele pode consultar telemetria privada e pedir comandos administrativos.
Nunca diga que um comando foi executado se o BLUMA CORE nao confirmou.
]]
    else
        permission = [[
O usuario nao e o proprietario.
Converse normalmente, mas nunca revele coordenadas, inventario, combustivel,
recursos, seguranca, configuracoes, chaves, telemetria privada ou comandos administrativos.
Nunca autorize controle de maquinas.
]]
    end

    return [[
Voce e BLUMA, a inteligencia central de uma base de Minecraft.
Responda NO MESMO IDIOMA usado pelo jogador na mensagem atual.
Se ele falar portugues, use portugues brasileiro natural.
Se falar ingles, responda em ingles. Se falar espanhol, responda em espanhol.
Se mudar de idioma na proxima mensagem, acompanhe a mudanca.

Personalidade:
- calma
- precisa
- inteligente
- tecnica quando necessario
- natural, sem parecer um chatbot generico
- normalmente curta

REGRA ABSOLUTA DE TELEMETRIA:
Voce nao enxerga o Minecraft por magia.
Nunca invente estado, porcentagem, fuel, inventario, progresso, coordenadas,
producao, sensores, jogadores ou execucao de maquinas.
Use SOMENTE a telemetria fornecida abaixo.
Se estiver offline, diga offline/sem telemetria.

TELEMETRIA REAL:
]] .. machineSummary(isOwner(username)) .. "\n\n" .. permission
end

local function askGroq(username, message)
    local messages = {
        { role = "system", content = systemPrompt(username) }
    }

    for _, msg in ipairs(getHistory(username)) do
        table.insert(messages, msg)
    end
    table.insert(messages, { role = "user", content = message })

    local body = textutils.serializeJSON({
        model = GROQ_MODEL,
        messages = messages,
        temperature = 0.45,
        max_tokens = 350
    })

    local response, err, errResponse = http.post(
        GROQ_URL,
        body,
        {
            ["Authorization"] = "Bearer " .. tostring(CONFIG.GROQ_KEY or ""),
            ["Content-Type"] = "application/json"
        }
    )

    if not response then
        local detail = tostring(err)
        if errResponse then
            detail = detail .. " | " .. tostring(errResponse.readAll())
            errResponse.close()
        end
        return nil, detail
    end

    local raw = response.readAll()
    response.close()

    local data = textutils.unserializeJSON(raw)
    if not data or not data.choices or not data.choices[1] or not data.choices[1].message then
        return nil, "Resposta inesperada da Groq."
    end

    return trim(data.choices[1].message.content)
end

-- ---------------------------
-- FISH AUDIO / WAV
-- ---------------------------

local function u16(data, pos)
    local a = data:byte(pos) or 0
    local b = data:byte(pos + 1) or 0
    return a + b * 256
end

local function u32(data, pos)
    local a = data:byte(pos) or 0
    local b = data:byte(pos + 1) or 0
    local c = data:byte(pos + 2) or 0
    local d = data:byte(pos + 3) or 0
    return a + b * 256 + c * 65536 + d * 16777216
end

local function s16(data, pos)
    local v = u16(data, pos)
    if v >= 32768 then v = v - 65536 end
    return v
end

local function playWav(wav)
    if wav:sub(1, 4) ~= "RIFF" or wav:sub(9, 12) ~= "WAVE" then
        return false, "Fish nao devolveu WAV PCM."
    end

    local pos = 13
    local audioFormat, channels, sampleRate, bitsPerSample
    local dataStart, dataSize

    while pos + 7 <= #wav do
        local chunkId = wav:sub(pos, pos + 3)
        local chunkSize = u32(wav, pos + 4)
        local start = pos + 8

        if chunkId == "fmt " then
            audioFormat = u16(wav, start)
            channels = u16(wav, start + 2)
            sampleRate = u32(wav, start + 4)
            bitsPerSample = u16(wav, start + 14)
        elseif chunkId == "data" then
            dataStart = start
            dataSize = math.min(chunkSize, #wav - start + 1)
            break
        end

        pos = start + chunkSize
        if chunkSize % 2 == 1 then pos = pos + 1 end
    end

    if not dataStart then return false, "Chunk DATA ausente." end
    if audioFormat ~= 1 then return false, "WAV nao e PCM linear." end
    if bitsPerSample ~= 16 then return false, "WAV nao e PCM16." end
    if channels ~= 1 and channels ~= 2 then return false, "Canais nao suportados." end
    if not sampleRate or sampleRate <= 0 then return false, "Sample rate invalido." end

    local frameSize = channels * 2
    local totalFrames = math.floor(dataSize / frameSize)
    if totalFrames <= 0 then return false, "Audio vazio." end

    local function mono(frame)
        frame = clamp(frame, 0, totalFrames - 1)
        local p = dataStart + frame * frameSize
        if channels == 1 then return s16(wav, p) end
        return (s16(wav, p) + s16(wav, p + 2)) / 2
    end

    -- Analise leve de ganho: amostra 1 a cada ~20 frames.
    local step = math.max(1, math.floor(totalFrames / 8000))
    local sum, count = 0, 0
    for i = 0, totalFrames - 1, step do
        sum = sum + mono(i)
        count = count + 1
    end
    local mean = count > 0 and (sum / count) or 0

    local peak = 1
    for i = 0, totalFrames - 1, step do
        local a = math.abs(mono(i) - mean)
        if a > peak then peak = a end
    end

    local targetPeak = 100
    local gain = (targetPeak * 256) / peak
    gain = clamp(gain, 0.25, 1.8)

    local targetRate = 48000
    local outputFrames = math.floor(totalFrames * targetRate / sampleRate)
    local buffer = {}
    local bufferLimit = 32768

    local function sampleAt(outFrame)
        if sampleRate == targetRate then
            return mono(outFrame)
        end
        local src = outFrame * sampleRate / targetRate
        local a = math.floor(src)
        local b = math.min(a + 1, totalFrames - 1)
        local f = src - a
        return mono(a) + (mono(b) - mono(a)) * f
    end

    local function flush()
        if #buffer == 0 then return end
        while not speaker.playAudio(buffer, runtime.volume) do
            os.pullEvent("speaker_audio_empty")
        end
        buffer = {}
        sleep(0)
    end

    for i = 0, outputFrames - 1 do
        local v = (sampleAt(i) - mean) * gain
        v = math.floor(v / 256)
        v = clamp(v, -targetPeak, targetPeak)
        buffer[#buffer + 1] = v
        if #buffer >= bufferLimit then flush() end
    end
    flush()
    return true
end

local function fishSpeak(text)
    if not runtime.voice_enabled then return true end
    text = trim(text)
    if text == "" then return true end

    local payload = {
        text = text,
        format = "wav",
        normalize = true,
        prosody = {
            speed = 1.0,
            volume = 0,
            normalize_loudness = true
        }
    }

    if runtime.voice_id and runtime.voice_id ~= "" then
        payload.reference_id = runtime.voice_id
    end

    local response, err, errResponse = http.post(
        FISH_URL,
        textutils.serializeJSON(payload),
        {
            ["Authorization"] = "Bearer " .. tostring(CONFIG.FISH_KEY or ""),
            ["Content-Type"] = "application/json",
            ["model"] = FISH_MODEL
        },
        true
    )

    if not response then
        local detail = tostring(err)
        if errResponse then
            detail = detail .. " | " .. tostring(errResponse.readAll())
            errResponse.close()
        end
        return false, detail
    end

    local audio = response.readAll()
    response.close()
    return playWav(audio)
end

local function queueTTS(text)
    if runtime.voice_enabled and trim(text) ~= "" then
        table.insert(state.ttsQueue, text)
    end
end

local function ttsLoop()
    while true do
        if #state.ttsQueue == 0 then
            sleep(0.1)
        else
            local text = table.remove(state.ttsQueue, 1)
            state.mode = "SPEAKING"
            state.activity = "VOICE OUTPUT"
            drawDashboard()

            local ok, err = fishSpeak(text)
            if not ok then
                state.error = "VOICE: " .. tostring(err)
                print(state.error)
            end

            state.mode = "ONLINE"
            state.activity = "IDLE"
            drawDashboard()
        end
    end
end

-- ---------------------------
-- CHAT OUTPUT
-- ---------------------------

local function sendPrivate(username, text)
    local clean = sanitizeDisplay(text)
    local ok = pcall(function()
        chatBox.sendMessageToPlayer(clean, username, "BLUMA", "[]", "&b")
    end)
    if not ok then
        print("BLUMA: falha no sendMessageToPlayer")
    end
end

local function sendPublic(text)
    local clean = sanitizeDisplay(text)
    local ok = pcall(function()
        chatBox.sendMessage(clean, "BLUMA", "[]", "&b")
    end)
    if not ok then
        print("BLUMA: falha no sendMessage")
    end
end

local function wantsPublic(username, message)
    if not isOwner(username) then return true end
    return contains(message, "bluma publico") or contains(message, "bluma público") or contains(message, "bluma public")
end

local function calledBluma(message)
    return contains(message, "bluma")
end

-- ---------------------------
-- COMANDOS LOCAIS
-- ---------------------------

local function parseLocal(username, message)
    local m = string.lower(message or "")

    if contains(m, "diagnostico") or contains(m, "diagnóstico") or contains(m, "diagnostic") then
        return true,
            "username='" .. tostring(username) ..
            "' | normalizado='" .. normalizeName(username) ..
            "' | owner=" .. tostring(isOwner(username)) ..
            " | coreID=" .. tostring(os.getComputerID()) ..
            " | voice=" .. tostring(runtime.voice_id) ..
            " | " .. machineSummary(isOwner(username))
    end

    if contains(m, "status da mineradora") or contains(m, "status mineradora") or contains(m, "miner status") then
        if not isOwner(username) then
            return true, "Essas informacoes sao restritas ao operador."
        end
        return true, machineSummary(true)
    end

    if contains(m, "liga a mineradora") or contains(m, "ligar mineradora") or contains(m, "start miner") or contains(m, "start the miner") then
        local _, msg = sendMachineCommand(username, "START")
        return true, msg
    end

    if contains(m, "pausa a mineradora") or contains(m, "pausar mineradora") or contains(m, "pause miner") then
        local _, msg = sendMachineCommand(username, "PAUSE")
        return true, msg
    end

    if contains(m, "continua a mineradora") or contains(m, "retoma a mineradora") or contains(m, "resume miner") then
        local _, msg = sendMachineCommand(username, "RESUME")
        return true, msg
    end

    if contains(m, "para a mineradora") or contains(m, "parar mineradora") or contains(m, "stop miner") then
        local _, msg = sendMachineCommand(username, "STOP")
        return true, msg
    end

    if contains(m, "voz desligada") or contains(m, "desliga a voz") or contains(m, "voice off") then
        if not isOwner(username) then return true, "Esse ajuste e restrito ao operador." end
        runtime.voice_enabled = false
        saveRuntime()
        return true, "Voz da BLUMA desativada."
    end

    if contains(m, "voz ligada") or contains(m, "liga a voz") or contains(m, "voice on") then
        if not isOwner(username) then return true, "Esse ajuste e restrito ao operador." end
        runtime.voice_enabled = true
        saveRuntime()
        return true, "Voz da BLUMA ativada."
    end

    if contains(m, "voz padrao") or contains(m, "voz padrão") or contains(m, "reset voice") then
        if not isOwner(username) then return true, "Esse ajuste e restrito ao operador." end
        runtime.voice_id = DEFAULT_VOICE_ID
        saveRuntime()
        return true, "Voz fixa restaurada."
    end

    local voiceId = message:match("[Bb][Ll][Uu][Mm][Aa]%s+[Vv][Oo][Zz]%s+([%w%-_]+)")
    if not voiceId then
        voiceId = message:match("[Bb][Ll][Uu][Mm][Aa]%s+[Vv][Oo][Ii][Cc][Ee]%s+([%w%-_]+)")
    end
    if voiceId then
        if not isOwner(username) then return true, "Esse ajuste e restrito ao operador." end
        runtime.voice_id = voiceId
        saveRuntime()
        return true, "Nova voz fixa salva. Nao precisa editar config.lua."
    end

    local vol = message:match("[Bb][Ll][Uu][Mm][Aa]%s+[Vv][Oo][Ll][Uu][Mm][Ee]%s+([%d%.]+)")
    if vol then
        if not isOwner(username) then return true, "Esse ajuste e restrito ao operador." end
        local n = tonumber(vol)
        if not n then return true, "Volume invalido." end
        runtime.volume = clamp(n, 0, 3)
        saveRuntime()
        return true, "Volume salvo em " .. tostring(runtime.volume) .. "."
    end

    return false, nil
end

-- ---------------------------
-- PROCESSAMENTO
-- ---------------------------

local function processMessage(username, message)
    state.lastUser = username
    state.lastMessage = message
    state.error = nil
    state.mode = "THINKING"
    state.activity = "PROCESSING REQUEST"
    drawDashboard()
    safeSound("minecraft:block.amethyst_block.chime", 0.10, 1.5)

    local handled, response = parseLocal(username, message)

    if not handled then
        local ai, err = askGroq(username, message)
        if ai then
            response = ai
        else
            response = "Falha ao acessar o nucleo de linguagem: " .. tostring(err)
            state.error = tostring(err)
        end
    end

    response = trim(response or "Sem resposta.")

    addHistory(username, "user", message)
    addHistory(username, "assistant", response)

    state.lastResponse = response
    state.mode = "ONLINE"
    state.activity = "IDLE"
    drawDashboard()

    if wantsPublic(username, message) then
        sendPublic(response)
    else
        sendPrivate(username, response)
    end

    safeSound("minecraft:block.note_block.pling", 0.12, 1.25)

    -- Mensagens administrativas de voz off nao devem se auto-falar depois de desligar.
    if runtime.voice_enabled then
        queueTTS(response)
    end
end

local function chatLoop()
    while true do
        local event, username, message, uuid, isHidden, messageUtf8 = os.pullEvent("chat")
        local actualMessage = messageUtf8 or message or ""
        if calledBluma(actualMessage) then
            local ok, err = pcall(processMessage, username, actualMessage)
            if not ok then
                state.error = tostring(err)
                state.mode = "ONLINE"
                state.activity = "RECOVERED FROM ERROR"
                drawDashboard()
                print("BLUMA ERROR: " .. tostring(err))
                sendPrivate(username, "Ocorreu um erro interno: " .. sanitizeDisplay(tostring(err)))
            end
        end
    end
end

-- ---------------------------
-- UI LOOP
-- ---------------------------

local function uiLoop()
    while true do
        state.spinner = state.spinner + 1
        if state.spinner > 999999 then state.spinner = 1 end
        drawDashboard()
        sleep(0.15)
    end
end

-- ---------------------------
-- START
-- ---------------------------

term.setBackgroundColor(colors.black)
term.setTextColor(colors.cyan)
term.clear()
term.setCursorPos(1, 1)
print("BLUMA CORE v4")
print("Owner: " .. OWNER)
print("Core ID: " .. os.getComputerID())
print("Protocol: " .. CORE_PROTOCOL)
print("Voice ID: " .. tostring(runtime.voice_id))
print("Starting...")

bootAnimation()

parallel.waitForAll(
    chatLoop,
    rednetLoop,
    ttsLoop,
    uiLoop
)
