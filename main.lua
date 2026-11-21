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
-- Laço a 35 Hz. A skill abre a vista e o jogador anda.
local atmos = require("atmos")

io.stdout:setvbuf("no")
io.stderr:setvbuf("no")

local wad = require("wad")
local video = require("video")
local v = require("v_video")
local menu_mod = require("menu")
local world_mod = require("world")
local rdata = require("r_data_c")
local render = require("render")
local sprites = require("sprites")
local collision = require("collision")
local player_mod = require("player")
local pspr = require("pspr")
local specials_mod = require("specials")
local rng = require("random")
local thinker = require("thinker")
local enemy = require("enemy")
local sound_mod = require("sound")
local status_mod = require("status")
local wi_mod = require("wi_stuff")
local wipe_mod = require("wipe")
local am_map = require("am_map")
local finale_mod = require("finale")
local saveg = require("saveg")
local cheats_mod = require("cheats")

local function take_args(argv)
  local out = {
    iwad = nil,
    files = {},
    warp = false,
    episode = 1,
    mapn = 1,
    skill = 2,
    show_fps = false,
    crt = false,
    nomonsters = false,
    fastparm = false,
    respawnparm = false,
    nosound = false,
    nomusic = false,
    nocheats = false,
  }
  local i = 1
  argv = argv or {}
  while argv[i] do
    local a = argv[i]
    if a == "-iwad" and argv[i + 1] then
      out.iwad = argv[i + 1]
      i = i + 2
    elseif a == "-warp" and argv[i + 2] then
      out.warp = true
      out.episode = tonumber(argv[i + 1]) or 1
      out.mapn = tonumber(argv[i + 2]) or 1
      i = i + 3
    elseif a == "-skill" and argv[i + 1] then
      out.skill = tonumber(argv[i + 1]) or 2
      i = i + 2
    elseif a == "-scale" then
      out.scale = tonumber(argv[i + 1]) or 2
      i = i + 1
    elseif a == "-file" then
      i = i + 1
      while argv[i] and argv[i]:sub(1, 1) ~= "-" do
        out.files[#out.files + 1] = argv[i]
        i = i + 1
      end
    elseif a == "-fps" then
      out.show_fps = true
      i = i + 1
    elseif a == "-crt" then
      out.crt = true
      i = i + 1
    elseif a == "-nomonsters" then
      out.nomonsters = true
      i = i + 1
    elseif a == "-fast" then
      out.fastparm = true
      i = i + 1
    elseif a == "-respawn" then
      out.respawnparm = true
      i = i + 1
    elseif a == "-nosound" then
      out.nosound = true
      i = i + 1
    elseif a == "-nomusic" then
      out.nomusic = true
      i = i + 1
    elseif a == "-nocheats" then
      out.nocheats = true
      i = i + 1
    elseif a:lower():sub(-4) == ".wad" and a:sub(1, 1) ~= "-" then
      out.iwad = a
      i = i + 1
    else
      i = i + 1
    end
  end
  return out
end

-- Mensagens do d_englsh.h original (GAMMALVL0..4).
local GAMMA_MESSAGES = {
  "Gamma correction OFF",
  "Gamma correction level 1",
  "Gamma correction level 2",
  "Gamma correction level 3",
  "Gamma correction level 4",
}
local opts = take_args(arg)

local TICRATE = 35
local TICK_MS = 1000 / TICRATE

local w = wad.new()
local iwad_path = opts.iwad or wad.find_iwad()
wad.add_file(w, iwad_path)
for i = 1, #opts.files do
  wad.add_file(w, opts.files[i])
end
local title = wad.cache_lump_name(w, "TITLEPIC")
local pal = wad.cache_lump_name(w, "PLAYPAL")
local res = rdata.new(w)
res:init()
--res.sprites = sprites.init_defs(w)
local renderer = render.new(res)

local sound = sound_mod.new()

local game = {
  running = true,
  gamestate = "title",
  show_messages = true,
  detail_level = 0,
  screen_size = 7,
  mouse_sensitivity = 5,
  sound = sound,
  skill = opts.skill,
  episode = opts.episode,
  scale = opts.scale,
  mapn = opts.mapn,
  warp = opts.warp,
  show_fps = opts.show_fps,
  crt = opts.crt,
  nomonsters = opts.nomonsters,
  fastparm = opts.fastparm,
  respawnparm = opts.respawnparm,
  nocheats = opts.nocheats,
  use_mouse = true,
  mouse_sensitivity = 5,
  mousex = 0,
  mousey = 0,
  mouse_fire = false,
  iwad_path = iwad_path,
  world = nil,
  wad = w,
  paused = false,       -- C2: a tecla Pause (paused do Doom)
  sendpause = false,    -- C2: Pause apertada, vale no proximo tic (G_BuildTiccmd)
}

-- C2: liga ou desliga a pausa (paused do G_Ticker). Como o
-- S_PauseSound/S_ResumeSound do Doom, so a musica para.
local function pausar(on)
  game.sendpause = false
  if game.paused ~= on then
    game.paused = on
    sound_mod.pause_music(sound, on)
  end
end

-- C2: o mundo para neste tic? Como o P_Ticker do Doom: com a pausa e, com o
-- menu aberto, depois do primeiro tic do nivel (no Doom, viewz ~= 1; aqui,
-- leveltime > 0, que tambem vale depois de um load).
local function mundo_parado(menu)
  return game.paused or (menu.active and (game.leveltime or 0) > 0)
end

function game.start_sound(name)
  sound.play(name)
end

function game.damage_mobj(target, source, damage, inflictor)
  enemy.damage_mobj(game, target, source, damage, inflictor)
end
-- O esmagamento (C1: pelo dano do jogo; C4c: como o PIT_ChangeSector, so
-- a cada 4 tics, !(leveltime&3), com um jato de sangue)
collision.esmagar = function(world, thing)
  if (game.leveltime or 0) % 4 == 0 then
    game.damage_mobj(thing, nil, 10, nil)
    collision.jato_de_sangue(world, thing, game)
  end
end

local function copy_list(src, n)
  local out = {}
  for i = 0, n - 1 do
    out[i] = src[i]
  end
  return out
end

local function apply_carry(player, prev)
  player.health = prev.health
  player.mo.health = prev.health
  player.armorpoints = prev.armorpoints
  player.armortype = prev.armortype
  player.ammo = prev.ammo
  player.maxammo = prev.maxammo
  player.weaponowned = prev.weaponowned
  player.pendingweapon = 10
  player.readyweapon = prev.readyweapon
  -- C3: o jogador do Doom passa de um nivel ao outro com os psprites; so
  -- a posicao horizontal da arma sobrevive (P_SetupPsprites apaga os
  -- estados e sobe a arma de baixo)
  player.psprites[0].sx = prev.psprite_sx or 0
  player.psprites[1].sx = prev.psprite_sx or 0
  player.cheats = prev.cheats
  player.didsecret = prev.didsecret
  player.cards = { [0] = false, false, false, false, false, false }
  player.damagecount = 0
  player.bonuscount = 0
  player.backpack = 0
  player.extralight = 0
  player.playerstate = 0
end

local function lump_patch(name)
  local n = wad.check_num_for_name(w, name)
  if n < 0 then
    return nil
  end
  return wad.cache_lump_num(w, n)
end

function game.touch_special(special, toucher)
  if player_mod.take_key(special, toucher, game) and game.world then
    thinker.remove_mobj(game.world, special)
  end
end

function game.use_special(line, thing, side)
  if game.specials then
    return specials_mod.use_special(game.specials, line, thing, side)
  end
  return false
end

function game.cross_special(line, side, thing)
  if game.specials then
    specials_mod.cross_special(game.specials, line, side, thing)
  end
end

function game.shoot_special(line, thing)
  if game.specials then
    specials_mod.shoot_special(game.specials, line, thing)
  end
end

function game.begin_exit(self)
  if self.automap then
    am_map.stop(self.automap)
  end
  local p = self.player
  local secret = self.specials and self.specials.secret_exit
  self.was_secret = secret and true or false
  local commercial = wad.check_num_for_name(w, "MAP01") >= 0
  if p and self.mapn == 9 then
    p.didsecret = true
  end
  if p then
    self.carry = {
      health = p.health,
      armorpoints = p.armorpoints,
      armortype = p.armortype,
      ammo = copy_list(p.ammo, 4),
      maxammo = copy_list(p.maxammo, 4),
      weaponowned = copy_list(p.weaponowned, 9),
      readyweapon = p.readyweapon,
      psprite_sx = p.psprites[0].sx,
      cheats = p.cheats,
      didsecret = (self.mapn == 9) or p.didsecret or secret or false,
    }
  end
  if not commercial and self.mapn == 8 then
    self.finale = finale_mod.new(self)
    self.gamestate = "finale"
    print("finale")
    return
  end
  local nxt
  if secret then
    nxt = 9
  elseif self.mapn == 9 then
    local back = { [1] = 4, [2] = 6, [3] = 7, [4] = 3 }
    nxt = back[self.episode] or 1
  else
    nxt = self.mapn + 1
  end
  self.pending_map = nxt
  local kills = self.totalkills or 0
  local items = self.totalitems or 0
  local secrets = self.totalsecret or 0
  if kills < 1 then
    kills = 1
  end
  if items < 1 then
    items = 1
  end
  if secrets < 1 then
    secrets = 1
  end
  self.wi = wi_mod.new(self, {
    epsd = self.episode - 1,
    last = self.mapn - 1,
    next = nxt - 1,
    maxkills = kills,
    maxitems = items,
    maxsecret = secrets,
    partime = wi_mod.partime(self.episode, self.mapn, commercial),
    skills = p and (p.killcount or 0) or 0,
    sitems = p and (p.itemcount or 0) or 0,
    ssecret = p and (p.secretcount or 0) or 0,
    stime = self.leveltime or 0,
    didsecret = p and p.didsecret or false,
    commercial = commercial,
  })
  self.gamestate = "intermission"
  print(string.format("intermissao E%dM%d", self.episode, nxt))
end

function game.finish_finale(self)
  local action = "title"
  if self.finale and self.finale.action ~= "" then
    action = self.finale.action
  end
  self.finale = nil
  if action == "worlddone" then
    self.mapn = self.pending_map
    self.start_level(self)
    return
  end
  self.gamestate = "title"
  self.carry = nil
  self.player = nil
  self.world = nil
  self.specials = nil
  sound_mod.play_title_music(sound)
end

function game.advance(self)
  local commercial = wad.check_num_for_name(w, "MAP01") >= 0
  if commercial and finale_mod.commercial_map(self.mapn, self.was_secret) then
    self.finale = finale_mod.new(self)
    self.gamestate = "finale"
    return
  end
  local lump = string.format("E%dM%d", self.episode, self.pending_map)
  if wad.check_num_for_name(w, "MAP01") >= 0 then
    lump = string.format("MAP%02d", self.pending_map)
  end
  if wad.check_num_for_name(w, lump) < 0 then
    self.gamestate = "title"
    self.carry = nil
    self.player = nil
    self.world = nil
    self.specials = nil
    sound_mod.play_title_music(sound)
    return
  end
  self.mapn = self.pending_map
  self.start_level(self)
end

function game.end_game(self)
  pausar(false)  -- C2: o titulo nao fica pausado (D_AdvanceDemo)
  if self.automap then
    am_map.stop(self.automap)
  end
  self.finale = nil
  self.wi = nil
  self.wiping = false
  self.gamestate = "title"
  self.carry = nil
  self.player = nil
  self.world = nil
  self.specials = nil
  sound_mod.play_title_music(sound)
end

function game.save_game(self, slot, desc)
  local name = desc
  if (name == nil or name == "") and self.world then
    name = self.world.mapname
  end
  return saveg.write(self, slot, name or "save")
end

function game.load_game(self, slot)
  return saveg.load(self, slot)
end

function game.slot_desc(self, slot)
  return saveg.description(self, slot)
end

function game.start_level(self)
  self.level_gen = (self.level_gen or 0) + 1 -- replay: niveis montados (hash de estado)
  pausar(false)  -- C2: todo nivel comeca sem pausa (G_InitNew)
  if self.automap then
    am_map.reset_level(self.automap)
  end
  rng.clear()
  local world = world_mod.new()
  world_mod.setup_level(world, w, res, self.episode, self.mapn)
  render.set_level_sky(res, w, self.episode, self.mapn)
  res:update_anims(0)
  self.world = world
  self.res = res
  self.player = nil
  self.specials = specials_mod.new(world, res, sound)
  local kills, items = thinker.spawn_map(world, self.skill, self)
  local secrets = 0
  for i = 1, #world.sectors do
    if world.sectors[i].special == 9 then
      secrets = secrets + 1
    end
  end
  self.totalkills = kills
  self.totalitems = items
  self.totalsecret = secrets
  thinker.apply_fast(self)
  if self.status and self.player then
    status_mod.reset(self.status, self.player)
  end
  sound_mod.cut_sfx(sound)
  sound_mod.play_level_music(sound, self.episode, self.mapn)
  self.gamestate = "view"
  self.leveltime = 0
  self.turnheld = 0
  local ps = world_mod.player_start(world)
  local px, py = 0, 0
  if ps then
    px, py = ps.x, ps.y
  end
  if self.player and self.carry then
    apply_carry(self.player, self.carry)
    self.carry = nil
  end
  if self.player then
    pspr.preparar_psprites(self.player, self)  -- C3: P_SetupPsprites
  end
  print(string.format(
    "vista %s  linhas %d  coisas %d  jogador %d,%d",
    world.mapname, #world.lines, #world.mobjs, px, py
  ))
end

local menu = menu_mod.new(w, sound, game)
game.menu = menu
game.status = status_mod.new(w)
game.automap = am_map.new()
game.cheats = cheats_mod.new()
game.wipe = wipe_mod.new()
game.wiping = false
game.st_palette = 0
local fb = v.new_fb()
local raw = nil
local dirty = true

local jitlib = rawget(_G, "jit")
local runtime = jitlib and ("luajit " .. tostring(jitlib.version)) or _VERSION
print("lua_doom: " .. runtime .. "  Tab abre o mapa, o texto final conta a historia")
print("texturas " .. res:texture_count() .. "  flats " .. res:flat_count())

print(game.scale)
video.init(v.SCREENWIDTH, v.SCREENHEIGHT, game.scale, "DOOM (" .. runtime .. ")")
video.set_palette(pal)
video.set_crt(game.crt)
sound_mod.init(sound, w)
if opts.nosound then
  sound.enabled = false
end
if opts.nomusic then
  sound.music_enabled = false
end
if game.warp then
  game.start_level(game)
  game.wipe_state = "view"
else
  sound_mod.play_title_music(sound)
end

-- C2: a figura "PAUSE", como no D_Display do Doom: no alto da vista (no alto
-- da tela com o automapa), centrada, por cima da vista e da barra, por baixo
-- do menu.
local pause_pic = lump_patch("M_PAUSE")
local function paint_pause()
  if not (game.paused and pause_pic) then
    return
  end
  local blocks = game.screen_size + 3
  local width, height = 320, 200
  if blocks < 11 then
    width = blocks * 32
    height = (blocks * 168 // 10) & ~7
  end
  local x = (320 - width) // 2
  local y = 4
  if not (game.automap and game.automap.active) and width < 320 then
    y = (200 - 32 - height) // 2 + 4
  end
  v.draw_patch(fb, x + (width - 68) // 2, y, pause_pic)
end

local function paint_view()
  if game.automap and game.automap.active then
    v.fill(fb, 0)
    am_map.drawer(game.automap, fb, game)
    if game.status and game.player then
      status_mod.draw(game.status, fb, game.player, game.show_messages)
    end
    paint_pause()
    return
  end
  local p = game.player
  local mo = p and p.mo
  local x, y, z, ang = 0, 0, 41 * 65536, 0
  local extra, cmap = 0, 0
  if mo then
    x, y, z, ang = mo.x, mo.y, p.viewz, mo.angle
    extra = p.extralight or 0
    cmap = p.fixedcolormap or 0
  end
  render.set_view_size(renderer, game.screen_size + 3, game.detail_level)
  render.setup_frame(renderer, x, y, z, ang, extra, cmap)
  v.fill(fb, 0)
  render.render(renderer, game.world, fb)
  sprites.draw(renderer, game.world, fb)
  render.draw_masked(renderer)
  if p then
    sprites.draw_weapon(renderer, fb, p)  -- C3: os psprites acesos (R_DrawPlayerSprites)
  end
  if game.status and game.player and renderer.screenblocks < 11 then
    status_mod.draw(game.status, fb, game.player, game.show_messages)
  end
  paint_pause()
end

local function apply_palette()
  local paln = 0
  local p = game.player
  if p and game.gamestate == "view" then
    local cnt = p.damagecount or 0
    local strength = 0
    if p.powers then
      strength = p.powers[1] or 0
    end
    if strength ~= 0 then
      local bzc = 12 - math.floor(strength / 64)
      if bzc > cnt then
        cnt = bzc
      end
    end
    if cnt ~= 0 then
      paln = math.floor((cnt + 7) / 8)
      if paln >= 8 then
        paln = 7
      end
      paln = paln + 1
    elseif (p.bonuscount or 0) ~= 0 then
      paln = math.floor((p.bonuscount + 7) / 8)
      if paln >= 4 then
        paln = 3
      end
      paln = paln + 9
    else
      local feet = 0
      if p.powers then
        feet = p.powers[3] or 0
      end
      if feet > 4 * 32 or (feet % 16) >= 8 then
        paln = 13
      end
    end
  end
  if paln == game.st_palette then
    return
  end
  game.st_palette = paln
  local off = paln * 768
  video.set_palette(pal:sub(off + 1, off + 768))
end

local function paint_state()
  if game.gamestate == "view" and game.world then
    paint_view()
  elseif game.gamestate == "intermission" and game.wi then
    v.fill(fb, 0)
    wi_mod.draw(game.wi, fb)
  elseif game.gamestate == "finale" and game.finale then
    finale_mod.draw(game.finale, fb)
  else
    v.fill(fb, 0)
    v.draw_patch(fb, 0, 0, title)
  end
end

local function draw_fps()
  if not game.show_fps or not game.status then
    return
  end
  local text = game.fps_text or "0 FPS"
  local width = status_mod.text_width(game.status, text)
  local x = v.SCREENWIDTH - 6 - width
  if x < 0 then
    x = 0
  end
  status_mod.draw_text(game.status, fb, x, 4, text)
end

local function redraw()
  if game.wiping then
    menu_mod.draw(menu, fb)
    draw_fps()
    raw = v.to_raw(fb)
    dirty = false
    apply_palette()
    return
  end
  local prev = game.wipe_state
  local need = prev ~= nil and (prev ~= game.gamestate or game.force_wipe)
  if prev == "title" and game.gamestate == "view" and not game.force_wipe then
    need = false
  end
  game.force_wipe = false
  if need then
    wipe_mod.capture_start(game.wipe, fb)
  end
  paint_state()
  if need then
    wipe_mod.capture_end(game.wipe, fb)
    wipe_mod.begin(game.wipe, fb)
    game.wiping = true
  end
  game.wipe_state = game.gamestate
  menu_mod.draw(menu, fb)
  draw_fps()
  raw = v.to_raw(fb)
  dirty = false
  apply_palette()
end

-- Modo replay (video.lua, DOOM_REPLAY): resumo do estado gravado a cada
-- quadro, no mesmo formato do G.state_string da branch atmos, para comparar
-- as duas branches pelo hash (fase de correcoes, docs/DIFERENCAS_DOOM.md).
-- Os campos marcados com DOOM_REPLAY_SIDES=1 so entram quando o teste liga.
local function state_string()
  local t = {
    tostring(game.gamestate), tostring(game.leveltime), tostring(rng.index()),
    tostring(game.episode), tostring(game.mapn), tostring(game.wiping),
    tostring(menu.active), tostring(game.level_gen),
  }
  if game.paused then
    t[#t + 1] = "pausado"  -- C2 (so quando pausado: o hash antigo nao muda)
  end
  local extra = os.getenv("DOOM_REPLAY_SIDES") == "1"
  local world = game.world
  if world then
    for i = 1, #world.mobjs do
      local mo = world.mobjs[i]
      t[#t + 1] = string.format("%d,%d,%d,%d,%s,%s,%s",
        mo.x or 0, mo.y or 0, mo.z or 0, mo.angle or 0,
        tostring(mo.health), tostring(mo.istate), tostring(mo.tics))
    end
    for i = 1, #world.sectors do
      local s = world.sectors[i]
      t[#t + 1] = string.format("%d,%d,%d", s.floorheight, s.ceilingheight, s.lightlevel)
    end
    for i = 1, extra and #world.sides or 0 do
      local sd = world.sides[i]
      t[#t + 1] = string.format("s%s,%s,%s,%s", tostring(sd.toptexture),
        tostring(sd.midtexture), tostring(sd.bottomtexture), tostring(sd.textureoffset))
    end
    for i = 1, extra and #world.sectors or 0 do
      local s = world.sectors[i]
      t[#t + 1] = string.format("f%s,%s", tostring(s.floorpic), tostring(s.ceilingpic))
    end
  end
  -- intermissao e finale (passo 7): o que as telas escrevem e o desenho le;
  -- tambem so com DOOM_REPLAY_SIDES=1
  if os.getenv("DOOM_REPLAY_SIDES") == "1" then
    local wi = game.wi
    if wi then
      t[#t + 1] = string.format("w%s,%s,%s,%s,%s,%s,%s,%s,%s", tostring(wi.state),
        tostring(wi.cnt_kills), tostring(wi.cnt_items), tostring(wi.cnt_secret),
        tostring(wi.cnt_time), tostring(wi.cnt_par), tostring(wi.snl_pointeron),
        tostring(wi.bcnt), tostring(wi.accelerate))
    end
    local fi = game.finale
    if fi then
      t[#t + 1] = string.format("e%s,%s", tostring(fi.stage), tostring(fi.count))
    end
    -- o rosto da barra (passo 8b): o que a task Rosto escreve e o desenho le
    if game.status then
      t[#t + 1] = string.format("r%s", tostring(game.status.face_index))
    end
    -- o menu (passo 8c): a caveira, a tela e o item
    t[#t + 1] = string.format("m%s,%s,%s", tostring(menu.which_skull),
      tostring(menu.screen), tostring(menu.item_on))
    -- o automapa (passo 8d): aberto, seguir, posicao e escala
    local am = game.automap
    if am then
      t[#t + 1] = string.format("am%s,%s,%s,%s,%s", tostring(am.active),
        tostring(am.followplayer), tostring(am.m_x), tostring(am.m_y), tostring(am.scale_mtof))
    end
  end
  local p = game.player
  if p then
    local w, f = p.psprites[0], p.psprites[1]
    t[#t + 1] = string.format("p%s,%s,%s,%s,%s", tostring(p.health), tostring(p.armorpoints),
      tostring(p.readyweapon), tostring(w.state), tostring(w.sy))
    if extra then
      t[#t + 1] = string.format("a%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s", tostring(w.tics),
        tostring(w.sx), tostring(f.state), tostring(f.tics), tostring(f.sx), tostring(f.sy),
        tostring(p.pendingweapon), tostring(p.attackdown), tostring(p.refire),
        tostring(p.extralight), tostring(p.mo and p.mo.flags))
    end
  end
  return table.concat(t, ";")
end
video.state_hook = state_string
game.level_gen = game.level_gen or 0      -- como no passo1 (game.lua)

local held = {}
local accum = 0
local last = video.ticks()
local fps_n = 0
local fps_t = last
game.fps_text = "0 FPS"
while game.running do
  local events = video.poll()
  for i = 1, #events do
    local ev = events[i]
    if ev.replay_exit then
      -- comando de teste do modo replay (video.lua): saida do nivel
      if video.replay and game.specials and game.gamestate == "view" then
        game.specials.exit_requested = true
        game.specials.secret_exit = ev.secret or nil
      end
    elseif ev.replay_die then
      -- comando de teste do modo replay: o jogador morre
      if video.replay and game.player and game.player.mo and game.gamestate == "view" then
        game.damage_mobj(game.player.mo, nil, 10000, nil)
      end
    elseif ev.replay_use then
      -- comando de teste do modo replay: "use" na linha N (indice do WAD)
      local line = game.world and game.world.lines[ev.replay_use + 1]
      if video.replay and line and game.player and game.player.mo and game.gamestate == "view" then
        game.use_special(line, game.player.mo, 0)
      end
    elseif ev.replay_cross then
      -- comando de teste do modo replay: cruza a linha N pela frente
      local line = game.world and game.world.lines[ev.replay_cross + 1]
      if video.replay and line and game.player and game.player.mo and game.gamestate == "view" then
        game.cross_special(line, 0, game.player.mo)
      end
    elseif ev.replay_goto then
      -- comando de teste do modo replay: poe o jogador em (x, y)
      local mo = game.player and game.player.mo
      if video.replay and mo and game.gamestate == "view" then
        collision.unset_thing_position(game.world, mo)
        mo.x = ev.replay_goto[1] * 65536
        mo.y = ev.replay_goto[2] * 65536
        mo.momx, mo.momy, mo.momz = 0, 0, 0
        local ss = collision.point_in_subsector(game.world, mo.x, mo.y)
        mo.floorz = ss.sector.floorheight
        mo.ceilingz = ss.sector.ceilingheight
        mo.z = mo.floorz
        collision.set_thing_position(game.world, mo)
        game.player.viewz = mo.z + game.player.viewheight
      end
    elseif ev.mouse then
      if ev.dx then
        game.mousex = game.mousex + ev.dx
        game.mousey = game.mousey - ev.dy
      end
      if ev.button == 1 then
        game.mouse_fire = ev.down and true or false
      end
    elseif ev.down and ev.key == "quit" then
      game.running = false
    elseif ev.key ~= "" then
      if ev.down and ev.key == "return" and (held.alt or ev.alt) then
        video.toggle_fullscreen()
      elseif ev.down then
        local block_menu = (game.gamestate == "intermission" or game.gamestate == "finale")
          and not menu.active and ev.key == "return"
        local used = false
        if not block_menu and menu_mod.responder(menu, ev.key) then
          used = true
          dirty = true
        end
        if not used and game.automap and am_map.responder(game.automap, ev.key, true, game) then
          used = true
          dirty = true
        end
        if used then
          held[ev.key] = nil
        else
          held[ev.key] = true
          if game.finale and game.gamestate == "finale" then
            finale_mod.responder(game.finale)
          end
          if game.cheats then
            cheats_mod.feed(game.cheats, ev.key, game)
          end
          if ev.key == "f11" then
            -- Correcao de gama, como no M_Responder original (qualquer tela).
            game.usegamma = video.set_gamma(((game.usegamma or 0) + 1) % 5)
            if game.player then
              player_mod.set_message(game.player, GAMMA_MESSAGES[game.usegamma + 1])
            end
            dirty = true
          end
          if ev.key == "pause" and game.gamestate == "view" then
            game.sendpause = true  -- C2: G_Responder (vale no proximo tic)
          end
          if game.gamestate == "view" and not menu.active then
            if ev.key == "equals" and game.screen_size < 8 then
              game.screen_size = game.screen_size + 1
              dirty = true
            elseif ev.key == "minus" and game.screen_size > 0 then
              game.screen_size = game.screen_size - 1
              dirty = true
            elseif ev.key == "f12" then
              game.show_fps = not game.show_fps
              dirty = true
            end
          end
        end
      else
        held[ev.key] = nil
        if game.automap then
          am_map.responder(game.automap, ev.key, false, game)
        end
      end
    end
  end
  local now = video.ticks()
  accum = accum + (now - last)
  last = now
  local guard = 0
  game.held = held
  while accum >= TICK_MS and guard < 4 do
    if game.wiping then
      if wipe_mod.tick(game.wipe, 1, fb) then
        game.wiping = false
      end
      dirty = true
    else
    if menu_mod.ticker(menu) then
      dirty = true
    end
    if game.gamestate == "view" and game.player and game.world then
      if game.automap then
        am_map.ticker(game.automap, game)
      end
      if menu.active then
        game.player.cmd = player_mod.empty_cmd()
        game.mousex = 0
        game.mousey = 0
      else
        local cmd, heldn = player_mod.build_ticcmd(
          held, game.turnheld or 0, game.player,
          game.mousex, game.mousey, game.mouse_sensitivity, game.mouse_fire
        )
        game.turnheld = heldn
        game.player.cmd = cmd
        game.mousex = 0
        game.mousey = 0
      end
      if game.sendpause then
        -- C2: o comando da pausa troca os botoes (BT_SPECIAL); o G_Ticker
        -- alterna paused, e o P_PlayerThink zera os botoes
        game.player.cmd.buttons = 0
        pausar(not game.paused)
      end
      local morte = false
      if not mundo_parado(menu) then  -- C2: o P_Ticker
        player_mod.think(game.world, game.player, game, game.leveltime or 0)
        player_mod.tick_fx(game.world)
        if game.player and game.player.playerstate == player_mod.PST_REBORN then
          game.start_level(game)
          morte = true
        else
          thinker.tick(game.world, game)
          if game.specials then
            specials_mod.tick(game.specials)
          end
          res:update_anims(game.leveltime or 0)
          if game.specials and game.specials.exit_requested then
            game.begin_exit(game)
            break
          end
          game.leveltime = (game.leveltime or 0) + 1
        end
      end
      if not morte and game.status then  -- a barra anda tambem na pausa (ST_Ticker)
        status_mod.ticker(game.status, game.player)
      end
      dirty = true
    elseif game.gamestate == "intermission" and game.wi then
      wi_mod.ticker(game.wi)
      if game.wi.done then
        game.wi = nil
        game.advance(game)
      end
      dirty = true
    elseif game.gamestate == "finale" and game.finale then
      finale_mod.ticker(game.finale)
      if game.finale and game.finale.done then
        game.finish_finale(game)
      end
      dirty = true
    end
    end
    accum = accum - TICK_MS
    guard = guard + 1
  end
  if accum > TICK_MS * 4 then
    accum = 0
  end
  if dirty or raw == nil then
    redraw()
  end
  sound_mod.update(sound)
  video.mouse_relative(game.use_mouse and game.gamestate == "view" and not menu.active)
  video.present(raw)
  video.delay(1)
  fps_n = fps_n + 1
  local fps_now = video.ticks()
  if fps_now - fps_t >= 1000 then
    game.fps_text = tostring(fps_n) .. " FPS"
    fps_n = 0
    fps_t = fps_now
    if game.show_fps then
      dirty = true
    end
  end
end

sound_mod.shutdown(sound)
video.shutdown()
print("janela fechada")
