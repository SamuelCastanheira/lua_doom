-- DOOM generic portado do python_doom para Lua com SDL2.
--
-- Por Wagner Nunes da Silva
--
-- vagucs@bol.com.br
-- vagucs@vagucs.com.br
-- vagucs@gmail.com
--
-- www.vagucs.com.br
--
-- Lancador: roda o main.atm (Atmos) a partir do Lua puro, para que o comando
-- de sempre continue funcionando:
--
--   lua5.4 main.lua -fps -scale 4      ==   atmos main.atm -- -fps -scale 4
--
-- Desde o passo 2 o fluxo do jogo so existe em Atmos. O laco imperativo
-- original (referencia dos testes de equivalencia) esta na tag "passo1".
io.stdout:setvbuf("no")
io.stderr:setvbuf("no")

atmos = require("atmos")
require("atmos.lang.exec")
require("atmos.lang.run")

-- Mesmo comportamento do executavel "atmos": o script fica em arg[1].
local args = { "main.atm" }
for i = 1, #arg do
  args[#args + 1] = arg[i]
end
arg = args

atmos.loop(assert(atm_loadfile("main.atm")))
