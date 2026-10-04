-- BLUMA UNIVERSAL INSTALLER V5
-- Same installer for Core, Mining Turtle and Crafting Turtle.

local VERSION="5.0.0"
local CONFIG_DATA=[=[return {
  OWNER = "Murillopip",
  PROTOCOL = "BLUMA",
  GROQ_KEY = "__GROQ_KEY__",
  GROQ_MODEL = "openai/gpt-oss-20b",
  HEARTBEAT_TIMEOUT = 7,
  MINER_ID = "MINER-01",
  CRAFTER_ID = "CRAFT-01"
}
]=]
local CORE_DATA=[=[-- BLUMA CONTROL CENTER V5
-- CC:Tweaked + Advanced Peripherals
-- No external modules required.

local PROGRAM = shell.getRunningProgram()
local ROOT = fs.getDir(PROGRAM)
local cfg = dofile(fs.combine(ROOT, "config.lua"))
local startedAt = os.epoch("utc")

local function lower(v) return string.lower(tostring(v or "")) end
local function trim(v) return (tostring(v or ""):gsub("^%s+",""):gsub("%s+$","")) end
local function contains(a,b) return string.find(lower(a), lower(b), 1, true) ~= nil end
local function isOwner(name) return lower(trim(name)) == lower(trim(cfg.OWNER)) end
local function now() return os.epoch("utc") / 1000 end
local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end

local accents={
  ["á"]="a",["à"]="a",["ã"]="a",["â"]="a",["ä"]="a",
  ["é"]="e",["ê"]="e",["ë"]="e",["í"]="i",["ï"]="i",
  ["ó"]="o",["õ"]="o",["ô"]="o",["ö"]="o",["ú"]="u",["ü"]="u",["ç"]="c",
  ["Á"]="A",["À"]="A",["Ã"]="A",["Â"]="A",["É"]="E",["Ê"]="E",
  ["Í"]="I",["Ó"]="O",["Õ"]="O",["Ô"]="O",["Ú"]="U",["Ç"]="C"
}
local function ascii(s)
  s=tostring(s or "")
  for a,b in pairs(accents) do s=s:gsub(a,b) end
  return s:gsub("[^%c%g ]","?")
end

local function findWirelessModem()
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name)=="modem" then
      local p=peripheral.wrap(name)
      if p and p.isWireless then
        local ok,res=pcall(p.isWireless)
        if ok and res then return p,name end
      end
    end
  end
  return nil,nil
end

local monitor, monitorName = peripheral.find("monitor")
local chatBox, chatName = peripheral.find("chatBox")
local speaker, speakerName = peripheral.find("speaker")
local modem, modemName = findWirelessModem()

if not monitor then error("BLUMA: Advanced Monitor nao encontrado.") end
if not chatBox then error("BLUMA: Chat Box nao encontrada.") end
if not modem then error("BLUMA: Wireless Modem nao encontrado.") end
if not rednet.isOpen(modemName) then rednet.open(modemName) end
pcall(function() monitor.setTextScale(0.5) end)

local machines={}
local pending={}
local reqCounter=0
local logs={}
local activePage="HOME"
local buttons={}
local lastResponse="BLUMA inicializada."
local lastSpeaker="SYSTEM"

local minerCfg={
  width=64,length=64,depth=64,
  unloadAt=14,autoUnload=true,returnWhenFull=true,
  resumeAfterUnload=true,fuelReserve=500,
  returnWhenDone=true,pauseIfBlocked=true
}

local function addLog(text)
  local t=os.date("%H:%M:%S")
  logs[#logs+1]=t.."  "..ascii(text)
  while #logs>80 do table.remove(logs,1) end
end

local function sendPublic(text)
  text=ascii(text)
  local tries={
    function() return chatBox.sendMessage(text,"BLUMA","[]","&b") end,
    function() return chatBox.sendMessage(text,"BLUMA") end,
    function() return chatBox.sendMessage(text) end
  }
  for _,fn in ipairs(tries) do if pcall(fn) then return true end end
  return false
end

local function sendPrivate(user,text)
  text=ascii(text)
  local tries={
    function() return chatBox.sendMessageToPlayer(text,user,"BLUMA","[]","&b") end,
    function() return chatBox.sendMessageToPlayer(text,user,"BLUMA") end,
    function() return chatBox.sendMessageToPlayer(text,user) end
  }
  for _,fn in ipairs(tries) do if pcall(fn) then return true end end
  return false
end

local function online(id)
  local m=machines[id]
  return m and (now()-(m.lastSeen or 0) <= (cfg.HEARTBEAT_TIMEOUT or 7))
end

local function machineLine(id)
  local m=machines[id]
  if not online(id) then return id.." OFFLINE" end
  local s=id.." "..tostring(m.state or "ONLINE")
  if m.progress~=nil then s=s.." "..tostring(m.progress).."%" end
  if m.fuel~=nil then s=s.." fuel="..tostring(m.fuel) end
  return s
end

local function nextReq()
  reqCounter=reqCounter+1
  return tostring(os.getComputerID()).."-"..tostring(os.epoch("utc")).."-"..reqCounter
end

local function sendWait(id,packet,timeout)
  local m=machines[id]
  if not online(id) or not m.sender then return false,id.." esta offline." end
  local req=nextReq()
  packet.requestId=req
  packet.id=id
  pending[req]=false
  rednet.send(m.sender,packet,cfg.PROTOCOL)
  local deadline=now()+(timeout or 4)
  while now()<deadline do
    local result=pending[req]
    if type(result)=="table" then
      pending[req]=nil
      return result.ok~=false,result.message or "OK"
    end
    sleep(0.05)
  end
  pending[req]=nil
  return false,"Sem confirmacao de "..id.."."
end

local function command(id,action)
  addLog(cfg.OWNER.." -> "..id.." "..action)
  local ok,msg=sendWait(id,{type="COMMAND",action=action},5)
  addLog(id.." -> "..tostring(msg))
  return ok,msg
end

local function saveMinerConfig()
  local ok,msg=sendWait(cfg.MINER_ID,{type="CONFIG",config=minerCfg},5)
  addLog("CONFIG -> "..tostring(msg))
  return ok,msg
end

local function discover()
  rednet.broadcast({type="DISCOVER",from="BLUMA-CORE"},cfg.PROTOCOL)
  addLog("Discovery broadcast enviado")
end

local function machineRelated(message)
  local words={"miner","mineradora","mining","turtle","craft","crafter","crafting","fuel","combust","invent","slot","maquina","machine"}
  for _,w in ipairs(words) do if contains(message,w) then return true end end
  return false
end

local function groq(user,message,withTelemetry)
  if not http then return nil,"HTTP API indisponivel." end
  if not cfg.GROQ_KEY or cfg.GROQ_KEY=="" then return nil,"Groq API key ausente." end

  local system=[[You are BLUMA, a calm, capable secretary and operations assistant inside Minecraft.
Answer naturally in the user's language. Portuguese from Brazil should sound natural and conversational.
Do not mention machines, mining, telemetry, or offline status unless the user asks about them or it is directly relevant.
Never invent machine state, telemetry, or command success.
Keep routine answers concise.]]
  if withTelemetry then
    system=system.."\nAuthoritative machine telemetry:\n"..machineLine(cfg.MINER_ID).."\n"..machineLine(cfg.CRAFTER_ID)
  end

  local payload=textutils.serializeJSON({
    model=cfg.GROQ_MODEL,
    temperature=0.45,
    max_tokens=350,
    messages={{role="system",content=system},{role="user",content=message}}
  })

  local response,err,errResp=http.post(
    "https://api.groq.com/openai/v1/chat/completions",
    payload,
    { ["Authorization"]="Bearer "..cfg.GROQ_KEY,["Content-Type"]="application/json" }
  )
  if not response then
    local detail=tostring(err or "HTTP failure")
    if errResp then
      local ok,extra=pcall(function() return errResp.readAll() end)
      pcall(function() errResp.close() end)
      if ok and extra and extra~="" then detail=detail.." | "..extra end
    end
    return nil,detail
  end
  local raw=response.readAll(); response.close()
  local data=textutils.unserializeJSON(raw)
  local c=data and data.choices and data.choices[1]
  c=c and c.message and c.message.content
  if not c then return nil,"Resposta invalida da Groq." end
  return trim(c),nil
end

local function parseCommand(message)
  local m=lower(message)
  local miner=contains(m,"miner") or contains(m,"mineradora")
  local craft=contains(m,"craft") or contains(m,"crafter")
  if miner then
    if contains(m,"pausa") or contains(m,"pause") then return cfg.MINER_ID,"PAUSE" end
    if contains(m,"retoma") or contains(m,"resume") or contains(m,"continua") then return cfg.MINER_ID,"RESUME" end
    if contains(m,"volta") or contains(m,"retorna") or contains(m,"return") then return cfg.MINER_ID,"RETURN" end
    if contains(m,"aborta") or contains(m,"abort") or contains(m,"cancela") then return cfg.MINER_ID,"ABORT" end
    if contains(m,"reset") then return cfg.MINER_ID,"RESET" end
    if contains(m,"inicia") or contains(m,"start") or contains(m,"comeca") then return cfg.MINER_ID,"START" end
  end
  if craft then
    if contains(m,"pausa") or contains(m,"pause") then return cfg.CRAFTER_ID,"PAUSE" end
    if contains(m,"retoma") or contains(m,"resume") or contains(m,"continua") then return cfg.CRAFTER_ID,"RESUME" end
    if contains(m,"para") or contains(m,"stop") then return cfg.CRAFTER_ID,"STOP" end
    if contains(m,"inicia") or contains(m,"start") then return cfg.CRAFTER_ID,"START" end
  end
  return nil,nil
end

local function processChat(user,message)
  if not contains(message,"bluma") then return end
  lastSpeaker=user
  addLog(user.." -> BLUMA: "..message)

  local related=machineRelated(message)
  if related and not isOwner(user) then
    lastResponse="Essa parte do sistema e restrita ao operador."
    sendPrivate(user,lastResponse)
    return
  end

  local id,action=parseCommand(message)
  if id and action then
    local ok,msg=command(id,action)
    lastResponse=msg
    sendPrivate(user,msg)
    return
  end

  if related and isOwner(user) and (contains(message,"status") or contains(message,"como esta") or contains(message,"como ta")) then
    lastResponse=machineLine(cfg.MINER_ID).." | "..machineLine(cfg.CRAFTER_ID)
    sendPrivate(user,lastResponse)
    return
  end

  local answer,err=groq(user,message,related)
  lastResponse=answer or ("Falha no nucleo de linguagem: "..tostring(err))
  if related then sendPrivate(user,lastResponse) else sendPublic(lastResponse) end
end

local function wrap(text,width)
  local out,line={},""
  for word in ascii(text):gmatch("%S+") do
    if line=="" then line=word
    elseif #line+#word+1<=width then line=line.." "..word
    else out[#out+1]=line; line=word end
  end
  if line~="" then out[#out+1]=line end
  return out
end

local function txt(x,y,s,fg,bg)
  local w,h=monitor.getSize()
  if x<1 or y<1 or x>w or y>h then return end
  monitor.setCursorPos(x,y)
  monitor.setTextColor(fg or colors.white)
  monitor.setBackgroundColor(bg or colors.black)
  s=tostring(s or "")
  if #s>w-x+1 then s=s:sub(1,w-x+1) end
  monitor.write(s)
end

local function fill(x,y,w,h,bg)
  local mw,mh=monitor.getSize()
  local line=string.rep(" ",math.max(0,math.min(w,mw-x+1)))
  for yy=y,math.min(y+h-1,mh) do txt(x,yy,line,colors.white,bg) end
end

local function button(x,y,w,label,bg,action)
  local mw,mh=monitor.getSize()
  if y>mh or x>mw then return end
  local ww=math.min(w,mw-x+1)
  if ww<3 then return end
  fill(x,y,ww,1,bg)
  local label2=" "..label.." "
  local sx=x+math.max(0,math.floor((ww-#label2)/2))
  txt(sx,y,label2,colors.white,bg)
  buttons[#buttons+1]={x1=x,y1=y,x2=x+ww-1,y2=y,action=action}
end

local function bar(x,y,w,pct,color)
  pct=clamp(tonumber(pct) or 0,0,100)
  fill(x,y,w,1,colors.gray)
  local on=math.floor(w*pct/100)
  if on>0 then fill(x,y,on,1,color or colors.cyan) end
end

local function stateColor(state)
  state=upper and upper(state) or string.upper(tostring(state or ""))
  if state=="MINING" or state=="CRAFTING" or state=="ONLINE" then return colors.lime end
  if state=="PAUSED" or state=="RETURNED" or state=="FULL" then return colors.orange end
  if state=="OFFLINE" or state=="ERROR" or state=="BLOCKED" or state=="LOW_FUEL" then return colors.red end
  return colors.lightBlue
end

local function drawHeader(title)
  local w,h=monitor.getSize()
  fill(1,1,w,3,colors.black)
  txt(2,1,"BLUMA // "..title,colors.cyan,colors.black)
  txt(math.max(2,w-12),1,"CORE ONLINE",colors.lime,colors.black)
  txt(2,2,"SECRETARY & OPERATIONS CONTROL",colors.gray,colors.black)
  fill(1,3,w,1,colors.cyan)
end

local function drawNav()
  local w,h=monitor.getSize()
  local labels={{"HOME","PAGE_HOME"},{"MINER","PAGE_MINER"},{"CONFIG","PAGE_CONFIG"},{"SYSTEM","PAGE_SYSTEM"},{"LOG","PAGE_LOG"}}
  local bw=math.max(8,math.floor((w-2)/#labels))
  local x=1
  for _,item in ipairs(labels) do
    local bg=(activePage==item[1]) and colors.blue or colors.gray
    button(x,h,bw,item[1],bg,item[2])
    x=x+bw
  end
end

local function machineCard(x,y,w,id)
  fill(x,y,w,6,colors.black)
  txt(x+1,y,id,colors.cyan,colors.black)
  local m=machines[id]
  if not online(id) then
    txt(x+1,y+1,"OFFLINE",colors.red,colors.black)
    txt(x+1,y+2,"Waiting for heartbeat",colors.gray,colors.black)
    return
  end
  txt(x+1,y+1,tostring(m.state or "ONLINE"),stateColor(m.state),colors.black)
  if id==cfg.MINER_ID then
    txt(x+1,y+2,"Progress  "..tostring(m.progress or 0).."%",colors.white,colors.black)
    bar(x+1,y+3,w-2,m.progress or 0,colors.cyan)
    txt(x+1,y+4,"Fuel "..tostring(m.fuel or "?").."  Slots "..tostring(m.usedSlots or "?").."/16",colors.gray,colors.black)
  else
    txt(x+1,y+2,"Crafted  "..tostring(m.crafted or 0),colors.white,colors.black)
    txt(x+1,y+3,"Recipe   DEEPSLATE BRICKS",colors.gray,colors.black)
  end
end

local function drawHome()
  drawHeader("CONTROL CENTER")
  local w,h=monitor.getSize()
  txt(2,5,"SYSTEM",colors.cyan,colors.black)
  txt(2,7,"GROQ",colors.gray,colors.black); txt(14,7,http and "READY" or "MISSING",http and colors.lime or colors.red,colors.black)
  txt(2,8,"REDNET",colors.gray,colors.black); txt(14,8,modemName or "MISSING",modemName and colors.lime or colors.red,colors.black)
  txt(2,9,"CHAT",colors.gray,colors.black); txt(14,9,chatName or "MISSING",chatName and colors.lime or colors.red,colors.black)
  txt(2,10,"SPEAKER",colors.gray,colors.black); txt(14,10,speakerName or "OPTIONAL",speakerName and colors.lime or colors.orange,colors.black)

  local cardX=math.max(27,math.floor(w*0.42))
  machineCard(cardX,5,w-cardX,cfg.MINER_ID)
  machineCard(cardX,12,w-cardX,cfg.CRAFTER_ID)

  txt(2,13,"LAST RESPONSE",colors.cyan,colors.black)
  local lines=wrap(lastResponse,math.max(18,cardX-5))
  for i=1,math.min(#lines,5) do txt(2,13+i,lines[i],colors.white,colors.black) end

  txt(2,20,"ACTIVITY",colors.cyan,colors.black)
  local start=math.max(1,#logs-4)
  local yy=21
  for i=start,#logs do txt(2,yy,logs[i],colors.gray,colors.black); yy=yy+1 end
  drawNav()
end

local function drawMiner()
  drawHeader("MINER-01")
  local w,h=monitor.getSize()
  local m=machines[cfg.MINER_ID]
  local state=online(cfg.MINER_ID) and tostring(m.state or "ONLINE") or "OFFLINE"
  txt(2,5,"STATE",colors.gray,colors.black); txt(14,5,state,stateColor(state),colors.black)
  if online(cfg.MINER_ID) then
    txt(2,7,"JOB",colors.gray,colors.black); txt(14,7,tostring(m.width or "?").." x "..tostring(m.length or "?").." x "..tostring(m.depth or "?"),colors.white,colors.black)
    txt(2,8,"PROGRESS",colors.gray,colors.black); txt(14,8,tostring(m.progress or 0).."%",colors.white,colors.black)
    bar(2,10,math.max(10,w-4),m.progress or 0,colors.cyan)
    txt(2,12,"POSITION",colors.gray,colors.black); txt(14,12,"X "..tostring(m.x or "?").."  Y "..tostring(m.y or "?").."  Z "..tostring(m.z or "?"),colors.white,colors.black)
    txt(2,13,"LAYER",colors.gray,colors.black); txt(14,13,tostring((m.layer or 0)+1).." / "..tostring(m.depth or "?"),colors.white,colors.black)
    txt(2,14,"FUEL",colors.gray,colors.black); txt(14,14,tostring(m.fuel or "?"),colors.white,colors.black)
    txt(2,15,"STORAGE",colors.gray,colors.black); txt(14,15,tostring(m.usedSlots or "?").." / 16",colors.white,colors.black)
    txt(2,16,"BLOCKS",colors.gray,colors.black); txt(14,16,tostring(m.blocks or 0),colors.white,colors.black)
  else
    txt(2,7,"MINER-01 is not sending heartbeat.",colors.red,colors.black)
    txt(2,8,"Install BLUMA on the Mining Turtle and keep it powered.",colors.gray,colors.black)
  end
  local y=19
  button(2,y,9,"START",colors.green,"MINER_START")
  button(12,y,9,"PAUSE",colors.orange,"MINER_PAUSE")
  button(22,y,9,"RESUME",colors.blue,"MINER_RESUME")
  button(32,y,10,"RETURN",colors.purple,"MINER_RETURN")
  button(43,y,9,"ABORT",colors.red,"MINER_ABORT")
  button(53,y,8,"RESET",colors.gray,"MINER_RESET")
  button(2,y+2,14,"DISCOVER",colors.lightBlue,"DISCOVER")
  drawNav()
end

local function cfgRow(y,label,value,minus,plus)
  txt(2,y,label,colors.gray,colors.black)
  button(25,y,5,"-",colors.gray,minus)
  txt(32,y,tostring(value),colors.white,colors.black)
  button(43,y,5,"+",colors.gray,plus)
end

local function toggleRow(y,label,value,action)
  txt(2,y,label,colors.gray,colors.black)
  button(25,y,12,value and "ON" or "OFF",value and colors.green or colors.red,action)
end

local function drawConfig()
  drawHeader("MINER CONFIG")
  txt(2,5,"JOB GEOMETRY",colors.cyan,colors.black)
  cfgRow(7,"Width",minerCfg.width,"CFG_W_MINUS","CFG_W_PLUS")
  cfgRow(8,"Length",minerCfg.length,"CFG_L_MINUS","CFG_L_PLUS")
  cfgRow(9,"Depth",minerCfg.depth,"CFG_D_MINUS","CFG_D_PLUS")
  txt(2,11,"STORAGE & SAFETY",colors.cyan,colors.black)
  cfgRow(13,"Unload at slots",minerCfg.unloadAt,"CFG_U_MINUS","CFG_U_PLUS")
  cfgRow(14,"Fuel reserve",minerCfg.fuelReserve,"CFG_F_MINUS","CFG_F_PLUS")
  toggleRow(16,"Auto unload",minerCfg.autoUnload,"CFG_AUTO_UNLOAD")
  toggleRow(17,"Return when full",minerCfg.returnWhenFull,"CFG_RETURN_FULL")
  toggleRow(18,"Resume after unload",minerCfg.resumeAfterUnload,"CFG_RESUME_UNLOAD")
  toggleRow(19,"Return when done",minerCfg.returnWhenDone,"CFG_RETURN_DONE")
  toggleRow(20,"Pause if blocked",minerCfg.pauseIfBlocked,"CFG_PAUSE_BLOCKED")
  button(2,23,16,"SAVE CONFIG",colors.blue,"CFG_SAVE")
  button(20,23,16,"SAVE + START",colors.green,"CFG_START")
  drawNav()
end

local function drawSystem()
  drawHeader("SYSTEM")
  local uptime=math.floor((os.epoch("utc")-startedAt)/1000)
  txt(2,5,"CORE",colors.cyan,colors.black)
  txt(2,7,"Uptime",colors.gray,colors.black); txt(18,7,tostring(uptime).."s",colors.white,colors.black)
  txt(2,8,"Computer ID",colors.gray,colors.black); txt(18,8,tostring(os.getComputerID()),colors.white,colors.black)
  txt(2,9,"Protocol",colors.gray,colors.black); txt(18,9,cfg.PROTOCOL,colors.white,colors.black)
  txt(2,11,"PERIPHERALS",colors.cyan,colors.black)
  txt(2,13,"Monitor",colors.gray,colors.black); txt(18,13,monitorName or "MISSING",monitorName and colors.lime or colors.red,colors.black)
  txt(2,14,"Chat Box",colors.gray,colors.black); txt(18,14,chatName or "MISSING",chatName and colors.lime or colors.red,colors.black)
  txt(2,15,"Wireless Modem",colors.gray,colors.black); txt(18,15,modemName or "MISSING",modemName and colors.lime or colors.red,colors.black)
  txt(2,16,"Speaker",colors.gray,colors.black); txt(18,16,speakerName or "OPTIONAL",speakerName and colors.lime or colors.orange,colors.black)
  txt(2,18,"MACHINES",colors.cyan,colors.black)
  txt(2,20,cfg.MINER_ID,colors.gray,colors.black); txt(18,20,online(cfg.MINER_ID) and "ONLINE" or "OFFLINE",online(cfg.MINER_ID) and colors.lime or colors.red,colors.black)
  txt(2,21,cfg.CRAFTER_ID,colors.gray,colors.black); txt(18,21,online(cfg.CRAFTER_ID) and "ONLINE" or "OFFLINE",online(cfg.CRAFTER_ID) and colors.lime or colors.red,colors.black)
  button(2,23,14,"DISCOVER",colors.lightBlue,"DISCOVER")
  drawNav()
end

local function drawLog()
  drawHeader("EVENT LOG")
  local w,h=monitor.getSize()
  local maxRows=math.max(1,h-5)
  local start=math.max(1,#logs-maxRows+1)
  local y=5
  for i=start,#logs do txt(2,y,logs[i],colors.gray,colors.black); y=y+1 end
  drawNav()
end

local function redraw()
  buttons={}
  monitor.setBackgroundColor(colors.black); monitor.clear()
  if activePage=="HOME" then drawHome()
  elseif activePage=="MINER" then drawMiner()
  elseif activePage=="CONFIG" then drawConfig()
  elseif activePage=="SYSTEM" then drawSystem()
  else drawLog() end
end

local function setResponse(msg)
  lastResponse=tostring(msg or "")
  redraw()
end

local function hit(x,y)
  for _,b in ipairs(buttons) do
    if x>=b.x1 and x<=b.x2 and y>=b.y1 and y<=b.y2 then return b.action end
  end
end

local function handleAction(a)
  if not a then return end
  if a:sub(1,5)=="PAGE_" then activePage=a:sub(6); redraw(); return end
  if a=="DISCOVER" then discover(); setResponse("Buscando maquinas BLUMA..."); return end
  if a=="MINER_START" then local _,m=command(cfg.MINER_ID,"START"); setResponse(m); return end
  if a=="MINER_PAUSE" then local _,m=command(cfg.MINER_ID,"PAUSE"); setResponse(m); return end
  if a=="MINER_RESUME" then local _,m=command(cfg.MINER_ID,"RESUME"); setResponse(m); return end
  if a=="MINER_RETURN" then local _,m=command(cfg.MINER_ID,"RETURN"); setResponse(m); return end
  if a=="MINER_ABORT" then local _,m=command(cfg.MINER_ID,"ABORT"); setResponse(m); return end
  if a=="MINER_RESET" then local _,m=command(cfg.MINER_ID,"RESET"); setResponse(m); return end
  if a=="CFG_W_MINUS" then minerCfg.width=clamp(minerCfg.width-8,1,512)
  elseif a=="CFG_W_PLUS" then minerCfg.width=clamp(minerCfg.width+8,1,512)
  elseif a=="CFG_L_MINUS" then minerCfg.length=clamp(minerCfg.length-8,1,512)
  elseif a=="CFG_L_PLUS" then minerCfg.length=clamp(minerCfg.length+8,1,512)
  elseif a=="CFG_D_MINUS" then minerCfg.depth=clamp(minerCfg.depth-8,1,512)
  elseif a=="CFG_D_PLUS" then minerCfg.depth=clamp(minerCfg.depth+8,1,512)
  elseif a=="CFG_U_MINUS" then minerCfg.unloadAt=clamp(minerCfg.unloadAt-1,4,16)
  elseif a=="CFG_U_PLUS" then minerCfg.unloadAt=clamp(minerCfg.unloadAt+1,4,16)
  elseif a=="CFG_F_MINUS" then minerCfg.fuelReserve=clamp(minerCfg.fuelReserve-100,0,100000)
  elseif a=="CFG_F_PLUS" then minerCfg.fuelReserve=clamp(minerCfg.fuelReserve+100,0,100000)
  elseif a=="CFG_AUTO_UNLOAD" then minerCfg.autoUnload=not minerCfg.autoUnload
  elseif a=="CFG_RETURN_FULL" then minerCfg.returnWhenFull=not minerCfg.returnWhenFull
  elseif a=="CFG_RESUME_UNLOAD" then minerCfg.resumeAfterUnload=not minerCfg.resumeAfterUnload
  elseif a=="CFG_RETURN_DONE" then minerCfg.returnWhenDone=not minerCfg.returnWhenDone
  elseif a=="CFG_PAUSE_BLOCKED" then minerCfg.pauseIfBlocked=not minerCfg.pauseIfBlocked
  elseif a=="CFG_SAVE" then local _,m=saveMinerConfig(); setResponse(m); return
  elseif a=="CFG_START" then
    local ok,m=saveMinerConfig()
    if ok then local _,m2=command(cfg.MINER_ID,"START"); setResponse(m2) else setResponse(m) end
    return
  end
  redraw()
end

local function rednetLoop()
  while true do
    local _,sender,p,protocol=os.pullEvent("rednet_message")
    if protocol==cfg.PROTOCOL and type(p)=="table" then
      if p.type=="HELLO" or p.type=="HEARTBEAT" or p.type=="STATUS" then
        if p.id then
          p.sender=sender; p.lastSeen=now(); machines[p.id]=p
          if p.id==cfg.MINER_ID and type(p.config)=="table" then
            for k,v in pairs(p.config) do if minerCfg[k]~=nil then minerCfg[k]=v end end
          end
          if p.type=="HELLO" then
            rednet.send(sender,{type="WELCOME",from="BLUMA-CORE"},cfg.PROTOCOL)
            addLog(p.id.." connected")
          end
        end
      elseif p.type=="ACK" and p.requestId then
        pending[p.requestId]={ok=p.ok~=false,message=p.message or "OK"}
      end
      redraw()
    end
  end
end

local function chatLoop()
  while true do
    local e={os.pullEvent("chat")}
    local user=e[2] or "player"
    local message=e[6] or e[3] or ""
    local ok,err=pcall(processChat,user,message)
    if not ok then
      addLog("Chat error: "..tostring(err))
      sendPrivate(user,"BLUMA encontrou um erro interno: "..tostring(err))
    end
    redraw()
  end
end

local function touchLoop()
  while true do
    local _,_,x,y=os.pullEvent("monitor_touch")
    local ok,err=pcall(handleAction,hit(x,y))
    if not ok then addLog("UI error: "..tostring(err)); setResponse("Erro no painel: "..tostring(err)) end
  end
end

local function refreshLoop()
  while true do redraw(); sleep(0.5) end
end

addLog("BLUMA Core online")
discover()
redraw()
sendPublic("BLUMA online.")
parallel.waitForAll(rednetLoop,chatLoop,touchLoop,refreshLoop)
]=]
local MINER_DATA=[=[-- BLUMA MINER-01 V5
-- Advanced Mining Turtle + Wireless Modem

local PROTOCOL="BLUMA"
local ID="MINER-01"
local STATE_FILE=".bluma_miner_state"
local CFG_FILE=".bluma_miner_config"

local cfg={
  width=64,length=64,depth=64,
  unloadAt=14,autoUnload=true,returnWhenFull=true,
  resumeAfterUnload=true,fuelReserve=500,
  returnWhenDone=true,pauseIfBlocked=true
}
local s={
  state="STANDBY",x=0,y=0,z=0,dir=0,
  layer=0,row=0,col=0,blocks=0,entered=false,
  paused=false,abort=false,returnRequested=false,resumeTarget=nil
}
local coreId=nil

local function readJSON(path)
  if not fs.exists(path) then return nil end
  local h=fs.open(path,"r"); if not h then return nil end
  local raw=h.readAll(); h.close()
  return textutils.unserializeJSON(raw)
end
local function writeJSON(path,data)
  local h=fs.open(path,"w"); if not h then return false end
  h.write(textutils.serializeJSON(data)); h.close(); return true
end

local oldCfg=readJSON(CFG_FILE); if type(oldCfg)=="table" then for k,v in pairs(oldCfg) do if cfg[k]~=nil then cfg[k]=v end end end
local oldState=readJSON(STATE_FILE); if type(oldState)=="table" then for k,v in pairs(oldState) do if s[k]~=nil then s[k]=v end end end
if s.state=="MINING" or s.state=="RETURNING" or s.state=="UNLOADING" then s.state="PAUSED"; s.paused=true end

local function saveCfg() writeJSON(CFG_FILE,cfg) end
local function saveState() writeJSON(STATE_FILE,s) end
local function nowFuel() return turtle.getFuelLevel() end
local function usedSlots() local n=0 for i=1,16 do if turtle.getItemCount(i)>0 then n=n+1 end end return n end
local function progress()
  local total=math.max(1,cfg.width*cfg.length*cfg.depth)
  local done=(s.layer*cfg.width*cfg.length)+(s.row*cfg.width)+s.col
  return math.floor(math.min(100,(done/total)*1000))/10
end

local function findWirelessModem()
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name)=="modem" then
      local m=peripheral.wrap(name)
      if m and m.isWireless then local ok,res=pcall(m.isWireless); if ok and res then return m,name end end
    end
  end
end
local modem,modemName=findWirelessModem()
if not modem then error("BLUMA MINER: Wireless Modem nao encontrado.") end
if not rednet.isOpen(modemName) then rednet.open(modemName) end

local function payload(tp,msg,req,ok)
  return {
    type=tp,id=ID,state=s.state,progress=progress(),fuel=nowFuel(),usedSlots=usedSlots(),blocks=s.blocks,
    x=s.x,y=s.y,z=s.z,dir=s.dir,layer=s.layer,row=s.row,col=s.col,
    width=cfg.width,length=cfg.length,depth=cfg.depth,config=cfg,
    message=msg,requestId=req,ok=ok
  }
end
local function send(tp,msg,req,ok)
  local p=payload(tp,msg,req,ok)
  if coreId then rednet.send(coreId,p,PROTOCOL) else rednet.broadcast(p,PROTOCOL) end
end

local function turnRight() turtle.turnRight(); s.dir=(s.dir+1)%4; saveState() end
local function turnLeft() turtle.turnLeft(); s.dir=(s.dir+3)%4; saveState() end
local function face(d)
  local diff=(d-s.dir)%4
  if diff==1 then turnRight()
  elseif diff==2 then turnRight(); turnRight()
  elseif diff==3 then turnLeft() end
end

local function blocked(reason)
  s.state="BLOCKED"; s.paused=true; saveState(); send("STATUS",reason)
end

local function digForward()
  if turtle.detect() then if turtle.dig() then s.blocks=s.blocks+1 end end
end
local function forward()
  digForward()
  for _=1,25 do
    if turtle.forward() then
      if s.dir==0 then s.z=s.z-1 elseif s.dir==1 then s.x=s.x+1 elseif s.dir==2 then s.z=s.z+1 else s.x=s.x-1 end
      saveState(); return true
    end
    turtle.attack(); digForward(); sleep(0.1)
  end
  blocked("Caminho bloqueado em frente."); return false
end
local function up()
  if turtle.detectUp() and turtle.digUp() then s.blocks=s.blocks+1 end
  for _=1,25 do
    if turtle.up() then s.y=s.y+1; saveState(); return true end
    turtle.attackUp(); turtle.digUp(); sleep(0.1)
  end
  blocked("Caminho bloqueado acima."); return false
end
local function down()
  if turtle.detectDown() and turtle.digDown() then s.blocks=s.blocks+1 end
  for _=1,25 do
    if turtle.down() then s.y=s.y-1; saveState(); return true end
    turtle.attackDown(); turtle.digDown(); sleep(0.1)
  end
  blocked("Caminho bloqueado abaixo."); return false
end

local function moveX(target)
  if s.x<target then face(1); while s.x<target do if not forward() then return false end end
  elseif s.x>target then face(3); while s.x>target do if not forward() then return false end end end
  return true
end
local function moveZ(target)
  if s.z<target then face(2); while s.z<target do if not forward() then return false end end
  elseif s.z>target then face(0); while s.z>target do if not forward() then return false end end end
  return true
end
local function moveY(target)
  while s.y<target do if not up() then return false end end
  while s.y>target do if not down() then return false end end
  return true
end
local function navigate(x,y,z,d)
  if not moveY(0) then return false end
  if not moveX(x) then return false end
  if not moveZ(z) then return false end
  if not moveY(y) then return false end
  if d~=nil then face(d) end
  return true
end

local function dropAllDown()
  local before=usedSlots()
  for i=1,16 do
    if turtle.getItemCount(i)>0 then turtle.select(i); turtle.dropDown() end
  end
  turtle.select(1)
  local after=usedSlots()
  return before-after,after
end

local function unloadAndReturn()
  local target={x=s.x,y=s.y,z=s.z,dir=s.dir}
  local oldState=s.state
  s.state="UNLOADING"; saveState(); send("STATUS","Retornando para descarregar.")
  if not navigate(0,0,0,0) then return false end
  local dropped,left=dropAllDown()
  if left>0 then
    s.state="FULL"; s.paused=true; saveState(); send("STATUS","Bau de descarga cheio ou ausente.")
    return false
  end
  if not cfg.resumeAfterUnload then
    s.state="RETURNED"; s.resumeTarget=target; saveState(); send("STATUS","Descarga concluida; aguardando RESUME.")
    return false
  end
  if not navigate(target.x,target.y,target.z,target.dir) then return false end
  s.state=oldState=="MINING" and "MINING" or oldState; saveState(); send("STATUS","Descarga concluida; trabalho retomado.")
  return true
end

local function fuelLow()
  local f=nowFuel()
  if type(f)=="string" then return false end
  return f < (cfg.fuelReserve or 0)
end

local function serviceChecks()
  if s.abort then s.state="ABORTED"; s.abort=false; s.paused=false; saveState(); send("STATUS","Job abortado."); return false end
  if s.returnRequested then
    s.resumeTarget={x=s.x,y=s.y,z=s.z,dir=s.dir}
    s.returnRequested=false; s.state="RETURNING"; saveState()
    if navigate(0,0,0,0) then s.state="RETURNED"; saveState(); send("STATUS","Retornei para HOME; progresso preservado.") end
    return false
  end
  if fuelLow() then s.state="LOW_FUEL"; s.paused=true; saveState(); send("STATUS","Combustivel abaixo da reserva.") end
  while s.paused do
    os.pullEvent("bluma_miner_wake")
    if s.abort or s.returnRequested then return serviceChecks() end
  end
  if cfg.autoUnload and usedSlots()>=cfg.unloadAt then
    if cfg.returnWhenFull then return unloadAndReturn() end
    s.state="FULL"; s.paused=true; saveState(); send("STATUS","Inventario atingiu o limite."); return serviceChecks()
  end
  return true
end

local function resetJob()
  s.state="STANDBY"; s.layer=0; s.row=0; s.col=0; s.blocks=0; s.entered=false
  s.paused=false; s.abort=false; s.returnRequested=false; s.resumeTarget=nil
  saveState()
end

local function resumeFromHome()
  if s.state=="RETURNED" and type(s.resumeTarget)=="table" then
    local t=s.resumeTarget
    s.state="RETURNING"; saveState()
    if navigate(t.x,t.y,t.z,t.dir) then s.resumeTarget=nil; s.state="MINING"; s.paused=false; saveState(); return true end
    return false
  end
  return true
end

local function mineJob()
  if s.state=="RETURNED" then if not resumeFromHome() then return end end
  s.state="MINING"; s.paused=false; saveState(); send("STATUS","Mineracao iniciada.")

  if not s.entered then
    face(0)
    if not forward() then return end
    turnRight()
    s.entered=true; saveState()
  end

  local firstLayer=s.layer
  for layer=firstLayer,cfg.depth-1 do
    s.layer=layer
    local firstRow=(layer==firstLayer) and s.row or 0
    for row=firstRow,cfg.length-1 do
      s.row=row
      local expected=(row%2==0) and 1 or 3
      face(expected)
      local firstCol=(layer==firstLayer and row==firstRow) and s.col or 0
      for col=firstCol,cfg.width-1 do
        s.col=col
        if not serviceChecks() then return end
        if col<cfg.width-1 then if not forward() then return end end
      end
      s.col=0
      if row<cfg.length-1 then
        face(0); if not forward() then return end
      end
      saveState()
    end
    s.row=0; s.col=0
    if layer<cfg.depth-1 then
      if not navigate(0,s.y,-1,0) then return end
      if not down() then return end
      turnRight()
    end
    saveState()
  end

  if cfg.returnWhenDone then navigate(0,0,0,0) end
  s.state="FINISHED"; s.paused=false; saveState(); send("STATUS","Job concluido.")
end

local function validConfig(c)
  if type(c)~="table" then return false,"Config invalida." end
  local numeric={"width","length","depth","unloadAt","fuelReserve"}
  for _,k in ipairs(numeric) do if type(c[k])~="number" then return false,"Campo invalido: "..k end end
  if c.width<1 or c.width>512 or c.length<1 or c.length>512 or c.depth<1 or c.depth>512 then return false,"Dimensoes fora do limite 1..512." end
  if c.unloadAt<4 or c.unloadAt>16 then return false,"unloadAt deve ficar entre 4 e 16." end
  return true
end

local function handlePacket(sender,p)
  if type(p)~="table" then return end
  if p.type=="DISCOVER" then coreId=sender; rednet.send(sender,payload("HELLO","MINER-01 ready"),PROTOCOL); return end
  if p.type=="WELCOME" then coreId=sender; return end
  if p.id and p.id~=ID then return end

  if p.type=="CONFIG" then
    coreId=sender
    local ok,msg=validConfig(p.config)
    if ok then
      if s.state=="MINING" then
        ok=false; msg="Pause/return the current job before changing geometry."
      else
        for k,v in pairs(p.config) do if cfg[k]~=nil then cfg[k]=v end end
        saveCfg(); msg="Configuracao salva em MINER-01."
      end
    end
    rednet.send(sender,payload("ACK",msg,p.requestId,ok),PROTOCOL)
    return
  end

  if p.type~="COMMAND" then return end
  coreId=sender
  local a=string.upper(tostring(p.action or "")); local ok=true; local msg="OK"
  if a=="START" then
    if s.state=="FINISHED" or s.state=="ABORTED" then
      if s.x==0 and s.y==0 and s.z==0 then resetJob() else ok=false; msg="Use RETURN antes de reiniciar o job." end
    end
    if ok then
      if s.state=="STANDBY" then s.state="MINING"; s.paused=false; saveState(); os.queueEvent("bluma_miner_start"); msg="Job iniciado."
      elseif s.state=="RETURNED" then s.paused=false; saveState(); os.queueEvent("bluma_miner_start"); msg="Voltando ao ponto salvo para continuar."
      elseif s.state=="PAUSED" or s.state=="FULL" or s.state=="LOW_FUEL" or s.state=="BLOCKED" then s.paused=false; s.state="MINING"; saveState(); os.queueEvent("bluma_miner_wake"); msg="Mineracao retomada."
      else msg="MINER-01 ja esta ativa." end
    end
  elseif a=="PAUSE" then s.paused=true; s.state="PAUSED"; saveState(); msg="MINER-01 pausada."
  elseif a=="RESUME" then
    if s.state=="RETURNED" then s.paused=false; os.queueEvent("bluma_miner_start"); msg="Retornando ao ponto salvo."
    else s.paused=false; s.state="MINING"; saveState(); os.queueEvent("bluma_miner_wake"); msg="MINER-01 retomada." end
  elseif a=="RETURN" then s.returnRequested=true; s.paused=false; saveState(); os.queueEvent("bluma_miner_wake"); msg="Retorno solicitado."
  elseif a=="ABORT" then s.abort=true; s.paused=false; saveState(); os.queueEvent("bluma_miner_wake"); msg="Abort solicitado."
  elseif a=="RESET" then
    if s.state=="MINING" then ok=false; msg="Pause/return before RESET."
    elseif s.x~=0 or s.y~=0 or s.z~=0 then ok=false; msg="MINER-01 precisa estar em HOME para RESET."
    else resetJob(); msg="Job resetado." end
  else ok=false; msg="Comando desconhecido." end
  rednet.send(sender,payload("ACK",msg,p.requestId,ok),PROTOCOL)
end

local function networkLoop()
  local timer=os.startTimer(0.2)
  while true do
    local e={os.pullEventRaw()}
    if e[1]=="rednet_message" and e[4]==PROTOCOL then handlePacket(e[2],e[3])
    elseif e[1]=="timer" and e[2]==timer then send("HEARTBEAT","alive"); timer=os.startTimer(2)
    elseif e[1]=="terminate" then s.state="STOPPED"; saveState(); return end
  end
end

local function minerLoop()
  while true do
    if s.state=="MINING" then mineJob()
    else
      local ev=os.pullEvent()
      if ev=="bluma_miner_start" then mineJob()
      elseif ev=="bluma_miner_wake" and (s.state=="MINING" or s.state=="PAUSED" or s.state=="RETURNED") then mineJob() end
    end
  end
end

local function uiLoop()
  while true do
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1)
    term.setTextColor(colors.cyan); print("BLUMA // MINER-01"); term.setTextColor(colors.white)
    print("STATE   "..s.state)
    print("JOB     "..cfg.width.."x"..cfg.length.."x"..cfg.depth)
    print("PROG    "..progress().."%")
    print("POS     "..s.x..","..s.y..","..s.z)
    print("FUEL    "..tostring(nowFuel()))
    print("SLOTS   "..usedSlots().."/16")
    print("BLOCKS  "..s.blocks)
    print("")
    print("Controlled by BLUMA Core")
    sleep(0.5)
  end
end

send("HELLO","MINER-01 boot")
parallel.waitForAll(networkLoop,minerLoop,uiLoop)
]=]
local CRAFTER_DATA=[=[-- BLUMA CRAFT-01 V5
-- Crafty Turtle recipe: Cobbled Deepslate -> Polished Deepslate -> Deepslate Bricks
-- INPUT container: FRONT. OUTPUT container/hopper: DOWN.

local PROTOCOL="BLUMA"
local ID="CRAFT-01"
local SOURCE="minecraft:cobbled_deepslate"
local MID="minecraft:polished_deepslate"
local OUTPUT="minecraft:deepslate_bricks"
local coreId=nil
local state="STANDBY"
local crafted=0
local paused=false
local stopped=false

if type(turtle.craft)~="function" then error("BLUMA CRAFT: esta Turtle nao possui Crafting Table upgrade.") end

local function findWirelessModem()
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name)=="modem" then
      local m=peripheral.wrap(name)
      if m and m.isWireless then local ok,res=pcall(m.isWireless); if ok and res then return m,name end end
    end
  end
end
local modem,modemName=findWirelessModem()
if modem and not rednet.isOpen(modemName) then rednet.open(modemName) end

local function usedSlots() local n=0 for i=1,16 do if turtle.getItemCount(i)>0 then n=n+1 end end return n end
local function payload(tp,msg,req,ok)
  return {type=tp,id=ID,state=state,crafted=crafted,usedSlots=usedSlots(),recipe="DEEPSLATE_BRICKS",message=msg,requestId=req,ok=ok}
end
local function send(tp,msg,req,ok)
  if not modem then return end
  local p=payload(tp,msg,req,ok)
  if coreId then rednet.send(coreId,p,PROTOCOL) else rednet.broadcast(p,PROTOCOL) end
end

local function item(slot)
  local d=turtle.getItemDetail(slot)
  return d and d.name or nil,d and d.count or 0
end

local function clearToDestination()
  for i=1,16 do
    local name,count=item(i)
    if count>0 then
      turtle.select(i)
      if name==SOURCE then
        if not turtle.drop() then return false,"Input chest in front is full/missing." end
      elseif name==OUTPUT then
        if not turtle.dropDown() then return false,"Output chest below is full/missing." end
      else
        return false,"Unexpected item in slot "..i..": "..tostring(name)
      end
    end
  end
  turtle.select(1)
  return true
end

local function gridFromStack(name)
  local sourceSlot=nil
  for i=1,16 do local n,c=item(i); if n==name and c>=4 then sourceSlot=i; break end end
  if not sourceSlot then return false,"Expected 4x "..name end
  if sourceSlot~=1 then turtle.select(sourceSlot); if not turtle.transferTo(1) then return false,"Cannot move recipe stack to slot 1." end end
  turtle.select(1)
  if turtle.getItemCount(1)<4 then return false,"Not enough recipe items." end
  if not turtle.transferTo(2,1) then return false,"Cannot fill slot 2." end
  turtle.select(1); if not turtle.transferTo(5,1) then return false,"Cannot fill slot 5." end
  turtle.select(1); if not turtle.transferTo(6,1) then return false,"Cannot fill slot 6." end
  return true
end

local function consolidate(name)
  local target=nil
  for i=1,16 do local n,c=item(i); if n==name and c>0 then target=target or i end end
  if not target then return false end
  for i=1,16 do
    if i~=target then local n,c=item(i); if n==name and c>0 then turtle.select(i); turtle.transferTo(target) end end
  end
  if target~=1 then turtle.select(target); turtle.transferTo(1) end
  turtle.select(1)
  return true
end

local function craftOneBatch()
  state="WAITING_INPUT"
  turtle.select(1)
  local ok=turtle.suck(4)
  if not ok then sleep(1); return true end
  local n,c=item(1)
  if n~=SOURCE or c<4 then
    turtle.select(1); turtle.drop()
    state="WRONG_INPUT"; send("STATUS","Input must be cobbled deepslate."); sleep(1); return true
  end

  state="CRAFTING"
  local g,msg=gridFromStack(SOURCE); if not g then return false,msg end
  local c1,e1=turtle.craft(1); if not c1 then return false,"First craft failed: "..tostring(e1) end
  if not consolidate(MID) then return false,"Polished deepslate not found after first craft." end
  local g2,msg2=gridFromStack(MID); if not g2 then return false,msg2 end
  local c2,e2=turtle.craft(1); if not c2 then return false,"Second craft failed: "..tostring(e2) end
  if not consolidate(OUTPUT) then return false,"Deepslate bricks not found after second craft." end

  turtle.select(1)
  if not turtle.dropDown() then state="OUTPUT_FULL"; return false,"Output chest below is full or missing." end
  crafted=crafted+4
  state="CRAFTING"
  send("STATUS","4 deepslate bricks crafted")
  return true
end

local function handle(sender,p)
  if type(p)~="table" then return end
  if p.type=="DISCOVER" then coreId=sender; rednet.send(sender,payload("HELLO","CRAFT-01 ready"),PROTOCOL); return end
  if p.type=="WELCOME" then coreId=sender; return end
  if p.type~="COMMAND" or (p.id and p.id~=ID) then return end
  coreId=sender
  local a=string.upper(tostring(p.action or "")); local ok=true; local msg="OK"
  if a=="PAUSE" then paused=true; state="PAUSED"; msg="CRAFT-01 pausada."
  elseif a=="RESUME" or a=="START" then paused=false; stopped=false; state="CRAFTING"; os.queueEvent("bluma_craft_wake"); msg="CRAFT-01 ativa."
  elseif a=="STOP" then stopped=true; paused=false; state="STOPPED"; os.queueEvent("bluma_craft_wake"); msg="CRAFT-01 parada."
  else ok=false; msg="Comando desconhecido." end
  rednet.send(sender,payload("ACK",msg,p.requestId,ok),PROTOCOL)
end

local function networkLoop()
  if not modem then while true do sleep(10) end end
  local timer=os.startTimer(0.2)
  while true do
    local e={os.pullEventRaw()}
    if e[1]=="rednet_message" and e[4]==PROTOCOL then handle(e[2],e[3])
    elseif e[1]=="timer" and e[2]==timer then send("HEARTBEAT","alive"); timer=os.startTimer(2) end
  end
end

local function craftLoop()
  local clean,msg=clearToDestination()
  if not clean then state="ERROR"; send("STATUS",msg) end
  while true do
    while paused or stopped or state=="ERROR" or state=="OUTPUT_FULL" do os.pullEvent("bluma_craft_wake") end
    local ok,err=craftOneBatch()
    if not ok then state="ERROR"; send("STATUS",err) end
    sleep(0.05)
  end
end

local function uiLoop()
  while true do
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1)
    term.setTextColor(colors.cyan); print("BLUMA // CRAFT-01"); term.setTextColor(colors.white)
    print("STATE   "..state)
    print("RECIPE  DEEPSLATE BRICKS")
    print("INPUT   CHEST IN FRONT")
    print("OUTPUT  CHEST BELOW")
    print("MADE    "..crafted)
    print("")
    print("Cobbled Deepslate")
    print(" -> Polished Deepslate")
    print(" -> Deepslate Bricks")
    print("")
    if modem then print("BLUMA link: ONLINE") else print("BLUMA link: NO MODEM (local mode)") end
    sleep(0.5)
  end
end

state="CRAFTING"
send("HELLO","CRAFT-01 boot")
parallel.waitForAll(networkLoop,craftLoop,uiLoop)
]=]

local function cls()
  term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1)
end
local function mkdir(path)
  if not path or path=="" or path=="/" or fs.exists(path) then return end
  local parent=fs.getDir(path); if parent and parent~="" and parent~=path then mkdir(parent) end
  fs.makeDir(path)
end
local function put(path,data)
  local dir=fs.getDir(path); if dir and dir~="" then mkdir(dir) end
  local h,err=fs.open(path,"w"); if not h then error("Cannot write "..path..": "..tostring(err)) end
  h.write(data); h.close()
  term.setTextColor(colors.lime); print("OK  "..path); term.setTextColor(colors.white)
end
local function get(path)
  if not fs.exists(path) then return nil end
  local h=fs.open(path,"r"); if not h then return nil end
  local d=h.readAll(); h.close(); return d
end
local function replacePlain(s,old,new)
  local out,pos={},1
  while true do
    local a,b=string.find(s,old,pos,true)
    if not a then out[#out+1]=string.sub(s,pos); break end
    out[#out+1]=string.sub(s,pos,a-1); out[#out+1]=new; pos=b+1
  end
  return table.concat(out)
end
local function extractKey(path)
  local d=get(path); if not d then return nil end
  local k=d:match('GROQ_KEY%s*=%s*"([^"]+)"')
  if k and k~="" and k~="__GROQ_KEY__" and k~="SUA_CHAVE_GROQ_AQUI" then return k end
end
local function backup(paths)
  local root=".bluma_backup/"..tostring(os.epoch("utc")); local any=false
  for _,p in ipairs(paths) do
    if fs.exists(p) then
      mkdir(root); local dest=fs.combine(root,p); mkdir(fs.getDir(dest)); if fs.exists(dest) then fs.delete(dest) end; fs.copy(p,dest); any=true
    end
  end
  if any then print("Backup: "..root) end
end
local function header(role)
  cls(); term.setTextColor(colors.cyan); print("BLUMA // UNIVERSAL INSTALLER V5"); term.setTextColor(colors.gray); print("Role: "..role); print("--------------------------------"); term.setTextColor(colors.white)
end

local function installCore()
  header("CORE")
  backup({"bluma","ananke","startup.lua"})
  local key=extractKey("bluma/config.lua") or extractKey("ananke/config.lua")
  if key then
    print("Existing Groq key found (BLUMA/ANANKE).")
    write("Reuse it? [Y/n]: "); local a=string.lower(read() or ""); if a=="n" or a=="no" then key=nil end
  end
  if not key then print("Paste Groq API key:"); write("> "); key=read("*") end
  if not key or key=="" then error("Groq key cannot be empty.") end
  local c=replacePlain(CONFIG_DATA,"__GROQ_KEY__",key)
  mkdir("bluma")
  put("bluma/config.lua",c)
  put("bluma/core.lua",CORE_DATA)
  put("startup.lua",'shell.run("bluma/core.lua")\n')
  print("")
  term.setTextColor(colors.lime); print("BLUMA CORE INSTALLED."); term.setTextColor(colors.white)
  write("Start BLUMA now? [Y/n]: "); local a=string.lower(read() or ""); if a~="n" and a~="no" then shell.run("bluma/core.lua") end
end

local function installMiner()
  header("MINER-01")
  backup({"bluma_miner.lua","startup.lua",".bluma_miner_state",".bluma_miner_config"})
  put("bluma_miner.lua",MINER_DATA)
  put("startup.lua",'shell.run("bluma_miner.lua")\n')
  print("")
  print("Required: Advanced Mining Turtle + Wireless Modem")
  print("For auto-unload, place a chest below HOME position.")
  term.setTextColor(colors.lime); print("MINER-01 INSTALLED."); term.setTextColor(colors.white)
  write("Start MINER-01 now? [Y/n]: "); local a=string.lower(read() or ""); if a~="n" and a~="no" then shell.run("bluma_miner.lua") end
end

local function installCrafter()
  header("CRAFT-01")
  backup({"bluma_crafter.lua","startup.lua"})
  if type(turtle.craft)~="function" then
    term.setTextColor(colors.red); print("WARNING: Crafting Table upgrade was not detected."); term.setTextColor(colors.white)
    print("Install a Crafting Table upgrade before running CRAFT-01.")
  end
  put("bluma_crafter.lua",CRAFTER_DATA)
  put("startup.lua",'shell.run("bluma_crafter.lua")\n')
  print("")
  print("Recipe preset: Deepslate Bricks")
  print("INPUT:  chest/container directly in FRONT")
  print("OUTPUT: chest/hopper directly BELOW")
  print("Optional: Wireless Modem for BLUMA telemetry/control")
  term.setTextColor(colors.lime); print("CRAFT-01 INSTALLED."); term.setTextColor(colors.white)
  write("Start CRAFT-01 now? [Y/n]: "); local a=string.lower(read() or ""); if a~="n" and a~="no" then shell.run("bluma_crafter.lua") end
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
  local c=read()
  if c=="1" then installMiner()
  elseif c=="2" then installCrafter()
  else print("Cancelled.") end
end
