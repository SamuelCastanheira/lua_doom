#!/usr/bin/env python3
"""Compara dois dumps do renderer C e agrupa os pixels diferentes pelo tipo
de superficie que os desenhou (tags_NN.raw do dump de referencia).

Uso: diff_by_tag.py <ref_dir> <novo_dir>
Serve para provar que uma mudanca so afetou o que devia (ex.: so o ceu).
"""
import os
import sys

NAMES = {0: "vazio", 1: "parede", 2: "flat", 3: "ceu", 4: "masked", 5: "sprite", 6: "arma"}

def main():
    ref, new = sys.argv[1], sys.argv[2]
    totals = {}
    changed_frames = 0
    names = sorted(n for n in os.listdir(ref) if n.startswith("frame_"))
    for name in names:
        a = open(os.path.join(ref, name), "rb").read()
        b = open(os.path.join(new, name), "rb").read()
        tags = open(os.path.join(ref, name.replace("frame_", "tags_")), "rb").read()
        any_diff = False
        for i in range(len(a)):
            if a[i] != b[i]:
                t = NAMES.get(tags[i], str(tags[i]))
                totals[t] = totals.get(t, 0) + 1
                any_diff = True
        changed_frames += any_diff
    desc = ", ".join(f"{k}={v}" for k, v in sorted(totals.items(), key=lambda kv: -kv[1])) or "nenhum"
    print(f"{changed_frames}/{len(names)} quadros mudaram; pixels por tipo: {desc}")

if __name__ == "__main__":
    main()
