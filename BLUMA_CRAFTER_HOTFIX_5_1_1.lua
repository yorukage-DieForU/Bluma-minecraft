-- BLUMA CRAFT-01 HOTFIX INSTALLER V5.1.1
local DATA = [==[-- BLUMA CRAFT-01 V5.1.1 HOTFIX
-- Reliable preset: Cobbled Deepslate -> Polished Deepslate -> Deepslate Bricks
-- Continuous mode: INPUT container directly in FRONT, OUTPUT container/hopper directly BELOW.
-- Manual test mode: exactly 4 Cobbled Deepslate may be placed in the Turtle inventory.

local VERSION = "5.1.1"
local PROTOCOL = "BLUMA"
local ID = "CRAFT-01"
local SOURCE = "minecraft:cobbled_deepslate"
local MID = "minecraft:polished_deepslate"
local OUTPUT = "minecraft:deepslate_bricks"

local coreId = nil
local state = "BOOTING"
local reason = ""
local crafted = 0
local paused = false
local stopped = false

if type(turtle) ~= "table" then error("BLUMA CRAFT: execute isto em uma Turtle.") end
if type(turtle.craft) ~= "function" then error("BLUMA CRAFT: Crafting Table upgrade nao detectado.") end

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

local function setState(s, why)
  state = s
  reason = tostring(why or "")
end

local function item(slot)
  local d = turtle.getItemDetail(slot)
  return d and d.name or nil, d and d.count or 0
end

local function countNamed(name)
  local total = 0
  for i = 1, 16 do
    local n, c = item(i)
    if n == name then total = total + c end
  end
  return total
end

local function usedSlots()
  local n = 0
  for i = 1, 16 do if turtle.getItemCount(i) > 0 then n = n + 1 end end
  return n
end

local function sideLooksLikeInventory(side)
  local ok, methods = pcall(peripheral.getMethods, side)
  if not ok or type(methods) ~= "table" then return false end
  local hasList, hasSize = false, false
  for _, m in ipairs(methods) do
    if m == "list" then hasList = true end
    if m == "size" then hasSize = true end
  end
  return hasList and hasSize
end

local function payload(tp, msg, req, ok)
  return {
    type = tp, id = ID, version = VERSION,
    state = state, reason = reason,
    crafted = crafted, usedSlots = usedSlots(), recipe = "DEEPSLATE_BRICKS",
    sourceCount = countNamed(SOURCE), midCount = countNamed(MID), outputCount = countNamed(OUTPUT),
    inputFront = sideLooksLikeInventory("front"), outputBelow = sideLooksLikeInventory("bottom"),
    message = msg, requestId = req, ok = ok
  }
end

local function send(tp, msg, req, ok)
  if not modem then return end
  local p = payload(tp, msg, req, ok)
  if coreId then rednet.send(coreId, p, PROTOCOL) else rednet.broadcast(p, PROTOCOL) end
end

local function inventorySummary()
  local rows = {}
  for i = 1, 16 do
    local n, c = item(i)
    if n then rows[#rows + 1] = ("%d:%s x%d"):format(i, n, c) end
  end
  return table.concat(rows, " | ")
end

local function ensureOnlyAllowed()
  for i = 1, 16 do
    local n, c = item(i)
    if c > 0 and n ~= SOURCE and n ~= MID and n ~= OUTPUT then
      return false, "Item inesperado no slot " .. i .. ": " .. tostring(n)
    end
  end
  return true
end

local function moveAllNamedToSlot(name, target)
  target = target or 1
  local currentName = item(target)
  if currentName and currentName ~= name then return false, "Slot alvo ocupado por outro item." end
  for i = 1, 16 do
    if i ~= target then
      local n, c = item(i)
      if n == name and c > 0 then
        turtle.select(i)
        local ok = turtle.transferTo(target)
        if not ok and turtle.getItemCount(i) > 0 then
          return false, "Nao consegui consolidar " .. name .. "."
        end
      end
    end
  end
  turtle.select(target)
  return true
end

local function allOtherSlotsEmpty(allowed)
  allowed = allowed or {}
  for i = 1, 16 do
    if not allowed[i] and turtle.getItemCount(i) > 0 then return false, i end
  end
  return true
end

local function arrange2x2FromExactlyFour(name)
  -- turtle.craft expects the inventory to represent a crafting grid. We use 1,2,5,6.
  local total = countNamed(name)
  if total ~= 4 then return false, "Esperava exatamente 4x " .. name .. ", encontrei " .. total .. "." end

  -- Consolidate into slot 1 first.
  local ok, why = moveAllNamedToSlot(name, 1)
  if not ok then return false, why end

  -- There must be nothing except this exact stack before we spread it.
  local clean, bad = allOtherSlotsEmpty({[1] = true})
  if not clean then return false, "Slot " .. bad .. " precisa estar vazio antes do craft." end
  if turtle.getItemCount(1) ~= 4 then return false, "Falha ao preparar os 4 ingredientes." end

  turtle.select(1)
  if not turtle.transferTo(2, 1) then return false, "Falha preenchendo slot 2." end
  turtle.select(1)
  if not turtle.transferTo(5, 1) then return false, "Falha preenchendo slot 5." end
  turtle.select(1)
  if not turtle.transferTo(6, 1) then return false, "Falha preenchendo slot 6." end

  -- Verify the recipe before consuming anything.
  local valid, verr = turtle.craft(0)
  if not valid then
    return false, "Receita 2x2 nao reconhecida: " .. tostring(verr or "invalid recipe")
  end
  return true
end

local function craftExactlyFour(name, expectedOutput, stageLabel)
  setState("CRAFTING", stageLabel)
  local ok, why = arrange2x2FromExactlyFour(name)
  if not ok then return false, why end

  local did, err = turtle.craft(1)
  if not did then return false, "turtle.craft falhou: " .. tostring(err or "unknown") end

  local outCount = countNamed(expectedOutput)
  if outCount <= 0 then
    return false, "Craft executou, mas nao encontrei " .. expectedOutput .. ". Inventario: " .. inventorySummary()
  end
  return true
end

local function dropAllDown(name)
  for i = 1, 16 do
    local n, c = item(i)
    if n == name and c > 0 then
      turtle.select(i)
      local ok, err = turtle.dropDown()
      if not ok then return false, tostring(err or "saida abaixo cheia/ausente") end
    end
  end
  turtle.select(1)
  return true
end

local function returnAllFront(name)
  if not sideLooksLikeInventory("front") then
    return false, "Preciso de um bau/container diretamente NA FRENTE para guardar excesso de entrada."
  end
  for i = 1, 16 do
    local n, c = item(i)
    if n == name and c > 0 then
      turtle.select(i)
      local ok, err = turtle.drop()
      if not ok then return false, tostring(err or "bau da frente cheio") end
    end
  end
  turtle.select(1)
  return true
end

local function normalizeBeforeBatch()
  local ok, why = ensureOnlyAllowed()
  if not ok then return false, why end

  -- First flush finished output.
  if countNamed(OUTPUT) > 0 then
    local d, de = dropAllDown(OUTPUT)
    if not d then return false, "Nao consegui descarregar embaixo: " .. tostring(de) end
  end

  -- If reboot happened between the two stages, finish the polished batch.
  local mid = countNamed(MID)
  if mid > 0 then
    if mid ~= 4 then
      return false, "Polished Deepslate parcial: encontrei " .. mid .. ". Preciso exatamente 4 para recuperar."
    end
    local c, ce = craftExactlyFour(MID, OUTPUT, "Criando Deepslate Bricks")
    if not c then return false, ce end
    local d, de = dropAllDown(OUTPUT)
    if not d then return false, de end
    crafted = crafted + 4
  end

  -- If the user preloaded the Turtle, allow exactly one 4-item manual batch.
  local src = countNamed(SOURCE)
  if src == 4 then return true, "MANUAL_BATCH" end
  if src > 0 then
    -- More than four cannot remain in arbitrary inventory slots while turtle.craft runs.
    local r, re = returnAllFront(SOURCE)
    if not r then
      return false, "Ha " .. src .. " cobbled deepslate no inventario. " .. re
    end
  end

  return true, "READY"
end

local function getFourInput()
  local src = countNamed(SOURCE)
  if src == 4 then return true end
  if src > 0 then return false, "Inventario interno inconsistente: " .. src .. " source items." end

  setState("WAITING_INPUT", "Aguardando 4 Cobbled Deepslate no bau da frente.")
  turtle.select(1)
  local ok, err = turtle.suck(4)
  if not ok then return false, "WAIT" end

  local n, c = item(1)
  if n ~= SOURCE or c ~= 4 then
    local got = n or "item desconhecido"
    if sideLooksLikeInventory("front") then
      turtle.select(1); turtle.drop()
    end
    return false, "Entrada errada: recebi " .. got .. ". Preciso minecraft:cobbled_deepslate."
  end
  return true
end

local function craftOneBatch()
  local normalized, modeOrWhy = normalizeBeforeBatch()
  if not normalized then return false, modeOrWhy end

  if modeOrWhy ~= "MANUAL_BATCH" then
    local got, why = getFourInput()
    if not got then
      if why == "WAIT" then return true, "WAIT" end
      return false, why
    end
  end

  local c1, e1 = craftExactlyFour(SOURCE, MID, "Cobbled -> Polished")
  if not c1 then return false, "Primeiro craft falhou: " .. tostring(e1) end

  -- At this point there must be exactly four polished and nothing else.
  if countNamed(MID) ~= 4 then
    return false, "Primeiro craft nao gerou exatamente 4 polished. Inventario: " .. inventorySummary()
  end

  local c2, e2 = craftExactlyFour(MID, OUTPUT, "Polished -> Bricks")
  if not c2 then return false, "Segundo craft falhou: " .. tostring(e2) end

  local d, de = dropAllDown(OUTPUT)
  if not d then return false, "Craft concluido, mas nao consegui descarregar abaixo: " .. tostring(de) end

  crafted = crafted + 4
  setState("CRAFTING", "Lote concluido: +4 Deepslate Bricks")
  send("STATUS", "4 deepslate bricks produzidos")
  return true, "DONE"
end

local function handle(sender, p)
  if type(p) ~= "table" then return end
  if p.type == "DISCOVER" then
    coreId = sender
    rednet.send(sender, payload("HELLO", "CRAFT-01 V5.1.1 ready"), PROTOCOL)
    return
  end
  if p.type == "WELCOME" then coreId = sender; return end
  if p.type ~= "COMMAND" or (p.id and p.id ~= ID) then return end

  coreId = sender
  local a = string.upper(tostring(p.action or ""))
  local ok, msg = true, "OK"

  if a == "PAUSE" then
    paused = true
    setState("PAUSED", "Pausada pelo operador.")
    msg = "CRAFT-01 pausada."
  elseif a == "RESUME" or a == "START" then
    paused = false
    stopped = false
    if state == "ERROR" then setState("STANDBY", "Tentando novamente.") end
    os.queueEvent("bluma_craft_wake")
    msg = "CRAFT-01 ativa."
  elseif a == "STOP" then
    stopped = true
    paused = false
    setState("STOPPED", "Parada pelo operador.")
    os.queueEvent("bluma_craft_wake")
    msg = "CRAFT-01 parada."
  elseif a == "DIAGNOSE" then
    msg = "state=" .. state .. "; source=" .. countNamed(SOURCE) .. "; mid=" .. countNamed(MID) .. "; output=" .. countNamed(OUTPUT) .. "; frontInv=" .. tostring(sideLooksLikeInventory("front")) .. "; bottomInv=" .. tostring(sideLooksLikeInventory("bottom"))
  else
    ok = false
    msg = "Comando desconhecido."
  end

  rednet.send(sender, payload("ACK", msg, p.requestId, ok), PROTOCOL)
end

local function networkLoop()
  if not modem then while true do sleep(10) end end
  local timer = os.startTimer(0.2)
  while true do
    local e = {os.pullEventRaw()}
    if e[1] == "rednet_message" and e[4] == PROTOCOL then
      handle(e[2], e[3])
    elseif e[1] == "timer" and e[2] == timer then
      send("HEARTBEAT", "alive")
      timer = os.startTimer(2)
    end
  end
end

local function craftLoop()
  setState("STANDBY", "CRAFT-01 pronta.")
  while true do
    while paused or stopped do os.pullEvent("bluma_craft_wake") end

    local ok, result = craftOneBatch()
    if not ok then
      setState("ERROR", result)
      send("STATUS", result)
      while state == "ERROR" do os.pullEvent("bluma_craft_wake") end
    elseif result == "WAIT" then
      sleep(0.7)
    else
      sleep(0.05)
    end
  end
end

local function uiLoop()
  while true do
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)

    term.setTextColor(colors.cyan)
    print("BLUMA // CRAFT-01 V" .. VERSION)
    term.setTextColor(colors.white)
    print("STATE   " .. state)
    print("RECIPE  DEEPSLATE BRICKS")
    print("SOURCE  " .. countNamed(SOURCE))
    print("MID     " .. countNamed(MID))
    print("OUTPUT  " .. countNamed(OUTPUT))
    print("MADE    " .. crafted)
    print("")
    print("INPUT FRONT  " .. (sideLooksLikeInventory("front") and "OK" or "NOT DETECTED"))
    print("OUTPUT BELOW " .. (sideLooksLikeInventory("bottom") and "OK" or "NOT DETECTED"))
    print("CRAFT TABLE  OK")
    print("")
    if reason ~= "" then
      term.setTextColor(state == "ERROR" and colors.red or colors.yellow)
      print("INFO")
      print(reason)
      term.setTextColor(colors.white)
    end
    print("")
    print("Pipeline:")
    print("Cobbled -> Polished -> Bricks")
    print("")
    print(modem and "BLUMA LINK ONLINE" or "BLUMA LINK OFFLINE")
    sleep(0.4)
  end
end

send("HELLO", "CRAFT-01 V5.1.1 boot")
parallel.waitForAll(networkLoop, craftLoop, uiLoop)
]==]

local function put(path, data)
  local h, err = fs.open(path, "w")
  if not h then error("Cannot write " .. path .. ": " .. tostring(err)) end
  h.write(data)
  h.close()
end

term.clear(); term.setCursorPos(1,1)
print("BLUMA // CRAFT-01 HOTFIX 5.1.1")
print("")
if not turtle then error("Execute este instalador na Crafty Turtle.") end
if type(turtle.craft) ~= "function" then
  error("Crafting Table upgrade nao detectado.")
end

if fs.exists("bluma_crafter.lua") then
  local backup = "bluma_crafter_v5_1_backup.lua"
  if fs.exists(backup) then fs.delete(backup) end
  fs.copy("bluma_crafter.lua", backup)
  print("Backup: " .. backup)
end

put("bluma_crafter.lua", DATA)
put("startup.lua", 'shell.run("bluma_crafter.lua")\n')
print("OK: bluma_crafter.lua atualizado")
print("OK: startup.lua atualizado")
print("")
print("LAYOUT CONTINUO:")
print("  [BAU INPUT] -> [CRAFT-01]")
print("                    |")
print("                    v")
print("               [BAU OUTPUT]")
print("")
print("Entrada: Cobbled Deepslate no bau NA FRENTE")
print("Saida: bau/funil DIRETAMENTE EMBAIXO")
print("")
write("Iniciar agora? [Y/n]: ")
local a = string.lower(read() or "")
if a == "" or a == "y" or a == "yes" or a == "s" or a == "sim" then
  shell.run("bluma_crafter.lua")
end
