-- ANANKE UNIVERSAL INSTALLER V4
-- One file installs CORE or MINER automatically.
-- V4 runtime has no require() module paths.

local VERSION="4.0.0"

local CORE_CONFIG=[=[return {
  OWNER = "Murillopip",
  PROTOCOL = "ANANKE",
  MACHINE_ID = "MINER-01",
  HEARTBEAT_TIMEOUT = 8,

  GROQ_KEY = "__GROQ_KEY__",
  GROQ_MODEL = "openai/gpt-oss-20b",

  VOICE_ENABLED = false
}
]=]
local CORE_RUNTIME=[=[-- ANANKE CORE V4
-- CC:Tweaked + Advanced Peripherals
-- Self-contained runtime: no require() paths.

local PROGRAM = shell.getRunningProgram()
local ROOT = fs.getDir(PROGRAM)
local CONFIG_PATH = fs.combine(ROOT, "config.lua")

if not fs.exists(CONFIG_PATH) then
  error("ANANKE: config.lua nao encontrado em "..CONFIG_PATH)
end

local cfg = dofile(CONFIG_PATH)

local function trim(s)
  s = tostring(s or "")
  return (s:gsub("^%s+",""):gsub("%s+$",""))
end

local function lower(s)
  return string.lower(tostring(s or ""))
end

local function contains(a,b)
  return string.find(lower(a), lower(b), 1, true) ~= nil
end

local function ownerEq(a,b)
  return lower(trim(a)) == lower(trim(b))
end

local function now()
  return os.epoch("utc") / 1000
end

local function ascii(s)
  s=tostring(s or "")
  local map={
    ["á"]="a",["à"]="a",["ã"]="a",["â"]="a",["ä"]="a",
    ["é"]="e",["ê"]="e",["ë"]="e",
    ["í"]="i",["ï"]="i",
    ["ó"]="o",["õ"]="o",["ô"]="o",["ö"]="o",
    ["ú"]="u",["ü"]="u",["ç"]="c",
    ["Á"]="A",["À"]="A",["Ã"]="A",["Â"]="A",["Ä"]="A",
    ["É"]="E",["Ê"]="E",["Ë"]="E",
    ["Í"]="I",["Ï"]="I",
    ["Ó"]="O",["Õ"]="O",["Ô"]="O",["Ö"]="O",
    ["Ú"]="U",["Ü"]="U",["Ç"]="C"
  }
  for a,b in pairs(map) do s=s:gsub(a,b) end
  return s:gsub("[^\32-\126\n]","?")
end

local function wrap(text,width)
  local out,line={},""
  width=math.max(8,tonumber(width) or 30)
  for word in ascii(text):gmatch("%S+") do
    if line=="" then line=word
    elseif #line+#word+1<=width then line=line.." "..word
    else out[#out+1]=line line=word end
  end
  if line~="" then out[#out+1]=line end
  return out
end

local function findPeripheral(ptype)
  local obj = peripheral.find(ptype)
  if obj then return obj, peripheral.getName(obj) end
  return nil,nil
end

local function findWirelessModem()
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      local m = peripheral.wrap(name)
      if m and m.isWireless then
        local ok,res = pcall(m.isWireless)
        if ok and res then return m,name end
      end
    end
  end
  return nil,nil
end

local mon, monName = findPeripheral("monitor")
local box, boxName = findPeripheral("chatBox")
local speaker, speakerName = findPeripheral("speaker")
local modem, modemName = findWirelessModem()

if not mon then error("ANANKE: Advanced Monitor nao encontrado.") end
if not box then error("ANANKE: Chat Box nao encontrada.") end
if not modem then error("ANANKE: Wireless Modem nao encontrado.") end

if not rednet.isOpen(modemName) then
  rednet.open(modemName)
end

pcall(function() mon.setTextScale(0.5) end)

local function sendPublic(text)
  text = ascii(text)
  local tries = {
    function() return box.sendMessage(text, "ANANKE", "[]", "&b") end,
    function() return box.sendMessage(text, "ANANKE") end,
    function() return box.sendMessage(text) end
  }
  for _,fn in ipairs(tries) do
    local ok = pcall(fn)
    if ok then return true end
  end
  return false
end

local function sendPrivate(user,text)
  text = ascii(text)
  local tries = {
    function() return box.sendMessageToPlayer(text, user, "ANANKE", "[]", "&b") end,
    function() return box.sendMessageToPlayer(text, user, "ANANKE") end,
    function() return box.sendMessageToPlayer(text, user) end
  }
  for _,fn in ipairs(tries) do
    local ok = pcall(fn)
    if ok then return true end
  end
  return false
end

local machine = {
  state = {},
  pending = {},
  counter = 0
}

local function machineOnline(id)
  local m = machine.state[id]
  return m and (now() - (m.lastSeen or 0) <= (cfg.HEARTBEAT_TIMEOUT or 8))
end

local function machineSummary(id)
  local m = machine.state[id]
  if not machineOnline(id) then return id.."=OFFLINE" end
  local s = id.."="..tostring(m.state or "UNKNOWN")
  s=s.." fuel="..tostring(m.fuel or "?")
  s=s.." slots="..tostring(m.usedSlots or "?").."/16"
  if m.progress~=nil then s=s.." progress="..tostring(m.progress).."%" end
  if m.blocks~=nil then s=s.." blocks="..tostring(m.blocks) end
  if m.x~=nil and m.y~=nil and m.z~=nil then
    s=s.." xyz="..tostring(m.x)..","..tostring(m.y)..","..tostring(m.z)
  end
  return s
end

local function updateMachine(sender,p)
  if type(p)~="table" or not p.id then return end
  machine.state[p.id] = {
    sender=sender,
    state=p.state or "UNKNOWN",
    fuel=p.fuel,
    usedSlots=p.usedSlots,
    progress=p.progress,
    blocks=p.blocks,
    job=p.job,
    message=p.message,
    x=p.x,y=p.y,z=p.z,dir=p.dir,
    lastSeen=now()
  }
end

local function machineCommand(id,action,args)
  local m = machine.state[id]
  if not machineOnline(id) then return false,id.." esta offline." end

  machine.counter=machine.counter+1
  local req=tostring(os.getComputerID()).."-"..tostring(os.epoch("utc")).."-"..machine.counter
  machine.pending[req]=false

  rednet.send(m.sender,{
    type="COMMAND",
    id=id,
    action=action,
    args=args or {},
    requestId=req
  },cfg.PROTOCOL)

  local deadline=now()+4
  while now()<deadline do
    local r=machine.pending[req]
    if type(r)=="table" then
      machine.pending[req]=nil
      return r.ok~=false,r.message or "OK"
    end
    sleep(0.05)
  end

  machine.pending[req]=nil
  return false,"Sem confirmacao da maquina."
end

local function classify(message)
  local hints={
    "miner","mineradora","fuel","combust","invent","slot","coorden",
    "machine","maquina","máquina","liga","desliga","pausa","resume",
    "retoma","stop","return","volta","admin","security","seguranca"
  }
  for _,h in ipairs(hints) do
    if contains(message,h) then return "PRIVATE_MACHINE" end
  end
  return "PUBLIC"
end

local function stripCodeFence(s)
  s=trim(s)
  if s:sub(1,3)=="```" then
    s=s:gsub("^```[%w%-_]*%s*","")
    s=s:gsub("%s*```$","")
  end
  return trim(s)
end

local function askGroq(user,message)
  if not http then return nil,nil,"HTTP API indisponivel." end
  if not cfg.GROQ_KEY or cfg.GROQ_KEY=="" or cfg.GROQ_KEY=="SUA_CHAVE_GROQ_AQUI" then
    return nil,nil,"Groq API key nao configurada."
  end

  local system = [[
You are ANANKE, a calm futuristic female operations assistant inside Minecraft.
Return ONLY compact JSON in this exact shape:
{"language":"pt-BR|en-US|ja-JP","text":"..."}
Rules:
- Answer naturally in the user's language.
- If the user explicitly asks for another language, obey it.
- Never invent telemetry, machine state, or command success.
- The telemetry below is authoritative.
- Keep answers concise and natural.
- You may discuss the machine only from the telemetry supplied.
TELEMETRY:
]]..machineSummary(cfg.MACHINE_ID)

  local body=textutils.serializeJSON({
    model=cfg.GROQ_MODEL,
    temperature=0.35,
    max_tokens=300,
    messages={
      {role="system",content=system},
      {role="user",content=message}
    }
  })

  local response,err,errResponse=http.post(
    "https://api.groq.com/openai/v1/chat/completions",
    body,
    {
      ["Authorization"]="Bearer "..tostring(cfg.GROQ_KEY),
      ["Content-Type"]="application/json"
    }
  )

  if not response then
    local d=tostring(err or "HTTP request failed")
    if errResponse then
      local ok,extra=pcall(function() return errResponse.readAll() end)
      pcall(function() errResponse.close() end)
      if ok and extra and extra~="" then d=d.." | "..extra end
    end
    return nil,nil,d
  end

  local raw=response.readAll()
  response.close()

  local data=textutils.unserializeJSON(raw)
  local c=data and data.choices and data.choices[1]
  c=c and c.message and c.message.content
  if not c then return nil,nil,"Resposta invalida da Groq." end

  c=stripCodeFence(c)
  local parsed=textutils.unserializeJSON(c)
  if type(parsed)=="table" and parsed.text then
    return parsed.language or "pt-BR",trim(parsed.text),nil
  end

  return "pt-BR",trim(c),nil
end

local FACE={
  "          #################",
  "         ##################",
  "        ####################",
  "      ######################",
  "      #######################",
  "     ########################",
  "     ###### ##################",
  "    #####     ################",
  "   # ### ##   #################",
  "  # #####    ####  ############",
  "  # #####    ## ################",
  "   ####### #    # ##############",
  "   ########   #  ################",
  "   #########    #################",
  "   ### ######  # ################",
  "  ############# #################",
  "    #############################",
  "        #########################"
}

local ui={buttons={}}
local state={lastResponse="",lastUser="-",lastError=""}

local function wr(x,y,t,fg,bg)
  local w,h=mon.getSize()
  if x<1 or y<1 or x>w or y>h then return end
  if bg then mon.setBackgroundColor(bg) end
  if fg then mon.setTextColor(fg) end
  mon.setCursorPos(x,y)
  local txt=tostring(t or "")
  if #txt > w-x+1 then txt=txt:sub(1,w-x+1) end
  mon.write(txt)
end

local function btn(x,y,w,label,bg,action)
  local mw,mh=mon.getSize()
  if y>mh or x>mw then return end
  local actual=math.min(w,mw-x+1)
  if actual<3 then return end
  local txt=" "..label
  if #txt<actual then txt=txt..string.rep(" ",actual-#txt) end
  txt=txt:sub(1,actual)
  mon.setBackgroundColor(bg)
  mon.setTextColor(colors.white)
  mon.setCursorPos(x,y)
  mon.write(txt)
  ui.buttons[#ui.buttons+1]={x1=x,y1=y,x2=x+actual-1,y2=y,action=action}
end

local function redraw()
  ui.buttons={}
  local w,h=mon.getSize()
  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.white)
  mon.clear()

  wr(2,1,"ANANKE // COMMAND",colors.cyan,colors.black)
  wr(math.max(2,w-9),1,"[ONLINE]",colors.lime,colors.black)
  wr(1,2,string.rep("-",w),colors.gray,colors.black)

  local split=math.max(30,math.floor(w*0.60))
  wr(2,4,cfg.MACHINE_ID,colors.cyan,colors.black)

  local m=machine.state[cfg.MACHINE_ID]
  if machineOnline(cfg.MACHINE_ID) then
    wr(2,6,"STATE",colors.gray,colors.black)
    wr(13,6,tostring(m.state),m.state=="MINING" and colors.lime or colors.yellow,colors.black)
    wr(2,7,"FUEL",colors.gray,colors.black)
    wr(13,7,tostring(m.fuel or "?"),colors.white,colors.black)
    wr(2,8,"STORAGE",colors.gray,colors.black)
    wr(13,8,tostring(m.usedSlots or "?").."/16",colors.white,colors.black)
    wr(2,9,"PROGRESS",colors.gray,colors.black)
    wr(13,9,tostring(m.progress or "?").."%",colors.white,colors.black)
    wr(2,10,"BLOCKS",colors.gray,colors.black)
    wr(13,10,tostring(m.blocks or "?"),colors.white,colors.black)

    btn(2,12,9,"START",colors.green,"START")
    btn(12,12,9,"PAUSE",colors.orange,"PAUSE")
    btn(22,12,10,"RESUME",colors.blue,"RESUME")
    btn(33,12,10,"RETURN",colors.purple,"RETURN")
    btn(44,12,8,"STOP",colors.red,"STOP")
  else
    wr(2,6,"OFFLINE",colors.red,colors.black)
    wr(2,7,"Waiting for heartbeat...",colors.gray,colors.black)
  end

  if state.lastResponse~="" then
    wr(2,15,"LAST RESPONSE",colors.cyan,colors.black)
    local rows=wrap(state.lastResponse,math.max(20,split-4))
    for i=1,math.min(#rows,math.max(0,h-16)) do
      wr(2,15+i,rows[i],colors.white,colors.black)
    end
  end

  if w>=58 then
    local ox=math.min(w-30,split+2)
    wr(ox,4,"RESI // FACE",colors.cyan,colors.black)
    for yy,row in ipairs(FACE) do
      if 5+yy>h-1 then break end
      for xx=1,#row do
        if ox+xx-1>w then break end
        local ch=row:sub(xx,xx)
        wr(ox+xx-1,5+yy," ",nil,ch=="#" and colors.lightBlue or colors.black)
      end
    end
  end

  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.white)
end

local function hit(x,y)
  for _,b in ipairs(ui.buttons) do
    if x>=b.x1 and x<=b.x2 and y>=b.y1 and y<=b.y2 then
      return b.action
    end
  end
  return nil
end

local function parseMachineIntent(user,msg)
  if not ownerEq(user,cfg.OWNER) then return nil end

  if (contains(msg,"liga") or contains(msg,"start") or contains(msg,"inicia") or contains(msg,"começa")) and
     (contains(msg,"miner") or contains(msg,"mineradora")) then
    return "START"
  end

  if contains(msg,"pausa") and (contains(msg,"miner") or contains(msg,"mineradora")) then
    return "PAUSE"
  end

  if (contains(msg,"retoma") or contains(msg,"resume") or contains(msg,"continua")) and
     (contains(msg,"miner") or contains(msg,"mineradora")) then
    return "RESUME"
  end

  if (contains(msg,"volta") or contains(msg,"return") or contains(msg,"retorna")) and
     (contains(msg,"miner") or contains(msg,"mineradora")) then
    return "RETURN"
  end

  if (contains(msg,"para") or contains(msg,"stop")) and
     (contains(msg,"miner") or contains(msg,"mineradora")) then
    return "STOP"
  end

  return nil
end

local function processChat(user,msg)
  local class=classify(msg)

  if class=="PRIVATE_MACHINE" and not ownerEq(user,cfg.OWNER) then
    local response="Essa informacao e restrita ao operador."
    state.lastUser=user
    state.lastResponse=response
    redraw()
    sendPublic(response)
    return
  end

  local action=parseMachineIntent(user,msg)
  local response

  if action then
    local ok,res=machineCommand(cfg.MACHINE_ID,action)
    response=res
  else
    local lang,answer,err=askGroq(user,msg)
    response=answer or ("Falha no nucleo de linguagem: "..tostring(err))
  end

  state.lastUser=user
  state.lastResponse=response
  redraw()

  if class=="PRIVATE_MACHINE" then
    sendPrivate(user,response)
  else
    sendPublic(response)
  end
end

local function chatLoop()
  while true do
    local e={os.pullEvent("chat")}
    local user=e[2]
    local msg=e[3]
    local utf8msg=e[6]
    local actual=utf8msg or msg or ""

    if contains(actual,"ananke") then
      local ok,err=pcall(processChat,user,actual)
      if not ok then
        state.lastError=tostring(err)
        state.lastResponse="Erro interno: "..tostring(err)
        redraw()
        sendPrivate(user,state.lastResponse)
      end
    end
  end
end

local function touchLoop()
  while true do
    local _,side,x,y=os.pullEvent("monitor_touch")
    local action=hit(x,y)
    if action then
      local ok,msg=machineCommand(cfg.MACHINE_ID,action)
      state.lastResponse=msg
      redraw()
      sendPrivate(cfg.OWNER,msg)
    end
  end
end

local function rednetLoop()
  while true do
    local _,sender,p,protocol=os.pullEvent("rednet_message")
    if protocol==cfg.PROTOCOL and type(p)=="table" then
      if p.type=="HEARTBEAT" or p.type=="STATUS" or p.type=="ACK" then
        updateMachine(sender,p)
      end

      if p.type=="ACK" and p.requestId then
        machine.pending[p.requestId]={
          ok=p.ok~=false,
          message=p.message
        }
      end

      redraw()
    end
  end
end

local function redrawLoop()
  while true do
    redraw()
    sleep(0.5)
  end
end

redraw()
sendPublic("ANANKE online.")

parallel.waitForAll(
  chatLoop,
  touchLoop,
  rednetLoop,
  redrawLoop
)
]=]
local MINER_RUNTIME=[=[-- ANANKE MINER V4
-- Advanced Mining Turtle + Wireless Modem
-- Persistent quarry + heartbeat + remote command ACK.

local PROTOCOL="ANANKE"
local ID="MINER-01"
local SAVE=".ananke_miner_state"

local DEFAULT_WIDTH=__WIDTH__
local DEFAULT_LENGTH=__LENGTH__
local DEFAULT_DEPTH=__DEPTH__

local function findWirelessModem()
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name)=="modem" then
      local m=peripheral.wrap(name)
      if m and m.isWireless then
        local ok,res=pcall(m.isWireless)
        if ok and res then return m,name end
      end
    end
  end
  return nil,nil
end

local modem,modemName=findWirelessModem()
if not modem then error("ANANKE MINER: Wireless Modem nao encontrado.") end
if not rednet.isOpen(modemName) then rednet.open(modemName) end

local s={
  state="STANDBY",
  width=DEFAULT_WIDTH,
  length=DEFAULT_LENGTH,
  depth=DEFAULT_DEPTH,
  layer=0,row=0,col=0,
  x=0,y=0,z=0,dir=0,
  blocks=0,
  paused=false,
  stop=false,
  returning=false
}

local coreId=nil

local function save()
  local h=fs.open(SAVE,"w")
  if h then
    h.write(textutils.serializeJSON(s))
    h.close()
  end
end

local function loadState()
  if not fs.exists(SAVE) then return end
  local h=fs.open(SAVE,"r")
  if not h then return end
  local raw=h.readAll()
  h.close()
  local d=textutils.unserializeJSON(raw)
  if type(d)=="table" then
    for k,v in pairs(d) do s[k]=v end
  end
  if s.state=="MINING" or s.state=="PREPARING" then
    s.state="PAUSED"
    s.paused=true
  end
end

loadState()

local function usedSlots()
  local n=0
  for i=1,16 do
    if turtle.getItemCount(i)>0 then n=n+1 end
  end
  return n
end

local function progress()
  local total=math.max(1,s.width*s.length*s.depth)
  local done=(s.layer*s.width*s.length)+(s.row*s.width)+s.col
  return math.floor(math.min(100,done/total*1000))/10
end

local function packet(tp,msg,req,ok)
  return {
    type=tp,id=ID,state=s.state,
    fuel=turtle.getFuelLevel(),
    usedSlots=usedSlots(),
    progress=progress(),
    blocks=s.blocks,
    job={
      width=s.width,length=s.length,depth=s.depth,
      layer=s.layer,row=s.row,col=s.col
    },
    x=s.x,y=s.y,z=s.z,dir=s.dir,
    message=msg,requestId=req,ok=ok
  }
end

local function send(tp,msg,req,ok)
  local p=packet(tp,msg,req,ok)
  if coreId then
    rednet.send(coreId,p,PROTOCOL)
  else
    rednet.broadcast(p,PROTOCOL)
  end
end

local function right()
  turtle.turnRight()
  s.dir=(s.dir+1)%4
  save()
end

local function left()
  turtle.turnLeft()
  s.dir=(s.dir+3)%4
  save()
end

local function face(d)
  while s.dir~=d do right() end
end

local function digForward()
  if turtle.detect() and turtle.dig() then
    s.blocks=s.blocks+1
  end
end

local function forward()
  digForward()
  local tries=0
  while not turtle.forward() do
    tries=tries+1
    if tries>30 then
      s.state="BLOCKED"
      save()
      send("STATUS","Blocked moving forward")
      return false
    end
    turtle.attack()
    digForward()
    sleep(0.1)
  end

  if s.dir==0 then s.z=s.z-1
  elseif s.dir==1 then s.x=s.x+1
  elseif s.dir==2 then s.z=s.z+1
  else s.x=s.x-1 end

  save()
  return true
end

local function moveUp()
  if turtle.detectUp() then turtle.digUp() end
  local tries=0
  while not turtle.up() do
    tries=tries+1
    if tries>30 then
      s.state="BLOCKED"
      save()
      send("STATUS","Blocked moving up")
      return false
    end
    turtle.attackUp()
    turtle.digUp()
    sleep(0.1)
  end
  s.y=s.y+1
  save()
  return true
end

local function moveDown()
  if turtle.detectDown() and turtle.digDown() then
    s.blocks=s.blocks+1
  end
  local tries=0
  while not turtle.down() do
    tries=tries+1
    if tries>30 then
      s.state="BLOCKED"
      save()
      send("STATUS","Blocked moving down")
      return false
    end
    turtle.attackDown()
    turtle.digDown()
    sleep(0.1)
  end
  s.y=s.y-1
  save()
  return true
end

local function moveXTo(target)
  if s.x<target then
    face(1)
    while s.x<target do if not forward() then return false end end
  elseif s.x>target then
    face(3)
    while s.x>target do if not forward() then return false end end
  end
  return true
end

local function moveZTo(target)
  if s.z<target then
    face(2)
    while s.z<target do if not forward() then return false end end
  elseif s.z>target then
    face(0)
    while s.z>target do if not forward() then return false end end
  end
  return true
end

local function returnHome()
  s.state="RETURNING"
  s.returning=true
  save()
  send("STATUS","Returning home")

  while s.y<0 do
    if not moveUp() then return false end
  end

  if not moveXTo(0) then return false end
  if not moveZTo(0) then return false end

  face(0)
  s.state="STANDBY"
  s.returning=false
  s.paused=false
  s.stop=false
  save()
  send("STATUS","At home")
  return true
end

local function handleFlags()
  if s.returning then
    returnHome()
    return false
  end

  if s.stop then
    s.state="STANDBY"
    s.stop=false
    s.paused=false
    save()
    send("STATUS","Stopped")
    return false
  end

  while s.paused do
    s.state="PAUSED"
    save()
    os.pullEvent("ananke_resume")
    if s.returning or s.stop then
      return handleFlags()
    end
  end

  return true
end

local function resetJob()
  s.state="STANDBY"
  s.layer=0
  s.row=0
  s.col=0
  s.x=0
  s.y=0
  s.z=0
  s.dir=0
  s.blocks=0
  s.paused=false
  s.stop=false
  s.returning=false
  save()
end

local function returnToLayerOrigin()
  if not moveXTo(0) then return false end
  if not moveZTo(0) then return false end
  face(0)
  return true
end

local function mineJob()
  s.state="MINING"
  s.paused=false
  s.stop=false
  save()
  send("STATUS","Mining started")

  local startLayer=s.layer

  for layer=startLayer,s.depth-1 do
    s.layer=layer

    local startRow=(layer==startLayer) and s.row or 0

    for row=startRow,s.length-1 do
      s.row=row

      local expectedDir=(row%2==0) and 0 or 2
      if s.col==0 then face(expectedDir) end

      local startCol=(layer==startLayer and row==startRow) and s.col or 0

      for col=startCol,s.width-1 do
        s.col=col

        if not handleFlags() then return end

        if usedSlots()>=16 then
          s.state="FULL"
          s.paused=true
          save()
          send("STATUS","Inventory full; paused")
          while s.paused do
            os.pullEvent("ananke_resume")
            if s.returning or s.stop then
              if not handleFlags() then return end
            end
          end
          s.state="MINING"
          save()
        end

        if col<s.width-1 then
          if not forward() then return end
        end
      end

      s.col=0

      if row<s.length-1 then
        if row%2==0 then
          right()
          if not forward() then return end
          right()
        else
          left()
          if not forward() then return end
          left()
        end
      end

      save()
    end

    s.row=0
    s.col=0

    if layer<s.depth-1 then
      if not returnToLayerOrigin() then return end
      if not moveDown() then return end
      face(0)
      save()
    end
  end

  if not returnToLayerOrigin() then return end
  s.state="FINISHED"
  save()
  send("STATUS","Job complete")
end

local function command(sender,p)
  if type(p)~="table" or p.type~="COMMAND" then return end
  coreId=sender

  local a=string.upper(tostring(p.action or ""))
  local ok=true
  local msg="OK"

  if a=="START" then
    if s.state=="FINISHED" then resetJob() end

    if s.state=="STANDBY" then
      s.state="PREPARING"
      save()
      os.queueEvent("ananke_start")
      msg="Job iniciado."
    elseif s.state=="PAUSED" or s.state=="FULL" then
      s.paused=false
      s.state="MINING"
      save()
      os.queueEvent("ananke_resume")
      msg="Mineracao retomada."
    else
      msg="Mineradora ja esta ativa."
    end

  elseif a=="PAUSE" then
    if s.state=="MINING" or s.state=="PREPARING" then
      s.paused=true
      s.state="PAUSED"
      save()
      msg="Mineradora pausada."
    else
      msg="Nada para pausar."
    end

  elseif a=="RESUME" then
    if s.state=="PAUSED" or s.state=="FULL" then
      s.paused=false
      s.state="MINING"
      save()
      os.queueEvent("ananke_resume")
      msg="Mineradora retomada."
    else
      msg="Mineradora nao esta pausada."
    end

  elseif a=="RETURN" then
    s.returning=true
    s.paused=false
    save()
    os.queueEvent("ananke_resume")
    msg="Retorno solicitado."

  elseif a=="STOP" then
    s.stop=true
    s.paused=false
    save()
    os.queueEvent("ananke_resume")
    msg="Parada solicitada."

  else
    ok=false
    msg="Comando desconhecido."
  end

  send("ACK",msg,p.requestId,ok)
end

local function networkLoop()
  local timer=os.startTimer(1)

  while true do
    local e={os.pullEventRaw()}

    if e[1]=="rednet_message" and e[4]==PROTOCOL then
      command(e[2],e[3])
    elseif e[1]=="timer" and e[2]==timer then
      send("HEARTBEAT","alive")
      timer=os.startTimer(2)
    elseif e[1]=="terminate" then
      s.state="STOPPED"
      save()
      return
    end
  end
end

local function uiLoop()
  while true do
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1,1)

    term.setTextColor(colors.cyan)
    print("ANANKE // MINER-01")
    term.setTextColor(colors.white)
    print("")
    print("STATE   "..s.state)
    print("JOB     "..s.width.."x"..s.length.."x"..s.depth)
    print("PROG    "..progress().."%")
    print("LAYER   "..(s.layer+1).."/"..s.depth)
    print("ROW     "..(s.row+1).."/"..s.length)
    print("FUEL    "..tostring(turtle.getFuelLevel()))
    print("SLOTS   "..usedSlots().."/16")
    print("BLOCKS  "..s.blocks)
    print("")

    term.setBackgroundColor(colors.orange)
    term.setTextColor(colors.black)
    print(" PAUSE ")

    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    print(" RESUME ")

    term.setBackgroundColor(colors.purple)
    print(" RETURN ")

    term.setBackgroundColor(colors.red)
    print(" STOP ")

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)

    sleep(0.5)
  end
end

local function mouseLoop()
  while true do
    local _,button,x,y=os.pullEvent("mouse_click")
    if y==12 then
      s.paused=true
      s.state="PAUSED"
      save()
    elseif y==13 then
      s.paused=false
      s.state="MINING"
      save()
      os.queueEvent("ananke_resume")
    elseif y==14 then
      s.returning=true
      s.paused=false
      save()
      os.queueEvent("ananke_resume")
    elseif y==15 then
      s.stop=true
      s.paused=false
      save()
      os.queueEvent("ananke_resume")
    end
  end
end

local function minerLoop()
  while true do
    if s.state=="PREPARING" or s.state=="MINING" then
      mineJob()
    elseif s.state=="PAUSED" or s.state=="FULL" then
      os.pullEvent("ananke_resume")
      if not s.returning and not s.stop and not s.paused then
        mineJob()
      elseif s.returning or s.stop then
        handleFlags()
      end
    else
      local e=os.pullEvent()
      if e=="ananke_start" then mineJob() end
      if e=="ananke_resume" and (s.returning or s.stop) then handleFlags() end
    end
  end
end

send("HEARTBEAT","boot")
parallel.waitForAll(networkLoop,uiLoop,mouseLoop,minerLoop)
]=]
local RESI_ASCII=[=[⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⣲⣵⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣿⣿⣿⣿⡿⣻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠟⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⣿⣿⣿⣿⣿⣿⣿⣿⡿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣎⣼⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣴⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⠹⣿⣿⣶⡝⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣽⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣴⣻⣯⣿⣿⣳⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⢏⣿⣿⣿⣿⣿⣿⣿⡟⢻⣿⢣⣿⣿⢻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣛⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣟⣧⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡌⣼⣿⣿⣿⢿⣿⣿⡟⠀⣿⠇⢸⣿⣿⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣹⠆⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⢠⣿⣿⣿⡿⢼⣿⣿⡇⢸⣿⠀⣼⣿⡇⠸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣧⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣸⣿⣿⣿⣿⣗⢴⣹⡟⢳⣾⣏⠇⣿⣿⡇⠀⣿⣿⣿⣿⣷⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣧⢷⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣿⣿⣿⣿⣿⡽⡿⣮⡂⠄⠙⢿⠀⣿⣿⡿⠀⠻⣿⣿⣿⣿⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣺⡄⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⡿⣿⣿⣿⣿⣆⠳⣫⣿⣶⠀⠈⠀⢹⢻⣻⣀⣘⣿⣿⣾⣿⡏⡿⢹⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡏⡟⡆⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⢇⣿⣿⣿⡏⡝⠓⠐⠀⠓⠀⠀⠀⠀⠁⠀⡣⡉⠻⣿⡿⢿⣿⣤⣋⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣇⣷⠱⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⣀⡾⣿⢿⣿⣿⣿⡇⠈⠳⣄⡀⠀⠀⠀⠀⠀⠈⠀⣐⣰⣦⣭⣝⠈⠻⢿⡛⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣾⢸⠀⡆⠀⠀⠀⠀
⠀⠀⠀⠀⢀⡴⠛⠁⠀⣿⢺⣿⣿⣿⣏⠀⠀⠈⠻⠹⡢⡀⠀⠀⠀⠈⠉⣅⢏⠟⠹⣿⢷⣦⣑⠸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢺⡇⢠⠀⠀⠀⠀
⠀⠀⠀⢀⠞⠁⠀⠄⢠⡇⢸⣿⣿⣿⡧⠁⢠⠌⠀⠀⠈⠚⠦⣀⠀⠀⠀⠉⠷⣬⣭⣑⡪⡭⠃⠑⢱⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡟⣯⢘⠀⠀⠀⠀
⠀⠀⠀⡏⠀⠀⠀⠀⢸⡇⣿⣿⣿⣿⣿⡆⠈⠇⠠⢀⠀⠀⠀⠉⠲⣦⣀⠀⠀⣀⠑⠒⠈⠁⢀⠀⠀⢉⣿⣿⣟⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣯⣿⣿⡀⠀⠀⠀⠀
⠀⠀⠸⣟⠀⠀⠀⠀⢸⣇⣿⣿⣿⣿⣿⣿⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⢭⠮⠖⠲⠆⠒⠉⠀⣠⣾⢺⣿⣿⣽⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣗⠀⠀⠀⠀
⠀⠀⠀⢹⡆⠀⠀⠀⢸⣿⣿⣿⣿⣯⣿⣧⡝⠚⠢⢀⠀⠀⠠⠀⡀⠀⢀⠼⠃⣀⣀⠤⠖⠀⣀⠴⣿⣴⣾⣿⣿⣿⣿⣿⣿⣟⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢸⣿⡼⡆⠀⠀⠀
⠀⠀⠀⠀⢿⣆⠀⠀⣷⣿⣿⣿⣿⣿⣿⣿⣽⠒⠀⠀⠉⠀⠀⠀⢀⡽⠋⠉⠀⠀⠀⢀⣤⡞⠃⢰⣿⣿⣿⣿⣿⣿⣿⡽⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣻⣿⣇⢱⡄⠀⠀
⠀⠀⠀⠀⠸⡾⡇⠀⢹⣿⣿⣿⣿⣿⣿⣿⣿⣥⠀⠀⠀⠀⠠⠂⢁⣀⣀⠤⠤⠒⠊⣡⠏⠀⠀⣾⣿⣿⣿⣿⣿⣿⣿⣿⠹⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡎⢷⡀⠀
⠀⠀⠀⠀⠀⢧⣇⠀⣿⣿⣿⣿⣿⣿⡟⠿⣿⣿⣷⠶⡒⠛⠋⠉⠉⠀⠀⠀⠀⠀⡰⠃⠀⠀⣼⢾⣿⣿⣿⣿⣿⣿⣿⣽⣷⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣼⣿⣿⢴⠈⣧⠀
⠀⠀⠀⠀⠀⠸⣿⣴⣿⣿⣿⣿⣿⣿⣿⠈⠽⣿⣯⢂⠘⡀⠀⠀⠀⠀⠀⣠⠴⠊⠀⠀⠀⣼⠇⣿⣿⣿⣿⡿⢻⣿⣿⣿⣽⣺⣟⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡆⠘⡄
⠀⠀⠀⠀⠀⠀⢿⣿⣿⣿⣿⣿⠇⣸⣿⣇⠈⢛⣿⣆⠵⢕⠄⠀⣠⠖⠚⠁⠀⠀⠀⠀⢠⠏⢀⣿⣿⣿⣿⡗⡏⣿⣿⣿⠰⣿⠫⢀⡹⡿⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣇⢧⠀⣣
⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⡏⠀⢹⣿⣿⡄⣴⣿⢹⣷⣶⣷⡍⠀⠀⠀⠀⠀⠀⠀⢠⡏⠀⣼⣿⣿⣿⣿⡟⠀⣿⣿⣿⣾⡇⢸⠊⠈⠀⠂⣴⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⡏
⠀⠀⠀⠀⠀⠀⣼⣿⣿⣿⣿⠇⠀⠈⣟⣿⣷⡛⣿⣧⣿⣤⣼⣿⣄⠀⠀⠀⠀⠀⢀⡞⠀⢠⣿⣿⣿⣿⣿⠇⠀⣿⢿⣿⣯⣕⠁⡖⠀⣤⣴⣾⣿⣿⣿⣿⣿⣭⣿⣿⣿⣽⣿⡇
⠀⠀⠀⠀⠀⠸⣿⣿⣿⣿⣿⡰⡀⠀⢸⡽⣿⣷⣘⣿⣿⣿⣿⠋⠘⣆⠀⠀⠀⣠⠏⠀⠰⢸⣿⣿⣿⣿⣿⠀⠀⣿⣾⣽⣿⣦⣤⣧⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣯⣿⣿⣿⣿⠷
⠂⠄⠢⢴⣶⠾⣿⣿⣿⣿⣿⣿⣿⣶⣎⠀⡈⢿⢻⣿⣿⣿⣿⣿⣄⠙⣄⢤⡴⠃⣀⠀⢰⣿⣿⣿⣿⣿⣿⢀⣼⣿⣶⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣾⣷⣿⣿⣿⡿⣦
⠀⠀⠀⠀⠀⠐⠸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣶⣧⣿⣿⣿⡘⣿⣿⣿⣿⣼⡍⠁⠢⠀⠊⣵⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡻⣿
⠀⠀⠀⠀⠀⠀⠈⠙⠿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣶⣶⣬⣐⣤⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡮
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠻⢿⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⣻
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠐⠛⠿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⣿
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠿⢿⣧⣹⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣻⣵⢫⣿⣷⣿
]=]
local ROLE=turtle and "MINER" or "CORE"

local function cls()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1,1)
end

local function ensureDir(path)
  if not path or path=="" or path=="/" or fs.exists(path) then return end
  local parent=fs.getDir(path)
  if parent and parent~="" and parent~=path then ensureDir(parent) end
  fs.makeDir(path)
end

local function put(path,data)
  local dir=fs.getDir(path)
  if dir and dir~="" then ensureDir(dir) end
  local h,err=fs.open(path,"w")
  if not h then error("Nao consegui criar "..path..": "..tostring(err)) end
  h.write(data)
  h.close()
  term.setTextColor(colors.lime)
  print("OK  "..path)
  term.setTextColor(colors.white)
end

local function get(path)
  if not fs.exists(path) then return nil end
  local h=fs.open(path,"r")
  if not h then return nil end
  local d=h.readAll()
  h.close()
  return d
end

local function replacePlain(s,old,new)
  local out,pos={},1
  while true do
    local a,b=string.find(s,old,pos,true)
    if not a then
      out[#out+1]=string.sub(s,pos)
      break
    end
    out[#out+1]=string.sub(s,pos,a-1)
    out[#out+1]=new
    pos=b+1
  end
  return table.concat(out)
end

local function backup()
  local stamp=tostring(os.epoch("utc"))
  local root=".ananke_backup/"..stamp
  local did=false

  local function cp(path)
    if fs.exists(path) then
      ensureDir(root)
      local dest=fs.combine(root,path)
      ensureDir(fs.getDir(dest))
      if fs.exists(dest) then fs.delete(dest) end
      fs.copy(path,dest)
      did=true
    end
  end

  if ROLE=="CORE" then
    cp("ananke")
    cp("startup.lua")
  else
    cp("ananke_miner.lua")
    cp(".ananke_miner_state")
    cp("startup.lua")
  end

  if did then
    print("Backup: "..root)
  end
end

local function findWirelessModemName()
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name)=="modem" then
      local m=peripheral.wrap(name)
      if m and m.isWireless then
        local ok,res=pcall(m.isWireless)
        if ok and res then return name end
      end
    end
  end
  return nil
end

local function title()
  cls()
  term.setTextColor(colors.cyan)
  print("ANANKE // UNIVERSAL INSTALLER V4")
  term.setTextColor(colors.gray)
  print("Role: "..ROLE)
  print("--------------------------------")
  term.setTextColor(colors.white)
end

local function existingGroq()
  local old=get("ananke/config.lua")
  if not old then return nil end
  local key=old:match('GROQ_KEY%s*=%s*"([^"]+)"')
  if key and key~="" and key~="SUA_CHAVE_GROQ_AQUI" and key~="__GROQ_KEY__" then
    return key
  end
  return nil
end

local function installCore()
  title()
  print("Instalando ANANKE CORE V4")
  print("")
  backup()

  local groq=existingGroq()
  if groq then
    print("Groq key existente encontrada.")
    write("Reutilizar? [Y/n]: ")
    local a=string.lower(read() or "")
    if a=="n" or a=="no" then groq=nil end
  end

  if not groq then
    print("Cole sua Groq API key.")
    write("> ")
    groq=read("*")
  end

  if not groq or groq=="" then
    error("Groq API key vazia. Instalacao cancelada.")
  end

  ensureDir("ananke")
  ensureDir("ananke/assets")

  local cfgData=CORE_CONFIG
  cfgData=replacePlain(cfgData,"__GROQ_KEY__",groq)

  put("ananke/config.lua",cfgData)
  put("ananke/core.lua",CORE_RUNTIME)
  put("ananke/assets/resi_ascii.txt",RESI_ASCII)
  put("startup.lua",'shell.run("ananke/core.lua")\n')

  print("")
  print("Diagnostico:")
  print("Monitor: "..(peripheral.find("monitor") and "OK" or "MISSING"))
  print("ChatBox: "..(peripheral.find("chatBox") and "OK" or "MISSING"))
  print("Speaker: "..(peripheral.find("speaker") and "OK" or "MISSING/OPTIONAL"))
  print("Wireless Modem: "..(findWirelessModemName() and "OK" or "MISSING"))
  print("HTTP API: "..(http and "OK" or "MISSING"))

  print("")
  term.setTextColor(colors.lime)
  print("ANANKE CORE V4 INSTALADA.")
  term.setTextColor(colors.white)

  write("Iniciar agora? [Y/n]: ")
  local a=string.lower(read() or "")
  if a~="n" and a~="no" then
    shell.run("ananke/core.lua")
  end
end

local function askInt(label,default)
  while true do
    write(label.." ["..default.."]: ")
    local v=read()
    if v=="" then return default end
    local n=tonumber(v)
    if n and n>=1 and n<=512 and math.floor(n)==n then return n end
    print("Use um numero inteiro de 1 a 512.")
  end
end

local function installMiner()
  title()
  print("Instalando ANANKE MINER V4")
  print("")
  backup()

  local w=askInt("Width",64)
  local l=askInt("Length",64)
  local d=askInt("Depth",64)

  local src=MINER_RUNTIME
  src=replacePlain(src,"__WIDTH__",tostring(w))
  src=replacePlain(src,"__LENGTH__",tostring(l))
  src=replacePlain(src,"__DEPTH__",tostring(d))

  put("ananke_miner.lua",src)
  put("startup.lua",'shell.run("ananke_miner.lua")\n')

  print("")
  print("Diagnostico:")
  print("Turtle API: "..(turtle and "OK" or "MISSING"))
  print("Wireless Modem: "..(findWirelessModemName() and "OK" or "MISSING"))
  print("Fuel: "..tostring(turtle.getFuelLevel()))

  print("")
  term.setTextColor(colors.lime)
  print("ANANKE MINER V4 INSTALADA.")
  term.setTextColor(colors.white)

  write("Iniciar agora? [Y/n]: ")
  local a=string.lower(read() or "")
  if a~="n" and a~="no" then
    shell.run("ananke_miner.lua")
  end
end

title()
print("Este arquivo instala tudo sozinho.")
print("Nenhuma pasta precisa ser criada manualmente.")
print("")
write("Instalar agora? [Y/n]: ")
local answer=string.lower(read() or "")

if answer=="n" or answer=="no" then
  print("Cancelado.")
  return
end

if ROLE=="MINER" then
  installMiner()
else
  installCore()
end
