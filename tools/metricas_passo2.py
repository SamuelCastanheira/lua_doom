#!/usr/bin/env python3
"""Metricas do passo 2 (fluxo de telas): referencia (tag passo1) x atual.

Conta, nas duas versoes:
  * escritas de game.gamestate (quem troca de tela);
  * pontos que iniciam um nivel (chamadas a start_level);
  * funcoes Lua que decidem a proxima tela;
  * linhas de codigo do fluxo (sem comentarios e linhas vazias).

Uso: python3 tools/metricas_passo2.py [ref] [atual]
     ref padrao: passo1; atual padrao: arvore de trabalho
"""
import re
import subprocess
import sys

REF = sys.argv[1] if len(sys.argv) > 1 else "passo1"
CUR = sys.argv[2] if len(sys.argv) > 2 else None   # None = arquivos do disco

FILES = ["game.lua", "menu.lua", "cheats.lua", "saveg.lua", "main.lua", "main.atm"]


def read(ref, path):
    # o arquivo pelo nome: na raiz (as tags antigas) ou em jogo/, render/ e
    # ponte/ (desde a organizacao em pastas)
    caminhos = [path] + [p + "/" + path for p in ("jogo", "render", "ponte")]
    for c in caminhos:
        if ref is None:
            try:
                return open(c).read()
            except FileNotFoundError:
                continue
        r = subprocess.run(["git", "show", f"{ref}:{c}"], capture_output=True, text=True)
        if r.returncode == 0:
            return r.stdout
    return ""


def code_lines(text, comment):
    n = 0
    for line in text.splitlines():
        t = line.strip()
        if t and not t.startswith(comment):
            n += 1
    return n


def function_body(text, header):
    """Corpo de uma funcao Lua indentada em 2 espacos (ate o 'end' alinhado)."""
    i = text.find(header)
    if i < 0:
        return ""
    indent = text[:i].split("\n")[-1]
    lines = text[i:].split("\n")
    out = [lines[0]]
    for line in lines[1:]:
        out.append(line)
        if line == indent + "end":
            break
    return "\n".join(out)


def atm_section(text, start, end):
    i = text.find(start)
    j = text.find(end, i + 1)
    return text[i:j] if i >= 0 and j > i else ""


LEGADO = "caminho antigo"   # ramos usados so sem main.atm (testes unitarios)


def gamestate_writes(src):
    found = []
    for path in FILES:
        for k, line in enumerate(read(src, path).splitlines(), 1):
            code = line.split("--")[0]
            if re.search(r"gamestate\s*=[^=]", code) and not re.search(r"gamestate\s*=\s*\"title\",", code):
                found.append(f"{path}:{k}" + (" (legado)" if LEGADO in line else ""))
    return found


def start_level_calls(src):
    found = []
    for path in FILES:
        for k, line in enumerate(read(src, path).splitlines(), 1):
            code = line.split("--")[0].split(";;")[0]
            if re.search(r"start_level\s*\(", code) and "function" not in code:
                found.append(f"{path}:{k}" + (" (legado)" if LEGADO in line else ""))
    return found


def main():
    ref_game = read(REF, "game.lua")
    cur_game = read(CUR, "game.lua")
    cur_atm = read(CUR, "main.atm")
    ref_atm = read(REF, "main.atm")

    decide_ref = ["function game.begin_exit", "function game.finish_finale",
                  "function game.advance", "function game.end_game"]
    ref_flow_lua = sum(code_lines(function_body(ref_game, h), "--") for h in decide_ref)
    decide_found_cur = [h for h in decide_ref[:3] if h in cur_game]

    helpers = ["function game.request", "function game.end_level", "function game.make_finale",
               "function game.make_intermission", "function game.commercial_finale",
               "function game.map_exists", "function game.to_title", "function game.end_game",
               "function game.clear_game", "function game.is_commercial"]
    cur_helpers = sum(code_lines(function_body(cur_game, h), "--") for h in helpers)

    ref_screens = atm_section(ref_atm, ";; ---------------------------------------------------------------- telas",
                              ";; ------------------------------------------------------------- entrada")
    cur_flow = atm_section(cur_atm, ";; ------------------------------------------------------- regras do Doom",
                           ";; ------------------------------------------------------------- entrada")

    gw_ref, gw_cur = gamestate_writes(REF), gamestate_writes(CUR)
    sl_ref, sl_cur = start_level_calls(REF), start_level_calls(CUR)

    tasks_cur = re.findall(r"^task (\w+)", cur_flow, re.M)
    tasks_ref = re.findall(r"^task (\w+)", ref_screens, re.M)

    print(f"| Metrica | {REF} | atual |")
    print("|---|---|---|")
    def live(xs):
        return len([x for x in xs if "(legado)" not in x])

    def leg(xs):
        n = len(xs) - live(xs)
        return f" (+{n} legado)" if n else ""

    print(f"| Escritas de `game.gamestate` (fora do valor inicial) | {live(gw_ref)} | {live(gw_cur)}{leg(gw_cur)} |")
    print(f"| Pontos que iniciam um nivel (`start_level(...)`) | {live(sl_ref)} | {live(sl_cur)}{leg(sl_cur)} |")
    print(f"| Funcoes Lua que decidem a proxima tela | {len(decide_ref)} | {len(decide_found_cur)} |")
    print(f"| Linhas do fluxo em Lua (decisao de tela) | {ref_flow_lua} | 0 |")
    print(f"| Linhas Lua de apoio ao fluxo (montar telas, pedidos) | - | {cur_helpers} |")
    print(f"| Linhas do fluxo em Atmos (tasks de tela) | {code_lines(ref_screens, ';;')} | {code_lines(cur_flow, ';;')} |")
    print(f"| Tasks de tela | {len(tasks_ref)} ({', '.join(tasks_ref)}) | {len(tasks_cur)} ({', '.join(tasks_cur)}) |")
    print()
    print("Escritas de gamestate:")
    print(f"  {REF}: " + ", ".join(gw_ref))
    print(f"  atual: " + ", ".join(gw_cur))
    print("start_level(...):")
    print(f"  {REF}: " + ", ".join(sl_ref))
    print(f"  atual: " + (", ".join(sl_cur) or "nenhum"))


if __name__ == "__main__":
    main()
