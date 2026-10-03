-- ============================================================
-- BLUMA CORE v6
-- Minecraft 1.20.1 | CC:Tweaked | Advanced Peripherals
--
-- Central:
--   Chat Box + Groq + Fish Audio + Advanced Monitor + Rednet
--
-- IMPORTANTE:
-- O asset Unicode da BLUMA pode existir com ou sem .txt.
-- O CC:Tweaked nao desenha Braille/Unicode completo no monitor.
-- O arquivo original e detectado/preservado, enquanto o painel
-- usa um retrato compativel com a fonte do ComputerCraft.
-- ============================================================

local CONFIG = require("config")

local OWNER = "Murillopip"
local PROTOCOL = "BLUMA"
local MACHINE_ID = "MINER-01"
local HEARTBEAT_TIMEOUT = 8

local GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
local GROQ_MODEL = "openai/gpt-oss-20b"

local FISH_URL = "https://api.fish.audio/v1/tts"
local FISH_MODEL = "s2.1-pro-free"

-- Vozes femininas fixas.
local VOICES = {
    ["pt-BR"] = "23c14f5db9dc40ba9c69f38575ae3a80",
    ["en"]    = "f090965f96e34b31b02f4c881e8e609c",
    ["ja"]    = "66635eb26bff4e18a2f9360ac2e6b364"
}

local monitor = peripheral.find("monitor")
local speaker = peripheral.find("speaker")
local chatBox = peripheral.find("chatBox")
local modem = peripheral.find("modem")

if not monitor then error("BLUMA: Advanced Monitor nao encontrado") end
if not speaker then error("BLUMA: Speaker nao encontrado") end
if not chatBox then error("BLUMA: Chat Box nao encontrada") end
if not modem then error("BLUMA: Wireless Modem nao encontrado") end

local modemName = peripheral.getName(modem)
if not rednet.isOpen(modemName) then
    rednet.open(modemName)
end

monitor.setTextScale(0.5)

local runtime = {
    voice_enabled = true,
    volume = 2.1,
    language_mode = "auto"
}

local RUNTIME_FILE = ".bluma_runtime"

local function saveRuntime()
    local h = fs.open(RUNTIME_FILE, "w")
    if not h then return false end
    h.write(textutils.serializeJSON(runtime))
    h.close()
    return true
end

local function loadRuntime()
    if not fs.exists(RUNTIME_FILE) then return end
    local h = fs.open(RUNTIME_FILE, "r")
    if not h then return end
    local raw = h.readAll()
    h.close()
    local data = textutils.unserializeJSON(raw)
    if type(data) ~= "table" then return end

    if type(data.voice_enabled) == "boolean" then
        runtime.voice_enabled = data.voice_enabled
    end

    if type(data.volume) == "number" then
        runtime.volume = data.volume
    end

    if data.language_mode == "auto"
        or data.language_mode == "pt-BR"
        or data.language_mode == "en"
        or data.language_mode == "ja"
    then
        runtime.language_mode = data.language_mode
    end
end

loadRuntime()

local state = {
    mode = "BOOT",
    activity = "INITIALIZING",
    errorText = nil,
    lastUser = "-",
    lastResponse = "",
    machines = {},
    pending = {},
    history = {},
    ttsQueue = {},
    spinner = 1,
    requestCounter = 0,
    asciiAsset = nil
}

local function trim(s)
    s = tostring(s or "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lower(s)
    return string.lower(tostring(s or ""))
end

local function normalizeName(s)
    return lower(trim(s))
end

local function isOwner(username)
    return normalizeName(username) == normalizeName(OWNER)
end

local function contains(text, needle)
    return string.find(lower(text), lower(needle), 1, true) ~= nil
end

local function nowSeconds()
    return os.epoch("utc") / 1000
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function sanitizeDisplay(s)
    s = tostring(s or "")

    local map = {
        ["á"]="a",["à"]="a",["ã"]="a",["â"]="a",
        ["é"]="e",["è"]="e",["ê"]="e",
        ["í"]="i",["ì"]="i",["î"]="i",
        ["ó"]="o",["ò"]="o",["õ"]="o",["ô"]="o",
        ["ú"]="u",["ù"]="u",["û"]="u",
        ["ç"]="c",
        ["Á"]="A",["À"]="A",["Ã"]="A",["Â"]="A",
        ["É"]="E",["È"]="E",["Ê"]="E",
        ["Í"]="I",["Ì"]="I",["Î"]="I",
        ["Ó"]="O",["Ò"]="O",["Õ"]="O",["Ô"]="O",
        ["Ú"]="U",["Ù"]="U",["Û"]="U",
        ["Ç"]="C"
    }

    for a, b in pairs(map) do
        s = s:gsub(a, b)
    end

    return s:gsub("[^\32-\126\n]", "?")
end

local function wrapText(text, width)
    local lines = {}
    local line = ""

    for word in sanitizeDisplay(text):gmatch("%S+") do
        if line == "" then
            line = word
        elseif #line + #word + 1 <= width then
            line = line .. " " .. word
        else
            table.insert(lines, line)
            line = word
        end
    end

    if line ~= "" then
        table.insert(lines, line)
    end

    return lines
end

local function safeSound(name, volume, pitch)
    pcall(function()
        speaker.playSound(name, volume or 0.1, pitch or 1)
    end)
end

-- ============================================================
-- ASCII ASSET
-- ============================================================

local ASCII_CANDIDATES = {
    "bluma_ascii_01.txt",
    "bluma_ascii_01",
    "Bluma-ASCII-01-01.txt",
    "Bluma-ASCII-01-01",
    "bluma-ASCII-01-01.txt",
    "bluma-ASCII-01-01",
    "Bluma_ascii_01.txt",
    "Bluma_ascii_01"
}

local function detectAsciiAsset()
    for _, name in ipairs(ASCII_CANDIDATES) do
        if fs.exists(name) and not fs.isDir(name) then
            state.asciiAsset = name
            return name
        end
    end

    state.asciiAsset = nil
    return nil
end

detectAsciiAsset()

-- Retrato compativel com a fonte do ComputerCraft.
-- O Unicode original continua no arquivo externo.
local PORTRAIT = {
    "           .::::::::::.           ",
    "        .::------------::.        ",
    "      .:----..      ..----:.      ",
    "     :---.              .---:     ",
    "    :--.      .----.      .--:    ",
    "   :--      .========.      --:   ",
    "   :-      /==  __  ==\\      -:   ",
    "   :-     |==  /  \\  ==|     -:   ",
    "   :-     |== | () | ==|     -:   ",
    "   :-     |==  \\__/  ==|     -:   ",
    "   :-      \\==      ==/      -:   ",
    "    :--.     '-====-'     .--:    ",
    "     :---.      /\\      .---:     ",
    "      ':----.  /  \\  .----:'      ",
    "        '::---____---::'           ",
    "           '::::::::'              "
}

-- ============================================================
-- UI
-- ============================================================

local function clearMonitor()
    monitor.setBackgroundColor(colors.black)
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

    writeAt(x, y, "+" .. string.rep("-", w - 2) .. "+", colors.gray, colors.black)

    for yy = y + 1, y + h - 2 do
        writeAt(x, yy, "|", colors.gray, colors.black)
        writeAt(x + w - 1, yy, "|", colors.gray, colors.black)
    end

    writeAt(x, y + h - 1, "+" .. string.rep("-", w - 2) .. "+", colors.gray, colors.black)

    if title then
        writeAt(x + 2, y, " " .. title .. " ", colors.cyan, colors.black)
    end
end

local function machineOnline(m)
    return m and (nowSeconds() - (m.lastSeen or 0) <= HEARTBEAT_TIMEOUT)
end

local function drawDashboard()
    local w, h = monitor.getSize()

    clearMonitor()

    writeAt(2, 1, "BLUMA // CENTRAL INTELLIGENCE", colors.cyan, colors.black)

    local status = "[ONLINE]"
    local statusColor = colors.lime

    if state.errorText then
        status = "[ERROR]"
        statusColor = colors.red
    elseif state.mode == "THINKING" then
        status = "[THINKING]"
        statusColor = colors.orange
    elseif state.mode == "SPEAKING" then
        status = "[SPEAKING]"
        statusColor = colors.yellow
    end

    writeAt(math.max(2, w - #status - 1), 1, status, statusColor, colors.black)
    writeAt(1, 2, string.rep("-", w), colors.gray, colors.black)

    local split = math.floor(w * 0.56)
    if split < 30 then split = math.floor(w * 0.64) end

    local leftW = math.max(24, split - 2)
    local rightX = split + 1
    local rightW = math.max(4, w - rightX)

    drawBox(2, 4, leftW, math.max(10, h - 7), "CORE")
    drawBox(rightX, 4, rightW, math.max(10, h - 7), "BLUMA")

    local y = 6

    writeAt(4, y, "OWNER", colors.gray)
    writeAt(15, y, OWNER, colors.white)
    y = y + 2

    writeAt(4, y, "ACTIVITY", colors.gray)
    writeAt(15, y, sanitizeDisplay(state.activity), colors.yellow)
    y = y + 2

    local miner = state.machines[MACHINE_ID]

    writeAt(4, y, MACHINE_ID, colors.gray)

    if machineOnline(miner) then
        local mstate = tostring(miner.state or "UNKNOWN")
        local c = colors.orange

        if mstate == "RUNNING" then c = colors.lime end
        if mstate == "PAUSED" then c = colors.yellow end
        if mstate == "ERROR" then c = colors.red end

        writeAt(15, y, mstate, c)
        y = y + 1

        writeAt(6, y, "fuel: " .. tostring(miner.fuel or "?"), colors.lightGray)
        y = y + 1

        writeAt(6, y, "slots: " .. tostring(miner.usedSlots or "?") .. "/16", colors.lightGray)
        y = y + 1

        if miner.message then
            local short = sanitizeDisplay(tostring(miner.message))
            if #short > leftW - 10 then
                short = short:sub(1, leftW - 10)
            end
            writeAt(6, y, short, colors.gray)
        end
    else
        writeAt(15, y, "OFFLINE", colors.red)
        y = y + 1
        writeAt(6, y, "waiting for heartbeat", colors.gray)
    end

    y = y + 2

    writeAt(4, y, "ASCII FILE", colors.gray)
    local artState = state.asciiAsset or "not found"
    writeAt(15, y, sanitizeDisplay(artState):sub(1, math.max(1, leftW - 16)), state.asciiAsset and colors.lime or colors.red)
    y = y + 2

    writeAt(4, y, "LAST USER", colors.gray)
    writeAt(15, y, sanitizeDisplay(state.lastUser), colors.white)
    y = y + 2

    if state.lastResponse ~= "" then
        writeAt(4, y, "BLUMA", colors.cyan)
        y = y + 1

        local lines = wrapText(state.lastResponse, math.max(12, leftW - 5))
        local maxLines = math.max(0, h - y - 3)

        for i = 1, math.min(#lines, maxLines) do
            writeAt(4, y, lines[i], colors.white)
            y = y + 1
        end
    end

    local artWidth = math.max(1, rightW - 4)
    local scan = ((state.spinner - 1) % #PORTRAIT) + 1

    for i = 1, math.min(#PORTRAIT, h - 10) do
        local line = PORTRAIT[i]

        if #line > artWidth then
            line = line:sub(1, artWidth)
        end

        local c = colors.lightGray
        if i == scan then c = colors.cyan end

        writeAt(rightX + 2, 6 + i - 1, line, c, colors.black)
    end

    local footer = h - 2

    if footer > 4 then
        writeAt(2, footer, "Bluma ... | mineradora | idioma | voz", colors.gray, colors.black)
    end
end

local function bootAnimation()
    state.mode = "BOOT"
    clearMonitor()

    local w, h = monitor.getSize()

    local function centered(y, text, color)
        local x = math.max(1, math.floor((w - #text) / 2))
        writeAt(x, y, text, color, colors.black)
    end

    centered(2, "BLUMA", colors.cyan)
    centered(3, "CENTRAL INTELLIGENCE SYSTEM", colors.gray)

    local steps = {
        "LOADING CORE",
        "LOADING CONFIG",
        "OPENING REDNET",
        "CHECKING MONITOR",
        "CHECKING SPEAKER",
        "CHECKING CHAT LINK",
        "CHECKING GROQ",
        "CHECKING FISH AUDIO",
        "LOCATING ASCII ASSET",
        "INITIALIZING INTERFACE"
    }

    local y = 6

    for _, label in ipairs(steps) do
        if y < h - 3 then
            writeAt(3, y, label, colors.lightGray, colors.black)
            sleep(0.07)
            writeAt(math.max(3, w - 5), y, "OK", colors.lime, colors.black)
            y = y + 1
        end
    end

    sleep(0.15)
    clearMonitor()

    centered(math.max(2, math.floor(h / 2) - 2), "> USER DETECTED <", colors.yellow)
    sleep(0.2)

    centered(math.max(3, math.floor(h / 2)), "AUTHENTICATING: MURILLOPIP", colors.white)
    sleep(0.2)

    centered(math.max(4, math.floor(h / 2) + 2), "ACCESS GRANTED", colors.lime)
    safeSound("minecraft:block.beacon.activate", 0.25, 1.1)
    sleep(0.35)

    state.mode = "ONLINE"
    state.activity = "IDLE"

    drawDashboard()
end

-- ============================================================
-- HISTORICO
-- ============================================================

local function getHistory(username)
    local key = normalizeName(username)

    if not state.history[key] then
        state.history[key] = {}
    end

    return state.history[key]
end

local function addHistory(username, role, content)
    local history = getHistory(username)

    table.insert(history, {
        role = role,
        content = content
    })

    while #history > 10 do
        table.remove(history, 1)
    end
end

-- ============================================================
-- REDNET / TELEMETRIA
-- ============================================================

local function updateMachine(sender, packet)
    if type(packet) ~= "table" then return end
    if not packet.id then return end

    state.machines[packet.id] = {
        sender = sender,
        state = packet.state or "UNKNOWN",
        fuel = packet.fuel,
        usedSlots = packet.usedSlots,
        message = packet.message,
        lastSeen = nowSeconds()
    }
end

local function machineSummary(private)
    local m = state.machines[MACHINE_ID]

    if not m or not machineOnline(m) then
        return MACHINE_ID .. "=OFFLINE"
    end

    local text = MACHINE_ID .. "=" .. tostring(m.state or "UNKNOWN")

    if private then
        text = text .. " fuel=" .. tostring(m.fuel or "?")
        text = text .. " slots=" .. tostring(m.usedSlots or "?") .. "/16"
    end

    return text
end

local function nextRequestId()
    state.requestCounter = state.requestCounter + 1
    return tostring(os.getComputerID()) .. "-" .. tostring(os.epoch("utc")) .. "-" .. tostring(state.requestCounter)
end

local function sendMachineCommand(username, action)
    if not isOwner(username) then
        return false, "Acesso negado."
    end

    local m = state.machines[MACHINE_ID]

    if not m or not machineOnline(m) then
        return false, "MINER-01 esta offline ou sem heartbeat."
    end

    local requestId = nextRequestId()

    state.pending[requestId] = false

    rednet.send(m.sender, {
        type = "COMMAND",
        id = MACHINE_ID,
        action = action,
        requestId = requestId,
        requestedBy = username
    }, PROTOCOL)

    local deadline = nowSeconds() + 4

    while nowSeconds() < deadline do
        local result = state.pending[requestId]

        if type(result) == "table" then
            state.pending[requestId] = nil

            if result.ok then
                return true, result.message or "Comando confirmado."
            end

            return false, result.message or "Comando rejeitado."
        end

        sleep(0.1)
    end

    state.pending[requestId] = nil

    return false, "MINER-01 nao confirmou o comando."
end

local function rednetLoop()
    while true do
        local _, sender, packet, protocol = os.pullEvent("rednet_message")

        if protocol == PROTOCOL and type(packet) == "table" then
            if packet.type == "HEARTBEAT" or packet.type == "STATUS" then
                updateMachine(sender, packet)

            elseif packet.type == "ACK" then
                updateMachine(sender, packet)

                if packet.requestId then
                    state.pending[packet.requestId] = {
                        ok = packet.ok ~= false,
                        message = packet.message
                    }
                end
            end

            drawDashboard()
        end
    end
end

-- ============================================================
-- IDIOMA
-- ============================================================

local function detectLanguage(message)
    if runtime.language_mode ~= "auto" then
        return runtime.language_mode
    end

    -- Hiragana/Katakana/CJK em UTF-8.
    for i = 1, #message do
        local b = message:byte(i)
        if b and b >= 227 and b <= 233 then
            return "ja"
        end
    end

    local padded = " " .. lower(message) .. " "

    local hints = {
        " hello ",
        " hi ",
        " how ",
        " what ",
        " why ",
        " please ",
        " english ",
        " speak ",
        " start the ",
        " stop the ",
        " status of "
    }

    for _, hint in ipairs(hints) do
        if contains(padded, hint) then
            return "en"
        end
    end

    return "pt-BR"
end

local function languageName(code)
    if code == "ja" then return "Japanese" end
    if code == "en" then return "English" end
    return "Brazilian Portuguese"
end

-- ============================================================
-- GROQ
-- ============================================================

local function buildSystemPrompt(username, language)
    local security

    if isOwner(username) then
        security = [[
The current player is the owner, Murillopip.
He may receive private telemetry and request administrative actions.
]]
    else
        security = [[
The current player is not the owner.
Never reveal coordinates, inventory, fuel, private telemetry,
security settings, keys or administrative controls.
]]
    end

    return [[
You are BLUMA, the central assistant of a Minecraft base.

Reply in ]] .. languageName(language) .. [[.

Style:
- feminine virtual secretary / operations assistant
- calm
- soft
- natural
- concise
- professional
- technically precise

CRITICAL MACHINE RULE:
Never invent machine state, fuel, inventory, progress, coordinates,
production, sensors or command execution.
Only use the telemetry supplied below.
If a machine says OFFLINE, say it is offline/unavailable.

REAL TELEMETRY:
]] .. machineSummary(isOwner(username)) .. "\n\n" .. security
end

local function askGroq(username, message, language)
    local messages = {
        {
            role = "system",
            content = buildSystemPrompt(username, language)
        }
    }

    for _, item in ipairs(getHistory(username)) do
        table.insert(messages, item)
    end

    table.insert(messages, {
        role = "user",
        content = message
    })

    local body = textutils.serializeJSON({
        model = GROQ_MODEL,
        messages = messages,
        temperature = 0.35,
        max_tokens = 300
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

    if not data
        or not data.choices
        or not data.choices[1]
        or not data.choices[1].message
    then
        return nil, "Resposta inesperada da Groq."
    end

    return trim(data.choices[1].message.content)
end

-- ============================================================
-- FISH AUDIO
-- ============================================================

local function readU16(data, pos)
    local a = data:byte(pos) or 0
    local b = data:byte(pos + 1) or 0
    return a + b * 256
end

local function readU32(data, pos)
    local a = data:byte(pos) or 0
    local b = data:byte(pos + 1) or 0
    local c = data:byte(pos + 2) or 0
    local d = data:byte(pos + 3) or 0

    return a + b * 256 + c * 65536 + d * 16777216
end

local function readS16(data, pos)
    local v = readU16(data, pos)

    if v >= 32768 then
        v = v - 65536
    end

    return v
end

local function playWav(wav)
    if wav:sub(1, 4) ~= "RIFF" or wav:sub(9, 12) ~= "WAVE" then
        return false, "Resposta de audio nao e WAV."
    end

    local pos = 13

    local audioFormat = nil
    local channels = nil
    local sampleRate = nil
    local bits = nil
    local dataStart = nil
    local dataSize = nil

    while pos + 7 <= #wav do
        local chunkId = wav:sub(pos, pos + 3)
        local chunkSize = readU32(wav, pos + 4)
        local start = pos + 8

        if chunkId == "fmt " then
            audioFormat = readU16(wav, start)
            channels = readU16(wav, start + 2)
            sampleRate = readU32(wav, start + 4)
            bits = readU16(wav, start + 14)

        elseif chunkId == "data" then
            dataStart = start
            dataSize = math.min(chunkSize, #wav - start + 1)
            break
        end

        pos = start + chunkSize

        if chunkSize % 2 == 1 then
            pos = pos + 1
        end
    end

    if not dataStart then return false, "Chunk DATA ausente." end
    if audioFormat ~= 1 then return false, "WAV nao e PCM." end
    if bits ~= 16 then return false, "WAV nao e PCM16." end
    if channels ~= 1 and channels ~= 2 then return false, "Canais nao suportados." end
    if not sampleRate or sampleRate <= 0 then return false, "Sample rate invalido." end

    local frameSize = channels * 2
    local totalFrames = math.floor(dataSize / frameSize)

    if totalFrames <= 0 then
        return false, "Audio vazio."
    end

    local function mono(frame)
        frame = clamp(frame, 0, totalFrames - 1)

        local p = dataStart + frame * frameSize

        if channels == 1 then
            return readS16(wav, p)
        end

        return (readS16(wav, p) + readS16(wav, p + 2)) / 2
    end

    local targetRate = 48000
    local outputFrames = math.floor(totalFrames * targetRate / sampleRate)

    local buffer = {}
    local bufferLimit = 32768

    local function sampleAt(outIndex)
        if sampleRate == targetRate then
            return mono(outIndex)
        end

        local source = outIndex * sampleRate / targetRate
        local a = math.floor(source)
        local b = math.min(a + 1, totalFrames - 1)
        local f = source - a

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
        local sample = sampleAt(i)

        -- Reducao para 8-bit sem esmagar tanto o sinal.
        sample = math.floor(sample / 300)
        sample = clamp(sample, -104, 104)

        buffer[#buffer + 1] = sample

        if #buffer >= bufferLimit then
            flush()
        end
    end

    flush()

    return true
end

local function fishSpeak(text, language)
    if not runtime.voice_enabled then
        return true
    end

    local voiceId = VOICES[language] or VOICES["pt-BR"]

    local payload = {
        text = text,
        reference_id = voiceId,
        format = "wav"
    }

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

local function ttsLoop()
    while true do
        if #state.ttsQueue == 0 then
            sleep(0.1)
        else
            local job = table.remove(state.ttsQueue, 1)

            state.mode = "SPEAKING"
            state.activity = "VOICE " .. tostring(job.language)
            drawDashboard()

            local ok, err = fishSpeak(job.text, job.language)

            if not ok then
                state.errorText = "VOICE: " .. tostring(err)
                print(state.errorText)
            end

            state.mode = "ONLINE"
            state.activity = "IDLE"

            drawDashboard()
        end
    end
end

-- ============================================================
-- CHAT
-- ============================================================

local function sendPrivate(username, text)
    pcall(function()
        chatBox.sendMessageToPlayer(
            sanitizeDisplay(text),
            username,
            "BLUMA",
            "[]",
            "&b"
        )
    end)
end

local function sendPublic(text)
    pcall(function()
        chatBox.sendMessage(
            sanitizeDisplay(text),
            "BLUMA",
            "[]",
            "&b"
        )
    end)
end

local function calledBluma(message)
    return contains(message, "bluma")
end

local function wantsPublic(username, message)
    if not isOwner(username) then
        return true
    end

    return contains(message, "bluma publico")
        or contains(message, "bluma público")
        or contains(message, "bluma public")
end

local function localCommand(username, message, language)
    if contains(message, "diagnostico")
        or contains(message, "diagnóstico")
        or contains(message, "diagnostic")
    then
        return true,
            "username='" .. tostring(username)
            .. "' owner=" .. tostring(isOwner(username))
            .. " lang=" .. language
            .. " ascii=" .. tostring(state.asciiAsset)
            .. " " .. machineSummary(isOwner(username))
    end

    if contains(message, "status da mineradora")
        or contains(message, "status mineradora")
        or contains(message, "miner status")
    then
        if not isOwner(username) then
            return true, "Essas informacoes sao restritas ao operador."
        end

        return true, machineSummary(true)
    end

    if contains(message, "liga a mineradora")
        or contains(message, "ligar mineradora")
        or contains(message, "start miner")
        or contains(message, "start the miner")
    then
        local _, msg = sendMachineCommand(username, "START")
        return true, msg
    end

    if contains(message, "pausa a mineradora")
        or contains(message, "pausar mineradora")
        or contains(message, "pause miner")
    then
        local _, msg = sendMachineCommand(username, "PAUSE")
        return true, msg
    end

    if contains(message, "continua a mineradora")
        or contains(message, "retoma a mineradora")
        or contains(message, "resume miner")
    then
        local _, msg = sendMachineCommand(username, "RESUME")
        return true, msg
    end

    if contains(message, "para a mineradora")
        or contains(message, "parar mineradora")
        or contains(message, "stop miner")
        or contains(message, "stop the miner")
    then
        local _, msg = sendMachineCommand(username, "STOP")
        return true, msg
    end

    if contains(message, "idioma automatico")
        or contains(message, "idioma automático")
        or contains(message, "language auto")
    then
        if not isOwner(username) then return true, "Acesso negado." end

        runtime.language_mode = "auto"
        saveRuntime()

        return true, "Deteccao automatica de idioma ativada."
    end

    if contains(message, "idioma portugues")
        or contains(message, "idioma português")
    then
        if not isOwner(username) then return true, "Acesso negado." end

        runtime.language_mode = "pt-BR"
        saveRuntime()

        return true, "Idioma fixado em portugues brasileiro."
    end

    if contains(message, "idioma ingles")
        or contains(message, "idioma inglês")
        or contains(message, "language english")
    then
        if not isOwner(username) then return true, "Acesso negado." end

        runtime.language_mode = "en"
        saveRuntime()

        return true, "Language fixed to English."
    end

    if contains(message, "idioma japones")
        or contains(message, "idioma japonês")
        or contains(message, "language japanese")
    then
        if not isOwner(username) then return true, "Acesso negado." end

        runtime.language_mode = "ja"
        saveRuntime()

        return true, "Japanese mode enabled."
    end

    if contains(message, "voz desligada")
        or contains(message, "desliga a voz")
        or contains(message, "voice off")
    then
        if not isOwner(username) then return true, "Acesso negado." end

        runtime.voice_enabled = false
        saveRuntime()

        return true, "Voz desativada."
    end

    if contains(message, "voz ligada")
        or contains(message, "liga a voz")
        or contains(message, "voice on")
    then
        if not isOwner(username) then return true, "Acesso negado." end

        runtime.voice_enabled = true
        saveRuntime()

        return true, "Voz ativada."
    end

    local volume = message:match("[Bb][Ll][Uu][Mm][Aa]%s+[Vv][Oo][Ll][Uu][Mm][Ee]%s+([%d%.]+)")

    if volume then
        if not isOwner(username) then return true, "Acesso negado." end

        local n = tonumber(volume)

        if not n then
            return true, "Volume invalido."
        end

        runtime.volume = clamp(n, 0, 3)
        saveRuntime()

        return true, "Volume salvo em " .. tostring(runtime.volume) .. "."
    end

    return false, nil
end

local function processMessage(username, message)
    state.lastUser = username
    state.errorText = nil

    local language = detectLanguage(message)

    state.mode = "THINKING"
    state.activity = "PROCESSING " .. language

    drawDashboard()
    safeSound("minecraft:block.amethyst_block.chime", 0.1, 1.5)

    local handled, response = localCommand(username, message, language)

    if not handled then
        local ai, err = askGroq(username, message, language)

        if ai then
            response = ai
        else
            response = "Falha no nucleo de linguagem: " .. tostring(err)
            state.errorText = tostring(err)
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

    if runtime.voice_enabled then
        table.insert(state.ttsQueue, {
            text = response,
            language = language
        })
    end
end

local function chatLoop()
    while true do
        local _, username, message, uuid, isHidden, messageUtf8 = os.pullEvent("chat")

        local actual = messageUtf8 or message or ""

        if calledBluma(actual) then
            local ok, err = pcall(processMessage, username, actual)

            if not ok then
                state.errorText = tostring(err)
                state.mode = "ONLINE"
                state.activity = "ERROR RECOVERED"

                print("BLUMA ERROR: " .. tostring(err))
                drawDashboard()

                sendPrivate(
                    username,
                    "Erro interno: " .. sanitizeDisplay(tostring(err))
                )
            end
        end
    end
end

local function uiLoop()
    while true do
        state.spinner = state.spinner + 1

        if state.spinner > 1000000 then
            state.spinner = 1
        end

        drawDashboard()
        sleep(0.15)
    end
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.cyan)
term.clear()
term.setCursorPos(1, 1)

print("BLUMA CORE v6")
print("Owner: " .. OWNER)
print("Core ID: " .. tostring(os.getComputerID()))
print("ASCII asset: " .. tostring(state.asciiAsset))
print("Starting...")

bootAnimation()

parallel.waitForAll(
    chatLoop,
    rednetLoop,
    ttsLoop,
    uiLoop
)
