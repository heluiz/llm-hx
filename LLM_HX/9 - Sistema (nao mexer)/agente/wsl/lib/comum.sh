# shellcheck shell=bash
# Agente HX - funcoes comuns dos scripts do WSL (carregado com ". lib/comum.sh").
# Mensagens so com ASCII: o console do Windows nem sempre mostra acentos certo.

AGENTE_HX_DIR="${AGENTE_HX_DIR:-/opt/agente-hx}"
PROJETOS_DIR="${PROJETOS_DIR:-$HOME/projetos}"

# wsl.exe -e roda sem shell de login: garante o PATH das ferramentas do agente.
export PATH="$HOME/.opencode/bin:$HOME/.local/bin:/usr/local/bin:$PATH"
# Ninguem atualiza nada sozinho no meio de uma corrida de dias.
export OPENCODE_DISABLE_AUTOUPDATE=1
export DISABLE_AUTOUPDATER=1

ts() { date '+%Y-%m-%d %H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
aviso() { printf '[%s] AVISO: %s\n' "$(ts)" "$*" >&2; }
erro() { printf '[%s] ERRO: %s\n' "$(ts)" "$*" >&2; }

# Nome de projeto: minusculas, numeros, hifen e sublinhado (vira nome de pasta).
nome_valido() { [[ "${1:-}" =~ ^[a-z0-9][a-z0-9_-]{0,63}$ ]]; }

# 3725 -> "1h 02min"
duracao() {
  local s=${1:-0}
  printf '%dh %02dmin' $((s / 3600)) $(((s % 3600) / 60))
}

# Linhas de tarefa do PLAN.md: "- [ ] ...", "- [x] ...", "- [!] ..." (aceita * no lugar do -).
RE_PEND='^[[:space:]]*[-*][[:space:]]+\[[[:space:]]\][[:space:]]+'
RE_FEITA='^[[:space:]]*[-*][[:space:]]+\[[xX]\][[:space:]]+'
RE_BLOQ='^[[:space:]]*[-*][[:space:]]+\[!\][[:space:]]+'
RE_TAREFA='^[[:space:]]*[-*][[:space:]]+\[([[:space:]]|[xX]|!)\][[:space:]]+'

# conta_plano <regex> [arquivo] -> numero de linhas que casam
conta_plano() { grep -cE "$1" "${2:-PLAN.md}" 2>/dev/null || true; }

# texto da tarefa sem a caixinha e sem \r
texto_tarefa() { printf '%s' "$1" | tr -d '\r' | sed -E "s/$RE_TAREFA//"; }
