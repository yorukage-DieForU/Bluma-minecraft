-- Renomeie para startup.lua na Turtle mineradora.
while true do
    local ok,err=pcall(function() shell.run("bluma_miner") end)
    if not ok then printError(err) end
    print("Agente miner reiniciando em 3s...")
    sleep(3)
end
