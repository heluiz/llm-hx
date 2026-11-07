#!/usr/bin/env bash
# Agente HX - cria um projeto novo a partir do modelo.
#   agente-novo.sh <nome> [--exemplo]
# --exemplo: ja vem com SPEC/PLAN de uma calculadora de risco/retorno (bom para testar o loop).
set -euo pipefail
AQUI="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"   # resolve o atalho de /usr/local/bin
# shellcheck source=../lib/comum.sh
. "$AQUI/../lib/comum.sh"

NOME="${1:-}"
EXEMPLO=0
[ "${2:-}" = "--exemplo" ] && EXEMPLO=1
if ! nome_valido "$NOME"; then
  erro "nome invalido: '$NOME' (use minusculas, numeros e hifen; ex.: meu-app)"
  exit 2
fi
DEST="$PROJETOS_DIR/$NOME"
if [ -e "$DEST" ]; then erro "ja existe um projeto com esse nome: $DEST"; exit 2; fi

MODELO="$AGENTE_HX_DIR/modelo-projeto"
[ $EXEMPLO -eq 1 ] && MODELO="$AGENTE_HX_DIR/exemplo-projeto"
[ -d "$MODELO" ] || { erro "modelo nao encontrado: $MODELO"; exit 2; }

mkdir -p "$PROJETOS_DIR"
cp -r "$MODELO" "$DEST"
[ -f "$DEST/gitignore" ] && mv "$DEST/gitignore" "$DEST/.gitignore"
# o modelo de base (AGENTS.md, CLAUDE.md, verificar.sh) vale para o exemplo tambem
for f in AGENTS.md CLAUDE.md verificar.sh .gitignore; do
  if [ ! -e "$DEST/$f" ] && [ -e "$AGENTE_HX_DIR/modelo-projeto/${f#.}" ]; then cp "$AGENTE_HX_DIR/modelo-projeto/${f#.}" "$DEST/$f"; fi
done
chmod +x "$DEST/verificar.sh" 2>/dev/null || true

cd "$DEST"
git init -q -b main
git add -A
git -c user.name="Agente HX" -c user.email="agente@local" -c commit.gpgsign=false commit -qm "projeto criado a partir do modelo"

info "projeto criado: $DEST"
if [ $EXEMPLO -eq 1 ]; then
  echo "Exemplo pronto: pode rodar o agente direto (3-RODAR-AGENTE)."
else
  echo "Agora edite SPEC.md (o que construir) e PLAN.md (lista de tarefas) antes de rodar o agente."
fi
