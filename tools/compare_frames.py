#!/usr/bin/env python3
"""Compara dois diretorios gerados por tools/dump_frames.lua.

Uso: compare_frames.py <ref_dir> <novo_dir> [png_dir]

Imprime a porcentagem de pixels diferentes por quadro. Com png_dir, grava
para cada quadro uma imagem lado a lado: referencia | novo | diferenca
(pixels diferentes em vermelho). Requer Pillow apenas para os PNGs.
"""
import os
import sys

W, H = 320, 200


def load(path):
    with open(path, "rb") as f:
        return f.read()


def main():
    ref_dir, new_dir = sys.argv[1], sys.argv[2]
    png_dir = sys.argv[3] if len(sys.argv) > 3 else None
    pal = load(os.path.join(ref_dir, "palette.raw"))
    names = sorted(n for n in os.listdir(ref_dir) if n.startswith("frame_"))
    if png_dir:
        from PIL import Image
        os.makedirs(png_dir, exist_ok=True)
    total_bad = 0
    for name in names:
        a = load(os.path.join(ref_dir, name))
        b_path = os.path.join(new_dir, name)
        if not os.path.exists(b_path):
            print(f"{name}: ausente")
            total_bad += 1
            continue
        b = load(b_path)
        bad = sum(1 for i in range(W * H) if a[i] != b[i])
        total_bad += bad
        print(f"{name}: {bad:6d} px diferentes ({100.0 * bad / (W * H):5.2f}%)")
        if png_dir:
            img = Image.new("RGB", (W * 3, H))
            px = img.load()
            for y in range(H):
                for x in range(W):
                    i = y * W + x
                    ca, cb = a[i], b[i]
                    px[x, y] = tuple(pal[ca * 3:ca * 3 + 3])
                    px[x + W, y] = tuple(pal[cb * 3:cb * 3 + 3])
                    px[x + 2 * W, y] = (255, 0, 0) if ca != cb else (0, 0, 0)
            img = img.resize((W * 3 * 2, H * 2), Image.NEAREST)
            img.save(os.path.join(png_dir, name.replace(".raw", ".png")))
    print(f"total: {total_bad} px diferentes em {len(names)} quadros")
    sys.exit(0 if total_bad == 0 else 1)


if __name__ == "__main__":
    main()
