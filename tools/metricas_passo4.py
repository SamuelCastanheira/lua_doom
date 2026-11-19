#!/usr/bin/env python3
"""Metricas do passo 4 (arma): referencia (tag passo3) x atual.

Compara so o que mudou: weapon_think (player.lua, tag passo3) contra a task
Arma (arma.atm) mais as duas funcoes novas de player.lua (arma_comeco,
arma_pode_atirar). As partes de um tic que nao mudaram (lower_weapon,
raise_weapon, start_ready, tick_ready, enter_atk_step, as tabelas) ficam de
fora dos dois lados.

Conta: linhas de codigo; campos do jogador lidos ou escritos (player.x /
p.x); comparacoes com psprite_state (o despacho por fase); decrementos de
contador.

Uso: python3 tools/metricas_passo4.py [ref]   (ref padrao: passo3)
"""
import re
import sys

sys.path.insert(0, "tools")
from metricas_passo3 import read, code_lines, lua_function, sem_comentarios  # noqa: E402

REF = sys.argv[1] if len(sys.argv) > 1 else "passo3"


def campos(text, nome):
    return set(re.findall(r"\b" + nome + r"\.(\w+)", sem_comentarios(text)))


def main():
    antes = lua_function(read(REF, "player.lua"), "local function weapon_think")
    atual_lua = "\n".join(lua_function(read(None, "player.lua"), h) for h in (
        "function M.arma_comeco", "function M.arma_pode_atirar"))
    atm = read(None, "arma.atm")
    atm = atm[:atm.rindex("[Arma=Arma]")]
    rl, ll, al = code_lines(antes, "--"), code_lines(atual_lua, "--"), code_lines(atm, ";;")
    print(f"referencia: tag {REF}   atual: arvore de trabalho\n")
    print(f"{'metrica':46} {'antes':>7} {'depois':>7}")
    print(f"{'linhas de codigo (Lua)':46} {rl:>7} {ll:>7}")
    print(f"{'linhas de codigo (Atmos)':46} {'-':>7} {al:>7}")
    print(f"{'linhas de codigo (total)':46} {rl:>7} {ll + al:>7}")
    ca = campos(antes, "player")
    cd = campos(atual_lua, "player") | campos(atm, "p")
    print(f"{'campos do jogador lidos ou escritos':46} {len(ca):>7} {len(cd):>7}")
    print(f"{'':46}   antes: {', '.join(sorted(ca))}")
    print(f"{'':46}   depois: {', '.join(sorted(cd))}")
    na = len(re.findall(r"psprite_state ==", antes))
    nd = len(re.findall(r"psprite_state ==", atual_lua)) + len(re.findall(r"\bst == ", atm)) \
        + len(re.findall(r"psprite_state [!=]=", atm))
    print(f"{'comparacoes com a fase (psprite_state, st)':46} {na:>7} {nd:>7}")
    dec = r"[.](\w+) = [\w.]+[.]\1 - 1"
    print(f"{'decrementos de contador (x.c = x.c - 1)':46} "
          f"{len(re.findall(dec, antes)):>7} {len(re.findall(dec, atual_lua + atm)):>7}")
    ret = re.compile(r"\breturn\b")
    nr = len(ret.findall(sem_comentarios(antes)))
    nd = len(ret.findall(sem_comentarios(atual_lua)))
    print(f"{'return no tic (Lua; Atmos nao tem)':46} {nr:>7} {nd:>7}")


if __name__ == "__main__":
    main()
