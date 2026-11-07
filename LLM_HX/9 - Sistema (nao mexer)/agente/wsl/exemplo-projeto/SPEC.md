# Especificação — calculadora de risco/retorno (projeto de EXEMPLO)

> Projeto pequeno para testar o agente de ponta a ponta. Leva de 30 minutos a algumas horas,
> dependendo do modelo. Quando ele terminar, você sabe que a montagem toda funciona.

## Objetivo
Um pacote Python chamado `calc` que, a partir do alvo e do stop em ticks, calcula quanto
cada um vale em dinheiro, a razão risco/retorno e a taxa de acerto mínima para empatar.

## O que precisa ter
- `calc/__init__.py` (pode ser vazio) e `calc/risco.py` com as funções abaixo.
- `valor_em_dinheiro(ticks, valor_tick)`: `ticks * valor_tick`, arredondado em 2 casas.
- `razao_risco_retorno(alvo_ticks, stop_ticks)`: `alvo / stop`, arredondado em 2 casas.
  Se alvo ou stop for menor ou igual a zero, levanta `ValueError`.
- `acerto_minimo(alvo_ticks, stop_ticks, valor_tick, custo_por_trade=0.0)`: porcentagem
  (0 a 100) com 1 casa decimal, pela fórmula
  `(stop_em_dinheiro + custo_por_trade) / (alvo_em_dinheiro + stop_em_dinheiro) * 100`.
- Linha de comando: `python3 -m calc --alvo 40 --stop 20 --valor-tick 5 --custo 4`
  (arquivo `calc/__main__.py`, usando `argparse`).

## O que NÃO fazer
- Nada fora da biblioteca padrão do Python.
- Nada de interface gráfica nem de arquivos de configuração.

## Exemplos
- `valor_em_dinheiro(40, 5)` → `200.0`
- `razao_risco_retorno(40, 20)` → `2.0` · `razao_risco_retorno(30, 40)` → `0.75`
- `acerto_minimo(40, 20, 5)` → `33.3` · `acerto_minimo(40, 20, 5, 4)` → `34.7`
- `python3 -m calc --alvo 40 --stop 20 --valor-tick 5 --custo 4` imprime exatamente:
```
Alvo: 40 ticks = $200.00
Stop: 20 ticks = $100.00
Risco/retorno: 2.00
Acerto minimo: 34.7%
```

## Como saber que está pronto
- `bash verificar.sh` passa, com testes para cada função e para a linha de comando.
- `README.md` explica o uso com o exemplo acima.
