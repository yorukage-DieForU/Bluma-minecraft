-- ANANKE UNIVERSAL INSTALLER V3
-- One file. No embedded file table.

local ROLE = turtle and "MINER" or "CORE"

local function mkdir(path)
  if path == "" or fs.exists(path) then return end
  local parent = fs.getDir(path)
  if parent ~= "" and not fs.exists(parent) then mkdir(parent) end
  fs.makeDir(path)
end

local function put(path, data)
  local dir = fs.getDir(path)
  if dir ~= "" then mkdir(dir) end
  local h = assert(fs.open(path, "w"), "Cannot write "..path)
  h.write(data)
  h.close()
  print("OK  "..path)
end

local function replacePlain(s, old, new)
  local out, pos = {}, 1
  while true do
    local a,b = string.find(s, old, pos, true)
    if not a then
      out[#out+1] = string.sub(s,pos)
      break
    end
    out[#out+1] = string.sub(s,pos,a-1)
    out[#out+1] = new
    pos = b+1
  end
  return table.concat(out)
end

term.clear()
term.setCursorPos(1,1)
term.setTextColor(colors.cyan)
print("ANANKE // UNIVERSAL INSTALLER V3")
term.setTextColor(colors.white)
print("Detected: "..ROLE)
print("")

if ROLE == "CORE" then
  print("This will install ANANKE CORE.")
  print("")
  write("Groq API key: ")
  local groq = read("*")
  if not groq or groq == "" then error("Groq key cannot be empty") end

  mkdir("ananke")
  mkdir("ananke/modules")
  mkdir("ananke/assets")
  put("ananke/core.lua", [=[local cfg=require("ananke.config")
local util=require("ananke.modules.util")
local sec=require("ananke.modules.security")
local chat=require("ananke.modules.chat")
local brain=require("ananke.modules.brain")
local machines=require("ananke.modules.machines")
local ui=require("ananke.modules.ui")

local mon=peripheral.find("monitor")
local box=peripheral.find("chatBox")
local modem=peripheral.find("modem")
if not mon then error("ANANKE: monitor nao encontrado") end
if not box then error("ANANKE: Chat Box nao encontrada") end
if not modem then error("ANANKE: modem nao encontrado") end

local modemName=peripheral.getName(modem)
if not rednet.isOpen(modemName) then rednet.open(modemName) end
mon.setTextScale(0.5)

local state={lastResponse="",lastUser="-"}
local function redraw() ui.draw(cfg,mon,state) end

local function machineIntent(user,msg)
  if not sec.isOwner(cfg,user) then return nil end
  local a=nil
  if util.contains(msg,"liga a miner") or util.contains(msg,"start miner") then a="START" end
  if util.contains(msg,"pausa") and util.contains(msg,"miner") then a="PAUSE" end
  if (util.contains(msg,"retoma") or util.contains(msg,"resume")) and util.contains(msg,"miner") then a="RESUME" end
  if (util.contains(msg,"volta") or util.contains(msg,"return")) and util.contains(msg,"miner") then a="RETURN" end
  if (util.contains(msg,"para") or util.contains(msg,"stop")) and util.contains(msg,"miner") then a="STOP" end
  if not a then return nil end
  local ok,res=machines.command(cfg,cfg.MACHINE_ID,a)
  return res
end

local function process(user,msg)
  local response=machineIntent(user,msg)
  if not response then
    local lang,answer,err=brain.ask(cfg,user,msg,machines.summary(cfg,cfg.MACHINE_ID))
    response=answer or ("Falha no nucleo de linguagem: "..tostring(err))
  end
  state.lastUser=user state.lastResponse=response redraw()
  chat.route(cfg,box,user,msg,response)
end

local function chatLoop()
  while true do
    local _,user,msg,uuid,hidden,utf8msg=os.pullEvent("chat")
    local actual=utf8msg or msg or ""
    if util.contains(actual,"ananke") then
      local ok,err=pcall(process,user,actual)
      if not ok then
        state.lastResponse="Erro interno: "..tostring(err) redraw()
        chat.private(box,user,state.lastResponse)
      end
    end
  end
end

local function touchLoop()
  while true do
    local _,side,x,y=os.pullEvent("monitor_touch")
    local action=ui.hit(x,y)
    if action then
      local ok,msg=machines.command(cfg,cfg.MACHINE_ID,action)
      state.lastResponse=msg redraw()
      chat.private(box,cfg.OWNER,msg)
    end
  end
end

redraw()
parallel.waitForAll(
  chatLoop,
  touchLoop,
  function() machines.loop(cfg,redraw) end,
  function() while true do redraw() sleep(0.5) end end
)
]=])
  local configData = [=[return {
  OWNER = "Murillopip",
  PROTOCOL = "ANANKE",
  MACHINE_ID = "MINER-01",
  HEARTBEAT_TIMEOUT = 8,

  GROQ_KEY = "SUA_CHAVE_GROQ_AQUI",
  GROQ_MODEL = "openai/gpt-oss-20b",

  -- Voz fica desligada por padrao nesta reconstrução.
  -- A estrutura de idioma ja esta separada e depois ligamos o TTS definitivo.
  VOICE_ENABLED = false
}
]=]
  configData = replacePlain(configData,
    'GROQ_KEY = "SUA_CHAVE_GROQ_AQUI"',
    'GROQ_KEY = "'..groq..'"')
  put("ananke/config.lua", configData)
  put("ananke/assets/resi_ascii.txt", [=[⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⣲⣵⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
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
]=])
  put("ananke/assets/resi_face.lua", [=[return {
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
  "        #########################",
}
]=])
  put("ananke/modules/brain.lua", [=[local util=require("ananke.modules.util")
local M={}
function M.ask(cfg,user,message,machineSummary)
  local system=[[
You are ANANKE, a calm futuristic female operations assistant inside Minecraft.
Return ONLY compact JSON in this exact shape:
{"language":"pt-BR|en-US|ja-JP","text":"..."}
Rules:
- Answer naturally in the user's language.
- If the user explicitly asks for another language, obey it.
- Never invent telemetry or machine execution.
- The telemetry below is authoritative.
- Keep the answer concise and natural.
TELEMETRY:
]]..machineSummary
  local body=textutils.serializeJSON({
    model=cfg.GROQ_MODEL,temperature=0.35,max_tokens=260,
    messages={{role="system",content=system},{role="user",content=message}}
  })
  local r,err,er=http.post("https://api.groq.com/openai/v1/chat/completions",body,
    {["Authorization"]="Bearer "..tostring(cfg.GROQ_KEY or ""),["Content-Type"]="application/json"})
  if not r then
    local d=tostring(err)
    if er then d=d.." | "..er.readAll() er.close() end
    return nil,nil,d
  end
  local raw=r.readAll() r.close()
  local data=textutils.unserializeJSON(raw)
  local c=data and data.choices and data.choices[1] and data.choices[1].message and data.choices[1].message.content
  if not c then return nil,nil,"Resposta invalida da Groq." end
  local p=textutils.unserializeJSON(c)
  if type(p)=="table" and p.text then return p.language or "pt-BR",util.trim(p.text),nil end
  return "pt-BR",util.trim(c),nil
end
return M
]=])
  put("ananke/modules/chat.lua", [=[local util=require("ananke.modules.util")
local sec=require("ananke.modules.security")
local M={}
function M.public(box,text)
  pcall(function() box.sendMessage(util.ascii(text),"ANANKE","[]","&b") end)
end
function M.private(box,user,text)
  pcall(function() box.sendMessageToPlayer(util.ascii(text),user,"ANANKE","[]","&b") end)
end
function M.route(cfg,box,user,message,response)
  local class=sec.classify(message)
  if class=="PRIVATE_MACHINE" then
    if sec.isOwner(cfg,user) then M.private(box,user,response)
    else M.public(box,"Essa informacao e restrita ao operador.") end
  else
    M.public(box,response)
  end
end
return M
]=])
  put("ananke/modules/machines.lua", [=[local util=require("ananke.modules.util")
local M={state={},pending={},counter=0}
function M.online(cfg,id)
  local m=M.state[id]
  return m and (util.now()-(m.lastSeen or 0)<=cfg.HEARTBEAT_TIMEOUT)
end
function M.summary(cfg,id)
  local m=M.state[id]
  if not M.online(cfg,id) then return id.."=OFFLINE" end
  local s=id.."="..tostring(m.state or "UNKNOWN").." fuel="..tostring(m.fuel or "?")..
    " slots="..tostring(m.usedSlots or "?").."/16"
  if m.progress~=nil then s=s.." progress="..tostring(m.progress).."%" end
  if m.blocks~=nil then s=s.." blocks="..tostring(m.blocks) end
  return s
end
function M.update(sender,p)
  if type(p)~="table" or not p.id then return end
  M.state[p.id]={sender=sender,state=p.state or "UNKNOWN",fuel=p.fuel,usedSlots=p.usedSlots,
    progress=p.progress,blocks=p.blocks,job=p.job,message=p.message,lastSeen=util.now()}
end
function M.command(cfg,id,action,args)
  local m=M.state[id]
  if not M.online(cfg,id) then return false,id.." esta offline." end
  M.counter=M.counter+1
  local req=tostring(os.getComputerID()).."-"..tostring(os.epoch("utc")).."-"..M.counter
  M.pending[req]=false
  rednet.send(m.sender,{type="COMMAND",id=id,action=action,args=args or {},requestId=req},cfg.PROTOCOL)
  local deadline=util.now()+4
  while util.now()<deadline do
    local r=M.pending[req]
    if type(r)=="table" then M.pending[req]=nil return r.ok~=false,r.message or "OK" end
    sleep(0.05)
  end
  M.pending[req]=nil return false,"Sem confirmacao da maquina."
end
function M.loop(cfg,onUpdate)
  while true do
    local _,sender,p,protocol=os.pullEvent("rednet_message")
    if protocol==cfg.PROTOCOL and type(p)=="table" then
      if p.type=="HEARTBEAT" or p.type=="STATUS" or p.type=="ACK" then M.update(sender,p) end
      if p.type=="ACK" and p.requestId then M.pending[p.requestId]={ok=p.ok~=false,message=p.message} end
      if onUpdate then onUpdate() end
    end
  end
end
return M
]=])
  put("ananke/modules/security.lua", [=[local util=require("ananke.modules.util")
local M={}
function M.isOwner(cfg,user) return util.ownerEq(user,cfg.OWNER) end
function M.classify(message)
  local hints={"miner","mineradora","fuel","combust","invent","slot","coorden","machine","maquina","máquina",
  "liga","desliga","pausa","resume","retoma","stop","return","volta","admin","security","seguranca"}
  for _,h in ipairs(hints) do if util.contains(message,h) then return "PRIVATE_MACHINE" end end
  return "PUBLIC"
end
return M
]=])
  put("ananke/modules/ui.lua", [=[local util=require("ananke.modules.util")
local machines=require("ananke.modules.machines")
local face=require("ananke.assets.resi_face")
local M={buttons={}}

local function wr(mon,x,y,t,fg,bg)
  if bg then mon.setBackgroundColor(bg) end
  if fg then mon.setTextColor(fg) end
  mon.setCursorPos(x,y) mon.write(tostring(t or ""))
end

local function btn(mon,x,y,w,label,bg,action)
  mon.setBackgroundColor(bg) mon.setTextColor(colors.white)
  mon.setCursorPos(x,y)
  mon.write(" "..label..string.rep(" ",math.max(0,w-#label-1)))
  table.insert(M.buttons,{x1=x,y1=y,x2=x+w-1,y2=y,action=action})
end

function M.draw(cfg,mon,state)
  M.buttons={}
  local w,h=mon.getSize()
  mon.setBackgroundColor(colors.black) mon.setTextColor(colors.white) mon.clear()
  wr(mon,2,1,"ANANKE // COMMAND",colors.cyan)
  wr(mon,math.max(2,w-9),1,"[ONLINE]",colors.lime)
  wr(mon,1,2,string.rep("-",w),colors.gray)
  local split=math.floor(w*0.60)

  wr(mon,2,4,"MINER-01",colors.cyan)
  local m=machines.state[cfg.MACHINE_ID]
  if machines.online(cfg,cfg.MACHINE_ID) then
    wr(mon,2,6,"STATE",colors.gray) wr(mon,13,6,tostring(m.state),m.state=="MINING" and colors.lime or colors.yellow)
    wr(mon,2,7,"FUEL",colors.gray) wr(mon,13,7,tostring(m.fuel or "?"),colors.white)
    wr(mon,2,8,"STORAGE",colors.gray) wr(mon,13,8,tostring(m.usedSlots or "?").."/16",colors.white)
    wr(mon,2,9,"PROGRESS",colors.gray) wr(mon,13,9,tostring(m.progress or "?").."%",colors.white)
    wr(mon,2,10,"BLOCKS",colors.gray) wr(mon,13,10,tostring(m.blocks or "?"),colors.white)
    btn(mon,2,12,9,"START",colors.green,"START")
    btn(mon,12,12,9,"PAUSE",colors.orange,"PAUSE")
    btn(mon,22,12,10,"RESUME",colors.blue,"RESUME")
    btn(mon,33,12,10,"RETURN",colors.purple,"RETURN")
    btn(mon,44,12,8,"STOP",colors.red,"STOP")
  else
    wr(mon,2,6,"OFFLINE",colors.red)
    wr(mon,2,7,"Waiting for heartbeat...",colors.gray)
  end

  if state.lastResponse and state.lastResponse~="" then
    wr(mon,2,15,"LAST RESPONSE",colors.cyan)
    local rows=util.wrap(state.lastResponse,math.max(20,split-4))
    for i=1,math.min(#rows,h-16) do wr(mon,2,15+i,rows[i],colors.white) end
  end

  local ox=split+2
  wr(mon,ox,4,"RESI // FACE",colors.cyan)
  for yy,row in ipairs(face) do
    if 5+yy>h-1 then break end
    for xx=1,#row do
      if ox+xx-1>w then break end
      local ch=row:sub(xx,xx)
      wr(mon,ox+xx-1,5+yy," ",nil,ch=="#" and colors.lightBlue or colors.black)
    end
  end
  mon.setBackgroundColor(colors.black)
end

function M.hit(x,y)
  for _,b in ipairs(M.buttons) do
    if x>=b.x1 and x<=b.x2 and y>=b.y1 and y<=b.y2 then return b.action end
  end
end
return M
]=])
  put("ananke/modules/util.lua", [=[local M={}
function M.trim(s) s=tostring(s or "") return (s:gsub("^%s+",""):gsub("%s+$","")) end
function M.lower(s) return string.lower(tostring(s or "")) end
function M.contains(a,b) return string.find(M.lower(a),M.lower(b),1,true)~=nil end
function M.now() return os.epoch("utc")/1000 end
function M.ownerEq(a,b) return M.lower(M.trim(a))==M.lower(M.trim(b)) end
function M.ascii(s)
  s=tostring(s or "")
  local map={["á"]="a",["à"]="a",["ã"]="a",["â"]="a",["é"]="e",["ê"]="e",["í"]="i",
  ["ó"]="o",["õ"]="o",["ô"]="o",["ú"]="u",["ç"]="c",["Á"]="A",["À"]="A",["Ã"]="A",
  ["Â"]="A",["É"]="E",["Ê"]="E",["Í"]="I",["Ó"]="O",["Õ"]="O",["Ô"]="O",["Ú"]="U",["Ç"]="C"}
  for a,b in pairs(map) do s=s:gsub(a,b) end
  return s:gsub("[^\32-\126\n]","?")
end
function M.wrap(text,width)
  local out,line={},""
  for word in M.ascii(text):gmatch("%S+") do
    if line=="" then line=word
    elseif #line+#word+1<=width then line=line.." "..word
    else table.insert(out,line) line=word end
  end
  if line~="" then table.insert(out,line) end
  return out
end
return M
]=])
  put("startup.lua", 'shell.run("ananke/core.lua")\n')

  print("")
  print("Peripheral check:")
  print("Monitor: "..(peripheral.find("monitor") and "OK" or "MISSING"))
  print("Modem:   "..(peripheral.find("modem") and "OK" or "MISSING"))
  print("ChatBox: "..(peripheral.find("chatBox") and "OK" or "MISSING"))
  print("Speaker: "..(peripheral.find("speaker") and "OK" or "MISSING"))
  print("")
  print("ANANKE CORE INSTALLED.")
  write("Start now? [Y/n]: ")
  local a=string.lower(read() or "")
  if a~="n" and a~="no" then shell.run("ananke/core.lua") end

else
  print("This will install MINER-01.")
  print("")
  if not peripheral.find("modem") then
    term.setTextColor(colors.yellow)
    print("WARNING: Wireless Modem not detected.")
    term.setTextColor(colors.white)
  end

  local function ask(label, default)
    write(label.." ["..default.."]: ")
    local v=read()
    if v=="" then return default end
    local n=tonumber(v)
    if not n or n<1 or math.floor(n)~=n then
      print("Invalid value; using "..default)
      return default
    end
    return n
  end

  local w=ask("Width",64)
  local l=ask("Length",64)
  local d=ask("Depth",64)

  local minerData = [=[-- ANANKE MINER v1
-- Advanced Mining Turtle + Wireless Modem
-- Nova quarry serpentina com save/resume + heartbeat + comandos.

local PROTOCOL="ANANKE"
local ID="MINER-01"
local SAVE=".ananke_miner_state"

local modem=peripheral.find("modem")
if not modem then error("Wireless modem nao encontrado.") end
local modemName=peripheral.getName(modem)
if not rednet.isOpen(modemName) then rednet.open(modemName) end

local s={state="STANDBY",width=64,length=64,depth=64,layer=0,row=0,col=0,x=0,y=0,z=0,dir=0,
  blocks=0,paused=false,stop=false,returning=false}

local coreId=nil
local hb=os.startTimer(1)

local function save()
  local h=fs.open(SAVE,"w")
  if h then h.write(textutils.serializeJSON(s)) h.close() end
end

local function load()
  if not fs.exists(SAVE) then return end
  local h=fs.open(SAVE,"r")
  if not h then return end
  local d=textutils.unserializeJSON(h.readAll()) h.close()
  if type(d)=="table" then for k,v in pairs(d) do s[k]=v end end
  if s.state=="MINING" then s.state="PAUSED" s.paused=true end
end
load()

local function usedSlots()
  local n=0 for i=1,16 do if turtle.getItemCount(i)>0 then n=n+1 end end return n
end

local function progress()
  local total=math.max(1,s.width*s.length*s.depth)
  local done=(s.layer*s.width*s.length)+(s.row*s.width)+s.col
  return math.floor(math.min(100,done/total*1000))/10
end

local function send(tp,msg,req,ok)
  local p={type=tp,id=ID,state=s.state,fuel=turtle.getFuelLevel(),usedSlots=usedSlots(),
    progress=progress(),blocks=s.blocks,job={width=s.width,length=s.length,depth=s.depth,
    layer=s.layer,row=s.row,col=s.col},x=s.x,y=s.y,z=s.z,dir=s.dir,message=msg,requestId=req,ok=ok}
  if coreId then rednet.send(coreId,p,PROTOCOL) else rednet.broadcast(p,PROTOCOL) end
end

local function right() turtle.turnRight() s.dir=(s.dir+1)%4 save() end
local function left() turtle.turnLeft() s.dir=(s.dir+3)%4 save() end
local function face(d) while s.dir~=d do right() end end

local function digF()
  if turtle.detect() and turtle.dig() then s.blocks=s.blocks+1 end
end

local function fwd()
  digF()
  local tries=0
  while not turtle.forward() do
    tries=tries+1
    if tries>20 then s.state="BLOCKED" save() return false end
    turtle.attack() digF() sleep(0.1)
  end
  if s.dir==0 then s.z=s.z-1 elseif s.dir==1 then s.x=s.x+1
  elseif s.dir==2 then s.z=s.z+1 else s.x=s.x-1 end
  save() return true
end

local function down()
  if turtle.detectDown() and turtle.digDown() then s.blocks=s.blocks+1 end
  local tries=0
  while not turtle.down() do
    tries=tries+1
    if tries>20 then s.state="BLOCKED" save() return false end
    turtle.attackDown() turtle.digDown() sleep(0.1)
  end
  s.y=s.y-1 save() return true
end

local function returnHome()
  s.state="RETURNING" save() send("STATUS","Returning home")
  while s.y<0 do
    if turtle.detectUp() then turtle.digUp() end
    if turtle.up() then s.y=s.y+1 save() else turtle.attackUp() sleep(0.1) end
  end
  if s.x>0 then face(3) while s.x>0 do if not fwd() then return end end end
  if s.x<0 then face(1) while s.x<0 do if not fwd() then return end end end
  if s.z>0 then face(0) while s.z>0 do if not fwd() then return end end end
  if s.z<0 then face(2) while s.z<0 do if not fwd() then return end end end
  face(0)
  s.state="STANDBY" s.returning=false save() send("STATUS","At home")
end

local function gate()
  if s.returning then returnHome() return false end
  if s.stop then s.state="STANDBY" s.stop=false save() return false end
  while s.paused do s.state="PAUSED" save() os.pullEvent("ananke_resume") end
  return true
end

local function mineJob()
  s.state="MINING" s.paused=false s.stop=false save()
  for layer=s.layer,s.depth-1 do
    s.layer=layer
    for row=s.row,s.length-1 do
      s.row=row
      for col=s.col,s.width-1 do
        s.col=col
        if not gate() then return end
        if col<s.width-1 and not fwd() then return end
      end
      s.col=0
      if row<s.length-1 then
        if row%2==0 then right() if not fwd() then return end right()
        else left() if not fwd() then return end left() end
      end
      save()
    end
    s.row=0 s.col=0
    if layer<s.depth-1 then right() right() if not down() then return end end
  end
  s.state="FINISHED" save() send("STATUS","Job complete")
end

local function command(sender,p)
  if type(p)~="table" or p.type~="COMMAND" then return end
  coreId=sender
  local a=string.upper(tostring(p.action or ""))
  local ok,msg=true,"OK"
  if a=="START" then
    if s.state=="STANDBY" or s.state=="FINISHED" then s.state="PREPARING" save() os.queueEvent("ananke_start") msg="Job iniciado."
    elseif s.state=="PAUSED" then s.paused=false s.state="MINING" save() os.queueEvent("ananke_resume") msg="Mineracao retomada."
    else msg="Mineradora ja esta ativa." end
  elseif a=="PAUSE" then s.paused=true s.state="PAUSED" save() msg="Mineradora pausada."
  elseif a=="RESUME" then s.paused=false s.state="MINING" save() os.queueEvent("ananke_resume") msg="Mineradora retomada."
  elseif a=="RETURN" then s.returning=true s.paused=false save() os.queueEvent("ananke_resume") msg="Retorno solicitado."
  elseif a=="STOP" then s.stop=true s.paused=false save() os.queueEvent("ananke_resume") msg="Parada solicitada."
  else ok=false msg="Comando desconhecido." end
  send("ACK",msg,p.requestId,ok)
end

local function network()
  while true do
    local e={os.pullEventRaw()}
    if e[1]=="rednet_message" and e[4]==PROTOCOL then command(e[2],e[3]) end
    if e[1]=="timer" and e[2]==hb then send("HEARTBEAT","alive") hb=os.startTimer(2) end
  end
end

local function ui()
  while true do
    term.setBackgroundColor(colors.black) term.setTextColor(colors.white) term.clear()
    term.setCursorPos(1,1) term.setTextColor(colors.cyan) print("ANANKE // MINER-01")
    term.setTextColor(colors.white)
    print("") print("STATE   "..s.state) print("JOB     "..s.width.."x"..s.length.."x"..s.depth)
    print("PROG    "..progress().."%") print("LAYER   "..s.layer.."/"..s.depth)
    print("ROW     "..s.row.."/"..s.length) print("FUEL    "..tostring(turtle.getFuelLevel()))
    print("SLOTS   "..usedSlots().."/16") print("BLOCKS  "..s.blocks) print("")
    term.setBackgroundColor(colors.orange) term.setTextColor(colors.black) print(" PAUSE ")
    term.setBackgroundColor(colors.blue) term.setTextColor(colors.white) print(" RESUME ")
    term.setBackgroundColor(colors.purple) print(" RETURN ")
    term.setBackgroundColor(colors.red) print(" STOP ")
    term.setBackgroundColor(colors.black)
    sleep(0.5)
  end
end

local function mouse()
  while true do
    local _,b,x,y=os.pullEvent("mouse_click")
    if y==12 then s.paused=true s.state="PAUSED" save()
    elseif y==13 then s.paused=false s.state="MINING" save() os.queueEvent("ananke_resume")
    elseif y==14 then s.returning=true s.paused=false save() os.queueEvent("ananke_resume")
    elseif y==15 then s.stop=true s.paused=false save() os.queueEvent("ananke_resume") end
  end
end

local function miner()
  while true do
    if s.state=="PREPARING" or s.state=="MINING" then mineJob()
    elseif s.state=="PAUSED" then os.pullEvent("ananke_resume") if not s.returning and not s.stop then mineJob() end
    else local e=os.pullEvent() if e=="ananke_start" then mineJob() end end
  end
end

send("HEARTBEAT","boot")
parallel.waitForAll(network,ui,mouse,miner)
]=]
  minerData = replacePlain(minerData,
    'local s={state="STANDBY",width=64,length=64,depth=64,',
    'local s={state="STANDBY",width='..w..',length='..l..',depth='..d..',')

  put("ananke_miner.lua", minerData)
  put("startup.lua", 'shell.run("ananke_miner.lua")\n')

  print("")
  print("ANANKE MINER INSTALLED.")
  write("Start now? [Y/n]: ")
  local a=string.lower(read() or "")
  if a~="n" and a~="no" then shell.run("ananke_miner.lua") end
end
