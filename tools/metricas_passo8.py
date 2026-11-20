#!/usr/bin/env python3
"""Metricas do passo 8 (barra de status, menu, automapa): tag passo7 x atual.

Para cada subpasso, compara o codigo Lua que fazia o tic (antes) com a task
nova mais as partes de Lua que ela chama (depois), e conta os campos de
estado escritos por tic que viraram variaveis da task.

Uso: python3 tools/metricas_passo8.py [ref]   (ref padrao: passo7)
"""
import re
import sys

sys.path.insert(0, "tools")
from metricas_passo3 import read, code_lines, lua_function, sem_comentarios  # noqa: E402

REF = sys.argv[1] if len(sys.argv) > 1 else "passo7"

# (nome, arquivo Lua, funcoes antes, funcoes Lua depois, arquivo atm, campos de fase)
SUBPASSOS = [
    ("8b barra (rosto)", "status.lua",
     ("local function update_face", "function M.ticker"),
     ("function M.sortear", "function M.olhar", "function M.arma_nova",
      "function M.rosto_dano", "function M.deus"),
     "barra.atm",
     ("face_count", "face_priority", "last_attackdown", "old_health", "face_index")),
    ("8c menu", "menu.lua",
     ("function M.ticker",),
     (),
     "interface.atm",
     ("skull_tics", "which_skull")),
    ("8d automapa", "am_map.lua",
     ("function M.ticker",),
     ("function M.passo",),
     "interface.atm",
     ("amclock", "m_x", "m_y", "scale_mtof")),
]


def bloco_atm(path):
    txt = read(None, path)
    i = txt.rfind("\n[")
    return txt[:i] if i > 0 else txt


def main():
    print(f"referencia: tag {REF}   atual: arvore de trabalho\n")
    for nome, lua, fa, fd, atm, campos in SUBPASSOS:
        antes = "\n".join(lua_function(read(REF, lua), h) for h in fa)
        dl = "\n".join(lua_function(read(None, lua), h) for h in fd)
        da = bloco_atm(atm)
        if nome.startswith("8c") or nome.startswith("8d"):
            da = da[da.index("val task Menu" if nome.startswith("8c") else "val task Automapa"):]
            da = da[:da.index("\n}\n") + 3]
        rl, ll, al = code_lines(antes, "--"), code_lines(dl, "--"), code_lines(da, ";;")
        print(f"== {nome}")
        print(f"{'metrica':48} {'antes':>7} {'depois':>7}")
        print(f"{'linhas de codigo (Lua)':48} {rl:>7} {ll:>7}")
        print(f"{'linhas de codigo (Atmos)':48} {'-':>7} {al:>7}")
        print(f"{'linhas de codigo (total)':48} {rl:>7} {ll + al:>7}")
        ca = sorted(c for c in campos if re.search(r"self\." + c + r" = ", sem_comentarios(antes)))
        cd = sorted(c for c in campos if re.search(r"self\." + c + r" = ", sem_comentarios(dl))
                    or re.search(r"set \w+\." + c + r" = ", da))
        print(f"{'campos de estado escritos por tic':48} {len(ca):>7} {len(cd):>7}")
        print(f"{'':48}   antes: {', '.join(ca)}")
        print(f"{'':48}   depois: {', '.join(cd)}")
        print()


if __name__ == "__main__":
    main()
