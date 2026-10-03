-- Renomeie para startup.lua no computador central.
while true do
    local ok,err=pcall(function() shell.run("bluma") end)
    if not ok then printError(err) end
    print("BLUMA reiniciando em 3s...")
    sleep(3)
end
