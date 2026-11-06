# LLM_HX — IA local no Predator

> **Repositório privado.** Guarda só os atalhos, scripts, workflows e guias da IA local. Ficam de fora os modelos, a instalação do ComfyUI, as fotos de referência e os resultados, as amostras de voz e os logs.

Configuração da IA que roda no notebook Predator (RTX 4070 Laptop, 8 GB): modelos de texto pelo llama.cpp, geração de imagem pelo ComfyUI (Z-Image Turbo) e voz pelo Voicebox. Os três usam a mesma placa de vídeo, por isso só um roda de cada vez.

## Estrutura

| Pasta | Onde fica no PC | O que tem |
|---|---|---|
| `LLM_HX/` | Área de Trabalho\LLM_HX | Atalhos por área (Texto, Imagem, Voz), workflows do ComfyUI, `COMO-USAR.txt` e os scripts de sistema (`setup.ps1`, `run-model.ps1`, `tune.ps1`) |
| `C-LLM/Imagem/Ferramentas_HX/` | C:\LLM\Imagem\Ferramentas_HX | Diagnóstico, reinício e testes do ComfyUI e do Voicebox |
| `C-LLM/tuned/` | C:\LLM\tuned | Parâmetros encontrados pelo `tune.ps1` para cada modelo |

## Restaurar

Copie cada pasta de volta para o lugar indicado na tabela. Os modelos e o ComfyUI precisam ser baixados de novo; o `LLM_HX/1 - Texto (LLMs)/INSTALAR-ATUALIZAR.bat` instala ou atualiza o llama.cpp e os modelos de texto.
