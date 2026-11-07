#!/usr/bin/env bash
# Agente HX - andamento dos projetos.
#   agente-status.sh               resumo de todos os projetos
#   agente-status.sh <nome>        detalhe de um projeto (tarefas e ultimas linhas do log)
#   agente-status.sh --lista       so os nomes (usado pelos atalhos do Windows)
#   agente-status.sh --parar <nome>  pede para o loop parar no fim da rodada atual
set -uo pipefail
AQUI="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"   # resolve o atalho de /usr/local/bin
# shellcheck source=../lib/comum.sh
. "$AQUI/../lib/comum.sh"

projetos() {
  local d
  [ -d "$PROJETOS_DIR" ] || return 0
  for d in "$PROJETOS_DIR"/*/; do
    [ -f "$d/PLAN.md" ] && basename "$d"
  done
  return 0
}

rodando() {   # 0 se ha um loop segurando a trava do projeto
  local lock="$PROJETOS_DIR/$1/.agente/loop.lock"
  [ -f "$lock" ] || return 1
  if flock -n "$lock" true 2>/dev/null; then return 1; fi
  return 0
}

conversando() {   # 0 se ha uma conversa (4-CONVERSAR) aberta no projeto
  local lock="$PROJETOS_DIR/$1/.agente/conversa.lock"
  [ -f "$lock" ] || return 1
  if flock -n "$lock" true 2>/dev/null; then return 1; fi
  return 0
}

resumo() {
  local p=$1 dir="$PROJETOS_DIR/$1" feitas pend bloq estado atual
  feitas=$(conta_plano "$RE_FEITA" "$dir/PLAN.md")
  pend=$(conta_plano "$RE_PEND" "$dir/PLAN.md")
  bloq=$(conta_plano "$RE_BLOQ" "$dir/PLAN.md")
  estado="parado"
  rodando "$p" && estado="RODANDO"
  conversando "$p" && estado="CONVERSA"
  [ -f "$dir/.agente/PARAR" ] && estado="$estado (vai parar no fim da rodada)"
  printf '%-28s %-10s feitas %3s | pendentes %3s | bloqueadas %3s\n' "$p" "$estado" "$feitas" "$pend" "$bloq"
  atual="$(grep -m1 -E "$RE_PEND" "$dir/PLAN.md" 2>/dev/null || true)"
  [ -n "$atual" ] && printf '   proxima: %s\n' "$(texto_tarefa "$atual")"
  return 0
}

case "${1:-}" in
  --lista)
    projetos
    ;;
  --parar)
    p="${2:-}"
    nome_valido "$p" && [ -d "$PROJETOS_DIR/$p" ] || { erro "projeto nao encontrado: '$p'"; exit 2; }
    mkdir -p "$PROJETOS_DIR/$p/.agente"
    touch "$PROJETOS_DIR/$p/.agente/PARAR"
    if rodando "$p"; then
      info "ok: o agente de '$p' para quando terminar a rodada atual (e gera o RELATORIO.md)."
    else
      info "o agente de '$p' nao esta rodando agora; o pedido de parada fica registrado."
      rm -f "$PROJETOS_DIR/$p/.agente/PARAR"
    fi
    ;;
  "")
    lista="$(projetos)"
    if [ -z "$lista" ]; then echo "Nenhum projeto ainda. Use 2-NOVO-PROJETO."; exit 0; fi
    echo "Projetos em $PROJETOS_DIR"
    echo
    while IFS= read -r p; do resumo "$p"; echo; done <<< "$lista"
    ;;
  *)
    p="$1"
    nome_valido "$p" && [ -d "$PROJETOS_DIR/$p" ] || { erro "projeto nao encontrado: '$p'"; exit 2; }
    dir="$PROJETOS_DIR/$p"
    resumo "$p"
    echo
    echo "--- tarefas (PLAN.md)"
    grep -E "$RE_TAREFA" "$dir/PLAN.md" | tr -d '\r'
    echo
    echo "--- ultimas linhas do loop"
    tail -n 15 "$dir/.agente/logs/loop.log" 2>/dev/null || echo "(o agente ainda nao rodou neste projeto)"
    [ -f "$dir/RELATORIO.md" ] && { echo; echo "--- RELATORIO.md existe: abra a pasta do projeto para ler."; }
    ;;
esac
