---
name: analise-binario
description: >
  Analise estatica e engenharia reversa de um binario, firmware ou app que
  voce tem direito de analisar (amostra de malware em laboratorio, APK, firmware,
  ou o seu proprio programa compilado). Use quando o pedido falar em "analisar
  binario", "engenharia reversa", "o que esse programa faz", "analisar esse APK"
  ou "analisar essa amostra". Usa o comando rea (REA) com Ghidra e JADX.
license: MIT
---

# Analise de binario (engenharia reversa)

Objetivo: explicar o que um artefato faz, com evidencia, para fins de defesa,
resposta a incidente, estudo ou analise do proprio codigo. So analise alvos que
voce tem autorizacao para analisar. Trabalho de analise e leitura: nao execute a
amostra; se precisar rodar algo, diga isso ao usuario e pare.

## Antes de comecar

- O agente nao enxerga o disco C: do Windows. Peca ao usuario para copiar o alvo
  para a pasta do projeto (8-ABRIR-PROJETOS) e confirme o caminho dentro da pasta.
- Trabalhe sempre sobre uma copia. Nao renomeie nem apague o original.
- Registre em um arquivo `ANALISE.md` na pasta do projeto o que voce for achando.

## Triagem estatica (rapida, sem o REA)

1. Tipo do arquivo: `file alvo` e `ls -l alvo` (tamanho).
2. Texto legivel: `strings -n 6 alvo | head -200` (URLs, caminhos, chaves, mensagens).
3. Hashes para identificar e cruzar depois: `sha256sum alvo`.
4. Empacotado/comprimido? Entropia alta e poucas strings sugerem packer; diga isso.
5. APK: liste o conteudo com `unzip -l alvo.apk` antes de decodificar.

## Analise com o REA

- Veja os comandos: `rea --help` e `rea <comando> --help`.
- Visao geral do artefato: `rea analyze` / `rea inspect`.
- Ler trechos como codigo: `rea decompile` (nativo), JavaScript/Electron e .NET o REA
  faz sem Ghidra; para nativo e Android ele usa o Ghidra e o JADX ja instalados.
- Android: decodifique manifesto e recursos e liste permissoes e componentes.
- Guarde a evidencia (saida do comando, enderecos, trechos) junto de cada afirmacao.

## Relatorio

Escreva no `ANALISE.md`, em portugues, com estas secoes:

- **Identificacao**: nome, tamanho, hash SHA-256, tipo, se esta empacotado.
- **O que faz**: comportamento principal, em poucas linhas.
- **Rede**: dominios, IPs, URLs e portas que aparecem.
- **Persistencia e sistema**: chaves de registro, servicos, tarefas, arquivos criados.
- **APIs/trechos suspeitos**: com o endereco ou a funcao de onde veio a evidencia.
- **Indicadores (IOCs)**: hashes, dominios, IPs, caminhos, em lista.
- **Incerteza**: o que voce nao conseguiu determinar e por que.

Toda afirmacao vem de uma evidencia que voce viu na saida de um comando. Se nao
tem evidencia, diga "nao determinado" em vez de supor.
