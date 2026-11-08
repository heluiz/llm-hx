#!/usr/bin/env bash
# Agente HX - plugins, MCPs e ferramentas extras do agente (rodado como root pelo instalador do Windows).
#   instalar-extras.sh [--usuario agente] [--node 24] [--rea 6.5.0] [--carimbo <texto>]
# Instala so o que falta:
#   - Node.js LTS oficial (conferido por SHA-256)        - REA: comando "rea" + servidor MCP + skill
#   - Java 21, Ghidra e JADX (os dois ultimos vem do C:\tools do Windows, pela pasta de passagem)
#   - Pyright (erros de Python logo depois de editar) e o plugin pyright-lsp do Claude Code
#   - skills do Ponytail (vem com o kit)                 - bibliotecas Python para Word, Excel e PDF
# Cada parte e independente: se uma falhar, as outras seguem e o resumo do fim mostra o que faltou.
# Codigo de saida: 0 = o essencial (Node + REA) ficou pronto; 1 = faltou o essencial; 2 = uso errado.
set -uo pipefail
USUARIO="agente"
NODE_MAJOR="24"
REA_VERSAO="6.5.0"
CARIMBO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --usuario) USUARIO="${2:-}"; shift 2 || shift ;;
    --node) NODE_MAJOR="${2:-}"; shift 2 || shift ;;
    --rea) REA_VERSAO="${2:-}"; shift 2 || shift ;;
    --carimbo) CARIMBO="${2:-}"; shift 2 || shift ;;
    *) echo "opcao desconhecida: $1" >&2; exit 2 ;;
  esac
done
[ "$(id -u)" -eq 0 ] || { echo "rode como root (wsl -u root)" >&2; exit 2; }
[[ "$USUARIO" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || { echo "usuario invalido: $USUARIO" >&2; exit 2; }
[[ "$NODE_MAJOR" =~ ^[0-9]{2}$ ]] || { echo "versao do Node invalida: $NODE_MAJOR" >&2; exit 2; }
[[ "$REA_VERSAO" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "versao do REA invalida: $REA_VERSAO" >&2; exit 2; }
HOME_U="$(getent passwd "$USUARIO" | cut -d: -f6)"
[ -n "$HOME_U" ] && [ -d "$HOME_U" ] || { echo "usuario $USUARIO sem pasta pessoal" >&2; exit 2; }

KIT="${AGENTE_HX_DIR:-/opt/agente-hx}"                       # scripts do kit (ja instalados)
EXTRAS="${AGENTE_HX_EXTRAS_DIR:-/opt/agente-hx-extras}"      # o que este script instala
STAGING="${AGENTE_HX_STAGING_DIR:-/opt/agente-hx-staging}"   # o que o Windows mandou (Ghidra, JADX)
NODE_URL="${AGENTE_HX_NODE_URL:-https://nodejs.org/dist}"
NPMDIR="$EXTRAS/npm"                                         # pacotes npm globais (sobrevivem a troca do Node)
BINDIR="${AGENTE_HX_BINDIR:-/usr/local/bin}"
OPTDIR="${AGENTE_HX_OPT_DIR:-/opt}"                          # onde fica o Node.js (/opt/node -> versao atual)
mkdir -p "$EXTRAS" "$BINDIR" "$OPTDIR"

FALTOU=()
passo() { printf '\n>>> %s\n' "$*"; }
ok() { printf '   ok: %s\n' "$*"; }
nota() { printf '   --  %s\n' "$*"; }
falhou() { printf '   FALHOU: %s\n' "$*"; FALTOU+=("$1"); }
como_usuario() { runuser -l "$USUARIO" -c "export CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1 DISABLE_AUTOUPDATER=1; $1"; }
liga_bin() { [ -x "$1" ] && ln -sf "$1" "$BINDIR/$(basename "$1")"; }

# versao do Node que o REA aceita: 22.19+, 24.11+ ou 26+
node_serve() {
  local v a b
  command -v node >/dev/null 2>&1 || return 1
  v="$(node -v 2>/dev/null)"; v="${v#v}"
  IFS=. read -r a b _ <<< "$v"
  [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ ]] || return 1
  { [ "$a" -eq 22 ] && [ "$b" -ge 19 ]; } || { [ "$a" -eq 24 ] && [ "$b" -ge 11 ]; } || [ "$a" -ge 26 ]
}

# ------------------------------------------------------------------ pacotes do Ubuntu
passo "Java 21 (para o Ghidra e o JADX) e bibliotecas Python para Word, Excel e PDF"
export DEBIAN_FRONTEND=noninteractive
apt_atualizado=0
for pkg in openjdk-21-jdk-headless python3-docx python3-openpyxl python3-pypdf python3-reportlab; do
  if dpkg -s "$pkg" >/dev/null 2>&1; then ok "$pkg (ja estava)"; continue; fi
  if [ $apt_atualizado -eq 0 ]; then apt-get update -y >/dev/null 2>&1 || true; apt_atualizado=1; fi
  if apt-get install -y --no-install-recommends "$pkg" >/dev/null 2>&1; then ok "$pkg"; else falhou "$pkg"; fi
done

# ------------------------------------------------------------------ Node.js
passo "Node.js $NODE_MAJOR (oficial, conferido por SHA-256)"
if node_serve && [ "$(node -v | cut -d. -f1)" = "v$NODE_MAJOR" ]; then
  ok "node $(node -v) (ja estava)"
else
  tmp="$(mktemp -d)"
  base="$NODE_URL/latest-v$NODE_MAJOR.x"
  if curl -fsSL --retry 3 -o "$tmp/SHASUMS256.txt" "$base/SHASUMS256.txt"; then
    linha="$(grep -E '^[0-9a-f]{64}  node-v[0-9]+\.[0-9]+\.[0-9]+-linux-x64\.tar\.xz$' "$tmp/SHASUMS256.txt" | head -n1)"
    soma="${linha%%  *}"
    arq="${linha##*  }"
    if [ -n "$linha" ] && curl -fsSL --retry 3 -o "$tmp/$arq" "$base/$arq" \
       && printf '%s  %s\n' "$soma" "$tmp/$arq" | sha256sum -c --status; then
      dir="$OPTDIR/${arq%.tar.xz}"
      rm -rf "$dir"
      if tar -xJf "$tmp/$arq" -C "$OPTDIR" --no-same-owner; then
        ln -sfn "$dir" "$OPTDIR/node"
        for b in node npm npx corepack; do liga_bin "$OPTDIR/node/bin/$b"; done
        hash -r
        if node_serve; then ok "node $(node -v)"; else falhou "node"; fi
      else
        falhou "node (nao consegui extrair $arq)"
      fi
    else
      falhou "node (download ou SHA-256 nao conferiu)"
    fi
  else
    falhou "node (sem acesso a $base)"
  fi
  rm -rf "$tmp"
fi

npm_global() {   # instala pacotes npm na pasta dos extras (fica de pe mesmo trocando a versao do Node)
  npm install -g --prefix "$NPMDIR" --no-fund --no-audit --loglevel=error "$@"
}
versao_npm() { jq -r '.version // empty' "$NPMDIR/lib/node_modules/$1/package.json" 2>/dev/null; }

# ------------------------------------------------------------------ REA
passo "REA $REA_VERSAO (engenharia reversa: comando rea, servidor MCP e skill)"
rea_ok=0
if ! node_serve || ! command -v npm >/dev/null 2>&1; then
  falhou "rea (precisa do Node.js)"
elif [ "$(versao_npm rea-agents)" = "$REA_VERSAO" ]; then
  liga_bin "$NPMDIR/bin/rea"; ok "rea $REA_VERSAO (ja estava)"; rea_ok=1
elif npm_global "rea-agents@$REA_VERSAO" && [ "$(versao_npm rea-agents)" = "$REA_VERSAO" ]; then
  liga_bin "$NPMDIR/bin/rea"; ok "rea $REA_VERSAO"; rea_ok=1
else
  falhou "rea"
fi

# ------------------------------------------------------------------ Pyright
passo "Pyright (o agente ve os erros de Python logo depois de editar)"
if [ -n "$(versao_npm pyright)" ]; then
  ok "pyright $(versao_npm pyright) (ja estava)"
elif node_serve && npm_global pyright && [ -n "$(versao_npm pyright)" ]; then
  ok "pyright $(versao_npm pyright)"
else
  falhou "pyright"
fi
liga_bin "$NPMDIR/bin/pyright"
liga_bin "$NPMDIR/bin/pyright-langserver"

# ------------------------------------------------------------------ Ghidra e JADX (vindos do Windows)
passo "Ghidra e JADX (copiados do seu C:\\tools)"
if [ -f "$STAGING/ghidra.tar" ]; then
  nome="$(tar -tf "$STAGING/ghidra.tar" 2>/dev/null | head -n1 | cut -d/ -f1)"
  if [[ "$nome" =~ ^ghidra_[0-9A-Za-z._-]+$ ]]; then
    mkdir -p "$EXTRAS/ghidra"
    rm -rf "${EXTRAS:?}/ghidra/$nome"
    if tar -xf "$STAGING/ghidra.tar" -C "$EXTRAS/ghidra" --no-same-owner; then
      g="$EXTRAS/ghidra/$nome"
      chmod -R u=rwX,go=rX "$g"
      # o tar feito no Windows nao guarda o "pode executar" dos programas do Linux
      find "$g" -type f \( -name ghidraRun -o -name '*.sh' -o -path '*/support/*' -o -path '*/server/*' \
        -o -path '*/os/linux_x86_64/*' \) -exec chmod 755 {} +
      ln -sfn "$g" "$EXTRAS/ghidra/atual"
      ok "$nome"
    else
      falhou "ghidra (nao consegui extrair)"
    fi
  else
    falhou "ghidra (arquivo inesperado)"
  fi
elif [ -e "$EXTRAS/ghidra/atual" ]; then
  ok "$(basename "$(readlink -f "$EXTRAS/ghidra/atual")") (ja estava)"
else
  nota "sem Ghidra no C:\\tools: o REA analisa JavaScript, Electron e .NET mesmo assim"
fi
jadx_novo="$(find "$STAGING" -maxdepth 1 -name 'jadx*.jar' 2>/dev/null | sort | tail -n1)"
if [ -n "$jadx_novo" ]; then
  if install -D -m 644 "$jadx_novo" "$EXTRAS/jadx/$(basename "$jadx_novo")"; then ok "$(basename "$jadx_novo")"; else falhou "jadx"; fi
elif [ -n "$(find "$EXTRAS/jadx" -maxdepth 1 -name 'jadx*.jar' 2>/dev/null | head -n1)" ]; then
  ok "jadx (ja estava)"
else
  nota "sem JADX no C:\\tools (so faz falta para apps Android)"
fi

# ------------------------------------------------------------------ ambiente do REA
passo "Configuracao do REA"
{
  echo "# Agente HX - ambiente do REA (gerado por instalar-extras.sh; o kit carrega este arquivo)"
  echo "REA_MCP_INPUT_SCHEMA_PROFILE=compact"
  echo "REA_MCP_OUTPUT_SCHEMA_PROFILE=off"
  jh="$(find /usr/lib/jvm -maxdepth 1 -name 'java-21-openjdk-*' 2>/dev/null | sort | head -n1)"
  [ -n "$jh" ] && echo "JAVA_HOME=$jh"
  [ -e "$EXTRAS/ghidra/atual" ] && echo "GHIDRA_INSTALL_DIR=$(readlink -f "$EXTRAS/ghidra/atual")"
  jj="$(find "$EXTRAS/jadx" -maxdepth 1 -name 'jadx*.jar' 2>/dev/null | sort | tail -n1)"
  [ -n "$jj" ] && echo "REA_JADX_MCP_JAR=$jj"
} > "$EXTRAS/rea.env"
sed -n '2,$p' "$EXTRAS/rea.env" | sed 's/^/   /'

# ------------------------------------------------------------------ skills
passo "Skills (REA, Ponytail e seguranca) para o OpenCode e o Claude Code"
SK="$HOME_U/.claude/skills"
install -d -o "$USUARIO" -g "$USUARIO" "$HOME_U/.claude" "$SK"
liga_skill() {   # $1 pasta da skill, $2 nome
  local alvo="$SK/$2"
  if [ ! -f "$1/SKILL.md" ]; then falhou "skill $2"; return; fi
  if [ -e "$alvo" ] && [ ! -L "$alvo" ]; then nota "skill $2: ja existe uma sua com esse nome, deixei a sua"; return; fi
  ln -sfn "$1" "$alvo" && chown -h "$USUARIO:$USUARIO" "$alvo" && ok "skill $2"
}
if [ $rea_ok -eq 1 ]; then
  liga_skill "$NPMDIR/lib/node_modules/rea-agents/skills/reverse-engineer-anything" reverse-engineer-anything
fi
for s in "$KIT"/extras/skills/*/; do
  [ -d "$s" ] && liga_skill "${s%/}" "$(basename "$s")"
done
# O OpenCode tambem le ~/.claude/skills; os atalhos abaixo cobrem as versoes que so olham a pasta dele.
install -d -o "$USUARIO" -g "$USUARIO" "$HOME_U/.config" "$HOME_U/.config/opencode"
for d in skills skill; do
  if [ ! -e "$HOME_U/.config/opencode/$d" ]; then
    ln -s "$SK" "$HOME_U/.config/opencode/$d" && chown -h "$USUARIO:$USUARIO" "$HOME_U/.config/opencode/$d"
  fi
done

# ------------------------------------------------------------------ plugin do Claude Code
passo "Plugin pyright-lsp do Claude Code (marketplace oficial da Anthropic)"
if ! como_usuario 'command -v claude' >/dev/null 2>&1; then
  falhou "plugin pyright-lsp (Claude Code nao encontrado)"
elif como_usuario 'claude plugin list < /dev/null 2>/dev/null' | grep -q 'pyright-lsp@claude-plugins-official'; then
  ok "pyright-lsp (ja estava)"
else
  if ! como_usuario 'claude plugin marketplace list < /dev/null 2>/dev/null' | grep -q 'claude-plugins-official'; then
    como_usuario 'claude plugin marketplace add anthropics/claude-plugins-official < /dev/null' >/dev/null 2>&1 || true
  fi
  if como_usuario 'claude plugin install pyright-lsp@claude-plugins-official < /dev/null' >/dev/null 2>&1; then
    ok "pyright-lsp"
  else
    falhou "plugin pyright-lsp"
  fi
fi

# ------------------------------------------------------------------ fim
chmod -R go=rX "$EXTRAS" 2>/dev/null || true
echo
if [ ${#FALTOU[@]} -eq 0 ]; then
  rm -f "$EXTRAS/AVISOS.txt"
  echo "Pronto: plugins, MCPs e ferramentas instalados."
else
  printf '%s\n' "${FALTOU[@]}" > "$EXTRAS/AVISOS.txt"
  echo "Faltou: ${FALTOU[*]}"
fi
if node_serve && [ $rea_ok -eq 1 ]; then
  [ -n "$CARIMBO" ] && printf '%s\n' "$CARIMBO" > "$EXTRAS/.versao"
  exit 0
fi
rm -f "$EXTRAS/.versao"
exit 1
