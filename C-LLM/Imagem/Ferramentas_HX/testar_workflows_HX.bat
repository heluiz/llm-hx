@echo off
REM Executa o teste real dos dois workflows pela API local e grava teste\resultado_teste.json
cd /d C:\LLM\Imagem\ComfyUI_windows_portable
python_embeded\python.exe -s C:\LLM\Imagem\Ferramentas_HX\teste_hx.py > C:\LLM\Imagem\Ferramentas_HX\teste\console_teste.txt 2>&1
