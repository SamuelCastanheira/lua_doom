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
-- Estado e regras do jogo, sem o laco principal e sem o fluxo de telas.
--
-- Passo 1: extraido do main.lua (laco imperativo) em fases.
-- Passo 2: as transicoes de tela sairam daqui e foram para o main.atm;
--          este modulo so monta telas e registra pedidos (game.request).
-- A referencia imperativa original esta na tag "passo1" (main.lua).
--
-- Um quadro e dividido em fases, sempre nesta ordem (o main.atm garante):
--   1. handle_input(ev)   para cada evento do video.poll()
--   2. ate 4 tics:        se wiping: tic_wipe()
--                         senao:     tic_menu(), depois a tela atual:
--                                    tic_view_antes()   -> "segue" | "parado"
--                                    (emit :game.jogador -> task Jogador)
--                                    tic_view_meio()    -> "segue" | "morte"
--                                    (emit :game.specials -> specials_resto())
--                                    tic_view_depois()  -> nil | "saida"
--                                    intermissao e finale: tasks de telas.atm
--                                    (passo 7), com :game.tic
--   3. frame()            redesenha, toca som, apresenta
-- Depois das fases 1 e 2, o main.atm emite os pedidos de transicao
-- (G.take_requests) como eventos.
local M = {}

local TICRATE = 35
M.TICRATE = TICRATE
M.TICK_MS = 1000 / TICRATE

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

local framebuffer_c = require("framebuffer_c")

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
-- O executavel "atmos" coloca o nome do script em arg[1] (no Lua puro ele
-- fica em arg[0]) e repassa um "--" separador. Devolve so os argumentos do jogo.
function M.atmos_args(argv)
  local out = {}
  local first = 1
  if argv and type(argv[1]) == "string" and argv[1]:sub(-4) == ".atm" then
    first = 2
  end
  -- "atmos main.atm -- -fps" (o "--" impede o atmos de ler as opcoes do jogo)
  if argv and argv[first] == "--" then
    first = first + 1
  end
  for i = first, #(argv or {}) do
    out[#out + 1] = argv[i]
  end
  return out
end

function M.new(argv)
  local opts = take_args(argv)
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
  }

  function game.start_sound(name)
    sound.play(name)
  end

  function game.damage_mobj(target, source, damage, inflictor)
    enemy.damage_mobj(game, target, source, damage, inflictor)
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
    player.psprite_state = "up"
    player.psprite_sy = 128 * 65536
    player.psprite_body = ""
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

  -- ===================================================================
  -- Transicoes de tela (passo 2 da migracao para Atmos).
  --
  -- Antes, begin_exit / advance / finish_finale / end_game decidiam a
  -- proxima tela e escreviam game.gamestate. Agora a decisao fica no
  -- main.atm (tasks Fluxo, Jogo, Nivel, Saida). O Lua so:
  --   * registra PEDIDOS vindos do menu, dos cheats e da janela
  --     (game.request), que o main.atm emite como eventos nas fronteiras
  --     de fase;
  --   * MONTA o que cada tela precisa (nivel, intermissao, finale) e faz
  --     a limpeza ao voltar ao titulo.
  -- ===================================================================

  local requests = {}

  -- Pedido de transicao. Tags: jogo.novo {episode, mapn, skill},
  -- jogo.carregar {data}, jogo.fim, jogo.sair, nivel.trocar {episode, mapn}.
  function game.request(tag, data)
    local ev = data or {}
    ev.tag = tag
    requests[#requests + 1] = ev
    if video.replay then
      print("pedido " .. tag) -- cobertura do teste de equivalencia
    end
  end

  -- Parte de G_ExitLevel/G_DoCompleted que nao decide nada: fecha o
  -- automapa, registra saida secreta e guarda o que o jogador leva para o
  -- proximo nivel (carry). Devolve true se a saida foi secreta.
  function game.end_level(self)
    if self.automap then
      am_map.stop(self.automap)
    end
    local p = self.player
    local secret = self.specials and self.specials.secret_exit
    self.was_secret = secret and true or false
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
        cheats = p.cheats,
        didsecret = (self.mapn == 9) or p.didsecret or secret or false,
      }
    end
    return self.was_secret
  end

  function game.is_commercial()
    return wad.check_num_for_name(w, "MAP01") >= 0
  end

  -- Monta a tela de texto/arte final. "announce" so imprime no log, como o
  -- antigo begin_exit fazia (o caminho do Doom 2 nao imprimia).
  function game.make_finale(self, announce)
    self.finale = finale_mod.new(self)
    if announce then
      print("finale")
    end
  end

  -- Monta a intermissao do nivel atual para o mapa "nxt" (WI_Start).
  function game.make_intermission(self, nxt)
    local p = self.player
    local commercial = game.is_commercial()
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
    print(string.format("intermissao E%dM%d", self.episode, nxt))
  end

  -- Doom 2: ha texto entre certos mapas (F_StartFinale via G_WorldDone).
  function game.commercial_finale(self)
    return finale_mod.commercial_map(self.mapn, self.was_secret)
  end

  -- O lump do mapa existe neste WAD?
  function game.map_exists(self, mapn)
    local lump = string.format("E%dM%d", self.episode, mapn)
    if game.is_commercial() then
      lump = string.format("MAP%02d", mapn)
    end
    return wad.check_num_for_name(w, lump) >= 0
  end

  -- Volta ao titulo: descarta o jogo atual e toca a musica do titulo.
  function game.to_title(self)
    self.carry = nil
    self.player = nil
    self.world = nil
    self.specials = nil
    sound_mod.play_title_music(sound)
  end

  -- "End Game" no menu: so pede. A limpeza e clear_game, chamada pelo
  -- main.atm depois de encerrar a task do jogo.
  function game.end_game(self)
    self.request("jogo.fim")
  end

  function game.clear_game(self)
    if self.automap then
      am_map.stop(self.automap)
    end
    self.finale = nil
    self.wi = nil
    self.wiping = false
    game.to_title(self)
  end

  function game.save_game(self, slot, desc)
    local name = desc
    if (name == nil or name == "") and self.world then
      name = self.world.mapname
    end
    return saveg.write(self, slot, name or "save")
  end

  -- Menu "Load Game": le o arquivo agora (para o menu saber se deu certo)
  -- e pede a troca; o nivel e montado pela task Nivel (load_level).
  function game.load_game(self, slot)
    local data = saveg.read(self, slot)
    if data == nil then
      return false
    end
    self.request("jogo.carregar", { data = data })
    return true
  end

  function game.load_level(self, data)
    return saveg.apply(self, data)
  end

  function game.slot_desc(self, slot)
    return saveg.description(self, slot)
  end

  -- Monta o nivel game.episode / game.mapn (G_DoLoadLevel). Nao muda de
  -- tela: quem entra em "view" e a task Nivel. level_gen conta instancias
  -- de nivel (entra no hash de estado do teste de equivalencia).
  function game.build_level(self)
    self.level_gen = (self.level_gen or 0) + 1
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
    self.specials = specials_mod.new(world, res, sound, self.pools)
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
    -- o nivel e montado pela task Jogo (G.initial_request)
    game.wipe_state = "view"
  else
    sound_mod.play_title_music(sound)
  end

  local function paint_view()
    if game.automap and game.automap.active then
      v.fill(fb, 0)
      am_map.drawer(game.automap, fb, game)
      if game.status and game.player then
        status_mod.draw(game.status, fb, game.player, game.show_messages)
      end
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
    if p and (p.playerstate ~= player_mod.PST_DEAD or p.psprite_sy < player_mod.WEAPONBOTTOM) then
      sprites.draw_weapon(renderer, fb, p, game.leveltime or 0)
    end
    if game.status and game.player and renderer.screenblocks < 11 then
      status_mod.draw(game.status, fb, game.player, game.show_messages)
    end
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

  -- O quadro (passo 6): o redesenho em tres partes, chamadas pela task do
  -- quadro no main.atm. Entre G.quadro_antes e G.quadro_depois, o main.atm
  -- emite :game.frame e a tela viva desenha a si mesma (G.pintar_vista,
  -- G.pintar_intermissao, G.pintar_finale, G.pintar_titulo). Antes era uma
  -- funcao so (redraw), que escolhia a tela com "if game.gamestate == ..."
  -- (paint_state); esse despacho sumiu. Sempre ha uma tela viva no quadro
  -- (conferido nos roteiros: nenhum quadro ficou sem pintor).
  local quadro_wipe = false            -- a tela mudou: este quadro comeca um wipe

  -- Devolve "pintar" (redesenhar: a tela desenha a si mesma), "sobrepor" (a
  -- transicao esta em andamento: so o menu e o FPS por cima) ou nil (nada
  -- mudou desde o ultimo quadro). Se a tela mudou, captura a tela antiga.
  local function quadro_antes_q()
    if not (dirty or raw == nil) then
      return nil
    end
    if game.wiping then
      return "sobrepor"
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
    quadro_wipe = need
    return "pintar"
  end

  local function pintar_vista_q()
    paint_view()
  end

  local function pintar_intermissao_q()
    v.fill(fb, 0)
    wi_mod.draw(game.wi, fb)
  end

  local function pintar_finale_q()
    finale_mod.draw(game.finale, fb)
  end

  local function pintar_titulo_q()
    v.fill(fb, 0)
    v.draw_patch(fb, 0, 0, title)
  end

  -- Fecha o redesenho: com a tela nova, comeca o wipe se a tela mudou; menu,
  -- FPS e paleta por cima. Devolve true se um wipe comecou neste quadro (o
  -- main.atm emite :tela.transicao). "pintado": vem de quadro_antes.
  local function quadro_depois_q(pintado)
    local comecou = false
    if pintado then
      if quadro_wipe then
        wipe_mod.capture_end(game.wipe, fb)
        wipe_mod.begin(game.wipe, fb)
        game.wiping = true
        comecou = true
      end
      game.wipe_state = game.gamestate
    end
    menu_mod.draw(menu, fb)
    draw_fps()
    raw = v.to_raw(fb)
    dirty = false
    apply_palette()
    return comecou
  end

  local held = {}
  local fps_n = 0
  local fps_t = video.ticks()
  game.fps_text = "0 FPS"
  game.held = held
  game.level_gen = game.level_gen or 0

  local G = { game = game }

  -- Fase 1: um evento de entrada (teclado, mouse, fechar janela).
  function G.handle_input(ev)
    if ev.replay_exit then
      -- comando de teste do modo replay (video.lua): saida do nivel
      if video.replay and game.specials and game.gamestate == "view" then
        game.specials.exit_requested = true
        game.specials.secret_exit = ev.secret or nil
      end
      return
    end
    if ev.replay_die then
      -- comando de teste do modo replay (video.lua): o jogador morre
      if video.replay and game.player and game.player.mo and game.gamestate == "view" then
        game.damage_mobj(game.player.mo, nil, 10000, nil)
      end
      return
    end
    if ev.replay_use then
      -- comando de teste do modo replay (video.lua): "use" na linha N
      local line = game.world and game.world.lines[ev.replay_use + 1]
      if video.replay and line and game.player and game.player.mo and game.gamestate == "view" then
        game.use_special(line, game.player.mo, 0)
      end
      return
    end
    if ev.replay_cross then
      -- comando de teste do modo replay (video.lua): cruza a linha N
      local line = game.world and game.world.lines[ev.replay_cross + 1]
      if video.replay and line and game.player and game.player.mo and game.gamestate == "view" then
        game.cross_special(line, 0, game.player.mo)
      end
      return
    end
    if ev.replay_goto then
      -- comando de teste do modo replay (video.lua): poe o jogador em (x, y)
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
      return
    end
    if ev.mouse then
      if ev.dx then
        game.mousex = game.mousex + ev.dx
        game.mousey = game.mousey - ev.dy
      end
      if ev.button == 1 then
        game.mouse_fire = ev.down and true or false
      end
    elseif ev.down and ev.key == "quit" then
      game.running = false
      game.request("jogo.sair")
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

  -- Fase 2a: tic da transicao de tela (enquanto ela dura, nada mais anda).
  -- Devolve true quando a transicao termina (passo 6: o relogio do main.atm
  -- volta ao tic normal).
  function G.tic_wipe()
    local fim = false
    if wipe_mod.tick(game.wipe, 1, fb) then
      game.wiping = false
      fim = true
    end
    dirty = true
    return fim
  end

  -- Fase 2b: tic do menu (anima o cursor; roda em todas as telas).
  function G.tic_menu()
    if menu_mod.ticker(menu) then
      dirty = true
    end
  end

  -- Fase 2c: tic do nivel, em quatro partes (passos 3 e 4). A task Nivel
  -- (main.atm) chama, em ordem:
  --   G.tic_view_antes()    automapa, comando do jogador
  --   emit :game.jogador    a task Jogador (passo 4c), com a Arma como filha,
  --                         no ponto do antigo player.think
  --   G.tic_view_meio()     efeitos, renascer
  --   (mobjs)               o laco dos mobjs, no Nivel (passo 5): monstros com
  --                         task por emit direcionado, os outros em Lua
  --   emit :game.specials   specials de setor: tasks nas pools do Nivel e,
  --                         entre elas, G.specials_resto() (o que ainda e
  --                         Lua), na ordem do antigo specials_mod.tick
  --   G.tic_view_depois()   texturas animadas, saida, leveltime, status
  -- Era uma funcao so (G.tic_view, tag passo2); o emit fica no meio para que
  -- as tasks de setor acordem no mesmo ponto do tic em que os thinkers
  -- rodavam (regra da ordem do tic, CLAUDE.md 4.2).
  --
  -- tic_view_antes devolve:
  --   "segue"   o tic continua (jogador, tic_view_meio, specials, depois)
  --   "parado"  fora da vista (sem jogador ou mundo): nada mais roda
  -- tic_view_meio devolve "segue" ou
  --   "morte"   o jogador vai renascer (antes: start_level aqui dentro)
  -- Quem decide o que fazer com isso e a task Jogo, no main.atm.
  function G.tic_view_antes()
    if not (game.gamestate == "view" and game.player and game.world) then
      return "parado"
    end
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
    return "segue"
  end

  -- Fase 2a, depois do emit :game.jogador (a task Jogador faz o tic do
  -- jogador e da arma, passo 4c): efeitos e renascer. Os mobjs vem depois,
  -- no Nivel (passo 5).
  -- Devolve "segue" | "morte".
  function G.tic_view_meio()
    player_mod.tick_fx(game.world)
    if game.player and game.player.playerstate == player_mod.PST_REBORN then
      dirty = true
      return "morte"
    end
    return "segue"
  end

  -- Os mobjs que pensam neste tic (passo 5): o laco que era thinker.tick fica
  -- no Nivel (main.atm), para os monstros com task acordarem na sua posicao.
  function G.pensantes()
    return thinker.pensantes(game.world, game)
  end

  -- Roda o thinker Lua dos mobjs de lista, a partir da posicao i, ate o
  -- proximo com task; devolve a posicao dele (0 se a lista acabou). Assim o
  -- laco do Nivel so da uma volta por monstro com task (custo, passo 5).
  function G.pensar_ate_task(lista, i)
    local world = game.world
    for k = i, #lista do
      local mo = lista[k]
      if mo.task then
        return k
      end
      thinker.mobj_thinker(world, mo, game)
    end
    return 0
  end

  -- Specials de setor que ainda sao thinkers Lua. Roda dentro do emit
  -- :game.specials, numa task do Nivel declarada entre as pools das partes
  -- ja migradas. A cada subpasso do passo 3, uma parte sai daqui.
  function G.specials_resto()
    if game.specials then
      specials_mod.tick(game.specials)
    end
  end

  -- Devolve "saida" (switch de saida; antes: begin_exit aqui dentro) ou nil.
  function G.tic_view_depois()
    res:update_anims(game.leveltime or 0)
    if game.specials and game.specials.exit_requested then
      return "saida"
    end
    game.leveltime = (game.leveltime or 0) + 1
    if game.status then
      status_mod.ticker(game.status, game.player)
    end
    dirty = true
    return nil
  end

  -- Fase 2c: intermissao e finale (passo 7). A sequencia de cada tela e uma
  -- task de telas.atm, que acorda com :game.tic; a cada tic ela pede o
  -- redesenho, e no fim a tela e solta.
  function G.redesenhar()
    dirty = true
  end

  function G.fim_intermissao()
    game.wi = nil
    dirty = true
  end

  function G.fim_finale()
    game.finale = nil
    dirty = true
  end

  -- Fase 3: redesenho, som e apresentacao do quadro.
  -- Fim do quadro: som, mouse, apresentar, contador de FPS.
  function G.quadro_fim()
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


  -- ---------------------------------------------- API do fluxo (main.atm)

  G.game = game

  -- O quadro (passo 6): ver quadro_antes acima.
  G.quadro_antes = quadro_antes_q
  G.pintar_vista = pintar_vista_q
  G.pintar_intermissao = pintar_intermissao_q
  G.pintar_finale = pintar_finale_q
  G.pintar_titulo = pintar_titulo_q
  G.quadro_depois = quadro_depois_q

  -- Pedidos registrados desde a ultima chamada (ver game.request).
  function G.take_requests()
    local out = requests
    requests = {}
    return out
  end

  -- Entra numa tela. Unico ponto que escreve game.gamestate depois da
  -- inicializacao; chamado so pelas tasks de tela do main.atm.
  function G.enter(screen)
    game.gamestate = screen
  end

  -- -warp: o jogo comeca direto num nivel, como um "novo jogo".
  function G.initial_request()
    if game.warp then
      return { tag = "jogo.novo", episode = game.episode, mapn = game.mapn, skill = game.skill }
    end
    return nil
  end

  function G.new_game(episode, mapn, skill)
    game.skill = skill
    game.episode = episode
    game.mapn = mapn
  end

  function G.set_level(episode, mapn)
    game.episode = episode
    game.mapn = mapn
  end

  function G.set_mapn(mapn)
    game.mapn = mapn
  end

  function G.start_level()
    game.build_level(game)
  end

  -- Pools de tasks de setor da instancia de nivel atual (task Nivel, passo
  -- 3). build_level as passa a specials_mod.new; nil fora de um nivel.
  function G.set_pools(pools)
    game.pools = pools
  end

  function G.load_level(data)
    return game.load_level(game, data)
  end

  function G.end_level()
    return game.end_level(game)
  end

  function G.make_intermission(nxt)
    game.make_intermission(game, nxt)
  end

  function G.make_finale(announce)
    game.make_finale(game, announce)
  end

  function G.commercial()
    return game.is_commercial()
  end

  function G.commercial_finale()
    return game.commercial_finale(game)
  end

  function G.map_exists(mapn)
    return game.map_exists(game, mapn)
  end

  function G.to_title()
    game.to_title(game)
  end

  function G.end_game()
    game.clear_game(game)
  end

  -- Resumo do estado do jogo para o teste de equivalencia entre drivers.
  function G.state_string()
    local t = {
      tostring(game.gamestate), tostring(game.leveltime), tostring(rng.index()),
      tostring(game.episode), tostring(game.mapn), tostring(game.wiping),
      tostring(menu.active), tostring(game.level_gen),
    }
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
      -- lados: texturas e deslocamento (botoes do passo 3e, linhas com
      -- scroll); acrescentado tambem a referencia (tests/ref-passo1.patch).
      -- So com DOOM_REPLAY_SIDES=1 (tests/test_drivers.sh, tools/mutacoes.py):
      -- custa caro e falsearia a medicao de custo (tools/custo_drivers.py).
      for i = 1, (os.getenv("DOOM_REPLAY_SIDES") == "1") and #world.sides or 0 do
        local sd = world.sides[i]
        t[#t + 1] = string.format("s%s,%s,%s,%s", tostring(sd.toptexture),
          tostring(sd.midtexture), tostring(sd.bottomtexture), tostring(sd.textureoffset))
      end
      -- texturas de chao e teto (passo 3d: o donut e "baixar e trocar" trocam
      -- o floorpic); tambem so com DOOM_REPLAY_SIDES=1
      for i = 1, (os.getenv("DOOM_REPLAY_SIDES") == "1") and #world.sectors or 0 do
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
    end
    local p = game.player
    if p then
      t[#t + 1] = string.format("p%s,%s,%s,%s,%s", tostring(p.health), tostring(p.armorpoints),
        tostring(p.readyweapon), tostring(p.psprite_state), tostring(p.psprite_sy))
      -- arma (passo 4a): o resto do que a task Arma escreve; tambem so com
      -- DOOM_REPLAY_SIDES=1
      if os.getenv("DOOM_REPLAY_SIDES") == "1" then
        t[#t + 1] = string.format("a%s,%s,%s,%s,%s,%s,%s,%s,%s", tostring(p.psprite_body),
          tostring(p.psprite_flash), tostring(p.flash_tics), tostring(p.psprite_tics),
          tostring(p.psprite_step), tostring(p.pendingweapon), tostring(p.attackdown),
          tostring(p.refire), tostring(p.extralight))
      end
    end
    return table.concat(t, ";")
  end
  video.state_hook = G.state_string

  function G.shutdown()
    sound_mod.shutdown(sound)
    video.shutdown()
    print("janela fechada")
  end

  return G
end

return M
