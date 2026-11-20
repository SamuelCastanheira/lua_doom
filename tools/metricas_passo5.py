#!/usr/bin/env python3
"""Metricas do passo 5 (o Zombieman como task): referencia (tag passo4) x atual.

Antes, o comportamento do Zombieman e dado: 33 linhas de info.STATES
(S_POSS_*) interpretadas por mobj_thinker e set_mobj_state (thinker.lua),
compartilhados por todos os mobjs. Depois, a task Zumbi (monstro.atm)
descompila essas linhas em comportamentos com nome e transicoes no codigo;
cada quadro ainda vem da tabela (thinker.aplicar_estado).

Conta: linhas de codigo; linhas da tabela do Zombieman (continuam usadas);
comportamentos com nome; transicoes escritas no codigo; comparacoes com o
estado (istate) para perceber saltos; campos do mobj escritos.

Uso: python3 tools/metricas_passo5.py [ref] [atual]
     (ref padrao: passo4; atual padrao: a tag passo5, porque o passo 9
     generalizou a task Zumbi em Monstro; "-" le a arvore de trabalho)
"""
import re
import sys

sys.path.insert(0, "tools")
from metricas_passo3 import read, code_lines, lua_function, sem_comentarios  # noqa: E402

REF = sys.argv[1] if len(sys.argv) > 1 else "passo4"
ATUAL = sys.argv[2] if len(sys.argv) > 2 else "passo5"
ATUAL = None if ATUAL == "-" else ATUAL


def main():
    th_ref = read(REF, "thinker.lua")
    antes = "\n".join(lua_function(th_ref, h) for h in (
        "function M.mobj_thinker", "function M.set_mobj_state", "function M.tick"))
    th = read(ATUAL, "thinker.lua")
    lua = "\n".join(lua_function(th, h) for h in (
        "function M.mobj_mover", "function M.aplicar_estado", "function M.mobj_thinker",
        "function M.mobj_parado", "function M.set_mobj_state", "function M.pensantes",
        "function M.tick"))
    atm = read(ATUAL, "monstro.atm")
    atm = atm[:atm.rindex("[Zumbi=Zumbi]")]
    main_atm = read(ATUAL, "main.atm")
    i = main_atm.index("func mobjs ()")
    laco = main_atm[i:main_atm.index("\n}\n", i) + 3]
    info = read(ATUAL, "info.lua")
    linhas_tab = len(re.findall(r"^  \[(1(7[4-9]|[89]\d)|20[0-6])\] = ", info, re.M))
    rl = code_lines(antes, "--")
    ll, al = code_lines(lua, "--"), code_lines(atm, ";;") + code_lines(laco, ";;")
    print(f"referencia: tag {REF}   atual: {ATUAL or 'arvore de trabalho'}\n")
    print(f"{'metrica':50} {'antes':>7} {'depois':>7}")
    print(f"{'linhas de codigo (Lua: interpretador e laco)':50} {rl:>7} {ll:>7}")
    print(f"{'linhas de codigo (Atmos: Zumbi e laco do Nivel)':50} {'-':>7} {al:>7}")
    print(f"{'linhas de codigo (total)':50} {rl:>7} {ll + al:>7}")
    print(f"{'linhas da tabela STATES do Zombieman (usadas)':50} {linhas_tab:>7} {linhas_tab:>7}")
    comps = re.findall(r"^val ([A-Z]+)\s+= \[", atm, re.M)
    print(f"{'comportamentos com nome':50} {0:>7} {len(comps):>7}")
    print(f"{'':50}   {', '.join(comps)}")
    corpo = sem_comentarios(atm).split("val task Zumbi")[1]
    rep = len(re.findall(r"vencido, true\)", corpo))
    volta = len(re.findall(r"vencido, false\)", corpo)) - 2   # menos morrer e explodir (sem fim)
    print(f"{'transicoes no codigo (repete; volta a correr)':50} {0:>7} {rep + volta:>7}")
    print(f"{'':50}   {rep} repetem (procurar, correr); {volta} voltam a correr (atacar, dor, levantar)")
    print(f"{'comparacoes com istate (perceber saltos)':50} "
          f"{len(re.findall(r'istate [!=]=', sem_comentarios(antes))):>7} "
          f"{len(re.findall(r'istate [!=]=', sem_comentarios(atm))):>7}")
    ca = set(re.findall(r"\bmo\.(\w+) =", sem_comentarios(antes)))
    cd = set(re.findall(r"\bmo\.(\w+) =", sem_comentarios(lua))) | \
        set(re.findall(r"set mo\.(\w+) =", sem_comentarios(atm)))
    print(f"{'campos do mobj escritos':50} {len(ca):>7} {len(cd):>7}")
    print(f"{'':50}   antes: {', '.join(sorted(ca))}")
    print(f"{'':50}   depois: {', '.join(sorted(cd))}")


if __name__ == "__main__":
    main()
