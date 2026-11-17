#!/usr/bin/env python3
"""Teste de sensibilidade: o teste de equivalencia detecta erros no fluxo?

Para cada mutacao (um erro plausivel no main.atm), roda a versao mutada no
mesmo roteiro da ultima execucao de tests/test_drivers.sh e compara com a
referencia (build/drivers/ref.log). Uma mutacao "sobrevive" se o log sair
identico; nesse caso o roteiro nao cobre aquele comportamento.

Uso (depois de: sh tests/test_drivers.sh 0 1 fluxo):
    python3 tools/mutacoes.py [roteiro]
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "build", "drivers")
SCRIPT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(OUT, "replay_1fluxo.txt")
REF = os.path.join(OUT, "ref.log")

# Mutantes equivalentes: mudam o codigo mas nao o comportamento. Sobreviver
# e o esperado; a justificativa fica registrada.
EQUIVALENTES = {
    "menu-depois-da-tela":
        "menu.ticker so muda skull_tics/which_skull (cursor do menu); nenhuma "
        "fase de tela le esses campos",
    "entra-antes-de-montar":
        "build_level nao le game.gamestate (a unica leitura fora das telas "
        "e am_map.responder, na fase de entrada)",
}

# (nome, descricao, trecho original, trecho mutado)
MUTACOES = [
    ("sem-cancel-catchup",
     "Nivel nao interrompe a recuperacao de tics ao sair do nivel",
     "                env.cancel_catchup()      ;; nao recupera mais tics neste quadro\n",
     ""),
    ("fim-sem-limpeza",
     "End Game encerra a task Jogo mas esquece a limpeza (G.end_game)",
     "            await :jogo.fim\n            G.end_game()\n",
     "            await :jogo.fim\n"),
    ("morte-encerra-jogo",
     "Morrer termina o jogo em vez de renascer no mesmo mapa",
     "            (r.fim == :morte)  => true            ;; renasce no mesmo mapa\n",
     "            (r.fim == :morte)  => false\n"),
    ("secreto-sem-volta",
     "Do mapa 9 vai para o mapa 10 (esquece a volta do secreto)",
     "        (mapn == 9)   => (VOLTA_DO_SECRETO@episode) || 1\n",
     ""),
    ("menu-depois-da-tela",
     "Relogio roda a tela antes do menu (ordem do tic trocada)",
     "            G.tic_menu()\n            pedidos()\n            emit :game.tic\n",
     "            emit :game.tic\n            G.tic_menu()\n            pedidos()\n"),
    ("pedidos-so-no-tic",
     "Pedidos da entrada so sao emitidos no tic seguinte",
     "        G.handle_input(ev)\n        pedidos()\n",
     "        G.handle_input(ev)\n"),
    ("entra-antes-de-montar",
     "Nivel entra em 'view' antes de montar o nivel",
     "        G.start_level()\n    }\n    G.enter(:view)\n",
     "        G.enter(:view)\n        G.start_level()\n    }\n    G.enter(:view)\n"),
    ("load-mantem-jogo",
     "Load Game nao descarta o jogo em andamento (pedido ignorado no Jogo)",
     "        } with {\n            await :jogo.carregar\n        } with {\n            await :jogo.fim",
     "        } with {\n            await :jogo.fim"),
    ("sair-sem-ultimo-quadro",
     "Quit encerra antes de desenhar o quadro atual",
     "    await :jogo.sair\n    await :frame                          ;; o quadro atual ainda e desenhado\n",
     "    await :jogo.sair\n"),
    ("trocar-ignora-mapa",
     "idclev reinicia o nivel atual em vez de ir ao mapa pedido",
     "                G.set_level(r.episode, r.mapn)\n",
     ""),
    ("wipe-nao-pausa",
     "Durante a transicao de tela, menu e tela continuam andando",
     "        if G.wiping() {\n            G.tic_wipe()\n        } else {\n",
     "        if G.wiping() {\n            G.tic_wipe()\n        }\n        do {\n"),
    ("novo-nao-descarta",
     "New Game no meio do jogo e ignorado (o Jogo atual continua)",
     "        } with {\n            await :jogo.novo\n        } with {\n            await :jogo.carregar",
     "        } with {\n            await :jogo.carregar"),
]


def mkrun(path, main_atm):
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
    for name in os.listdir(ROOT):
        if name.endswith((".lua", ".so", ".dll", ".wad")) or name == "atmos":
            os.symlink(os.path.join(ROOT, name), os.path.join(path, name))
    with open(os.path.join(path, "main.atm"), "w") as f:
        f.write(main_atm)


def compare(log):
    ref = open(REF).read().splitlines()
    got = open(log).read().splitlines() if os.path.exists(log) else []
    first = None
    diff = 0
    for i in range(max(len(ref), len(got))):
        a = ref[i] if i < len(ref) else None
        b = got[i] if i < len(got) else None
        if a != b:
            diff += 1
            if first is None:
                first = i + 1
    return first, diff, len(ref), len(got)


def main():
    if not os.path.exists(REF):
        sys.exit("rode antes: sh tests/test_drivers.sh 0 1 fluxo")
    src = open(os.path.join(ROOT, "main.atm")).read()
    print(f"roteiro: {os.path.relpath(SCRIPT, ROOT)}  referencia: {len(open(REF).read().splitlines())} quadros\n")
    print(f"{'mutacao':24} {'resultado':12} {'1o quadro':>9} {'quadros dif.':>12}  descricao")
    survived = 0
    equivalent = 0
    for name, desc, old, new in MUTACOES:
        if src.count(old) != 1:
            print(f"{name:24} {'NAO APLICADA':12} {'':>9} {'':>12}  trecho nao encontrado")
            survived += 1
            continue
        run = os.path.join(ROOT, "build", "mut", name)
        mkrun(run, src.replace(old, new))
        log = os.path.join(run, "replay.log")
        env = dict(os.environ, DOOM_REPLAY=SCRIPT, DOOM_REPLAY_OUT=log)
        with open(os.path.join(run, "saida.txt"), "w") as out:
            subprocess.run(["atmos", "main.atm", "--", "-nosound", "-nomusic"],
                           cwd=run, env=env, stdout=out, stderr=subprocess.STDOUT,
                           timeout=600)
        first, diff, nref, ngot = compare(log)
        if first is None and name in EQUIVALENTES:
            result = "equivalente"
            equivalent += 1
        elif first is None:
            result = "SOBREVIVEU"
            survived += 1
        else:
            result = "detectada"
        extra = "" if ngot == nref else f" ({ngot} quadros)"
        print(f"{name:24} {result:12} {first or '-':>9} {diff:>12}  {desc}{extra}")
        if result == "equivalente":
            print(f"{'':24} {'':12} {'':>9} {'':>12}    -> {EQUIVALENTES[name]}")
    total = len(MUTACOES) - equivalent
    print(f"\n{total - survived}/{total} mutacoes nao equivalentes detectadas"
          f" ({equivalent} equivalentes, justificadas acima)")
    sys.exit(1 if survived else 0)


if __name__ == "__main__":
    main()
