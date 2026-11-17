# lua_doom - build dos modulos nativos (Lua 5.4 C API).
#
# Linux, macOS, BSD e Windows (MSYS2 UCRT64/MINGW64).
#
#   make              compila todos os modulos em modo release
#   make debug        -O0 -g com AddressSanitizer/UBSan (Linux/macOS)
#   make run          compila e roda: $(LUA) main.lua $(ARGS)
#   make run-atmos    idem pelo driver Atmos: atmos main.atm -- $(ARGS)
#   make test-drivers prova que main.lua e main.atm dao o mesmo jogo
#   make test         roda os testes em tests/
#   make clean        remove binarios e objetos
#   make help         mostra as variaveis detectadas
#
# Variaveis uteis: LUA=lua5.4  ARGS="-fps -scale 4"  CC=clang  LUA_PC=lua54

# ---------------------------------------------------------------- plataforma
ifeq ($(OS),Windows_NT)
  PLATFORM := windows
else
  UNAME_S := $(shell uname -s)
  ifeq ($(UNAME_S),Darwin)
    PLATFORM := macos
  else
    PLATFORM := unix
  endif
endif

CC         ?= cc
PKG_CONFIG ?= pkg-config
LUA        ?= lua5.4
ARGS       ?= -fps -scale 4
MODE       ?= release

# --------------------------------------------------------------------- Lua
# O nome do pacote pkg-config muda entre distros: lua5.4 (Debian/Ubuntu),
# lua54 (FreeBSD), lua-5.4, lua (Arch, Fedora, MSYS2, Homebrew).
LUA_PC_CANDIDATES := $(LUA_PC) lua5.4 lua-5.4 lua54 lua
LUA_PC_FOUND := $(firstword $(foreach p,$(LUA_PC_CANDIDATES),\
  $(shell $(PKG_CONFIG) --exists $(p) 2>/dev/null && echo $(p))))

ifneq ($(LUA_PC_FOUND),)
  LUA_CFLAGS ?= $(shell $(PKG_CONFIG) --cflags $(LUA_PC_FOUND))
  LUA_LIBS   ?= $(shell $(PKG_CONFIG) --libs $(LUA_PC_FOUND))
else
  LUA_CFLAGS ?= -I/usr/include/lua5.4 -I/usr/local/include/lua5.4
  LUA_LIBS   ?= -llua5.4
endif

# ------------------------------------------------------------------- SDL2
SDL_CFLAGS ?= $(shell $(PKG_CONFIG) --cflags sdl2 SDL2_mixer 2>/dev/null)
SDL_LIBS   ?= $(shell $(PKG_CONFIG) --libs sdl2 SDL2_mixer 2>/dev/null)
ifeq ($(strip $(SDL_LIBS)),)
  SDL_CFLAGS := $(shell sdl2-config --cflags 2>/dev/null)
  SDL_LIBS   := $(shell sdl2-config --libs 2>/dev/null) -lSDL2_mixer
endif

# ------------------------------------------------- flags por plataforma
# Linux/BSD: o interpretador ja exporta os simbolos da API Lua, entao o
# modulo nao linka liblua (evita duas copias da VM no mesmo processo).
# macOS: mesma ideia com -undefined dynamic_lookup.
# Windows: DLL precisa linkar lua54.dll explicitamente.
ifeq ($(PLATFORM),windows)
  EXT        := dll
  SHARED     := -shared -static-libgcc
  MOD_LIBS   := $(LUA_LIBS)
  PIC        :=
  SDL_LIBS   := $(filter-out -mwindows -lSDL2main,$(SDL_LIBS)) -lwinmm
  SANITIZE   :=
else ifeq ($(PLATFORM),macos)
  EXT        := so
  SHARED     := -bundle -undefined dynamic_lookup
  MOD_LIBS   :=
  PIC        := -fPIC
  SANITIZE   := -fsanitize=address,undefined
else
  EXT        := so
  SHARED     := -shared
  MOD_LIBS   :=
  PIC        := -fPIC
  SANITIZE   := -fsanitize=address,undefined
endif

WARN := -Wall -Wextra -Wno-unused-parameter
ifeq ($(MODE),debug)
  OPT := -O0 -g3 $(SANITIZE) -fno-omit-frame-pointer
else
  OPT := -O2 -DNDEBUG
endif

# -fwrapv: overflow de inteiro com sinal vira wrap de 32 bits, como no Doom
# original. Sem isso o compilador pode "otimizar" contas de ponto fixo.
CFLAGS_ALL = -std=c99 $(OPT) $(WARN) $(PIC) -fwrapv -fno-strict-aliasing \
             -Isrc $(LUA_CFLAGS) $(CFLAGS) $(CPPFLAGS)
LDFLAGS_ALL = $(SHARED) $(OPT) $(LDFLAGS)

BUILD := build/$(PLATFORM)-$(MODE)

# ------------------------------------------------------------ modulos
# Cada modulo: <nome>_SRC = fontes, <nome>_LIBS = libs extras.
MODULES := tables_c framebuffer_c r_data_c render_c video_c test_fixed_c

tables_c_SRC      := src/tables_c.c
framebuffer_c_SRC := src/framebuffer_c.c src/v_draw.c
framebuffer_c_LIBS := -lm
r_data_c_SRC      := src/r_data_c.c
render_c_SRC      := $(wildcard src/render/*.c)
render_c_CFLAGS   := -Isrc/render
video_c_SRC       := src/video_c.c
video_c_CFLAGS    := $(SDL_CFLAGS)
video_c_LIBS      := $(SDL_LIBS)
test_fixed_c_SRC  := tests/test_fixed_c.c src/fixed_c.c

tables_c_LIBS := -lm

TARGETS := $(addsuffix .$(EXT),$(MODULES))

# Os .so ficam na raiz para qualquer modo; o stamp muda quando o modo muda,
# forcando o relink ao alternar entre debug e release.
MODE_STAMP := build/.mode-stamp
$(shell mkdir -p build; [ "$$(cat $(MODE_STAMP) 2>/dev/null)" = "$(PLATFORM)-$(MODE)" ] || echo "$(PLATFORM)-$(MODE)" > $(MODE_STAMP))

.PHONY: all debug release run run-atmos test-drivers test compare baseline check-baseline clean distclean help
.DEFAULT_GOAL := all

all: $(TARGETS)

release:
	$(MAKE) MODE=release all

debug:
	$(MAKE) MODE=debug all

define MODULE_RULES
$(1)_OBJ := $$(patsubst %.c,$(BUILD)/%.o,$$($(1)_SRC))

$(1).$(EXT): $$($(1)_OBJ) $(MODE_STAMP)
	$$(CC) $$(filter %.o,$$^) -o $$@ $$(LDFLAGS_ALL) $$($(1)_LIBS) $$(MOD_LIBS)

$$($(1)_OBJ): EXTRA_CFLAGS := $$($(1)_CFLAGS)
endef
$(foreach m,$(MODULES),$(eval $(call MODULE_RULES,$(m))))

$(BUILD)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS_ALL) $(EXTRA_CFLAGS) -MMD -MP -c $< -o $@

-include $(shell find build -name '*.d' 2>/dev/null)

# ------------------------------------------------------------- tarefas
# Em modo debug o ASan precisa ser carregado antes do interpretador.
ifeq ($(MODE),debug)
  ifeq ($(PLATFORM),unix)
    ASAN_PRELOAD := LD_PRELOAD="$$($(CC) -print-file-name=libasan.so)" ASAN_OPTIONS=detect_leaks=0
  endif
endif

run: all
	$(ASAN_PRELOAD) $(LUA) main.lua $(ARGS)

# Mesmo jogo pelo driver com concorrencia estruturada (main.atm).
ATMOS ?= atmos
run-atmos: all
	$(ASAN_PRELOAD) $(ATMOS) main.atm -- $(ARGS)

# Equivalencia main.lua x main.atm em modo replay (sem janela).
test-drivers: all
	@sh tests/test_drivers.sh 4000 1
	@sh tests/test_drivers.sh 6000 2 exits
	@sh tests/test_drivers.sh 6000 5 exits

TESTS ?= $(wildcard tests/test_*.lua)
test: all
	@fail=0; for t in $(TESTS); do \
	  printf '%-36s ' "$$t"; \
	  if $(LUA) "$$t" > "$(BUILD)/$$(basename $$t).log" 2>&1; then echo ok; \
	  else echo FALHOU "($(BUILD)/$$(basename $$t).log)"; fail=1; fi; \
	done; exit $$fail

# Compara o renderer atual com o renderer Lua puro (commit REF_COMMIT),
# pixel a pixel. PNGs lado a lado ficam em build/compare/png.
#   make compare MAP=3 EP=1        make compare SPRITES=sprites
#   make compare SPRITES=full BLOCKS=10 DETAIL=1
REF_COMMIT ?= 522b06f
REF_DIR    ?= build/ref-worktree
EP  ?= 1
MAP ?= 1
SPRITES ?=
BLOCKS ?= 11
DETAIL ?= 0
CMP := build/compare/e$(EP)m$(MAP)$(SPRITES)-b$(BLOCKS)d$(DETAIL)
compare: all
	@test -d $(REF_DIR) || git worktree add $(REF_DIR) $(REF_COMMIT)
	@test -e $(REF_DIR)/doom.wad || ln -sf "$(CURDIR)"/*.wad $(REF_DIR)/ 2>/dev/null || true
	@mkdir -p $(CMP)/ref $(CMP)/cur
	cd $(REF_DIR) && $(LUA) "$(CURDIR)/tools/dump_frames.lua" "$(CURDIR)/$(CMP)/ref" $(EP) $(MAP) "$(SPRITES)" $(BLOCKS) $(DETAIL)
	$(LUA) tools/dump_frames.lua $(CMP)/cur $(EP) $(MAP) "$(SPRITES)" $(BLOCKS) $(DETAIL)
	python3 tools/compare_frames.py $(CMP)/ref $(CMP)/cur $(CMP)/png

# Referencia congelada do renderer C (com tags por pixel), para validar
# mudancas visuais intencionais:
#   make baseline          congela os quadros atuais
#   make check-baseline    mostra, por tipo de superficie, o que mudou
BASELINE_CFGS ?= 1:1:11:0 1:3:10:0 1:4:11:1 2:2:11:0 3:3:11:0 4:1:11:0
baseline: all
	@for c in $(BASELINE_CFGS); do set -- $$(echo $$c | tr ':' ' '); \
	  d=build/baseline/e$$1m$$2-b$$3d$$4; mkdir -p $$d; \
	  $(LUA) tools/dump_frames.lua $$d $$1 $$2 full $$3 $$4 >/dev/null || exit 1; \
	  echo "baseline $$d"; done
check-baseline: all
	@for c in $(BASELINE_CFGS); do set -- $$(echo $$c | tr ':' ' '); \
	  n=e$$1m$$2-b$$3d$$4; mkdir -p build/check/$$n; \
	  $(LUA) tools/dump_frames.lua build/check/$$n $$1 $$2 full $$3 $$4 >/dev/null || exit 1; \
	  printf '%-16s ' $$n; python3 tools/diff_by_tag.py build/baseline/$$n build/check/$$n; done

clean:
	rm -rf build/$(PLATFORM)-* build/compare build/check
	rm -f $(addsuffix .so,$(MODULES)) $(addsuffix .dll,$(MODULES))

distclean: clean
	rm -f fixed_test.so src/*.so ./.\\doommus_*.mid

help:
	@echo "PLATFORM     = $(PLATFORM)"
	@echo "MODE         = $(MODE)"
	@echo "CC           = $(CC)"
	@echo "LUA          = $(LUA)"
	@echo "LUA_PC       = $(LUA_PC_FOUND)"
	@echo "LUA_CFLAGS   = $(LUA_CFLAGS)"
	@echo "LUA_LIBS     = $(MOD_LIBS)"
	@echo "SDL_CFLAGS   = $(SDL_CFLAGS)"
	@echo "SDL_LIBS     = $(SDL_LIBS)"
	@echo "TARGETS      = $(TARGETS)"
