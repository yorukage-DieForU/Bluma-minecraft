local speaker = peripheral.find("speaker")

if not speaker then
    error("Speaker nao encontrado")
end

local API_KEY = "SUA_CHAVE_FISH_AQUI"
local URL = "https://api.fish.audio/v1/tts"

local texto = "Ola, Murillo. Eu sou a Bluma. Sistemas centrais online."

print("================================")
print("       BLUMA VOICE TEST")
print("================================")
print("")
print("Gerando voz...")

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
    print("ERRO HTTP")
    print(tostring(err))

    if errResponse then
        local erroTexto = errResponse.readAll()
        errResponse.close()

        print("")
        print("Resposta da Fish:")
        print(erroTexto)
    end

    return
end

local audio = response.readAll()
response.close()

print("")
print("Resposta recebida.")
print("Tamanho: " .. tostring(#audio) .. " bytes")

-- =====================================================
-- DEBUG DA RESPOSTA
-- =====================================================

local inicio = audio:sub(1, 12)

print("Cabecalho:")
print(textutils.serialize(inicio))

if audio:sub(1, 4) ~= "RIFF" then
    print("")
    print("A Fish NAO retornou WAV RIFF.")
    print("")
    print("Primeiros caracteres:")
    print(audio:sub(1, 300))
    return
end

if audio:sub(9, 12) ~= "WAVE" then
    print("Arquivo RIFF recebido, mas nao parece WAV.")
    return
end

print("")
print("WAV detectado.")

-- =====================================================
-- LEITURA LITTLE ENDIAN
-- =====================================================

local function readU16(data, pos)
    local b1 = data:byte(pos) or 0
    local b2 = data:byte(pos + 1) or 0

    return b1 + b2 * 256
end

local function readU32(data, pos)
    local b1 = data:byte(pos) or 0
    local b2 = data:byte(pos + 1) or 0
    local b3 = data:byte(pos + 2) or 0
    local b4 = data:byte(pos + 3) or 0

    return b1
        + b2 * 256
        + b3 * 65536
        + b4 * 16777216
end

local function readS16(data, pos)
    local value = readU16(data, pos)

    if value >= 32768 then
        value = value - 65536
    end

    return value
end

-- =====================================================
-- ENCONTRAR CHUNKS
-- =====================================================

local pos = 13

local audioFormat
local channels
local sampleRate
local bitsPerSample

local dataStart
local dataSize

while pos + 7 <= #audio do

    local chunkID = audio:sub(pos, pos + 3)
    local chunkSize = readU32(audio, pos + 4)

    local chunkDataStart = pos + 8

    if chunkID == "fmt " then

        audioFormat = readU16(audio, chunkDataStart)
        channels = readU16(audio, chunkDataStart + 2)
        sampleRate = readU32(audio, chunkDataStart + 4)
        bitsPerSample = readU16(audio, chunkDataStart + 14)

    elseif chunkID == "data" then

        dataStart = chunkDataStart
        dataSize = chunkSize
        break
    end

    pos = chunkDataStart + chunkSize

    if chunkSize % 2 == 1 then
        pos = pos + 1
    end
end

print("")
print("Informacoes do WAV:")
print("Formato: " .. tostring(audioFormat))
print("Canais: " .. tostring(channels))
print("Sample rate: " .. tostring(sampleRate))
print("Bits: " .. tostring(bitsPerSample))
print("Data bytes: " .. tostring(dataSize))

if not dataStart then
    error("Chunk de audio DATA nao encontrado")
end

if audioFormat ~= 1 then
    error(
        "WAV nao esta em PCM linear. Formato recebido: " ..
        tostring(audioFormat)
    )
end

if bitsPerSample ~= 16 then
    error(
        "Esperava PCM 16-bit. Recebido: " ..
        tostring(bitsPerSample)
    )
end

if channels ~= 1 and channels ~= 2 then
    error(
        "Numero de canais nao suportado: " ..
        tostring(channels)
    )
end

if not sampleRate or sampleRate <= 0 then
    error("Sample rate invalido")
end

-- =====================================================
-- CONVERSAO PARA SPEAKER
-- =====================================================

local bytesPerSample = 2
local frameSize = bytesPerSample * channels
local totalFrames = math.floor(dataSize / frameSize)

local TARGET_RATE = 48000

local totalOutputFrames = math.floor(
    totalFrames * TARGET_RATE / sampleRate
)

local function getMonoSample(frameIndex)

    local offset =
        dataStart +
        frameIndex * frameSize

    if channels == 1 then
        return readS16(audio, offset)
    end

    local left = readS16(audio, offset)
    local right = readS16(audio, offset + 2)

    return math.floor((left + right) / 2)
end

local buffer = {}
local BUFFER_SIZE = 12000

local function playBuffer()

    if #buffer == 0 then
        return
    end

    while not speaker.playAudio(buffer, 1.0) do
        os.pullEvent("speaker_audio_empty")
    end

    buffer = {}
end

print("")
print("Convertendo...")
print("Falando...")

for outputFrame = 0, totalOutputFrames - 1 do

    local sourceFrame = math.floor(
        outputFrame * sampleRate / TARGET_RATE
    )

    if sourceFrame >= totalFrames then
        sourceFrame = totalFrames - 1
    end

    local pcm16 = getMonoSample(sourceFrame)

    local sample8 = math.floor(pcm16 / 256)

    if sample8 > 127 then
        sample8 = 127
    end

    if sample8 < -128 then
        sample8 = -128
    end

    buffer[#buffer + 1] = sample8

    if #buffer >= BUFFER_SIZE then
        playBuffer()
    end
end

playBuffer()

print("")
print("Concluido.")
