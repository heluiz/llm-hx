# Rodada {{RODADA}} — você está trabalhando sozinho

Você é um agente de programação rodando sem ninguém olhando, dentro de um loop.
Cada rodada começa do zero: tudo o que se sabe do projeto está nos arquivos desta pasta.

Antes de mexer em qualquer coisa, leia nesta ordem:
1. `AGENTS.md` — regras do projeto
2. `SPEC.md` — o que precisa ser construído
3. `PLAN.md` — a lista de tarefas
4. o final de `PROGRESS.md` — o que já aconteceu nas rodadas anteriores

## Sua tarefa nesta rodada

{{TAREFA}}

(tentativa {{TENTATIVA}} de {{TENTATIVAS}})

{{FALHA_ANTERIOR}}

## Como trabalhar

1. Faça SÓ essa tarefa. Não adiante as próximas.
2. Escreva ou ajuste os testes da tarefa.
3. Rode `bash verificar.sh` e corrija até passar.
4. No fim de `PROGRESS.md`, acrescente um bloco começando com `## Rodada {{RODADA}}` contando o que você fez, o que testou e o que ficou faltando.
5. Se a tarefa ficou pronta e `bash verificar.sh` passou, crie o arquivo `.agente/CONCLUIDA` com o texto da tarefa e escreva `TAREFA_CONCLUIDA` na última linha do seu bloco em `PROGRESS.md`.
6. Se não conseguiu terminar, explique em `PROGRESS.md` o erro, a causa provável e o que a próxima rodada deve tentar. Nesse caso NÃO crie `.agente/CONCLUIDA`.

## Regras

- Não edite `SPEC.md`, `PLAN.md`, `AGENTS.md`, `CLAUDE.md` nem `verificar.sh`: o loop desfaz.
- Não rode git que mude o histórico (commit, reset, checkout, restore, stash, clean, rebase, push). O loop faz os commits. `git status` e `git diff` podem.
- Não faça perguntas: ninguém vai responder. Decida e registre a decisão em `PROGRESS.md`.
- Trabalhe só dentro desta pasta e sem internet.
- Encerre quando a tarefa estiver pronta ou quando não houver mais o que tentar nesta rodada.

## Últimas notas do PROGRESS.md

{{NOTAS}}
