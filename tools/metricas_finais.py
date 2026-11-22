#!/usr/bin/env python3
"""Metricas finais da migracao (secao 7 do docs/PLANO_ATMOS.md).

Junta, em tabelas Markdown prontas para a monografia, os numeros de todos os
passos, medidos na arvore de trabalho:

  1. expressividade por entidade: roda tools/metricas_passo3.py ... passo6.py
     (cada um contra a tag anterior ao seu passo) e extrai linhas de codigo e
     estado;
  2. pontos de limpeza manual (dead = true, specialdata = nil) na tag passo2 e
     hoje;
  3. roteiros de equivalencia: quadros e estados distintos (do log do
     make test-drivers);
  4. mutacoes por passo (do log do make test-mutacoes e das secoes
     "# --- passo N" de tools/mutacoes.py);
  5. com --custo: ms por quadro de todas as tags (tools/custo_drivers.py com
     CUSTO_TAGS), nos roteiros fluxo e monstro;
  6. com --memoria: pico de memoria Lua (collectgarbage) no roteiro fluxo,
     no passo1 (Lua e Atmos) e hoje.

Uso:
    make test-drivers | tee build/test-drivers.log
    make test-mutacoes | tee build/mutacoes.log
    python3 tools/metricas_finais.py [--custo] [--memoria]
"""
import os
import re
import shutil
import subprocess
import sys
import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pastas

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
os.chdir(ROOT)
LOG_DRIVERS = os.environ.get("LOG_DRIVERS", "build/test-drivers.log")
LOG_MUTACOES = os.environ.get("LOG_MUTACOES", "build/mutacoes.log")

# Entidades na ordem da regua da fase (docs/NOTAS_MONOGRAFIA.md, secao 8):
# (bloco no script, nome, script, exigencias da regua: leitura de fora, save,
# recado, interrupcao)
ENTIDADES = [
    ("3a luzes", "Luzes (3a)", "metricas_passo3.py", "nenhuma"),
    ("7", "Intermissão e finale (7)", "metricas_passo7.py", "nenhuma (só o desenho lê)"),
    ("3d pisos e tetos", "Pisos e tetos (3d)", "metricas_passo3.py", "save (piso)"),
    ("3e botoes", "Botões (3e)", "metricas_passo3.py", "save"),
    ("3b portas", "Portas (3b)", "metricas_passo3.py", "save, recado, interrupção"),
    ("3c elevadores", "Elevadores (3c)", "metricas_passo3.py", "save, recado, interrupção"),
    ("4c jogador", "Jogador (4c)", "metricas_passo4.py", "as quatro"),
    ("4a arma", "Arma (4a)", "metricas_passo4.py", "as quatro"),
    ("5", "Zombieman (5)", "metricas_passo5.py", "as quatro"),
    ("6", "Quadro e wipe (6)", "metricas_passo6.py", "nenhuma (o relógio)"),
]


def run(cmd, env=None):
    r = subprocess.run(cmd, capture_output=True, text=True, env=env)
    return r.stdout + r.stderr


def blocos(saida):
    """Separa a saida de um script de metricas em blocos "== nome"."""
    out, nome = {}, None
    for line in saida.splitlines():
        m = re.match(r"^== (.+)$", line)
        if m:
            nome = m.group(1).strip()
            out[nome] = []
        elif nome is not None:
            out[nome].append(line)
    if not out:
        out[""] = saida.splitlines()
    return out


def numeros(linhas, prefixo):
    for line in linhas:
        if line.startswith(prefixo):
            m = re.findall(r"\s(\d+|-)(?=\s|$)", line[len(prefixo):])
            if len(m) >= 2:
                return m[0], m[1]
    return None, None


def pct(a, b):
    try:
        a, b = int(a), int(b)
        return f"{(b - a) * 100 / a:+.0f}%" if a else "–"
    except (TypeError, ValueError):
        return "–"


def expressividade():
    saidas = {}
    print("### 1. Expressividade por entidade (na ordem da régua da fase)\n")
    print("Linhas de código sem comentários e sem linhas vazias; \"estado\" é o número")
    print("de campos guardados por entidade (ou lidos e escritos, na arma e no monstro),")
    print("como cada script o define. Antes: a tag anterior ao passo; depois: a árvore.\n")
    print("| Entidade | Exigências da régua | Linhas antes | Linhas depois | Variação | Estado antes | Estado depois |")
    print("|---|---|---|---|---|---|---|")
    for bloco, nome, script, regua in ENTIDADES:
        if script not in saidas:
            saidas[script] = blocos(run([sys.executable, os.path.join("tools", script)]))
        b = saidas[script]
        linhas = b.get(bloco) or b.get("") or []
        la, ld = numeros(linhas, "linhas de codigo (total)")
        ea, ed = None, None
        for pref in ("estado por entidade", "campos do jogador", "campos do mobj",
                     "campos de fase escritos"):
            ea, ed = numeros(linhas, pref)
            if ea:
                break
        print(f"| {nome} | {regua} | {la or '–'} | {ld or '–'} | {pct(la, ld)} | {ea or '–'} | {ed or '–'} |")
    print()


def limpeza():
    print("### 2. Pontos de limpeza manual\n")
    print("Ocorrências de `dead = true` e `specialdata = nil` no código (Lua e Atmos).")
    print("Hoje, as que restam estão nos `defer` das tasks: declaradas uma vez por")
    print("task e executadas também quando o `Nivel` aborta a task.\n")
    print("| Padrão | tag `passo2` | hoje | hoje, dentro de `defer` |")
    print("|---|---|---|---|")
    arquivos = ["specials.lua", "saveg.lua", "setores.atm", "thinker.lua", "player.lua",
                "arma.atm", "jogador.atm", "monstro.atm", "game.lua"]
    for pad in (r"dead = true", r"specialdata = nil"):
        antes = hoje = em_defer = 0
        for f in arquivos:
            r = subprocess.run(["git", "show", f"passo2:{f}"], capture_output=True, text=True)
            antes += len(re.findall(pad, r.stdout))
            if os.path.exists(f):
                txt = open(f).read()
                hoje += len(re.findall(pad, txt))
                for d in re.finditer(r"defer \{(.*?)\n    \}", txt, re.S):
                    em_defer += len(re.findall(pad, d.group(1)))
        print(f"| `{pad}` | {antes} | {hoje} | {em_defer} |")
    print()


def roteiros():
    print("### 3. Roteiros de equivalência (driver Atmos × tag `passo1`)\n")
    if not os.path.exists(LOG_DRIVERS):
        print(f"(sem {LOG_DRIVERS}: rode `make test-drivers | tee {LOG_DRIVERS}`)\n")
        return
    txt = open(LOG_DRIVERS).read()
    print("| Roteiro | Argumentos | Quadros | Estados distintos | Resultado |")
    print("|---|---|---|---|---|")
    total_q = 0
    for m in re.finditer(r"identico a passo1: (\d+) quadros, (\d+) estados distintos \(semente (\d+) ?(\S*) ?(.*?)\)", txt):
        q, e, sem, nome, args = m.groups()
        nome = nome or f"semente {sem}"
        total_q += int(q)
        print(f"| {nome} | `{args.strip() or '-'}` | {int(q):,} | {int(e):,} | idêntico |".replace(",", "."))
    div = len(re.findall(r"DIVERGENCIA", txt))
    print(f"| **total** | | {total_q:,} | | {div} divergências |".replace(",", "."))
    m = re.search(r"atmos: (\d+) propriedades ok", txt)
    if m:
        print(f"\nSemântica do Atmos: {m.group(1)} propriedades verificadas (P1 a P9).")
    print()


def mutacoes():
    print("### 4. Mutações por passo\n")
    if not os.path.exists(LOG_MUTACOES):
        print(f"(sem {LOG_MUTACOES}: rode `make test-mutacoes | tee {LOG_MUTACOES}`)\n")
        return
    src = open("tools/mutacoes.py").read()
    passo, mapa = None, {}
    ini = src.index("MUTACOES = [")
    for line in src[ini:].splitlines():
        m = re.match(r"\s*# --- (?:passo (\d)|(C\d))", line)
        if m:
            passo = m.group(1) or m.group(2)
            continue
        m = re.match(r'\s*\("([a-z0-9-]+)",\s*$', line)
        if m and passo:
            mapa[m.group(1)] = passo
    log = open(LOG_MUTACOES).read()
    res = {}
    for line in log.splitlines():
        m = re.match(r"^([a-z0-9-]+)\s+(detectada|equivalente|pendente|SOBREVIVEU|NAO APLICADA)", line)
        if m:
            res[m.group(1)] = m.group(2)
    print("| Passo | Mutações | Detectadas | Equivalentes | Pendentes | Sobreviventes |")
    print("|---|---|---|---|---|---|")
    tot = [0, 0, 0, 0, 0]
    for p in sorted(set(mapa.values())):
        nomes = [n for n, q in mapa.items() if q == p]
        c = [len(nomes)] + [sum(1 for n in nomes if res.get(n) == k)
                            for k in ("detectada", "equivalente", "pendente")]
        c.append(len(nomes) - sum(c[1:]))
        tot = [a + b for a, b in zip(tot, c)]
        print(f"| {p} | {c[0]} | {c[1]} | {c[2]} | {c[3]} | {c[4]} |")
    print(f"| **total** | {tot[0]} | {tot[1]} | {tot[2]} | {tot[3]} | {tot[4]} |")
    m = re.search(r"(\d+/\d+) mutacoes nao equivalentes detectadas", log)
    if m:
        print(f"\nResumo do `tools/mutacoes.py`: {m.group(1)} não equivalentes detectadas.")
    print()


def custo():
    print("### 5. Custo acumulado (ms por quadro, modo replay)\n")
    env = dict(os.environ, CUSTO_TAGS="passo2,passo3,passo4,passo5")
    linhas = {}
    for nome, args in (("fluxo", []),
                       ("monstro", ["build/drivers/replay_1monstro.txt", "-warp", "1", "2", "-respawn"])):
        if nome == "monstro" and not os.path.exists(args[0]):
            run(["sh", "tests/test_drivers.sh", "0", "1", "monstro", "-warp", "1", "2", "-respawn"])
        out = run([sys.executable, "tools/custo_drivers.py", "5"] + args, env=env)
        for m in re.finditer(r"^(\S+-\S+)\s+\S+ s\s+\S+ s\s+\d+\s+([\d.]+)", out, re.M):
            linhas.setdefault(m.group(1), {})[nome] = float(m.group(2))
    base = linhas.get("passo1-lua", {})
    print("| Driver | `fluxo` | vs. `passo1` Lua | `monstro` | vs. `passo1` Lua |")
    print("|---|---|---|---|---|")
    for drv in ("passo1-lua", "passo1-atm", "passo2-atm", "passo3-atm", "passo4-atm", "passo5-atm", "atual-atm"):
        v = linhas.get(drv, {})
        cel = []
        for r in ("fluxo", "monstro"):
            if r in v and r in base:
                cel += [f"{v[r]:.3f}".replace(".", ","), f"{(v[r] / base[r] - 1) * 100:+.1f}%".replace(".", ",")]
            else:
                cel += ["–", "–"]
        nome = drv.replace("atual-atm", "atual (`passo6`)").replace("-atm", " `main.atm`").replace("-lua", " `main.lua`")
        print(f"| {nome} | {' | '.join(cel)} |")
    print("\nO tic dura 28,6 ms a 35 Hz. As medições oscilam alguns por cento entre")
    print("séries (registro do passo 3d, seção de custo).\n")


LUA_INIT = r"""
local pico = 0
local function amostra()
  local c = collectgarbage("count")
  if c > pico then pico = c end
end
debug.sethook(amostra, "", 50000)
local relatado = false
local function relata()
  -- sem collectgarbage aqui: no fechamento do estado (finalizador) ele falha
  -- e o erro vira um aviso silencioso
  if relatado then return end
  relatado = true
  pcall(io.stderr.write, io.stderr, string.format("MEMORIA_PICO_KB %.0f\n", pico))
end
_MEMORIA_GUARDA = setmetatable({}, { __gc = relata })
local sair = os.exit
os.exit = function(...) amostra(); relata(); return sair(...) end
"""


def memoria():
    print("### 6. Pico de memória Lua (roteiro `fluxo`)\n")
    print("`collectgarbage(\"count\")` amostrado por um gancho de contagem (a cada 50.000")
    print("instruções da linha principal). É uma estimativa: as")
    print("tasks rodam em corrotinas, onde o gancho não está ativo, mas a memória é a")
    print("do estado Lua inteiro.\n")
    script = os.path.abspath("build/drivers/replay_1fluxo.txt")
    if not os.path.exists(script):
        run(["sh", "tests/test_drivers.sh", "0", "1", "fluxo"])
    drivers = [("passo1 `main.lua`", "build/ref-passo1", ["lua5.4", "main.lua"]),
               ("passo1 `main.atm`", "build/ref-passo1", ["atmos", "main.atm", "--"]),
               ("atual (`passo6`)", ".", ["atmos", "main.atm", "--"])]
    print("| Driver | Pico (KB) |")
    print("|---|---|")
    for nome, src, cmd in drivers:
        path = os.path.join(ROOT, "build", "memoria", "run")
        src = os.path.abspath(src)
        pastas.montar_execucao(src, path)
        env = dict(os.environ, DOOM_REPLAY=script, DOOM_REPLAY_OUT=os.path.join(path, "x.log"),
                   LUA_INIT_5_4=LUA_INIT)
        r = subprocess.run(cmd + ["-nosound", "-nomusic"], cwd=path, env=env,
                           capture_output=True, text=True)
        m = re.findall(r"MEMORIA_PICO_KB (\d+)", r.stderr)
        print(f"| {nome} | {int(m[-1]):,} |".replace(",", ".") if m else f"| {nome} | – |")
    print()


def main():
    print("## Métricas finais da migração (medidas por `tools/metricas_finais.py`)\n")
    expressividade()
    limpeza()
    roteiros()
    mutacoes()
    if "--custo" in sys.argv:
        custo()
    if "--memoria" in sys.argv:
        memoria()


if __name__ == "__main__":
    main()
