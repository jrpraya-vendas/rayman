# RAYMAN — seu assistente de IA pessoal, 100% local

O RAYMAN é o OpenJarvis (projeto de Stanford) com persona própria em português do Brasil, voz local gratuita, ativação por palmas, HUD visual, chat web em tempo real e integração com as suas notas do Obsidian. Tudo roda no seu Mac: nenhuma conta, nenhuma API key, custo zero.

## Instalação (um comando)

Abra o Terminal e rode:

```bash
bash ~/Downloads/install_rayman.sh
```

Pronto. O instalador cuida de tudo sozinho (uv, Ollama, o modelo qwen3.5:2b de ~2,7 GB, a voz Kokoro em pt-BR e a persona RAYMAN). Leva uns 5–10 minutos, a maior parte baixando modelos. Ele pode pedir sua senha do Mac uma única vez (instalação do Homebrew) e, na primeira conversa por voz, o macOS pede permissão de microfone pro Terminal — aceite.

## Como usar

```bash
rayman                     # chat por texto no terminal
rayman ask "pergunta"      # pergunta única
rayman-voz                 # conversa por voz (fale; diga "desligar" pra sair)
rayman-show                # modo show: palma 2x -> HUD na tela + voz
rayman-hud                 # só o HUD (tela de status ao vivo)
rayman-obsidian            # sincroniza suas notas do Obsidian
rayman-obsidian "pergunta" # pergunta usando as suas notas
rayman start               # chat web em tempo real (http://127.0.0.1:8000)
rayman doctor              # diagnóstico: mostra o que está ok e o que falta
```

Se o comando `rayman` não for encontrado, abra um terminal novo (ou rode `export PATH="$HOME/.local/bin:$PATH"`).

## Obsidian (suas notas)

Na instalação, o RAYMAN procura sozinho um vault do Obsidian nos lugares comuns do Mac (iCloud, Documentos, Desktop) e indexa as notas num banco local. Depois disso, você pode perguntar `rayman-obsidian "o que anotei sobre o projeto X?"` — ou, por voz, dizer algo como "Rayman, procura nas minhas notas...", que ele consulta o vault automaticamente. Quando criar notas novas, rode `rayman-obsidian --sync` pra atualizar o índice. Se ele não achou o vault sozinho (ou você tem mais de um), aponte com `rayman-obsidian /caminho/do/vault`. Tudo fica no seu Mac — as notas nunca saem da máquina.

## HUD (a tela do RAYMAN)

O `rayman-hud` abre no navegador uma tela escura estilo reator, com o anel mudando de cor conforme o estado — azul ouvindo, âmbar processando, verde falando — além do que você disse e da resposta dele. Funciona junto com o `rayman-voz`, e o `rayman-show` já abre os dois após as palmas. Pra cena completa: arraste a janela pra um monitor secundário e aperte cmd+ctrl+F pra tela cheia. A porta muda com `RAYMAN_HUD_PORT` (padrão 8765).

## Tempo real (chat web)

O instalador também constrói a interface web oficial do OpenJarvis: rode `rayman start` e abra http://127.0.0.1:8000 — chat com streaming de resposta em tempo real, dashboard de telemetria e gerenciamento de agentes. É o complemento do HUD: o HUD é a cara do RAYMAN; a interface web é o painel de controle.

## Busca na internet em tempo real

`rayman-web "cotação do dólar agora"` pesquisa no DuckDuckGo (grátis, sem conta) e responde citando a fonte. Por voz funciona sozinho: se a sua frase tiver palavras como "pesquisa", "na internet", "notícias", "hoje" ou "agora", o RAYMAN busca na web antes de responder. O modelo continua rodando local — só a busca vai à internet.

## De qualquer lugar: celular, computador e Apple Watch

O `rayman-telegram` põe o RAYMAN de plantão no Telegram. Configuração única: no Telegram, fale com o @BotFather, mande `/newbot`, escolha um nome e um usuário pro seu bot; ele te dá um token. Aí rode `rayman-telegram --token SEU_TOKEN` e depois `rayman-telegram` (deixe o terminal aberto e o Mac ligado — `caffeinate -s` em outro terminal impede o Mac de dormir). Mande "oi" pro bot: por segurança, o RAYMAN se tranca no primeiro chat que falar com ele (o seu) e ignora todos os outros. A partir daí você conversa com ele do celular, de qualquer computador, do navegador — e do Apple Watch, respondendo pela notificação do Telegram, inclusive ditando por voz. Os gatilhos valem lá também: "pesquisa..." busca na web, "minhas notas..." consulta o Obsidian.

## Vozes

- Padrão (grátis, offline): Kokoro com a voz pt-BR `pf_dora`. Se o Kokoro falhar por qualquer motivo, o RAYMAN cai automaticamente na voz Luciana do próprio macOS.
- Trocar a voz do Kokoro: `export RAYMAN_VOICE=pm_alex` (voz masculina pt-BR) antes de rodar `rayman-voz`.
- Premium (opcional, pago): OpenAI ou Cartesia já têm suporte nativo no OpenJarvis — `export OPENAI_API_KEY=sk-...` e `rayman config set tts.backend openai`. ElevenLabs não tem backend nativo; o uso mais fácil é exportar um .mp3 do site deles como jingle do modo show (salve em `~/.openjarvis/rayman/assets/jingle.mp3`).

## Ajustes do modo show e da voz

Variáveis de ambiente (rode `export VAR=valor` antes do comando):

```
RAYMAN_CLAP_THRESH   # sensibilidade da palma (padrão 0.30; maior = menos sensível)
RAYMAN_MIC           # índice ou nome do microfone
RAYMAN_VOICE         # voz do Kokoro (padrão pf_dora)
RAYMAN_VOICE_SPEED   # velocidade da fala (padrão 1.05)
RAYMAN_STT_MODEL     # modelo do faster-whisper (padrão "small"; "base" é mais leve)
RAYMAN_VAD_THRESH    # sensibilidade de detecção de fala (padrão 0.012)
```

## Solução de problemas

- "Ollama não responde" → rode `ollama serve` em outro terminal (no Mac ele não sobe sozinho fora do app).
- Voz muda / mic não pega → Ajustes > Privacidade e Segurança > Microfone > habilite o Terminal.
- Kokoro reclama do espeak → `brew install espeak-ng` e tente de novo (o instalador já faz isso, mas se você mudou de máquina...).
- Palma dispara sozinha ou não pega → ajuste `RAYMAN_CLAP_THRESH` (suba pra 0.5 se dispara à toa, desça pra 0.2 se não pega).
- Qualquer outra coisa → `rayman doctor` diz exatamente o que está faltando.

## Onde ficam as coisas

Tudo em `~/.openjarvis`: o código em `src/`, a configuração em `config.toml`, a persona do RAYMAN em `personas/rayman/SOUL.md` (edite à vontade — é aí que se muda a personalidade dele) e os scripts de voz em `rayman/`.

## Windows

Este instalador foi feito e testado para macOS. No Windows, o caminho suportado pelo OpenJarvis é o WSL2 (Ubuntu): `wsl --install -d Ubuntu-24.04` num PowerShell de administrador e depois o instalador oficial (`curl -fsSL https://open-jarvis.github.io/OpenJarvis/install.sh | bash`) dentro do Ubuntu. Se um dia você quiser o RAYMAN completo no Windows, me peça que eu adapto o script.
