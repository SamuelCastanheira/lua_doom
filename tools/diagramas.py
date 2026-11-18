#!/usr/bin/env python3
"""Gera build/diagramas/index.html com todos os diagramas Mermaid de .md.

Serve para conferir a sintaxe antes de commitar (o GitHub renderiza os
blocos ```mermaid, mas um erro so aparece la). A pagina carrega o Mermaid
da CDN, tenta "parse" em cada diagrama e guarda os erros em window.erros.

Uso:
    python3 tools/diagramas.py [arquivo.md ...]    (padrao: docs/registro/03-specials.md)
    python3 -m http.server 8765 --directory build/diagramas
    (abra http://localhost:8765 e leia window.erros no console)
"""
import html
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "build", "diagramas", "index.html")
FILES = sys.argv[1:] or [os.path.join(ROOT, "docs", "registro", "03-specials.md")]

PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>Diagramas</title></head>
<body>
%s
<script type="module">
import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.esm.min.mjs";
mermaid.initialize({startOnLoad: false});
window.erros = [];
const els = [...document.querySelectorAll("pre.mermaid")];
for (const [i, el] of els.entries()) {
  try { await mermaid.parse(el.textContent); }
  catch (e) { window.erros.push((i + 1) + ": " + String(e.message || e).slice(0, 300)); }
}
await mermaid.run();
window.pronto = true;
</script>
</body></html>
"""


def main():
    parts = []
    n = 0
    for path in FILES:
        text = open(path).read()
        for bloco in re.findall(r"```mermaid\n(.*?)```", text, re.S):
            n += 1
            parts.append(f"<h3>diagrama {n} ({os.path.relpath(path, ROOT)})</h3>"
                         f'<pre class="mermaid">{html.escape(bloco)}</pre>')
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        f.write(PAGE % "\n".join(parts))
    print(f"{os.path.relpath(OUT, ROOT)}: {n} diagramas")


if __name__ == "__main__":
    main()
