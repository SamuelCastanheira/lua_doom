local compat = require("compat")
local fixed_c = require("test_fixed_c")

local MIN = -2147483648
local MAX = 2147483647

local total = 0

local function check_equal(expected, actual, message)
assert(
expected == actual,
string.format(
"%s: esperado %s, recebido %s",
message,
tostring(expected),
tostring(actual)
)
)

total = total + 1

end

-- Valores extremos e representativos.
local values = {
MIN,
MIN + 1,
-1000000000,
-65536,
-32768,
-1000,
-1,
0,
1,
1000,
32768,
65536,
1000000000,
MAX - 1,
MAX
}

-- ABS
for _, a in ipairs(values) do
check_equal(
compat.abs_fixed(a),
fixed_c.abs_fixed(a),
"abs_fixed(" .. a .. ")"
)
end

-- FIXED MUL
for _, a in ipairs(values) do
for _, b in ipairs(values) do
check_equal(
compat.fixed_mul(a, b),
fixed_c.fixed_mul(a, b),
"fixed_mul(" .. a .. ", " .. b .. ")"
)
end
end

-- FIXED DIV
for _, a in ipairs(values) do
for _, b in ipairs(values) do
check_equal(
compat.fixed_div(a, b),
fixed_c.fixed_div(a, b),
"fixed_div(" .. a .. ", " .. b .. ")"
)
end
end

-- Testes aleatórios
math.randomseed(12345)

for i = 1, 5000 do
local a = math.random(MIN, MAX)
local b = math.random(MIN, MAX)

check_equal(
    compat.fixed_mul(a, b),
    fixed_c.fixed_mul(a, b),
    "fixed_mul aleatório " .. i
)

check_equal(
    compat.fixed_div(a, b),
    fixed_c.fixed_div(a, b),
    "fixed_div aleatório " .. i
)

check_equal(
    compat.abs_fixed(a),
    fixed_c.abs_fixed(a),
    "abs_fixed aleatório " .. i
)

end

print("Todos os testes passaram!")
print("Total de comparações:", total)