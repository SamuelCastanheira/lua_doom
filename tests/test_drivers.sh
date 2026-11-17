#!/bin/sh
# Equivalencia entre os drivers: main.lua (laco imperativo) e main.atm (Atmos).
#
# Roda os dois em modo replay (sem janela, tempo simulado, mesmas teclas) e
# compara, quadro a quadro, o hash do framebuffer e o hash do estado do jogo
# (mobjs, setores, jogador, RNG, tela atual). Qualquer diferenca de ordem ou
# de tempo entre os drivers aparece como a primeira linha divergente.
#
#   sh tests/test_drivers.sh [quadros] [semente] [exits] [args do jogo...]
#   (exits: o roteiro tambem termina niveis -> intermissao e finale)
set -e
cd "$(dirname "$0")/.."
FRAMES=${1:-4000}
SEED=${2:-1}
EXITS=${3:-}
n=0
while [ $# -gt 0 ] && [ $n -lt 3 ]; do
  shift
  n=$((n + 1))
done
OUT=build/drivers
mkdir -p "$OUT"
SCRIPT="$OUT/replay_$SEED.txt"
lua5.4 tools/make_replay.lua "$SCRIPT" "$FRAMES" "$SEED" "$EXITS" >/dev/null

DOOM_REPLAY="$SCRIPT" DOOM_REPLAY_OUT="$OUT/lua.log" \
  lua5.4 main.lua -nosound -nomusic "$@" >"$OUT/lua.out" 2>&1
DOOM_REPLAY="$SCRIPT" DOOM_REPLAY_OUT="$OUT/atm.log" \
  atmos main.atm -- -nosound -nomusic "$@" >"$OUT/atm.out" 2>&1

n=$(wc -l <"$OUT/lua.log")
if cmp -s "$OUT/lua.log" "$OUT/atm.log"; then
  states=$(cut -d' ' -f3 "$OUT/lua.log" | sort -u | wc -l)
  echo "drivers identicos: $n quadros, $states estados distintos (semente $SEED $EXITS $*)"
  grep -E "^vista|^intermissao|^finale" "$OUT/lua.out" | sort | uniq -c | sed 's/^/  /'
else
  echo "DIVERGENCIA (semente $SEED $*):"
  diff "$OUT/lua.log" "$OUT/atm.log" | head -5
  exit 1
fi
