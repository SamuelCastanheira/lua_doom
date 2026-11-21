#!/usr/bin/env python3
"""Metricas do passo 7 (intermissao e finale como tasks): tag passo6 x atual.

Antes: a maquina de estados de wi_stuff.lua (ticker, update_stats,
update_show_next, update_no_state, init_show_next, init_no_state) e o
ticker de finale.lua. Depois: telas.atm mais as partes novas de Lua
(wi_stuff: tic, acelerar_tudo, mostrar_proximo, sem_estado; finale:
para_arte). O desenho e as tabelas ficam de fora dos dois lados.

Conta: linhas de codigo; campos de fase escritos (state, sp_state,
cnt_pause, cnt, stage); comparacoes com a fase.

Uso: python3 tools/metricas_passo7.py [ref]   (ref padrao: passo6)
"""
import re
import sys

sys.path.insert(0, "tools")
from metricas_passo3 import read, code_lines, lua_function, sem_comentarios  # noqa: E402

REF = sys.argv[1] if len(sys.argv) > 1 else "passo6"
FASE = ("state", "sp_state", "cnt_pause", "cnt", "stage")


def main():
    wi0, fi0 = read(REF, "wi_stuff.lua"), read(REF, "finale.lua")
    antes = "\n".join(lua_function(wi0, h) for h in (
        "local function init_show_next", "local function init_no_state",
        "local function update_stats", "local function update_show_next",
        "local function update_no_state", "function M.ticker")) + \
        lua_function(fi0, "function M.ticker")
    wi1, fi1 = read(None, "wi_stuff.lua"), read(None, "finale.lua")
    lua = "\n".join(lua_function(wi1, h) for h in (
        "function M.tic", "function M.acelerar_tudo", "function M.mostrar_proximo",
        "function M.sem_estado")) + lua_function(fi1, "function M.para_arte")
    atm = read(None, "telas.atm")
    atm = atm[:atm.rindex("[Contagem=Contagem")]
    rl, ll, al = code_lines(antes, "--"), code_lines(lua, "--"), code_lines(atm, ";;")
    print(f"referencia: tag {REF}   atual: arvore de trabalho\n")
    print(f"{'metrica':48} {'antes':>7} {'depois':>7}")
    print(f"{'linhas de codigo (Lua)':48} {rl:>7} {ll:>7}")
    print(f"{'linhas de codigo (Atmos)':48} {'-':>7} {al:>7}")
    print(f"{'linhas de codigo (total)':48} {rl:>7} {ll + al:>7}")
    def escritos(txt, pref):
        return sorted({c for c in FASE if re.search(pref + c + r" = ", sem_comentarios(txt))})
    fa = escritos(antes, r"self\.")
    fd = sorted(set(escritos(lua, r"self\.")) | {c for c in FASE if re.search(r"set [wf]\." + c + r" = ", atm)})
    print(f"{'campos de fase escritos':48} {len(fa):>7} {len(fd):>7}")
    print(f"{'':48}   antes: {', '.join(fa)}")
    print(f"{'':48}   depois: {', '.join(fd)}")
    ca = len(re.findall(r"(?:sp_state|\.state|stage) [=~]=", sem_comentarios(antes)))
    cd = len(re.findall(r"(?:sp_state|\.state|stage) [=~!]=", sem_comentarios(lua + atm)))
    print(f"{'comparacoes com a fase':48} {ca:>7} {cd:>7}")
    dec = r"[.](\w+) = [\w.]+[.]\1 - 1"
    print(f"{'contadores em campo (x.c = x.c - 1)':48} "
          f"{len(re.findall(dec, antes)):>7} {len(re.findall(dec, lua)) + len(re.findall(r'set [wf]\.\w+ = [wf]\.\w+ - 1', atm)):>7}")


if __name__ == "__main__":
    main()
