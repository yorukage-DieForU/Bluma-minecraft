BLUMA v6 - INSTALACAO CORRIGIDA

1. COMPUTADOR CENTRAL
Arquivos:
  bluma.lua
  config.lua
  bluma_ascii_01.txt   (opcional para preservar/detectar o asset)

No config.lua, coloque SOMENTE:
  GROQ_KEY
  FISH_KEY

Rode:
  bluma

2. ASCII
Nao e obrigatorio usar a extensao .txt.
O bluma.lua procura automaticamente:
  bluma_ascii_01.txt
  bluma_ascii_01
  Bluma-ASCII-01-01.txt
  Bluma-ASCII-01-01
  e outras variacoes.

IMPORTANTE:
O arquivo Unicode/Braille original e preservado, mas o monitor
do CC:Tweaked nao possui a fonte necessaria para desenha-lo exatamente.
Por isso o painel usa um retrato ASCII compativel.
O dashboard mostra qual arquivo original foi encontrado.

3. MINER TURTLE
A sua Turtle ja tem miner64 e modem.
O problema anterior e que miner64 estava rodando sozinho e nao enviava
heartbeat para a BLUMA.

Quando a mineracao atual terminar:
  coloque bluma_miner_bridge.lua na Turtle
  rode:
    bluma_miner_bridge

Entao use:
  Bluma liga a mineradora

O bridge executa miner64 e telemetria ao mesmo tempo.

4. COMANDOS
  Bluma diagnostico
  Bluma status da mineradora
  Bluma liga a mineradora
  Bluma pausa a mineradora
  Bluma continua a mineradora
  Bluma para a mineradora

  Bluma idioma automatico
  Bluma idioma portugues
  Bluma idioma ingles
  Bluma idioma japones

  Bluma voz ligada
  Bluma voz desligada
  Bluma volume 2.1

5. VOZES EMBUTIDAS
PT-BR:
  23c14f5db9dc40ba9c69f38575ae3a80

EN:
  f090965f96e34b31b02f4c881e8e609c

JA:
  66635eb26bff4e18a2f9360ac2e6b364

Nao precisa colocar esses IDs no config.lua.

6. STARTUP
Depois que tudo estiver testado:
  computador central: copie startup_core.lua para startup.lua
  Turtle: copie startup_miner.lua para startup.lua

OBSERVACAO:
Se a Turtle estiver fisicamente desligada, Rednet nao consegue acorda-la.
