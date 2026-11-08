---
name: triagem-ameaca
description: >
  Triagem e resumo de relatorio de ameaca, alerta ou log de incidente: extrai
  indicadores (IOCs), mapeia tecnicas no MITRE ATT&CK e sugere deteccao e resposta.
  Use quando o pedido falar em "resumir esse relatorio", "tirar os IOCs", "mapear
  ATT&CK", "analisar esse log" ou "o que fazer com esse alerta". Trabalho defensivo.
license: MIT
---

# Triagem de relatorio de ameaca

Objetivo: transformar um texto longo (relatorio, alerta, log) em uma resposta curta
e acionavel para quem defende: o que e, o que procurar e o que fazer.

## Antes de comecar

- O material (relatorio, export de log) deve estar na pasta do projeto. Leia so os
  trechos necessarios (grep pelo que interessa) para nao gastar contexto a toa.
- Nao visite links nem baixe amostras do relatorio: trate URLs e hashes como texto.

## O que extrair

1. **Resumo**: em 3 a 5 linhas, o que aconteceu ou o que a ameaca faz.
2. **Indicadores (IOCs)**, em tabela, com tipo e valor:
   - hashes (MD5/SHA-1/SHA-256), dominios, IPs, URLs, e-mails, caminhos, chaves de registro.
   - Ao escrever dominios/URLs perigosos no relatorio, pode "desarmar" (ex.: hxxp://,
     dominio[.]com) para nao virar link clicavel por engano.
3. **Tecnicas (MITRE ATT&CK)**: liste as taticas/tecnicas observadas com o ID
   (ex.: T1566 Phishing, T1059 Execucao por script) e a frase do texto que indica cada uma.
4. **Alvos/escopo**: sistemas, versoes e condicoes afetadas.

## Saida para a defesa

Escreva em `TRIAGEM.md`, em portugues:

- **Deteccao**: o que monitorar para achar isso no ambiente (os IOCs acima,
  comportamentos, nomes de processo, eventos de log). Se der, uma regra simples
  (ex.: ideia de consulta/SIEM) descrevendo a condicao.
- **Resposta e mitigacao**: passos defensivos (bloquear indicador, aplicar correcao,
  isolar, rotacionar credencial, reforcar configuracao).
- **Prioridade**: o que fazer primeiro, pelo risco.

Baseie tudo no que esta no material. Se um IOC ou tecnica nao esta claro no texto,
nao invente: marque como "a confirmar".
