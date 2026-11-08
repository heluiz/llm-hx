---
name: revisao-seguranca
description: >
  Revisao de seguranca de codigo: encontra vulnerabilidades, explica o risco e
  mostra a correcao. Use quando o pedido falar em "revisar seguranca", "procurar
  falhas", "tem vulnerabilidade nesse codigo", "SAST", "OWASP" ou antes de
  publicar um codigo que lida com entrada de usuario, autenticacao ou dados
  sensiveis. Foco em achar e corrigir, nao em explorar.
license: MIT
---

# Revisao de seguranca de codigo

Objetivo: achar falhas no codigo, explicar por que sao perigosas e entregar a
correcao. Revisao defensiva: o resultado e um codigo mais seguro, nao um exploit.

## Como revisar

1. Entenda o que o codigo faz e por onde entra dado de fora (parametros, formularios,
   arquivos, rede, variaveis de ambiente). Esses sao os pontos de risco.
2. Siga o dado nao confiavel ate onde ele e usado (consulta, comando, caminho de
   arquivo, HTML, desserializacao). Falha aparece quando o dado chega sem validacao.
3. Procure as categorias conhecidas (OWASP Top 10 / CWE):
   - Injecao: SQL, comando de SO, LDAP, template. (CWE-89, CWE-78)
   - XSS e saida sem escape em HTML/JS. (CWE-79)
   - Autenticacao e sessao fracas, senha em texto, token previsivel. (CWE-287)
   - Controle de acesso quebrado: funcao sem checar permissao. (CWE-862)
   - Segredo no codigo: chave, senha, token commitados. (CWE-798)
   - Caminho de arquivo controlado pelo usuario (path traversal). (CWE-22)
   - SSRF: requisicao para URL que o usuario controla. (CWE-918)
   - Desserializacao de dado nao confiavel. (CWE-502)
   - Cripto mal usada: algoritmo fraco, IV fixo, sem sal, comparacao vazavel. (CWE-327)
   - Falta de limite: tamanho, taxa, recursao (negacao de servico). (CWE-400)
4. Use o Pyright (Python) e os erros do compilador para achar o que e erro simples;
   sobra tempo para a analise de seguranca de verdade.

## Relatorio

Escreva em `REVISAO-SEGURANCA.md`, em portugues. Para cada achado:

- **Onde**: arquivo e linha.
- **Categoria**: o CWE/OWASP.
- **Gravidade**: alta, media ou baixa, e por que.
- **Por que da problema**: o caminho do dado nao confiavel ate o ponto perigoso.
- **Correcao**: o trecho corrigido (consulta parametrizada, escape na saida,
  validacao, segredo fora do codigo, algoritmo forte). Pequena e so no necessario.

Ordene por gravidade. Nao invente falha para encher lista: se o codigo esta ok
num ponto, nao cite. Se faltou contexto para julgar, diga o que faltou.
