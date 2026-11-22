"""As pastas do projeto, para as ferramentas.

Desde a organizacao em pastas, o codigo fica em jogo/ (a logica), render/
(o renderer) e ponte/ (a comunicacao com o C: video, som, teclas, o ambiente
Atmos e os .so); main.lua, main.atm e caminhos.lua ficam na raiz. As tags
antigas (passo1 a c5) tem tudo na raiz, e as ferramentas precisam lidar com
os dois jeitos.
"""
import os
import shutil

PASTAS = ("jogo", "render", "ponte")


def localizar(raiz, nome):
    """O caminho (relativo a raiz) de um arquivo do jogo pelo nome: na raiz
    (as tags antigas) ou numa das pastas."""
    if os.path.exists(os.path.join(raiz, nome)):
        return nome
    for pasta in PASTAS:
        caminho = os.path.join(pasta, nome)
        if os.path.exists(os.path.join(raiz, caminho)):
            return caminho
    return nome


def montar_execucao(src, dst, copiar_pastas=False):
    """Uma pasta para rodar o jogo isolado: links para o codigo de src, e
    saves/ e musica/ vazias (o jogo grava ali; as tags antigas gravam os
    saves na raiz da pasta). copiar_pastas: as pastas do codigo viram pastas
    de verdade, com um link por arquivo, para que um arquivo possa ser
    trocado (tools/mutacoes.py) sem tocar no original."""
    shutil.rmtree(dst, ignore_errors=True)
    os.makedirs(os.path.join(dst, "saves"))
    os.makedirs(os.path.join(dst, "musica"))
    for nome in os.listdir(src):
        if nome.endswith((".lua", ".so", ".dll", ".atm", ".wad")) or nome == "atmos":
            os.symlink(os.path.join(src, nome), os.path.join(dst, nome))
    for pasta in PASTAS:
        origem = os.path.join(src, pasta)
        if not os.path.isdir(origem):
            continue
        if not copiar_pastas:
            os.symlink(origem, os.path.join(dst, pasta))
            continue
        for raiz, _dirs, arquivos in os.walk(origem):
            destino = os.path.join(dst, os.path.relpath(raiz, src))
            os.makedirs(destino, exist_ok=True)
            for arq in arquivos:
                os.symlink(os.path.join(raiz, arq), os.path.join(destino, arq))


def save_de(execucao, nome):
    """Um save gravado numa execucao: em saves/ ou na raiz (tags antigas)."""
    novo = os.path.join(execucao, "saves", nome)
    return novo if os.path.exists(novo) else os.path.join(execucao, nome)
