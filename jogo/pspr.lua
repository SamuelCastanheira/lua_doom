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
-- Os psprites da arma, como o p_pspr.c do Doom (C3, o antigo passo 4b do
-- docs/PLANO_ATMOS.md). Igual nas branches atmos e lua.
--
-- O jogador tem dois psprites: a arma (psprites[0], ps_weapon) e o clarao
-- (psprites[1], ps_flash). Cada um esta num estado de info.STATES (0 =
-- S_NULL, apagado), com os tics que faltam e a posicao na tela (sx, sy).
-- Entrar num estado chama a acao dele (A_WeaponReady, A_FirePistol,
-- A_ReFire...), e as acoes trocam estados: o tiro comeca de dentro do
-- A_WeaponReady, o A_ReFire volta ao comeco do tiro, o A_Lower troca de arma.
--
-- Antes (ate a tag c2) a arma usava tabelas proprias (WEAPON_PATCH,
-- WEAPON_ATK, WEAPON_READY em player.lua) e quatro fases por nome
-- (psprite_state "up", "ready", "atk", "down"); o clarao era um contador.
--
-- Quem chama:
--   branch lua: M.mover_psprites, no ponto do P_MovePsprites (player.think);
--   branch atmos: a task Arma (arma.atm), que segue os dois psprites com
--   M.contar_tic e M.set_psprite.
-- De fora, no meio do tic: M.soltar_arma na morte (P_KillMobj ->
-- P_DropWeapon) e M.preparar_psprites quando o jogador nasce
-- (P_SetupPsprites).

local compat = require("compat")
-- finesine, tantoangle e slope_div: as tabelas do Doom, em C (tables_c)
local tabela = require("tables_c").padrao
local info = require("info")
local rng = require("random")

local band, bor = compat.band, compat.bor
local as_u32 = compat.as_u32
local fixed_mul = compat.fixed_mul

local M = {}


local FRACUNIT = 65536
local FINEANGLES = 8192
local FINEMASK = FINEANGLES - 1
local FINESINE_LEN = 10240
local ANG90 = 1073741824
local ANG180 = 2147483648

local WEAPONTOP = 32 * FRACUNIT
local WEAPONBOTTOM = 128 * FRACUNIT
local LOWERSPEED = 6 * FRACUNIT
local RAISESPEED = 6 * FRACUNIT
local MELEERANGE = 64 * FRACUNIT
local MISSILERANGE = 32 * 64 * FRACUNIT
local BFGCELLS = 40

local PS_WEAPON = 0
local PS_FLASH = 1

local BT_ATTACK = 1
local PST_DEAD = 1
local PW_STRENGTH = 1
local MF_JUSTATTACKED = 128

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

-- weaponinfo[] do d_items.c: municao e os estados de subir, baixar, pronta,
-- atirar e clarao de cada arma
local WEAPONINFO = {
  [WP_FIST] = { ammo = nil, up = info.S_PUNCHUP, down = info.S_PUNCHDOWN,
    ready = info.S_PUNCH, atk = info.S_PUNCH1, flash = info.S_NULL },
  [WP_PISTOL] = { ammo = AM_CLIP, up = info.S_PISTOLUP, down = info.S_PISTOLDOWN,
    ready = info.S_PISTOL, atk = info.S_PISTOL1, flash = info.S_PISTOLFLASH },
  [WP_SHOTGUN] = { ammo = AM_SHELL, up = info.S_SGUNUP, down = info.S_SGUNDOWN,
    ready = info.S_SGUN, atk = info.S_SGUN1, flash = info.S_SGUNFLASH1 },
  [WP_CHAINGUN] = { ammo = AM_CLIP, up = info.S_CHAINUP, down = info.S_CHAINDOWN,
    ready = info.S_CHAIN, atk = info.S_CHAIN1, flash = info.S_CHAINFLASH1 },
  [WP_MISSILE] = { ammo = AM_MISL, up = info.S_MISSILEUP, down = info.S_MISSILEDOWN,
    ready = info.S_MISSILE, atk = info.S_MISSILE1, flash = info.S_MISSILEFLASH1 },
  [WP_PLASMA] = { ammo = AM_CELL, up = info.S_PLASMAUP, down = info.S_PLASMADOWN,
    ready = info.S_PLASMA, atk = info.S_PLASMA1, flash = info.S_PLASMAFLASH1 },
  [WP_BFG] = { ammo = AM_CELL, up = info.S_BFGUP, down = info.S_BFGDOWN,
    ready = info.S_BFG, atk = info.S_BFG1, flash = info.S_BFGFLASH1 },
  [WP_CHAINSAW] = { ammo = nil, up = info.S_SAWUP, down = info.S_SAWDOWN,
    ready = info.S_SAW, atk = info.S_SAW1, flash = info.S_NULL },
  [WP_SUPERSHOTGUN] = { ammo = AM_SHELL, up = info.S_DSGUNUP, down = info.S_DSGUNDOWN,
    ready = info.S_DSGUN, atk = info.S_DSGUN1, flash = info.S_DSGUNFLASH1 },
}
M.WEAPONINFO = WEAPONINFO

-- Os campos de uma linha de info.STATES: [0] sprite, [1] quadro (com
-- FF_FULLBRIGHT), [2] tics, [3] acao, [4] proximo estado
local function estado(st)
  return info.STATES[st]
end

-- O gamemode do Doom: commercial (Doom 2, MAP01) ou shareware (sem E2M1)
local function modo(game)
  local w = game and game.wad
  if not w then
    return false, false
  end
  local wad = require("wad")
  local commercial = wad.check_num_for_name(w, "MAP01") >= 0
  local shareware = (not commercial) and wad.check_num_for_name(w, "E2M1") < 0
  return commercial, shareware
end

local function som(game, name)
  if game and game.start_sound then
    game.start_sound(name)
  end
end

-- Psprites novos (o jogador recem-criado), apagados: P_SetupPsprites os
-- acende quando o jogador entra no nivel.
function M.novos_psprites()
  return {
    [PS_WEAPON] = { state = 0, tics = 0, sx = 0, sy = 0 },
    [PS_FLASH] = { state = 0, tics = 0, sx = 0, sy = 0 },
  }
end

local ACOES -- as acoes dos estados da arma, abaixo

-- P_SetPsprite: entra no estado stnum; segue pelos estados de 0 tics,
-- chamando a acao de cada um. Uma acao pode trocar o estado (de novo
-- P_SetPsprite) ou apagar o psprite (S_NULL).
function M.set_psprite(player, position, stnum, game)
  local psp = player.psprites[position]
  repeat
    if stnum == 0 then
      psp.state = 0                      -- o psprite se apagou
      break
    end
    local s = estado(stnum)
    psp.state = stnum
    psp.tics = s[2]                      -- pode ser 0
    local acao = ACOES[info.ACTIONS[s[3]]]
    if acao then
      acao(player, psp, game)
      if psp.state == 0 then
        break
      end
    end
    stnum = estado(psp.state)[4]
  until psp.tics ~= 0
end

-- P_BringUpWeapon: comeca a subir a arma pedida (ou a atual), de baixo
local function bring_up_weapon(player, game)
  if player.pendingweapon == WP_NOCHANGE then
    player.pendingweapon = player.readyweapon
  end
  if player.pendingweapon == WP_CHAINSAW then
    som(game, "sawup")
  end
  local newstate = WEAPONINFO[player.pendingweapon].up
  player.pendingweapon = WP_NOCHANGE
  player.psprites[PS_WEAPON].sy = WEAPONBOTTOM
  M.set_psprite(player, PS_WEAPON, newstate, game)
end

-- P_CheckAmmo: ha municao para um tiro? Sem municao, escolhe outra arma
-- (na ordem de preferencia do Doom) e comeca a baixar a atual.
local function check_ammo(player, game)
  local ammo = WEAPONINFO[player.readyweapon].ammo
  local count = 1
  if player.readyweapon == WP_BFG then
    count = BFGCELLS
  elseif player.readyweapon == WP_SUPERSHOTGUN then
    count = 2
  end
  if ammo == nil or player.ammo[ammo] >= count then
    return true
  end
  local own, am = player.weaponowned, player.ammo
  local commercial, shareware = modo(game)
  if own[WP_PLASMA] and am[AM_CELL] > 0 and not shareware then
    player.pendingweapon = WP_PLASMA
  elseif own[WP_SUPERSHOTGUN] and am[AM_SHELL] > 2 and commercial then
    player.pendingweapon = WP_SUPERSHOTGUN
  elseif own[WP_CHAINGUN] and am[AM_CLIP] > 0 then
    player.pendingweapon = WP_CHAINGUN
  elseif own[WP_SHOTGUN] and am[AM_SHELL] > 0 then
    player.pendingweapon = WP_SHOTGUN
  elseif am[AM_CLIP] > 0 then
    player.pendingweapon = WP_PISTOL
  elseif own[WP_CHAINSAW] then
    player.pendingweapon = WP_CHAINSAW
  elseif own[WP_MISSILE] and am[AM_MISL] > 0 then
    player.pendingweapon = WP_MISSILE
  elseif own[WP_BFG] and am[AM_CELL] > 40 and not shareware then
    player.pendingweapon = WP_BFG
  else
    player.pendingweapon = WP_FIST
  end
  M.set_psprite(player, PS_WEAPON, WEAPONINFO[player.readyweapon].down, game)
  return false
end

local function noise_alert(player, game)
  if player.mo and game and game.world then
    require("enemy").noise_alert(game.world, player.mo, game)
  end
end

-- C8: o estado do corpo do jogador (o mobj), que o p_pspr.c troca ao
-- atirar (S_PLAY_ATK1, S_PLAY_ATK2) e ao voltar a arma pronta (S_PLAY)
local function corpo(player, st, game)
  if player.mo and player.mo.istate then
    require("thinker").set_mobj_state(player.mo, st, game and game.world, game)
  end
end

-- P_FireWeapon: comeca o tiro (se houver municao)
local function fire_weapon(player, game)
  if not check_ammo(player, game) then
    return
  end
  corpo(player, info.S_PLAY_ATK1, game)  -- C8: o corpo atira
  M.set_psprite(player, PS_WEAPON, WEAPONINFO[player.readyweapon].atk, game)
  noise_alert(player, game)
end

-- P_DropWeapon: o jogador morreu; a arma desce
function M.soltar_arma(player, game)
  M.set_psprite(player, PS_WEAPON, WEAPONINFO[player.readyweapon].down, game)
end

-- P_SetupPsprites: o jogador entrou no nivel; apaga os dois psprites e sobe
-- a arma atual
function M.preparar_psprites(player, game)
  player.psprites[PS_WEAPON].state = 0
  player.psprites[PS_FLASH].state = 0
  player.pendingweapon = player.readyweapon
  bring_up_weapon(player, game)
end

-- P_BulletSlope: a inclinacao do tiro (o alvo na frente, ou a 1/16 de
-- volta para cada lado)
local function bullet_slope(player, game)
  return require("collision").bullet_slope(game.world, player.mo)
end

-- P_GunShot
local function gun_shot(player, game, accurate, slope)
  local mo = player.mo
  local damage = 5 * ((rng.p_random() % 3) + 1)
  local angle = mo.angle
  if not accurate then
    angle = as_u32(angle + (rng.p_random() - rng.p_random()) * 262144)
  end
  require("collision").line_attack(game.world, mo, damage, game, MISSILERANGE, angle, slope)
end

local function flash(player, game, stnum)
  M.set_psprite(player, PS_FLASH, stnum, game)
end

-- Vira o jogador para o alvo do ataque de perto (R_PointToAngle2)
local function angulo_para(mo, alvo)
  return require("collision").angle_to(mo.x, mo.y, alvo.x, alvo.y)
end

ACOES = {
  -- A_WeaponReady: troca pedida (ou morto): baixa; gatilho: atira (o
  -- lanca-foguetes e o BFG pedem soltar antes); senao, balanca a arma
  WeaponReady = function(player, psp, game)
    -- C8: o corpo sai do tiro
    local mo = player.mo
    if mo and (mo.istate == info.S_PLAY_ATK1 or mo.istate == info.S_PLAY_ATK2) then
      corpo(player, info.S_PLAY, game)
    end
    if player.readyweapon == WP_CHAINSAW and psp.state == info.S_SAW then
      som(game, "sawidl")
    end
    if player.pendingweapon ~= WP_NOCHANGE or player.health == 0 then
      M.set_psprite(player, PS_WEAPON, WEAPONINFO[player.readyweapon].down, game)
      return
    end
    if band(player.cmd.buttons, BT_ATTACK) ~= 0 then
      if not player.attackdown
          or (player.readyweapon ~= WP_MISSILE and player.readyweapon ~= WP_BFG) then
        player.attackdown = true
        fire_weapon(player, game)
        return
      end
    else
      player.attackdown = false
    end
    local angle = band(128 * ((game and game.leveltime) or 0), FINEMASK)
    psp.sx = FRACUNIT + fixed_mul(player.bob or 0,
      tabela:get_finesine((angle + FINEANGLES // 4) % FINESINE_LEN))
    angle = band(angle, FINEANGLES // 2 - 1)
    psp.sy = WEAPONTOP + fixed_mul(player.bob or 0, tabela:get_finesine(angle))
  end,

  -- A_ReFire: gatilho ainda preso (sem troca pedida): atira de novo
  ReFire = function(player, psp, game)
    if band(player.cmd.buttons, BT_ATTACK) ~= 0
        and player.pendingweapon == WP_NOCHANGE and player.health ~= 0 then
      player.refire = player.refire + 1
      fire_weapon(player, game)
    else
      player.refire = 0
      check_ammo(player, game)
    end
  end,

  CheckReload = function(player, psp, game)
    check_ammo(player, game)
  end,

  -- A_Lower: desce; embaixo, troca de arma (morto, fica embaixo)
  Lower = function(player, psp, game)
    psp.sy = psp.sy + LOWERSPEED
    if psp.sy < WEAPONBOTTOM then
      return
    end
    if player.playerstate == PST_DEAD then
      psp.sy = WEAPONBOTTOM
      return
    end
    if player.health == 0 then
      M.set_psprite(player, PS_WEAPON, 0, game)
      return
    end
    player.readyweapon = player.pendingweapon
    bring_up_weapon(player, game)
  end,

  -- A_Raise: sobe; no topo, fica pronta
  Raise = function(player, psp, game)
    psp.sy = psp.sy - RAISESPEED
    if psp.sy > WEAPONTOP then
      return
    end
    psp.sy = WEAPONTOP
    M.set_psprite(player, PS_WEAPON, WEAPONINFO[player.readyweapon].ready, game)
  end,

  GunFlash = function(player, psp, game)
    flash(player, game, WEAPONINFO[player.readyweapon].flash)
  end,

  Punch = function(player, psp, game)
    local mo = player.mo
    local damage = ((rng.p_random() % 10) + 1) * 2
    if (player.powers[PW_STRENGTH] or 0) ~= 0 then
      damage = damage * 10
    end
    local angle = as_u32(mo.angle + (rng.p_random() - rng.p_random()) * 262144)
    local collision = require("collision")
    local slope, alvo = collision.aim_line(game.world, mo, angle, MELEERANGE)
    collision.line_attack(game.world, mo, damage, game, MELEERANGE, angle, slope)
    if alvo then
      som(game, "punch")
      mo.angle = angulo_para(mo, alvo)
    end
  end,

  Saw = function(player, psp, game)
    local mo = player.mo
    local damage = 2 * ((rng.p_random() % 10) + 1)
    local angle = as_u32(mo.angle + (rng.p_random() - rng.p_random()) * 262144)
    local collision = require("collision")
    -- MELEERANGE + 1: o puff nao pula o clarao
    local slope, alvo = collision.aim_line(game.world, mo, angle, MELEERANGE + 1)
    collision.line_attack(game.world, mo, damage, game, MELEERANGE + 1, angle, slope)
    if not alvo then
      som(game, "sawful")
      return
    end
    som(game, "sawhit")
    angle = angulo_para(mo, alvo)
    local d = as_u32(angle - mo.angle)
    local passo = ANG90 // 20
    if d > ANG180 then
      if d < as_u32(-passo) then
        mo.angle = as_u32(angle + ANG90 // 21)
      else
        mo.angle = as_u32(mo.angle - passo)
      end
    else
      if d > passo then
        mo.angle = as_u32(angle - ANG90 // 21)
      else
        mo.angle = as_u32(mo.angle + passo)
      end
    end
    mo.flags = bor(mo.flags, MF_JUSTATTACKED)
  end,

  FireMissile = function(player, psp, game)
    player.ammo[WEAPONINFO[player.readyweapon].ammo] = player.ammo[WEAPONINFO[player.readyweapon].ammo] - 1
    require("enemy").spawn_player_missile(game.world, player.mo, "rocket")
    som(game, "rlaunc")
  end,

  FireBFG = function(player, psp, game)
    player.ammo[WEAPONINFO[player.readyweapon].ammo] = player.ammo[WEAPONINFO[player.readyweapon].ammo] - BFGCELLS
    require("enemy").spawn_player_missile(game.world, player.mo, "bfg")
  end,

  FirePlasma = function(player, psp, game)
    player.ammo[WEAPONINFO[player.readyweapon].ammo] = player.ammo[WEAPONINFO[player.readyweapon].ammo] - 1
    flash(player, game, WEAPONINFO[player.readyweapon].flash + band(rng.p_random(), 1))
    require("enemy").spawn_player_missile(game.world, player.mo, "plasma")
    som(game, "plasma")
  end,

  FirePistol = function(player, psp, game)
    som(game, "pistol")
    corpo(player, info.S_PLAY_ATK2, game)  -- C8
    player.ammo[WEAPONINFO[player.readyweapon].ammo] = player.ammo[WEAPONINFO[player.readyweapon].ammo] - 1
    flash(player, game, WEAPONINFO[player.readyweapon].flash)
    gun_shot(player, game, player.refire == 0, bullet_slope(player, game))
  end,

  FireShotgun = function(player, psp, game)
    som(game, "shotgn")
    corpo(player, info.S_PLAY_ATK2, game)  -- C8
    player.ammo[WEAPONINFO[player.readyweapon].ammo] = player.ammo[WEAPONINFO[player.readyweapon].ammo] - 1
    flash(player, game, WEAPONINFO[player.readyweapon].flash)
    local slope = bullet_slope(player, game)
    for _ = 1, 7 do
      gun_shot(player, game, false, slope)
    end
  end,

  FireShotgun2 = function(player, psp, game)
    som(game, "dshtgn")
    corpo(player, info.S_PLAY_ATK2, game)  -- C8
    player.ammo[WEAPONINFO[player.readyweapon].ammo] = player.ammo[WEAPONINFO[player.readyweapon].ammo] - 2
    flash(player, game, WEAPONINFO[player.readyweapon].flash)
    local slope = bullet_slope(player, game)
    local mo = player.mo
    local collision = require("collision")
    for _ = 1, 20 do
      local damage = 5 * ((rng.p_random() % 3) + 1)
      local angle = as_u32(mo.angle + (rng.p_random() - rng.p_random()) * 524288)
      local pellet = slope + (rng.p_random() - rng.p_random()) * 32
      collision.line_attack(game.world, mo, damage, game, MISSILERANGE, angle, pellet)
    end
  end,

  OpenShotgun2 = function(player, psp, game)
    som(game, "dbopn")
  end,

  LoadShotgun2 = function(player, psp, game)
    som(game, "dbload")
  end,

  CloseShotgun2 = function(player, psp, game)
    som(game, "dbcls")
    ACOES.ReFire(player, psp, game)
  end,

  -- A_FireCGun: o clarao acompanha o quadro do tiro (S_CHAIN1 ou S_CHAIN2)
  FireCGun = function(player, psp, game)
    som(game, "pistol")
    local ammo = WEAPONINFO[player.readyweapon].ammo
    if player.ammo[ammo] == 0 then
      return
    end
    corpo(player, info.S_PLAY_ATK2, game)  -- C8
    player.ammo[ammo] = player.ammo[ammo] - 1
    flash(player, game, WEAPONINFO[player.readyweapon].flash + psp.state - info.S_CHAIN1)
    gun_shot(player, game, player.refire == 0, bullet_slope(player, game))
  end,

  Light0 = function(player)
    player.extralight = 0
  end,
  Light1 = function(player)
    player.extralight = 1
  end,
  Light2 = function(player)
    player.extralight = 2
  end,

  BFGsound = function(player, psp, game)
    som(game, "bfg")
  end,
}

-- Um tic de um psprite, sem a troca de estado: o clarao vai para a
-- posicao da arma, e os tics descontam (-1 nunca muda). Devolve true se os
-- tics acabaram (a troca, para o estado seguinte, e de quem chamou).
function M.contar_tic(player, position)
  local psp = player.psprites[position]
  if position == PS_FLASH then
    psp.sx = player.psprites[PS_WEAPON].sx
    psp.sy = player.psprites[PS_WEAPON].sy
  end
  if psp.state == 0 or psp.tics == -1 then
    return false
  end
  psp.tics = psp.tics - 1
  return psp.tics == 0
end

-- O estado seguinte ao atual (o ponteiro "proximo" de info.STATES)
function M.proximo(player, position)
  return estado(player.psprites[position].state)[4]
end

-- P_MovePsprites: um tic dos dois psprites, a arma e depois o clarao. Na
-- branch atmos, a task Arma faz o mesmo com contar_tic e set_psprite.
function M.mover_psprites(player, game)
  for position = PS_WEAPON, PS_FLASH do
    local psp = player.psprites[position]
    if psp.state ~= 0 and psp.tics ~= -1 then
      psp.tics = psp.tics - 1
      if psp.tics == 0 then
        M.set_psprite(player, position, M.proximo(player, position), game)
      end
    end
  end
  player.psprites[PS_FLASH].sx = player.psprites[PS_WEAPON].sx
  player.psprites[PS_FLASH].sy = player.psprites[PS_WEAPON].sy
end

-- O patch de um estado (ex.: "PISGA0") e se ele e aceso (FF_FULLBRIGHT),
-- para o renderer
local FF_FULLBRIGHT = 32768
function M.patch(st)
  local s = estado(st)
  local frame = s[1]
  local aceso = frame >= FF_FULLBRIGHT
  return info.SPRNAMES[s[0]] .. string.char(65 + frame % FF_FULLBRIGHT) .. "0", aceso
end

M.modo = modo
M.PS_WEAPON = PS_WEAPON
M.PS_FLASH = PS_FLASH
M.WEAPONTOP = WEAPONTOP
M.WEAPONBOTTOM = WEAPONBOTTOM
M.WP_NOCHANGE = WP_NOCHANGE
M.MF_JUSTATTACKED = MF_JUSTATTACKED

return M
