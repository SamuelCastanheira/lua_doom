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
-- Jogador, gravidade e armas, a partir de player.py.

local compat = require("compat")
-- finesine, tantoangle e slope_div: as tabelas do Doom, em C (tables_c)
local tabela = require("tables_c").padrao
local collision = require("collision")
local rng = require("random")
local pspr = require("pspr")

local M = {}

local band, bnot = compat.band, compat.bnot
local shar = compat.shar
local as_u32 = compat.as_u32
local fixed_mul = compat.fixed_mul

local PW_ALLMAP = 4
local MF_DROPPED = 131072
local MF_COUNTITEM = 8388608
local MAXBONUS = 200
local BONUSADD = 6



local FRACUNIT = 65536
local ANG90 = 1073741824
local ANG180 = 2147483648
local FINEMASK = 8191
local FINEANGLES = 8192
local FRICTION = 59392
local GRAVITY = FRACUNIT
local STOPSPEED = 4096
local MAXMOVE = 30 * FRACUNIT
local MAXBOB = 1048576
local VIEWHEIGHT = 41 * FRACUNIT
local PLAYER_RADIUS = 16 * FRACUNIT
local PLAYER_HEIGHT = 56 * FRACUNIT
local MELEERANGE = 64 * FRACUNIT
local MISSILERANGE = 32 * 64 * FRACUNIT
local MF_SOLID = 2
local MF_SHOOTABLE = 4
local MF_DROPOFF = 1024
local MF_PICKUP = 2048
local MF_NOCLIP = 4096
local MF_NOGRAVITY = 512
local MF_MISSILE = 65536
local MF_CORPSE = 1048576
local MF_SKULLFLY = 16777216
local MF_SHADOW = 262144
local CF_NOCLIP = 1
local CF_GODMODE = 2
local CF_NOMOMENTUM = 4
local PST_LIVE = 0
local PST_DEAD = 1
local PST_REBORN = 2
local PW_INVULNERABILITY = 0
local PW_STRENGTH = 1
local PW_INVISIBILITY = 2
local PW_IRONFEET = 3
local PW_INFRARED = 5
local BT_ATTACK = 1
local BT_USE = 2
local BT_CHANGE = 4
local BT_WEAPONMASK = 56
local BT_WEAPONSHIFT = 3
local WP_FIST = 0
local WP_PISTOL = 1
local WP_SHOTGUN = 2
local WP_CHAINGUN = 3
local WP_MISSILE = 4
local WP_PLASMA = 5
local WP_BFG = 6
local WP_CHAINSAW = 7
local WP_SUPERSHOTGUN = 8
local WP_NOCHANGE = 10
local AM_CLIP = 0
local AM_SHELL = 1
local AM_CELL = 2
local AM_MISL = 3
local INVERSECOLORMAP = 32
local WEAPONTOP = 32 * FRACUNIT
local WEAPONBOTTOM = 128 * FRACUNIT
local TICRATE = 35
local MAXHEALTH = 100

local FORWARDMOVE = { [0] = 25, 50 }
local SIDEMOVE = { [0] = 24, 40 }
local ANGLETURN = { [0] = 640, 1280, 320 }

local function has(flags, bit)
  return band(flags or 0, bit) ~= 0
end

local function empty_cmd()
  return { forwardmove = 0, sidemove = 0, angleturn = 0, buttons = 0 }
end

local function trunc2(n)
  n = compat.as_i32(n)
  if n < 0 then
    return -math.floor((-n) / 2)
  end
  return math.floor(n / 2)
end

local WEAPON_AMMO = {
  [WP_PISTOL] = AM_CLIP,
  [WP_SHOTGUN] = AM_SHELL,
  [WP_SUPERSHOTGUN] = AM_SHELL,
  [WP_CHAINGUN] = AM_CLIP,
  [WP_MISSILE] = AM_MISL,
  [WP_PLASMA] = AM_CELL,
  [WP_BFG] = AM_CELL,
}

-- C3: as tabelas proprias da arma (WEAPON_PATCH, WEAPON_FIRE_BODY,
-- WEAPON_ATK, WEAPON_READY) sairam; a arma segue info.STATES (pspr.lua).

function M.damage_mobj(target, source, damage, inflictor)
  if target == nil or target.alive == false or not has(target.flags, MF_SHOOTABLE) then
    return
  end
  if target.player then
    local player = target.player
    if (has(player.cheats, CF_GODMODE) or (player.powers[PW_INVULNERABILITY] or 0) ~= 0) and damage < 1000 then
      return
    end
    local saved = 0
    if (player.armortype or 0) ~= 0 then
      local div = 2
      if player.armortype == 1 then
        div = 3
      end
      saved = math.floor(damage / div)
      if player.armorpoints <= saved then
        saved = player.armorpoints
        player.armortype = 0
      end
      player.armorpoints = player.armorpoints - saved
    end
    damage = damage - saved
    player.health = player.health - damage
    target.health = player.health
    player.damagecount = (player.damagecount or 0) + damage
    if player.damagecount > 100 then
      player.damagecount = 100
    end
    player.attacker = source
    if player.health <= 0 then
      player.health = 0
      target.health = 0
      player.playerstate = PST_DEAD
      target.alive = false
      target.flags = band(target.flags, bnot(MF_SOLID + MF_SHOOTABLE))
      pspr.soltar_arma(player, nil)  -- C3: P_KillMobj -> P_DropWeapon
    end
    return
  end
  target.health = (target.health or 0) - damage
  if target.health <= 0 then
    target.health = 0
    target.alive = false
    target.flags = band(target.flags, bnot(MF_SOLID + MF_SHOOTABLE))
  end
end

function M.spawn(world, start, cheats)
  local x = start.x * FRACUNIT
  local y = start.y * FRACUNIT
  local sub = collision.point_in_subsector(world, x, y)
  local flags = MF_SOLID + MF_SHOOTABLE + MF_PICKUP + MF_DROPOFF
  cheats = cheats or 0
  if has(cheats, CF_NOCLIP) then
    flags = compat.bor(flags, MF_NOCLIP)
  end
  local mo = {
    x = x,
    y = y,
    z = sub.sector.floorheight,
    angle = as_u32(math.floor(start.angle / 45) * 536870912),
    momx = 0,
    momy = 0,
    momz = 0,
    radius = PLAYER_RADIUS,
    height = PLAYER_HEIGHT,
    floorz = sub.sector.floorheight,
    ceilingz = sub.sector.ceilingheight,
    flags = flags,
    health = 100,
    type = 0,
    sprite = "PLAY",
    frame = 0,
    alive = true,
    player = nil,
    damage = 0,
  }
  local player = {
    mo = mo,
    cmd = empty_cmd(),
    playerstate = PST_LIVE,
    viewz = mo.z + VIEWHEIGHT,
    viewheight = VIEWHEIGHT,
    deltaviewheight = 0,
    bob = 0,
    health = 100,
    armorpoints = 0,
    armortype = 0,
    ammo = { [0] = 50, 0, 0, 0 },
    maxammo = { [0] = 200, 50, 300, 50 },
    clipammo = { [0] = 10, 4, 20, 1},
    weaponowned = { [0] = true, true, false, false, false, false, false, false, false },
    pendingweapon = WP_NOCHANGE,
    readyweapon = WP_PISTOL,
    cards = { [0] = false, false, false, false, false, false },
    cheats = cheats,
    attackdown = false,
    usedown = false,
    damagecount = 0,
    bonuscount = 0,
    attacker = nil,
    extralight = 0,
    fixedcolormap = 0,
    refire = 0,
    killcount = 0,
    itemcount = 0,
    secretcount = 0,
    psprites = pspr.novos_psprites(),  -- C3: a arma e o clarao (pspr.lua)
    powers = { [0] = 0, 0, 0, 0, 0, 0 },
    message = "",
    message_tics = 0,
  }
  mo.player = player
  mo.lastlook = rng.p_random() % 4
  world.mobjs[#world.mobjs + 1] = mo
  collision.set_thing_position(world, mo)
  return player
end

function M.thrust(mo, angle, move)
  mo.momx = mo.momx + fixed_mul(move, tabela:fine_cos(angle))
  mo.momy = mo.momy + fixed_mul(move, tabela:fine_sin(angle))
end

local function calc_height(player, leveltime)
  local mo = player.mo
  player.bob = math.floor((fixed_mul(mo.momx, mo.momx) + fixed_mul(mo.momy, mo.momy)) / 4)
  if player.bob > MAXBOB then
    player.bob = MAXBOB
  end
  local onground = mo.z <= mo.floorz
  if not onground then
    player.viewz = mo.z + player.viewheight
    if player.viewz > mo.ceilingz - 4 * FRACUNIT then
      player.viewz = mo.ceilingz - 4 * FRACUNIT
    end
    return
  end
  local angle = band(math.floor(FINEANGLES / 20) * leveltime, FINEMASK)
  local bob = fixed_mul(math.floor(player.bob / 2), tabela:get_finesine(angle))
  if player.playerstate == PST_LIVE then
    player.viewheight = player.viewheight + player.deltaviewheight
    if player.viewheight > VIEWHEIGHT then
      player.viewheight = VIEWHEIGHT
      player.deltaviewheight = 0
    end
    if player.viewheight < math.floor(VIEWHEIGHT / 2) then
      player.viewheight = math.floor(VIEWHEIGHT / 2)
      if player.deltaviewheight <= 0 then
        player.deltaviewheight = 1
      end
    end
    if player.deltaviewheight ~= 0 then
      player.deltaviewheight = player.deltaviewheight + math.floor(FRACUNIT / 4)
    end
  end
  player.viewz = mo.z + player.viewheight + bob
  if player.viewz > mo.ceilingz - 4 * FRACUNIT then
    player.viewz = mo.ceilingz - 4 * FRACUNIT
  end
end

function M.xy_movement(world, mo, game)
  if mo.momx == 0 and mo.momy == 0 then
    if has(mo.flags, MF_SKULLFLY) then
      mo.flags = band(mo.flags, bnot(MF_SKULLFLY))
      mo.momx, mo.momy, mo.momz = 0, 0, 0
    end
    return
  end
  if mo.momx > MAXMOVE then
    mo.momx = MAXMOVE
  elseif mo.momx < -MAXMOVE then
    mo.momx = -MAXMOVE
  end
  if mo.momy > MAXMOVE then
    mo.momy = MAXMOVE
  elseif mo.momy < -MAXMOVE then
    mo.momy = -MAXMOVE
  end
  local xmove, ymove = mo.momx, mo.momy
  local half = math.floor(MAXMOVE / 2)
  while xmove ~= 0 or ymove ~= 0 do
    local ptryx, ptryy
    if xmove > half or ymove > half then
      ptryx = mo.x + trunc2(xmove)
      ptryy = mo.y + trunc2(ymove)
      xmove = trunc2(xmove)
      ymove = trunc2(ymove)
    else
      ptryx = mo.x + xmove
      ptryy = mo.y + ymove
      xmove, ymove = 0, 0
    end
    if has(mo.flags, MF_NOCLIP) then
      collision.unset_thing_position(world, mo)
      mo.x, mo.y = ptryx, ptryy
      collision.set_thing_position(world, mo)
    elseif collision.try_move(world, mo, ptryx, ptryy, game) then
    elseif mo.player then
      collision.slide_move(world, mo, mo.momx, mo.momy, game)
    else
      mo.momx, mo.momy = 0, 0
    end
  end
  local player = mo.player
  if player and has(player.cheats, CF_NOMOMENTUM) then
    mo.momx, mo.momy = 0, 0
    return
  end
  if has(mo.flags, MF_MISSILE + MF_SKULLFLY) then
    return
  end
  if mo.z > mo.floorz then
    return
  end
  if has(mo.flags, MF_CORPSE) then
    local lim = math.floor(FRACUNIT / 4)
    if mo.momx > lim or mo.momx < -lim or mo.momy > lim or mo.momy < -lim then
      local sec = collision.point_in_subsector(world, mo.x, mo.y).sector
      if mo.floorz ~= sec.floorheight then
        return
      end
    end
  end
  local cmd = player and player.cmd
  local idle = player == nil or (cmd.forwardmove == 0 and cmd.sidemove == 0)
  if mo.momx > -STOPSPEED and mo.momx < STOPSPEED and mo.momy > -STOPSPEED and mo.momy < STOPSPEED and idle then
    mo.momx, mo.momy = 0, 0
  else
    mo.momx = fixed_mul(mo.momx, FRICTION)
    mo.momy = fixed_mul(mo.momy, FRICTION)
  end
end

function M.z_movement(mo, world, game)
  local player = mo.player
  if player and mo.z < mo.floorz then
    player.viewheight = player.viewheight - (mo.floorz - mo.z)
    player.deltaviewheight = shar(VIEWHEIGHT - player.viewheight, 3)
  end
  mo.z = mo.z + mo.momz
  if mo.z <= mo.floorz then
    if mo.momz < 0 then
      if player and mo.momz < -GRAVITY * 8 then
        player.deltaviewheight = shar(mo.momz, 3)
        if game and game.start_sound then
          game.start_sound("oof")
        end
      end
      mo.momz = 0
    end
    mo.z = mo.floorz
    if has(mo.flags, MF_SKULLFLY) and not has(mo.flags, MF_MISSILE) then
      mo.momz = -mo.momz
    end
  elseif not has(mo.flags, MF_NOGRAVITY) then
    if mo.momz == 0 then
      mo.momz = -GRAVITY * 2
    else
      mo.momz = mo.momz - GRAVITY
    end
  end
  if mo.z + mo.height > mo.ceilingz then
    if mo.momz > 0 then
      mo.momz = 0
    end
    mo.z = mo.ceilingz - mo.height
    if has(mo.flags, MF_SKULLFLY) then
      mo.momz = -mo.momz
    end
  end
end

local function special_sector(world, player, game, leveltime)
  local mo = player.mo
  if mo == nil then
    return
  end
  local sector = collision.point_in_subsector(world, mo.x, mo.y).sector
  if mo.z ~= sector.floorheight or sector.special == 0 then
    return
  end
  local spec = sector.special
  if spec == 9 then
    player.secretcount = player.secretcount + 1
    sector.special = 0
    return
  end
  if spec == 5 or spec == 7 or spec == 4 or spec == 16 or spec == 11 then
    if (player.powers[PW_IRONFEET] or 0) ~= 0 then
      return
    end
    if band(leveltime, 31) ~= 0 then
      return
    end
    if game and game.damage_mobj then
      local dmg = 0
      if spec == 5 then
        dmg = 10
      elseif spec == 7 then
        dmg = 5
      else
        dmg = 20
      end
      game.damage_mobj(mo, nil, dmg)
    end
  end
end

-- C3: a arma (o tiro, as fases e weapon_think) saiu daqui: os psprites
-- seguem info.STATES, com as acoes do p_pspr.c, em pspr.lua.

local function death_think(world, player, game, leveltime)
  local mo = player.mo
  local cmd = player.cmd
  if player.viewheight > 6 * FRACUNIT then
    player.viewheight = player.viewheight - FRACUNIT
  end
  if player.viewheight < 6 * FRACUNIT then
    player.viewheight = 6 * FRACUNIT
  end
  player.deltaviewheight = 0
  M.xy_movement(world, mo, game)
  M.z_movement(mo, world, game)
  calc_height(player, leveltime)
  if player.attacker and player.attacker ~= mo then
    local angle = collision.angle_to(mo.x, mo.y, player.attacker.x, player.attacker.y)
    local delta = as_u32(angle - mo.angle)
    local ang5 = math.floor(ANG90 / 18)
    if delta < as_u32(ang5) or delta > as_u32(-ang5) then
      mo.angle = angle
      if player.damagecount ~= 0 then
        player.damagecount = player.damagecount - 1
      end
    elseif delta < as_u32(ANG180) then
      mo.angle = as_u32(mo.angle + ang5)
    else
      mo.angle = as_u32(mo.angle - ang5)
    end
  elseif player.damagecount ~= 0 then
    player.damagecount = player.damagecount - 1
  end
  pspr.mover_psprites(player, game)  -- C3: P_MovePsprites
  if band(cmd.buttons, BT_USE) ~= 0 then
    player.playerstate = PST_REBORN
  end
end

-- Troca de arma pelo teclado: so registra o pedido (a arma troca).
-- C3: como o P_PlayerThink do Doom: a tecla 1 da a motosserra, se o jogador
-- a tiver (com a motosserra na mao, so volta ao punho com o berserk); no
-- Doom 2, a tecla 3 da a espingarda de cano duplo; no shareware, nada de
-- plasma nem BFG.
function M.escolher_arma(player, game)
  local cmd = player.cmd
  if band(cmd.buttons, BT_CHANGE) ~= 0 then
    local neww = math.floor(band(cmd.buttons, BT_WEAPONMASK) / (2 ^ BT_WEAPONSHIFT))
    local commercial, shareware = pspr.modo(game)
    if neww == WP_FIST and player.weaponowned[WP_CHAINSAW]
        and not (player.readyweapon == WP_CHAINSAW and (player.powers[PW_STRENGTH] or 0) ~= 0) then
      neww = WP_CHAINSAW
    end
    if commercial and neww == WP_SHOTGUN and player.weaponowned[WP_SUPERSHOTGUN]
        and player.readyweapon ~= WP_SUPERSHOTGUN then
      neww = WP_SUPERSHOTGUN
    end
    if neww >= 0 and neww <= WP_SUPERSHOTGUN and player.weaponowned[neww] and neww ~= player.readyweapon then
      if (neww ~= WP_PLASMA and neww ~= WP_BFG) or not shareware then
        player.pendingweapon = neww
      end
    end
  end
end

-- C3: a motosserra que acertou puxa o jogador para a frente no tic
-- seguinte (MF_JUSTATTACKED, no comeco do P_PlayerThink)
local function arrancada(player)
  local mo = player.mo
  if band(mo.flags, pspr.MF_JUSTATTACKED) ~= 0 then
    player.cmd.angleturn = 0
    player.cmd.forwardmove = 100       -- 0xc800 / 512
    player.cmd.sidemove = 0
    mo.flags = band(mo.flags, bnot(pspr.MF_JUSTATTACKED))
  end
end

function M.think(world, player, game, leveltime)
  local mo = player.mo
  local cmd = player.cmd
  arrancada(player)
  if player.playerstate == PST_DEAD then
    death_think(world, player, game, leveltime)
    return
  end
  mo.angle = as_u32(mo.angle + cmd.angleturn * 65536)
  local onground = mo.z <= mo.floorz
  if cmd.forwardmove ~= 0 and onground then
    M.thrust(mo, mo.angle, cmd.forwardmove * 2048)
  end
  if cmd.sidemove ~= 0 and onground then
    M.thrust(mo, as_u32(mo.angle - ANG90), cmd.sidemove * 2048)
  end
  M.xy_movement(world, mo, game)
  M.z_movement(mo, world, game)
  calc_height(player, leveltime)
  special_sector(world, player, game, leveltime)
  if band(cmd.buttons, BT_USE) ~= 0 then
    if not player.usedown then
      collision.use_lines(world, player, game)
      player.usedown = true
    end
  else
    player.usedown = false
  end
  M.escolher_arma(player, game)
  pspr.mover_psprites(player, game)  -- C3: P_MovePsprites
  if (player.powers[PW_STRENGTH] or 0) ~= 0 then
    player.powers[PW_STRENGTH] = player.powers[PW_STRENGTH] + 1
  end
  if (player.powers[PW_INVULNERABILITY] or 0) ~= 0 then
    player.powers[PW_INVULNERABILITY] = player.powers[PW_INVULNERABILITY] - 1
  end
  if (player.powers[PW_INVISIBILITY] or 0) ~= 0 then
    player.powers[PW_INVISIBILITY] = player.powers[PW_INVISIBILITY] - 1
    if player.powers[PW_INVISIBILITY] == 0 then
      mo.flags = band(mo.flags, bnot(MF_SHADOW))
    end
  end
  if (player.powers[PW_INFRARED] or 0) ~= 0 then
    player.powers[PW_INFRARED] = player.powers[PW_INFRARED] - 1
  end
  if (player.powers[PW_IRONFEET] or 0) ~= 0 then
    player.powers[PW_IRONFEET] = player.powers[PW_IRONFEET] - 1
  end
  local inv = player.powers[PW_INVULNERABILITY] or 0
  local ir = player.powers[PW_INFRARED] or 0
  if inv ~= 0 then
    if inv > 4 * 32 or band(inv, 8) ~= 0 then
      player.fixedcolormap = INVERSECOLORMAP
    else
      player.fixedcolormap = 0
    end
  elseif ir ~= 0 then
    if ir > 4 * 32 or band(ir, 8) ~= 0 then
      player.fixedcolormap = 1
    else
      player.fixedcolormap = 0
    end
  else
    player.fixedcolormap = 0
  end
  if player.damagecount ~= 0 then
    player.damagecount = player.damagecount - 1
  end
  if player.bonuscount ~= 0 then
    player.bonuscount = player.bonuscount - 1
  end
  if player.message_tics ~= 0 then
    player.message_tics = player.message_tics - 1
    if player.message_tics <= 0 then
      player.message = ""
    end
  end
end

function M.tick_fx(world)
  local src = world.mobjs or {}
  local keep = {}
  for i = 1, #src do
    local mo = src[i]
    if mo.fx then
      mo.tics = (mo.tics or 1) - 1
      if mo.tics > 0 then
        keep[#keep + 1] = mo
      end
    else
      keep[#keep + 1] = mo
    end
  end
  world.mobjs = keep
end

function M.set_message(player, text)
  if player == nil then
    return
  end
  player.message = text or ""
  player.message_tics = 4 * 35
end

function M.give_power(player, power)
  if player == nil then
    return false
  end
  if power == PW_INVULNERABILITY then
    player.powers[power] = 30 * 35
    return true
  end
  if power == PW_INVISIBILITY then
    player.powers[power] = 60 * 35
    if player.mo then
      player.mo.flags = compat.bor(player.mo.flags, MF_SHADOW)
    end
    return true
  end
  if power == PW_INFRARED then
    player.powers[power] = 120 * 35
    return true
  end
  if power == PW_IRONFEET then
    player.powers[power] = 60 * 35
    return true
  end
  if power == PW_STRENGTH then
    if player.health < 100 then
      player.health = math.min(100, player.health + 100)
      if player.mo then
        player.mo.health = player.health
      end
    end
    player.powers[power] = 1
    return true
  end
  if (player.powers[power] or 0) ~= 0 then
    return false
  end
  player.powers[power] = 1
  return true
end

function M.build_ticcmd(held, turnheld, player, mousex, mousey, sensitivity, mouse_fire)
  local cmd = empty_cmd()
  local speed = 0
  if held.shift then
    speed = 1
  end
  local strafe = held.alt and true or false
  local turning = held.right or held.left
  local held_count = 0
  if turning then
    held_count = turnheld + 1
  end
  local tspeed = speed
  if held_count < 6 then
    tspeed = 2
  end
  if strafe then
    if held.right then
      cmd.sidemove = cmd.sidemove + SIDEMOVE[speed]
    end
    if held.left then
      cmd.sidemove = cmd.sidemove - SIDEMOVE[speed]
    end
  else
    if held.right then
      cmd.angleturn = cmd.angleturn - ANGLETURN[tspeed]
    end
    if held.left then
      cmd.angleturn = cmd.angleturn + ANGLETURN[tspeed]
    end
  end
  if held.up then
    cmd.forwardmove = cmd.forwardmove + FORWARDMOVE[speed]
  end
  if held.down then
    cmd.forwardmove = cmd.forwardmove - FORWARDMOVE[speed]
  end
  if held.comma then
    cmd.sidemove = cmd.sidemove - SIDEMOVE[speed]
  end
  if held.period then
    cmd.sidemove = cmd.sidemove + SIDEMOVE[speed]
  end
  if held.ctrl then
    cmd.buttons = compat.bor(cmd.buttons, BT_ATTACK)
  end
  if held.space or held.e then
    cmd.buttons = compat.bor(cmd.buttons, BT_USE)
  end
  local picked = nil
  if held["1"] then
    picked = WP_FIST                     -- C3: a motosserra e do P_PlayerThink
  elseif held["2"] then
    picked = WP_PISTOL
  elseif held["3"] then
    picked = WP_SHOTGUN
  elseif held["4"] then
    picked = WP_CHAINGUN
  elseif held["5"] then
    picked = WP_MISSILE
  elseif held["6"] then
    picked = WP_PLASMA
  elseif held["7"] then
    picked = WP_BFG
  end
  if picked ~= nil then
    cmd.buttons = compat.bor(cmd.buttons, BT_CHANGE + picked * (2 ^ BT_WEAPONSHIFT))
  end
  if mousex ~= nil or mousey ~= nil or mouse_fire then
    local sens = ((sensitivity or 5) + 5) / 10
    local function trunc(n)
      if n >= 0 then
        return math.floor(n)
      end
      return math.ceil(n)
    end
    local function clamp(n)
      if n > 127 then
        return 127
      end
      if n < -127 then
        return -127
      end
      return n
    end
    local mx = trunc((mousex or 0) * sens)
    local my = trunc((mousey or 0) * sens)
    cmd.forwardmove = clamp(cmd.forwardmove + my)
    if strafe then
      cmd.sidemove = clamp(cmd.sidemove + mx * 2)
    else
      cmd.angleturn = cmd.angleturn - mx * 8
    end
    if mouse_fire then
      cmd.buttons = compat.bor(cmd.buttons, BT_ATTACK)
    end
  end
  return cmd, held_count
end

local KEY_CARD = {
  [5] = 0,
  [6] = 1,
  [13] = 2,
  [40] = 3,
  [39] = 4,
  [38] = 5,
}
-- P_GiveAmmo
function M.give_ammo(player, ammo_type, num, skill)
  if ammo_type == nil then
    return false
  end

  local current = player.ammo[ammo_type]
  local maximum = player.maxammo[ammo_type]
  local clip = player.clipammo[ammo_type]

  if current == nil or maximum == nil or clip == nil then
    return false
  end

  if current >= maximum then
    return false
  end

  local amount

  if num ~= nil and num ~= 0 then
    amount = num * clip
  else
    amount = math.floor(clip / 2)
  end

  -- Baby e Nightmare.
  if skill == 0 or skill == 4 then
    amount = amount * 2
  end

  local oldammo = current

  player.ammo[ammo_type] = math.min(
    current + amount,
    maximum
  )

  -- Já possuía munição: não troca de arma.
  if oldammo > 0 then
    return true
  end

  -- Seleção automática de arma.
  if ammo_type == AM_CLIP then
    if player.readyweapon == WP_FIST then
      if player.weaponowned[WP_CHAINGUN] then
        player.pendingweapon = WP_CHAINGUN
      else
        player.pendingweapon = WP_PISTOL
      end
    end

  elseif ammo_type == AM_SHELL then
    if player.readyweapon == WP_FIST
      or player.readyweapon == WP_PISTOL then

      if player.weaponowned[WP_SHOTGUN] then
        player.pendingweapon = WP_SHOTGUN
      end
    end

  elseif ammo_type == AM_CELL then
    if player.readyweapon == WP_FIST
      or player.readyweapon == WP_PISTOL then

      if player.weaponowned[WP_PLASMA] then
        player.pendingweapon = WP_PLASMA
      end
    end

  elseif ammo_type == AM_MISL then
    if player.readyweapon == WP_FIST then
      if player.weaponowned[WP_MISSILE] then
        player.pendingweapon = WP_MISSILE
      end
    end
  end

  return true
end


-- P_GiveWeapon
function M.give_weapon(player, weapon, dropped, skill)
  local ammo_type = WEAPON_AMMO[weapon]

  local gaveammo = false
  local gaveweapon = false

  if ammo_type ~= nil then
    if dropped then
      gaveammo = M.give_ammo(player, ammo_type, 1, skill)
    else
      gaveammo = M.give_ammo(player, ammo_type, 2, skill)
    end
  end

  if not player.weaponowned[weapon] then
    gaveweapon = true
    player.weaponowned[weapon] = true
    player.pendingweapon = weapon
  end

  return gaveweapon or gaveammo
end


-- P_GiveBody
function M.give_body(player, amount)
  if player.health >= MAXHEALTH then
    return false
  end

  player.health = math.min(
    player.health + amount,
    MAXHEALTH
  )

  player.mo.health = player.health

  return true
end


-- P_GiveArmor
function M.give_armor(player, armor_type)
  local hits = armor_type * 100

  if player.armorpoints >= hits then
    return false
  end

  player.armortype = armor_type
  player.armorpoints = hits

  return true
end

-- P_GiveCard
function M.give_card(player, card)
  if not player.cards[card] then
    player.bonuscount = BONUSADD
    player.cards[card] = true
  end
end


-- P_TouchSpecialThing

function M.touch_special(special, toucher, game)

  if not special or not toucher then
    return false
  end

  local player = toucher.player

  if not player or special.alive == false then
    return false
  end

  -- Verifica alcance vertical.
  local delta = special.z - toucher.z

  if delta > toucher.height
    or delta < -8 * FRACUNIT then
    return false
  end

  -- Jogador morto não coleta.
  if toucher.health <= 0 then
    return false
  end

  local id = special.doomednum
  local skill = game and game.skill or 2

  local sound = "itemup"
  local message = nil
  local collected = false

  ------------------------------------------------
  -- ARMADURA
  ------------------------------------------------

  if id == 2018 then
    collected = M.give_armor(player, 1)
    message = "Picked up the armor."

  elseif id == 2019 then
    collected = M.give_armor(player, 2)
    message = "Picked up the MegaArmor."

  ------------------------------------------------
  -- BONUS
  ------------------------------------------------

  elseif id == 2014 then
    player.health = math.min(player.health + 1, MAXBONUS)
    player.mo.health = player.health

    collected = true
    message = "Picked up a health bonus."

  elseif id == 2015 then
    player.armorpoints = math.min(
      player.armorpoints + 1,
      MAXBONUS
    )

    if player.armortype == 0 then
      player.armortype = 1
    end

    collected = true
    message = "Picked up an armor bonus."

  elseif id == 2013 then
    player.health = math.min(
      player.health + 100,
      MAXBONUS
    )

    player.mo.health = player.health

    collected = true
    message = "Supercharge!"

    sound = "getpow"

  ------------------------------------------------
  -- CHAVES
  ------------------------------------------------

  elseif KEY_CARD[id] ~= nil then
    local card = KEY_CARD[id]

    if not player.cards[card] then
      M.give_card(player, card)
      message = "Picked up a key."
    end

    -- No single-player, chaves duplicadas
    -- também desaparecem.
    collected = true

  ------------------------------------------------
  -- VIDA
  ------------------------------------------------

  elseif id == 2011 then
    collected = M.give_body(player, 10)
    message = "Picked up a stimpack."

  elseif id == 2012 then
    collected = M.give_body(player, 25)

    if player.health < 25 then
      message = "Picked up a medikit that you REALLY need!"
    else
      message = "Picked up a medikit."
    end

  ------------------------------------------------
  -- POWER UPS
  ------------------------------------------------

  elseif id == 2022 then
    collected = M.give_power(player, PW_INVULNERABILITY)
    message = "Invulnerability!"
    sound = "getpow"

  elseif id == 2023 then
    collected = M.give_power(player, PW_STRENGTH)
    message = "Berserk!"

    if player.readyweapon ~= WP_FIST then
      player.pendingweapon = WP_FIST
    end

    sound = "getpow"

  elseif id == 2024 then
    collected = M.give_power(player, PW_INVISIBILITY)
    message = "Partial Invisibility!"
    sound = "getpow"

  elseif id == 2025 then
    collected = M.give_power(player, PW_IRONFEET)
    message = "Radiation Shielding Suit!"
    sound = "getpow"

  elseif id == 2026 then
    collected = M.give_power(player, PW_ALLMAP)
    message = "Computer Area Map!"
    sound = "getpow"

  elseif id == 2045 then
    collected = M.give_power(player, PW_INFRARED)
    message = "Light Amplification Visor!"
    sound = "getpow"

  ------------------------------------------------
  -- MUNIÇÃO
  ------------------------------------------------

  elseif id == 2007 then
    local dropped = has(special.flags, MF_DROPPED)

    collected = M.give_ammo(
      player, AM_CLIP,
      dropped and 0 or 1,
      skill
    )

    message = "Picked up a clip."

  elseif id == 2048 then
    collected = M.give_ammo(player, AM_CLIP, 5, skill)
    message = "Picked up a box of bullets."

  elseif id == 2008 then
    collected = M.give_ammo(player, AM_SHELL, 1, skill)
    message = "Picked up 4 shotgun shells."

  elseif id == 2049 then
    collected = M.give_ammo(player, AM_SHELL, 5, skill)
    message = "Picked up a box of shells."

  elseif id == 2010 then
    collected = M.give_ammo(player, AM_MISL, 1, skill)
    message = "Picked up a rocket."

  elseif id == 2046 then
    collected = M.give_ammo(player, AM_MISL, 5, skill)
    message = "Picked up a box of rockets."

  elseif id == 2047 then
    collected = M.give_ammo(player, AM_CELL, 1, skill)
    message = "Picked up an energy cell."

  elseif id == 17 then
    collected = M.give_ammo(player, AM_CELL, 5, skill)
    message = "Picked up an energy cell pack."

  ------------------------------------------------
  -- MOCHILA
  ------------------------------------------------

  elseif id == 8 then

    if not player.backpack then
      for i = 0, 3 do
        player.maxammo[i] = player.maxammo[i] * 2
      end

      player.backpack = true
    end

    for i = 0, 3 do
      M.give_ammo(player, i, 1, skill)
    end

    collected = true
    message = "Picked up a backpack."

  ------------------------------------------------
  -- ARMAS
  ------------------------------------------------

  elseif id == 2001 then
    collected = M.give_weapon(player, WP_SHOTGUN, false, skill)
    message = "You got the shotgun!"
    sound = "wpnup"

  elseif id == 2002 then
    collected = M.give_weapon(
      player, WP_CHAINGUN,
      has(special.flags, MF_DROPPED),
      skill
    )

    message = "You got the chaingun!"
    sound = "wpnup"

  elseif id == 2003 then
    collected = M.give_weapon(player, WP_MISSILE, false, skill)
    message = "You got the rocket launcher!"
    sound = "wpnup"

  elseif id == 2004 then
    collected = M.give_weapon(player, WP_PLASMA, false, skill)
    message = "You got the plasma rifle!"
    sound = "wpnup"

  elseif id == 2005 then
    collected = M.give_weapon(player, WP_CHAINSAW, false, skill)
    message = "A chainsaw!"
    sound = "wpnup"

  elseif id == 2006 then
    collected = M.give_weapon(player, WP_BFG, false, skill)
    message = "You got the BFG9000!"
    sound = "wpnup"

  else
    return false
  end

  ------------------------------------------------
  -- FINALIZAÇÃO
  ------------------------------------------------

  if not collected then
    return false
  end

  if has(special.flags, MF_COUNTITEM) then
    player.itemcount = player.itemcount + 1
  end

  special.alive = false
  special.flags = 0
  special.sprite = ""

  player.bonuscount = player.bonuscount + BONUSADD

  if message then
    M.set_message(player, message)
  end

  if game and game.start_sound then
    game.start_sound(sound)
  end

  return true
end


-- Mantém compatibilidade com chamadas antigas.
function M.take_key(special, toucher, game)
  return M.touch_special(special, toucher, game)
end


-- 

M.WEAPONBOTTOM = WEAPONBOTTOM
M.PST_DEAD = PST_DEAD
M.PST_REBORN = PST_REBORN
M.WP_FIST = WP_FIST
M.WP_CHAINSAW = WP_CHAINSAW
M.empty_cmd = empty_cmd

return M
