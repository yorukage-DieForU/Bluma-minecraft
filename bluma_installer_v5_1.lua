-- BLUMA UNIVERSAL INSTALLER V5.1
-- Core + MINER-01 + CRAFT-01

local VERSION = "5.1.0"
local CONFIG_DATA = [==[return {
  OWNER = "Murillopip",
  PROTOCOL = "BLUMA",

  GROQ_KEY = "__GROQ_KEY__",
  GROQ_MODEL = "openai/gpt-oss-20b",

  HEARTBEAT_TIMEOUT = 7,
  MINER_ID = "MINER-01",
  CRAFTER_ID = "CRAFT-01",

  VOICE_ENABLED = __VOICE_ENABLED__,
  FISH_API_KEY = "__FISH_KEY__",
  FISH_MODEL = "s2.1-pro-free",
  FISH_REFERENCE_ID = "__FISH_REFERENCE_ID__",
  FISH_SPEED = 1.0,
  TTS_VOLUME = 1.5,
  TTS_MAX_CHARS = 260
}
]==]
local CORE_DATA = [==[-- BLUMA CONTROL CENTER V5.1
-- CC:Tweaked + Advanced Peripherals
-- Core, HUD, Groq, Rednet control and optional Fish Audio voice through Speaker.

local VERSION = "5.1.0"
local PROGRAM = shell.getRunningProgram()
local ROOT = fs.getDir(PROGRAM)
local cfg = dofile(fs.combine(ROOT, "config.lua"))
local startedAt = os.epoch("utc")

local function lower(v) return string.lower(tostring(v or "")) end
local function trim(v) return (tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function contains(a, b) return string.find(lower(a), lower(b), 1, true) ~= nil end
local function isOwner(name) return lower(trim(name)) == lower(trim(cfg.OWNER)) end
local function now() return os.epoch("utc") / 1000 end
local function clamp(v, a, b) if v < a then return a elseif v > b then return b else return v end end
local function copyTable(t)
  local out = {}
  for k, v in pairs(t or {}) do
    if type(v) == "table" then out[k] = copyTable(v) else out[k] = v end
  end
  return out
end

local accents = {
  ["á"]="a",["à"]="a",["ã"]="a",["â"]="a",["ä"]="a",
  ["é"]="e",["ê"]="e",["ë"]="e",["í"]="i",["ï"]="i",
  ["ó"]="o",["õ"]="o",["ô"]="o",["ö"]="o",["ú"]="u",["ü"]="u",["ç"]="c",
  ["Á"]="A",["À"]="A",["Ã"]="A",["Â"]="A",["É"]="E",["Ê"]="E",
  ["Í"]="I",["Ó"]="O",["Õ"]="O",["Ô"]="O",["Ú"]="U",["Ç"]="C"
}
local function ascii(s)
  s = tostring(s or "")
  for a, b in pairs(accents) do s = s:gsub(a, b) end
  return s:gsub("[^%c%g ]", "?")
end

local function findWirelessModem()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      local p = peripheral.wrap(name)
      if p and p.isWireless then
        local ok, res = pcall(p.isWireless)
        if ok and res then return p, name end
      end
    end
  end
  return nil, nil
end

local function findByType(typeName)
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n) == typeName then return peripheral.wrap(n), n end
  end
  return nil, nil
end

local function findChatBox()
  for _, n in ipairs(peripheral.getNames()) do
    local ty = peripheral.getType(n)
    if ty == "chatBox" or ty == "chat_box" then return peripheral.wrap(n), n end
  end
  for _, n in ipairs(peripheral.getNames()) do
    local methods = peripheral.getMethods(n) or {}
    local hasSend = false
    for _, m in ipairs(methods) do
      if m == "sendMessage" or m == "sendMessageToPlayer" then hasSend = true; break end
    end
    if hasSend then return peripheral.wrap(n), n end
  end
  return nil, nil
end

local monitor, monitorName = findByType("monitor")
local chatBox, chatName = findChatBox()
local speaker, speakerName = findByType("speaker")
local modem, modemName = findWirelessModem()

if not monitor then error("BLUMA: Advanced Monitor nao encontrado.") end
if not modem then error("BLUMA: Wireless Modem nao encontrado.") end
if not rednet.isOpen(modemName) then rednet.open(modemName) end
pcall(function() monitor.setTextScale(0.5) end)

local machines = {}
local pending = {}
local reqCounter = 0
local logs = {}
local activePage = "HOME"
local buttons = {}
local lastResponse = "BLUMA inicializada."
local lastSpeaker = "SYSTEM"
local voiceQueue = {}
local voiceBusy = false
local voiceLastError = ""

local defaultMinerCfg = {
  width = 64, length = 64, depth = 64,
  unloadAt = 14, autoUnload = true, returnWhenFull = true,
  resumeAfterUnload = true, fuelReserve = 500, autoRefuel = true,
  returnWhenDone = true, pauseIfBlocked = true
}
local remoteMinerCfg = copyTable(defaultMinerCfg)
local minerCfg = copyTable(defaultMinerCfg) -- editable draft
local configDirty = false
local configSyncStatus = "WAITING MINER"

local function addLog(text)
  local t = os.date("%H:%M:%S")
  logs[#logs + 1] = t .. "  " .. ascii(text)
  while #logs > 100 do table.remove(logs, 1) end
end

local function tryCall(fn)
  local ok, a, b = pcall(fn)
  if not ok then return false, tostring(a) end
  if a == nil or a == false then return false, tostring(b or "send failed") end
  return true, nil
end

local function sendPublic(text)
  if not chatBox then return false, "Chat Box nao encontrada." end
  local utf = tostring(text or "")
  local plain = ascii(utf)
  local tries = {
    function() return chatBox.sendMessage(utf, "BLUMA", "[]", "&b", nil, true) end,
    function() return chatBox.sendMessage(plain, "BLUMA", "[]", "&b") end,
    function() return chatBox.sendMessage(plain, "BLUMA") end,
    function() return chatBox.sendMessage(plain) end
  }
  local last
  for _, fn in ipairs(tries) do
    local ok, err = tryCall(fn)
    if ok then return true end
    last = err
  end
  return false, last
end

local function sendPrivate(user, text)
  if not chatBox then return false, "Chat Box nao encontrada." end
  local utf = tostring(text or "")
  local plain = ascii(utf)
  local tries = {
    function() return chatBox.sendMessageToPlayer(utf, user, "BLUMA", "[]", "&b", nil, true) end,
    function() return chatBox.sendMessageToPlayer(plain, user, "BLUMA", "[]", "&b") end,
    function() return chatBox.sendMessageToPlayer(plain, user, "BLUMA") end,
    function() return chatBox.sendMessageToPlayer(plain, user) end
  }
  local last
  for _, fn in ipairs(tries) do
    local ok, err = tryCall(fn)
    if ok then return true end
    last = err
  end
  return false, last
end

local function online(id)
  local m = machines[id]
  return m and (now() - (m.lastSeen or 0) <= (cfg.HEARTBEAT_TIMEOUT or 7))
end

local function machineLine(id)
  local m = machines[id]
  if not online(id) then return id .. " OFFLINE" end
  local line = id .. " " .. tostring(m.state or "ONLINE")
  if m.progress ~= nil then line = line .. " " .. tostring(m.progress) .. "%" end
  if m.fuel ~= nil then line = line .. " fuel=" .. tostring(m.fuel) end
  if m.reason and m.reason ~= "" then line = line .. " reason=" .. tostring(m.reason) end
  return line
end

local function nextReq()
  reqCounter = reqCounter + 1
  return tostring(os.getComputerID()) .. "-" .. tostring(os.epoch("utc")) .. "-" .. reqCounter
end

local function sendWait(id, packet, timeout)
  local m = machines[id]
  if not online(id) or not m.sender then return false, id .. " esta offline.", nil end
  local req = nextReq()
  packet.requestId = req
  packet.id = id
  pending[req] = false
  rednet.send(m.sender, packet, cfg.PROTOCOL)
  local deadline = now() + (timeout or 5)
  while now() < deadline do
    local result = pending[req]
    if type(result) == "table" then
      pending[req] = nil
      return result.ok ~= false, result.message or "OK", result
    end
    sleep(0.05)
  end
  pending[req] = nil
  return false, "Sem confirmacao de " .. id .. ".", nil
end

local function command(id, action)
  addLog(cfg.OWNER .. " -> " .. id .. " " .. action)
  local ok, msg, packet = sendWait(id, {type = "COMMAND", action = action}, 6)
  addLog(id .. " -> " .. tostring(msg))
  if packet and id == cfg.MINER_ID and type(packet.config) == "table" then
    remoteMinerCfg = copyTable(packet.config)
    if not configDirty then minerCfg = copyTable(remoteMinerCfg) end
  end
  return ok, msg
end

local function saveMinerConfig()
  configSyncStatus = "SENDING..."
  local ok, msg, packet = sendWait(cfg.MINER_ID, {type = "CONFIG", config = copyTable(minerCfg)}, 6)
  if ok then
    if packet and type(packet.config) == "table" then remoteMinerCfg = copyTable(packet.config)
    else remoteMinerCfg = copyTable(minerCfg) end
    minerCfg = copyTable(remoteMinerCfg)
    configDirty = false
    configSyncStatus = "SYNCED"
  else
    configSyncStatus = "SAVE FAILED"
  end
  addLog("CONFIG -> " .. tostring(msg))
  return ok, msg
end

local function discover()
  rednet.broadcast({type = "DISCOVER", from = "BLUMA-CORE", version = VERSION}, cfg.PROTOCOL)
  addLog("Discovery broadcast enviado")
end

local function machineRelated(message)
  local words = {"miner", "mineradora", "mining", "turtle", "craft", "crafter", "crafting", "fuel", "combust", "invent", "slot", "maquina", "machine"}
  for _, w in ipairs(words) do if contains(message, w) then return true end end
  return false
end

local function groq(user, message, withTelemetry)
  if not http then return nil, "HTTP API indisponivel." end
  if not cfg.GROQ_KEY or cfg.GROQ_KEY == "" or cfg.GROQ_KEY == "SUA_CHAVE_GROQ_AQUI" then return nil, "Groq API key ausente." end

  local system = [[You are BLUMA, a calm, capable secretary and operations assistant inside Minecraft.
Answer naturally in the user's language. Portuguese from Brazil should sound natural and conversational.
Do not mention machines, mining, telemetry, or offline status unless the user asks about them or it is directly relevant.
Never invent machine state, telemetry, or command success. If telemetry is absent, say it is unavailable.
Keep routine answers concise enough to be spoken aloud.]]
  if withTelemetry then
    system = system .. "\nAuthoritative machine telemetry:\n" .. machineLine(cfg.MINER_ID) .. "\n" .. machineLine(cfg.CRAFTER_ID)
  end

  local payload = textutils.serializeJSON({
    model = cfg.GROQ_MODEL,
    temperature = 0.45,
    max_tokens = 300,
    messages = {{role = "system", content = system}, {role = "user", content = message}}
  })

  local response, err, errResp = http.post(
    "https://api.groq.com/openai/v1/chat/completions",
    payload,
    {["Authorization"] = "Bearer " .. cfg.GROQ_KEY, ["Content-Type"] = "application/json"}
  )
  if not response then
    local detail = tostring(err or "HTTP failure")
    if errResp then
      local ok, extra = pcall(function() return errResp.readAll() end)
      pcall(function() errResp.close() end)
      if ok and extra and extra ~= "" then detail = detail .. " | " .. extra end
    end
    return nil, detail
  end
  local raw = response.readAll(); response.close()
  local data = textutils.unserializeJSON(raw)
  local c = data and data.choices and data.choices[1]
  c = c and c.message and c.message.content
  if not c then return nil, "Resposta invalida da Groq." end
  return trim(c), nil
end

local function voiceAvailable()
  return speaker ~= nil and cfg.VOICE_ENABLED == true and cfg.FISH_API_KEY and cfg.FISH_API_KEY ~= ""
end

local function cleanSpeech(text)
  local s = tostring(text or "")
  s = s:gsub("```.-```", " ")
  s = s:gsub("`", "")
  s = s:gsub("%*%*", "")
  s = s:gsub("[_#>]", " ")
  s = s:gsub("%s+", " ")
  s = trim(s)
  local maxChars = tonumber(cfg.TTS_MAX_CHARS) or 260
  if #s > maxChars then s = s:sub(1, maxChars) .. "." end
  return s
end

local function queueVoice(text)
  if not voiceAvailable() then return end
  local s = cleanSpeech(text)
  if s == "" then return end
  voiceQueue[#voiceQueue + 1] = s
  while #voiceQueue > 4 do table.remove(voiceQueue, 1) end
  os.queueEvent("bluma_voice_wake")
end

local function u16le(raw, pos)
  local a, b = raw:byte(pos, pos + 1)
  if not a or not b then return nil end
  return a + b * 256
end

local function u32le(raw, pos)
  local a, b, c, d = raw:byte(pos, pos + 3)
  if not a or not b or not c or not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function parseWav(raw)
  if type(raw) ~= "string" or #raw < 44 then return nil, "WAV muito curto." end
  if raw:sub(1, 4) ~= "RIFF" or raw:sub(9, 12) ~= "WAVE" then return nil, "Resposta TTS nao e WAV RIFF." end

  local pos = 13
  local fmt, dataStart, dataSize
  while pos + 7 <= #raw do
    local id = raw:sub(pos, pos + 3)
    local size = u32le(raw, pos + 4)
    if not size then break end
    local chunkStart = pos + 8
    if id == "fmt " and size >= 16 then
      fmt = {
        audioFormat = u16le(raw, chunkStart),
        channels = u16le(raw, chunkStart + 2),
        sampleRate = u32le(raw, chunkStart + 4),
        blockAlign = u16le(raw, chunkStart + 12),
        bits = u16le(raw, chunkStart + 14)
      }
    elseif id == "data" then
      dataStart = chunkStart
      dataSize = math.min(size, #raw - chunkStart + 1)
      break
    end
    pos = chunkStart + size + (size % 2)
  end

  if not fmt or not dataStart or not dataSize then return nil, "WAV sem fmt/data." end
  if fmt.audioFormat ~= 1 then return nil, "WAV TTS nao-PCM (format " .. tostring(fmt.audioFormat) .. ")." end
  if fmt.channels ~= 1 and fmt.channels ~= 2 then return nil, "Canais WAV nao suportados: " .. tostring(fmt.channels) end
  if fmt.bits ~= 8 and fmt.bits ~= 16 then return nil, "Bits WAV nao suportados: " .. tostring(fmt.bits) end
  if not fmt.blockAlign or fmt.blockAlign <= 0 or not fmt.sampleRate or fmt.sampleRate <= 0 then return nil, "Cabecalho WAV invalido." end

  fmt.dataStart = dataStart
  fmt.dataSize = dataSize
  return fmt, nil
end

local function sampleAt(raw, fmt, frame)
  local bytesPerSample = fmt.bits / 8
  local base = fmt.dataStart + frame * fmt.blockAlign
  local sum = 0
  for ch = 0, fmt.channels - 1 do
    local p = base + ch * bytesPerSample
    if fmt.bits == 16 then
      local lo, hi = raw:byte(p, p + 1)
      if not lo or not hi then return 0 end
      local v = lo + hi * 256
      if v >= 32768 then v = v - 65536 end
      sum = sum + math.floor(v / 256)
    else
      local v = raw:byte(p)
      if not v then return 0 end
      sum = sum + (v - 128)
    end
  end
  return math.floor(sum / fmt.channels)
end

local function playWav(raw)
  if not speaker then return false, "Speaker nao encontrado." end
  local fmt, err = parseWav(raw)
  if not fmt then return false, err end

  local frames = math.floor(fmt.dataSize / fmt.blockAlign)
  local outFrames = math.floor(frames * 48000 / fmt.sampleRate)
  local outIndex = 0
  local volume = tonumber(cfg.TTS_VOLUME) or 1.5

  while outIndex < outFrames do
    local count = math.min(12000, outFrames - outIndex)
    local buf = {}
    for i = 1, count do
      local src = math.floor((outIndex + i - 1) * fmt.sampleRate / 48000)
      if src >= frames then src = frames - 1 end
      buf[i] = sampleAt(raw, fmt, src)
    end
    while not speaker.playAudio(buf, volume) do os.pullEvent("speaker_audio_empty") end
    outIndex = outIndex + count
  end
  return true
end

local function fishSpeak(text)
  if not voiceAvailable() then return false, "Voice disabled or not configured." end
  if not http then return false, "HTTP API indisponivel." end

  local body = {text = text, format = "wav"}
  if cfg.FISH_REFERENCE_ID and cfg.FISH_REFERENCE_ID ~= "" then body.reference_id = cfg.FISH_REFERENCE_ID end
  -- Keep the default request minimal and documented. Only send optional speed control
  -- when the operator explicitly changes it away from 1.0.
  local speed = tonumber(cfg.FISH_SPEED)
  if speed and math.abs(speed - 1.0) > 0.001 then body.prosody = {speed = speed} end

  local headers = {
    ["Authorization"] = "Bearer " .. cfg.FISH_API_KEY,
    ["Content-Type"] = "application/json",
    ["model"] = cfg.FISH_MODEL or "s2.1-pro-free"
  }

  local response, err, errResp = http.post("https://api.fish.audio/v1/tts", textutils.serializeJSON(body), headers, true)
  if not response then
    local detail = tostring(err or "Fish TTS request failed")
    if errResp then
      local ok, extra = pcall(function() return errResp.readAll() end)
      pcall(function() errResp.close() end)
      if ok and extra and extra ~= "" then detail = detail .. " | " .. tostring(extra):sub(1, 180) end
    end
    return false, detail
  end

  local raw = response.readAll()
  response.close()
  if not raw or #raw == 0 then return false, "Fish retornou audio vazio." end
  return playWav(raw)
end

local function parseCommand(message)
  local m = lower(message)
  local miner = contains(m, "miner") or contains(m, "mineradora")
  local craft = contains(m, "craft") or contains(m, "crafter")
  if miner then
    if contains(m, "pausa") or contains(m, "pause") then return cfg.MINER_ID, "PAUSE" end
    if contains(m, "retoma") or contains(m, "resume") or contains(m, "continua") then return cfg.MINER_ID, "RESUME" end
    if contains(m, "descarrega") or contains(m, "unload") then return cfg.MINER_ID, "UNLOAD_NOW" end
    if contains(m, "volta") or contains(m, "retorna") or contains(m, "return") then return cfg.MINER_ID, "RETURN" end
    if contains(m, "aborta") or contains(m, "abort") or contains(m, "cancela") then return cfg.MINER_ID, "ABORT" end
    if contains(m, "reset") then return cfg.MINER_ID, "RESET" end
    if contains(m, "inicia") or contains(m, "start") or contains(m, "comeca") then return cfg.MINER_ID, "START" end
  end
  if craft then
    if contains(m, "pausa") or contains(m, "pause") then return cfg.CRAFTER_ID, "PAUSE" end
    if contains(m, "retoma") or contains(m, "resume") or contains(m, "continua") then return cfg.CRAFTER_ID, "RESUME" end
    if contains(m, "para") or contains(m, "stop") then return cfg.CRAFTER_ID, "STOP" end
    if contains(m, "inicia") or contains(m, "start") or contains(m, "comeca") then return cfg.CRAFTER_ID, "START" end
  end
  return nil, nil
end

local function deliver(user, text, private)
  lastResponse = tostring(text or "")
  if private then sendPrivate(user, lastResponse) else sendPublic(lastResponse) end
  queueVoice(lastResponse)
end

local function processChat(user, message)
  if not contains(message, "bluma") then return end
  lastSpeaker = user
  addLog(user .. " -> BLUMA: " .. message)

  local related = machineRelated(message)
  if related and not isOwner(user) then
    deliver(user, "Essa parte do sistema e restrita ao operador.", true)
    return
  end

  local id, action = parseCommand(message)
  if id and action then
    local ok, msg = command(id, action)
    deliver(user, msg, true)
    return
  end

  if related and isOwner(user) and (contains(message, "status") or contains(message, "como esta") or contains(message, "como ta")) then
    deliver(user, machineLine(cfg.MINER_ID) .. " | " .. machineLine(cfg.CRAFTER_ID), true)
    return
  end

  local answer, err = groq(user, message, related)
  deliver(user, answer or ("Falha no nucleo de linguagem: " .. tostring(err)), related)
end

local function wrap(text, width)
  local out, line = {}, ""
  for word in ascii(text):gmatch("%S+") do
    if line == "" then line = word
    elseif #line + #word + 1 <= width then line = line .. " " .. word
    else out[#out + 1] = line; line = word end
  end
  if line ~= "" then out[#out + 1] = line end
  return out
end

local function txt(x, y, s, fg, bg)
  local w, h = monitor.getSize()
  if x < 1 or y < 1 or x > w or y > h then return end
  monitor.setCursorPos(x, y)
  monitor.setTextColor(fg or colors.white)
  monitor.setBackgroundColor(bg or colors.black)
  s = tostring(s or "")
  if #s > w - x + 1 then s = s:sub(1, w - x + 1) end
  monitor.write(s)
end

local function fill(x, y, w, h, bg)
  local mw, mh = monitor.getSize()
  local line = string.rep(" ", math.max(0, math.min(w, mw - x + 1)))
  for yy = y, math.min(y + h - 1, mh) do txt(x, yy, line, colors.white, bg) end
end

local function button(x, y, w, label, bg, action, enabled)
  local mw, mh = monitor.getSize()
  if y > mh or x > mw then return end
  local ww = math.min(w, mw - x + 1)
  if ww < 3 then return end
  if enabled == false then bg = colors.gray end
  fill(x, y, ww, 1, bg)
  local label2 = " " .. label .. " "
  local sx = x + math.max(0, math.floor((ww - #label2) / 2))
  txt(sx, y, label2, enabled == false and colors.lightGray or colors.white, bg)
  if enabled ~= false then buttons[#buttons + 1] = {x1 = x, y1 = y, x2 = x + ww - 1, y2 = y, action = action} end
end

local function bar(x, y, w, pct, color)
  pct = clamp(tonumber(pct) or 0, 0, 100)
  fill(x, y, w, 1, colors.gray)
  local on = math.floor(w * pct / 100)
  if on > 0 then fill(x, y, on, 1, color or colors.cyan) end
end

local function stateColor(state)
  state = string.upper(tostring(state or ""))
  if state == "MINING" or state == "CRAFTING" or state == "ONLINE" then return colors.lime end
  if state == "PAUSED" or state == "RETURNED" or state == "FULL" or state == "STANDBY" then return colors.orange end
  if state == "OFFLINE" or state == "ERROR" or state == "BLOCKED" or state == "LOW_FUEL" or state == "NO_FUEL" then return colors.red end
  return colors.lightBlue
end

local function drawHeader(title)
  local w = monitor.getSize()
  fill(1, 1, w, 3, colors.black)
  txt(2, 1, "BLUMA // " .. title, colors.cyan, colors.black)
  txt(math.max(2, w - 17), 1, "CORE " .. VERSION, colors.lime, colors.black)
  txt(2, 2, "SECRETARY & OPERATIONS CONTROL", colors.gray, colors.black)
  fill(1, 3, w, 1, colors.cyan)
end

local function drawNav()
  local w, h = monitor.getSize()
  local labels = {{"HOME", "PAGE_HOME"}, {"MINER", "PAGE_MINER"}, {"CONFIG", "PAGE_CONFIG"}, {"SYSTEM", "PAGE_SYSTEM"}, {"LOG", "PAGE_LOG"}}
  local bw = math.max(8, math.floor((w - 2) / #labels))
  local x = 1
  for _, item in ipairs(labels) do
    local bg = (activePage == item[1]) and colors.blue or colors.gray
    button(x, h, bw, item[1], bg, item[2])
    x = x + bw
  end
end

local function machineCard(x, y, w, id)
  fill(x, y, w, 6, colors.black)
  txt(x + 1, y, id, colors.cyan, colors.black)
  local m = machines[id]
  if not online(id) then
    txt(x + 1, y + 1, "OFFLINE", colors.red, colors.black)
    txt(x + 1, y + 2, "Waiting for heartbeat", colors.gray, colors.black)
    return
  end
  txt(x + 1, y + 1, tostring(m.state or "ONLINE"), stateColor(m.state), colors.black)
  if id == cfg.MINER_ID then
    txt(x + 1, y + 2, "Progress  " .. tostring(m.progress or 0) .. "%", colors.white, colors.black)
    bar(x + 1, y + 3, w - 2, m.progress or 0, colors.cyan)
    txt(x + 1, y + 4, "Fuel " .. tostring(m.fuel or "?") .. "  Slots " .. tostring(m.usedSlots or "?") .. "/16", colors.gray, colors.black)
    if m.reason and m.reason ~= "" then txt(x + 1, y + 5, m.reason, stateColor(m.state), colors.black) end
  else
    txt(x + 1, y + 2, "Crafted  " .. tostring(m.crafted or 0), colors.white, colors.black)
    txt(x + 1, y + 3, "Recipe   " .. tostring(m.recipe or "DEEPSLATE_BRICKS"), colors.gray, colors.black)
  end
end

local function drawHome()
  drawHeader("CONTROL CENTER")
  local w = monitor.getSize()
  txt(2, 5, "SYSTEM", colors.cyan, colors.black)
  txt(2, 7, "GROQ", colors.gray, colors.black); txt(14, 7, http and "READY" or "MISSING", http and colors.lime or colors.red, colors.black)
  txt(2, 8, "REDNET", colors.gray, colors.black); txt(14, 8, modemName or "MISSING", modemName and colors.lime or colors.red, colors.black)
  txt(2, 9, "CHAT", colors.gray, colors.black); txt(14, 9, chatName or "MISSING", chatName and colors.lime or colors.red, colors.black)
  txt(2, 10, "VOICE", colors.gray, colors.black)
  local voiceState = voiceAvailable() and (voiceBusy and "SPEAKING" or "READY") or (speakerName and "NO KEY/OFF" or "NO SPEAKER")
  txt(14, 10, voiceState, voiceAvailable() and colors.lime or colors.orange, colors.black)

  local cardX = math.max(27, math.floor(w * 0.42))
  machineCard(cardX, 5, w - cardX, cfg.MINER_ID)
  machineCard(cardX, 12, w - cardX, cfg.CRAFTER_ID)

  txt(2, 13, "LAST RESPONSE", colors.cyan, colors.black)
  local lines = wrap(lastResponse, math.max(18, cardX - 5))
  for i = 1, math.min(#lines, 5) do txt(2, 13 + i, lines[i], colors.white, colors.black) end

  txt(2, 20, "ACTIVITY", colors.cyan, colors.black)
  local start = math.max(1, #logs - 4)
  local yy = 21
  for i = start, #logs do txt(2, yy, logs[i], colors.gray, colors.black); yy = yy + 1 end
  drawNav()
end

local function drawMiner()
  drawHeader("MINER-01")
  local w = monitor.getSize()
  local m = machines[cfg.MINER_ID]
  local state = online(cfg.MINER_ID) and tostring(m.state or "ONLINE") or "OFFLINE"
  txt(2, 5, "STATE", colors.gray, colors.black); txt(14, 5, state, stateColor(state), colors.black)
  if online(cfg.MINER_ID) then
    txt(2, 7, "JOB", colors.gray, colors.black); txt(14, 7, tostring(m.width or "?") .. " x " .. tostring(m.length or "?") .. " x " .. tostring(m.depth or "?"), colors.white, colors.black)
    txt(2, 8, "PROGRESS", colors.gray, colors.black); txt(14, 8, tostring(m.progress or 0) .. "%", colors.white, colors.black)
    bar(2, 10, math.max(10, w - 4), m.progress or 0, colors.cyan)
    txt(2, 12, "POSITION", colors.gray, colors.black); txt(14, 12, "X " .. tostring(m.x or "?") .. "  Y " .. tostring(m.y or "?") .. "  Z " .. tostring(m.z or "?"), colors.white, colors.black)
    txt(2, 13, "CELL", colors.gray, colors.black); txt(14, 13, "L" .. tostring((m.layer or 0) + 1) .. " R" .. tostring((m.row or 0) + 1) .. " C" .. tostring((m.col or 0) + 1), colors.white, colors.black)
    txt(2, 14, "FUEL", colors.gray, colors.black); txt(14, 14, tostring(m.fuel or "?") .. "  reserve=" .. tostring((m.config and m.config.fuelReserve) or "?"), colors.white, colors.black)
    txt(2, 15, "STORAGE", colors.gray, colors.black); txt(14, 15, tostring(m.usedSlots or "?") .. " / 16", colors.white, colors.black)
    txt(2, 16, "BLOCKS", colors.gray, colors.black); txt(14, 16, tostring(m.blocks or 0), colors.white, colors.black)
    if m.reason and m.reason ~= "" then txt(2, 17, "INFO  " .. tostring(m.reason), stateColor(m.state), colors.black) end
  else
    txt(2, 7, "MINER-01 is not sending heartbeat.", colors.red, colors.black)
    txt(2, 8, "Run BLUMA V5.1 on the Mining Turtle.", colors.gray, colors.black)
  end
  local y = 19
  button(2, y, 9, "START", colors.green, "MINER_START")
  button(12, y, 9, "PAUSE", colors.orange, "MINER_PAUSE")
  button(22, y, 9, "RESUME", colors.blue, "MINER_RESUME")
  button(32, y, 10, "RETURN", colors.purple, "MINER_RETURN")
  button(43, y, 9, "ABORT", colors.red, "MINER_ABORT")
  button(53, y, 8, "RESET", colors.gray, "MINER_RESET")
  button(2, y + 2, 14, "UNLOAD NOW", colors.lightBlue, "MINER_UNLOAD")
  button(18, y + 2, 14, "DISCOVER", colors.lightBlue, "DISCOVER")
  drawNav()
end

local function cfgRow(y, label, value, minus, plus)
  txt(2, y, label, colors.gray, colors.black)
  button(25, y, 5, "-", colors.gray, minus)
  txt(32, y, tostring(value), colors.white, colors.black)
  button(43, y, 5, "+", colors.gray, plus)
end

local function toggleRow(y, label, value, action)
  txt(2, y, label, colors.gray, colors.black)
  button(25, y, 12, value and "ON" or "OFF", value and colors.green or colors.red, action)
end

local function drawConfig()
  drawHeader("MINER CONFIG")
  txt(2, 5, "JOB GEOMETRY", colors.cyan, colors.black)
  txt(50, 5, configDirty and "UNSAVED" or configSyncStatus, configDirty and colors.orange or colors.lime, colors.black)
  cfgRow(7, "Width", minerCfg.width, "CFG_W_MINUS", "CFG_W_PLUS")
  cfgRow(8, "Length", minerCfg.length, "CFG_L_MINUS", "CFG_L_PLUS")
  cfgRow(9, "Depth", minerCfg.depth, "CFG_D_MINUS", "CFG_D_PLUS")
  txt(2, 11, "STORAGE & SAFETY", colors.cyan, colors.black)
  cfgRow(13, "Unload at slots", minerCfg.unloadAt, "CFG_U_MINUS", "CFG_U_PLUS")
  cfgRow(14, "Fuel reserve", minerCfg.fuelReserve, "CFG_F_MINUS", "CFG_F_PLUS")
  toggleRow(16, "Auto unload", minerCfg.autoUnload, "CFG_AUTO_UNLOAD")
  toggleRow(17, "Auto refuel", minerCfg.autoRefuel, "CFG_AUTO_REFUEL")
  toggleRow(18, "Return when full", minerCfg.returnWhenFull, "CFG_RETURN_FULL")
  toggleRow(19, "Resume after unload", minerCfg.resumeAfterUnload, "CFG_RESUME_UNLOAD")
  toggleRow(20, "Return when done", minerCfg.returnWhenDone, "CFG_RETURN_DONE")
  toggleRow(21, "Pause if blocked", minerCfg.pauseIfBlocked, "CFG_PAUSE_BLOCKED")
  button(2, 23, 16, "SAVE CONFIG", colors.blue, "CFG_SAVE")
  button(20, 23, 16, "SAVE + START", colors.green, "CFG_START")
  drawNav()
end

local function drawSystem()
  drawHeader("SYSTEM")
  local uptime = math.floor((os.epoch("utc") - startedAt) / 1000)
  txt(2, 5, "CORE", colors.cyan, colors.black)
  txt(2, 7, "Uptime", colors.gray, colors.black); txt(18, 7, tostring(uptime) .. "s", colors.white, colors.black)
  txt(2, 8, "Computer ID", colors.gray, colors.black); txt(18, 8, tostring(os.getComputerID()), colors.white, colors.black)
  txt(2, 9, "Protocol", colors.gray, colors.black); txt(18, 9, cfg.PROTOCOL, colors.white, colors.black)
  txt(2, 10, "Version", colors.gray, colors.black); txt(18, 10, VERSION, colors.white, colors.black)
  txt(2, 12, "PERIPHERALS", colors.cyan, colors.black)
  txt(2, 14, "Monitor", colors.gray, colors.black); txt(18, 14, monitorName or "MISSING", monitorName and colors.lime or colors.red, colors.black)
  txt(2, 15, "Chat Box", colors.gray, colors.black); txt(18, 15, chatName or "MISSING", chatName and colors.lime or colors.red, colors.black)
  txt(2, 16, "Wireless Modem", colors.gray, colors.black); txt(18, 16, modemName or "MISSING", modemName and colors.lime or colors.red, colors.black)
  txt(2, 17, "Speaker", colors.gray, colors.black); txt(18, 17, speakerName or "MISSING", speakerName and colors.lime or colors.red, colors.black)
  txt(2, 18, "Fish TTS", colors.gray, colors.black); txt(18, 18, voiceAvailable() and "READY" or "OFF/NO KEY", voiceAvailable() and colors.lime or colors.orange, colors.black)
  if voiceLastError ~= "" then txt(35, 18, ascii(voiceLastError), colors.red, colors.black) end
  txt(2, 20, "MACHINES", colors.cyan, colors.black)
  txt(2, 21, cfg.MINER_ID, colors.gray, colors.black); txt(18, 21, online(cfg.MINER_ID) and "ONLINE" or "OFFLINE", online(cfg.MINER_ID) and colors.lime or colors.red, colors.black)
  txt(34, 21, cfg.CRAFTER_ID, colors.gray, colors.black); txt(50, 21, online(cfg.CRAFTER_ID) and "ONLINE" or "OFFLINE", online(cfg.CRAFTER_ID) and colors.lime or colors.red, colors.black)
  button(2, 23, 14, "DISCOVER", colors.lightBlue, "DISCOVER")
  button(18, 23, 14, "TEST VOICE", colors.purple, "VOICE_TEST", voiceAvailable())
  drawNav()
end

local function drawLog()
  drawHeader("EVENT LOG")
  local _, h = monitor.getSize()
  local maxRows = math.max(1, h - 5)
  local start = math.max(1, #logs - maxRows + 1)
  local y = 5
  for i = start, #logs do txt(2, y, logs[i], colors.gray, colors.black); y = y + 1 end
  drawNav()
end

local function redraw()
  buttons = {}
  monitor.setBackgroundColor(colors.black); monitor.clear()
  if activePage == "HOME" then drawHome()
  elseif activePage == "MINER" then drawMiner()
  elseif activePage == "CONFIG" then drawConfig()
  elseif activePage == "SYSTEM" then drawSystem()
  else drawLog() end
end

local function setResponse(msg)
  lastResponse = tostring(msg or "")
  redraw()
end

local function hit(x, y)
  for _, b in ipairs(buttons) do
    if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then return b.action end
  end
end

local function markDirty()
  configDirty = true
  configSyncStatus = "UNSAVED"
end

local function handleAction(a)
  if not a then return end
  if a:sub(1, 5) == "PAGE_" then activePage = a:sub(6); redraw(); return end
  if a == "DISCOVER" then discover(); setResponse("Buscando maquinas BLUMA..."); return end
  if a == "VOICE_TEST" then queueVoice("Bluma online. Sistema de voz funcionando."); setResponse("Teste de voz enviado."); return end
  if a == "MINER_START" then local _, m = command(cfg.MINER_ID, "START"); setResponse(m); queueVoice(m); return end
  if a == "MINER_PAUSE" then local _, m = command(cfg.MINER_ID, "PAUSE"); setResponse(m); queueVoice(m); return end
  if a == "MINER_RESUME" then local _, m = command(cfg.MINER_ID, "RESUME"); setResponse(m); queueVoice(m); return end
  if a == "MINER_RETURN" then local _, m = command(cfg.MINER_ID, "RETURN"); setResponse(m); queueVoice(m); return end
  if a == "MINER_ABORT" then local _, m = command(cfg.MINER_ID, "ABORT"); setResponse(m); queueVoice(m); return end
  if a == "MINER_RESET" then local _, m = command(cfg.MINER_ID, "RESET"); setResponse(m); queueVoice(m); return end
  if a == "MINER_UNLOAD" then local _, m = command(cfg.MINER_ID, "UNLOAD_NOW"); setResponse(m); queueVoice(m); return end

  if a == "CFG_W_MINUS" then minerCfg.width = clamp(minerCfg.width - 8, 1, 512); markDirty()
  elseif a == "CFG_W_PLUS" then minerCfg.width = clamp(minerCfg.width + 8, 1, 512); markDirty()
  elseif a == "CFG_L_MINUS" then minerCfg.length = clamp(minerCfg.length - 8, 1, 512); markDirty()
  elseif a == "CFG_L_PLUS" then minerCfg.length = clamp(minerCfg.length + 8, 1, 512); markDirty()
  elseif a == "CFG_D_MINUS" then minerCfg.depth = clamp(minerCfg.depth - 8, 1, 512); markDirty()
  elseif a == "CFG_D_PLUS" then minerCfg.depth = clamp(minerCfg.depth + 8, 1, 512); markDirty()
  elseif a == "CFG_U_MINUS" then minerCfg.unloadAt = clamp(minerCfg.unloadAt - 1, 4, 16); markDirty()
  elseif a == "CFG_U_PLUS" then minerCfg.unloadAt = clamp(minerCfg.unloadAt + 1, 4, 16); markDirty()
  elseif a == "CFG_F_MINUS" then minerCfg.fuelReserve = clamp(minerCfg.fuelReserve - 100, 0, 100000); markDirty()
  elseif a == "CFG_F_PLUS" then minerCfg.fuelReserve = clamp(minerCfg.fuelReserve + 100, 0, 100000); markDirty()
  elseif a == "CFG_AUTO_UNLOAD" then minerCfg.autoUnload = not minerCfg.autoUnload; markDirty()
  elseif a == "CFG_AUTO_REFUEL" then minerCfg.autoRefuel = not minerCfg.autoRefuel; markDirty()
  elseif a == "CFG_RETURN_FULL" then minerCfg.returnWhenFull = not minerCfg.returnWhenFull; markDirty()
  elseif a == "CFG_RESUME_UNLOAD" then minerCfg.resumeAfterUnload = not minerCfg.resumeAfterUnload; markDirty()
  elseif a == "CFG_RETURN_DONE" then minerCfg.returnWhenDone = not minerCfg.returnWhenDone; markDirty()
  elseif a == "CFG_PAUSE_BLOCKED" then minerCfg.pauseIfBlocked = not minerCfg.pauseIfBlocked; markDirty()
  elseif a == "CFG_SAVE" then
    local _, m = saveMinerConfig(); setResponse(m); return
  elseif a == "CFG_START" then
    local ok, m = saveMinerConfig()
    if ok then local _, m2 = command(cfg.MINER_ID, "START"); setResponse(m2); queueVoice(m2) else setResponse(m) end
    return
  end
  redraw()
end

local function mergeMachinePacket(sender, p)
  p.sender = sender
  p.lastSeen = now()
  machines[p.id] = p
  if p.id == cfg.MINER_ID and type(p.config) == "table" then
    remoteMinerCfg = copyTable(p.config)
    if not configDirty then
      minerCfg = copyTable(remoteMinerCfg)
      configSyncStatus = "SYNCED"
    end
  end
end

local function rednetLoop()
  while true do
    local _, sender, p, protocol = os.pullEvent("rednet_message")
    if protocol == cfg.PROTOCOL and type(p) == "table" then
      if p.type == "HELLO" or p.type == "HEARTBEAT" or p.type == "STATUS" then
        if p.id then
          mergeMachinePacket(sender, p)
          if p.type == "HELLO" then
            rednet.send(sender, {type = "WELCOME", from = "BLUMA-CORE", version = VERSION}, cfg.PROTOCOL)
            addLog(p.id .. " connected")
          elseif p.type == "STATUS" and p.message and p.message ~= "" then
            addLog(p.id .. " -> " .. tostring(p.message))
          end
        end
      elseif p.type == "ACK" and p.requestId then
        pending[p.requestId] = p
        if p.id then mergeMachinePacket(sender, p) end
      end
      redraw()
    end
  end
end

local function looksLikeUuid(v)
  if type(v) ~= "string" then return false end
  return v:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

local function decodeChatEvent(e)
  -- Advanced Peripherals 0.7 / MC 1.20.1:
  --   chat, username, message, uuid, hidden, messageUtf8
  -- Newer layouts may put uuid before username:
  --   chat, uuid, username, message, hidden, messageUtf8
  if looksLikeUuid(e[2]) then
    return tostring(e[3] or "player"), tostring(e[6] or e[4] or "")
  elseif looksLikeUuid(e[4]) then
    return tostring(e[2] or "player"), tostring(e[6] or e[3] or "")
  end

  -- Conservative fallback for custom/older Chat Box builds.
  if type(e[2]) == "string" and type(e[3]) == "string" then
    return e[2], tostring(e[6] or e[3])
  end
  return "player", tostring(e[6] or e[4] or e[3] or "")
end

local function chatLoop()
  while true do
    local e = {os.pullEvent("chat")}
    local user, message = decodeChatEvent(e)
    local ok, err = pcall(processChat, user, message)
    if not ok then
      addLog("Chat error: " .. tostring(err))
      sendPrivate(user, "BLUMA encontrou um erro interno: " .. tostring(err))
    end
    redraw()
  end
end

local function touchLoop()
  while true do
    local _, _, x, y = os.pullEvent("monitor_touch")
    local ok, err = pcall(handleAction, hit(x, y))
    if not ok then addLog("UI error: " .. tostring(err)); setResponse("Erro no painel: " .. tostring(err)) end
  end
end

local function voiceLoop()
  while true do
    if #voiceQueue == 0 then os.pullEvent("bluma_voice_wake") end
    while #voiceQueue > 0 do
      local text = table.remove(voiceQueue, 1)
      voiceBusy = true
      voiceLastError = ""
      redraw()
      local ok, err = pcall(function()
        local played, why = fishSpeak(text)
        if not played then error(why or "TTS failed") end
      end)
      if not ok then
        voiceLastError = tostring(err)
        addLog("Voice error: " .. voiceLastError)
      end
      voiceBusy = false
      redraw()
    end
  end
end

local function refreshLoop()
  while true do redraw(); sleep(0.5) end
end

addLog("BLUMA Core V" .. VERSION .. " online")
discover()
redraw()
sendPublic("BLUMA online.")
queueVoice("Bluma online.")
parallel.waitForAll(rednetLoop, chatLoop, touchLoop, voiceLoop, refreshLoop)

]==]
local MINER_DATA = [==[-- BLUMA MINER-01 V5.1
-- Advanced Mining Turtle + Wireless Modem
-- Persistent quarry with remote config, heartbeat, fuel preflight and real ACKs.

local PROTOCOL = "BLUMA"
local ID = "MINER-01"
local STATE_FILE = ".bluma_miner_state"
local CFG_FILE = ".bluma_miner_config"
local VERSION = "5.1.0"

local cfg = {
  width = 64,
  length = 64,
  depth = 64,
  unloadAt = 14,
  autoUnload = true,
  returnWhenFull = true,
  resumeAfterUnload = true,
  fuelReserve = 500,
  autoRefuel = true,
  returnWhenDone = true,
  pauseIfBlocked = true
}

local s = {
  state = "STANDBY",
  reason = "",
  x = 0, y = 0, z = 0, dir = 0,
  layer = 0, row = 0, col = 0,
  blocks = 0,
  entered = false,
  paused = false,
  abort = false,
  returnRequested = false,
  unloadRequested = false,
  resumeTarget = nil
}

local coreId = nil

local function readJSON(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  if not h then return nil end
  local raw = h.readAll()
  h.close()
  local ok, data = pcall(textutils.unserializeJSON, raw)
  if ok then return data end
  return nil
end

local function writeJSON(path, data)
  local h = fs.open(path, "w")
  if not h then return false end
  h.write(textutils.serializeJSON(data))
  h.close()
  return true
end

local oldCfg = readJSON(CFG_FILE)
if type(oldCfg) == "table" then
  for k, v in pairs(oldCfg) do
    if cfg[k] ~= nil then cfg[k] = v end
  end
end

local oldState = readJSON(STATE_FILE)
if type(oldState) == "table" then
  for k, v in pairs(oldState) do
    if s[k] ~= nil then s[k] = v end
  end
end

-- A reboot must never make the turtle move by itself.
if s.state == "MINING" or s.state == "RETURNING" or s.state == "UNLOADING" then
  s.state = "PAUSED"
  s.reason = "Reboot detected; waiting for RESUME."
  s.paused = true
end

-- Migrate the common broken V5 state shown when START was attempted with zero fuel.
if s.state == "BLOCKED" and not s.entered and s.x == 0 and s.y == 0 and s.z == 0 then
  s.state = "STANDBY"
  s.reason = ""
  s.paused = false
end

local function saveCfg() return writeJSON(CFG_FILE, cfg) end
local function saveState() return writeJSON(STATE_FILE, s) end
local function nowFuel() return turtle.getFuelLevel() end

local function usedSlots()
  local n = 0
  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then n = n + 1 end
  end
  return n
end

local function progress()
  if not s.entered then return 0 end
  local total = math.max(1, cfg.width * cfg.length * cfg.depth)
  local done = (s.layer * cfg.width * cfg.length) + (s.row * cfg.width) + s.col + 1
  done = math.max(0, math.min(total, done))
  return math.floor((done / total) * 1000) / 10
end

local function findWirelessModem()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      local m = peripheral.wrap(name)
      if m and m.isWireless then
        local ok, res = pcall(m.isWireless)
        if ok and res then return m, name end
      end
    end
  end
  return nil, nil
end

local modem, modemName = findWirelessModem()
if not modem then error("BLUMA MINER: Wireless Modem nao encontrado.") end
if not rednet.isOpen(modemName) then rednet.open(modemName) end

local function payload(tp, msg, req, ok)
  return {
    type = tp,
    id = ID,
    version = VERSION,
    state = s.state,
    reason = s.reason,
    progress = progress(),
    fuel = nowFuel(),
    usedSlots = usedSlots(),
    blocks = s.blocks,
    x = s.x, y = s.y, z = s.z, dir = s.dir,
    layer = s.layer, row = s.row, col = s.col,
    width = cfg.width, length = cfg.length, depth = cfg.depth,
    entered = s.entered,
    config = cfg,
    message = msg,
    requestId = req,
    ok = ok
  }
end

local function send(tp, msg, req, ok)
  local p = payload(tp, msg, req, ok)
  if coreId then rednet.send(coreId, p, PROTOCOL)
  else rednet.broadcast(p, PROTOCOL) end
end

local function setState(state, reason)
  s.state = state
  s.reason = reason or ""
  saveState()
end

local function turnRight()
  turtle.turnRight()
  s.dir = (s.dir + 1) % 4
  saveState()
end

local function turnLeft()
  turtle.turnLeft()
  s.dir = (s.dir + 3) % 4
  saveState()
end

local function face(d)
  local diff = (d - s.dir) % 4
  if diff == 1 then turnRight()
  elseif diff == 2 then turnRight(); turnRight()
  elseif diff == 3 then turnLeft() end
end

local function autoRefuelTo(target)
  local level = nowFuel()
  if level == "unlimited" then return true, level end
  target = math.max(1, math.floor(tonumber(target) or 1))
  if level >= target then return true, level end
  if not cfg.autoRefuel then return false, level end

  local selected = turtle.getSelectedSlot and turtle.getSelectedSlot() or 1
  for slot = 1, 16 do
    if level >= target then break end
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      local isFuel = turtle.refuel(0)
      if isFuel then
        -- Consume only what is needed, preserving as much fuel item stock as possible.
        while turtle.getItemCount(slot) > 0 and level < target do
          local ok = turtle.refuel(1)
          if not ok then break end
          level = nowFuel()
          if level == "unlimited" then break end
        end
      end
    end
  end
  turtle.select(selected)
  level = nowFuel()
  return level == "unlimited" or level >= target, level
end

local function fuelReady(minimum)
  local level = nowFuel()
  if level == "unlimited" then return true, level end
  local ok, after = autoRefuelTo(minimum)
  return ok, after
end

local function noFuel(reason)
  s.paused = true
  setState("NO_FUEL", reason or "Sem combustivel.")
  send("STATUS", s.reason)
end

local function blocked(reason)
  s.paused = true
  setState("BLOCKED", reason or "Caminho bloqueado.")
  send("STATUS", s.reason)
end

local function countDig(fn)
  local ok = fn()
  if ok then s.blocks = s.blocks + 1; saveState() end
  return ok
end

local function shouldInterruptMove()
  return s.paused or s.abort or s.returnRequested or s.unloadRequested
end

local function blockedCycle(reason)
  if cfg.pauseIfBlocked then
    blocked(reason)
    return false
  end
  setState("BLOCKED", reason .. " Retentando automaticamente...")
  send("STATUS", s.reason)
  sleep(1)
  return true
end

local function moveForward()
  local attempts = 0
  while true do
    if shouldInterruptMove() then return false end
    local fuel = nowFuel()
    if fuel ~= "unlimited" and fuel <= 0 then
      local ok = autoRefuelTo(math.max(1, cfg.fuelReserve))
      if not ok then noFuel("Sem combustivel para mover em frente."); return false end
    end

    local ok, err = turtle.forward()
    if ok then
      if s.dir == 0 then s.z = s.z - 1
      elseif s.dir == 1 then s.x = s.x + 1
      elseif s.dir == 2 then s.z = s.z + 1
      else s.x = s.x - 1 end
      if s.state == "BLOCKED" and not s.paused then s.state = "MINING"; s.reason = "" end
      saveState()
      return true
    end

    if turtle.detect() then countDig(turtle.dig) else turtle.attack() end
    attempts = attempts + 1
    sleep(0.08)
    if attempts >= 12 then
      local why = "Frente bloqueada: " .. tostring(err or "obstaculo impossivel de remover")
      if not blockedCycle(why) then return false end
      attempts = 0
    end
  end
end

local function moveUp()
  local attempts = 0
  while true do
    if shouldInterruptMove() then return false end
    local fuel = nowFuel()
    if fuel ~= "unlimited" and fuel <= 0 then
      local ok = autoRefuelTo(math.max(1, cfg.fuelReserve))
      if not ok then noFuel("Sem combustivel para subir."); return false end
    end

    local ok, err = turtle.up()
    if ok then
      s.y = s.y + 1
      if s.state == "BLOCKED" and not s.paused then s.state = "MINING"; s.reason = "" end
      saveState()
      return true
    end
    if turtle.detectUp() then countDig(turtle.digUp) else turtle.attackUp() end
    attempts = attempts + 1
    sleep(0.08)
    if attempts >= 12 then
      local why = "Acima bloqueado: " .. tostring(err or "obstaculo impossivel de remover")
      if not blockedCycle(why) then return false end
      attempts = 0
    end
  end
end

local function moveDown()
  local attempts = 0
  while true do
    if shouldInterruptMove() then return false end
    local fuel = nowFuel()
    if fuel ~= "unlimited" and fuel <= 0 then
      local ok = autoRefuelTo(math.max(1, cfg.fuelReserve))
      if not ok then noFuel("Sem combustivel para descer."); return false end
    end

    local ok, err = turtle.down()
    if ok then
      s.y = s.y - 1
      if s.state == "BLOCKED" and not s.paused then s.state = "MINING"; s.reason = "" end
      saveState()
      return true
    end
    if turtle.detectDown() then countDig(turtle.digDown) else turtle.attackDown() end
    attempts = attempts + 1
    sleep(0.08)
    if attempts >= 12 then
      local why = "Abaixo bloqueado: " .. tostring(err or "obstaculo impossivel de remover")
      if not blockedCycle(why) then return false end
      attempts = 0
    end
  end
end

local function moveX(target)
  if s.x < target then
    face(1)
    while s.x < target do if not moveForward() then return false end end
  elseif s.x > target then
    face(3)
    while s.x > target do if not moveForward() then return false end end
  end
  return true
end

local function moveZ(target)
  if s.z < target then
    face(2)
    while s.z < target do if not moveForward() then return false end end
  elseif s.z > target then
    face(0)
    while s.z > target do if not moveForward() then return false end end
  end
  return true
end

local function moveY(target)
  while s.y < target do if not moveUp() then return false end end
  while s.y > target do if not moveDown() then return false end end
  return true
end

local function atHome()
  return s.x == 0 and s.y == 0 and s.z == 0
end

-- Return through cells which are already part of the mined path whenever possible.
local function goHomeFromMining()
  if atHome() then face(0); return true end

  if s.entered then
    local startX = (s.row % 2 == 0) and 0 or (cfg.width - 1)
    if not moveX(startX) then return false end

    -- Same x/z was mined on every completed upper layer.
    if not moveY(0) then return false end

    -- Move back along completed row endpoints to the first quarry row.
    if not moveZ(-1) then return false end

    -- Row zero is complete unless we are still inside row zero, whose start is x=0.
    if not moveX(0) then return false end
    if not moveZ(0) then return false end
    face(0)
    return true
  end

  -- Before entering the quarry, HOME is the only valid known position.
  if not moveY(0) then return false end
  if not moveX(0) then return false end
  if not moveZ(0) then return false end
  face(0)
  return true
end

local function resumeToTarget(t)
  if type(t) ~= "table" then return false end
  if not atHome() then return false end

  face(0)
  if not t.entered then return true end

  -- Enter first quarry cell.
  if not moveZ(-1) then return false end

  -- Descend through the first cell of all previously completed layers.
  if not moveY(t.y) then return false end

  local startX = (t.row % 2 == 0) and 0 or (cfg.width - 1)
  if startX ~= 0 then
    -- Row zero is complete before any odd row can be active.
    if not moveX(startX) then return false end
  end

  if not moveZ(t.z) then return false end
  if not moveX(t.x) then return false end
  if t.dir ~= nil then face(t.dir) end
  return true
end

local function isFuelSlot(slot)
  if turtle.getItemCount(slot) <= 0 then return false end
  local selected = turtle.getSelectedSlot and turtle.getSelectedSlot() or 1
  turtle.select(slot)
  local ok, result = pcall(turtle.refuel, 0)
  turtle.select(selected)
  return ok and result == true
end

local function chooseFuelKeepSlot()
  if not cfg.autoRefuel then return nil end
  local best, bestCount = nil, -1
  for i = 1, 16 do
    local count = turtle.getItemCount(i)
    if count > bestCount and isFuelSlot(i) then
      best, bestCount = i, count
    end
  end
  return best
end

local function cargoSlots(keepFuel)
  local n = 0
  for i = 1, 16 do
    if i ~= keepFuel and turtle.getItemCount(i) > 0 then n = n + 1 end
  end
  return n
end

local function dropAllDown()
  -- Preserve one stack of valid fuel when auto-refuel is enabled.
  -- This prevents an unload cycle from throwing away the Turtle's only fuel stock.
  local selected = turtle.getSelectedSlot and turtle.getSelectedSlot() or 1
  local keepFuel = chooseFuelKeepSlot()
  local before = cargoSlots(keepFuel)
  for i = 1, 16 do
    if i ~= keepFuel and turtle.getItemCount(i) > 0 then
      turtle.select(i)
      turtle.dropDown()
    end
  end
  turtle.select(selected)
  local after = cargoSlots(keepFuel)
  return before - after, after
end

local function captureTarget()
  return {
    x = s.x, y = s.y, z = s.z, dir = s.dir,
    layer = s.layer, row = s.row, col = s.col,
    entered = s.entered
  }
end

local function restoreProgressFromTarget(t)
  if type(t) ~= "table" then return end
  s.layer = t.layer or s.layer
  s.row = t.row or s.row
  s.col = t.col or s.col
  s.entered = t.entered ~= false
end

local function unloadAndReturn()
  local target = captureTarget()
  target.unload = true
  local okFuel = fuelReady(math.max(cfg.fuelReserve, 1))
  if not okFuel then
    noFuel("Combustivel insuficiente para retorno de descarga.")
    return false
  end

  s.resumeTarget = target
  s.paused = false
  setState("UNLOADING", "Retornando para descarregar.")
  send("STATUS", s.reason)

  if not goHomeFromMining() then return false end

  local _, left = dropAllDown()
  if left > 0 then
    s.paused = true
    setState("FULL", "Bau abaixo de HOME ausente ou cheio.")
    send("STATUS", s.reason)
    return false
  end

  if not cfg.resumeAfterUnload then
    s.paused = true
    setState("RETURNED", "Descarga concluida; aguardando RESUME.")
    send("STATUS", s.reason)
    return false
  end

  local target2 = s.resumeTarget
  setState("RETURNING", "Voltando ao ponto salvo.")
  if not resumeToTarget(target2) then return false end
  restoreProgressFromTarget(target2)
  s.resumeTarget = nil
  s.paused = false
  setState("MINING", "Descarga concluida; mineracao retomada.")
  send("STATUS", s.reason)
  return true
end

local function serviceChecks()
  if s.abort then
    s.abort = false
    s.paused = false
    setState("ABORTED", "Job abortado; progresso preservado.")
    send("STATUS", s.reason)
    return false
  end

  if s.unloadRequested then
    s.unloadRequested = false
    return unloadAndReturn()
  end

  if s.returnRequested then
    s.resumeTarget = captureTarget()
    s.returnRequested = false
    s.paused = false
    setState("RETURNING", "Retorno solicitado.")
    if goHomeFromMining() then
      s.paused = true
      setState("RETURNED", "Em HOME; progresso preservado.")
      send("STATUS", s.reason)
    end
    return false
  end

  local fuel = nowFuel()
  if fuel ~= "unlimited" and fuel < cfg.fuelReserve then
    local ok, after = autoRefuelTo(cfg.fuelReserve)
    if not ok then
      s.paused = true
      setState("LOW_FUEL", "Combustivel abaixo da reserva: " .. tostring(after) .. "/" .. tostring(cfg.fuelReserve))
      send("STATUS", s.reason)
    end
  end

  while s.paused do
    os.pullEvent("bluma_miner_wake")
    if s.abort or s.returnRequested or s.unloadRequested then return serviceChecks() end
  end

  if cfg.autoUnload and usedSlots() >= cfg.unloadAt then
    if cfg.returnWhenFull then return unloadAndReturn() end
    s.paused = true
    setState("FULL", "Inventario atingiu o limite configurado.")
    send("STATUS", s.reason)
    return false
  end

  return true
end

local function resetJob()
  s.state = "STANDBY"
  s.reason = ""
  s.x = 0; s.y = 0; s.z = 0; s.dir = 0
  s.layer = 0; s.row = 0; s.col = 0
  s.blocks = 0; s.entered = false
  s.paused = false; s.abort = false; s.returnRequested = false; s.unloadRequested = false
  s.resumeTarget = nil
  saveState()
end

local function jobHasProgress()
  return s.entered or s.layer > 0 or s.row > 0 or s.col > 0 or not atHome()
end

local function activeJob()
  if not jobHasProgress() then return false end
  return s.state ~= "FINISHED" and s.state ~= "ABORTED" and s.state ~= "STANDBY"
end

local function sameGeometry(c)
  return c.width == cfg.width and c.length == cfg.length and c.depth == cfg.depth
end

local function validConfig(c)
  if type(c) ~= "table" then return false, "Config invalida." end
  local numeric = {"width", "length", "depth", "unloadAt", "fuelReserve"}
  for _, k in ipairs(numeric) do
    if type(c[k]) ~= "number" then return false, "Campo invalido: " .. k end
  end
  if c.width < 1 or c.width > 512 or c.length < 1 or c.length > 512 or c.depth < 1 or c.depth > 512 then
    return false, "Dimensoes devem ficar entre 1 e 512."
  end
  if c.unloadAt < 4 or c.unloadAt > 16 then return false, "unloadAt deve ficar entre 4 e 16." end
  if c.fuelReserve < 0 or c.fuelReserve > 100000 then return false, "fuelReserve invalido." end
  return true
end

local function applyConfig(c)
  for k, v in pairs(c) do
    if cfg[k] ~= nil then cfg[k] = v end
  end
  saveCfg()
end

local function startPreflight()
  if not atHome() and not s.entered and s.state == "STANDBY" then
    return false, "Posicao desconhecida: coloque a Turtle em HOME e use RESET."
  end

  local minimum = math.max(1, cfg.fuelReserve)
  local okFuel, level = fuelReady(minimum)
  if not okFuel then
    return false, "Combustivel insuficiente: " .. tostring(level) .. "/" .. tostring(minimum) .. ". Coloque combustivel no inventario ou reduza a reserva."
  end

  return true, "Preflight OK."
end

local function finishLayerAndGoToNext()
  -- Current layer is complete, so any route inside it is now safe.
  if not moveX(0) then return false end
  if not moveZ(-1) then return false end
  if not moveDown() then return false end
  s.layer = s.layer + 1
  s.row = 0
  s.col = 0
  face(1)
  saveState()
  return true
end

local function mineJob()
  -- A RETURN/unload keeps the exact mining target while coordinates move back to HOME.
  if atHome() and type(s.resumeTarget) == "table" and s.resumeTarget.entered then
    local t = s.resumeTarget
    if t.unload and usedSlots() > 0 then
      local _, left = dropAllDown()
      if left > 0 then
        s.paused = true
        setState("FULL", "Bau abaixo de HOME ausente ou cheio.")
        send("STATUS", s.reason)
        return
      end
    end
    setState("RETURNING", "Voltando ao ponto salvo.")
    if not resumeToTarget(t) then return end
    restoreProgressFromTarget(t)
    s.resumeTarget = nil
  elseif s.state == "RETURNED" then
    s.paused = true
    setState("PAUSED", "Sem ponto salvo para RESUME.")
    return
  end

  local ok, msg = startPreflight()
  if not ok then
    noFuel(msg)
    return
  end

  s.paused = false
  setState("MINING", "Mineracao em andamento.")
  send("STATUS", s.reason)

  if not s.entered then
    if not serviceChecks() then return end
    face(0)
    if not moveForward() then return end
    s.entered = true
    s.layer = 0; s.row = 0; s.col = 0
    face(1)
    saveState()
  end

  while s.layer < cfg.depth do
    while s.row < cfg.length do
      local expected = (s.row % 2 == 0) and 1 or 3
      face(expected)

      while s.col < cfg.width - 1 do
        if not serviceChecks() then return end
        if not moveForward() then return end
        s.col = s.col + 1
        saveState()
      end

      if not serviceChecks() then return end

      if s.row < cfg.length - 1 then
        face(0)
        if not moveForward() then return end
        s.row = s.row + 1
        s.col = 0
        face((s.row % 2 == 0) and 1 or 3)
        saveState()
      else
        break
      end
    end

    if s.layer < cfg.depth - 1 then
      if not finishLayerAndGoToNext() then return end
    else
      break
    end
  end

  if cfg.returnWhenDone then
    setState("RETURNING", "Job concluido; retornando a HOME.")
    if not goHomeFromMining() then return end
  end

  s.paused = false
  s.resumeTarget = nil
  setState("FINISHED", "Job concluido.")
  send("STATUS", s.reason)
end

local function handlePacket(sender, p)
  if type(p) ~= "table" then return end

  if p.type == "DISCOVER" then
    coreId = sender
    rednet.send(sender, payload("HELLO", "MINER-01 ready"), PROTOCOL)
    return
  end

  if p.type == "WELCOME" then coreId = sender; return end
  if p.id and p.id ~= ID then return end

  if p.type == "CONFIG" then
    coreId = sender
    local ok, msg = validConfig(p.config)
    if ok then
      if activeJob() and not sameGeometry(p.config) then
        ok = false
        msg = "Geometria bloqueada enquanto existe um job em andamento. RETURN/ABORT + RESET antes de mudar Width/Length/Depth."
      else
        applyConfig(p.config)
        msg = "CONFIG SYNCED em MINER-01."
      end
    end
    rednet.send(sender, payload("ACK", msg, p.requestId, ok), PROTOCOL)
    return
  end

  if p.type ~= "COMMAND" then return end
  coreId = sender

  local a = string.upper(tostring(p.action or ""))
  local ok = true
  local msg = "OK"

  if a == "START" then
    if s.state == "FINISHED" or s.state == "ABORTED" then
      if atHome() then resetJob()
      else ok = false; msg = "Use RETURN antes de iniciar outro job." end
    end

    if ok then
      local pre, why = startPreflight()
      if not pre then
        ok = false
        if nowFuel() == 0 then setState("NO_FUEL", why) else setState("LOW_FUEL", why) end
        msg = why
      elseif s.state == "STANDBY" then
        s.paused = false; s.reason = ""; saveState()
        os.queueEvent("bluma_miner_start")
        msg = "START aceito; preflight OK."
      elseif s.state == "RETURNED" then
        s.paused = false; s.reason = ""; saveState()
        os.queueEvent("bluma_miner_start")
        msg = "RESUME aceito; voltando ao ponto salvo."
      elseif s.state == "PAUSED" or s.state == "FULL" or s.state == "LOW_FUEL" or s.state == "NO_FUEL" or s.state == "BLOCKED" then
        s.paused = false; s.state = "MINING"; s.reason = ""; saveState()
        os.queueEvent("bluma_miner_wake")
        os.queueEvent("bluma_miner_start")
        msg = "RESUME aceito; preflight OK."
      elseif s.state == "MINING" or s.state == "RETURNING" or s.state == "UNLOADING" then
        msg = "MINER-01 ja esta ativa."
      else
        s.paused = false; saveState(); os.queueEvent("bluma_miner_start")
        msg = "START aceito."
      end
    end

  elseif a == "PAUSE" then
    s.paused = true
    setState("PAUSED", "Pausa solicitada pelo operador.")
    msg = "MINER-01 pausada."

  elseif a == "RESUME" then
    local pre, why = startPreflight()
    if not pre then
      ok = false; msg = why
    elseif s.state == "RETURNED" then
      s.paused = false; s.reason = ""; saveState()
      os.queueEvent("bluma_miner_start")
      msg = "Retornando ao ponto salvo."
    else
      s.paused = false; s.state = "MINING"; s.reason = ""; saveState()
      os.queueEvent("bluma_miner_wake")
      os.queueEvent("bluma_miner_start")
      msg = "MINER-01 retomada."
    end

  elseif a == "RETURN" then
    if atHome() then
      s.paused = true
      setState("RETURNED", "MINER-01 ja esta em HOME.")
      msg = "MINER-01 ja esta em HOME."
    else
      s.returnRequested = true; s.paused = false; saveState()
      os.queueEvent("bluma_miner_wake")
      msg = "Retorno solicitado."
    end

  elseif a == "ABORT" then
    s.abort = true; s.paused = false; saveState()
    os.queueEvent("bluma_miner_wake")
    msg = "Abort solicitado; progresso sera preservado."

  elseif a == "RESET" then
    if not atHome() then
      ok = false; msg = "MINER-01 precisa estar fisicamente em HOME para RESET."
    elseif s.state == "MINING" or s.state == "RETURNING" or s.state == "UNLOADING" then
      ok = false; msg = "Pause/RETURN antes de RESET."
    else
      resetJob(); msg = "Job e coordenadas resetados em HOME."
    end

  elseif a == "UNLOAD_NOW" then
    if not s.entered and atHome() then
      local _, left = dropAllDown()
      if left > 0 then ok = false; msg = "Bau abaixo de HOME ausente ou cheio."
      else msg = "Inventario descarregado." end
    else
      s.unloadRequested = true; s.paused = false; saveState()
      os.queueEvent("bluma_miner_wake")
      msg = "Retorno para descarga solicitado."
    end

  else
    ok = false; msg = "Comando desconhecido."
  end

  rednet.send(sender, payload("ACK", msg, p.requestId, ok), PROTOCOL)
end

local function networkLoop()
  local timer = os.startTimer(0.2)
  while true do
    local e = {os.pullEventRaw()}
    if e[1] == "rednet_message" and e[4] == PROTOCOL then
      handlePacket(e[2], e[3])
    elseif e[1] == "timer" and e[2] == timer then
      send("HEARTBEAT", "alive")
      timer = os.startTimer(2)
    elseif e[1] == "terminate" then
      s.paused = true
      setState("PAUSED", "Programa interrompido; aguardando reinicio.")
      return
    end
  end
end

local function minerLoop()
  while true do
    if s.state == "MINING" and not s.paused then
      mineJob()
    else
      local ev = os.pullEvent()
      if ev == "bluma_miner_start" then
        if not s.paused then mineJob() end
      elseif ev == "bluma_miner_wake" then
        if s.abort or s.returnRequested or s.unloadRequested then
          serviceChecks()
        elseif s.state == "MINING" and not s.paused then
          mineJob()
        end
      end
    end
  end
end

local function uiLoop()
  while true do
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan); print("BLUMA // MINER-01  V" .. VERSION)
    term.setTextColor(colors.white)
    print("STATE   " .. s.state)
    print("JOB     " .. cfg.width .. "x" .. cfg.length .. "x" .. cfg.depth)
    print("PROG    " .. progress() .. "%")
    print("POS     " .. s.x .. "," .. s.y .. "," .. s.z)
    print("CELL    L" .. (s.layer + 1) .. " R" .. (s.row + 1) .. " C" .. (s.col + 1))
    print("FUEL    " .. tostring(nowFuel()) .. "  reserve=" .. tostring(cfg.fuelReserve))
    print("SLOTS   " .. usedSlots() .. "/16")
    print("BLOCKS  " .. s.blocks)
    if s.reason and s.reason ~= "" then
      term.setTextColor((s.state == "BLOCKED" or s.state == "NO_FUEL" or s.state == "LOW_FUEL") and colors.red or colors.yellow)
      print("INFO    " .. s.reason)
      term.setTextColor(colors.white)
    end
    print("")
    print("Controlled by BLUMA Core")
    sleep(0.5)
  end
end

saveCfg()
saveState()
send("HELLO", "MINER-01 boot")
parallel.waitForAll(networkLoop, minerLoop, uiLoop)

]==]
local CRAFTER_DATA = [==[-- BLUMA CRAFT-01 V5.1
-- Fixed recipe pipeline: Cobbled Deepslate -> Polished Deepslate -> Deepslate Bricks
-- INPUT: container in FRONT. OUTPUT: container/hopper BELOW.

local VERSION = "5.1.0"
local PROTOCOL = "BLUMA"
local ID = "CRAFT-01"
local SOURCE = "minecraft:cobbled_deepslate"
local MID = "minecraft:polished_deepslate"
local OUTPUT = "minecraft:deepslate_bricks"

local coreId = nil
local state = "STANDBY"
local reason = ""
local crafted = 0
local paused = false
local stopped = false

if type(turtle.craft) ~= "function" then error("BLUMA CRAFT: esta Turtle nao possui Crafting Table upgrade.") end

local function findWirelessModem()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      local m = peripheral.wrap(name)
      if m and m.isWireless then
        local ok, res = pcall(m.isWireless)
        if ok and res then return m, name end
      end
    end
  end
end

local modem, modemName = findWirelessModem()
if modem and not rednet.isOpen(modemName) then rednet.open(modemName) end

local function usedSlots()
  local n = 0
  for i = 1, 16 do if turtle.getItemCount(i) > 0 then n = n + 1 end end
  return n
end

local function payload(tp, msg, req, ok)
  return {
    type = tp, id = ID, version = VERSION,
    state = state, reason = reason,
    crafted = crafted, usedSlots = usedSlots(), recipe = "DEEPSLATE_BRICKS",
    message = msg, requestId = req, ok = ok
  }
end

local function send(tp, msg, req, ok)
  if not modem then return end
  local p = payload(tp, msg, req, ok)
  if coreId then rednet.send(coreId, p, PROTOCOL) else rednet.broadcast(p, PROTOCOL) end
end

local function setState(newState, why)
  state = newState
  reason = why or ""
end

local function item(slot)
  local d = turtle.getItemDetail(slot)
  return d and d.name or nil, d and d.count or 0
end

local function dropNamed(name, direction)
  for i = 1, 16 do
    local n, c = item(i)
    if n == name and c > 0 then
      turtle.select(i)
      local ok
      if direction == "down" then ok = turtle.dropDown() else ok = turtle.drop() end
      if not ok then return false end
    end
  end
  turtle.select(1)
  return true
end

local function consolidate(name)
  local target = nil
  for i = 1, 16 do
    local n, c = item(i)
    if n == name and c > 0 then target = target or i end
  end
  if not target then return false end
  for i = 1, 16 do
    if i ~= target then
      local n, c = item(i)
      if n == name and c > 0 then turtle.select(i); turtle.transferTo(target) end
    end
  end
  if target ~= 1 then turtle.select(target); turtle.transferTo(1) end
  turtle.select(1)
  return true
end

local function clearUnexpected()
  for i = 1, 16 do
    local n, c = item(i)
    if c > 0 and n ~= SOURCE and n ~= MID and n ~= OUTPUT then
      return false, "Item inesperado no slot " .. i .. ": " .. tostring(n)
    end
  end
  return true
end

local function gridFromStack(name)
  if not consolidate(name) then return false, "Nao encontrei " .. name end
  if turtle.getItemCount(1) < 4 then return false, "Preciso de 4x " .. name end
  turtle.select(1)
  if not turtle.transferTo(2, 1) then return false, "Falha ao preencher slot 2." end
  turtle.select(1); if not turtle.transferTo(5, 1) then return false, "Falha ao preencher slot 5." end
  turtle.select(1); if not turtle.transferTo(6, 1) then return false, "Falha ao preencher slot 6." end
  return true
end

local function finishMidIfPresent()
  local total = 0
  for i = 1, 16 do local n, c = item(i); if n == MID then total = total + c end end
  if total == 0 then return true end
  if total < 4 then return false, "Ha polished deepslate incompleta no inventario (menos de 4)." end
  local ok, msg = gridFromStack(MID)
  if not ok then return false, msg end
  local c2, e2 = turtle.craft(1)
  if not c2 then return false, "Segundo craft falhou: " .. tostring(e2) end
  if not consolidate(OUTPUT) then return false, "Deepslate bricks nao apareceu apos o craft." end
  turtle.select(1)
  if not turtle.dropDown() then return false, "Bau/funil abaixo esta cheio ou ausente." end
  crafted = crafted + 4
  return true
end

local function recoverInventory()
  local ok, msg = clearUnexpected()
  if not ok then return false, msg end

  -- Output already crafted: send it down first.
  if not dropNamed(OUTPUT, "down") then return false, "Bau/funil abaixo esta cheio ou ausente." end

  -- If a reboot happened between the two recipe stages, finish the second stage.
  local midCount = 0
  for i = 1, 16 do local n, c = item(i); if n == MID then midCount = midCount + c end end
  if midCount >= 4 then
    local done, why = finishMidIfPresent()
    if not done then return false, why end
  elseif midCount > 0 then
    return false, "Polished deepslate parcial no inventario; remova ou complete para 4."
  end

  -- Return any leftover source to the input container so the grid starts clean.
  if not dropNamed(SOURCE, "front") then return false, "Bau de entrada na frente esta cheio ou ausente." end
  return true
end

local function craftOneBatch()
  setState("WAITING_INPUT", "Aguardando 4 cobbled deepslate.")
  turtle.select(1)
  local ok = turtle.suck(4)
  if not ok then sleep(0.7); return true end

  local n, c = item(1)
  if n ~= SOURCE or c < 4 then
    turtle.select(1); turtle.drop()
    setState("WRONG_INPUT", "Entrada deve conter cobbled deepslate.")
    send("STATUS", reason)
    sleep(1)
    return true
  end

  setState("CRAFTING", "Polindo deepslate.")
  local g, msg = gridFromStack(SOURCE)
  if not g then return false, msg end
  local c1, e1 = turtle.craft(1)
  if not c1 then return false, "Primeiro craft falhou: " .. tostring(e1) end

  setState("CRAFTING", "Criando deepslate bricks.")
  if not consolidate(MID) then return false, "Polished deepslate nao apareceu apos o primeiro craft." end
  local g2, msg2 = gridFromStack(MID)
  if not g2 then return false, msg2 end
  local c2, e2 = turtle.craft(1)
  if not c2 then return false, "Segundo craft falhou: " .. tostring(e2) end
  if not consolidate(OUTPUT) then return false, "Deepslate bricks nao apareceu apos o segundo craft." end

  turtle.select(1)
  if not turtle.dropDown() then return false, "Bau/funil abaixo esta cheio ou ausente." end
  crafted = crafted + 4
  setState("CRAFTING", "Lote concluido.")
  send("STATUS", "4 deepslate bricks produzidos")
  return true
end

local function handle(sender, p)
  if type(p) ~= "table" then return end
  if p.type == "DISCOVER" then coreId = sender; rednet.send(sender, payload("HELLO", "CRAFT-01 ready"), PROTOCOL); return end
  if p.type == "WELCOME" then coreId = sender; return end
  if p.type ~= "COMMAND" or (p.id and p.id ~= ID) then return end

  coreId = sender
  local a = string.upper(tostring(p.action or ""))
  local ok, msg = true, "OK"
  if a == "PAUSE" then
    paused = true; setState("PAUSED", "Pausada pelo operador."); msg = "CRAFT-01 pausada."
  elseif a == "RESUME" or a == "START" then
    local recovered, why = recoverInventory()
    if not recovered then
      ok = false; setState("ERROR", why); msg = why
    else
      paused = false; stopped = false; setState("CRAFTING", "Producao ativa."); os.queueEvent("bluma_craft_wake"); msg = "CRAFT-01 ativa."
    end
  elseif a == "STOP" then
    stopped = true; paused = false; setState("STOPPED", "Parada pelo operador."); os.queueEvent("bluma_craft_wake"); msg = "CRAFT-01 parada."
  else
    ok = false; msg = "Comando desconhecido."
  end
  rednet.send(sender, payload("ACK", msg, p.requestId, ok), PROTOCOL)
end

local function networkLoop()
  if not modem then while true do sleep(10) end end
  local timer = os.startTimer(0.2)
  while true do
    local e = {os.pullEventRaw()}
    if e[1] == "rednet_message" and e[4] == PROTOCOL then handle(e[2], e[3])
    elseif e[1] == "timer" and e[2] == timer then send("HEARTBEAT", "alive"); timer = os.startTimer(2) end
  end
end

local function craftLoop()
  local clean, msg = recoverInventory()
  if not clean then setState("ERROR", msg); send("STATUS", msg) else setState("CRAFTING", "Producao ativa.") end
  while true do
    while paused or stopped or state == "ERROR" or state == "OUTPUT_FULL" do os.pullEvent("bluma_craft_wake") end
    local ok, err = craftOneBatch()
    if not ok then setState("ERROR", err); send("STATUS", err) end
    sleep(0.05)
  end
end

local function uiLoop()
  while true do
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan); print("BLUMA // CRAFT-01 V" .. VERSION); term.setTextColor(colors.white)
    print("STATE   " .. state)
    print("RECIPE  DEEPSLATE BRICKS")
    print("INPUT   CHEST IN FRONT")
    print("OUTPUT  CHEST BELOW")
    print("MADE    " .. crafted)
    if reason ~= "" then print("INFO    " .. reason) end
    print("")
    print("Cobbled Deepslate")
    print(" -> Polished Deepslate")
    print(" -> Deepslate Bricks")
    print("")
    if modem then print("BLUMA link: ONLINE") else print("BLUMA link: NO MODEM (local mode)") end
    sleep(0.5)
  end
end

send("HELLO", "CRAFT-01 boot")
parallel.waitForAll(networkLoop, craftLoop, uiLoop)

]==]

local function cls()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1,1)
end

local function mkdir(path)
  if path and path ~= "" and not fs.exists(path) then fs.makeDir(path) end
end

local function put(path, data)
  local dir = fs.getDir(path)
  if dir and dir ~= "" then mkdir(dir) end
  local h, err = fs.open(path, "w")
  if not h then error("Cannot write " .. path .. ": " .. tostring(err)) end
  h.write(data)
  h.close()
  term.setTextColor(colors.lime); print("OK  " .. path); term.setTextColor(colors.white)
end

local function get(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  if not h then return nil end
  local d = h.readAll()
  h.close()
  return d
end

local function replacePlain(s, old, new)
  local out, pos = {}, 1
  while true do
    local a, b = string.find(s, old, pos, true)
    if not a then out[#out+1] = string.sub(s, pos); break end
    out[#out+1] = string.sub(s, pos, a-1)
    out[#out+1] = new
    pos = b + 1
  end
  return table.concat(out)
end

local function extractQuoted(path, field)
  local d = get(path)
  if not d then return nil end
  local pat = field .. '%s*=%s*"([^"]*)"'
  local v = d:match(pat)
  if v and v ~= "" and v ~= "SUA_CHAVE_GROQ_AQUI" and v ~= "__GROQ_KEY__" and v ~= "__FISH_KEY__" then return v end
  return nil
end

local function findOldField(field)
  local paths = {"bluma/config.lua", "ananke/config.lua", "config.lua"}
  for _, p in ipairs(paths) do
    local v = extractQuoted(p, field)
    if v then return v end
  end
  return nil
end

local function backup(paths)
  local root = ".bluma_backup/" .. tostring(os.epoch("utc"))
  local any = false
  for _, p in ipairs(paths) do
    if fs.exists(p) then
      mkdir(root)
      local dest = fs.combine(root, p)
      mkdir(fs.getDir(dest))
      if fs.exists(dest) then fs.delete(dest) end
      fs.copy(p, dest)
      any = true
    end
  end
  if any then print("Backup: " .. root) end
  return root
end

local function header(role)
  cls()
  term.setTextColor(colors.cyan); print("BLUMA // UNIVERSAL INSTALLER V" .. VERSION)
  term.setTextColor(colors.gray); print("Role: " .. role); print("--------------------------------")
  term.setTextColor(colors.white)
end

local function yesNo(prompt, defaultYes)
  write(prompt)
  local a = string.lower(read() or "")
  if a == "" then return defaultYes end
  return a == "y" or a == "yes" or a == "s" or a == "sim"
end

local function installCore()
  header("CORE")
  local oldGroq = findOldField("GROQ_KEY")
  local oldFish = findOldField("FISH_API_KEY") or findOldField("FISH_KEY")
  local oldRef = findOldField("FISH_REFERENCE_ID") or findOldField("FISH_VOICE_ID")
  backup({"bluma", "ananke", "startup.lua"})

  local groq = oldGroq
  if groq then
    print("Existing Groq key found.")
    if not yesNo("Reuse Groq key? [Y/n]: ", true) then groq = nil end
  end
  if not groq then
    print("Paste Groq API key:")
    write("> ")
    groq = read("*")
  end
  if not groq or groq == "" then error("Groq key cannot be empty.") end

  local voice = yesNo("Enable BLUMA voice through Speaker/Fish Audio? [Y/n]: ", true)
  local fish = oldFish
  local ref = oldRef or ""
  if voice then
    if fish then
      print("Existing Fish Audio key found.")
      if not yesNo("Reuse Fish key? [Y/n]: ", true) then fish = nil end
    end
    if not fish then
      print("Paste Fish Audio API key (ENTER disables voice for now):")
      write("> ")
      fish = read("*") or ""
    end
    if fish ~= "" then
      if ref ~= "" then
        print("Existing Fish voice/reference ID found: " .. ref)
        if not yesNo("Reuse this voice? [Y/n]: ", true) then ref = "" end
      end
      if ref == "" then
        print("Fish voice/reference ID (optional, ENTER = provider default voice):")
        write("> ")
        ref = read() or ""
      end
    else
      voice = false
    end
  else
    fish = fish or ""
  end

  local c = CONFIG_DATA
  c = replacePlain(c, "__GROQ_KEY__", groq)
  c = replacePlain(c, "__VOICE_ENABLED__", voice and "true" or "false")
  c = replacePlain(c, "__FISH_KEY__", fish or "")
  c = replacePlain(c, "__FISH_REFERENCE_ID__", ref or "")

  mkdir("bluma")
  put("bluma/config.lua", c)
  put("bluma/core.lua", CORE_DATA)
  put("startup.lua", 'shell.run("bluma/core.lua")\n')
  print("")
  term.setTextColor(colors.lime); print("BLUMA CORE V" .. VERSION .. " INSTALLED."); term.setTextColor(colors.white)
  print("Voice: " .. (voice and "ENABLED" or "DISABLED"))
  if voice then print("Speaker audio uses Fish WAV -> PCM -> CC Speaker.") end
  if yesNo("Start BLUMA now? [Y/n]: ", true) then shell.run("bluma/core.lua") end
end

local function installMiner()
  header("MINER-01")
  local hadOld = fs.exists(".bluma_miner_state") or fs.exists(".bluma_miner_config") or fs.exists("bluma_miner.lua")
  backup({"bluma_miner.lua", "startup.lua", ".bluma_miner_state", ".bluma_miner_config"})

  if hadOld then
    print("")
    print("Previous MINER files detected and backed up.")
    if yesNo("Reset old MINER state/config? [Y/n]: ", true) then
      if fs.exists(".bluma_miner_state") then fs.delete(".bluma_miner_state") end
      if fs.exists(".bluma_miner_config") then fs.delete(".bluma_miner_config") end
      print("Old runtime state cleared. Backup was kept.")
    else
      print("Old progress/config preserved.")
    end
  end

  put("bluma_miner.lua", MINER_DATA)
  put("startup.lua", 'shell.run("bluma_miner.lua")\n')
  print("")
  print("Required: Advanced Mining Turtle + Wireless Modem")
  print("IMPORTANT: Turtle movement needs fuel.")
  print("Auto-refuel scans the Turtle inventory for valid fuel items.")
  print("For auto-unload, place a chest/container directly BELOW HOME.")
  term.setTextColor(colors.lime); print("MINER-01 V" .. VERSION .. " INSTALLED."); term.setTextColor(colors.white)
  if yesNo("Start MINER-01 now? [Y/n]: ", true) then shell.run("bluma_miner.lua") end
end

local function installCrafter()
  header("CRAFT-01")
  backup({"bluma_crafter.lua", "startup.lua"})
  if type(turtle.craft) ~= "function" then
    term.setTextColor(colors.red); print("WARNING: Crafting Table upgrade was not detected."); term.setTextColor(colors.white)
    print("Install the Crafting Table upgrade before running CRAFT-01.")
  end
  put("bluma_crafter.lua", CRAFTER_DATA)
  put("startup.lua", 'shell.run("bluma_crafter.lua")\n')
  print("")
  print("Recipe preset: Deepslate Bricks")
  print("INPUT:  chest/container directly in FRONT")
  print("OUTPUT: chest/hopper directly BELOW")
  print("Wireless Modem: recommended for BLUMA control/telemetry")
  term.setTextColor(colors.lime); print("CRAFT-01 V" .. VERSION .. " INSTALLED."); term.setTextColor(colors.white)
  if yesNo("Start CRAFT-01 now? [Y/n]: ", true) then shell.run("bluma_crafter.lua") end
end

if not turtle then
  installCore()
else
  header("TURTLE")
  print("Which role should this Turtle use?")
  print("")
  print("1. MINER-01   (Advanced Mining Turtle)")
  print("2. CRAFT-01   (Crafty Turtle)")
  print("")
  write("> ")
  local c = read()
  if c == "1" then installMiner()
  elseif c == "2" then installCrafter()
  else print("Cancelled.") end
end
