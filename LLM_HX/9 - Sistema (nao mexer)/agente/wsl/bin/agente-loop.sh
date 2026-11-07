#!/usr/bin/env bash
# Agente HX - loop de rodadas (tecnica "Ralph"): chama o agente varias vezes, sempre com
# contexto limpo, ate todas as tarefas do PLAN.md ficarem prontas ou bloqueadas.
#
#   agente-loop.sh <projeto> [--agente opencode|claude] [--tentativas 4] [--minutos 60]
#                            [--rodadas 400] [--porta 8090] [--turnos 80] [--verificacao 30]
#
# Cada rodada: espera o servidor -> pega a 1a tarefa "- [ ]" -> chama o agente ->
# desfaz mexidas nos arquivos protegidos -> roda verificar.sh -> commit ou nova tentativa.
# Para parar com calma: crie .agente/PARAR no projeto (atalho 7-PARAR-PROJETO).
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

AQUI="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"   # resolve o atalho de /usr/local/bin
# shellcheck source=../lib/comum.sh
. "$AQUI/../lib/comum.sh"

PROJETO=""
AGENTE="opencode"
TENTATIVAS=4
MINUTOS=60
RODADAS_MAX=400
PORTA=8090
TURNOS=80
VERIF_MIN=30

while [ $# -gt 0 ]; do
  case "$1" in
    --agente) AGENTE="${2:-}"; shift 2 || shift ;;
    --tentativas) TENTATIVAS="${2:-}"; shift 2 || shift ;;
    --minutos) MINUTOS="${2:-}"; shift 2 || shift ;;
    --rodadas) RODADAS_MAX="${2:-}"; shift 2 || shift ;;
    --porta) PORTA="${2:-}"; shift 2 || shift ;;
    --turnos) TURNOS="${2:-}"; shift 2 || shift ;;
    --verificacao) VERIF_MIN="${2:-}"; shift 2 || shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    -*) erro "opcao desconhecida: $1"; exit 2 ;;
    *) PROJETO="$1"; shift ;;
  esac
done

for v in TENTATIVAS MINUTOS RODADAS_MAX PORTA TURNOS VERIF_MIN; do
  if ! [[ "${!v}" =~ ^[0-9]+$ ]] || [ "${!v}" -le 0 ]; then erro "valor invalido para $v: '${!v}'"; exit 2; fi
done
case "$AGENTE" in opencode|claude) ;; *) erro "agente deve ser opencode ou claude (veio '$AGENTE')"; exit 2 ;; esac
if ! nome_valido "$PROJETO"; then erro "nome de projeto invalido: '$PROJETO'"; exit 2; fi

P="$PROJETOS_DIR/$PROJETO"
[ -d "$P" ] || { erro "projeto nao encontrado: $P"; exit 2; }
cd "$P" || exit 2
for f in SPEC.md PLAN.md; do
  [ -f "$f" ] || { erro "falta o arquivo $f no projeto"; exit 2; }
done

ESTADO="$P/.agente"
LOGS="$ESTADO/logs"
ANTES="$ESTADO/antes"
mkdir -p "$LOGS" "$ANTES"
URL="http://127.0.0.1:$PORTA"
LOG_LOOP="$LOGS/loop.log"
SINAL="$ESTADO/CONCLUIDA"
PROMPT_MODELO="$AGENTE_HX_DIR/prompts/rodada.md"
PROTEGIDOS=(SPEC.md PLAN.md AGENTS.md CLAUDE.md verificar.sh)
GITC=(git -c user.name="Agente HX" -c user.email="agente@local" -c commit.gpgsign=false)

# Um loop por projeto.
exec 9>"$ESTADO/loop.lock"
if ! flock -n 9; then erro "ja tem um agente rodando neste projeto (feche a outra janela primeiro)"; exit 2; fi
# ...e nunca junto com uma conversa aberta no mesmo projeto (4-CONVERSAR-COM-O-AGENTE).
if [ -f "$ESTADO/conversa.lock" ] && ! flock -n "$ESTADO/conversa.lock" true 2>/dev/null; then
  erro "tem uma conversa aberta neste projeto (4-CONVERSAR-COM-O-AGENTE): feche a conversa antes de rodar o agente sozinho"
  exit 2
fi

registrar() {
  local msg
  msg="[$(ts)] $*"
  printf '%s\n' "$msg"
  printf '%s\n' "$msg" >> "$LOG_LOOP"
}

# A trava (fd 9) fica so com este script: o agente roda com "9>&-", entao um programa que ele deixe
# rodando em segundo plano nao segura a trava depois que o loop termina.
AG_PID=""
parar_agente() {   # o timeout roda o agente num grupo de processos proprio: derruba o grupo todo
  if [ -n "$AG_PID" ]; then kill -TERM -- "-$AG_PID" 2>/dev/null || kill -TERM "$AG_PID" 2>/dev/null; fi
  return 0
}
trap 'parar_agente; registrar "loop interrompido (janela fechada ou Ctrl+C)"; exit 130' INT TERM HUP

# ---------------------------------------------------------------- ferramentas
if [ ! -f "$PROMPT_MODELO" ]; then erro "nao achei $PROMPT_MODELO (rode o instalador de novo)"; exit 2; fi
case "$AGENTE" in
  opencode) command -v opencode >/dev/null 2>&1 || { erro "opencode nao instalado (rode 0-INSTALAR-AGENTE)"; exit 2; } ;;
  claude)   command -v claude   >/dev/null 2>&1 || { erro "claude nao instalado (rode 0-INSTALAR-AGENTE)"; exit 2; } ;;
esac
OC_SKIP=()
if [ "$AGENTE" = opencode ]; then
  oc_ajuda="$(opencode run --help 2>&1 || true)"
  if grep -q -- '--dangerously-skip-permissions' <<< "$oc_ajuda"; then
    OC_SKIP=(--dangerously-skip-permissions)   # dentro da distro isolada; os "deny" do opencode.json continuam valendo
  fi
fi

# ---------------------------------------------------------------- git
if [ ! -d .git ]; then git init -q -b main; fi
if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ]; then printf '\n' >> .gitignore; fi
grep -qxF '.agente/' .gitignore 2>/dev/null || printf '.agente/\n' >> .gitignore
if ! git rev-parse -q --verify HEAD >/dev/null 2>&1; then
  git add -A
  "${GITC[@]}" commit -qm "inicio do projeto" >/dev/null 2>&1 || true
fi
# Mudancas suas no plano/especificacao (feitas com o loop parado) entram num commit proprio.
mapfile -t _prot < <(for f in "${PROTEGIDOS[@]}" .gitignore; do [ -e "$f" ] && printf '%s\n' "$f"; done)
if [ ${#_prot[@]} -gt 0 ] && [ -n "$(git status --porcelain -- "${_prot[@]}")" ]; then
  git add -- "${_prot[@]}"
  "${GITC[@]}" commit -qm "ajustes manuais no plano/especificacao" -- "${_prot[@]}" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------- servidor
MODELO="local"
CTX=65536
servidor_ok() { curl -sf -m 5 "$URL/health" >/dev/null 2>&1; }
esperar_servidor() {
  local ultimo=-100000
  while ! servidor_ok; do
    [ -f "$ESTADO/PARAR" ] && return 1
    if [ $((SECONDS - ultimo)) -ge 1800 ]; then
      registrar "aguardando o servidor do modelo em $URL (pausa do pregao, pausado ou desligado)..."
      ultimo=$SECONDS
    fi
    sleep "${AGENTE_HX_ESPERA_SEG:-15}"
  done
  return 0
}
info_modelo() {
  local m c
  m="$(curl -sf -m 10 "$URL/v1/models" 2>/dev/null | jq -r '.data[0].id // empty' 2>/dev/null)"
  c="$(curl -sf -m 10 "$URL/props" 2>/dev/null | jq -r '.default_generation_settings.n_ctx // empty' 2>/dev/null)"
  [ -n "$m" ] && MODELO="$m"
  [[ "$c" =~ ^[0-9]+$ ]] && CTX="$c"
  return 0
}

# ---------------------------------------------------------------- plano
proxima_tarefa() { grep -m1 -E "$RE_PEND" PLAN.md 2>/dev/null || true; }

# troca_linha "<linha exata atual>" "<linha nova>"  (so a 1a ocorrencia; sem interpretar \)
troca_linha() {
  local tmp
  tmp="$(mktemp)"
  VELHA="$1" NOVA="$2" awk 'BEGIN { v = ENVIRON["VELHA"]; n = ENVIRON["NOVA"]; feito = 0 }
    { if (!feito && $0 == v) { print n; feito = 1 } else { print } }' PLAN.md > "$tmp" && cat "$tmp" > PLAN.md
  rm -f "$tmp"
}
marcar_feita() {
  local linha=$1 cr="" base nova
  [[ "$linha" == *$'\r' ]] && cr=$'\r'
  base="${linha%$'\r'}"
  nova="$(printf '%s' "$base" | sed -E 's/\[[[:space:]]\]/[x]/')"
  troca_linha "$linha" "$nova$cr"
}
marcar_bloqueada() {
  local linha=$1 motivo=$2 cr="" base nova
  [[ "$linha" == *$'\r' ]] && cr=$'\r'
  base="${linha%$'\r'}"
  nova="$(printf '%s' "$base" | sed -E 's/\[[[:space:]]\]/[!]/')  (BLOQUEADA: $motivo)"
  troca_linha "$linha" "$nova$cr"
}

# ---------------------------------------------------------------- arquivos protegidos
guardar_protegidos() {
  rm -rf "$ANTES"
  mkdir -p "$ANTES"
  local f
  for f in "${PROTEGIDOS[@]}" PROGRESS.md; do
    [ -f "$f" ] && cp -p "$f" "$ANTES/$f"
  done
  return 0
}
restaurar_protegidos() {   # desfaz o que o agente mexeu nos arquivos que so voce/o loop alteram
  local f
  for f in "${PROTEGIDOS[@]}"; do
    if [ -f "$ANTES/$f" ] && ! cmp -s "$ANTES/$f" "$f" 2>/dev/null; then
      cp -p "$ANTES/$f" "$f"
      registrar "  o agente mexeu em $f - desfeito (esse arquivo e seu/do loop)"
    fi
  done
  return 0
}
sinal_de_conclusao() {      # o agente diz que terminou: arquivo .agente/CONCLUIDA ou TAREFA_CONCLUIDA no PROGRESS.md
  [ -f "$SINAL" ] && return 0
  [ -f PROGRESS.md ] || return 1
  local novas
  if [ -f "$ANTES/PROGRESS.md" ]; then
    novas="$(diff "$ANTES/PROGRESS.md" PROGRESS.md 2>/dev/null | grep -E '^>' || true)"   # so as linhas desta rodada
  else
    novas="$(cat PROGRESS.md)"
  fi
  grep -qE 'TAREFA_CONCLU(I|Í)DA' <<< "$novas"
}

# ---------------------------------------------------------------- agente
montar_prompt() {   # $1 tarefa (texto) $2 tentativa $3 log da ultima verificacao com falha (ou vazio)
  local tarefa=$1 tent=$2 falha_log=${3:-} falha="" notas="" p
  if [ -n "$falha_log" ] && [ -s "$falha_log" ]; then
    falha="## O que deu errado na tentativa anterior

A verificacao (bash verificar.sh) falhou. Ultimas linhas da saida:

\`\`\`
$(tail -n 60 "$falha_log" | cut -c1-400 | tail -c 6000)
\`\`\`
Comece corrigindo isso."
  fi
  if [ -f PROGRESS.md ]; then notas="$(tail -n 30 PROGRESS.md | tail -c 4000)"; fi
  p="$(cat "$PROMPT_MODELO")"
  p="${p//'{{RODADA}}'/"$RODADA"}"
  p="${p//'{{TAREFA}}'/"$tarefa"}"
  p="${p//'{{TENTATIVA}}'/"$tent"}"
  p="${p//'{{TENTATIVAS}}'/"$TENTATIVAS"}"
  p="${p//'{{FALHA_ANTERIOR}}'/"$falha"}"
  p="${p//'{{NOTAS}}'/"$notas"}"
  printf '%s\n' "$p"
}

config_opencode() {   # gera o opencode.json desta corrida (fora do projeto)
  local cfg=$1
  jq -n --arg m "$MODELO" --arg url "$URL/v1" --argjson ctx "$CTX" '{
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
              "git commit*": "deny", "git push*": "deny", "git reset*": "deny", "git checkout*": "deny",
              "git clean*": "deny", "git stash*": "deny", "git rebase*": "deny", "git restore*": "deny",
              "sudo *": "deny" },
      webfetch: "deny",
      websearch: "deny",
      external_directory: "deny",
      doom_loop: "deny",
      question: "deny"
    }
  }' > "$cfg"
}

rodar_agente() {   # $1 arquivo do prompt, $2 log  -> codigo de saida do agente (124 = estourou o tempo)
  local pf=$1 lg=$2 limite="${AGENTE_HX_LIMITE_SEG:-$((MINUTOS * 60))}"
  if [ "$AGENTE" = opencode ]; then
    local cfg="$ESTADO/opencode.json"
    config_opencode "$cfg"
    OPENCODE_CONFIG="$cfg" OPENCODE_DISABLE_LSP_DOWNLOAD=1 OPENCODE_DISABLE_MODELS_FETCH=1 \
      timeout --kill-after=60 "$limite" \
      opencode run --model "llamacpp/$MODELO" "${OC_SKIP[@]}" "$(cat "$pf")" < /dev/null > "$lg" 2>&1 9>&- &
  else
    env -u ANTHROPIC_API_KEY \
      ANTHROPIC_BASE_URL="$URL" ANTHROPIC_AUTH_TOKEN="local-sem-chave" \
      ANTHROPIC_MODEL="$MODELO" ANTHROPIC_DEFAULT_SONNET_MODEL="$MODELO" \
      ANTHROPIC_DEFAULT_OPUS_MODEL="$MODELO" ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODELO" \
      CLAUDE_CODE_MAX_CONTEXT_TOKENS="$CTX" CLAUDE_CODE_MAX_OUTPUT_TOKENS=8192 \
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1 \
      CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL=1 \
      API_TIMEOUT_MS=1800000 BASH_DEFAULT_TIMEOUT_MS=600000 BASH_MAX_TIMEOUT_MS=1800000 \
      timeout --kill-after=60 "$limite" \
      claude -p --model "$MODELO" --dangerously-skip-permissions --max-turns "$TURNOS" \
        --no-session-persistence --output-format text \
        --disallowedTools "Bash(git commit *)" "Bash(git push *)" "Bash(git reset *)" \
        "Bash(git checkout *)" "Bash(git clean *)" "Bash(git stash *)" "Bash(git rebase *)" \
        "Bash(git restore *)" "Bash(sudo *)" "WebFetch" "WebSearch" \
        < "$pf" > "$lg" 2>&1 9>&- &
  fi
  AG_PID=$!
  local c=0
  wait "$AG_PID" || c=$?
  AG_PID=""
  return $c
}

# ---------------------------------------------------------------- relatorio
ULTIMA_VERIF=""
gerar_relatorio() {   # $1 motivo do fim
  local motivo=$1
  {
    printf '# Relatório do agente — %s\n\n' "$PROJETO"
    printf -- '- Fim: %s (%s)\n' "$(ts)" "$motivo"
    printf -- '- Rodadas nesta corrida: %s · tempo: %s\n' "$RODADA" "$(duracao $((SECONDS - T0)))"
    printf -- '- Modelo: %s (contexto %s) · agente: %s\n\n' "$MODELO" "$CTX" "$AGENTE"
    printf '## Concluídas (%s)\n\n' "$(conta_plano "$RE_FEITA")"
    grep -E "$RE_FEITA" PLAN.md | while IFS= read -r l; do printf -- '- %s\n' "$(texto_tarefa "$l")"; done
    printf '\n## Bloqueadas (%s)\n\n' "$(conta_plano "$RE_BLOQ")"
    grep -E "$RE_BLOQ" PLAN.md | while IFS= read -r l; do printf -- '- %s\n' "$(texto_tarefa "$l")"; done
    printf '\n## Pendentes (%s)\n\n' "$(conta_plano "$RE_PEND")"
    grep -E "$RE_PEND" PLAN.md | while IFS= read -r l; do printf -- '- %s\n' "$(texto_tarefa "$l")"; done
    if [ -n "$ULTIMA_VERIF" ] && [ -f "$ULTIMA_VERIF" ]; then
      printf '\n## Última verificação\n\n```\n%s\n```\n' "$(tail -n 30 "$ULTIMA_VERIF")"
    fi
    printf '\n## Histórico (git log)\n\n```\n%s\n```\n' "$(git log --oneline -n 60 2>/dev/null)"
    printf '\nAs tentativas que falharam e foram descartadas ficam guardadas em: git stash list\n'
  } > RELATORIO.md
  cp -f RELATORIO.md "$ESTADO/RELATORIO.md"
  git add -A >/dev/null 2>&1
  "${GITC[@]}" commit -qm "relatorio final ($motivo)" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------- inicio
T0=$SECONDS
RODADA=0
rm -f "$ESTADO/PARAR" "$SINAL"
total=$(( $(conta_plano "$RE_PEND") + $(conta_plano "$RE_FEITA") + $(conta_plano "$RE_BLOQ") ))
if [ "$total" -eq 0 ]; then erro "o PLAN.md nao tem nenhuma tarefa no formato '- [ ] ...'"; exit 2; fi
[ -f verificar.sh ] || aviso "sem verificar.sh: o loop vai confiar so no que o agente disser (menos seguro)"

registrar "=== Agente HX: projeto '$PROJETO' | agente $AGENTE | ate $TENTATIVAS tentativas por tarefa | $MINUTOS min por rodada ==="
registrar "tarefas: $(conta_plano "$RE_FEITA") feitas, $(conta_plano "$RE_PEND") pendentes, $(conta_plano "$RE_BLOQ") bloqueadas"

FALHA_LOG=""
while :; do
  if [ -f "$ESTADO/PARAR" ]; then
    rm -f "$ESTADO/PARAR"
    registrar "parado a pedido (PARAR)."
    gerar_relatorio "parado a pedido"
    exit 3
  fi
  linha="$(proxima_tarefa)"
  if [ -z "$linha" ]; then
    registrar "nao ha mais tarefas pendentes. Fim."
    gerar_relatorio "todas as tarefas processadas"
    registrar "relatorio: RELATORIO.md ($(conta_plano "$RE_FEITA") concluidas, $(conta_plano "$RE_BLOQ") bloqueadas)"
    exit 0
  fi
  if [ "$RODADA" -ge "$RODADAS_MAX" ]; then
    registrar "limite de $RODADAS_MAX rodadas atingido."
    gerar_relatorio "limite de rodadas"
    exit 4
  fi

  if ! esperar_servidor; then continue; fi
  info_modelo

  tarefa="$(texto_tarefa "$linha")"
  # tentativas da tarefa atual (zera quando muda de tarefa)
  if [ "$(cat "$ESTADO/tarefa" 2>/dev/null)" != "$tarefa" ]; then
    printf '%s' "$tarefa" > "$ESTADO/tarefa"
    echo 0 > "$ESTADO/tentativas"
    FALHA_LOG=""
  fi
  tent=$(( $(cat "$ESTADO/tentativas" 2>/dev/null || echo 0) + 1 ))
  RODADA=$((RODADA + 1))
  seq_total=$(( $(cat "$ESTADO/contador" 2>/dev/null || echo 0) + 1 ))   # numero da rodada somando todas as corridas
  echo "$seq_total" > "$ESTADO/contador"
  n="$(printf '%04d' "$seq_total")"
  LOG_AG="$LOGS/rodada-$n-agente.log"
  LOG_VF="$LOGS/rodada-$n-verificacao.log"
  PF="$ESTADO/prompt.md"

  registrar "rodada $RODADA | tarefa: $tarefa | tentativa $tent/$TENTATIVAS | modelo $MODELO"
  montar_prompt "$tarefa" "$tent" "$FALHA_LOG" > "$PF"
  rm -f "$SINAL"
  guardar_protegidos
  inicio=$SECONDS
  rodar_agente "$PF" "$LOG_AG"
  cod=$?
  restaurar_protegidos
  concluiu=0
  if sinal_de_conclusao; then concluiu=1; fi
  rm -f "$SINAL"

  if [ $concluiu -eq 0 ] && ! servidor_ok; then
    registrar "  rodada interrompida: o servidor saiu do ar (pausa do pregao?). O trabalho fica na pasta e a tarefa continua depois."
    continue
  fi
  [ $cod -eq 124 ] && registrar "  o agente estourou o limite de $MINUTOS min nesta rodada"

  if [ -f verificar.sh ]; then
    timeout --kill-after=30 "$((VERIF_MIN * 60))" bash verificar.sh > "$LOG_VF" 2>&1 < /dev/null
    vcod=$?
  else
    echo "(projeto sem verificar.sh)" > "$LOG_VF"
    vcod=0
  fi
  ULTIMA_VERIF="$LOG_VF"
  dur="$(duracao $((SECONDS - inicio)))"

  if [ $vcod -eq 0 ] && [ $concluiu -eq 1 ]; then
    marcar_feita "$linha"
    git add -A >/dev/null 2>&1
    "${GITC[@]}" commit -qm "rodada $RODADA: concluida - $tarefa" >/dev/null 2>&1 || true
    echo 0 > "$ESTADO/tentativas"
    FALHA_LOG=""
    registrar "  OK em $dur: tarefa concluida e verificada (commit feito). Agora: $(conta_plano "$RE_FEITA") feitas, $(conta_plano "$RE_PEND") pendentes"
    continue
  fi

  echo "$tent" > "$ESTADO/tentativas"
  if [ $vcod -eq 0 ]; then
    # verificacao passou mas o agente nao disse que terminou: guarda o avanco
    if [ -n "$(git status --porcelain)" ]; then
      git add -A >/dev/null 2>&1
      "${GITC[@]}" commit -qm "rodada $RODADA: progresso - $tarefa" >/dev/null 2>&1 || true
    fi
    FALHA_LOG=""
    registrar "  em $dur: verificacao passou, mas o agente nao confirmou que terminou (tentativa $tent/$TENTATIVAS)"
  else
    FALHA_LOG="$LOG_VF"
    if [ $concluiu -eq 1 ]; then
      registrar "  em $dur: o agente disse que terminou, mas a verificacao FALHOU (tentativa $tent/$TENTATIVAS)"
    else
      registrar "  em $dur: verificacao falhou (tentativa $tent/$TENTATIVAS). Log: $LOG_VF"
    fi
  fi

  if [ "$tent" -ge "$TENTATIVAS" ]; then
    if [ $vcod -ne 0 ]; then
      motivo="verificacao falhou $tent vezes"
      if [ -n "$(git status --porcelain)" ]; then
        git stash push -u -q -m "agente: tentativa descartada - $tarefa" >/dev/null 2>&1 || true
      fi
    else
      motivo="agente nao confirmou a conclusao em $tent tentativas - revise"
    fi
    marcar_bloqueada "$linha" "$motivo"
    {
      printf '\n## Rodada %s — tarefa BLOQUEADA pelo loop\n' "$RODADA"
      printf -- '- Tarefa: %s\n- Motivo: %s\n' "$tarefa" "$motivo"
      [ $vcod -ne 0 ] && printf -- '- A última tentativa foi guardada no git stash; a pasta voltou ao último commit bom.\n'
    } >> PROGRESS.md
    git add -A >/dev/null 2>&1
    "${GITC[@]}" commit -qm "rodada $RODADA: bloqueada - $tarefa" >/dev/null 2>&1 || true
    echo 0 > "$ESTADO/tentativas"
    FALHA_LOG=""
    registrar "  tarefa BLOQUEADA ($motivo). Seguindo para a proxima."
  fi
done
