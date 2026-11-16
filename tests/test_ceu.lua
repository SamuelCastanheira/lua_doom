local tables = require("tables")
local tables_c = require("tables_c")

local FINEANGLES = 8192
local FINESINE_SIZE = 10240
local FRACUNIT = 65536

print("=== TESTE FINESINE: LUA x C ===")

-- Inicializa as duas implementações.
tables.init()

local native = tables_c.new()
native:init()

local data = native:finesine_data()

assert(#data == FINESINE_SIZE * 4,
    "Tamanho incorreto de finesine_data: " .. #data)

-- Detecta se a tabela Lua começa no índice 0 ou 1.
local lua_offset = tables.finesine[0] ~= nil and 0 or 1

local divergencias = 0
local max_diff = 0
local primeiro_erro = nil

for i = 0, FINESINE_SIZE - 1 do
    local lua_value = tables.finesine[i + lua_offset]
    local c_value = string.unpack("=i4", data, i * 4 + 1)

    assert(lua_value ~= nil,
        "Valor Lua ausente no índice " .. i)

    local diff = math.abs(lua_value - c_value)

    if diff > max_diff then
        max_diff = diff
    end

    if diff ~= 0 then
        divergencias = divergencias + 1

        if not primeiro_erro then
            primeiro_erro = {
                index = i,
                lua = lua_value,
                c = c_value,
                diff = diff
            }
        end
    end
end

print("Divergências Lua x C:", divergencias)
print("Maior diferença:", max_diff)

if primeiro_erro then
    print("Primeira divergência:")
    print("  índice:", primeiro_erro.index)
    print("  Lua:", primeiro_erro.lua)
    print("  C:", primeiro_erro.c)
    print("  Diferença:", primeiro_erro.diff)
end

-- Verifica pontos importantes da senoide.
print("\n=== PONTOS DA SENOIDE ===")

local pontos = {
    0,
    1024,
    2048,
    3072,
    4096,
    5120,
    6144,
    7168,
    8191,
    8192,
    9216,
    10239
}

for _, i in ipairs(pontos) do
    local lua_value = tables.finesine[i + lua_offset]
    local c_value = string.unpack("=i4", data, i * 4 + 1)

    print(string.format(
        "%5d | Lua: %8d | C: %8d",
        i, lua_value, c_value
    ))
end

-- Verifica a fórmula matemática independentemente das tabelas.
print("\n=== TESTE MATEMÁTICO ===")

local formula_errors = 0
local formula_max_diff = 0

for i = 0, FINESINE_SIZE - 1 do
    local expected = math.modf(
        FRACUNIT * math.sin(
            (i + 0.5) * 2 * math.pi / FINEANGLES
        )
    )

    local c_value = string.unpack("=i4", data, i * 4 + 1)
    local diff = math.abs(expected - c_value)

    if diff > formula_max_diff then
        formula_max_diff = diff
    end

    if diff > 1 then
        formula_errors = formula_errors + 1
    end
end

print("Erros na fórmula (tolerância 1):", formula_errors)
print("Maior diferença da fórmula:", formula_max_diff)

assert(divergencias == 0,
    "A tabela Lua diverge da tabela C!")

assert(formula_errors == 0,
    "A tabela C diverge da fórmula matemática!")

print("\nTESTE FINESINE PASSOU!")