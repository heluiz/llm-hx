#!/usr/bin/env bash
# Verificacao do projeto: o loop roda este arquivo depois de cada rodada.
# Tem que terminar com codigo 0 quando esta tudo certo. Adapte ao seu projeto
# (ex.: "npm test", "dotnet test", "cargo test").
set -euo pipefail
cd "$(dirname "$0")"

if compgen -G "tests/test_*.py" > /dev/null || compgen -G "tests/*_test.py" > /dev/null; then
  python3 -m pytest -q
else
  echo "ainda nao ha testes em tests/; conferindo so se o Python compila"
  python3 -m compileall -q -x '(^|/)\.' . > /dev/null
fi
