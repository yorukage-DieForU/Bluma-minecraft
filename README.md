
BLUMA FINAL - INSTALACAO

CENTRAL:
1) Coloque bluma.lua e config.lua no Advanced Computer.
2) Em config.lua, preencha GROQ_KEY e FISH_KEY uma unica vez.
3) Opcional: copie startup_core.lua como startup.lua.
4) Execute: bluma

TURTLE MINERADORA:
1) O programa miner64 precisa continuar existente e funcionando.
2) Coloque bluma_miner.lua na Turtle.
3) Copie startup_miner.lua como startup.lua.
4) Reinicie a Turtle uma vez.
5) Ela pareia automaticamente com o computador BLUMA e fica STANDBY.

TESTE:
- No chat: Bluma diagnostico
- Deve mostrar owner=true para Murillopip.
- No chat: Bluma status da mineradora
- No chat: Bluma liga a mineradora
- No chat: Bluma pausa a mineradora
- No chat: Bluma continua a mineradora

VOZ:
- A voz e fixa por reference_id salvo em .bluma_runtime.
- Nao precisa editar config.lua para trocar a voz.
- Comando: Bluma voz SEU_REFERENCE_ID
- Comando: Bluma voz atual
- Comando: Bluma limpar voz
- Comando: Bluma desliga a voz
- Comando: Bluma liga a voz

IMPORTANTE:
- PAUSE preserva a coroutine atual do miner64.
- ABORT descarta a sessao. Como miner64 originalmente mantem estado em memoria, um novo START apos ABORT reinicia o programa miner64.
- Se a Turtle estiver fisicamente desligada, nenhum comando Rednet consegue liga-la. startup.lua serve para o agente subir automaticamente quando a Turtle for ligada/reiniciada.
