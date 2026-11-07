# Plano de tarefas

O loop pega sempre a PRIMEIRA linha `- [ ]`, de cima para baixo.
- `- [ ]` pendente · `- [x]` feita (o loop marca) · `- [!]` bloqueada (o loop marca; para tentar de novo, volte para `- [ ]`)

## Tarefas

- [ ] T01: criar `calc/__init__.py` (vazio) e `calc/risco.py` com `valor_em_dinheiro(ticks, valor_tick)`; testes em `tests/test_risco.py` (ex.: 40 ticks a 5 = 200.0)
- [ ] T02: em `calc/risco.py`, criar `razao_risco_retorno(alvo_ticks, stop_ticks)` conforme a SPEC (2 casas; `ValueError` se algum valor for menor ou igual a zero); testes em `tests/test_risco.py`
- [ ] T03: em `calc/risco.py`, criar `acerto_minimo(alvo_ticks, stop_ticks, valor_tick, custo_por_trade=0.0)` conforme a fórmula da SPEC; testes com os dois exemplos da SPEC
- [ ] T04: criar `calc/__main__.py` com a linha de comando da SPEC (saída exatamente igual ao exemplo); teste em `tests/test_cli.py` rodando `python3 -m calc` com `subprocess`
- [ ] T05: criar `README.md` explicando o que é e como usar, com o exemplo de linha de comando e a saída real
