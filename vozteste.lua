-- =========================================================
-- BLUMA VOICE TEST V2
-- Fish Audio -> WAV PCM -> CC:Tweaked Speaker
-- =========================================================

local speaker = peripheral.find("speaker")

if not speaker then
    error("Speaker nao encontrado.")
end

-- COLOQUE SUA KEY SOMENTE AQUI NO COMPUTADOR
local API_KEY = "SUA_CHAVE_FISH_AQUI"

local URL = "https://api.fish.audio/v1/tts"

-- Volume do Speaker.
-- CC:Tweaked aceita de 0.0 ate 3.0.
local SPEAKER_VOLUME = 2.5

-- Pico maximo do PCM 8-bit.
-- Nao usamos 127 para evitar estouro.
local TARGET_PEAK = 100

local texto =
    "Ola, Murillo. Eu sou a Bluma. Sistemas centrais online. Voz sintetica operacional."

print("======================================")
print("          BLUMA VOICE V2")
print("======================================")
print("")
print("Gerando voz...")

-- =========================================================
-- CHAMAR FISH AUDIO
-- =========================================================

local body = textutils.serializeJSON({
    text = texto,
    format = "wav"
})

local response, err, errResponse = http.post(
    URL,
    body,
    {
        ["Authorization"] = "Bearer " .. API_KEY,
        ["Content-Type"] = "application/json",
        ["model"] = "s2.1-pro-free"
    },
    true
)

if not response then
    print("")
    print("ERRO HTTP:")
    print(tostring(err))

    if errResponse then
        print("")
        print(errResponse.readAll())
        errResponse.close()
    end

    return
end

local wav = response.readAll()
response.close()

print("Recebido: " .. #wav .. " bytes")

-- =========================================================
-- FUNCOES WAV
-- =========================================================

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

    return a
        + b * 256
        + c * 65536
        + d * 16777216
end

local function s16(data, pos)
    local value = u16(data, pos)

    if value >= 32768 then
        value = value - 65536
    end

    return value
end

-- =========================================================
-- VALIDAR WAV
-- =========================================================

if wav:sub(1, 4) ~= "RIFF" then
    print("")
    print("ERRO: resposta nao e WAV.")
    print(wav:sub(1, 300))
    return
end

if wav:sub(9, 12) ~= "WAVE" then
    error("RIFF encontrado, mas nao e WAVE.")
end

-- =========================================================
-- LER CHUNKS DO WAV
-- =========================================================

local pos = 13

local audioFormat
local channels
local sampleRate
local bitsPerSample
local dataStart
local dataSize

while pos + 7 <= #wav do
    local chunkID = wav:sub(pos, pos + 3)
    local chunkSize = u32(wav, pos + 4)
    local start = pos + 8

    if chunkID == "fmt " then
        audioFormat = u16(wav, start)
        channels = u16(wav, start + 2)
        sampleRate = u32(wav, start + 4)
        bitsPerSample = u16(wav, start + 14)

    elseif chunkID == "data" then
        dataStart = start
        dataSize = math.min(chunkSize, #wav - start + 1)
        break
    end

    pos = start + chunkSize

    if chunkSize % 2 == 1 then
        pos = pos + 1
    end
end

print("")
print("WAV:")
print("Formato     : " .. tostring(audioFormat))
print("Canais      : " .. tostring(channels))
print("Sample rate : " .. tostring(sampleRate))
print("Bits        : " .. tostring(bitsPerSample))
print("Audio bytes : " .. tostring(dataSize))
print("")

if not dataStart then
    error("Chunk DATA nao encontrado.")
end

if audioFormat ~= 1 then
    error(
        "Esperava PCM linear. Formato recebido: " ..
        tostring(audioFormat)
    )
end

if bitsPerSample ~= 16 then
    error(
        "Esperava PCM16. Recebido: " ..
        tostring(bitsPerSample)
    )
end

if channels ~= 1 and channels ~= 2 then
    error(
        "Numero de canais nao suportado: " ..
        tostring(channels)
    )
end

-- =========================================================
-- LEITOR DE FRAMES
-- =========================================================

local frameSize = channels * 2
local totalFrames = math.floor(dataSize / frameSize)

local function readMono(frame)
    if frame < 0 then
        frame = 0
    elseif frame >= totalFrames then
        frame = totalFrames - 1
    end

    local offset =
        dataStart +
        frame * frameSize

    if channels == 1 then
        return s16(wav, offset)
    end

    local left = s16(wav, offset)
    local right = s16(wav, offset + 2)

    return (left + right) / 2
end

-- =========================================================
-- ANALISAR AUDIO
-- =========================================================

print("Analisando nivel do audio...")

local soma = 0
local pico = 0

-- Analisa parte suficiente do sinal.
-- Fazemos tudo aqui porque as frases sao curtas.
for frame = 0, totalFrames - 1 do
    local sample = readMono(frame)

    soma = soma + sample

    local absSample = math.abs(sample)

    if absSample > pico then
        pico = absSample
    end
end

local media = soma / math.max(totalFrames, 1)

print("Offset medio : " .. math.floor(media))
print("Pico PCM16   : " .. math.floor(pico))

if pico < 1 then
    error("Audio recebido esta praticamente silencioso.")
end

-- =========================================================
-- CALCULAR GANHO
-- =========================================================

-- Primeiro removemos DC offset e depois encontramos
-- quanto podemos amplificar sem chegar perto do clipping.

local picoCorrigido = 0

for frame = 0, totalFrames - 1 do
    local sample = readMono(frame) - media
    local absSample = math.abs(sample)

    if absSample > picoCorrigido then
        picoCorrigido = absSample
    end
end

if picoCorrigido < 1 then
    picoCorrigido = 1
end

local ganho =
    (TARGET_PEAK * 256) /
    picoCorrigido

-- Nao queremos amplificacao absurda de ruido.
if ganho > 3.0 then
    ganho = 3.0
end

print("Ganho digital: " .. string.format("%.2f", ganho))
print("Volume speaker: " .. tostring(SPEAKER_VOLUME))

-- =========================================================
-- RESAMPLING
-- =========================================================

local TARGET_RATE = 48000

local outputFrames = math.floor(
    totalFrames *
    TARGET_RATE /
    sampleRate
)

local function getResampled(outputFrame)
    -- Posicao fracionaria no audio original
    local sourcePos =
        outputFrame *
        sampleRate /
        TARGET_RATE

    local frameA = math.floor(sourcePos)
    local frameB = frameA + 1

    if frameB >= totalFrames then
        frameB = totalFrames - 1
    end

    local fraction =
        sourcePos - frameA

    local a = readMono(frameA)
    local b = readMono(frameB)

    -- interpolacao linear
    return a + (b - a) * fraction
end

-- =========================================================
-- CONVERSAO PCM16 -> PCM8
-- =========================================================

local function convertSample(pcm16)
    -- remove DC offset
    pcm16 = pcm16 - media

    -- normaliza volume
    pcm16 = pcm16 * ganho

    -- PCM16 -> PCM8
    local sample =
        math.floor(pcm16 / 256)

    -- soft limit
    if sample > TARGET_PEAK then
        sample = TARGET_PEAK

    elseif sample < -TARGET_PEAK then
        sample = -TARGET_PEAK
    end

    return sample
end

-- =========================================================
-- REPRODUCAO
-- =========================================================

-- Quanto maior o buffer, menor a chance de estalo entre blocos.
local BUFFER_SIZE = 64 * 1024

local buffer = {}

local function flush()
    if #buffer == 0 then
        return
    end

    while not speaker.playAudio(
        buffer,
        SPEAKER_VOLUME
    ) do
        os.pullEvent("speaker_audio_empty")
    end

    buffer = {}

    -- Evita timeout do computador.
    sleep(0)
end

print("")
print("BLUMA falando...")
print("")

for i = 0, outputFrames - 1 do
    local pcm16

    if sampleRate == TARGET_RATE then
        -- Fish normalmente ja esta em 48 kHz.
        -- ZERO resampling nesse caso.
        pcm16 = readMono(i)
    else
        pcm16 = getResampled(i)
    end

    buffer[#buffer + 1] =
        convertSample(pcm16)

    if #buffer >= BUFFER_SIZE then
        flush()
    end
end

flush()

print("")
print("Reproducao concluida.")
