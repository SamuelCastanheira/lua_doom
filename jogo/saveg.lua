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
-- Save de 6 vagas. Cabecalho de 24 bytes, magica DOOMPY01 e JSON, como saveg.py.

local collision = require("collision")

local M = {}

local SAVESTRINGSIZE = 24
local MAGIC = "DOOMPY01"
local EMPTY = "empty slot"

local function enc_str(s)
  return '"' .. (s or ""):gsub('[%z\1-\31\\"]', function(c)
    if c == '"' then
      return '\\"'
    end
    if c == "\\" then
      return "\\\\"
    end
    if c == "\n" then
      return "\\n"
    end
    if c == "\r" then
      return "\\r"
    end
    if c == "\t" then
      return "\\t"
    end
    return string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function enc(v)
  if v == nil then
    return "null"
  end
  local t = type(v)
  if t == "boolean" then
    if v then
      return "true"
    end
    return "false"
  end
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      return "null"
    end
    if v == math.floor(v) and math.abs(v) < 9007199254740992 then
      return string.format("%.0f", v)
    end
    return string.format("%.17g", v)
  end
  if t == "string" then
    return enc_str(v)
  end
  if t == "table" then
    if v._json == "array" then
      local parts = {}
      for i = 1, #v do
        parts[i] = enc(v[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local parts = {}
    for i = 1, #v do
      parts[i] = enc_str(v[i][1]) .. ":" .. enc(v[i][2])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

local function arr(list)
  list._json = "array"
  return list
end

local function skip(s, i)
  local n = #s
  while i <= n do
    local c = s:sub(i, i)
    if c ~= " " and c ~= "\n" and c ~= "\r" and c ~= "\t" then
      return i
    end
    i = i + 1
  end
  return i
end

local function parse_at(s, i)
  i = skip(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    local obj = {}
    i = i + 1
    i = skip(s, i)
    if s:sub(i, i) == "}" then
      return obj, i + 1
    end
    while true do
      local key
      key, i = parse_at(s, i)
      i = skip(s, i)
      i = i + 1
      local val
      val, i = parse_at(s, i)
      if key ~= nil then
        obj[key] = val
      end
      i = skip(s, i)
      c = s:sub(i, i)
      if c == "}" then
        return obj, i + 1
      end
      i = i + 1
    end
  end
  if c == "[" then
    local list = {}
    i = i + 1
    i = skip(s, i)
    if s:sub(i, i) == "]" then
      return list, i + 1
    end
    while true do
      local val
      val, i = parse_at(s, i)
      list[#list + 1] = val
      i = skip(s, i)
      c = s:sub(i, i)
      if c == "]" then
        return list, i + 1
      end
      i = i + 1
    end
  end
  if c == '"' then
    i = i + 1
    local out = {}
    while i <= #s do
      local ch = s:sub(i, i)
      if ch == '"' then
        return table.concat(out), i + 1
      end
      if ch == "\\" then
        local e = s:sub(i + 1, i + 1)
        if e == "n" then
          out[#out + 1] = "\n"
        elseif e == "r" then
          out[#out + 1] = "\r"
        elseif e == "t" then
          out[#out + 1] = "\t"
        elseif e == "u" then
          local hex = s:sub(i + 2, i + 5)
          out[#out + 1] = string.char(tonumber(hex, 16) or 0)
          i = i + 4
        else
          out[#out + 1] = e
        end
        i = i + 2
      else
        out[#out + 1] = ch
        i = i + 1
      end
    end
    return table.concat(out), i
  end
  if s:sub(i, i + 3) == "true" then
    return true, i + 4
  end
  if s:sub(i, i + 4) == "false" then
    return false, i + 5
  end
  if s:sub(i, i + 3) == "null" then
    return nil, i + 4
  end
  local rest = s:sub(i)
  local num = rest:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*")
  if num == nil or num == "" or num == "-" then
    return nil, i + 1
  end
  return tonumber(num), i + #num
end

function M.decode(text)
  local value = parse_at(text, 1)
  return value
end

function M.encode(pairs)
  return enc(pairs)
end

local function save_dir(game)
  local path = game.iwad_path or ""
  local dir = path:match("^(.*)[/\\][^/\\]+$")
  if dir ~= nil and dir ~= "" then
    return dir
  end
  return "."
end

-- Os saves ficam na pasta saves/, ao lado do IWAD (antes, na pasta do
-- IWAD). A barra "/" serve tambem no Windows.
local function pasta_saves(game)
  local dir = save_dir(game)
  if dir == "." then
    return "saves"
  end
  return dir .. "/saves"
end

function M.path(game, slot)
  return pasta_saves(game) .. "/doomsav" .. tostring(slot) .. ".dsg"
end

local function pad_desc(text)
  text = tostring(text or "")
  if #text > SAVESTRINGSIZE then
    text = text:sub(1, SAVESTRINGSIZE)
  end
  return text .. string.rep("\0", SAVESTRINGSIZE - #text)
end

local function decode_desc(raw)
  local cut = raw:find("\0", 1, true)
  if cut then
    raw = raw:sub(1, cut - 1)
  end
  return (raw:gsub("%s+$", ""))
end

function M.description(game, slot)
  local f = io.open(M.path(game, slot), "rb")
  if f == nil then
    return EMPTY, false
  end
  local header = f:read(SAVESTRINGSIZE + #MAGIC)
  f:close()
  if header == nil or #header < SAVESTRINGSIZE + #MAGIC then
    return EMPTY, false
  end
  if header:sub(SAVESTRINGSIZE + 1, SAVESTRINGSIZE + #MAGIC) ~= MAGIC then
    return EMPTY, false
  end
  local desc = decode_desc(header:sub(1, SAVESTRINGSIZE))
  if desc == "" then
    desc = EMPTY
  end
  return desc, true
end

local function num_list(src, n)
  local list = {}
  for i = 0, n - 1 do
    list[i + 1] = src[i] or 0
  end
  return arr(list)
end

local function bool_list(src, n)
  local list = {}
  for i = 0, n - 1 do
    list[i + 1] = src[i] and true or false
  end
  return arr(list)
end

local function mobj_index(mobjs, mo)
  if mo == nil then
    return nil
  end
  for i = 1, #mobjs do
    if mobjs[i] == mo then
      return i - 1
    end
  end
  return nil
end

-- C5: o mobj inteiro, como o P_ArchiveThinkers grava o mobj_t, com o tipo
-- (o load recria o mobj a partir disto). target e tracer sao indices na
-- lista; spawnpoint e o mapthing (o pesadelo, -respawn, o usa).
local CAMPOS_MOBJ = {
  "x", "y", "z", "angle", "momx", "momy", "momz", "radius", "height",
  "floorz", "ceilingz", "flags", "health", "type", "doomednum", "sprite",
  "frame", "tics", "istate", "alive", "reactiontime", "lastlook",
  "threshold", "movedir", "movecount", "damage", "fx", "_easy_skip",
}

local function dump_mobj(mo, mobjs)
  local rec = {}
  for i = 1, #CAMPOS_MOBJ do
    local k = CAMPOS_MOBJ[i]
    rec[#rec + 1] = { k, mo[k] }
  end
  rec[#rec + 1] = { "target", mobj_index(mobjs, mo.target) }
  rec[#rec + 1] = { "tracer", mobj_index(mobjs, mo.tracer) }
  local sp = mo.spawnpoint
  if sp then
    rec[#rec + 1] = { "spawnpoint", {
      { "x", sp.x }, { "y", sp.y }, { "angle", sp.angle },
      { "type", sp.type }, { "options", sp.options },
    } }
  end
  rec[#rec + 1] = { "is_player", mo.player ~= nil }
  return rec
end

local function dump_player(p)
  return {
    { "playerstate", p.playerstate or 0 },
    { "viewz", p.viewz or 0 },
    { "viewheight", p.viewheight or 0 },
    { "deltaviewheight", p.deltaviewheight or 0 },
    { "bob", p.bob or 0 },
    { "health", p.health or 0 },
    { "armorpoints", p.armorpoints or 0 },
    { "armortype", p.armortype or 0 },
    { "ammo", num_list(p.ammo or {}, 4) },
    { "maxammo", num_list(p.maxammo or {}, 4) },
    { "weaponowned", bool_list(p.weaponowned or {}, 9) },
    { "pendingweapon", p.pendingweapon or 0 },
    { "readyweapon", p.readyweapon or 0 },
    { "cards", bool_list(p.cards or {}, 6) },
    { "cheats", p.cheats or 0 },
    { "message", p.message or "" },
    { "message_tics", p.message_tics or 0 },
    { "attackdown", p.attackdown and true or false },
    { "usedown", p.usedown and true or false },
    { "damagecount", p.damagecount or 0 },
    { "bonuscount", p.bonuscount or 0 },
    { "extralight", p.extralight or 0 },
    { "refire", p.refire or 0 },
    { "killcount", p.killcount or 0 },
    { "itemcount", p.itemcount or 0 },
    { "secretcount", p.secretcount or 0 },
    { "didsecret", p.didsecret and true or false },
    -- C3: os dois psprites (a arma e o clarao), como o P_ArchivePlayers
    { "psp0_state", p.psprites[0].state },
    { "psp0_tics", p.psprites[0].tics },
    { "psp0_sx", p.psprites[0].sx },
    { "psp0_sy", p.psprites[0].sy },
    { "psp1_state", p.psprites[1].state },
    { "psp1_tics", p.psprites[1].tics },
    { "psp1_sx", p.psprites[1].sx },
    { "psp1_sy", p.psprites[1].sy },
    { "powers", num_list(p.powers or {}, 6) },
  }
end

local function sector_index(world, sector)
  for i = 1, #world.sectors do
    if world.sectors[i] == sector then
      return i - 1
    end
  end
  return -1
end

local function dump_thinker(th, world)
  local sec_i = sector_index(world, th.sector)
  if sec_i < 0 then
    return nil
  end
  if th.kind == "door" then
    return {
      { "kind", "door" },
      { "sector", sec_i },
      { "type", th.type or 0 },
      { "direction", th.direction or 0 },
      { "topheight", th.topheight or 0 },
      { "speed", th.speed or 0 },
      { "topwait", th.topwait or 0 },
      { "topcountdown", th.topcountdown or 0 },
    }
  end
  if th.kind == "plat" then
    return {
      { "kind", "plat" },
      { "sector", sec_i },
      { "type", th.type or 0 },
      { "status", th.status or 0 },
      { "speed", th.speed or 0 },
      { "low", th.low or 0 },
      { "high", th.high or 0 },
      { "wait", th.wait or 0 },
      { "count", th.count or 0 },
      { "oldstatus", th.oldstatus or 0 },   -- C4d: o status de antes de parar
    }
  end
  if th.kind == "floor" then
    return {
      { "kind", "floor" },
      { "sector", sec_i },
      { "direction", th.direction or 0 },
      { "dest", th.dest or 0 },
      { "speed", th.speed or 0 },
      { "crush", th.crush and true or false },    -- C5: o piso inteiro
      { "floorpic", th.floorpic },
      { "newspecial", th.newspecial },
    }
  end
  if th.kind == "ceiling" then                  -- C5: os tetos (P_ArchiveSpecials)
    return {
      { "kind", "ceiling" },
      { "sector", sec_i },
      { "ctype", th.ctype or 0 },
      { "direction", th.direction or 0 },
      { "speed", th.speed or 0 },
      { "crush", th.crush and true or false },
      { "topheight", th.topheight or 0 },
      { "bottomheight", th.bottomheight or 0 },
      { "parado", th.parado and true or false },
    }
  end
  return nil
end

-- C5: uma luz (P_ArchiveSpecials: tc_flash, tc_strobe, tc_glow; o fogo
-- tambem, que o Doom nao grava), com os campos do registro do Doom
local function dump_luz(l, world)
  local sec_i = sector_index(world, l.sector or l.setor)
  local rec = { { "kind", l.kind }, { "sector", sec_i },
    { "maxlight", l.maxlight }, { "minlight", l.minlight } }
  if l.kind == "glow" then
    rec[#rec + 1] = { "direction", l.direction }
  else
    rec[#rec + 1] = { "count", l.count }
  end
  if l.kind == "flash" then
    rec[#rec + 1] = { "maxtime", l.maxtime }
    rec[#rec + 1] = { "mintime", l.mintime }
  elseif l.kind == "strobe" then
    rec[#rec + 1] = { "darktime", l.darktime }
    rec[#rec + 1] = { "brighttime", l.brighttime }
  end
  return rec
end

local function dump_state(game)
  local world = game.world
  local mobjs = world.mobjs or {}
  local mobj_rows = {}
  for i = 1, #mobjs do
    mobj_rows[i] = dump_mobj(mobjs[i], mobjs)
  end
  local sectors = {}
  for i = 1, #world.sectors do
    local s = world.sectors[i]
    sectors[i] = {
      { "floorheight", s.floorheight or 0 },
      { "ceilingheight", s.ceilingheight or 0 },
      { "floorpic", s.floorpic or 0 },
      { "ceilingpic", s.ceilingpic or 0 },
      { "lightlevel", s.lightlevel or 0 },
      { "special", s.special or 0 },
    }
  end
  local sides = {}
  for i = 1, #(world.sides or {}) do
    local sd = world.sides[i]
    sides[i] = {
      { "textureoffset", sd.textureoffset or 0 },
      { "rowoffset", sd.rowoffset or 0 },
      { "toptexture", sd.toptexture or 0 },
      { "bottomtexture", sd.bottomtexture or 0 },
      { "midtexture", sd.midtexture or 0 },
    }
  end
  local lines = {}
  for i = 1, #(world.lines or {}) do
    local ln = world.lines[i]
    lines[i] = {
      { "flags", ln.flags or 0 },
      { "special", ln.special or 0 },
    }
  end
  local thinkers = {}
  if game.specials and game.specials.thinkers then
    for i = 1, #game.specials.thinkers do
      local th = game.specials.thinkers[i]
      if not th.dead then
        local rec = dump_thinker(th, world)
        if rec then
          thinkers[#thinkers + 1] = rec
        end
      end
    end
  end
  -- C5: as luzes, na ordem da lista
  local luzes = {}
  for i = 1, #((game.specials and game.specials.lights) or {}) do
    luzes[#luzes + 1] = dump_luz(game.specials.lights[i], world)
  end
  local buttons = {}
  if game.specials and game.specials.buttons then
    for i = 1, #game.specials.buttons do
      local btn = game.specials.buttons[i]
      local line = btn.line
      local idx = -1
      if line and line.i_line ~= nil then
        idx = line.i_line
      end
      buttons[#buttons + 1] = {
        { "line", idx },
        { "where", btn.attr or "toptexture" },
        { "texture", btn.texture or 0 },
        { "timer", btn.timer or 0 },
      }
    end
  end
  return {
    { "episode", game.episode or 1 },
    { "mapn", game.mapn or 1 },
    { "skill", game.skill or 2 },
    { "leveltime", game.leveltime or 0 },
    { "player", dump_player(game.player) },
    { "sectors", arr(sectors) },
    { "sides", arr(sides) },
    { "lines", arr(lines) },
    { "mobjs", arr(mobj_rows) },
    { "thinkers", arr(thinkers) },
    { "luzes", arr(luzes) },
    { "buttons", arr(buttons) },
    { "totalkills", game.totalkills or 0 },
    { "totalitems", game.totalitems or 0 },
    { "totalsecret", game.totalsecret or 0 },
  }
end

function M.write(game, slot, description)
  if game.world == nil or game.player == nil then
    return false
  end
  local payload = enc(dump_state(game))
  local blob = pad_desc(description) .. MAGIC .. payload
  local path = M.path(game, slot)
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "wb")
  if f == nil then
    os.execute('mkdir "' .. pasta_saves(game) .. '"')  -- a pasta saves/ ainda nao existe
    f = io.open(tmp, "wb")
  end
  if f == nil then
    return false
  end
  f:write(blob)
  f:close()
  os.remove(path)
  if not os.rename(tmp, path) then
    return false
  end
  return true
end

function M.read(game, slot)
  local f = io.open(M.path(game, slot), "rb")
  if f == nil then
    return nil
  end
  local data = f:read("*a")
  f:close()
  local need = SAVESTRINGSIZE + #MAGIC
  if data == nil or #data < need then
    return nil
  end
  if data:sub(SAVESTRINGSIZE + 1, need) ~= MAGIC then
    return nil
  end
  return M.decode(data:sub(need + 1))
end

local function copy_nums(dst, src)
  if src == nil then
    return
  end
  for i = 1, #src do
    dst[i - 1] = src[i]
  end
end

local function apply_player(player, rec)
  if rec == nil then
    return
  end
  local function take(name, fallback)
    if rec[name] ~= nil then
      return rec[name]
    end
    return fallback
  end
  player.playerstate = take("playerstate", player.playerstate)
  player.viewz = take("viewz", player.viewz)
  player.viewheight = take("viewheight", player.viewheight)
  player.deltaviewheight = take("deltaviewheight", player.deltaviewheight)
  player.bob = take("bob", player.bob)
  player.health = take("health", player.health)
  player.armorpoints = take("armorpoints", player.armorpoints)
  player.armortype = take("armortype", player.armortype)
  if rec.ammo then
    copy_nums(player.ammo, rec.ammo)
  end
  if rec.maxammo then
    copy_nums(player.maxammo, rec.maxammo)
  end
  if rec.weaponowned then
    for i = 1, #rec.weaponowned do
      player.weaponowned[i - 1] = rec.weaponowned[i] and true or false
    end
  end
  player.pendingweapon = take("pendingweapon", player.pendingweapon)
  player.readyweapon = take("readyweapon", player.readyweapon)
  if rec.cards then
    for i = 1, #rec.cards do
      player.cards[i - 1] = rec.cards[i] and true or false
    end
  end
  player.cheats = take("cheats", player.cheats)
  player.message = take("message", "")
  player.message_tics = take("message_tics", 0)
  player.attackdown = rec.attackdown and true or false
  player.usedown = rec.usedown and true or false
  player.damagecount = take("damagecount", 0)
  player.bonuscount = take("bonuscount", 0)
  player.extralight = take("extralight", 0)
  player.refire = take("refire", 0)
  player.killcount = take("killcount", 0)
  player.itemcount = take("itemcount", 0)
  player.secretcount = take("secretcount", 0)
  player.didsecret = rec.didsecret and true or false
  -- C3: os psprites; um save de antes do C3 nao os tem, e a arma fica como
  -- o nivel a montou (subindo)
  for i = 0, 1 do
    local psp = player.psprites[i]
    psp.state = take("psp" .. i .. "_state", psp.state)
    psp.tics = take("psp" .. i .. "_tics", psp.tics)
    psp.sx = take("psp" .. i .. "_sx", psp.sx)
    psp.sy = take("psp" .. i .. "_sy", psp.sy)
  end
  if rec.powers then
    copy_nums(player.powers, rec.powers)
  end
  if player.mo then
    player.mo.health = player.health
  end
end

-- C5: os campos de um mobj gravado (sem target e tracer, ligados depois)
local function campos_mobj(rec)
  local campos = {}
  for i = 1, #CAMPOS_MOBJ do
    local k = CAMPOS_MOBJ[i]
    campos[k] = rec[k]
  end
  if campos.alive == nil then
    campos.alive = true
  end
  -- um save de antes do C5 nao tem estes campos: os valores do mobj novo
  if campos.lastlook == nil then
    campos.lastlook = 0
  end
  if campos.threshold == nil then
    campos.threshold = 0
  end
  if campos.reactiontime == nil then
    campos.reactiontime = 0
  end
  if campos.movecount == nil then
    campos.movecount = 0
  end
  if campos.movedir == nil then
    campos.movedir = 8
  end
  if campos.doomednum == nil and campos.type then
    local info = require("info")
    local row = info.MOBJINFO[campos.type]
    campos.doomednum = row and row[info.MI_DOOMEDNUM]
  end
  if rec.spawnpoint then
    local sp = rec.spawnpoint
    campos.spawnpoint = { x = sp.x, y = sp.y, angle = sp.angle, type = sp.type, options = sp.options }
  end
  return campos
end


-- C5: o load apaga o que o nivel acabou de criar (os mobjs, menos o do
-- jogador, e os specials), como o P_UnArchiveThinkers e o
-- P_UnArchiveSpecials, e recria tudo a partir do save.
local function limpar_nivel(game, data)
  local world = game.world
  local thinker = require("thinker")
  local lista = {}
  for i = 1, #world.mobjs do
    lista[i] = world.mobjs[i]
  end
  for i = 1, #lista do
    local mo = lista[i]
    if mo == game.player.mo then
      collision.unset_thing_position(world, mo)
      table.remove(world.mobjs, 1)
    else
      thinker.remove_mobj(world, mo)
    end
  end
  for i = 1, #world.sectors do
    world.sectors[i].specialdata = nil
  end
  if game.specials then
    game.specials.thinkers = {}
    if data.luzes ~= nil then             -- um save de antes do C5 nao tem as luzes
      game.specials.lights = {}
    end
    game.specials.buttons = {}
    game.specials.tetos_ativos = {}
    game.specials.plats_ativos = {}
  end
end

-- Monta o nivel do save e aplica o estado gravado.
function M.apply(game, data)
  if data == nil or game.start_level == nil then
    return false
  end
  game.carry = nil
  game.episode = data.episode or game.episode
  game.mapn = data.mapn or game.mapn
  game.skill = data.skill or game.skill
  game.start_level(game)
  if game.world == nil or game.player == nil then
    return false
  end
  limpar_nivel(game, data)                -- C5
  game.leveltime = data.leveltime or 0
  game.totalkills = data.totalkills or game.totalkills
  game.totalitems = data.totalitems or game.totalitems
  game.totalsecret = data.totalsecret or game.totalsecret
  local world = game.world
  local sectors = data.sectors or {}
  for i = 1, #sectors do
    local s = world.sectors[i]
    local rec = sectors[i]
    if s and rec then
      s.floorheight = rec.floorheight or s.floorheight
      s.ceilingheight = rec.ceilingheight or s.ceilingheight
      s.floorpic = rec.floorpic or s.floorpic
      s.ceilingpic = rec.ceilingpic or s.ceilingpic
      s.lightlevel = rec.lightlevel or s.lightlevel
      s.special = rec.special or s.special
    end
  end
  local sides = data.sides or {}
  for i = 1, #sides do
    local sd = world.sides[i]
    local rec = sides[i]
    if sd and rec then
      sd.textureoffset = rec.textureoffset or sd.textureoffset
      sd.rowoffset = rec.rowoffset or sd.rowoffset
      sd.toptexture = rec.toptexture or sd.toptexture
      sd.bottomtexture = rec.bottomtexture or sd.bottomtexture
      sd.midtexture = rec.midtexture or sd.midtexture
    end
  end
  local lines = data.lines or {}
  for i = 1, #lines do
    local ln = world.lines[i]
    local rec = lines[i]
    if ln and rec then
      ln.flags = rec.flags or ln.flags
      ln.special = rec.special or ln.special
    end
  end
  local where_attr = {
    top = "toptexture",
    middle = "midtexture",
    bottom = "bottomtexture",
    toptexture = "toptexture",
    midtexture = "midtexture",
    bottomtexture = "bottomtexture",
  }
  if game.specials then
    local thinkers = data.thinkers or {}
    for i = 1, #thinkers do
      local rec = thinkers[i]
      local sec_i = rec.sector or -1
      local sector = world.sectors[sec_i + 1]
      if sector then
        local th = {
          kind = rec.kind,
          sector = sector,
          type = rec.type or 0,
          direction = rec.direction or 0,
          topheight = rec.topheight or 0,
          speed = rec.speed or 0,
          topwait = rec.topwait or 0,
          topcountdown = rec.topcountdown or 0,
          status = rec.status or 0,
          low = rec.low or 0,
          high = rec.high or 0,
          wait = rec.wait or 0,
          count = rec.count or 0,
          oldstatus = rec.oldstatus or 0,
          dest = rec.dest or 0,
          ctype = rec.ctype or 0,                -- C5: tetos e pisos inteiros
          crush = rec.crush and true or false,
          bottomheight = rec.bottomheight or 0,
          parado = rec.parado and true or false,
          floorpic = rec.floorpic,
          newspecial = rec.newspecial,
          dead = false,
        }
        if th.kind == "door" or th.kind == "plat" or th.kind == "floor" then
          sector.specialdata = th
          game.specials.thinkers[#game.specials.thinkers + 1] = th
          if th.kind == "plat" then
            require("specials").add_active_plat(game.specials, th)  -- C4d
          end
        elseif th.kind == "ceiling" then
          require("specials").start_teto_gravado(game.specials, th)  -- C5
        end
      end
    end
    -- C5: as luzes, na ordem gravada
    local luzes = data.luzes or {}
    for i = 1, #luzes do
      local sector = world.sectors[(luzes[i].sector or -1) + 1]
      if sector then
        require("specials").start_luz(game.specials, luzes[i], sector)
      end
    end
    local buttons = data.buttons or {}
    for i = 1, #buttons do
      local rec = buttons[i]
      local li = rec.line or -1
      local line = world.lines[li + 1]
      if line then
        game.specials.buttons[#game.specials.buttons + 1] = {
          line = line,
          attr = where_attr[rec.where or ""] or "toptexture",
          texture = rec.texture or 0,
          timer = rec.timer or 0,
        }
      end
    end
  end
  -- C5: os mobjs sao recriados a partir do save, na ordem gravada (antes, os
  -- registros eram aplicados por indice aos mobjs que o nivel acabou de
  -- criar, e caiam nos mobjs errados quando a lista tinha mudado)
  local thinker = require("thinker")
  local recs = data.mobjs or {}
  local novos = {}
  for i = 1, #recs do
    local campos = campos_mobj(recs[i])
    if recs[i].is_player then
      local mo = game.player.mo
      -- C8: um save de antes do C8 nao tem o estado do corpo do jogador (ou
      -- tem 0): fica o S_PLAY do mobj novo
      if (campos.istate or 0) == 0 then
        campos.istate, campos.tics, campos.sprite, campos.frame = nil, nil, nil, nil
      end
      for k, v in pairs(campos) do
        mo[k] = v
      end
      world.mobjs[#world.mobjs + 1] = mo
      collision.set_thing_position(world, mo)
      novos[i] = mo
    else
      novos[i] = thinker.recriar_mobj(world, campos, game)
    end
  end
  for i = 1, #recs do
    local ti, tr = recs[i].target, recs[i].tracer
    if type(ti) == "number" and ti >= 0 then
      novos[i].target = novos[ti + 1]
    end
    if type(tr) == "number" and tr >= 0 then
      novos[i].tracer = novos[tr + 1]
    end
  end
  apply_player(game.player, data.player)
  if game.status and game.player then
    local status = require("status")
    status.reset(game.status, game.player)
  end
  game.gamestate = "view"
  return true
end

function M.load(game, slot)
  local data = M.read(game, slot)
  if data == nil then
    return false
  end
  return M.apply(game, data)
end

return M
