# LLM_HX — IA local no Predator

> **Repositório privado.** Guarda só os atalhos, scripts, workflows e guias da IA local. Ficam de fora os modelos, a instalação do ComfyUI, a distro do agente, as fotos de referência e os resultados, as amostras de voz e os logs.

Configuração da IA que roda no notebook Predator (RTX 4070 Laptop, 8 GB): modelos de texto pelo llama.cpp, geração de imagem pelo ComfyUI (Z-Image Turbo), voz pelo Voicebox e um agente de programação local (OpenCode ou Claude Code falando só com o llama.cpp). Todos usam a mesma placa de vídeo, por isso só um roda de cada vez.

## Estrutura

| Pasta | Onde fica no PC | O que tem |
|---|---|---|
| `LLM_HX/` | Área de Trabalho\LLM_HX | Atalhos por área (Texto, Imagem, Voz, Agente), workflows do ComfyUI, os guias `COMO-USAR.txt` e os scripts de sistema (`setup.ps1`, `run-model.ps1`, `tune.ps1` e a pasta `agente\`) |
| `C-LLM/Imagem/Ferramentas_HX/` | C:\LLM\Imagem\Ferramentas_HX | Diagnóstico, reinício e testes do ComfyUI e do Voicebox |
| `C-LLM/tuned/` | C:\LLM\tuned | Parâmetros encontrados pelo `tune.ps1` para cada modelo |

## Agente local

Fica em `LLM_HX/4 - Agente (tarefas longas)`. Roda numa distro WSL separada (AgenteHX, Ubuntu 24.04), sem acesso ao disco C:, sem abrir programas do Windows e sem sudo. Tem dois modos:

- **Chat** (`4-CONVERSAR-COM-O-AGENTE`): você digita os pedidos e acompanha cada passo.
- **Sozinho** (`3-RODAR-AGENTE`): um loop de rodadas, sempre com contexto limpo, pega a próxima tarefa do `PLAN.md`, confere com o `verificar.sh` e faz commit. Aguenta horas ou dias.

Os scripts do Windows e o `config.json` (pausa do pregão, modelo e agente padrão) ficam em `LLM_HX/9 - Sistema (nao mexer)/agente/`. A subpasta `wsl/` vai para `/opt/agente-hx` dentro da distro; os atalhos levam a versão nova sozinhos quando o kit muda. O guia completo é o `COMO-USAR.txt` da pasta do agente.

O modelo indicado para o agente é o Qwen3.6-35B-A3B oficial, que o `INSTALAR-ATUALIZAR` baixa; as versões abliterated erram mais nas chamadas de ferramenta. O molde de conversa original dos Qwen 3.5 em diante recusa uma segunda mensagem de sistema, e o OpenCode e o Claude Code mandam essa mensagem: cada pedido voltava com erro 500 e os agentes repetiam até desistir. Por isso o `1-LIGAR-SERVIDOR` liga o llama-server com um molde corrigido (`agente/templates/`), que põe essa mensagem no lugar em que ela chegou. Para um modelo novo, ele confere o molde no primeiro uso e, se precisar, corrige e religa uma vez.

Plugins e MCPs (`wsl/extras/`, instalados sozinhos na distro): REA para engenharia reversa (comando `rea` e skill), com o Ghidra e o JADX copiados do `C:\tools` e o Java 21; as skills do Ponytail (licença MIT); o Pyright, com o plugin `pyright-lsp` no Claude Code; e bibliotecas Python para Word, Excel e PDF. O Node.js e os pacotes npm são baixados na instalação e não ficam neste repositório.

O servidor MCP do REA fica desligado: ele anuncia 207 ferramentas, uns 60 mil tokens mesmo com os esquemas compactos, quase todo o contexto de 64 mil do modelo local. Com ele ligado, cada passo do agente vinha seguido de um pedido extra de cerca de um minuto, e o agente quase não avançava. Para ligar mesmo assim, use `AGENTE_HX_REA_MCP=1` (só faz sentido com um contexto bem maior).

## Restaurar

Copie cada pasta de volta para o lugar indicado na tabela. Os modelos e o ComfyUI precisam ser baixados de novo; o `LLM_HX/1 - Texto (LLMs)/INSTALAR-ATUALIZAR.bat` instala ou atualiza o llama.cpp e os modelos de texto. A distro do agente (C:\LLM\Agente) não fica aqui: o `0-INSTALAR-AGENTE.bat` cria uma nova.

Os projetos do agente ficam dentro da distro (`\\wsl.localhost\AgenteHX\home\agente\projetos`) e não entram neste backup. Cada projeto já tem o próprio git, então dá para guardar um projeto importante num repositório separado.
