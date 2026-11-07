#!/usr/bin/env bash
# Agente HX - instalacao dentro da distro WSL do agente (rodado como root pelo 0-INSTALAR-AGENTE).
#   instalar.sh [--usuario agente] [--opencode 1.19.5] [--claude 2.1.319] [--so-scripts]
# --so-scripts: so atualiza os scripts do kit (nao mexe em pacotes nem nas ferramentas).
set -euo pipefail
ORIGEM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USUARIO="agente"
OC_VERSAO="1.19.5"
CC_VERSAO="2.1.319"
SO_SCRIPTS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --usuario) USUARIO="$2"; shift 2 ;;
    --opencode) OC_VERSAO="$2"; shift 2 ;;
    --claude) CC_VERSAO="$2"; shift 2 ;;
    --so-scripts) SO_SCRIPTS=1; shift ;;
    *) echo "opcao desconhecida: $1" >&2; exit 2 ;;
  esac
done
[ "$(id -u)" -eq 0 ] || { echo "rode como root (wsl -u root)" >&2; exit 2; }
[[ "$USUARIO" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || { echo "usuario invalido: $USUARIO" >&2; exit 2; }
passo() { printf '\n>>> %s\n' "$*"; }

if [ $SO_SCRIPTS -eq 0 ]; then
  passo "Pacotes do Ubuntu (git, python, pytest, jq, ripgrep...)"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get -y -o Dpkg::Options::=--force-confold upgrade
  apt-get install -y --no-install-recommends \
    ca-certificates curl git jq python3 python3-pip python3-venv python3-pytest \
    ripgrep unzip xz-utils procps less nano util-linux tzdata build-essential
  ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
  echo "America/Sao_Paulo" > /etc/timezone
fi

passo "Usuario do agente: $USUARIO (sem sudo)"
if ! id -u "$USUARIO" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$USUARIO"
fi
install -d -o "$USUARIO" -g "$USUARIO" "/home/$USUARIO/projetos"

passo "Scripts do kit em /opt/agente-hx (somente leitura para o agente)"
if [ -d /opt/agente-hx ]; then
  rm -rf /opt/agente-hx.anterior
  mv /opt/agente-hx /opt/agente-hx.anterior
fi
mkdir -p /opt/agente-hx
cp -r "$ORIGEM"/. /opt/agente-hx/
chown -R root:root /opt/agente-hx
chmod -R u=rwX,go=rX /opt/agente-hx
chmod 755 /opt/agente-hx/bin/*.sh /opt/agente-hx/instalar.sh
for s in /opt/agente-hx/bin/agente-*.sh; do
  ln -sf "$s" "/usr/local/bin/$(basename "$s" .sh)"
done

cat > /etc/profile.d/agente-hx.sh <<'EOF'
# Agente HX: ferramentas no PATH e sem atualizacao automatica
export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"
export OPENCODE_DISABLE_AUTOUPDATE=1
export DISABLE_AUTOUPDATER=1
EOF

if [ $SO_SCRIPTS -eq 0 ]; then
  passo "git do agente"
  runuser -l "$USUARIO" -c 'git config --global user.name "Agente HX"; git config --global user.email "agente@local"; git config --global init.defaultBranch main'

  passo "OpenCode $OC_VERSAO (versao fixa)"
  runuser -l "$USUARIO" -c "curl -fsSL https://opencode.ai/install | bash -s -- --version $OC_VERSAO"

  passo "Claude Code $CC_VERSAO (versao fixa; vai falar so com o seu llama-server)"
  runuser -l "$USUARIO" -c "curl -fsSL https://claude.ai/install.sh | bash -s $CC_VERSAO"
  install -d -o "$USUARIO" -g "$USUARIO" "/home/$USUARIO/.claude"
  if [ ! -f "/home/$USUARIO/.claude/settings.json" ]; then
    cat > "/home/$USUARIO/.claude/settings.json" <<'EOF'
{
  "env": {
    "DISABLE_AUTOUPDATER": "1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  }
}
EOF
    chown "$USUARIO:$USUARIO" "/home/$USUARIO/.claude/settings.json"
  fi
fi

passo "Isolamento: sem acesso ao disco C: e sem abrir programas do Windows"
cat > /etc/wsl.conf <<EOF
# Agente HX - distro isolada do agente (gerado por instalar.sh)
[automount]
enabled = false
mountFsTab = false

[interop]
enabled = false
appendWindowsPath = false

[user]
default = $USUARIO
EOF

if [ $SO_SCRIPTS -eq 1 ]; then
  passo "Pronto: scripts atualizados (nao precisa reiniciar a distro)."
else
  passo "Pronto. O Windows precisa reiniciar esta distro para o isolamento valer (o instalador faz isso)."
fi
