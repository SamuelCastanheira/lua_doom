#!/usr/bin/env python3
"""Metricas do passo 9 (a familia de monstros): referencia (tag passo8) x atual.

Antes, so o Zombieman tinha task (Zumbi, passo 5); os outros monstros eram
interpretados pelo thinker Lua (mobj_thinker), que serve a todos os tipos
sem codigo por tipo: acrescentar um tipo no Lua custa so as linhas de
info.STATES. Depois, a task Zumbi virou Monstro(mo, game, C), com uma tabela
de comportamentos por tipo (ZUMBI, SOLDADO, DEMONIO; o Spectre usa a do
Demon).

Conta: linhas de codigo de monstro.atm (generico e tabelas); linhas por
tipo (o custo de acrescentar um tipo); tipos com task; linhas de STATES
cobertas por tipo; monstros com task em cada mapa dos roteiros (THINGS do
WAD, dificuldade 3, sem os de multijogador).

Uso: python3 tools/metricas_passo9.py [ref]   (ref padrao: passo8)
"""
import re
import struct
import sys

sys.path.insert(0, "tools")
from metricas_passo3 import read, code_lines, sem_comentarios  # noqa: E402

REF = sys.argv[1] if len(sys.argv) > 1 else "passo8"

# doomednum -> tipo (info.c)
EDNUM = {3004: "Zombieman", 9: "Shotgun Guy", 3002: "Demon", 58: "Spectre"}
MAPAS = [("monstro", "E1M2"), ("familia", "E1M5")]


def blocos_val(atm):
    """Os blocos 'val NOME = [ ... ]' de varias linhas (as tabelas por tipo)."""
    out = {}
    for m in re.finditer(r"^val ([A-Z]+) = \[\n(.*?)^\]\n", atm, re.M | re.S):
        out[m.group(1)] = m.group(0)
    return out


def generico(atm):
    """Do primeiro 'val func indice' ate o fim, sem a linha de exportacao."""
    i = atm.index("val func indice")
    corpo = atm[i:]
    return corpo[:corpo.rindex("\n[")]


def things(mapa):
    f = open("doom.wad", "rb").read()
    n, off = struct.unpack("<ii", f[4:12])
    cur = None
    cont = {}
    for k in range(n):
        p, s, nm = struct.unpack("<ii8s", f[off + 16 * k:off + 16 * k + 16])
        nm = nm.rstrip(b"\0").decode()
        if len(nm) == 4 and nm[0] == "E" and nm[2] == "M":
            cur = nm
        if nm == "THINGS" and cur == mapa:
            for i in range(0, s, 10):
                _, _, _, t, fl = struct.unpack("<hhhhh", f[p + i:p + i + 10])
                if t in EDNUM and fl & 2 and not fl & 16:
                    cont[EDNUM[t]] = cont.get(EDNUM[t], 0) + 1
    return cont


def main():
    ref = read(REF, "monstro.atm")
    atm = read(None, "monstro.atm")
    th_ref, th = read(REF, "thinker.lua"), read(None, "thinker.lua")
    ref_corpo = ref[:ref.rindex("\n[")]
    atm_corpo = atm[:atm.rindex("\n[")]
    gen_ref = generico(ref_corpo + "\n[")
    gen = generico(atm_corpo + "\n[")
    tabs = blocos_val(atm)
    tipos = re.findall(r"^set TIPOS@\(info\.(\w+)\)\s+= (\w+)", atm, re.M)
    faixa = atm[atm.index("val func faixa"):]
    faixa = faixa[:faixa.index("\n}\n") + 3]

    print(f"referencia: tag {REF}   atual: arvore de trabalho\n")
    print(f"{'metrica':52} {'antes':>7} {'depois':>7}")
    print(f"{'linhas de codigo de monstro.atm (total)':52} "
          f"{code_lines(ref_corpo, ';;'):>7} {code_lines(atm_corpo, ';;'):>7}")
    print(f"{'  parte generica (indice ate a task)':52} "
          f"{code_lines(gen_ref, ';;'):>7} {code_lines(gen, ';;'):>7}")
    print(f"{'  func faixa (monta as sequencias)':52} {'-':>7} {code_lines(faixa, ';;'):>7}")
    for nome, bloco in tabs.items():
        print(f"{'  tabela ' + nome:52} {'-':>7} {code_lines(bloco, ';;'):>7}")
    print(f"{'  TIPOS (tipo -> tabela)':52} {'-':>7} {len(tipos) + 1:>7}")
    print(f"{'tipos com task':52} {1:>7} {len(tipos):>7}")
    print(f"{'':52}   {', '.join(f'{t} -> {c}' for t, c in tipos)}")
    print(f"{'tabelas de comportamento':52} {1:>7} {len(tabs):>7}")
    um = code_lines(tabs.get("SOLDADO", ""), ";;") + 1
    print(f"{'linhas para acrescentar um tipo (Atmos)':52} {'-':>7} {um:>7}")
    print(f"{'':52}   uma tabela de {um - 1} linhas + 1 linha em TIPOS; o mesmo")
    print(f"{'':52}   desenho (Spectre) custa 1 linha; no Lua, 0 linhas de codigo")
    mt_ref = len(re.findall(r"MT_POSSESSED", sem_comentarios(th_ref)))
    mt = len(re.findall(r"MT_\w+", sem_comentarios(th[th.index("function M.spawn_mobj"):th.index("function M.remove_mobj")])))
    print(f"{'tipos citados em spawn_mobj (thinker.lua)':52} {mt_ref:>7} {mt:>7}")

    info = read(None, "info.lua")
    def linhas(a, b):
        return sum(1 for k in range(a, b + 1) if re.search(rf"^  \[{k}\] = ", info, re.M))
    print(f"\n{'linhas de info.STATES cobertas (usadas pelas tasks)':52}")
    print(f"{'  POSS (Zombieman)':52} {linhas(174, 206):>7} {linhas(174, 206):>7}")
    print(f"{'  SPOS (Shotgun Guy)':52} {0:>7} {linhas(207, 240):>7}")
    print(f"{'  SARG (Demon e Spectre)':52} {0:>7} {linhas(475, 501):>7}")

    print(f"\n{'monstros com task por mapa (THINGS, dificuldade 3)':52}")
    for roteiro, mapa in MAPAS:
        c = things(mapa)
        antes = c.get("Zombieman", 0)
        depois = sum(c.values())
        det = ", ".join(f"{k} {v}" for k, v in c.items())
        print(f"{'  ' + roteiro + ' (' + mapa + ')':52} {antes:>7} {depois:>7}   {det}")


if __name__ == "__main__":
    main()
