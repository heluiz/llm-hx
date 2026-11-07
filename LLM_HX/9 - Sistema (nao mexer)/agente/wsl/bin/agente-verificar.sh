#!/usr/bin/env bash
# Agente HX - confere a distro do agente: isolamento, ferramentas e conexao com o servidor.
#   agente-verificar.sh [--porta 8090]
set -uo pipefail
AQUI="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"   # resolve o atalho de /usr/local/bin
# shellcheck source=../lib/comum.sh
. "$AQUI/../lib/comum.sh"

PORTA=8090
[ "${1:-}" = "--porta" ] && PORTA="${2:-8090}"
falhas=0
ok()   { printf '  OK    %s\n' "$*"; }
ruim() { printf '  FALHA %s\n' "$*"; falhas=$((falhas + 1)); }
obs()  { printf '  --    %s\n' "$*"; }

echo "Distro do agente: $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-?}") | usuario: $(whoami)"
echo
echo "[isolamento]"
if [ "$(id -u)" -ne 0 ]; then ok "roda como usuario comum ($(whoami)), nao como root"; else ruim "esta rodando como root"; fi
if sudo -n true 2>/dev/null; then ruim "o usuario tem sudo sem senha"; else ok "sem sudo"; fi
if [ -d /mnt/c/Windows ]; then ruim "o disco C: do Windows esta visivel em /mnt/c (automount ligado)"; else ok "nao enxerga o disco C: do Windows"; fi
# O registro WSLInterop em /proc/sys/fs/binfmt_misc e do kernel e vale para todas as distros da VM do WSL
# (vem das suas outras distros). O que decide e esta distro: com [interop] enabled=false o init do WSL nao
# abre o canal com o Windows e nem cria WSL_INTEROP, entao pedidos para rodar .exe daqui sao descartados.
interop_cfg="$(awk -F= '/^[[:space:]]*\[/{sec=$0} sec ~ /\[interop\]/ && $1 ~ /^[[:space:]]*enabled[[:space:]]*$/ {v=$2; gsub(/[[:space:]]/, "", v); print tolower(v)}' /etc/wsl.conf 2>/dev/null | tail -n1)"
if [ "$interop_cfg" = "false" ] && [ -z "${WSL_INTEROP:-}" ] && ! command -v cmd.exe >/dev/null 2>&1 && ! command -v powershell.exe >/dev/null 2>&1; then
  ok "nao abre programas do Windows (interop desligado nesta distro)"
  [ -e /proc/sys/fs/binfmt_misc/WSLInterop ] && obs "o registro WSLInterop que aparece no kernel vem das outras distros; aqui ele nao funciona"
else
  ruim "consegue abrir programas do Windows (interop=${interop_cfg:-ligado}, WSL_INTEROP=${WSL_INTEROP:-vazio})"
fi

echo
echo "[ferramentas]"
for c in git python3 jq curl rg; do
  if command -v "$c" >/dev/null 2>&1; then ok "$c"; else ruim "$c nao encontrado"; fi
done
if python3 -m pytest --version >/dev/null 2>&1; then ok "pytest"; else ruim "pytest nao encontrado"; fi
if command -v opencode >/dev/null 2>&1; then ok "opencode $(opencode --version < /dev/null 2>/dev/null | head -n1)"; else ruim "opencode nao instalado"; fi
if command -v claude >/dev/null 2>&1; then ok "claude $(claude --version < /dev/null 2>/dev/null | head -n1)"; else ruim "claude (Claude Code) nao instalado"; fi
[ -d "$PROJETOS_DIR" ] && ok "pasta de projetos: $PROJETOS_DIR" || ruim "pasta de projetos nao existe: $PROJETOS_DIR"

echo
echo "[plugins e MCPs]"
EX="$AGENTE_HX_EXTRAS_DIR"
if command -v node >/dev/null 2>&1; then ok "node $(node -v 2>/dev/null)"; else obs "node: ainda nao (os extras instalam no proximo atalho ou no ATUALIZAR-SCRIPTS)"; fi
rea_v="$(jq -r '.version // empty' "$EX/npm/lib/node_modules/rea-agents/package.json" 2>/dev/null)"
if command -v rea >/dev/null 2>&1 && [ -n "$rea_v" ]; then ok "REA $rea_v (MCP no modo conversa; comando rea nos dois modos)"; else obs "REA: nao instalado"; fi
if [ -n "${GHIDRA_INSTALL_DIR:-}" ] && [ -d "$GHIDRA_INSTALL_DIR" ]; then ok "Ghidra: $(basename "$GHIDRA_INSTALL_DIR")"; else obs "Ghidra: nao (o REA analisa JavaScript e .NET sem ele)"; fi
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then ok "Java: $("$JAVA_HOME/bin/java" -version 2>&1 | grep -v '^Picked up' | head -n1)"; else obs "Java: nao"; fi
if [ -n "${REA_JADX_MCP_JAR:-}" ] && [ -f "$REA_JADX_MCP_JAR" ]; then ok "JADX: $(basename "$REA_JADX_MCP_JAR")"; else obs "JADX: nao (so faz falta para apps Android)"; fi
if command -v pyright-langserver >/dev/null 2>&1; then ok "pyright (erros de Python depois de editar)"; else obs "pyright: nao"; fi
skills_ok=""
for s in reverse-engineer-anything ponytail ponytail-review ponytail-audit ponytail-debt; do
  [ -f "$HOME/.claude/skills/$s/SKILL.md" ] && skills_ok="$skills_ok $s"
done
if [ -n "$skills_ok" ]; then ok "skills:$skills_ok"; else obs "skills: nenhuma"; fi
if command -v claude >/dev/null 2>&1 && claude plugin list < /dev/null 2>/dev/null | grep -q 'pyright-lsp@claude-plugins-official'; then
  ok "plugin do Claude Code: pyright-lsp"
else
  obs "plugin do Claude Code pyright-lsp: nao"
fi
[ -s "$EX/AVISOS.txt" ] && obs "na ultima instalacao dos extras faltou: $(tr '\n' ' ' < "$EX/AVISOS.txt")"

echo
echo "[servidor do modelo em http://127.0.0.1:$PORTA]"
if curl -sf -m 5 "http://127.0.0.1:$PORTA/health" >/dev/null 2>&1; then
  m="$(curl -sf -m 10 "http://127.0.0.1:$PORTA/v1/models" | jq -r '.data[0].id // "?"' 2>/dev/null)"
  c="$(curl -sf -m 10 "http://127.0.0.1:$PORTA/props" | jq -r '.default_generation_settings.n_ctx // "?"' 2>/dev/null)"
  ok "respondendo: modelo $m, contexto $c tokens"
else
  obs "nao respondeu agora (normal se o 1-LIGAR-SERVIDOR estiver fechado ou em pausa)"
fi

echo
if [ $falhas -eq 0 ]; then echo "Tudo certo."; else echo "$falhas item(ns) com FALHA - veja acima."; fi
exit $falhas
