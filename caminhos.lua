-- Os caminhos do projeto. main.lua e main.atm fazem require "caminhos"
-- antes de qualquer outro modulo: a logica do jogo fica em jogo/, o
-- renderer em render/, e a comunicacao com o C em ponte/ (os modulos Lua
-- que embrulham o SDL e o som, o ambiente Atmos e os .so/.dll compilados).
-- Os caminhos sao relativos a pasta de onde o jogo roda (a raiz do projeto).
-- O Atmos procura os .atm no mesmo package.path (trocando .lua por .atm).

if not package.path:find("./jogo/?.lua", 1, true) then
  package.path = "./?.lua;./jogo/?.lua;./render/?.lua;./ponte/?.lua;./ponte/?/init.lua;"
    .. package.path
  package.cpath = "./ponte/?.so;./ponte/?.dll;" .. package.cpath
end
