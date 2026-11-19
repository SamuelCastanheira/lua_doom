#!/usr/bin/env python3
"""Metricas do passo 6 (wipe como fase do relogio e quadro por evento):
referencia (tag passo5) x atual.

Conta, no redesenho e no relogio: linhas de codigo; leituras de
game.gamestate para escolher o que desenhar; perguntas "esta no wipe?" por
tic; telas que desenham a si mesmas.

Uso: python3 tools/metricas_passo6.py [ref]   (ref padrao: passo5)
"""
import re
import sys

sys.path.insert(0, "tools")
from metricas_passo3 import read, code_lines, sem_comentarios  # noqa: E402

REF = sys.argv[1] if len(sys.argv) > 1 else "passo5"


def bloco(text, ini, fim):
    i = text.find(ini)
    if i < 0:
        return ""
    j = text.find(fim, i)
    return text[i:j]


def main():
    g0, m0 = read(REF, "game.lua"), read(REF, "main.atm")
    g1, m1 = read(None, "game.lua"), read(None, "main.atm")
    def funcao(text, cab):
        i = text.find(cab)
        if i < 0:
            return ""
        j = text.find("\n  end\n", i)
        return text[i:j + 7]
    antes_lua = funcao(g0, "  local function paint_state()") + funcao(g0, "  local function redraw()")
    antes_atm = bloco(m0, ";; -------------------------------------------------------------- relogio",
                      ";; --------------------------------------------------------- fluxo e quadro") + \
        bloco(m0, "    loop on :frame {", "} with {\n    await :jogo.sair")
    depois_lua = "".join(funcao(g1, c) for c in (
        "  local function quadro_antes_q()", "  local function pintar_vista_q()",
        "  local function pintar_intermissao_q()", "  local function pintar_finale_q()",
        "  local function pintar_titulo_q()", "  local function quadro_depois_q(")) + \
        "  local quadro_wipe = false\n"
    depois_atm = bloco(m1, ";; -------------------------------------------------------------- relogio",
                       ";; --------------------------------------------------------- fluxo e quadro") + \
        bloco(m1, "    ;; O quadro (passo 6)", "} with {\n    await :jogo.sair") + \
        "\n".join(re.findall(r"    spawn \{[^\n]*\n        loop on :game\.frame \{[^\n]*\}\n    \}", m1))
    print(f"referencia: tag {REF}   atual: arvore de trabalho\n")
    print(f"{'metrica':50} {'antes':>7} {'depois':>7}")
    rl, ra = code_lines(antes_lua, "--"), code_lines(antes_atm, ";;")
    dl, da = code_lines(depois_lua, "--"), code_lines(depois_atm, ";;")
    print(f"{'linhas de codigo (Lua: redesenho)':50} {rl:>7} {dl:>7}")
    print(f"{'linhas de codigo (Atmos: relogio, quadro, telas)':50} {ra:>7} {da:>7}")
    print(f"{'linhas de codigo (total)':50} {rl + ra:>7} {dl + da:>7}")
    print(f"{'despacho por gamestate no desenho':50} "
          f"{len(re.findall(r'gamestate ==', sem_comentarios(antes_lua))):>7} "
          f"{len(re.findall(r'gamestate ==', sem_comentarios(depois_lua))):>7}")
    print(f"{'pergunta por tic: esta no wipe? (G.wiping)':50} "
          f"{len(re.findall(r'G\.wiping\(\)', sem_comentarios(antes_atm))):>7} "
          f"{len(re.findall(r'G\.wiping\(\)', sem_comentarios(depois_atm))):>7}")
    print(f"{'telas que desenham a si mesmas (:game.frame)':50} "
          f"{len(re.findall(r'loop on :game\.frame', m0)):>7} "
          f"{len(re.findall(r'loop on :game\.frame', m1)):>7}")


if __name__ == "__main__":
    main()
