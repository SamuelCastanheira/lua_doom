#!/usr/bin/env python3
"""Metricas do passo 3 (specials de setor): referencia (tag passo2) x atual.

Para cada subpasso ja migrado, conta nas duas versoes:
  * linhas de codigo (sem comentarios e linhas vazias);
  * campos de estado guardados por entidade (a tabela do thinker) x
    parametros e variaveis vivas entre awaits (a task);
  * ramos de despacho por tipo ("kind ==") e contadores manuais ("count");
  * referencias a lista de thinkers (criar, percorrer, reconstruir).

Uso: python3 tools/metricas_passo3.py [ref]
     ref padrao: passo2; a versao atual e a arvore de trabalho.
A cada subpasso, acrescente uma entrada em SUBPASSOS.
"""
import re
import subprocess
import sys

REF = sys.argv[1] if len(sys.argv) > 1 else "passo2"


def read(ref, path):
    if ref is None:
        try:
            return open(path).read()
        except FileNotFoundError:
            return ""
    r = subprocess.run(["git", "show", f"{ref}:{path}"], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def code_lines(text, comment):
    return sum(1 for line in text.splitlines()
               if line.strip() and not line.strip().startswith(comment))


def lua_function(text, header):
    """Funcao Lua de nivel superior: do cabecalho ate o 'end' na coluna 0."""
    i = text.find(header)
    if i < 0:
        return ""
    out = []
    for line in text[i:].split("\n"):
        out.append(line)
        if line == "end":
            break
    return "\n".join(out)


def atm_block(text, header):
    """Bloco Atmos de nivel superior: do cabecalho ate o '}' na coluna 0."""
    i = text.find(header)
    if i < 0:
        return ""
    out = []
    for line in text[i:].split("\n"):
        out.append(line)
        if line == "}":
            break
    return "\n".join(out)


def trecho(text, start, stop):
    """Linhas de "start" (inclusive) ate "stop" (exclusive)."""
    i = text.find(start)
    if i < 0:
        return ""
    j = text.find(stop, i + len(start))
    return text[i:j] if j > i else ""


def parte(ref, item):
    """item: (arquivo, tipo, a[, b]); tipo "fn" (funcao Lua), "blk" (bloco
    Atmos) ou "trecho" (de a ate b)."""
    path, kind, a = item[:3]
    text = read(ref, path)
    if kind == "fn":
        return lua_function(text, a)
    if kind == "blk":
        return atm_block(text, a)
    return trecho(text, a, item[3])


def juntar(ref, itens):
    return "\n".join(parte(ref, it) for it in itens)


SUBPASSOS = {
    "3a luzes": {
        "antes": [("specials.lua", "fn", h) for h in (
            "local function spawn_light_flash", "local function spawn_strobe",
            "local function spawn_glow", "local function spawn_fire",
            "local function tick_lights")],
        "lua": [("specials.lua", "fn", h) for h in (
            "local function spawn_task", "local function spawn_luz",
            "local function spawn_light_flash",
            "local function spawn_strobe", "local function spawn_glow",
            "local function spawn_fire")],
        "atm": [("setores.atm", "blk", h) for h in (
            "val func espera", "val task Pisca", "val task Strobe",
            "val task Brilho", "val task Fogo")],
        "lista": [("specials.lua", r"self\.lights")],
    },
    "3e botoes": {
        "antes": [
            ("specials.lua", "trecho", "  local keep = {}", "  return self.stamp ~= before"),
            ("specials.lua", "trecho", "      if use_again then", "      side[attr] = new"),
            ("saveg.lua", "trecho", "  local buttons = {}", "  return {"),
            ("saveg.lua", "trecho", "    local buttons = data.buttons or {}", "  local recs = data.mobjs"),
        ],
        "lua": [
            ("specials.lua", "fn", "function M.start_button"),
            ("specials.lua", "trecho", "      if use_again then", "      side[attr] = new"),
            ("saveg.lua", "trecho", "  -- Botoes (passo 3e)", "  return {"),
            ("saveg.lua", "trecho", "    local buttons = data.buttons or {}", "  local recs = data.mobjs"),
        ],
        "atm": [("setores.atm", "blk", "val task Botao")],
        "lista": [("specials.lua", r"self\.buttons"), ("saveg.lua", r"specials\.buttons")],
    },
    "3b portas": {
        "antes": [
            ("specials.lua", "fn", "local function spawn_door"),
            ("specials.lua", "fn", "local function spawn_door_close_in_30"),
            ("specials.lua", "fn", "local function spawn_door_raise_in_5"),
            ("specials.lua", "fn", "local function tick_door"),
            ("specials.lua", "trecho", "  local alive = {}", "  local keep = {}"),
            ("specials.lua", "fn", "function M.stop_plat"),
            ("saveg.lua", "trecho", "  local thinkers = {}", "  local buttons = {}"),
            ("saveg.lua", "trecho", "    local thinkers = data.thinkers or {}", "    local buttons = data.buttons or {}"),
        ],
        "lua": [
            ("specials.lua", "fn", "local function add_thinker"),
            ("specials.lua", "fn", "function M.start_door"),
            ("specials.lua", "fn", "local function spawn_door"),
            ("specials.lua", "fn", "local function spawn_door_close_in_30"),
            ("specials.lua", "fn", "local function spawn_door_raise_in_5"),
            ("specials.lua", "fn", "function M.tick_thinker"),
            ("specials.lua", "fn", "function M.stop_plat"),
            ("saveg.lua", "trecho", "  -- Movimentadores (passo 3b)", "  -- Botoes (passo 3e)"),
            ("saveg.lua", "trecho", "    local thinkers = data.thinkers or {}", "    local buttons = data.buttons or {}"),
        ],
        "atm": [("setores.atm", "blk", h) for h in (
            "val task ThinkerLua", "val func mover", "val func esperar_porta", "val task Porta")],
        # estado: so as partes da porta (sem stop_plat, load e ThinkerLua,
        # que tratam tambem de elevadores e pisos)
        "estado_antes": [("specials.lua", "fn", h) for h in (
            "local function spawn_door", "local function spawn_door_close_in_30",
            "local function spawn_door_raise_in_5", "local function tick_door")],
        "estado_depois": [("setores.atm", "blk", h) for h in (
            "val func mover", "val func esperar_porta", "val task Porta")],
        "lista": [("specials.lua", r"self\.thinkers"), ("saveg.lua", r"specials\.thinkers")],
    },
}


def sem_comentarios(text):
    """Tira comentarios Lua de linha ("-- ..."), para contar so codigo."""
    return "\n".join(re.sub(r"--.*$", "", line) for line in text.splitlines())


def campos_lua(ref_text):
    """Campos das tabelas de thinker: chaves "nome = ..." em construtores e
    "x.nome = ..." em atribuicoes, sem variaveis locais."""
    chaves, acessos = set(), set()
    for line in ref_text.splitlines():
        t = line.strip()
        m = re.match(r"^(\w+) = ", t)
        if m and not t.startswith("local"):
            chaves.add(m.group(1))
        for m in re.finditer(r"\b(?:light|flash|door|plat|floor|ceil|btn)\.(\w+)", t):
            acessos.add(m.group(1))
    locais = set(re.findall(r"\blocal (\w+)", ref_text))
    return (chaves - locais) | acessos


# Parametros que sao so contexto ou um registro compartilhado (os campos do
# registro e que contam, logo abaixo).
CONTEXTO = {"sp", "porta", "th"}


def estado_atm(atm_text):
    """Estado das tasks: parametros de cada task (o que vive entre awaits;
    as locais das tasks do 3a nao atravessam um await) mais os campos de
    registros compartilhados com o Lua que a task le ou escreve (porta.x,
    pub.x)."""
    nomes = set()
    for m in re.finditer(r"task \w+ \(([^)]*)\)", atm_text):
        nomes.update(x.strip() for x in m.group(1).split(",") if x.strip())
    for m in re.finditer(r"\b(?:porta|pub)\.(\w+)", atm_text):
        nomes.add(m.group(1))
    return nomes - CONTEXTO


def main():
    print(f"referencia: tag {REF}   atual: arvore de trabalho\n")
    for nome, s in SUBPASSOS.items():
        ref = juntar(REF, s["antes"])
        lua = juntar(None, s["lua"])
        atm = juntar(None, s["atm"])
        rl, ll, al = code_lines(ref, "--"), code_lines(lua, "--"), code_lines(atm, ";;")
        print(f"== {nome}")
        print(f"{'metrica':44} {'antes':>7} {'depois':>7}")
        print(f"{'linhas de codigo (Lua)':44} {rl:>7} {ll:>7}")
        print(f"{'linhas de codigo (Atmos)':44} {'-':>7} {al:>7}")
        print(f"{'linhas de codigo (total)':44} {rl:>7} {ll + al:>7}")
        er = juntar(REF, s["estado_antes"]) if "estado_antes" in s else ref
        ed = juntar(None, s["estado_depois"]) if "estado_depois" in s else atm
        cr, ea = campos_lua(er), estado_atm(ed)
        print(f"{'estado por entidade (campos x parametros)':44} {len(cr):>7} {len(ea):>7}")
        print(f"{'':44}   antes: {', '.join(sorted(cr))}")
        print(f"{'':44}   depois: {', '.join(sorted(ea))}")
        print(f"{'ramos de despacho por tipo (kind ==)':44} "
              f"{len(re.findall(r'kind ==', ref)):>7} "
              f"{len(re.findall(r'kind ==', lua + atm)):>7}")
        print(f"{'contadores manuais (count)':44} "
              f"{len(re.findall(r'[.]count', ref)):>7} "
              f"{len(re.findall(r'[.]count', lua + atm)):>7}")
        dec = r"[.](\w+) = [\w.]+[.]\1 - 1"
        print(f"{'decrementos de contador (x.c = x.c - 1)':44} "
              f"{len(re.findall(dec, ref)):>7} {len(re.findall(dec, lua + atm)):>7}")
        nr = sum(len(re.findall(rx, sem_comentarios(read(REF, f)))) for f, rx in s["lista"])
        na = sum(len(re.findall(rx, sem_comentarios(read(None, f)))) for f, rx in s["lista"])
        arqs = ", ".join(sorted({f for f, _ in s["lista"]}))
        print(f"{'referencias a lista (' + arqs + ')':44} {nr:>7} {na:>7}")
        print()


if __name__ == "__main__":
    main()
