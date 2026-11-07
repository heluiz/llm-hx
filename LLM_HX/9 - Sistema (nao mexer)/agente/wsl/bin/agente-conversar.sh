#!/usr/bin/env bash
# Agente HX - modo conversa: abre o OpenCode ou o Claude Code em modo chat, dentro de um projeto,
# usando o modelo do seu llama-server. Voce digita os pedidos e acompanha cada passo.
#   agente-conversar.sh <projeto> [--agente opencode|claude] [--porta 8090]
# O projeto "rascunho" e criado na hora se nao existir (pasta livre para testes).
set -uo pipefail
AQUI="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"   # resolve o atalho de /usr/local/bin
# shellcheck source=../lib/comum.sh
. "$AQUI/../lib/comum.sh"

PROJETO=""
AGENTE="opencode"
PORTA=8090
while [ $# -gt 0 ]; do
  case "$1" in
    --agente) AGENTE="${2:-}"; shift 2 || shift ;;
    --porta) PORTA="${2:-}"; shift 2 || shift ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    -*) erro "opcao desconhecida: $1"; exit 2 ;;
    *) PROJETO="$1"; shift ;;
  esac
done
case "$AGENTE" in opencode|claude) ;; *) erro "agente deve ser opencode ou claude"; exit 2 ;; esac
[[ "$PORTA" =~ ^[0-9]+$ ]] || { erro "porta invalida: $PORTA"; exit 2; }
nome_valido "$PROJETO" || { erro "nome de projeto invalido: '$PROJETO'"; exit 2; }
command -v "$AGENTE" >/dev/null 2>&1 || { erro "$AGENTE nao instalado (rode 0-INSTALAR-AGENTE)"; exit 2; }
GITC=(git -c user.name="Agente HX" -c user.email="agente@local" -c commit.gpgsign=false)

P="$PROJETOS_DIR/$PROJETO"
if [ ! -d "$P" ]; then
  if [ "$PROJETO" = "rascunho" ]; then
    mkdir -p "$P"
    git -C "$P" init -q -b main
    printf '.agente/\n' > "$P/.gitignore"
  else
    erro "projeto nao encontrado: $P"; exit 2
  fi
fi
cd "$P" || exit 2
mkdir -p .agente
# Git no projeto = ponto de volta depois de cada conversa. A pasta .agente/ (travas, logs) fica fora.
[ -d .git ] || git init -q -b main
if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ]; then printf '\n' >> .gitignore; fi
grep -qxF '.agente/' .gitignore 2>/dev/null || printf '.agente/\n' >> .gitignore

# Uma conversa por projeto, e nunca junto com o agente sozinho (os dois mexeriam nos mesmos arquivos).
# Primeiro pega a propria trava, depois olha a do loop (o loop faz o contrario): nunca rodam juntos.
# Quem segura a trava e so este script (o agente roda com "8>&-"): ela solta quando a conversa fecha,
# mesmo que o agente tenha deixado algum programa rodando em segundo plano.
exec 8>".agente/conversa.lock"
if ! flock -n 8; then
  erro "ja tem uma conversa aberta neste projeto (outra janela do 4-CONVERSAR-COM-O-AGENTE)."
  exit 2
fi
if [ -f .agente/loop.lock ] && ! flock -n .agente/loop.lock true 2>/dev/null; then
  erro "o agente esta trabalhando sozinho neste projeto agora (3-RODAR-AGENTE)."
  echo "Pare antes com 7-PARAR-PROJETO, ou converse em outro projeto (ou no 'rascunho')."
  exit 2
fi

URL="http://127.0.0.1:$PORTA"
if ! curl -sf -m 5 "$URL/health" >/dev/null 2>&1; then
  echo "O servidor do modelo ainda nao respondeu em $URL."
  echo "Abra o 1-LIGAR-SERVIDOR (e confira se nao esta em pausa). Esperando... (Ctrl+C para desistir)"
  until curl -sf -m 5 "$URL/health" >/dev/null 2>&1; do sleep "${AGENTE_HX_ESPERA_SEG:-5}"; done
fi
MODELO="$(curl -sf -m 10 "$URL/v1/models" 2>/dev/null | jq -r '.data[0].id // empty' 2>/dev/null)"
CTX="$(curl -sf -m 10 "$URL/props" 2>/dev/null | jq -r '.default_generation_settings.n_ctx // empty' 2>/dev/null)"
[ -n "$MODELO" ] || MODELO="local"
[[ "$CTX" =~ ^[0-9]+$ ]] || CTX=65536

# Agente sozinho rodando em outro projeto? (olha as travas dos loops, nao o nome dos processos)
outros=""
for lk in "$PROJETOS_DIR"/*/.agente/loop.lock; do
  [ -f "$lk" ] || continue
  flock -n "$lk" true 2>/dev/null || outros="$outros $(basename "$(dirname "$(dirname "$lk")")")"
done
if [ -n "$outros" ]; then
  aviso "o agente esta rodando sozinho em:$outros. O modelo atende um pedido por vez: os dois ficam mais lentos."
fi

ESTADO_DIR="$HOME/.agente-hx"
mkdir -p "$ESTADO_DIR"

# Extras: o servidor MCP do REA entra so no modo conversa (o modo sozinho fica leve).
# Esquemas "compact" e sem esquema de saida: gasta pouco dos 64K de contexto do modelo local.
USA_REA=0
REA_ENV='{}'
if command -v rea >/dev/null 2>&1 && [ "${AGENTE_HX_SEM_MCP:-0}" != 1 ]; then
  USA_REA=1
  if [ -r "$AGENTE_HX_EXTRAS_DIR/rea.env" ]; then
    REA_ENV="$(jq -Rn '[inputs | select(test("^[A-Z_][A-Z0-9_]*=")) | capture("^(?<key>[A-Z_][A-Z0-9_]*)=(?<value>.*)$")] | from_entries' \
      < "$AGENTE_HX_EXTRAS_DIR/rea.env" 2>/dev/null)" || REA_ENV='{}'
    [ -n "$REA_ENV" ] || REA_ENV='{}'
  fi
  REA_ENV="$(jq -c '{REA_MCP_INPUT_SCHEMA_PROFILE: "compact", REA_MCP_OUTPUT_SCHEMA_PROFILE: "off"} + .' <<< "$REA_ENV")"
fi
EXTRAS_TXT=""
[ $USA_REA -eq 1 ] && EXTRAS_TXT="REA (engenharia reversa)"
[ -e "$HOME/.claude/skills/ponytail/SKILL.md" ] && EXTRAS_TXT="${EXTRAS_TXT:+$EXTRAS_TXT, }Ponytail"
command -v pyright-langserver >/dev/null 2>&1 && EXTRAS_TXT="${EXTRAS_TXT:+$EXTRAS_TXT, }Pyright"

echo
echo "Projeto: $PROJETO  ($P)"
echo "Modelo : $MODELO (contexto $CTX tokens) | agente: $AGENTE"
[ -n "$EXTRAS_TXT" ] && echo "Extras : $EXTRAS_TXT"
echo "Esc interrompe a resposta | Ctrl+D sai da conversa (no Claude Code tambem /exit)"
sleep "${AGENTE_HX_PAUSA_SEG:-3}"

trap 'true' INT   # Ctrl+C e da conversa; este script so espera ela acabar
if [ "$AGENTE" = opencode ]; then
  CFG="$ESTADO_DIR/opencode-conversa.json"
  jq -n --arg m "$MODELO" --arg url "$URL/v1" --argjson ctx "$CTX" --argjson rea "$USA_REA" --argjson reaenv "$REA_ENV" '{
    "$schema": "https://opencode.ai/config.json",
    model: ("llamacpp/" + $m),
    small_model: ("llamacpp/" + $m),
    enabled_providers: ["llamacpp"],
    autoupdate: false,
    share: "disabled",
    provider: {
      llamacpp: {
        npm: "@ai-sdk/openai-compatible",
        name: "llama-server (Predator)",
        options: { baseURL: $url, apiKey: "local", timeout: 1800000 },
        models: { ($m): { name: $m, tool_call: true, reasoning: false,
                          limit: { context: $ctx, output: 8192 } } }
      }
    },
    permission: {
      edit: "allow",
      bash: { "*": "allow",
              "rm -r *": "ask", "rm -rf *": "ask", "git push*": "ask", "git reset --hard*": "ask",
              "git clean*": "ask", "sudo *": "deny" },
      webfetch: "ask",
      websearch: "deny",
      external_directory: "ask",
      doom_loop: "ask",
      question: "allow"
    }
  } + (if $rea == 1 then {mcp: {rea: {type: "local", command: ["rea", "mcp"], enabled: true,
                                       environment: $reaenv}}} else {} end)' > "$CFG"
  OPENCODE_CONFIG="$CFG" OPENCODE_DISABLE_LSP_DOWNLOAD=1 OPENCODE_DISABLE_MODELS_FETCH=1 \
    opencode "$P" 8>&-
  rc=$?
else
  # Pula a tela de boas-vindas (tema/login) e a pergunta "confia nesta pasta?": aqui ele so fala com o modelo local.
  [ -s "$HOME/.claude.json" ] || printf '{}\n' > "$HOME/.claude.json"
  tmp="$(mktemp)"
  if jq --arg p "$P" '.hasCompletedOnboarding = true | .projects[$p].hasTrustDialogAccepted = true' \
       "$HOME/.claude.json" > "$tmp" 2>/dev/null; then
    cat "$tmp" > "$HOME/.claude.json"
  fi
  rm -f "$tmp"
  MCP_ARGS=()
  if [ $USA_REA -eq 1 ]; then
    MCPF="$ESTADO_DIR/mcp-conversa.json"
    jq -n --argjson reaenv "$REA_ENV" '{mcpServers: {rea: {type: "stdio", command: "rea", args: ["mcp"], env: $reaenv}}}' > "$MCPF"
    MCP_ARGS=(--mcp-config "$MCPF")
  fi
  env -u ANTHROPIC_API_KEY \
    ANTHROPIC_BASE_URL="$URL" ANTHROPIC_AUTH_TOKEN="local-sem-chave" \
    ANTHROPIC_MODEL="$MODELO" ANTHROPIC_DEFAULT_SONNET_MODEL="$MODELO" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="$MODELO" ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODELO" \
    CLAUDE_CODE_MAX_CONTEXT_TOKENS="$CTX" CLAUDE_CODE_MAX_OUTPUT_TOKENS=8192 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1 \
    CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL=1 \
    API_TIMEOUT_MS=1800000 BASH_DEFAULT_TIMEOUT_MS=600000 BASH_MAX_TIMEOUT_MS=1800000 MAX_MCP_OUTPUT_TOKENS=8000 \
    claude --model "$MODELO" --permission-mode acceptEdits --disallowedTools "WebSearch" "${MCP_ARGS[@]}" 8>&-
  rc=$?
fi
trap - INT
[ "$rc" -eq 130 ] && rc=0

# Guarda no git o que a conversa mudou: vira um ponto de volta (da para pedir "desfaca a ultima conversa").
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  git add -A >/dev/null 2>&1
  if "${GITC[@]}" commit -qm "conversa ($AGENTE): mudancas feitas no chat" >/dev/null 2>&1; then
    info "o que mudou nesta conversa ficou salvo no historico do projeto (git)."
  fi
fi
exit "$rc"
