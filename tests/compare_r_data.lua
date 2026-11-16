local wad = require("wad")
local rdata_lua = require("r_data")
local rdata_c = require("r_data_c")

local w = wad.new()
wad.add_file(w, wad.find_iwad())

local lua = rdata_lua.new(w)
rdata_lua.init(lua)

local c = rdata_c.new(w)
c:init()

local function compare(name, a, b)
    if a == b then
        print("[OK] " .. name .. ": " .. tostring(a))
    else
        print("[DIFERENÇA] " .. name ..
            " | Lua: " .. tostring(a) ..
            " | C: " .. tostring(b))
    end
end

print("\n=== CONTAGENS ===")

compare("Texturas", #lua.textures, c:texture_count())
compare("Flats", #lua.flattranslation, c:flat_count())

print("\n=== TEXTURAS ===")

local errors = 0

for i = 1, #lua.textures do
    local lt = lua.textures[i]
    local ct = c:texture_info(i)

    local fields = {
        "name",
        "width",
        "height",
        "widthmask"
    }

    for _, field in ipairs(fields) do
        if lt[field] ~= ct[field] then
            print(string.format(
                "[DIFERENÇA] Textura %d, %s: Lua=%s C=%s",
                i, field,
                tostring(lt[field]),
                tostring(ct[field])
            ))
            errors = errors + 1
        end
    end

    if #lt.patches ~= #ct.patches then
        print(string.format(
            "[DIFERENÇA] Textura %d, patches: Lua=%d C=%d",
            i, #lt.patches, #ct.patches
        ))
        errors = errors + 1
    end

    for j = 1, #lt.patches do
        local lp = lt.patches[j]
        local cp = ct.patches[j]

        for _, field in ipairs({"originx", "originy", "patch"}) do
            if lp[field] ~= cp[field] then
                print(string.format(
                    "[DIFERENÇA] Textura %d, patch %d, %s: Lua=%s C=%s",
                    i, j, field,
                    tostring(lp[field]),
                    tostring(cp[field])
                ))
                errors = errors + 1
            end
        end
    end

    for j = 1, lt.width do
        if lt.col_lump[j] ~= ct.col_lump[j] then
            print(string.format(
                "[DIFERENÇA] Textura %d, col_lump[%d]: Lua=%s C=%s",
                i, j,
                tostring(lt.col_lump[j]),
                tostring(ct.col_lump[j])
            ))
            errors = errors + 1
        end

        if lt.col_ofs[j] ~= ct.col_ofs[j] then
            print(string.format(
                "[DIFERENÇA] Textura %d, col_ofs[%d]: Lua=%s C=%s",
                i, j,
                tostring(lt.col_ofs[j]),
                tostring(ct.col_ofs[j])
            ))
            errors = errors + 1
        end
    end
end

print("\n=== RESULTADO ===")

if errors == 0 then
    print("Todas as texturas são equivalentes!")
else
    print("Total de diferenças:", errors)
end