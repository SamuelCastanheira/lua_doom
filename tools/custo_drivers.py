#!/usr/bin/env python3
"""Custo por quadro dos drivers, em modo replay (sem janela, sem som).

Compara, no mesmo roteiro:
  passo1-lua   main.lua da tag passo1 (laco imperativo, referencia)
  passo1-atm   main.atm da tag passo1 (Atmos, telas observadas)
  passo2-atm   main.atm da tag passo2 (Atmos, fluxo de telas em tasks)
  atual-atm    main.atm atual

Cada execucao roda numa pasta limpa (sem saves). O custo por quadro desconta
a inicializacao, medida com um roteiro que sai no quadro 2.

Uso (depois de: sh tests/test_drivers.sh 0 1 fluxo):
    python3 tools/custo_drivers.py [repeticoes] [roteiro] [args do jogo...]
    ex.: python3 tools/custo_drivers.py 5 build/drivers/replay_1luzes.txt -warp 4 1
O worktree da tag passo2 (build/ref-passo2) e criado e compilado se faltar.
"""
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
REF = os.path.join(ROOT, "build", "ref-passo1")
REF2 = os.path.join(ROOT, "build", "ref-passo2")
REPS = int(sys.argv[1]) if len(sys.argv) > 1 else 5
SCRIPT = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.join(ROOT, "build", "drivers", "replay_1fluxo.txt")
QUIT = os.path.join(ROOT, "build", "custo", "quit2.txt")
GAME_ARGS = sys.argv[3:]

DRIVERS = [
    ("passo1-lua", REF, ["lua5.4", "main.lua"]),
    ("passo1-atm", REF, ["atmos", "main.atm", "--"]),
    ("passo2-atm", REF2, ["atmos", "main.atm", "--"]),
    ("atual-atm", ROOT, ["atmos", "main.atm", "--"]),
]


def mkrun(src, path):
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
    for name in os.listdir(src):
        if name.endswith((".lua", ".so", ".dll", ".atm", ".wad")) or name == "atmos":
            os.symlink(os.path.join(src, name), os.path.join(path, name))


def run(src, cmd, script):
    path = os.path.join(ROOT, "build", "custo", "run")
    mkrun(src, path)
    log = os.path.join(path, "replay.log")
    env = dict(os.environ, DOOM_REPLAY=script, DOOM_REPLAY_OUT=log)
    t0 = time.perf_counter()
    subprocess.run(cmd + ["-nosound", "-nomusic"] + GAME_ARGS, cwd=path, env=env,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    dt = time.perf_counter() - t0
    frames = sum(1 for _ in open(log))
    return dt, frames


def ensure_ref2():
    if not os.path.isdir(REF2):
        subprocess.run(["git", "worktree", "add", "--detach", REF2, "passo2"],
                       cwd=ROOT, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for name in os.listdir(ROOT):
        if name.endswith(".wad") and not os.path.exists(os.path.join(REF2, name)):
            os.symlink(os.path.join(ROOT, name), os.path.join(REF2, name))
    subprocess.run(["make", "-s"], cwd=REF2, check=True, stdout=subprocess.DEVNULL)


def main():
    ensure_ref2()
    os.makedirs(os.path.dirname(QUIT), exist_ok=True)
    with open(QUIT, "w") as f:
        f.write("2 quit\n")
    print(f"roteiro: {os.path.relpath(SCRIPT, ROOT)}, {REPS} repeticoes por driver\n")
    print(f"{'driver':12} {'inicializacao':>14} {'total':>9} {'quadros':>8} {'ms/quadro':>10}")
    base = None
    for name, src, cmd in DRIVERS:
        ini = min(run(src, cmd, QUIT)[0] for _ in range(REPS))
        totals = []
        frames = 0
        for _ in range(REPS):
            dt, frames = run(src, cmd, SCRIPT)
            totals.append(dt)
        tot = min(totals)
        per = (tot - ini) / frames * 1000
        rel = "" if base is None else f"  ({(per - base) / base * 100:+.1f}%)"
        base = base if base is not None else per
        print(f"{name:12} {ini:>12.2f} s {tot:>7.2f} s {frames:>8} {per:>10.3f}{rel}")
    print("\n(min de cada serie; ms/quadro inclui jogo, renderer em C e carregamento de niveis)")


if __name__ == "__main__":
    main()
