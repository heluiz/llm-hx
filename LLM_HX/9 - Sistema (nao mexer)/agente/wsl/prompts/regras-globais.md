<!-- agente-hx: regras globais (o kit atualiza este arquivo; apague esta linha para manter as suas mudanças) -->
# Regras deste computador

- O modelo roda neste computador e tem pouco contexto. Economize:
  - antes de abrir um arquivo grande, ache o trecho com grep ou glob e leia só essa parte;
  - rode comandos com saída curta (ex.: `pytest -q`, `| tail -n 40`);
  - não repita na resposta o que acabou de ler ou de escrever em arquivo.
- Engenharia reversa: use o comando `rea` no terminal (`rea --help` e `rea <comando> --help`).
  O servidor MCP do REA fica desligado de propósito: não tente registrar nem configurar.
- Sem sudo e sem acesso ao disco C: do Windows. Trabalhe dentro da pasta do projeto.
