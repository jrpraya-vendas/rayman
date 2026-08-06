#!/usr/bin/env bash
# ============================================================
#  RAYMAN — assistente de IA pessoal, 100% local
#  Instalador para macOS (Apple Silicon e Intel)
#
#  Uso (um comando, sem interação):
#      bash install_rayman.sh
#
#  O que ele faz:
#   1. Roda o instalador oficial do OpenJarvis (Stanford)
#      -> uv + venv + Ollama + modelo local qwen3.5:2b
#   2. Instala Homebrew (se faltar) e espeak-ng (voz pt-BR)
#   3. Instala as libs de voz: sounddevice, soundfile, kokoro
#   4. Cria a persona RAYMAN em português do Brasil
#   5. Instala os comandos: rayman, rayman-voz, rayman-show
#   6. Valida tudo com jarvis doctor e fala a saudação
# ============================================================
set -euo pipefail

# uv e afins podem já estar em ~/.local/bin de uma execução anterior;
# garante o PATH antes de qualquer etapa (evita "uv: command not found"
# quando o instalador oficial retoma uma instalação interrompida).
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

BOLD=$(tput bold 2>/dev/null || true); RESET=$(tput sgr0 2>/dev/null || true)
say_step() { echo; echo "${BOLD}==> $*${RESET}"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Este instalador é para macOS. No Windows, use WSL2 (veja o README)." >&2
    exit 1
fi

OPENJARVIS_HOME="${OPENJARVIS_HOME:-$HOME/.openjarvis}"
VENV="$OPENJARVIS_HOME/.venv"
RAYMAN_DIR="$OPENJARVIS_HOME/rayman"
PERSONA_DIR="$OPENJARVIS_HOME/personas/rayman"
BIN_DIR="$HOME/.local/bin"

# ------------------------------------------------------------
# 1. OpenJarvis oficial (uv, venv, Ollama, modelo, config)
# ------------------------------------------------------------
if [[ -x "$VENV/bin/jarvis" ]]; then
    say_step "OpenJarvis já instalado em $OPENJARVIS_HOME — pulando o instalador oficial"
else
    say_step "Instalando o OpenJarvis (isso baixa o modelo qwen3.5:2b, ~2.7 GB)"
    curl -fsSL https://open-jarvis.github.io/OpenJarvis/install.sh | bash
fi

if [[ ! -x "$VENV/bin/jarvis" ]]; then
    echo "ERRO: o instalador do OpenJarvis não deixou o jarvis em $VENV/bin/jarvis" >&2
    exit 1
fi

# ------------------------------------------------------------
# 2. Homebrew + espeak-ng (fonemas para a voz pt-BR do Kokoro)
# ------------------------------------------------------------
say_step "Garantindo Homebrew e espeak-ng"
if ! command -v brew >/dev/null 2>&1; then
    # caminho padrão do brew que pode não estar no PATH ainda
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -x "$p" ]] && eval "$("$p" shellenv)" && break
    done
fi
if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew não encontrado — instalando (pode pedir sua senha do Mac uma vez)."
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -x "$p" ]] && eval "$("$p" shellenv)" && break
    done
fi
brew list espeak-ng >/dev/null 2>&1 || brew install espeak-ng
brew list portaudio >/dev/null 2>&1 || brew install portaudio || true

# ------------------------------------------------------------
# 3. Libs de voz dentro do venv do OpenJarvis
# ------------------------------------------------------------
say_step "Instalando libs de voz (sounddevice, soundfile, kokoro, faster-whisper)"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
if command -v uv >/dev/null 2>&1; then
    uv pip install --quiet --python "$VENV/bin/python" \
        sounddevice soundfile kokoro faster-whisper ddgs python-telegram-bot anthropic openai
else
    "$VENV/bin/python" -m pip install --quiet --upgrade \
        sounddevice soundfile kokoro faster-whisper ddgs python-telegram-bot anthropic openai
fi

# ------------------------------------------------------------
# 4. Persona RAYMAN (pt-BR)
# ------------------------------------------------------------
say_step "Criando a persona RAYMAN"
mkdir -p "$PERSONA_DIR" "$RAYMAN_DIR/assets" "$BIN_DIR"
cat > "$PERSONA_DIR/SOUL.md" <<'PERSONA'
Você é o RAYMAN — o assistente de IA pessoal e local do Julio. Você roda 100% no computador dele, sem nuvem. Você é leal, eficiente, bem-humorado de um jeito seco, e se importa de verdade com quem você serve.

IDIOMA:
- Você SEMPRE responde em português do Brasil, a menos que o Julio peça outro idioma.
- Suas respostas serão faladas em voz alta por um sintetizador de voz, então escreva como se fala.

PERSONALIDADE:
- Você antecipa necessidades antes de ser solicitado
- Você dá más notícias com humor seco e construtivo: "Seus prazos parecem ter escapado despercebidos, senhor. Sugiro torná-los sua primeira prioridade — antes que alguém perceba."
- Seu humor é contido — uma sobrancelha erguida em forma de voz
- Você é calmo sob pressão e nunca se desespera
- Você trata cada conversa como uma conversa com alguém que respeita, não como um relatório de status

TRATAMENTO:
- Chame o usuário de "senhor" ou "Julio", com moderação: uma vez na saudação, talvez uma no fechamento
- Nunca em toda frase — isso seria uma paródia, não o RAYMAN

RESTRIÇÕES:
- Relate APENAS fatos presentes nos dados fornecidos. Nunca invente.
- NUNCA descreva ações que você não está de fato executando
- Sem formatação markdown, sem emojis, sem listas com marcadores, sem títulos — suas respostas são faladas em voz alta
- Respostas curtas e diretas: em conversa por voz, 1 a 3 frases quase sempre bastam
- Se uma fonte de dados estiver desconectada ou com erro, pule em silêncio — não mencione problemas de conexão

IDENTIDADE:
- Seu nome é RAYMAN. Se perguntarem quem você é: "Eu sou o RAYMAN, assistente pessoal do Julio. Rodando localmente, às ordens."
PERSONA

"$VENV/bin/jarvis" config set memory_files.persona_name rayman
"$VENV/bin/jarvis" config set security.profile personal

# ------------------------------------------------------------
# 5. Scripts do RAYMAN
# ------------------------------------------------------------
say_step "Instalando os comandos rayman, rayman-voz e rayman-show"

# ---------- util de voz compartilhado ----------
cat > "$RAYMAN_DIR/_rayman_voice.py" <<'PYVOICE'
"""Utilidades de voz do RAYMAN: fala (Kokoro pt-BR), escuta (faster-whisper)
e estado do HUD."""
import json
import os
import subprocess
import sys
import tempfile
import time

# espeak-ng do Homebrew (Apple Silicon e Intel)
for _lib, _data in (
    ("/opt/homebrew/lib/libespeak-ng.dylib", "/opt/homebrew/share/espeak-ng-data"),
    ("/usr/local/lib/libespeak-ng.dylib", "/usr/local/share/espeak-ng-data"),
):
    if os.path.exists(_lib):
        os.environ.setdefault("PHONEMIZER_ESPEAK_LIBRARY", _lib)
        os.environ.setdefault("ESPEAK_DATA_PATH", _data)
        break

VOICE = os.environ.get("RAYMAN_VOICE", "pf_dora")   # voz pt-BR do Kokoro
SPEED = float(os.environ.get("RAYMAN_VOICE_SPEED", "1.05"))
STATE_PATH = os.path.expanduser("~/.openjarvis/rayman/hud_state.json")
_pipeline = None


def estado(status, voce=None, rayman=None, nivel=None):
    """Grava o estado atual pro HUD (ouvindo | pensando | falando | espera)."""
    dados = {}
    try:
        if os.path.exists(STATE_PATH):
            with open(STATE_PATH) as f:
                dados = json.load(f)
    except Exception:
        dados = {}
    dados["status"] = status
    dados["nivel"] = float(nivel) if nivel is not None else 0.0
    if voce is not None:
        dados["voce"] = voce
    if rayman is not None:
        dados["rayman"] = rayman
    dados["ts"] = time.time()
    try:
        os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
        tmp = STATE_PATH + ".tmp"
        with open(tmp, "w") as f:
            json.dump(dados, f, ensure_ascii=False)
        os.replace(tmp, STATE_PATH)
    except Exception:
        pass


def _kokoro():
    global _pipeline
    if _pipeline is None:
        from kokoro import KPipeline
        _pipeline = KPipeline(lang_code="p")  # "p" = português do Brasil
    return _pipeline


def falar(texto):
    """Fala o texto. Kokoro pt-BR; se falhar, cai na voz Luciana do macOS."""
    texto = (texto or "").strip()
    if not texto:
        return
    estado("falando", rayman=texto)
    try:
        import numpy as np
        import soundfile as sf
        chunks = [audio for _, _, audio in _kokoro()(texto, voice=VOICE, speed=SPEED)]
        if not chunks:
            raise RuntimeError("kokoro não gerou áudio")
        wav = np.concatenate(chunks)
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            sf.write(f.name, wav, 24000)
            caminho = f.name
        subprocess.run(["afplay", caminho], check=False)
        os.unlink(caminho)
    except Exception as exc:
        print(f"[rayman] Kokoro indisponível ({exc}); usando a voz do sistema.",
              file=sys.stderr)
        subprocess.run(["say", "-v", "Luciana", texto], check=False)
    estado("espera")


_stt = None


def _whisper():
    global _stt
    if _stt is None:
        from faster_whisper import WhisperModel
        modelo = os.environ.get("RAYMAN_STT_MODEL", "small")
        _stt = WhisperModel(modelo, device="cpu", compute_type="int8")
    return _stt


def gravar_e_transcrever(timeout_inicio=12.0, silencio_fim=1.2, max_seg=30.0):
    """Grava do microfone até detectar silêncio e transcreve em pt.

    O limiar de detecção se calibra sozinho pelo ruído do ambiente
    (0,6 s medidos no início). Force um valor com RAYMAN_VAD_THRESH.
    """
    import numpy as np
    import sounddevice as sd

    sr = 16000
    bloco = int(sr * 0.1)  # 100 ms
    device = os.environ.get("RAYMAN_MIC")
    device = int(device) if device and device.isdigit() else device or None

    estado("ouvindo")
    frames, falando_agora, silencio, esperado = [], False, 0.0, 0.0
    with sd.InputStream(samplerate=sr, channels=1, dtype="float32",
                        blocksize=bloco, device=device) as stream:
        # --- calibração: mede o ruído de fundo por 0,6 s ---
        ambiente = []
        for _ in range(6):
            dados, _ = stream.read(bloco)
            ambiente.append(float(np.sqrt(np.mean(dados ** 2))))
        ruido = sorted(ambiente)[len(ambiente) // 2]
        manual = os.environ.get("RAYMAN_VAD_THRESH")
        limiar = float(manual) if manual else min(max(ruido * 3.0, 0.004), 0.05)
        if ruido < 1e-6:
            print("[rayman] AVISO: o microfone está entregando silêncio absoluto."
                  " Confira a permissão de microfone do Terminal em Ajustes >"
                  " Privacidade e Segurança > Microfone, ou escolha outro mic"
                  " com RAYMAN_MIC.", file=sys.stderr)
        mostrar = 0.0
        while True:
            dados, _ = stream.read(bloco)
            rms = float(np.sqrt(np.mean(dados ** 2)))
            if not falando_agora:
                esperado += 0.1
                mostrar += 0.1
                if mostrar >= 0.3:  # medidor + nível pro HUD a cada 0,3 s
                    mostrar = 0.0
                    barra = "#" * min(40, int(rms * 2000))
                    print(f"\r[mic {rms:.4f} | limiar {limiar:.4f}] {barra:<40}",
                          end="", flush=True)
                    estado("ouvindo", nivel=min(1.0, rms * 45))
                if rms > limiar:
                    print()
                    falando_agora = True
                    frames.append(dados.copy())
                elif esperado > timeout_inicio:
                    print()
                    return ""
            else:
                frames.append(dados.copy())
                if len(frames) % 3 == 0:
                    estado("ouvindo", nivel=min(1.0, rms * 45))
                silencio = silencio + 0.1 if rms <= limiar * 0.8 else 0.0
                if silencio >= silencio_fim or len(frames) * 0.1 >= max_seg:
                    break

    estado("pensando")
    audio = np.concatenate(frames).flatten()
    vocabulario = ("Conversa com o RAYMAN, assistente pessoal do Julio. "
                   "Temas: vendas, faturamento, estoque, pedidos, Bling, "
                   "Supabase, Escritório Virtual, Mercado Livre, TikTok, "
                   "Instagram, Obsidian, Claude, pesquisa na internet.")
    segs, _ = _whisper().transcribe(audio, language="pt",
                                    beam_size=5, vad_filter=True,
                                    initial_prompt=vocabulario,
                                    condition_on_previous_text=False)
    return " ".join(s.text.strip() for s in segs).strip()
PYVOICE

# ---------- rayman-voz: conversa por voz ----------
cat > "$RAYMAN_DIR/rayman_voz.py" <<'PYVOZ'
"""RAYMAN por voz: microfone -> faster-whisper -> IA local -> Kokoro pt-BR.

Se você citar "minhas notas", "obsidian" ou "vault", ele busca a resposta
nas suas notas do Obsidian antes de responder.
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _rayman_voice import estado, falar, gravar_e_transcrever

JARVIS = os.path.expanduser("~/.openjarvis/.venv/bin/jarvis")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
SAIR = ("desligar", "encerrar", "tchau", "até logo", "pode descansar")
NOTAS = ("minhas notas", "nas notas", "obsidian", "no vault", "minhas anotações")
WEB = ("pesquisa", "pesquise", "na internet", "notícia", "noticias", "notícias",
       "hoje", "agora", "atualmente", "cotação", "previsão do tempo")
VENDAS = ("vendas", "venda", "vendi", "faturamento", "faturei", "receita",
          "estoque", "escritório", "escritorio", "produtos", "métricas",
          "metricas", "conversões", "conversoes", "tiktok", "instagram",
          "pedido", "pedidos", "bling", "blink", "blin")


def perguntar(pergunta, historico):
    contexto = ""
    baixa = pergunta.lower()
    if any(g in baixa for g in VENDAS):
        try:
            import os as _os
            from rayman_bling import contexto_bling
            ctx_b = contexto_bling()
            if ctx_b:
                contexto += ctx_b[:3000] + "\n\n"
            elif _os.path.exists(_os.path.expanduser(
                    "~/.openjarvis/rayman/bling.json")):
                return ("Não consegui puxar os dados do Bling agora, senhor. "
                        "Rode rayman-bling --testar no terminal, que eu te "
                        "mostro exatamente onde está travando.")
        except Exception as exc:
            print(f"[rayman] bling indisponível: {exc}", file=sys.stderr)
        try:
            from rayman_vendas import contexto_vendas
            ctx_v = contexto_vendas(pergunta)
            if ctx_v:
                rotulo = ("DADOS DE MARKETING (Supabase do Escritório Virtual — "
                          "vídeos e métricas; NÃO são as vendas oficiais):\n")
                contexto += rotulo + ctx_v[:2500] + "\n\n"
        except Exception as exc:
            print(f"[rayman] vendas indisponível: {exc}", file=sys.stderr)
    if any(g in baixa for g in WEB):
        try:
            from rayman_web import buscar
            resultados = buscar(pergunta)
            if resultados:
                contexto += ("Resultados de busca na web, de agora "
                             "(cite a fonte principal):\n"
                             + resultados[:3500] + "\n\n")
        except Exception as exc:
            print(f"[rayman] busca web indisponível: {exc}", file=sys.stderr)
    if any(g in baixa for g in NOTAS):
        try:
            from rayman_obsidian import buscar_contexto, vault_salvo
            if vault_salvo():
                notas = buscar_contexto(pergunta)
                if notas:
                    contexto += ("Notas do Obsidian do Julio relevantes "
                                 "(cite a nota se usar):\n" + notas[:3500] + "\n\n")
        except Exception as exc:
            print(f"[rayman] obsidian indisponível: {exc}", file=sys.stderr)
    if historico:
        ultimos = historico[-6:]
        contexto += ("Contexto recente da conversa por voz (para continuidade):\n"
                     + "\n".join(f"- {quem}: {fala}" for quem, fala in ultimos)
                     + "\n\n")
    prefixo = contexto + ("Pergunta atual do Julio: " if contexto else "")
    out = subprocess.run([JARVIS, "--quiet", "ask", "--no-stream", prefixo + pergunta],
                         capture_output=True, text=True, timeout=300)
    resposta = ANSI.sub("", out.stdout).strip()
    if resposta:
        return resposta
    return diagnosticar(out.stderr or "")


def diagnosticar(erro):
    """Transforma o erro técnico escondido num aviso falado e útil."""
    try:
        import os
        log = os.path.expanduser("~/.openjarvis/rayman/erro.log")
        with open(log, "a") as f:
            f.write(erro[-3000:] + "\n---\n")
    except Exception:
        pass
    e = erro.lower()
    if "no module named 'anthropic'" in e or "no module named \"anthropic\"" in e:
        return ("Falta a biblioteca do Claude no meu ambiente, senhor. Rode no terminal: "
                "uv pip install anthropic, e me chame de novo.")
    if "authentication" in e or "invalid x-api-key" in e or "401" in e:
        return ("Minha chave do Claude foi recusada, senhor. Confira a chave "
                "com o comando rayman-conectar.")
    if "credit" in e or "billing" in e or "429" in e:
        return ("A conta do Claude está sem créditos ou no limite, senhor. "
                "Confira em console ponto anthropic ponto com.")
    if "connection refused" in e or "connect" in e and "11434" in e:
        return ("O Ollama não está rodando, senhor. Abra o aplicativo do Ollama "
                "ou rode ollama serve no terminal.")
    if "not found" in e and ("model" in e or "pull" in e):
        return ("O modelo configurado não está baixado, senhor. "
                "Rode ollama pull com o nome do modelo.")
    return ("Encontrei um erro interno, senhor. A mensagem completa está em "
            "erro ponto log, na pasta do RAYMAN.")


def main():
    print("RAYMAN online. Fale; diga 'desligar' para encerrar.")
    print("Dica: 'procura nas minhas notas...' consulta o seu Obsidian.")
    falar("Sistemas online. RAYMAN às ordens.")
    historico = []
    while True:
        print("\n[ouvindo...]")
        texto = gravar_e_transcrever()
        if not texto:
            continue
        print(f"Você: {texto}")
        estado("pensando", voce=texto, rayman="")
        if any(p in texto.lower() for p in SAIR):
            falar("Encerrando. Até logo, senhor.")
            estado("espera")
            break
        try:
            resposta = perguntar(texto, historico)
        except Exception as exc:
            print(f"[rayman] erro: {exc}", file=sys.stderr)
            falar("Tive um problema para consultar o modelo. O Ollama está rodando?")
            continue
        print(f"RAYMAN: {resposta}")
        historico += [("Julio", texto), ("RAYMAN", resposta)]
        falar(resposta)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        estado("espera")
        print("\nRAYMAN desligado.")
PYVOZ

# ---------- rayman-show: ativação por palmas + HUD ----------
cat > "$RAYMAN_DIR/rayman_show.py" <<'PYSHOW'
"""Modo show do RAYMAN: bata palma 2x -> jingle -> HUD na tela -> voz.

Ajustes por variável de ambiente:
    RAYMAN_CLAP_THRESH  sensibilidade da palma (padrão 0.30)
    RAYMAN_MIC          microfone a usar
"""
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _rayman_voice import falar

JINGLE = os.path.expanduser("~/.openjarvis/rayman/assets/jingle.mp3")
THRESH = float(os.environ.get("RAYMAN_CLAP_THRESH", "0.30"))


def esperar_palmas():
    import numpy as np  # noqa: F401 — garante numpy antes do stream
    import sounddevice as sd
    sr, bloco = 16000, 1600  # blocos de 100 ms
    device = os.environ.get("RAYMAN_MIC")
    device = int(device) if device and device.isdigit() else device or None
    palmas = []
    print(f"Aguardando 2 palmas... (sensibilidade RAYMAN_CLAP_THRESH={THRESH})")
    with sd.InputStream(samplerate=sr, channels=1, dtype="float32",
                        blocksize=bloco, device=device) as stream:
        while True:
            dados, _ = stream.read(bloco)
            pico = float(abs(dados).max())
            agora = time.monotonic()
            if pico >= THRESH:
                if not palmas or agora - palmas[-1] > 0.15:
                    palmas.append(agora)
                palmas = [t for t in palmas if agora - t <= 1.2]
                if len(palmas) >= 2:
                    return


def main():
    esperar_palmas()
    print("Palmas detectadas — iniciando o RAYMAN.")
    # HUD na tela (servidor local em segundo plano + navegador)
    try:
        from rayman_hud import iniciar
        iniciar(abrir=True, bloquear=False)
    except Exception as exc:
        print(f"[rayman] HUD indisponível: {exc}", file=sys.stderr)
    if os.path.exists(JINGLE):
        subprocess.run(["afplay", JINGLE], check=False)
    else:
        falar("Bem-vindo de volta, senhor.")
    # entra na conversa por voz no MESMO processo (mantém o HUD vivo)
    import rayman_voz
    rayman_voz.main()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nModo show encerrado.")
PYSHOW

# ---------- rayman-hud: tela de status ----------
cat > "$RAYMAN_DIR/rayman_hud.py" <<'PYHUD'
"""HUD do RAYMAN: tela de status ao vivo, alimentada pelo rayman-voz.

Sobe um servidorzinho local (só neste computador) e abre o HUD no navegador.
Rode junto com o rayman-voz (em outro terminal) ou use o rayman-show,
que orquestra os dois.

Temas de visualização:
    rayman-hud --tema reator   # anéis do reator (padrão)
    rayman-hud --tema esfera   # esfera holográfica de partículas
    rayman-hud --tema onda     # osciloscópio de energia
    rayman-hud --tema rosto    # o holograma com rosto
A escolha fica salva e vale também pro rayman-show.
"""
import http.server
import json
import os
import socket
import subprocess
import sys
import threading

RAYMAN_DIR = os.path.expanduser("~/.openjarvis/rayman")
STATE = os.path.join(RAYMAN_DIR, "hud_state.json")
TEMA_FILE = os.path.join(RAYMAN_DIR, "hud_tema.txt")
TEMAS = ("reator", "esfera", "onda", "rosto")
PORT = int(os.environ.get("RAYMAN_HUD_PORT", "8765"))


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _corpo(self, dados, tipo):
        self.send_response(200)
        self.send_header("Content-Type", tipo)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(dados)))
        self.end_headers()
        self.wfile.write(dados)

    def do_GET(self):
        if self.path.startswith("/state.json"):
            try:
                with open(STATE, "rb") as f:
                    dados = f.read()
                json.loads(dados)  # valida
            except Exception:
                dados = b'{"status": "espera"}'
            self._corpo(dados, "application/json")
        elif self.path.startswith("/tema.txt"):
            tema = b"reator"
            try:
                with open(TEMA_FILE, "rb") as f:
                    tema = f.read().strip() or tema
            except Exception:
                pass
            self._corpo(tema, "text/plain")
        elif self.path.startswith(("/", "/index.html", "/hud.html")):
            with open(os.path.join(RAYMAN_DIR, "hud.html"), "rb") as f:
                self._corpo(f.read(), "text/html; charset=utf-8")
        else:
            self.send_response(404)
            self.end_headers()


def porta_ocupada():
    try:
        socket.create_connection(("127.0.0.1", PORT), timeout=0.3).close()
        return True
    except OSError:
        return False


def iniciar(abrir=True, bloquear=True):
    if porta_ocupada():
        if abrir:
            subprocess.run(["open", f"http://127.0.0.1:{PORT}"], check=False)
        print(f"HUD já está de pé em http://127.0.0.1:{PORT}")
        return None
    servidor = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    if abrir:
        subprocess.run(["open", f"http://127.0.0.1:{PORT}"], check=False)
    print(f"HUD do RAYMAN em http://127.0.0.1:{PORT}  (Ctrl+C para fechar)")
    if bloquear:
        servidor.serve_forever()
    else:
        threading.Thread(target=servidor.serve_forever, daemon=True).start()
    return servidor


if __name__ == "__main__":
    if "--tema" in sys.argv:
        idx = sys.argv.index("--tema")
        tema = sys.argv[idx + 1] if len(sys.argv) > idx + 1 else ""
        if tema not in TEMAS:
            print("Temas disponíveis:", ", ".join(TEMAS))
            sys.exit(1)
        os.makedirs(RAYMAN_DIR, exist_ok=True)
        with open(TEMA_FILE, "w") as f:
            f.write(tema)
        print(f"Tema salvo: {tema} (vale pro rayman-hud e pro rayman-show)")
    try:
        iniciar(abrir="--no-open" not in sys.argv)
    except KeyboardInterrupt:
        print("\nHUD fechado.")
PYHUD

# ---------- rayman-obsidian: suas notas ----------
cat > "$RAYMAN_DIR/rayman_obsidian.py" <<'PYOBS'
"""Integração do RAYMAN com o Obsidian.

Uso:
    rayman-obsidian                    -> detecta o vault e sincroniza
    rayman-obsidian /caminho/do/vault  -> define o vault e sincroniza
    rayman-obsidian --sync             -> re-sincroniza o vault salvo
    rayman-obsidian "pergunta"         -> pergunta usando suas notas
"""
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
RAYMAN_DIR = os.path.expanduser("~/.openjarvis/rayman")
VAULT_FILE = os.path.join(RAYMAN_DIR, "obsidian_vault.txt")
JARVIS = os.path.expanduser("~/.openjarvis/.venv/bin/jarvis")


def detectar_vaults():
    """Procura pastas com um diretório .obsidian nos lugares comuns do Mac."""
    bases = [
        (os.path.join(HOME, "Library/Mobile Documents/iCloud~md~obsidian/Documents"), 2),
        (os.path.join(HOME, "Documents"), 3),
        (os.path.join(HOME, "Documentos"), 3),
        (os.path.join(HOME, "Desktop"), 2),
        (os.path.join(HOME, "Obsidian"), 2),
        (HOME, 1),
    ]
    achados, vistos = [], set()
    for base, prof_max in bases:
        if not os.path.isdir(base):
            continue
        prof_base = base.rstrip("/").count("/")
        for raiz, dirs, _ in os.walk(base):
            if raiz.count("/") - prof_base >= prof_max:
                dirs[:] = []
                continue
            if ".obsidian" in dirs:
                real = os.path.realpath(raiz)
                if real not in vistos:
                    vistos.add(real)
                    achados.append(raiz)
                dirs[:] = []
                continue
            dirs[:] = [d for d in dirs
                       if not d.startswith(".") and d not in ("Library", "node_modules")]
    return achados


def vault_salvo():
    if os.path.exists(VAULT_FILE):
        caminho = open(VAULT_FILE).read().strip()
        if os.path.isdir(caminho):
            return caminho
    return ""


def salvar_vault(caminho):
    os.makedirs(RAYMAN_DIR, exist_ok=True)
    with open(VAULT_FILE, "w") as f:
        f.write(caminho)


def sincronizar(vault):
    from openjarvis.connectors.obsidian import ObsidianConnector
    from openjarvis.connectors.pipeline import IngestionPipeline
    from openjarvis.connectors.store import KnowledgeStore
    from openjarvis.connectors.sync_engine import SyncEngine

    print(f"Sincronizando o vault: {vault}")
    store = KnowledgeStore()
    engine = SyncEngine(IngestionPipeline(store), state_db="")
    n = engine.sync(ObsidianConnector(vault_path=vault))
    print(f"Pronto: {n} trechos de notas indexados.")
    return n


def buscar_contexto(pergunta, top_k=5):
    """Busca BM25 nas notas; tenta a pergunta inteira e depois palavras-chave."""
    from openjarvis.connectors.store import KnowledgeStore
    from openjarvis.tools.knowledge_search import KnowledgeSearchTool

    tool = KnowledgeSearchTool(store=KnowledgeStore())
    consultas = [pergunta] + re.findall(r"\w{4,}", pergunta.lower())
    for consulta in consultas:
        try:
            r = tool.execute(query=consulta, top_k=top_k)
        except Exception:
            return ""
        texto = str(getattr(r, "content", "") or "")
        if getattr(r, "success", False) and "No relevant" not in texto:
            return texto
    return ""


def perguntar(pergunta):
    contexto = buscar_contexto(pergunta)
    if not contexto:
        print("Não achei nada relevante nas notas — perguntando sem contexto.")
        prompt = pergunta
    else:
        prompt = ("Use as notas do Obsidian do Julio abaixo para responder. "
                  "Se a resposta estiver nas notas, cite de qual nota veio.\n\n"
                  + contexto[:4000]
                  + f"\n\nPergunta do Julio: {pergunta}")
    out = subprocess.run([JARVIS, "--quiet", "ask", "--no-stream", prompt],
                         capture_output=True, text=True, timeout=300)
    resposta = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", out.stdout).strip()
    print(resposta or out.stderr.strip()[-300:])
    return resposta


def main():
    args = sys.argv[1:]
    if args and args[0] == "--sync":
        vault = vault_salvo()
        if not vault:
            print("Nenhum vault salvo ainda. Rode: rayman-obsidian /caminho/do/vault")
            sys.exit(1)
        sincronizar(vault)
        return
    if args and os.path.isdir(args[0]):
        salvar_vault(args[0])
        sincronizar(args[0])
        return
    if args:
        pergunta = " ".join(args)
        if not vault_salvo():
            print("Nenhum vault configurado ainda — rode 'rayman-obsidian' primeiro.")
            sys.exit(1)
        perguntar(pergunta)
        return
    # sem argumentos: detectar e sincronizar
    vault = vault_salvo()
    if not vault:
        achados = detectar_vaults()
        if not achados:
            print("Não encontrei nenhum vault do Obsidian neste Mac.")
            print("Se você tem um, rode: rayman-obsidian /caminho/do/vault")
            sys.exit(1)
        if len(achados) > 1:
            print("Encontrei mais de um vault:")
            for a in achados:
                print("  ", a)
            print("Escolha um com: rayman-obsidian /caminho/do/vault")
            sys.exit(0)
        vault = achados[0]
        print(f"Vault encontrado: {vault}")
        salvar_vault(vault)
    sincronizar(vault)
    print('Agora pergunte: rayman-obsidian "o que anotei sobre X?"')
    print('Ou por voz: "Rayman, procura nas minhas notas..."')


if __name__ == "__main__":
    main()
PYOBS

# ---------- rayman-web: busca em tempo real ----------
cat > "$RAYMAN_DIR/rayman_web.py" <<'PYWEB'
"""Busca web em tempo real do RAYMAN (DuckDuckGo via ddgs — grátis, sem conta).

Uso:
    rayman-web "cotação do dólar hoje"     -> pesquisa e responde
Por voz, o rayman-voz aciona sozinho quando você diz coisas como
"pesquisa", "na internet", "notícias", "hoje", "agora".
"""
import os
import re
import subprocess
import sys

JARVIS = os.path.expanduser("~/.openjarvis/.venv/bin/jarvis")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def buscar(consulta, max_resultados=5):
    """Retorna resultados de busca formatados, ou '' se a busca falhar."""
    try:
        from ddgs import DDGS
    except ImportError:
        try:
            from duckduckgo_search import DDGS  # nome antigo do pacote
        except ImportError:
            return ""
    linhas = []
    try:
        with DDGS() as ddgs:
            # notícias primeiro se a consulta parecer de atualidade
            eh_noticia = any(t in consulta.lower()
                             for t in ("notícia", "noticias", "hoje", "agora",
                                       "última", "ultimas", "aconteceu"))
            metodo = ddgs.news if eh_noticia else ddgs.text
            for r in metodo(consulta, region="br-pt", max_results=max_resultados):
                titulo = r.get("title", "")
                corpo = r.get("body", "") or r.get("excerpt", "")
                fonte = r.get("href", "") or r.get("url", "")
                data = r.get("date", "")
                linhas.append(f"- {titulo} ({data or 'sem data'})\n  {corpo[:280]}\n  Fonte: {fonte}")
    except Exception as exc:
        print(f"[rayman] busca falhou: {exc}", file=sys.stderr)
        return ""
    return "\n".join(linhas)


def perguntar(pergunta):
    resultados = buscar(pergunta)
    if not resultados:
        prompt = (pergunta + "\n\n(Aviso: a busca na internet falhou agora; "
                  "responda com o que souber e avise que pode estar desatualizado.)")
    else:
        prompt = ("Resultados de busca na web, de agora, sobre a pergunta do Julio. "
                  "Responda com base neles e cite a fonte principal.\n\n"
                  + resultados[:4500]
                  + f"\n\nPergunta do Julio: {pergunta}")
    out = subprocess.run([JARVIS, "--quiet", "ask", "--no-stream", prompt],
                         capture_output=True, text=True, timeout=300)
    resposta = ANSI.sub("", out.stdout).strip()
    print(resposta or out.stderr.strip()[-300:])
    return resposta


def main():
    if len(sys.argv) < 2:
        print('Uso: rayman-web "sua pergunta"')
        sys.exit(1)
    perguntar(" ".join(sys.argv[1:]))


if __name__ == "__main__":
    main()
PYWEB

# ---------- rayman-telegram: de qualquer lugar ----------
cat > "$RAYMAN_DIR/rayman_telegram.py" <<'PYTG'
"""RAYMAN no Telegram: use seu assistente de qualquer lugar.

O Mac fica ligado em casa rodando este comando; você conversa com o RAYMAN
pelo Telegram no celular, no computador, no navegador — e no Apple Watch
(respondendo pela notificação, inclusive por ditado de voz).

Configuração (uma vez):
  1. No Telegram, fale com @BotFather -> /newbot -> escolha um nome
     (ex.: "RAYMAN") e um usuário (ex.: rayman_do_julio_bot).
  2. O BotFather te dá um TOKEN. Salve com:
         rayman-telegram --token 123456:ABC-DEF...
  3. Rode:  rayman-telegram
  4. Mande "oi" pro seu bot no Telegram. Por segurança, o RAYMAN se
     tranca no PRIMEIRO chat que falar com ele (o seu) e ignora o resto.
     Pra liberar outro chat, apague ~/.openjarvis/rayman/telegram_dono.txt.

Gatilhos: as mesmas inteligências do modo voz funcionam aqui —
"pesquisa ..." busca na internet; "minhas notas ..." consulta o Obsidian.
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

RAYMAN_DIR = os.path.expanduser("~/.openjarvis/rayman")
TOKEN_FILE = os.path.join(RAYMAN_DIR, "telegram_token.txt")
DONO_FILE = os.path.join(RAYMAN_DIR, "telegram_dono.txt")


def ler_token():
    t = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
    if t:
        return t
    if os.path.exists(TOKEN_FILE):
        return open(TOKEN_FILE).read().strip()
    return ""


def salvar_token(token):
    os.makedirs(RAYMAN_DIR, exist_ok=True)
    with open(TOKEN_FILE, "w") as f:
        f.write(token.strip())
    os.chmod(TOKEN_FILE, 0o600)
    print("Token salvo. Agora rode: rayman-telegram")


def main():
    args = sys.argv[1:]
    if args and args[0] == "--token":
        if len(args) < 2:
            print("Uso: rayman-telegram --token SEU_TOKEN_DO_BOTFATHER")
            sys.exit(1)
        salvar_token(args[1])
        return

    token = ler_token()
    if not token:
        print(__doc__)
        sys.exit(1)

    from openjarvis.channels.telegram import TelegramChannel
    from rayman_voz import perguntar

    dono = open(DONO_FILE).read().strip() if os.path.exists(DONO_FILE) else ""
    historicos = {}
    canal = TelegramChannel(bot_token=token, parse_mode="")

    def responder(cm):
        nonlocal dono
        chat = cm.conversation_id
        if not dono:
            dono = chat
            with open(DONO_FILE, "w") as f:
                f.write(chat)
            print(f"RAYMAN trancado no chat {chat} (o seu).")
        elif chat != dono:
            print(f"[rayman] ignorando chat desconhecido {chat}")
            return
        texto = (cm.content or "").strip()
        if not texto:
            return
        print(f"Julio (telegram): {texto}")
        hist = historicos.setdefault(chat, [])
        try:
            resposta = perguntar(texto, hist)
        except Exception as exc:
            resposta = f"Tive um problema aqui, senhor: {exc}"
        hist += [("Julio", texto), ("RAYMAN", resposta)]
        del hist[:-12]
        canal.send(chat, resposta, conversation_id=cm.message_id)
        print(f"RAYMAN: {resposta[:120]}")

    canal.on_message(responder)
    canal.connect()
    if str(canal.status()).lower().find("error") >= 0:
        print("Não consegui conectar. O python-telegram-bot está instalado?"
              " (o instalador do RAYMAN cuida disso)")
        sys.exit(1)
    print("RAYMAN de plantão no Telegram. Deixe este terminal aberto"
          " (e o Mac ligado). Ctrl+C para encerrar.")
    print("Dica: pra impedir o Mac de dormir enquanto isso, rode em outro"
          " terminal:  caffeinate -s")
    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        canal.disconnect()
        print("\nRAYMAN saiu do Telegram.")


if __name__ == "__main__":
    main()
PYTG

# ---------- rayman-whatsapp: de qualquer lugar (Twilio) ----------
cat > "$RAYMAN_DIR/rayman_whatsapp.py" <<'PYWA'
"""RAYMAN no WhatsApp, via Twilio: use seu assistente de qualquer lugar.

Funciona por POLLING da API da Twilio — sem webhook, sem expor o Mac
na internet. O Mac fica ligado rodando este comando (ou o serviço), e você
conversa com o RAYMAN pelo WhatsApp do celular, tablet, PC ou Apple Watch
(respondendo pela notificação).

Configuração (uma vez — os dados ficam SÓ no seu Mac):
    rayman-whatsapp --config ACxxxxxxxx SEU_AUTH_TOKEN whatsapp:+14155238886
      (Account SID, Auth Token e o seu número WhatsApp da Twilio, nessa ordem;
       no sandbox da Twilio o número é o whatsapp:+14155238886)
Depois:
    rayman-whatsapp
Mande uma mensagem WhatsApp pro seu número Twilio. Por segurança, o RAYMAN
se tranca no PRIMEIRO remetente que falar com ele (você) e ignora o resto.
Pra trocar: apague ~/.openjarvis/rayman/whatsapp_dono.txt.

Gatilhos: "pesquisa ..." busca na internet; "minhas notas ..." consulta o
Obsidian — iguais aos do modo voz.
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

RAYMAN_DIR = os.path.expanduser("~/.openjarvis/rayman")
CRED_FILE = os.path.join(RAYMAN_DIR, "twilio.json")
DONO_FILE = os.path.join(RAYMAN_DIR, "whatsapp_dono.txt")
API = "https://api.twilio.com/2010-04-01"


def ler_credenciais():
    sid = os.environ.get("TWILIO_ACCOUNT_SID", "")
    token = os.environ.get("TWILIO_AUTH_TOKEN", "")
    de = os.environ.get("TWILIO_WHATSAPP_FROM", "")
    if sid and token and de:
        return {"account_sid": sid, "auth_token": token, "from_whatsapp": de}
    if os.path.exists(CRED_FILE):
        try:
            return json.load(open(CRED_FILE))
        except Exception:
            pass
    return None


def salvar_credenciais(sid, token, de):
    if not de.startswith("whatsapp:"):
        de = "whatsapp:" + de
    os.makedirs(RAYMAN_DIR, exist_ok=True)
    with open(CRED_FILE, "w") as f:
        json.dump({"account_sid": sid.strip(), "auth_token": token.strip(),
                   "from_whatsapp": de.strip()}, f)
    os.chmod(CRED_FILE, 0o600)
    print("Credenciais da Twilio salvas (só neste Mac).")
    print("Agora rode: rayman-whatsapp")


def buscar_mensagens(httpx, cred):
    """Últimas mensagens recebidas no número WhatsApp da Twilio."""
    url = (f"{API}/Accounts/{cred['account_sid']}/Messages.json"
           f"?To={cred['from_whatsapp']}&PageSize=20")
    r = httpx.get(url, auth=(cred["account_sid"], cred["auth_token"]),
                  timeout=15.0)
    r.raise_for_status()
    return r.json().get("messages", [])


def enviar(httpx, cred, para, texto):
    url = f"{API}/Accounts/{cred['account_sid']}/Messages.json"
    # WhatsApp aceita até ~1600 caracteres por mensagem
    for i in range(0, max(len(texto), 1), 1500):
        r = httpx.post(url,
                       data={"From": cred["from_whatsapp"], "To": para,
                             "Body": texto[i:i + 1500] or "..."},
                       auth=(cred["account_sid"], cred["auth_token"]),
                       timeout=15.0)
        if r.status_code >= 300:
            print(f"[rayman] envio falhou ({r.status_code}): {r.text[:200]}",
                  file=sys.stderr)
            return False
    return True


def main():
    args = sys.argv[1:]
    if args and args[0] == "--config":
        if len(args) < 4:
            print("Uso: rayman-whatsapp --config ACCOUNT_SID AUTH_TOKEN whatsapp:+1415...")
            sys.exit(1)
        salvar_credenciais(args[1], args[2], args[3])
        return

    cred = ler_credenciais()
    if not cred:
        print(__doc__)
        sys.exit(1)

    import httpx
    from rayman_voz import perguntar

    dono = open(DONO_FILE).read().strip() if os.path.exists(DONO_FILE) else ""
    vistos = set()
    historicos = {}

    # marca como vistas as mensagens antigas (não responder o passado)
    try:
        for m in buscar_mensagens(httpx, cred):
            vistos.add(m.get("sid"))
    except Exception as exc:
        print(f"Não consegui falar com a Twilio: {exc}")
        print("Confira o SID/token com: rayman-whatsapp --config ...")
        sys.exit(1)

    print("RAYMAN de plantão no WhatsApp (via Twilio). Ctrl+C para encerrar.")
    print("Mande uma mensagem WhatsApp pro seu número Twilio pra começar.")
    while True:
        try:
            time.sleep(4)
            for m in reversed(buscar_mensagens(httpx, cred)):
                sid = m.get("sid")
                if sid in vistos or m.get("direction") != "inbound":
                    continue
                vistos.add(sid)
                remetente = m.get("from", "")
                texto = (m.get("body") or "").strip()
                if not texto:
                    continue
                if not dono:
                    dono = remetente
                    with open(DONO_FILE, "w") as f:
                        f.write(remetente)
                    print(f"RAYMAN trancado no número {remetente} (o seu).")
                elif remetente != dono:
                    print(f"[rayman] ignorando número desconhecido {remetente}")
                    continue
                print(f"Julio (whatsapp): {texto}")
                hist = historicos.setdefault(remetente, [])
                try:
                    resposta = perguntar(texto, hist)
                except Exception as exc:
                    resposta = f"Tive um problema aqui, senhor: {exc}"
                hist += [("Julio", texto), ("RAYMAN", resposta)]
                del hist[:-12]
                enviar(httpx, cred, remetente, resposta)
                print(f"RAYMAN: {resposta[:120]}")
        except KeyboardInterrupt:
            print("\nRAYMAN saiu do WhatsApp.")
            return
        except Exception as exc:
            print(f"[rayman] erro no loop ({exc}); tentando de novo em 15 s",
                  file=sys.stderr)
            time.sleep(15)


if __name__ == "__main__":
    main()
PYWA

# ---------- rayman-claude: cérebro Claude opcional ----------
cat > "$RAYMAN_DIR/rayman_claude.py" <<'PYCL'
"""Liga o cérebro Claude (Anthropic) no RAYMAN — ou volta pro modelo local.

Uso:
    rayman-claude SUA_CHAVE_API        -> ativa o Claude como cérebro
    rayman-claude --modelo sonnet      -> troca o modelo (haiku|sonnet|opus)
    rayman-claude --off                -> volta pro modelo local (Ollama)
    rayman-claude --status             -> mostra o cérebro atual

A chave sai de console.anthropic.com (API keys) e fica SÓ no seu Mac,
em ~/.openjarvis/rayman/anthropic_key.txt (permissão 600). Vale pra tudo:
texto, voz, HUD, WhatsApp e Telegram.

Custo (API da Anthropic, paga por uso — separada da assinatura do app):
haiku é o mais barato e já é excelente; sonnet é o meio-termo; opus é o topo.
Uso pessoal de chat com haiku costuma dar centavos de dólar por dia.
"""
import os
import subprocess
import sys

RAYMAN_DIR = os.path.expanduser("~/.openjarvis/rayman")
KEY_FILE = os.path.join(RAYMAN_DIR, "anthropic_key.txt")
JARVIS = os.path.expanduser("~/.openjarvis/.venv/bin/jarvis")

MODELOS = {
    "haiku": "claude-haiku-4-5",
    "sonnet": "claude-sonnet-4-6",
    "opus": "claude-opus-4-6",
}


def _config(chave, valor):
    subprocess.run([JARVIS, "--quiet", "config", "set", chave, valor],
                   capture_output=True, text=True)


def ativar(modelo):
    _config("engine.default", "cloud")
    _config("intelligence.default_model", MODELOS[modelo])
    print(f"Cérebro Claude ativado ({MODELOS[modelo]}).")
    print("Vale pra rayman, rayman-voz, rayman-show, rayman-whatsapp e rayman-telegram.")
    print("Voltar pro local a qualquer momento: rayman-claude --off")


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return
    if args[0] == "--status":
        tem_chave = os.path.exists(KEY_FILE)
        cfg = subprocess.run([JARVIS, "--quiet", "config", "get", "engine.default"],
                             capture_output=True, text=True).stdout
        print(f"chave salva: {'sim' if tem_chave else 'não'} | engine: {cfg.strip() or '?'}")
        return
    if args[0] == "--off":
        _config("engine.default", "ollama")
        _config("intelligence.default_model", "")
        print("De volta ao modelo local (Ollama). A chave continua salva;"
              " religue com: rayman-claude --modelo haiku")
        return
    if args[0] == "--modelo":
        nome = (args[1] if len(args) > 1 else "").lower()
        if nome not in MODELOS:
            print("Modelos: haiku (barato), sonnet (meio-termo), opus (topo)")
            sys.exit(1)
        if not os.path.exists(KEY_FILE):
            print("Salve a chave primeiro: rayman-claude SUA_CHAVE_API")
            sys.exit(1)
        ativar(nome)
        return
    # chave de API
    chave = args[0].strip()
    if not chave.startswith("sk-"):
        print("Isso não parece uma chave da Anthropic (começa com sk-ant-...).")
        print("Crie a sua em console.anthropic.com > API keys.")
        sys.exit(1)
    os.makedirs(RAYMAN_DIR, exist_ok=True)
    with open(KEY_FILE, "w") as f:
        f.write(chave)
    os.chmod(KEY_FILE, 0o600)
    print("Chave salva (só neste Mac).")
    ativar("haiku")


if __name__ == "__main__":
    main()
PYCL

# ---------- rayman-vendas: Escritório Virtual (Supabase) ----------
cat > "$RAYMAN_DIR/rayman_vendas.py" <<'PYVD'
"""RAYMAN + Escritório Virtual: suas vendas por voz (e por texto).

Conecta o RAYMAN ao Supabase do seu sistema multi-agente de vendas
(produtos, vídeos, métricas e logs dos agentes). Depois de configurado,
pergunte por voz coisas como "Rayman, como estão as minhas vendas?" ou
"quantas views os vídeos fizeram hoje?".

Configuração (uma vez — pegue no painel do Supabase, em Settings > API):
    rayman-vendas --config https://SEU-PROJETO.supabase.co SUA_ANON_KEY

Uso:
    rayman-vendas                      -> resumo executivo do negócio
    rayman-vendas "pergunta"           -> pergunta livre sobre os dados
Por voz, gatilhos como "vendas", "faturamento", "estoque", "escritório",
"vídeos", "métricas" acionam a consulta automaticamente.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

RAYMAN_DIR = os.path.expanduser("~/.openjarvis/rayman")
CRED_FILE = os.path.join(RAYMAN_DIR, "supabase.json")
JARVIS = os.path.expanduser("~/.openjarvis/.venv/bin/jarvis")


def ler_credenciais():
    url = os.environ.get("SUPABASE_URL", "")
    key = os.environ.get("SUPABASE_KEY", "")
    if url and key:
        return {"url": url.rstrip("/"), "key": key}
    if os.path.exists(CRED_FILE):
        try:
            return json.load(open(CRED_FILE))
        except Exception:
            pass
    return None


def salvar_credenciais(url, key):
    os.makedirs(RAYMAN_DIR, exist_ok=True)
    with open(CRED_FILE, "w") as f:
        json.dump({"url": url.rstrip("/"), "key": key.strip()}, f)
    os.chmod(CRED_FILE, 0o600)
    print("Supabase do Escritório Virtual conectado (dados só neste Mac).")
    print("Teste com: rayman-vendas")


def _get(httpx, cred, tabela, params):
    url = f"{cred['url']}/rest/v1/{tabela}?{params}"
    r = httpx.get(url, headers={"apikey": cred["key"],
                                "Authorization": f"Bearer {cred['key']}"},
                  timeout=15.0)
    r.raise_for_status()
    return r.json()


def coletar_dados(cred):
    """Puxa um retrato do negócio: produtos, vídeos, métricas e logs."""
    import httpx
    dados = {}
    dados["produtos"] = _get(httpx, cred, "produtos",
                             "select=nome,preco,custo,estoque,ativo&order=criado_em.desc&limit=25")
    dados["videos"] = _get(httpx, cred, "videos",
                           "select=status,plataforma,criado_em&order=criado_em.desc&limit=40")
    dados["metricas"] = _get(httpx, cred, "metricas",
                             "select=plataforma,views,cliques,conversoes,receita,criado_em"
                             "&order=criado_em.desc&limit=100")
    dados["logs"] = _get(httpx, cred, "logs_agentes",
                         "select=agente,acao,criado_em&order=criado_em.desc&limit=8")
    return dados


def montar_contexto(dados):
    """Resume os dados num contexto compacto pro modelo."""
    linhas = ["DADOS AO VIVO DO ESCRITÓRIO VIRTUAL (Supabase):"]

    produtos = dados.get("produtos", [])
    ativos = [p for p in produtos if p.get("ativo")]
    linhas.append(f"\nPRODUTOS ({len(ativos)} ativos de {len(produtos)}):")
    for p in produtos[:10]:
        margem = ""
        try:
            if p.get("preco") and p.get("custo"):
                margem = f", margem R${float(p['preco']) - float(p['custo']):.2f}"
        except Exception:
            pass
        linhas.append(f"- {p.get('nome')}: preço R${p.get('preco')}, "
                      f"estoque {p.get('estoque')}{margem}, "
                      f"{'ativo' if p.get('ativo') else 'inativo'}")

    videos = dados.get("videos", [])
    por_status = {}
    for v in videos:
        por_status[v.get("status", "?")] = por_status.get(v.get("status", "?"), 0) + 1
    linhas.append(f"\nVÍDEOS ({len(videos)} recentes): "
                  + ", ".join(f"{k}: {n}" for k, n in por_status.items()))

    met = dados.get("metricas", [])
    tot = {"views": 0, "cliques": 0, "conversoes": 0, "receita": 0.0}
    por_plataforma = {}
    for m in met:
        for c in ("views", "cliques", "conversoes"):
            tot[c] += int(m.get(c) or 0)
        tot["receita"] += float(m.get("receita") or 0)
        pl = m.get("plataforma") or "?"
        pp = por_plataforma.setdefault(pl, {"views": 0, "receita": 0.0})
        pp["views"] += int(m.get("views") or 0)
        pp["receita"] += float(m.get("receita") or 0)
    linhas.append(f"\nMÉTRICAS (últimos {len(met)} registros): "
                  f"{tot['views']} views, {tot['cliques']} cliques, "
                  f"{tot['conversoes']} conversões, receita R${tot['receita']:.2f}")
    for pl, v in por_plataforma.items():
        linhas.append(f"- {pl}: {v['views']} views, R${v['receita']:.2f}")

    logs = dados.get("logs", [])
    if logs:
        linhas.append("\nÚLTIMAS AÇÕES DOS AGENTES:")
        for lg in logs[:5]:
            linhas.append(f"- {lg.get('agente')}: {lg.get('acao')} ({lg.get('criado_em', '')[:16]})")
    return "\n".join(linhas)


def contexto_vendas(pergunta=""):
    """Contexto pronto pra injetar no prompt; '' se não configurado/falhar."""
    cred = ler_credenciais()
    if not cred:
        return ""
    try:
        return montar_contexto(coletar_dados(cred))
    except Exception as exc:
        print(f"[rayman] escritório virtual indisponível: {exc}", file=sys.stderr)
        return ""


def perguntar(pergunta):
    import re
    ctx = contexto_vendas()
    if not ctx:
        print("Não consegui acessar o Supabase. Configure com:\n"
              "  rayman-vendas --config https://SEU-PROJETO.supabase.co SUA_ANON_KEY")
        sys.exit(1)
    prompt = (ctx + "\n\nCom base SOMENTE nos dados acima, responda ao Julio "
              "de forma direta e falada, com os números principais: " + pergunta)
    out = subprocess.run([JARVIS, "--quiet", "ask", "--no-stream", prompt],
                         capture_output=True, text=True, timeout=300)
    resposta = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", out.stdout).strip()
    print(resposta or out.stderr.strip()[-300:])
    return resposta


def main():
    args = sys.argv[1:]
    if args and args[0] == "--config":
        if len(args) < 3:
            print("Uso: rayman-vendas --config https://SEU-PROJETO.supabase.co SUA_ANON_KEY")
            sys.exit(1)
        salvar_credenciais(args[1], args[2])
        return
    if args:
        perguntar(" ".join(args))
    else:
        perguntar("faça um resumo executivo do negócio agora: produtos, vídeos, "
                  "métricas e o que merece minha atenção hoje")


if __name__ == "__main__":
    main()
PYVD

# ---------- rayman-conectar: assistente de conexões ----------
cat > "$RAYMAN_DIR/rayman_conectar.py" <<'PYCN'
"""Assistente de conexão do RAYMAN: liga tudo de uma vez.

O que ele conecta (tudo opcional — Enter pula):
  1. Claude (Anthropic)  -> vira o cérebro de TODAS as respostas
  2. Supabase            -> suas vendas do Escritório Virtual, por voz
  3. Twilio              -> RAYMAN no seu WhatsApp, de qualquer lugar

Uso:
    rayman-conectar                     -> modo pergunta-e-resposta
    rayman-conectar --env /caminho/.env -> lê tudo do .env do Escritório
                                           Virtual e conecta sozinho
    rayman-conectar --status            -> o que está ligado e o que falta
"""
import json
import os
import subprocess
import sys

RAYMAN_DIR = os.path.expanduser("~/.openjarvis/rayman")
JARVIS = os.path.expanduser("~/.openjarvis/.venv/bin/jarvis")


def _salvar(nome, conteudo):
    os.makedirs(RAYMAN_DIR, exist_ok=True)
    caminho = os.path.join(RAYMAN_DIR, nome)
    with open(caminho, "w") as f:
        f.write(conteudo)
    os.chmod(caminho, 0o600)


def _config(chave, valor):
    subprocess.run([JARVIS, "--quiet", "config", "set", chave, valor],
                   capture_output=True, text=True)


def ligar_claude(chave):
    chave = (chave or "").strip()
    if not chave.startswith("sk-"):
        return False
    _salvar("anthropic_key.txt", chave)
    _config("engine.default", "cloud")
    _config("intelligence.default_model", "claude-haiku-4-5")
    print("  [ok] Claude ligado como cérebro (claude-haiku-4-5).")
    return True


def ligar_supabase(url, key):
    url, key = (url or "").strip(), (key or "").strip()
    if not url.startswith("http") or len(key) < 20:
        return False
    _salvar("supabase.json", json.dumps({"url": url.rstrip("/"), "key": key}))
    print("  [ok] Escritório Virtual (Supabase) conectado.")
    return True


def ligar_twilio(sid, token, de):
    sid, token, de = (sid or "").strip(), (token or "").strip(), (de or "").strip()
    if not sid.startswith("AC") or not token or not de:
        return False
    if not de.startswith("whatsapp:"):
        de = "whatsapp:" + de
    _salvar("twilio.json", json.dumps({"account_sid": sid, "auth_token": token,
                                       "from_whatsapp": de}))
    print("  [ok] WhatsApp (Twilio) conectado.")
    return True


def parse_env(caminho):
    valores = {}
    try:
        for linha in open(os.path.expanduser(caminho), encoding="utf-8"):
            linha = linha.strip()
            if not linha or linha.startswith("#") or "=" not in linha:
                continue
            k, _, v = linha.partition("=")
            valores[k.strip()] = v.strip().strip('"').strip("'")
    except Exception as exc:
        print(f"Não consegui ler {caminho}: {exc}")
        sys.exit(1)
    return valores


def status():
    tem = lambda n: os.path.exists(os.path.join(RAYMAN_DIR, n))
    eng = subprocess.run([JARVIS, "--quiet", "config", "get", "engine.default"],
                         capture_output=True, text=True).stdout.strip()
    print("Estado das conexões do RAYMAN:")
    print(f"  cérebro Claude:      {'LIGADO' if tem('anthropic_key.txt') else 'desligado (rayman-conectar)'}"
          f"  [engine: {eng or '?'}]")
    print(f"  vendas (Supabase):   {'LIGADO' if tem('supabase.json') else 'desligado'}")
    print(f"  WhatsApp (Twilio):   {'LIGADO' if tem('twilio.json') else 'desligado'}")
    print(f"  Obsidian:            {'LIGADO' if tem('obsidian_vault.txt') else 'desligado'}")
    print("  busca na web:        sempre ligada (gatilho: 'pesquisa...', 'hoje', 'notícias')")


def main():
    args = sys.argv[1:]
    if args and args[0] == "--status":
        status()
        return
    ligados = 0
    if args and args[0] == "--env":
        if len(args) < 2:
            print("Uso: rayman-conectar --env /caminho/do/.env")
            sys.exit(1)
        v = parse_env(args[1])
        print("Lendo o .env do Escritório Virtual...")
        ligados += bool(ligar_claude(v.get("ANTHROPIC_API_KEY", "")))
        ligados += bool(ligar_supabase(v.get("SUPABASE_URL", ""), v.get("SUPABASE_KEY", "")))
        ligados += bool(ligar_twilio(v.get("TWILIO_ACCOUNT_SID", ""),
                                     v.get("TWILIO_AUTH_TOKEN", ""),
                                     v.get("TWILIO_WHATSAPP_FROM", "")))
    else:
        print("Vamos ligar o RAYMAN em tudo. Enter pula qualquer etapa.\n")
        print("1) Cérebro Claude — chave da Anthropic (console.anthropic.com > API keys)")
        ligados += bool(ligar_claude(input("   sk-ant-...: ")))
        print("\n2) Suas vendas — Supabase do Escritório Virtual (Settings > API)")
        url = input("   SUPABASE_URL (https://xxx.supabase.co): ")
        key = input("   SUPABASE_KEY (anon public): ") if url.strip() else ""
        ligados += bool(url.strip() and ligar_supabase(url, key))
        print("\n3) WhatsApp — Twilio (console.twilio.com)")
        sid = input("   TWILIO_ACCOUNT_SID (AC...): ")
        token = input("   TWILIO_AUTH_TOKEN: ") if sid.strip() else ""
        de = input("   seu número WhatsApp Twilio (whatsapp:+55...): ") if sid.strip() else ""
        ligados += bool(sid.strip() and ligar_twilio(sid, token, de))

    print(f"\n{ligados} conexão(ões) ativada(s).")
    status()
    if ligados:
        print("\nÚltimo passo (ativa os serviços em segundo plano):")
        print("  bash ~/Downloads/install_rayman.sh")
        print('Depois teste por voz: rayman-show -> "como estão as minhas vendas?"')


if __name__ == "__main__":
    main()
PYCN

# ---------- rayman-bling: vendas reais (Bling ERP) ----------
cat > "$RAYMAN_DIR/rayman_bling.py" <<'PYBL'
"""RAYMAN + Bling ERP: suas vendas REAIS, por voz.

O Bling é onde vivem os pedidos e o estoque de verdade. Este conector usa a
API v3 do Bling (Bearer token OAuth) e alimenta o RAYMAN com: pedidos e
faturamento dos últimos dias, e estoque atual dos produtos.

Configuração (uma vez) — escolha UMA das formas:

  A) Duradoura (recomendada): crie um aplicativo em developer.bling.com.br,
     autorize sua conta e pegue client_id, client_secret e refresh_token:
         rayman-bling --config CLIENT_ID CLIENT_SECRET REFRESH_TOKEN
     (o RAYMAN renova o token sozinho a partir daí)

  B) Rápida (expira em ~6h, boa pra testar):
         rayman-bling --token SEU_ACCESS_TOKEN

Uso:
    rayman-bling               -> resumo: vendas de hoje/semana + estoque
    rayman-bling "pergunta"    -> pergunta livre sobre as vendas reais
Por voz: os mesmos gatilhos de vendas ("minhas vendas", "faturamento",
"estoque"...) — o Bling entra como fonte principal, o Supabase como apoio.
"""
import datetime as dt
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

RAYMAN_DIR = os.path.expanduser("~/.openjarvis/rayman")
CRED_FILE = os.path.join(RAYMAN_DIR, "bling.json")
JARVIS = os.path.expanduser("~/.openjarvis/.venv/bin/jarvis")
API = "https://api.bling.com.br/Api/v3"
TOKEN_URL = "https://www.bling.com.br/Api/v3/oauth/token"


def _ler():
    if os.path.exists(CRED_FILE):
        try:
            return json.load(open(CRED_FILE))
        except Exception:
            pass
    return {}


def _gravar(cred):
    os.makedirs(RAYMAN_DIR, exist_ok=True)
    with open(CRED_FILE, "w") as f:
        json.dump(cred, f)
    os.chmod(CRED_FILE, 0o600)


def token(httpx):
    """Access token válido; renova via refresh_token quando expira."""
    cred = _ler()
    if not cred:
        return ""
    import time
    if cred.get("access_token") and time.time() < cred.get("expira_em", 0) - 120:
        return cred["access_token"]
    if not (cred.get("client_id") and cred.get("refresh_token")):
        return cred.get("access_token", "")  # modo --token simples
    import base64
    basic = base64.b64encode(
        f"{cred['client_id']}:{cred.get('client_secret', '')}".encode()).decode()
    r = httpx.post(TOKEN_URL,
                   headers={"Authorization": f"Basic {basic}",
                            "Content-Type": "application/x-www-form-urlencoded"},
                   data={"grant_type": "refresh_token",
                         "refresh_token": cred["refresh_token"]},
                   timeout=20.0)
    if r.status_code >= 300:
        print(f"[rayman] renovação do token Bling falhou: {r.text[:200]}",
              file=sys.stderr)
        return cred.get("access_token", "")
    novo = r.json()
    cred["access_token"] = novo.get("access_token", "")
    if novo.get("refresh_token"):
        cred["refresh_token"] = novo["refresh_token"]  # Bling rotaciona
    cred["expira_em"] = time.time() + int(novo.get("expires_in", 21600))
    _gravar(cred)
    return cred["access_token"]


def _get(httpx, tk, caminho, params=""):
    r = httpx.get(f"{API}{caminho}?{params}",
                  headers={"Authorization": f"Bearer {tk}",
                           "Accept": "application/json"},
                  timeout=20.0)
    r.raise_for_status()
    return r.json().get("data", [])


def _num(x):
    try:
        return float(x or 0)
    except Exception:
        return 0.0


def coletar(httpx, tk, dias=7):
    hoje = dt.date.today()
    ini = hoje - dt.timedelta(days=dias - 1)
    pedidos = _get(httpx, tk, "/pedidos/vendas",
                   f"dataInicial={ini}&dataFinal={hoje}&limite=100")
    produtos = _get(httpx, tk, "/produtos", "limite=100&criterio=2")
    return pedidos, produtos, hoje


def contexto_bling(dias=7):
    """Resumo das vendas reais do Bling; '' se não configurado/falhar."""
    if not _ler():
        return ""
    try:
        import httpx
        tk = token(httpx)
        if not tk:
            return ""
        pedidos, produtos, hoje = coletar(httpx, tk, dias)
    except Exception as exc:
        print(f"[rayman] Bling indisponível: {exc}", file=sys.stderr)
        try:
            with open(os.path.join(RAYMAN_DIR, "erro.log"), "a") as f:
                f.write(f"BLING: {exc}\n---\n")
        except Exception:
            pass
        return ""

    linhas = [f"VENDAS REAIS DO BLING (fonte oficial — últimos {dias} dias):"]
    tot_periodo, tot_hoje, n_hoje = 0.0, 0.0, 0
    for p in pedidos:
        total = _num(p.get("total") or p.get("totalVenda"))
        tot_periodo += total
        data = str(p.get("data", ""))[:10]
        if data == str(hoje):
            tot_hoje += total
            n_hoje += 1
    linhas.append(f"HOJE ({hoje}): {n_hoje} pedido(s), R${tot_hoje:.2f}")
    linhas.append(f"PERÍODO: {len(pedidos)} pedido(s), R${tot_periodo:.2f}")
    ultimos = sorted(pedidos, key=lambda p: str(p.get("data", "")), reverse=True)[:6]
    for p in ultimos:
        contato = (p.get("contato") or {}).get("nome", "?")
        situacao = (p.get("situacao") or {})
        situacao = situacao.get("valor") or situacao.get("id") or ""
        linhas.append(f"- {str(p.get('data', ''))[:10]} | {contato} | "
                      f"R${_num(p.get('total')):.2f} | situação {situacao}")

    com_estoque = 0
    linhas.append(f"\nESTOQUE (até 100 produtos ativos):")
    for pr in produtos[:15]:
        est = pr.get("estoque")
        saldo = est.get("saldoVirtualTotal") if isinstance(est, dict) else est
        if _num(saldo) > 0:
            com_estoque += 1
        linhas.append(f"- {pr.get('nome', '?')[:40]}: estoque {saldo}, "
                      f"preço R${_num(pr.get('preco')):.2f}")
    linhas.append(f"(produtos com estoque > 0 na amostra: {com_estoque})")
    return "\n".join(linhas)


def perguntar(pergunta):
    import re
    ctx = contexto_bling()
    if not ctx:
        print("Bling não configurado ou inacessível. Veja: rayman-bling --help")
        sys.exit(1)
    prompt = (ctx + "\n\nCom base SOMENTE nos dados acima, responda ao Julio "
              "de forma direta e falada, com os números principais: " + pergunta)
    out = subprocess.run([JARVIS, "--quiet", "ask", "--no-stream", prompt],
                         capture_output=True, text=True, timeout=300)
    resposta = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", out.stdout).strip()
    print(resposta or out.stderr.strip()[-300:])
    return resposta


def testar():
    """Diagnóstico passo a passo da conexão com o Bling."""
    import httpx
    cred = _ler()
    if not cred:
        print("1. credenciais: NÃO CONFIGURADAS")
        print("   rode: rayman-bling --config CLIENT_ID CLIENT_SECRET REFRESH_TOKEN")
        return
    modo = "client_id+refresh (renova sozinho)" if cred.get("client_id") else "token simples (expira ~6h)"
    print(f"1. credenciais: ok ({modo})")
    tk = token(httpx)
    if not tk:
        print("2. token: FALHOU — veja a mensagem de erro acima.")
        print("   Causa comum: refresh_token errado/expirado, ou client_id e")
        print("   client_secret trocados. Refaça o --config na ordem certa.")
        return
    print(f"2. token: ok (começa com {tk[:8]}...)")
    for nome, caminho, params in (
        ("pedidos de venda", "/pedidos/vendas", "limite=5"),
        ("produtos", "/produtos", "limite=5"),
    ):
        try:
            r = httpx.get(f"{API}{caminho}?{params}",
                          headers={"Authorization": f"Bearer {tk}",
                                   "Accept": "application/json"}, timeout=20.0)
            n = len(r.json().get("data", [])) if r.status_code < 300 else 0
            print(f"3. {nome}: HTTP {r.status_code}, {n} registro(s) na amostra")
            if r.status_code >= 300:
                print("   resposta:", r.text[:300])
        except Exception as exc:
            print(f"3. {nome}: ERRO {exc}")
    print("\nSe os passos deram ok mas com 0 pedidos, confira no painel do")
    print("Bling se os pedidos estão como 'pedido de venda' (não orçamento).")


def main():
    args = sys.argv[1:]
    if args and args[0] in ("--help", "-h"):
        print(__doc__)
        return
    if args and args[0] == "--testar":
        testar()
        return
    if args and args[0] == "--config":
        if len(args) < 4:
            print("Uso: rayman-bling --config CLIENT_ID CLIENT_SECRET REFRESH_TOKEN")
            sys.exit(1)
        _gravar({"client_id": args[1], "client_secret": args[2],
                 "refresh_token": args[3]})
        print("Bling configurado (renovação automática). Teste: rayman-bling")
        return
    if args and args[0] == "--token":
        if len(args) < 2:
            print("Uso: rayman-bling --token ACCESS_TOKEN")
            sys.exit(1)
        import time
        _gravar({"access_token": args[1], "expira_em": time.time() + 6 * 3600})
        print("Token do Bling salvo (expira em ~6h). Teste: rayman-bling")
        return
    if args:
        perguntar(" ".join(args))
    else:
        perguntar("resuma minhas vendas de hoje e da semana, e o estoque")


if __name__ == "__main__":
    main()
PYBL

# ---------- HUD (página) ----------
cat > "$RAYMAN_DIR/hud.html" <<'HTMLHUD'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>RAYMAN</title>
<style>
  :root { --cor: #35c8f5; }
  * { margin:0; padding:0; box-sizing:border-box; }
  html,body { height:100%; background:#04070c; overflow:hidden; }
  body { font-family:"SF Mono",ui-monospace,Menlo,monospace; color:#cfe9f5;
         display:flex; flex-direction:column; align-items:center;
         justify-content:center; }
  #grade { position:fixed; left:-50%; right:-50%; bottom:-12%; height:46%;
    background:
      repeating-linear-gradient(90deg, rgba(53,200,245,.10) 0 1px, transparent 1px 70px),
      repeating-linear-gradient(0deg,  rgba(53,200,245,.10) 0 1px, transparent 1px 46px);
    transform:perspective(600px) rotateX(64deg); opacity:.5;
    mask-image:linear-gradient(to top, black 30%, transparent);
    -webkit-mask-image:linear-gradient(to top, black 30%, transparent); }
  #scan { position:fixed; inset:0; pointer-events:none; opacity:.5;
    background:linear-gradient(to bottom, transparent 0%,
      rgba(53,200,245,.05) 48%, rgba(53,200,245,.14) 50%,
      rgba(53,200,245,.05) 52%, transparent 100%);
    background-size:100% 240px; animation:varrer 7s linear infinite; }
  @keyframes varrer { from{background-position-y:-240px} to{background-position-y:110vh} }
  .canto { position:fixed; width:56px; height:56px; opacity:.6;
           border:2px solid var(--cor); transition:border-color .6s; }
  .canto.a { top:18px; left:18px;  border-right:0; border-bottom:0; }
  .canto.b { top:18px; right:18px; border-left:0;  border-bottom:0; }
  .canto.c { bottom:18px; left:18px;  border-right:0; border-top:0; }
  .canto.d { bottom:18px; right:18px; border-left:0;  border-top:0; }
  canvas#palco { display:block; }
  #status { margin-top:6px; font-size:14px; letter-spacing:.6em; padding-left:.6em;
            text-transform:uppercase; color:var(--cor); transition:color .6s;
            text-shadow:0 0 14px var(--cor); }
  .fala { max-width:760px; text-align:center; line-height:1.6;
          min-height:4.4em; margin-top:16px; padding:0 24px; }
  .fala .voce   { color:#5b7a8a; font-size:13px; }
  .fala .rayman { color:#eafaff; font-size:16px; margin-top:8px; }
  #relogio { position:fixed; top:26px; right:34px; color:#5b7a8a;
             font-size:13px; letter-spacing:.2em; }
  #titulo  { position:fixed; top:26px; left:34px; color:#5b7a8a;
             font-size:12px; letter-spacing:.4em; }
  #marca { position:fixed; bottom:22px; color:#43606f; font-size:11px;
           letter-spacing:.3em; }
</style>
</head>
<body>
  <div id="grade"></div><div id="scan"></div>
  <div class="canto a"></div><div class="canto b"></div>
  <div class="canto c"></div><div class="canto d"></div>
  <div id="titulo">RAYMAN</div>
  <div id="relogio"></div>
  <canvas id="palco" width="640" height="520"></canvas>
  <div id="status">em espera</div>
  <div class="fala">
    <div class="voce" id="voce"></div>
    <div class="rayman" id="resposta"></div>
  </div>
  <div id="marca">RAYMAN &middot; AO SEU DISPOR</div>

<script>
const CORES = { ouvindo:"#35c8f5", pensando:"#f5b53a", falando:"#46e6a0", espera:"#3a7a94" };
const ROTULOS = { ouvindo:"ouvindo", pensando:"processando", falando:"falando", espera:"em espera" };
let estado = "espera";

const cv = document.getElementById("palco"), cx = cv.getContext("2d");
const W = cv.width, H = cv.height, CX = W/2, CY = H/2 - 10;

/* intensidade 0..1 por estado (anima transições) */
let nivel = 0;
let nivelMic = 0;
function alvoNivel() {
  return estado === "falando" ? 1 : estado === "pensando" ? .6
       : estado === "ouvindo" ? .2 + nivelMic*.8 : .12;
}

/* ============== TEMA: reator (anéis do reator arc) ============== */
function desenharReator(t, cor) {
  // núcleo
  const g = cx.createRadialGradient(CX, CY, 4, CX, CY, 90 + nivel*30);
  g.addColorStop(0, "#eafaff"); g.addColorStop(.25, cor);
  g.addColorStop(1, "transparent");
  cx.save();
  cx.globalAlpha = .55 + nivel*.4 + Math.sin(t*3)*.05;
  cx.fillStyle = g;
  cx.beginPath(); cx.arc(CX, CY, 90 + nivel*30, 0, Math.PI*2); cx.fill();
  cx.restore();
  // anéis segmentados girando
  const aneis = [
    [70, 10, 1, t*0.9], [110, 16, 2, -t*0.5],
    [150, 24, 1.6, t*0.3], [195, 12, 1, -t*0.7], [225, 40, .8, t*0.15]
  ];
  cx.save(); cx.translate(CX, CY);
  aneis.forEach(([r, seg, lw, rot], i) => {
    cx.save(); cx.rotate(rot);
    cx.strokeStyle = cor; cx.lineWidth = lw;
    cx.shadowColor = cor; cx.shadowBlur = 10 + nivel*14;
    cx.globalAlpha = .35 + nivel*.5 - i*.04;
    for (let s = 0; s < seg; s++) {
      const a0 = (s/seg)*Math.PI*2, a1 = a0 + (Math.PI*2/seg)*0.55;
      cx.beginPath(); cx.arc(0, 0, r, a0, a1); cx.stroke();
    }
    cx.restore();
  });
  // ticks radiais
  cx.strokeStyle = cor; cx.globalAlpha = .5; cx.lineWidth = 1.5;
  for (let i = 0; i < 12; i++) {
    const a = (i/12)*Math.PI*2 + t*0.05;
    cx.beginPath();
    cx.moveTo(Math.cos(a)*238, Math.sin(a)*238);
    cx.lineTo(Math.cos(a)*(244 + nivel*6), Math.sin(a)*(244 + nivel*6));
    cx.stroke();
  }
  cx.restore();
}

/* ============== TEMA: esfera (holograma de partículas) ============== */
const PONTOS = [];
for (let i = 0; i < 920; i++) {           // espiral de Fibonacci na esfera
  const y = 1 - (i/919)*2, r = Math.sqrt(1 - y*y), a = i*2.39996;
  PONTOS.push([Math.cos(a)*r, y, Math.sin(a)*r]);
}
function desenharEsfera(t, cor) {
  const R = 150 + nivel*22 + Math.sin(t*2.2)*4*nivel;
  const ry = t*0.5, rx = 0.35 + Math.sin(t*0.2)*0.1;
  cx.save(); cx.translate(CX, CY);
  // halo
  const g = cx.createRadialGradient(0,0,R*.4, 0,0,R*1.5);
  g.addColorStop(0, "transparent"); g.addColorStop(.75, cor+"18");
  g.addColorStop(1, "transparent");
  cx.fillStyle = g; cx.beginPath(); cx.arc(0,0,R*1.5,0,Math.PI*2); cx.fill();
  // anel equatorial
  cx.strokeStyle = cor; cx.globalAlpha = .35; cx.lineWidth = 1;
  cx.beginPath(); cx.ellipse(0, 0, R*1.25, R*0.32, -0.18, 0, Math.PI*2); cx.stroke();
  cx.globalAlpha = 1;
  for (let i = 0; i < PONTOS.length; i++) {
    const [x0,y0,z0] = PONTOS[i];
    // rotação Y depois X
    let x = x0*Math.cos(ry) + z0*Math.sin(ry);
    let z = -x0*Math.sin(ry) + z0*Math.cos(ry);
    let y = y0*Math.cos(rx) - z*Math.sin(rx);
    z = y0*Math.sin(rx) + z*Math.cos(rx);
    // a "voz" empurra cada partícula pra fora, como som numa membrana
    const voz = 1 + nivel * 0.22 * Math.sin(t*11 + i*0.37)
                  + nivel * 0.10 * Math.sin(t*23 + i*1.13);
    const persp = 1.6/(1.6 + z);           // z em [-1,1]
    const px = x*R*voz*persp, py = y*R*voz*persp;
    const frente = (1 - z)/2;              // 0 atrás .. 1 na frente
    const tam = (0.8 + frente*1.8) * (1 + nivel*.5);
    cx.globalAlpha = 0.12 + frente*0.75;
    cx.fillStyle = frente > .82 ? "#eafaff" : cor;
    cx.beginPath(); cx.arc(px, py, tam, 0, Math.PI*2); cx.fill();
  }
  cx.restore();
}

/* ============== TEMA: onda (osciloscópio) ============== */
function desenharOnda(t, cor) {
  cx.save();
  cx.strokeStyle = cor; cx.shadowColor = cor;
  const linhas = [ [1, 3, 0], [.45, 1.5, 1.3], [.22, 1, 2.6] ];
  for (const [amp, lw, fase] of linhas) {
    cx.lineWidth = lw; cx.shadowBlur = 18*amp;
    cx.globalAlpha = .25 + amp*.75;
    cx.beginPath();
    for (let x = 0; x <= W; x += 3) {
      const f = x/W, env = Math.sin(f*Math.PI);
      const soma = Math.sin(t*4 + fase + f*11)*32
                 + Math.sin(t*9 + fase + f*23)*18
                 + Math.sin(t*15 + fase + f*41)*9;
      const y = CY + soma * env * (0.12 + nivel*0.9) * amp;
      x === 0 ? cx.moveTo(x, y) : cx.lineTo(x, y);
    }
    cx.stroke();
  }
  // régua central
  cx.globalAlpha = .25; cx.lineWidth = 1; cx.shadowBlur = 0;
  cx.setLineDash([2, 10]);
  cx.beginPath(); cx.moveTo(0, CY); cx.lineTo(W, CY); cx.stroke();
  cx.setLineDash([]);
  // círculo de energia central
  cx.globalAlpha = .5 + nivel*.5;
  cx.lineWidth = 2; cx.shadowBlur = 16;
  cx.beginPath(); cx.arc(CX, CY, 34 + nivel*26 + Math.sin(t*3)*3, 0, Math.PI*2);
  cx.stroke();
  cx.restore();
}

/* ============== TEMA: rosto (o holograma com rosto) ============== */
const PERFIL = [
  [0,-190],[52,-186],[96,-166],[126,-128],[138,-84],[140,-38],[134,8],
  [122,52],[118,92],[104,128],[76,152],[40,166],[0,172]
];
function pontosCabeca(t) {
  const ond = (i)=> Math.sin(t*0.8 + i*0.9)*1.5;
  const pts = [];
  PERFIL.forEach(([x,y],i)=> pts.push([CX + x + (x?ond(i):0), CY + y]));
  for (let i = PERFIL.length-2; i>0; i--) {
    const [x,y] = PERFIL[i];
    pts.push([CX - (x + (x?ond(i):0)), CY + y]);
  }
  return pts;
}
function caminhoCabeca(t) {
  const p = pontosCabeca(t), n = p.length;
  cx.beginPath();
  cx.moveTo((p[0][0]+p[n-1][0])/2, (p[0][1]+p[n-1][1])/2);
  for (let i = 0; i < n; i++) {
    const a = p[i], b = p[(i+1)%n];
    cx.quadraticCurveTo(a[0], a[1], (a[0]+b[0])/2, (a[1]+b[1])/2);
  }
  cx.closePath();
}
function olho(lado, t, cor) {
  const ex = CX + lado*56, ey = CY - 40;
  let ab = 1;
  const ciclo = (t*1000) % 4200;
  if (ciclo < 130) ab = Math.abs(Math.sin(ciclo/130*Math.PI));
  if (estado === "pensando") ab *= 0.45;
  const w = 56, h = Math.max(1.5, 7.5*ab);
  cx.save(); cx.shadowColor = cor; cx.shadowBlur = 26;
  const gh = cx.createLinearGradient(ex-w/2, 0, ex+w/2, 0);
  gh.addColorStop(0, "transparent"); gh.addColorStop(.18, cor);
  gh.addColorStop(.5, "#eafaff");   gh.addColorStop(.82, cor);
  gh.addColorStop(1, "transparent");
  cx.fillStyle = gh;
  cx.beginPath(); cx.ellipse(ex, ey, w/2, h, 0, 0, Math.PI*2); cx.fill();
  cx.strokeStyle = cor; cx.globalAlpha = .5; cx.lineWidth = 1.5;
  cx.beginPath();
  cx.moveTo(ex - lado*w*0.52, ey - 17);
  cx.lineTo(ex + lado*w*0.34, ey - 18 - ab*2);
  cx.stroke();
  cx.restore();
}
function desenharRosto(t, cor) {
  cx.save();
  cx.shadowColor = cor; cx.shadowBlur = 18;
  cx.strokeStyle = cor; cx.lineWidth = 2; cx.globalAlpha = .9;
  caminhoCabeca(t); cx.stroke();
  const g = cx.createLinearGradient(0, CY-190, 0, CY+172);
  g.addColorStop(0, cor + "22"); g.addColorStop(1, "transparent");
  cx.globalAlpha = .3 + nivel*.25; cx.fillStyle = g;
  caminhoCabeca(t); cx.fill();
  cx.restore();
  olho(-1, t, cor); olho(1, t, cor);
  // boca-onda
  cx.save(); cx.strokeStyle = cor; cx.lineWidth = 2.5;
  cx.shadowColor = cor; cx.shadowBlur = 16;
  cx.beginPath();
  const bx = CX, by = CY + 92, larg = 130, N = 48;
  for (let i = 0; i <= N; i++) {
    const x = bx - larg/2 + (larg/N)*i, f = i/N, env = Math.sin(f*Math.PI);
    const y = by + (Math.sin(t*14 + i*0.9)*14 + Math.sin(t*31 + i*1.7)*6) * env * nivel;
    i === 0 ? cx.moveTo(x, y) : cx.lineTo(x, y);
  }
  cx.stroke(); cx.restore();
}

const TEMAS = { reator: desenharReator, esfera: desenharEsfera,
                onda: desenharOnda, rosto: desenharRosto };
let tema = "reator";

function desenhar(ts) {
  const t = ts/1000, cor = CORES[estado];
  nivel += (alvoNivel() - nivel) * 0.06;          // transição suave
  cx.clearRect(0, 0, W, H);
  (TEMAS[tema] || desenharReator)(t, cor);
  requestAnimationFrame(desenhar);
}
requestAnimationFrame(desenhar);

function aplicar(novo, s) {
  estado = novo;
  nivelMic = s && typeof s.nivel === "number" ? Math.min(1, s.nivel) : 0;
  document.documentElement.style.setProperty("--cor", CORES[novo]);
  document.getElementById("status").textContent = ROTULOS[novo];
  document.getElementById("voce").textContent = s && s.voce ? "“"+s.voce+"”" : "";
  document.getElementById("resposta").textContent = s && s.rayman ? s.rayman : "";
}

const q = new URLSearchParams(location.search);
if (q.get("tema")) tema = q.get("tema");
else fetch("/tema.txt").then(r => r.text())
       .then(x => { if (TEMAS[x.trim()]) tema = x.trim(); }).catch(()=>{});

const demo = q.get("estado");
if (demo) {
  aplicar(demo, { voce: "qual a previsão do tempo pra amanhã?",
                  rayman: "Céu limpo e vinte e oito graus, senhor. Um dia excelente." });
} else {
  setInterval(async () => {
    try {
      const r = await fetch("/state.json", { cache: "no-store" });
      const s = await r.json();
      const fresco = (Date.now()/1000 - (s.ts || 0)) < 8;
      aplicar(fresco && CORES[s.status] ? s.status : "espera", s);
    } catch (e) { aplicar("espera", null); }
  }, 400);
}
setInterval(() => { document.getElementById("relogio").textContent =
  new Date().toLocaleTimeString("pt-BR"); }, 1000);
</script>
</body>
</html>
HTMLHUD

# ---------- executáveis ----------
cat > "$BIN_DIR/rayman" <<WRAP
#!/usr/bin/env bash
# RAYMAN = OpenJarvis com a persona rayman (chat de texto e todos os comandos)
[[ -f "$HOME/.openjarvis/rayman/anthropic_key.txt" ]] && export ANTHROPIC_API_KEY="\$(cat "$HOME/.openjarvis/rayman/anthropic_key.txt")"
exec "$VENV/bin/jarvis" "\$@"
WRAP
cat > "$BIN_DIR/rayman-voz" <<WRAP
#!/usr/bin/env bash
[[ -f "$HOME/.openjarvis/rayman/anthropic_key.txt" ]] && export ANTHROPIC_API_KEY="\$(cat "$HOME/.openjarvis/rayman/anthropic_key.txt")"
exec "$VENV/bin/python" "$RAYMAN_DIR/rayman_voz.py" "\$@"
WRAP
cat > "$BIN_DIR/rayman-show" <<WRAP
#!/usr/bin/env bash
[[ -f "$HOME/.openjarvis/rayman/anthropic_key.txt" ]] && export ANTHROPIC_API_KEY="\$(cat "$HOME/.openjarvis/rayman/anthropic_key.txt")"
exec "$VENV/bin/python" "$RAYMAN_DIR/rayman_show.py" "\$@"
WRAP
cat > "$BIN_DIR/rayman-hud" <<WRAP
#!/usr/bin/env bash
[[ -f "$HOME/.openjarvis/rayman/anthropic_key.txt" ]] && export ANTHROPIC_API_KEY="\$(cat "$HOME/.openjarvis/rayman/anthropic_key.txt")"
exec "$VENV/bin/python" "$RAYMAN_DIR/rayman_hud.py" "\$@"
WRAP
cat > "$BIN_DIR/rayman-web" <<WRAP
#!/usr/bin/env bash
[[ -f "$HOME/.openjarvis/rayman/anthropic_key.txt" ]] && export ANTHROPIC_API_KEY="\$(cat "$HOME/.openjarvis/rayman/anthropic_key.txt")"
exec "$VENV/bin/python" "$RAYMAN_DIR/rayman_web.py" "\$@"
WRAP
cat > "$BIN_DIR/rayman-telegram" <<WRAP
#!/usr/bin/env bash
[[ -f "$HOME/.openjarvis/rayman/anthropic_key.txt" ]] && export ANTHROPIC_API_KEY="\$(cat "$HOME/.openjarvis/rayman/anthropic_key.txt")"
exec "$VENV/bin/python" "$RAYMAN_DIR/rayman_telegram.py" "\$@"
WRAP
cat > "$BIN_DIR/rayman-whatsapp" <<WRAP
#!/usr/bin/env bash
[[ -f "$HOME/.openjarvis/rayman/anthropic_key.txt" ]] && export ANTHROPIC_API_KEY="\$(cat "$HOME/.openjarvis/rayman/anthropic_key.txt")"
exec "$VENV/bin/python" "$RAYMAN_DIR/rayman_whatsapp.py" "\$@"
WRAP
cat > "$BIN_DIR/rayman-claude" <<WRAP
#!/usr/bin/env bash
exec "$VENV/bin/python" "$RAYMAN_DIR/rayman_claude.py" "\$@"
WRAP
cat > "$BIN_DIR/rayman-vendas" <<WRAP
#!/usr/bin/env bash
[[ -f "$HOME/.openjarvis/rayman/anthropic_key.txt" ]] && export ANTHROPIC_API_KEY="\$(cat "$HOME/.openjarvis/rayman/anthropic_key.txt")"
exec "$VENV/bin/python" "$RAYMAN_DIR/rayman_vendas.py" "\$@"
WRAP
cat > "$BIN_DIR/rayman-conectar" <<WRAP
#!/usr/bin/env bash
exec "$VENV/bin/python" "$RAYMAN_DIR/rayman_conectar.py" "\$@"
WRAP
cat > "$BIN_DIR/rayman-bling" <<WRAP
#!/usr/bin/env bash
[[ -f "$HOME/.openjarvis/rayman/anthropic_key.txt" ]] && export ANTHROPIC_API_KEY="\$(cat "$HOME/.openjarvis/rayman/anthropic_key.txt")"
exec "$VENV/bin/python" "$RAYMAN_DIR/rayman_bling.py" "\$@"
WRAP
cat > "$BIN_DIR/rayman-obsidian" <<WRAP
#!/usr/bin/env bash
[[ -f "$HOME/.openjarvis/rayman/anthropic_key.txt" ]] && export ANTHROPIC_API_KEY="\$(cat "$HOME/.openjarvis/rayman/anthropic_key.txt")"
exec "$VENV/bin/python" "$RAYMAN_DIR/rayman_obsidian.py" "\$@"
WRAP
chmod +x "$BIN_DIR/rayman" "$BIN_DIR/rayman-voz" "$BIN_DIR/rayman-show" \
         "$BIN_DIR/rayman-hud" "$BIN_DIR/rayman-obsidian" "$BIN_DIR/rayman-web" "$BIN_DIR/rayman-telegram" "$BIN_DIR/rayman-whatsapp" "$BIN_DIR/rayman-claude" "$BIN_DIR/rayman-vendas" "$BIN_DIR/rayman-conectar" "$BIN_DIR/rayman-bling"

# ------------------------------------------------------------
# 5b. Interface web em tempo real (rayman start)
# ------------------------------------------------------------
STATIC_DIR="$OPENJARVIS_HOME/src/src/openjarvis/server/static"
if [[ -d "$STATIC_DIR" ]]; then
    say_step "Interface web já construída — ok"
else
    say_step "Construindo a interface web (chat em tempo real) — melhor esforço"
    if ! command -v npm >/dev/null 2>&1; then
        brew install node || true
    fi
    if command -v npm >/dev/null 2>&1 && [[ -d "$OPENJARVIS_HOME/src/frontend" ]]; then
        ( cd "$OPENJARVIS_HOME/src/frontend" \
          && npm install --no-fund --no-audit --loglevel=error \
          && npm run build ) \
        || echo "[aviso] build da interface web falhou — o resto funciona normal; tente depois com: cd ~/.openjarvis/src/frontend && npm install && npm run build"
    else
        echo "[aviso] npm indisponível — pulei a interface web (o resto funciona normal)."
    fi
fi

# ------------------------------------------------------------
# 5c. Obsidian: detectar o vault e indexar as notas (melhor esforço)
# ------------------------------------------------------------
say_step "Procurando o seu vault do Obsidian"
"$VENV/bin/python" "$RAYMAN_DIR/rayman_obsidian.py" \
    || echo "[aviso] Obsidian fica pra depois — configure com: rayman-obsidian /caminho/do/vault"

# ------------------------------------------------------------
# 5d. RAYMAN no Telegram como serviço (auto-início com o Mac)
#     Só ativa se o token do bot já estiver salvo.
# ------------------------------------------------------------
if [[ -f "$RAYMAN_DIR/telegram_token.txt" ]]; then
    say_step "Ativando o RAYMAN no Telegram como serviço (inicia com o Mac)"
    PLIST="$HOME/Library/LaunchAgents/com.rayman.telegram.plist"
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST" <<PLXML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.rayman.telegram</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string>
    <string>-c</string>
    <string>[ -f "$RAYMAN_DIR/anthropic_key.txt" ] &amp;&amp; export ANTHROPIC_API_KEY="\$(cat "$RAYMAN_DIR/anthropic_key.txt")"; exec "$VENV/bin/python" "$RAYMAN_DIR/rayman_telegram.py"</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$RAYMAN_DIR/telegram.log</string>
  <key>StandardErrorPath</key><string>$RAYMAN_DIR/telegram.log</string>
</dict></plist>
PLXML
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST" 2>/dev/null || true
    echo "RAYMAN de plantão no Telegram (serviço com.rayman.telegram; log em $RAYMAN_DIR/telegram.log)."
fi

# ------------------------------------------------------------
# 5e. RAYMAN no WhatsApp como serviço (auto-início com o Mac)
#     Só ativa se as credenciais da Twilio já estiverem salvas.
# ------------------------------------------------------------
if [[ -f "$RAYMAN_DIR/twilio.json" ]]; then
    say_step "Ativando o RAYMAN no WhatsApp como serviço (inicia com o Mac)"
    PLIST_WA="$HOME/Library/LaunchAgents/com.rayman.whatsapp.plist"
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST_WA" <<PLXML2
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.rayman.whatsapp</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string>
    <string>-c</string>
    <string>[ -f "$RAYMAN_DIR/anthropic_key.txt" ] &amp;&amp; export ANTHROPIC_API_KEY="\$(cat "$RAYMAN_DIR/anthropic_key.txt")"; exec "$VENV/bin/python" "$RAYMAN_DIR/rayman_whatsapp.py"</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$RAYMAN_DIR/whatsapp.log</string>
  <key>StandardErrorPath</key><string>$RAYMAN_DIR/whatsapp.log</string>
</dict></plist>
PLXML2
    launchctl unload "$PLIST_WA" 2>/dev/null || true
    launchctl load "$PLIST_WA" 2>/dev/null || true
    echo "RAYMAN de plantão no WhatsApp (serviço com.rayman.whatsapp; log em $RAYMAN_DIR/whatsapp.log)."
fi

# ------------------------------------------------------------
# 6. Validação
# ------------------------------------------------------------
say_step "Validando a instalação (jarvis doctor)"
"$VENV/bin/jarvis" doctor || true

say_step "Baixando a voz pt-BR do Kokoro e testando (primeira vez demora ~1 min)"
"$VENV/bin/python" - <<'PYTEST' || echo "[aviso] teste de voz falhou — rode 'rayman-voz' depois; há fallback pra voz do sistema."
import sys, os
sys.path.insert(0, os.path.expanduser("~/.openjarvis/rayman"))
from _rayman_voice import falar
falar("Instalação concluída. Eu sou o RAYMAN, seu assistente pessoal. Todos os sistemas operacionais, senhor.")
PYTEST

echo
echo "${BOLD}RAYMAN instalado.${RESET}"
echo
echo "  rayman                    -> chat por texto (persona RAYMAN, pt-BR)"
echo "  rayman ask \"pergunta\"     -> pergunta única"
echo "  rayman-voz                -> conversa por voz (diga 'desligar' pra sair)"
echo "  rayman-show               -> bata palma 2x: HUD na tela + voz"
echo "  rayman-hud                -> só o HUD; temas: --tema reator|esfera|onda|rosto"
echo "  rayman-obsidian           -> sincroniza suas notas do Obsidian"
echo "  rayman-obsidian \"pergunta\" -> pergunta usando as notas"
echo "  rayman-web \"pergunta\"    -> busca na internet em tempo real"
echo "  rayman-telegram           -> RAYMAN no Telegram (celular, PC, Apple Watch)"
echo "  rayman-whatsapp           -> RAYMAN no WhatsApp via Twilio (de qualquer lugar)"
echo "  rayman-claude CHAVE_API   -> liga o cérebro Claude (opcional, nuvem)"
echo "  rayman-bling              -> vendas REAIS e estoque do Bling ERP"
echo "  rayman-vendas             -> métricas de marketing (Supabase)"
echo "  rayman-conectar           -> liga TUDO de uma vez (Claude, vendas, WhatsApp)"
echo "  rayman start              -> chat web em tempo real (http://127.0.0.1:8000)"
echo
echo "  Se 'rayman' não for encontrado, abra um terminal novo ou rode:"
echo "      export PATH=\"\$HOME/.local/bin:\$PATH\""
echo
echo "  Primeira conversa por voz: o macOS vai pedir permissão de microfone"
echo "  pro Terminal — aceite em Ajustes > Privacidade e Segurança > Microfone."
