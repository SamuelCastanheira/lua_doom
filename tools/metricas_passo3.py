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


def lua_part(ref, path, headers):
    text = read(ref, path)
    return "\n".join(lua_function(text, h) for h in headers)


def atm_part(path, headers):
    text = read(None, path)
    return "\n".join(atm_block(text, h) for h in headers)


SUBPASSOS = {
    "3a luzes": {
        "ref": ("specials.lua", [
            "local function spawn_light_flash", "local function spawn_strobe",
            "local function spawn_glow", "local function spawn_fire",
            "local function tick_lights",
        ]),
        "lua": ("specials.lua", [
            "local function spawn_luz", "local function spawn_light_flash",
            "local function spawn_strobe", "local function spawn_glow",
            "local function spawn_fire",
        ]),
        "atm": ("setores.atm", [
            "val func espera", "val task Pisca", "val task Strobe",
            "val task Brilho", "val task Fogo",
        ]),
        "lista": r"self\.lights",
    },
}


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


def estado_atm(atm_text):
    """Estado das tasks: parametros de cada task (o que vive entre awaits;
    as locais das tasks do 3a nao atravessam um await)."""
    nomes = set()
    for m in re.finditer(r"task \w+ \(([^)]*)\)", atm_text):
        nomes.update(x.strip() for x in m.group(1).split(",") if x.strip())
    return nomes


def main():
    print(f"referencia: tag {REF}   atual: arvore de trabalho\n")
    for nome, s in SUBPASSOS.items():
        ref = lua_part(REF, *s["ref"])
        lua = lua_part(None, *s["lua"])
        atm = atm_part(*s["atm"])
        rl, ll, al = code_lines(ref, "--"), code_lines(lua, "--"), code_lines(atm, ";;")
        print(f"== {nome}")
        print(f"{'metrica':44} {'antes':>7} {'depois':>7}")
        print(f"{'linhas de codigo (Lua)':44} {rl:>7} {ll:>7}")
        print(f"{'linhas de codigo (Atmos)':44} {'-':>7} {al:>7}")
        print(f"{'linhas de codigo (total)':44} {rl:>7} {ll + al:>7}")
        cr, ea = campos_lua(ref), estado_atm(atm)
        print(f"{'estado por entidade (campos x parametros)':44} {len(cr):>7} {len(ea):>7}")
        print(f"{'':44}   antes: {', '.join(sorted(cr))}")
        print(f"{'':44}   depois: {', '.join(sorted(ea))}")
        print(f"{'ramos de despacho por tipo (kind ==)':44} "
              f"{len(re.findall(r'kind ==', ref)):>7} "
              f"{len(re.findall(r'kind ==', lua + atm)):>7}")
        print(f"{'contadores manuais (count)':44} "
              f"{len(re.findall(r'[.]count', ref)):>7} "
              f"{len(re.findall(r'[.]count', lua + atm)):>7}")
        cur_specials = read(None, "specials.lua")
        ref_specials = read(REF, "specials.lua")
        print(f"{'referencias a lista (specials.lua inteiro)':44} "
              f"{len(re.findall(s['lista'], ref_specials)):>7} "
              f"{len(re.findall(s['lista'], cur_specials)):>7}")
        print()


if __name__ == "__main__":
    main()
