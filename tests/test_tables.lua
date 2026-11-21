local lua_tables = require("tables")
local c_tables = require("tables_c")

local function check(condition, message)
if not condition then
error(message, 2)
end
end

local function equal(expected, actual, message)
check(
expected == actual,
message .. " | esperado: " .. tostring(expected)
.. " | recebido: " .. tostring(actual)
)
end

local function test_arrays(lua_array, c_get, first, last, name)
for i = first, last do
equal(
lua_array[i],
c_get(i),
name .. "[" .. i .. "]"
)
end

print(name .. ": OK")

end

-- Inicialização
lua_tables.init()

local c = c_tables.new()
c:init()

-- =========================================================
-- Comparação das tabelas completas
-- =========================================================

print("Testando tabelas...")

test_arrays(
lua_tables.finesine,
function(i) return c:get_finesine(i) end,
0,
lua_tables.FINEANGLES * 5 / 4 - 1,
"finesine"
)

test_arrays(
lua_tables.finetangent,
function(i) return c:get_finetangent(i) end,
0,
lua_tables.FINEANGLES / 2 - 1,
"finetangent"
)

test_arrays(
lua_tables.tantoangle,
function(i) return c:get_tantoangle(i) end,
0,
2048,
"tantoangle"
)

-- =========================================================
-- fine_sin e fine_cos
-- =========================================================

print("Testando fine_sin e fine_cos...")

local angles = {
0,
1,
-1,
1073741824,
-1073741824,
2147483647,
-2147483648,
123456789,
-987654321
}

for _, angle in ipairs(angles) do
equal(
lua_tables.fine_sin(angle),
c:fine_sin(angle),
"fine_sin(" .. angle .. ")"
)

equal(
    lua_tables.fine_cos(angle),
    c:fine_cos(angle),
    "fine_cos(" .. angle .. ")"
)

end

math.randomseed(12345)

for i = 1, 10000 do
local angle = math.random(-2147483647, 2147483647)

equal(
    lua_tables.fine_sin(angle),
    c:fine_sin(angle),
    "fine_sin aleatório #" .. i
)

equal(
    lua_tables.fine_cos(angle),
    c:fine_cos(angle),
    "fine_cos aleatório #" .. i
)

end

print("fine_sin/fine_cos: OK")

-- =========================================================
-- slope_div
-- =========================================================

print("Testando slope_div...")

local numerators = {
-2147483648,
-2147483647,
-100000,
-1000,
-1,
0,
1,
1000,
100000,
2147483647
}

local denominators = {
-1000,
-1,
0,
1,
511,
512,
513,
1024,
2048,
4096,
65536,
2147483647
}

for _, num in ipairs(numerators) do
for _, den in ipairs(denominators) do
equal(
lua_tables.slope_div(num, den),
c:slope_div(num, den),
"slope_div(" .. num .. ", " .. den .. ")"
)
end
end

for i = 1, 10000 do
local num = math.random(-2147483647, 2147483647)
local den = math.random(-2147483647, 2147483647)

equal(
    lua_tables.slope_div(num, den),
    c:slope_div(num, den),
    "slope_div aleatório #" .. i
)

end

print("slope_div: OK")

print("\nTodos os testes passaram!")