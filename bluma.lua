-- ============================================================
--                         BLUMA
--                Base Logical Unified
--                 Management Assistant
--
-- CC:Tweaked + Advanced Peripherals
--
-- Recursos:
--   Chat
--   Groq AI
--   Fish Audio TTS
--   Monitor
--   Speaker
--   Rednet
--   Telemetria
--   Controle seguro
--   Historico
--   Permissoes
-- ============================================================

local CONFIG = require("config")

-- ============================================================
-- PERIFERICOS
-- ============================================================

local monitor = peripheral.find("monitor")
local speaker = peripheral.find("speaker")
local chatBox = peripheral.find("chatBox")
local modem = peripheral.find("modem")

if not monitor then
    error("Monitor nao encontrado.")
end

if not speaker then
    error("Speaker nao encontrado.")
end

if not chatBox then
    error("Chat Box nao encontrada.")
end

if not modem then
    error("Wireless Modem nao encontrado.")
end

-- ============================================================
-- REDNET
-- ============================================================

local modemName = peripheral.getName(modem)

if not rednet.isOpen(modemName) then
    rednet.open(modemName)
end

-- ============================================================
-- CONFIGURACAO MONITOR
-- ============================================================

monitor.setTextScale(0.5)
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.white)
monitor.clear()

-- ============================================================
-- ESTADO
-- ============================================================

local state = {

    status = "ONLINE",

    speaking = false,

    thinking = false,

    lastUser = nil,

    lastMessage = nil,

    lastResponse = nil,

    machines = {},

    history = {}
}

-- ============================================================
-- UTILIDADES
-- ============================================================

local function now()
    return os.epoch("utc") / 1000
end

local function isOwner(username)
    return username == CONFIG.OWNER
end

local function lower(text)
    return string.lower(text or "")
end

-- ============================================================
-- DISPLAY ASCII
-- ============================================================

local replacements = {

    ["á"] = "a",
    ["à"] = "a",
    ["ã"] = "a",
    ["â"] = "a",

    ["Á"] = "A",
    ["À"] = "A",
    ["Ã"] = "A",
    ["Â"] = "A",

    ["é"] = "e",
    ["ê"] = "e",
    ["É"] = "E",
    ["Ê"] = "E",

    ["í"] = "i",
    ["Í"] = "I",

    ["ó"] = "o",
    ["ô"] = "o",
    ["õ"] = "o",

    ["Ó"] = "O",
    ["Ô"] = "O",
    ["Õ"] = "O",

    ["ú"] = "u",
    ["Ú"] = "U",

    ["ç"] = "c",
    ["Ç"] = "C"
}

local function ascii(text)

    text = tostring(text or "")

    for original, replacement in pairs(replacements) do
        text = text:gsub(original, replacement)
    end

    return text
end

-- ============================================================
-- QUEBRA DE TEXTO
-- ============================================================

local function wrapText(text, width)

    local lines = {}
    local line = ""

    for word in text:gmatch("%S+") do

        if #line + #word + 1 > width then

            table.insert(lines, line)

            line = word

        else

            if line == "" then
                line = word
            else
                line = line .. " " .. word
            end

        end
    end

    if line ~= "" then
        table.insert(lines, line)
    end

    return lines
end

-- ============================================================
-- MONITOR
-- ============================================================

local function drawHeader()

    local w = monitor.getSize()

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.cyan)

    monitor.setCursorPos(2, 1)
    monitor.write("BLUMA")

    monitor.setTextColor(colors.gray)

    monitor.setCursorPos(2, 2)
    monitor.write(
        "CENTRAL INTELLIGENCE SYSTEM"
    )

    monitor.setCursorPos(1, 3)
    monitor.write(
        string.rep("-", w)
    )
end

local function drawStatus()

    local w, h = monitor.getSize()

    monitor.setBackgroundColor(colors.black)

    monitor.setCursorPos(2, 5)

    if state.thinking then

        monitor.setTextColor(colors.orange)
        monitor.write("STATUS: PROCESSANDO")

    elseif state.speaking then

        monitor.setTextColor(colors.lime)
        monitor.write("STATUS: FALANDO")

    else

        monitor.setTextColor(colors.green)
        monitor.write("STATUS: ONLINE")

    end

    monitor.setTextColor(colors.lightGray)

    monitor.setCursorPos(2, 7)
    monitor.write(
        "OPERADOR: " ..
        ascii(CONFIG.OWNER)
    )

    monitor.setCursorPos(2, 9)

    local count = 0

    for _ in pairs(state.machines) do
        count = count + 1
    end

    monitor.write(
        "MAQUINAS REGISTRADAS: " ..
        count
    )

    monitor.setCursorPos(2, h - 1)

    monitor.setTextColor(colors.gray)

    monitor.write(
        "BLUMA CORE"
    )
end

local function drawConversation()

    local w, h = monitor.getSize()

    if not state.lastResponse then
        return
    end

    local startY = 12

    monitor.setTextColor(colors.cyan)
    monitor.setCursorPos(2, startY)

    monitor.write("BLUMA:")

    local lines =
        wrapText(
            ascii(state.lastResponse),
            w - 4
        )

    monitor.setTextColor(colors.white)

    for i = 1, math.min(#lines, h - startY - 2) do

        monitor.setCursorPos(
            2,
            startY + i
        )

        monitor.write(lines[i])
    end
end

local function redraw()

    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    drawHeader()
    drawStatus()
    drawConversation()
end

-- ============================================================
-- SOM UI
-- ============================================================

local function soundThinking()

    pcall(function()

        speaker.playSound(
            "minecraft:block.amethyst_block.chime",
            0.25,
            1.4
        )

    end)
end

local function soundReady()

    pcall(function()

        speaker.playSound(
            "minecraft:block.note_block.pling",
            0.25,
            1.3
        )

    end)
end

-- ============================================================
-- HISTORICO
-- ============================================================

local function getHistory(username)

    if not state.history[username] then
        state.history[username] = {}
    end

    return state.history[username]
end

local function addHistory(
    username,
    role,
    content
)

    local history =
        getHistory(username)

    table.insert(
        history,
        {
            role = role,
            content = content
        }
    )

    while #history > 10 do
        table.remove(history, 1)
    end
end

-- ============================================================
-- MAQUINAS
-- ============================================================

local function updateMachine(
    id,
    data,
    sender
)

    if type(data) ~= "table" then
        return
    end

    state.machines[id] = {

        id = id,

        sender = sender,

        type =
            data.type or
            "UNKNOWN",

        state =
            data.state or
            "UNKNOWN",

        fuel =
            data.fuel,

        progress =
            data.progress,

        position =
            data.position,

        message =
            data.message,

        lastSeen =
            now()
    }
end

local function machineOnline(machine)

    if not machine then
        return false
    end

    return
        now() - machine.lastSeen
        <= CONFIG.HEARTBEAT_TIMEOUT
end

local function machineSummary(private)

    local result = {}

    for id, machine in pairs(state.machines) do

        local online =
            machineOnline(machine)

        local text =
            id ..
            ": " ..
            (
                online
                and machine.state
                or "OFFLINE"
            )

        if private and online then

            if machine.fuel ~= nil then
                text =
                    text ..
                    ", combustivel " ..
                    tostring(machine.fuel)
            end

            if machine.progress ~= nil then
                text =
                    text ..
                    ", progresso " ..
                    tostring(machine.progress)
            end

            if machine.position then

                text =
                    text ..
                    ", posicao " ..
                    textutils.serialize(
                        machine.position
                    )
            end
        end

        table.insert(result, text)
    end

    if #result == 0 then
        return "Nenhuma maquina possui telemetria."
    end

    return table.concat(result, "\n")
end

-- ============================================================
-- CONTROLE DE MAQUINAS
-- ============================================================

local function sendMachineCommand(
    username,
    machineID,
    action
)

    if not isOwner(username) then
        return false,
            "Acesso negado."
    end

    local machine =
        state.machines[machineID]

    if not machine then

        return false,
            "Nao existe telemetria para " ..
            machineID .. "."

    end

    if not machineOnline(machine) then

        return false,
            machineID ..
            " esta offline. " ..
            "Nao posso confirmar nem executar o comando."

    end

    rednet.send(
        machine.sender,
        {
            type = "COMMAND",

            machine = machineID,

            action = action,

            requestedBy = username
        },
        CONFIG.REDNET_PROTOCOL
    )

    return true,
        "Comando " ..
        action ..
        " enviado para " ..
        machineID .. "."
end

-- ============================================================
-- CONTEXTO DA IA
-- ============================================================

local function buildSystemPrompt(username)

    local owner =
        isOwner(username)

    local telemetry =
        machineSummary(owner)

    local permission

    if owner then

        permission = [[
O usuario atual e MurilloPip, proprietario e administrador da BLUMA.

Ele pode consultar informacoes internas e solicitar comandos administrativos.

Mesmo assim, nunca invente execucao de comandos.
]]

    else

        permission = [[
O usuario atual NAO e o proprietario.

Converse normalmente, mas NUNCA revele:
- coordenadas
- inventarios
- recursos internos
- seguranca
- configuracoes
- chaves
- dados administrativos
- localizacao de maquinas
- comandos administrativos
- informacoes privadas da base

O usuario nao pode controlar maquinas.
]]

    end

    return [[
Voce e BLUMA, a inteligencia central de uma base no Minecraft.

Fale em portugues brasileiro natural.

Seu estilo:
- inteligente
- direta
- calma
- tecnica quando necessario
- respostas relativamente curtas
- nao fale como assistente generico

REGRA CRITICA:

Voce NAO possui acesso magico ao Minecraft.

Toda informacao sobre:
- maquinas
- mineradoras
- energia
- combustivel
- progresso
- inventario
- coordenadas
- producao
- jogadores

deve vir exclusivamente da telemetria fornecida abaixo.

Se uma maquina estiver OFFLINE, diga que esta offline ou sem telemetria.

NUNCA invente:
- porcentagens
- status
- producao
- coordenadas
- combustivel
- sensores
- itens
- execucao de comandos

Nao diga que uma maquina foi ligada ou desligada apenas porque o usuario pediu.

O BLUMA CORE e responsavel por executar comandos reais.

]] ..
    permission ..
    "\n\nTELEMETRIA REAL ATUAL:\n" ..
    telemetry
end

-- ============================================================
-- GROQ
-- ============================================================

local function askGroq(
    username,
    message
)

    local messages = {}

    table.insert(
        messages,
        {
            role = "system",
            content =
                buildSystemPrompt(username)
        }
    )

    local history =
        getHistory(username)

    for _, msg in ipairs(history) do
        table.insert(messages, msg)
    end

    table.insert(
        messages,
        {
            role = "user",
            content = message
        }
    )

    local requestBody =
        textutils.serializeJSON({

            model =
                CONFIG.GROQ_MODEL,

            messages =
                messages,

            temperature =
                0.5,

            max_tokens =
                300
        })

    local response,
          err,
          errResponse =
        http.post(

            CONFIG.GROQ_URL,

            requestBody,

            {
                ["Authorization"] =
                    "Bearer " ..
                    CONFIG.GROQ_KEY,

                ["Content-Type"] =
                    "application/json"
            }
        )

    if not response then

        local detail =
            tostring(err)

        if errResponse then

            detail =
                detail ..
                " " ..
                errResponse.readAll()

            errResponse.close()
        end

        return nil, detail
    end

    local raw =
        response.readAll()

    response.close()

    local data =
        textutils.unserializeJSON(raw)

    if not data then
        return nil,
            "Resposta JSON invalida."
    end

    if not data.choices
        or not data.choices[1]
        or not data.choices[1].message
    then

        return nil,
            "Resposta inesperada da Groq."
    end

    return
        data.choices[1].message.content
end

-- ============================================================
-- WAV
-- ============================================================

local function readU16(data, pos)

    local a =
        data:byte(pos) or 0

    local b =
        data:byte(pos + 1) or 0

    return a + b * 256
end

local function readU32(data, pos)

    local a =
        data:byte(pos) or 0

    local b =
        data:byte(pos + 1) or 0

    local c =
        data:byte(pos + 2) or 0

    local d =
        data:byte(pos + 3) or 0

    return
        a +
        b * 256 +
        c * 65536 +
        d * 16777216
end

local function readS16(data, pos)

    local value =
        readU16(data, pos)

    if value >= 32768 then
        value =
            value - 65536
    end

    return value
end

-- ============================================================
-- PLAY WAV
-- ============================================================

local function playWav(wav)

    if wav:sub(1, 4) ~= "RIFF" then
        return false,
            "Audio recebido nao e RIFF."
    end

    if wav:sub(9, 12) ~= "WAVE" then
        return false,
            "Audio recebido nao e WAV."
    end

    local pos = 13

    local audioFormat
    local channels
    local sampleRate
    local bitsPerSample

    local dataStart
    local dataSize

    while pos + 7 <= #wav do

        local chunkID =
            wav:sub(
                pos,
                pos + 3
            )

        local chunkSize =
            readU32(
                wav,
                pos + 4
            )

        local start =
            pos + 8

        if chunkID == "fmt " then

            audioFormat =
                readU16(
                    wav,
                    start
                )

            channels =
                readU16(
                    wav,
                    start + 2
                )

            sampleRate =
                readU32(
                    wav,
                    start + 4
                )

            bitsPerSample =
                readU16(
                    wav,
                    start + 14
                )

        elseif chunkID == "data" then

            dataStart = start

            dataSize =
                math.min(
                    chunkSize,
                    #wav - start + 1
                )

            break
        end

        pos =
            start + chunkSize

        if chunkSize % 2 == 1 then
            pos = pos + 1
        end
    end

    if not dataStart then
        return false,
            "Chunk DATA ausente."
    end

    if audioFormat ~= 1 then
        return false,
            "Formato WAV nao e PCM."
    end

    if bitsPerSample ~= 16 then
        return false,
            "WAV nao e PCM16."
    end

    if channels ~= 1
        and channels ~= 2
    then

        return false,
            "Quantidade de canais nao suportada."
    end

    local frameSize =
        channels * 2

    local totalFrames =
        math.floor(
            dataSize /
            frameSize
        )

    if totalFrames <= 0 then
        return false,
            "Audio vazio."
    end

    local function readMono(frame)

        if frame < 0 then
            frame = 0
        end

        if frame >= totalFrames then
            frame =
                totalFrames - 1
        end

        local offset =
            dataStart +
            frame * frameSize

        if channels == 1 then

            return
                readS16(
                    wav,
                    offset
                )

        end

        local left =
            readS16(
                wav,
                offset
            )

        local right =
            readS16(
                wav,
                offset + 2
            )

        return
            (left + right) / 2
    end

    -- =========================================
    -- ANALISE
    -- =========================================

    local sum = 0

    for frame = 0,
        totalFrames - 1
    do

        sum =
            sum +
            readMono(frame)

        if frame % 20000 == 0 then
            sleep(0)
        end
    end

    local mean =
        sum /
        totalFrames

    local peak = 1

    for frame = 0,
        totalFrames - 1
    do

        local value =
            math.abs(
                readMono(frame)
                - mean
            )

        if value > peak then
            peak = value
        end

        if frame % 20000 == 0 then
            sleep(0)
        end
    end

    local targetPeak =
        CONFIG.AUDIO_PEAK
        or 100

    local gain =
        (targetPeak * 256)
        / peak

    if gain > 2.0 then
        gain = 2.0
    end

    -- =========================================
    -- RESAMPLING
    -- =========================================

    local targetRate =
        48000

    local outputFrames =
        math.floor(
            totalFrames *
            targetRate /
            sampleRate
        )

    local function sampleAt(
        outputFrame
    )

        if sampleRate ==
            targetRate
        then

            return
                readMono(
                    outputFrame
                )
        end

        local sourcePosition =
            outputFrame *
            sampleRate /
            targetRate

        local aFrame =
            math.floor(
                sourcePosition
            )

        local bFrame =
            math.min(
                aFrame + 1,
                totalFrames - 1
            )

        local fraction =
            sourcePosition -
            aFrame

        local a =
            readMono(aFrame)

        local b =
            readMono(bFrame)

        return
            a +
            (b - a) *
            fraction
    end

    -- =========================================
    -- PLAYBACK
    -- =========================================

    local buffer = {}

    -- CC:Tweaked suporta ate
    -- 128 * 1024 samples.
    local BUFFER_SIZE =
        96 * 1024

    local function flush()

        if #buffer == 0 then
            return
        end

        while not speaker.playAudio(
            buffer,
            CONFIG.SPEAKER_VOLUME
            or 2.0
        ) do

            os.pullEvent(
                "speaker_audio_empty"
            )
        end

        buffer = {}

        sleep(0)
    end

    for i = 0,
        outputFrames - 1
    do

        local sample =
            sampleAt(i)

        sample =
            (sample - mean)
            * gain

        sample =
            math.floor(
                sample / 256
            )

        if sample > targetPeak then
            sample = targetPeak
        end

        if sample < -targetPeak then
            sample = -targetPeak
        end

        buffer[#buffer + 1] =
            sample

        if #buffer >=
            BUFFER_SIZE
        then
            flush()
        end
    end

    flush()

    return true
end

-- ============================================================
-- FISH AUDIO
-- ============================================================

local function fishSpeak(text)

    if not text
        or text == ""
    then
        return
    end

    state.speaking = true
    redraw()

    local payload = {

        text = text,

        format = "wav"
    }

    -- Quando escolhermos a voz brasileira:
    if CONFIG.FISH_REFERENCE_ID then

        payload.reference_id =
            CONFIG.FISH_REFERENCE_ID
    end

    local body =
        textutils.serializeJSON(
            payload
        )

    local response,
          err,
          errResponse =
        http.post(

            CONFIG.FISH_URL,

            body,

            {
                ["Authorization"] =
                    "Bearer " ..
                    CONFIG.FISH_KEY,

                ["Content-Type"] =
                    "application/json",

                ["model"] =
                    CONFIG.FISH_MODEL
            },

            true
        )

    if not response then

        state.speaking = false
        redraw()

        print(
            "Fish error: " ..
            tostring(err)
        )

        if errResponse then

            print(
                errResponse.readAll()
            )

            errResponse.close()
        end

        return
    end

    local audio =
        response.readAll()

    response.close()

    local ok, playError =
        playWav(audio)

    if not ok then

        print(
            "Audio error: " ..
            tostring(playError)
        )
    end

    state.speaking = false
    redraw()
end

-- ============================================================
-- CHAT
-- ============================================================

local function calledBluma(message)

    return
        lower(message):find(
            "bluma",
            1,
            true
        ) ~= nil
end

local function wantsPublic(
    username,
    message
)

    if not isOwner(username) then
        return true
    end

    local m =
        lower(message)

    return
        m:find(
            "bluma publico",
            1,
            true
        ) ~= nil
        or
        m:find(
            "bluma público",
            1,
            true
        ) ~= nil
end

local function sendPrivate(
    username,
    text
)

    local display =
        ascii(text)

    pcall(function()

        chatBox.sendMessageToPlayer(
            display,
            username,
            "BLUMA",
            "[]",
            "&b"
        )

    end)
end

local function sendPublic(text)

    local display =
        ascii(text)

    pcall(function()

        chatBox.sendMessage(
            display,
            "BLUMA",
            "[]",
            "&b"
        )

    end)
end

-- ============================================================
-- COMANDOS LOCAIS
-- ============================================================

local function localCommand(
    username,
    message
)

    local m =
        lower(message)

    -- STATUS

    if m:find(
        "status das maquinas",
        1,
        true
    )
    or
    m:find(
        "status da base",
        1,
        true
    )
    then

        if not isOwner(username) then

            return true,
                "Essas informacoes sao restritas ao operador."

        end

        return true,
            machineSummary(true)
    end

    -- LIGAR MINERADORA

    if m:find(
        "liga a mineradora",
        1,
        true
    )
    or
    m:find(
        "ligar mineradora",
        1,
        true
    )
    then

        local ok, result =
            sendMachineCommand(
                username,
                "MINER-01",
                "START"
            )

        return true, result
    end

    -- PARAR MINERADORA

    if m:find(
        "para a mineradora",
        1,
        true
    )
    or
    m:find(
        "parar mineradora",
        1,
        true
    )
    then

        local ok, result =
            sendMachineCommand(
                username,
                "MINER-01",
                "STOP"
            )

        return true, result
    end

    return false
end

-- ============================================================
-- PROCESSAMENTO
-- ============================================================

local function processMessage(
    username,
    message
)

    state.lastUser =
        username

    state.lastMessage =
        message

    state.thinking =
        true

    redraw()

    soundThinking()

    -- =========================================
    -- COMANDO REAL
    -- =========================================

    local handled,
          localResponse =
        localCommand(
            username,
            message
        )

    local response

    if handled then

        response =
            localResponse

    else

        -- =====================================
        -- IA
        -- =====================================

        local ai,
              err =
            askGroq(
                username,
                message
            )

        if not ai then

            response =
                "Nao consegui acessar meu nucleo de linguagem. " ..
                tostring(err)

        else

            response = ai
        end
    end

    state.thinking =
        false

    state.lastResponse =
        response

    redraw()

    -- =========================================
    -- HISTORICO
    -- =========================================

    addHistory(
        username,
        "user",
        message
    )

    addHistory(
        username,
        "assistant",
        response
    )

    -- =========================================
    -- CHAT
    -- =========================================

    if wantsPublic(
        username,
        message
    ) then

        sendPublic(response)

    else

        sendPrivate(
            username,
            response
        )
    end

    soundReady()

    -- =========================================
    -- VOZ
    -- =========================================

    -- A voz recebe o texto ORIGINAL.
    -- Nao usamos ASCII aqui.
    --
    -- Portanto:
    --
    -- "Olá, Murillo"
    --
    -- continua com acentos para melhorar
    -- pronuncia do TTS.

    fishSpeak(response)
end

-- ============================================================
-- REDNET LISTENER
-- ============================================================

local function rednetLoop()

    while true do

        local sender,
              message,
              protocol =
            rednet.receive()

        if type(message) ==
            "table"
        then

            if message.type ==
                "HEARTBEAT"
            then

                local id =
                    message.id

                if id then

                    updateMachine(
                        id,
                        message,
                        sender
                    )

                    redraw()
                end
            end

            if message.type ==
                "STATUS"
            then

                local id =
                    message.id

                if id then

                    updateMachine(
                        id,
                        message,
                        sender
                    )

                    redraw()
                end
            end
        end
    end
end

-- ============================================================
-- CHAT LISTENER
-- ============================================================

local function chatLoop()

    while true do

        local event,
              username,
              message,
              uuid,
              isHidden,
              messageUtf8 =
            os.pullEvent("chat")

        if calledBluma(message) then

            local ok, err =
                pcall(
                    processMessage,
                    username,
                    message
                )

            if not ok then

                print(
                    "BLUMA ERROR: " ..
                    tostring(err)
                )

                sendPrivate(
                    username,
                    "Ocorreu um erro interno."
                )

                state.thinking = false
                state.speaking = false

                redraw()
            end
        end
    end
end

-- ============================================================
-- WATCHDOG
-- ============================================================

local function watchdogLoop()

    while true do

        -- Nao apagamos maquinas.
        -- Elas permanecem registradas e passam
        -- automaticamente para OFFLINE caso
        -- heartbeat pare.

        redraw()

        sleep(2)
    end
end

-- ============================================================
-- BOOT
-- ============================================================

local function boot()

    redraw()

    speaker.playSound(
        "minecraft:block.beacon.activate",
        0.4,
        1.2
    )

    print("")
    print("==============================")
    print("          BLUMA CORE")
    print("==============================")
    print("")
    print("Owner: " .. CONFIG.OWNER)
    print("Monitor: OK")
    print("Speaker: OK")
    print("ChatBox: OK")
    print("Wireless: OK")
    print("Groq: READY")
    print("Fish Audio: READY")
    print("")
    print("Aguardando comandos...")
    print("")
end

boot()

parallel.waitForAny(
    chatLoop,
    rednetLoop,
    watchdogLoop
)
