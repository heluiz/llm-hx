@echo off
REM Diagnostico somente leitura do ambiente ComfyUI (criado pelo Claude)
set OUT=C:\LLM\Imagem\Ferramentas_HX\diagnostico.txt
cd /d C:\LLM\Imagem\ComfyUI_windows_portable
echo ===== DATA %date% %time% > "%OUT%"
echo ===== NVIDIA-SMI >> "%OUT%"
nvidia-smi >> "%OUT%" 2>&1
echo ===== PROCESSOS GPU >> "%OUT%"
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv >> "%OUT%" 2>&1
echo ===== PYTHON / TORCH >> "%OUT%"
python_embeded\python.exe -c "import sys,torch;print(sys.version);print('torch',torch.__version__,'cuda',torch.version.cuda,'avail',torch.cuda.is_available());print(torch.cuda.get_device_name(0));f,t=torch.cuda.mem_get_info();print('vram livre GB',round(f/1e9,2),'total GB',round(t/1e9,2))" >> "%OUT%" 2>&1
echo ===== PORTA 8188 >> "%OUT%"
netstat -ano | findstr ":8188" >> "%OUT%" 2>&1
echo ===== SYSTEM_STATS >> "%OUT%"
curl -s -m 5 http://127.0.0.1:8188/system_stats >> "%OUT%" 2>&1
echo. >> "%OUT%"
echo ===== PROCESSOS python / llama >> "%OUT%"
tasklist /fi "imagename eq python.exe" >> "%OUT%" 2>&1
tasklist | findstr /i "llama ollama lms" >> "%OUT%" 2>&1
echo ===== DISCO C >> "%OUT%"
powershell -NoProfile -Command "Get-PSDrive C | Format-List Used,Free" >> "%OUT%" 2>&1
echo ===== RAM >> "%OUT%"
powershell -NoProfile -Command "Get-CimInstance Win32_OperatingSystem | Format-List TotalVisibleMemorySize,FreePhysicalMemory" >> "%OUT%" 2>&1
echo ===== FIM >> "%OUT%"
