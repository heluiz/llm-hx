@echo off
REM Diagnostico somente leitura do Voicebox (criado pelo Claude)
set OUT=C:\LLM\Imagem\Ferramentas_HX\voz\voz_diagnostico.txt
echo ===== DATA %date% %time% > "%OUT%"
echo ===== VARIAVEIS DE AMBIENTE DO USUARIO >> "%OUT%"
reg query HKCU\Environment >> "%OUT%" 2>&1
echo ===== VARIAVEIS DE SISTEMA (HF/VOICEBOX) >> "%OUT%"
set | findstr /i "VOICEBOX HF_ HUGGING" >> "%OUT%" 2>&1
echo ===== C:\LLM\Voz (arvore) >> "%OUT%"
dir /s /-c "C:\LLM\Voz" >> "%OUT%" 2>&1
echo ===== CACHE HF DO USUARIO >> "%OUT%"
dir /-c "C:\Users\heluiz\.cache\huggingface\hub" >> "%OUT%" 2>&1
echo ===== APPDATA VOICEBOX >> "%OUT%"
dir /-c "C:\Users\heluiz\AppData\Roaming\sh.voicebox.app" >> "%OUT%" 2>&1
dir /s /-c "C:\Users\heluiz\AppData\Roaming\sh.voicebox.app\logs" >> "%OUT%" 2>&1
echo ===== PROCESSOS VOICEBOX >> "%OUT%"
tasklist | findstr /i "voicebox" >> "%OUT%" 2>&1
echo ===== GPU >> "%OUT%"
nvidia-smi --query-gpu=memory.used,memory.total --format=csv >> "%OUT%" 2>&1
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv >> "%OUT%" 2>&1
echo ===== FIM >> "%OUT%"
