#!/bin/sh
# Equivalencia entre a versao imperativa de referencia e a versao Atmos.
#
# Referencia: main.lua da tag passo1 (laco imperativo; as transicoes de tela
# ainda em Lua), rodado num worktree em build/ref-passo1, com o patch de
# teste tests/ref-passo1.patch (comando "die" do replay). Na tag passo1 essa
# referencia foi comparada com a branch "lua" original (framebuffer identico).
#
# Candidatos (codigo atual):
#   atm  atmos main.atm -- ...
#   lan  lua5.4 main.lua ...   (lancador do main.atm)
#
# Os tres rodam em modo replay (sem janela, tempo simulado, mesmas teclas).
# Compara, quadro a quadro, o hash do framebuffer e o hash do estado do jogo
# (mobjs, setores, jogador, RNG, tela atual). A primeira linha divergente
# aponta o quadro em que a ordem ou o tempo mudou.
#
#   sh tests/test_drivers.sh [quadros] [semente] [exits|fluxo|luzes|botoes|portas|elevadores|pisos|arma|monstro] [args do jogo...]
#   exits: o roteiro tambem termina niveis -> intermissao e finale
#   fluxo: roteiro fixo que passa por todas as transicoes (quadros ignorado)
#   luzes: jogador parado no E4M1 e no E1M2 (rode com -warp 4 1; passo 3a)
#   botoes: switches repetiveis, save e load (rode com -warp 1 1; passo 3e)
#   portas: portas em cada fase, save e load (rode com -warp 1 1; passo 3b)
#   elevadores: elevadores em cada fase, parados, save e load (rode com -warp 1 3; passo 3c)
#   pisos: pisos, escadas, donut e esmagadores, save e load (rode com -warp 2 2; passo 3d)
#   arma: cada arma atirando, trocas, sem municao, save e load, morte (rode com -warp 1 1; passo 4a)
#   monstro: zumbis procurando, correndo, atirando, morrendo, save e load, -respawn (rode com -warp 1 2 -respawn; passo 5)
#
# REF_TAG=<tag> muda a referencia (padrao: passo1); REF_DIR=<pasta> aponta
# para uma pasta pronta (por exemplo, a branch lua: build/branch-lua).
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
FRAMES=${1:-4000}
SEED=${2:-1}
EXITS=${3:-}
n=0
while [ $# -gt 0 ] && [ $n -lt 3 ]; do
  shift
  n=$((n + 1))
done
REF_TAG=${REF_TAG:-passo1}
# O hash de estado tambem cobre os lados (texturas e deslocamento) so com
# esta variavel; tools/custo_drivers.py roda sem ela.
export DOOM_REPLAY_SIDES=1
# REF_DIR=<pasta> usa uma pasta ja pronta como referencia (por exemplo, o
# worktree da branch lua: REF_TAG=lua REF_DIR=build/branch-lua).
REF_DIR=${REF_DIR:-build/ref-$REF_TAG}
OUT=build/drivers
mkdir -p "$OUT"

if [ ! -d "$REF_DIR" ]; then
  git worktree add --detach "$REF_DIR" "$REF_TAG" >/dev/null 2>&1
fi
# A referencia recebe so instrumentacao de teste (comandos do modo replay
# que nao existiam quando a tag foi criada). Ver tests/ref-<tag>.patch.
PATCH="$ROOT/tests/ref-$REF_TAG.patch"
if [ -f "$PATCH" ] && git -C "$REF_DIR" apply --check "$PATCH" 2>/dev/null; then
  git -C "$REF_DIR" apply "$PATCH"
fi
for wadf in "$ROOT"/*.wad; do
  [ -e "$REF_DIR/$(basename "$wadf")" ] || ln -sf "$wadf" "$REF_DIR/"
done
(cd "$REF_DIR" && make -s >/dev/null)

SCRIPT="$OUT/replay_$SEED$EXITS.txt"
lua5.4 tools/make_replay.lua "$SCRIPT" "$FRAMES" "$SEED" "$EXITS" >/dev/null

# Cada execucao roda numa pasta propria (links para o codigo, sem saves):
# o jogo salva na pasta do IWAD, entao saves de teste nunca tocam os
# arquivos do usuario e toda execucao comeca sem saves.
mkrun() {
  rm -rf "$2"
  mkdir -p "$2"
  for f in "$1"/*.lua "$1"/*.so "$1"/*.dll "$1"/*.atm "$1"/*.wad; do
    [ -e "$f" ] && ln -s "$f" "$2/"
  done
  [ -d "$1/atmos" ] && ln -s "$1/atmos" "$2/atmos"
  return 0
}
mkrun "$ROOT/$REF_DIR" "$ROOT/$OUT/run_ref"
mkrun "$ROOT" "$ROOT/$OUT/run_atm"
mkrun "$ROOT" "$ROOT/$OUT/run_lan"

if ! (cd "$OUT/run_ref" && DOOM_REPLAY="$ROOT/$SCRIPT" DOOM_REPLAY_OUT="$ROOT/$OUT/ref.log" \
  lua5.4 main.lua -nosound -nomusic "$@" >"$ROOT/$OUT/ref.out" 2>&1); then
  echo "ERRO na referencia $REF_TAG:"; tail -5 "$OUT/ref.out"; exit 1
fi
# Copia por roteiro: tools/mutacoes.py compara cada mutacao com o seu roteiro
# (o log e os saves gravados pela referencia).
cp "$OUT/ref.log" "$OUT/ref_$SEED$EXITS.log"
rm -rf "$OUT/saves_$SEED$EXITS"
mkdir -p "$OUT/saves_$SEED$EXITS"
for f in "$OUT"/run_ref/doomsav*.dsg; do
  [ -e "$f" ] && cp "$f" "$OUT/saves_$SEED$EXITS/"
done
(cd "$OUT/run_atm" && DOOM_REPLAY="$ROOT/$SCRIPT" DOOM_REPLAY_OUT="$ROOT/$OUT/atm.log" \
  atmos main.atm -- -nosound -nomusic "$@" >"$ROOT/$OUT/atm.out" 2>&1) || true
(cd "$OUT/run_lan" && DOOM_REPLAY="$ROOT/$SCRIPT" DOOM_REPLAY_OUT="$ROOT/$OUT/lan.log" \
  lua5.4 main.lua -nosound -nomusic "$@" >"$ROOT/$OUT/lan.out" 2>&1) || true

status=0
# Saves sao parte do resultado: os arquivos gravados pelas duas versoes tem
# de ser identicos byte a byte (o formato nao mudou na migracao).
for f in "$OUT"/run_ref/doomsav*.dsg; do
  [ -e "$f" ] || continue
  if ! cmp -s "$f" "$OUT/run_atm/$(basename "$f")"; then
    echo "DIVERGENCIA no save $(basename "$f") (referencia x atmos)"
    status=1
  fi
done
for cand in atm lan; do
  if ! cmp -s "$OUT/ref.log" "$OUT/$cand.log"; then
    echo "DIVERGENCIA $cand x $REF_TAG (semente $SEED $EXITS $*):"
    diff "$OUT/ref.log" "$OUT/$cand.log" | head -5
    tail -3 "$OUT/$cand.out"
    status=1
  fi
done
if [ $status -eq 0 ]; then
  nq=$(wc -l <"$OUT/ref.log")
  states=$(cut -d' ' -f3 "$OUT/ref.log" | sort -u | wc -l)
  echo "identico a $REF_TAG: $nq quadros, $states estados distintos (semente $SEED $EXITS $*)"
  echo "  telas (referencia, em ordem):"
  grep -E "^vista|^intermissao|^finale" "$OUT/ref.out" | awk '{print $1, $2}' | tr '\n' ',' | sed 's/,$//; s/,/ > /g; s/^/    /'
  echo
  if grep -q "^pedido" "$OUT/atm.out"; then
    echo "  pedidos emitidos (atmos):"
    grep "^pedido" "$OUT/atm.out" | awk '{print $2}' | sort | uniq -c | sed 's/^/   /'
  fi
fi
# No roteiro "fluxo", cada transicao precisa ter acontecido de verdade.
if [ "$EXITS" = "fluxo" ] && [ $status -eq 0 ]; then
  need() {
    got=$(grep -c "$2" "$OUT/$1" || true)
    if [ "$got" -lt "$3" ]; then
      echo "COBERTURA INCOMPLETA: '$2' apareceu $got vez(es), esperado >= $3"
      status=1
    fi
  }
  need atm.out "^pedido jogo.novo" 3
  need atm.out "^pedido jogo.carregar" 2
  need atm.out "^pedido jogo.fim" 1
  need atm.out "^pedido nivel.trocar" 1
  need atm.out "^pedido jogo.sair" 1
  need ref.out "^intermissao E1M2" 1
  need ref.out "^intermissao E1M9" 1
  need ref.out "^intermissao E1M4" 1
  need ref.out "^finale" 1
  need ref.out "^vista E1M4" 3
  [ $status -eq 0 ] && echo "  cobertura do fluxo: completa"
fi
# No roteiro "luzes" (passo 3a), os dois mapas com todos os tipos de luz.
if [ "$EXITS" = "luzes" ] && [ $status -eq 0 ]; then
  for m in E4M1 E1M2; do
    if ! grep -q "^vista $m" "$OUT/ref.out"; then
      echo "COBERTURA INCOMPLETA: o roteiro de luzes nao chegou ao $m (rode com -warp 4 1)"
      status=1
    fi
  done
  [ $status -eq 0 ] && echo "  cobertura das luzes: E4M1 (fogo, flash) e E1M2 (glow, flash, strobes)"
fi
# No roteiro "botoes" (passo 3e): o save tem de ter gravado um botao ativo,
# e o jogo tem de ter carregado esse save e chegado ao E1M4.
if [ "$EXITS" = "botoes" ] && [ $status -eq 0 ]; then
  for run in run_ref run_atm; do
    if ! grep -aq '"buttons":\[{' "$OUT/$run/doomsav5.dsg" 2>/dev/null; then
      echo "COBERTURA INCOMPLETA: $run nao gravou um botao ativo no save (slot 5)"
      status=1
    fi
  done
  grep -q "^pedido jogo.carregar" "$OUT/atm.out" || { echo "COBERTURA INCOMPLETA: sem load"; status=1; }
  grep -q "^vista E1M4" "$OUT/ref.out" || { echo "COBERTURA INCOMPLETA: nao chegou ao E1M4"; status=1; }
  [ $status -eq 0 ] && echo "  cobertura dos botoes: save com botao ativo, load, E1M1 e E1M4"
fi
# No roteiro "portas" (passo 3b): um save em cada fase da porta (slot 5
# abrindo, 4 esperando, 3 fechando), tres loads, E1M6 (30 s) e E1M2.
if [ "$EXITS" = "portas" ] && [ $status -eq 0 ]; then
  fase() {
    got=$(grep -ao '"kind":"door"[^}]*' "$OUT/run_atm/doomsav$1.dsg" 2>/dev/null | grep -c "\"direction\":$2,")
    if [ "$got" -lt 1 ]; then
      echo "COBERTURA INCOMPLETA: o slot $1 nao tem porta com direction $2"
      status=1
    fi
  }
  fase 5 1; fase 4 0; fase 3 -1
  n=$(grep -c "^pedido jogo.carregar" "$OUT/atm.out" || true)
  [ "$n" -ge 3 ] || { echo "COBERTURA INCOMPLETA: $n loads (esperado 3)"; status=1; }
  for m in E1M6 E1M2; do
    grep -q "^vista $m" "$OUT/ref.out" || { echo "COBERTURA INCOMPLETA: nao chegou ao $m"; status=1; }
  done
  [ $status -eq 0 ] && echo "  cobertura das portas: save e load abrindo, esperando e fechando; E1M6 (30 s); E1M2"
fi
# No roteiro "elevadores" (passo 3c): um save em cada fase do elevador
# (slot 5 descendo, 4 esperando, 3 subindo), um com elevadores parados
# (slot 2: esperando, count enorme), quatro loads, E1M3 e E2M3.
if [ "$EXITS" = "elevadores" ] && [ $status -eq 0 ]; then
  fase_p() {
    got=$(grep -ao '"kind":"plat"[^}]*' "$OUT/run_atm/doomsav$1.dsg" 2>/dev/null | grep -c "\"status\":$2,")
    if [ "$got" -lt 1 ]; then
      echo "COBERTURA INCOMPLETA: o slot $1 nao tem elevador com status $2"
      status=1
    fi
  }
  fase_p 5 0; fase_p 4 2; fase_p 3 1
  grep -aq '"count":21474' "$OUT/run_atm/doomsav2.dsg" 2>/dev/null || { echo "COBERTURA INCOMPLETA: o slot 2 nao tem elevador parado"; status=1; }
  n=$(grep -c "^pedido jogo.carregar" "$OUT/atm.out" || true)
  [ "$n" -ge 4 ] || { echo "COBERTURA INCOMPLETA: $n loads (esperado 4)"; status=1; }
  grep -q "^vista E2M3" "$OUT/ref.out" || { echo "COBERTURA INCOMPLETA: nao chegou ao E2M3"; status=1; }
  [ $status -eq 0 ] && echo "  cobertura dos elevadores: save e load descendo, esperando, subindo e parado; E1M3; E2M3"
fi
# No roteiro "pisos" (passo 3d): um save com pisos andando para cima e para
# baixo (slot 5), um load, e os mapas dos esmagadores (E2M2, E2M4, E3M5) e
# do "baixar e trocar" (E2M1). O esmagamento do jogador foi conferido com
# prints (registro do passo 3, secao 3d).
if [ "$EXITS" = "pisos" ] && [ $status -eq 0 ]; then
  for d in 1 -1; do
    got=$(grep -ao '"kind":"floor"[^}]*' "$OUT/run_atm/doomsav5.dsg" 2>/dev/null | grep -c "\"direction\":$d,")
    [ "$got" -ge 1 ] || { echo "COBERTURA INCOMPLETA: o slot 5 nao tem piso com direction $d"; status=1; }
  done
  n=$(grep -c "^pedido jogo.carregar" "$OUT/atm.out" || true)
  [ "$n" -ge 1 ] || { echo "COBERTURA INCOMPLETA: $n loads (esperado 1)"; status=1; }
  for m in E2M4 E2M1 E3M5; do
    grep -q "^vista $m" "$OUT/ref.out" || { echo "COBERTURA INCOMPLETA: nao chegou ao $m"; status=1; }
  done
  [ $status -eq 0 ] && echo "  cobertura dos pisos: save e load com pisos subindo e descendo; E2M2, E2M4, E2M1, E3M5"
fi
# No roteiro "arma" (passo 4a): save no meio do tiro do BFG (slot 5 com
# psprite_state "atk" e readyweapon 6) e um load. As trocas, a falta de
# municao e a morte atirando foram conferidas com prints (registro do passo
# 4, secao 4a).
if [ "$EXITS" = "arma" ] && [ $status -eq 0 ]; then
  grep -aq '"psprite_state":"atk"' "$OUT/run_atm/doomsav5.dsg" 2>/dev/null || { echo "COBERTURA INCOMPLETA: o slot 5 nao tem a arma atirando"; status=1; }
  grep -aq '"readyweapon":6' "$OUT/run_atm/doomsav5.dsg" 2>/dev/null || { echo "COBERTURA INCOMPLETA: o slot 5 nao tem o BFG"; status=1; }
  n=$(grep -c "^pedido jogo.carregar" "$OUT/atm.out" || true)
  [ "$n" -ge 1 ] || { echo "COBERTURA INCOMPLETA: $n loads (esperado 1)"; status=1; }
  v=$(grep -c "^vista E1M1" "$OUT/ref.out" || true)
  [ "$v" -ge 3 ] || { echo "COBERTURA INCOMPLETA: o jogador nao renasceu ($v vistas do E1M1, esperado 3)"; status=1; }
  [ $status -eq 0 ] && echo "  cobertura da arma: save e load no meio do tiro do BFG; morte e renascimento"
fi
# No roteiro "monstro" (passo 5): save e load no meio da briga e o E1M2.
# Os comportamentos percorridos (procurar, correr, atacar, dor, morrer,
# explodir, pesadelo) foram conferidos com prints (registro do passo 5).
if [ "$EXITS" = "monstro" ] && [ $status -eq 0 ]; then
  [ -e "$OUT/run_atm/doomsav5.dsg" ] || { echo "COBERTURA INCOMPLETA: sem o save do slot 5"; status=1; }
  n=$(grep -c "^pedido jogo.carregar" "$OUT/atm.out" || true)
  [ "$n" -ge 1 ] || { echo "COBERTURA INCOMPLETA: $n loads (esperado 1)"; status=1; }
  [ $status -eq 0 ] && echo "  cobertura do monstro: save e load no meio da briga; E1M2 com -respawn"
fi
exit $status
