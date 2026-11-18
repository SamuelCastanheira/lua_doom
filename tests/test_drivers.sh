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
#   sh tests/test_drivers.sh [quadros] [semente] [exits|fluxo|luzes] [args do jogo...]
#   exits: o roteiro tambem termina niveis -> intermissao e finale
#   fluxo: roteiro fixo que passa por todas as transicoes (quadros ignorado)
#   luzes: jogador parado no E4M1 e no E1M2 (rode com -warp 4 1; passo 3a)
#
# REF_TAG=<tag> muda a referencia (padrao: passo1).
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
REF_DIR=build/ref-$REF_TAG
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
# Copia por roteiro: tools/mutacoes.py compara cada mutacao com o seu roteiro.
cp "$OUT/ref.log" "$OUT/ref_$SEED$EXITS.log"
(cd "$OUT/run_atm" && DOOM_REPLAY="$ROOT/$SCRIPT" DOOM_REPLAY_OUT="$ROOT/$OUT/atm.log" \
  atmos main.atm -- -nosound -nomusic "$@" >"$ROOT/$OUT/atm.out" 2>&1) || true
(cd "$OUT/run_lan" && DOOM_REPLAY="$ROOT/$SCRIPT" DOOM_REPLAY_OUT="$ROOT/$OUT/lan.log" \
  lua5.4 main.lua -nosound -nomusic "$@" >"$ROOT/$OUT/lan.out" 2>&1) || true

status=0
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
exit $status
